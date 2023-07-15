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
    // FIXME: test this on iOS 15+
    // We cannot overwrite the buffer directly due to the new path being longer, we'll have to find the address and overwrite it
    const char *path = _dyld_get_image_name(0);
    uint64_t *refAddr = (uint64_t *)path;
    char tmp[PATH_MAX];
    uint32_t tmpLen = PATH_MAX;
    _NSGetExecutablePath(tmp, &tmpLen);
    while (true) {
        while (*refAddr != (uint64_t)path) {
            ++refAddr;
        }
        *(const char **)refAddr = *_CFGetProcessPath();
        _NSGetExecutablePath(tmp, &tmpLen);
        if (strncmp(tmp, path, tmpLen)) {
            // doesn't match, restore
            *(const char **)refAddr = path;
        } else {
            break;
        }
    }
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
    return dlsym(handle, "_mh_execute_header") + entryoff;
}

static int invokeAppMain(NSString *selectedApp, int argc, char *argv[]) {
    // First of all, let's check if we have JIT
    if (!checkJITEnabled()) {
        appError = @"JIT was not enabled";
        return -1;
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
    if (!appHandle) {
        appError = @(dlerror());
        NSLog(@"[LCBootstrap] %@", appError);
        *path = oldPath;
        return -1;
    }

    // Find main()
    appMain = getAppEntryPoint(appHandle, appIndex);
/*
    if (!appMain) {
        appError = @(dlerror());
        NSLog(@"[LCBootstrap] %@", appError);
        *path = oldPath;
        return -1;
    }
*/

    if (![appBundle loadAndReturnError:&error]) {
        appError = error.localizedDescription;
        NSLog(@"[LCBootstrap] loading bundle failed: %@", error);
        *path = oldPath;
        return -1;
    }
    NSLog(@"[LCBootstrap] loaded bundle");

    if (!overwriteMainBundle(appBundle)) {
        appError = @"Failed to overwrite main bundle";
        *path = oldPath;
        return -1;
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
    return appMain(argc, argv);
}

int LiveContainerMain(int argc, char *argv[]) {
    NSString *selectedApp = [NSUserDefaults.standardUserDefaults stringForKey:@"selected"];
    if (selectedApp) {
        invokeAppMain(selectedApp, argc, argv);
        // don't return, let invokeAppMain takeover or continue
    }
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([LCAppDelegate class]));
    }
}

// fake main() used for dlsym(RTLD_DEFAULT, main)
int main(int argc, char *argv[]) {
    assert(appMain != NULL);
    return appMain(argc, argv);
}
