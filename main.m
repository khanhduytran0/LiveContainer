#import <Foundation/Foundation.h>
#import "LCAppDelegate.h"
#import "utils.h"

#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <objc/runtime.h>

#include <dlfcn.h>
#include <execinfo.h>
#include <signal.h>
#include <sys/mman.h>

static int (*appMain)(int, char**);

static BOOL _JITNotEnabled() {
    return NO;
}
static void checkJITEnabled_handler(int signum, siginfo_t* siginfo, void* context)
{
    struct __darwin_ucontext *ucontext = (struct __darwin_ucontext *)context;
    ucontext->uc_mcontext->__ss.__pc = (uint64_t)_JITNotEnabled();
}
static BOOL checkJITEnabled() {
    struct sigaction sa, saOld;
    sa.sa_sigaction = checkJITEnabled_handler;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGBUS, &sa, &saOld);

    uint32_t *page = (uint32_t *)mmap(NULL, PAGE_SIZE, PROT_READ | PROT_WRITE, MAP_ANON | MAP_SHARED, -1, 0);
    page[0] = 0xD2800020; // mov x0, #1
    page[1] = 0xD65F03C0; // ret

    mprotect(page, PAGE_SIZE, PROT_READ | PROT_EXEC);
    BOOL(*testJIT)() = (void *)page;
    BOOL result = testJIT();
    munmap(page, PAGE_SIZE);

    sigaction(SIGBUS, &saOld, NULL);
    return result;
}

static BOOL overwriteMainBundle(NSBundle *newBundle) {
    NSString *oldPath = NSBundle.mainBundle.executablePath;
    uint32_t *mainBundleImpl = (uint32_t *)method_getImplementation(class_getClassMethod(NSBundle.class, @selector(mainBundle)));
    for (int i = 0; i < 20; i++) {
        void **_MergedGlobals = (void **)aarch64_emulate_adrp_add(mainBundleImpl[i], mainBundleImpl[i+1], (uint64_t)&mainBundleImpl[i]);
        if (_MergedGlobals) {
            assert(_MergedGlobals[1] == (__bridge void *)NSBundle.mainBundle);
            _MergedGlobals[1] = (__bridge void *)newBundle;
            break;
        }
    }

    return ![NSBundle.mainBundle.executablePath isEqualToString:oldPath];
}

static void overwriteExecPath() {
    // Silly workaround: we have set our executable name 100 characters long, now just overwrite its path
    char *path = (char *)_dyld_get_image_name(0);
    const char *newPath = *_CFGetProcessPath();
    size_t maxLen = strlen(path);
    size_t newLen = strlen(newPath);
    // Check if it's long enough...
    assert(maxLen >= newLen);

    // Make it RW and overwrite now
    builtin_vm_protect(mach_task_self(), (mach_vm_address_t)path, maxLen, false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    bzero(path, maxLen);
    strncpy(path, newPath, newLen);
    // Don't change back to RO to avoid any issues related to memory access
}

static void *getAppEntryPoint(void *handle, uint32_t imageIndex) {
    uint32_t entryoff = 0;
    const struct mach_header_64 *header = (struct mach_header_64 *)_dyld_get_image_header(imageIndex);
    uint8_t *imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
    struct load_command *command = (struct load_command *)imageHeaderPtr;
    for(int i = 0; i < header->ncmds > 0; ++i) {
        if(command->cmd == LC_MAIN) {
            struct entry_point_command ucmd = *(struct entry_point_command *)imageHeaderPtr;
            entryoff = ucmd.entryoff;
            break;
        }
        imageHeaderPtr += command->cmdsize;
        command = (struct load_command *)imageHeaderPtr;
    }
    assert(entryoff > 0);
    return (void *)_dyld_get_image_header(imageIndex) + entryoff;
}

static NSString* invokeAppMain(NSString *selectedApp, int argc, char *argv[]) {
    NSString *appError = nil;
    // First of all, let's check if we have JIT
    if (!checkJITEnabled()) {
        appError = @"JIT was not enabled";
        return appError;
    }

    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"selected"];

    NSString *docPath = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask]
        .lastObject.path;
    NSString *bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", docPath, selectedApp];
    NSBundle *appBundle = [[NSBundle alloc] initWithPath:bundlePath];
    NSError *error;

    // Bypass library validation so we can load arbitrary binaries
    init_bypassDyldLibValidation();

    // Overwrite @executable_path
    const char **path = _CFGetProcessPath();
    const char *oldPath = *path;
    *path = appBundle.executablePath.UTF8String;
    overwriteExecPath();

    // Preload executable to bypass RT_NOLOAD
    uint32_t appIndex = _dyld_image_count();
    void *appHandle = dlopen(appBundle.executablePath.UTF8String, RTLD_LAZY|RTLD_LOCAL|RTLD_FIRST);
    const char *dlerr = dlerror();
    if (!appHandle || (uint64_t)appHandle > 0xf00000000000 || dlerr) {
        if (dlerr) {
            appError = @(dlerr);
        } else {
            appError = @"dlopen: an unknown error occurred";
        }
        NSLog(@"[LCBootstrap] %@", appError);
        *path = oldPath;
        return appError;
    }

    // Find main()
    appMain = getAppEntryPoint(appHandle, appIndex);
    if (!appMain) {
        appError = @"Could not find the main entry point";
        NSLog(@"[LCBootstrap] %@", appError);
        *path = oldPath;
        return appError;
    }

    if (![appBundle loadAndReturnError:&error]) {
        appError = error.localizedDescription;
        NSLog(@"[LCBootstrap] loading bundle failed: %@", error);
        *path = oldPath;
        return appError;
    }
    NSLog(@"[LCBootstrap] loaded bundle");

    if (!overwriteMainBundle(appBundle)) {
        appError = @"Failed to overwrite main bundle";
        *path = oldPath;
        return appError;
    }

    // Overwrite executable info
    NSMutableArray<NSString *> *objcArgv = NSProcessInfo.processInfo.arguments.mutableCopy;
    objcArgv[0] = appBundle.executablePath;
    [NSProcessInfo.processInfo performSelector:@selector(setArguments:) withObject:objcArgv];
    NSProcessInfo.processInfo.processName = appBundle.infoDictionary[@"CFBundleExecutable"];
    *_CFGetProgname() = NSProcessInfo.processInfo.processName.UTF8String;

    // Go!
    NSLog(@"[LCBootstrap] jumping to main %p", appMain);
    argv[0] = (char *)NSBundle.mainBundle.executablePath.UTF8String;
    appMain(argc, argv);

    return nil;
}

int LiveContainerMain(int argc, char *argv[]) {
    NSString *appError = nil;
    NSString *selectedApp = [NSUserDefaults.standardUserDefaults stringForKey:@"selected"];
    if (selectedApp) {
        appError = invokeAppMain(selectedApp, argc, argv);
        // don't return, let invokeAppMain takeover or continue to LiveContainerUI
    }

    if (appError) {
        [NSUserDefaults.standardUserDefaults setObject:appError forKey:@"error"];
    }

    dlopen("@executable_path/Frameworks/LiveContainerUI.dylib", RTLD_LAZY);
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, @"LCAppDelegate");
    }
}

// fake main() used for dlsym(RTLD_DEFAULT, main)
int main(int argc, char *argv[]) {
    assert(appMain != NULL);
    return appMain(argc, argv);
}
