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

static NSBundle *overwrittenBundle;
@implementation NSBundle(LC_iOS12)
+ (id)hooked_mainBundle {
    if (overwrittenBundle) {
        return overwrittenBundle;
    }
    return self.hooked_mainBundle;
}
@end

static int (*appMain)(int, char**);

static BOOL checkJITEnabled() {
    // check if jailbroken
    if (access("/var/mobile", R_OK) == 0) {
        return YES;
    }

    // check csflags
    int flags;
    csops(getpid(), 0, &flags, sizeof(flags));
    return (flags & CS_DEBUGGED) != 0;
}

static BOOL overwriteMainBundle(NSBundle *newBundle) {
    NSString *oldPath = NSBundle.mainBundle.executablePath;
    uint32_t *mainBundleImpl = (uint32_t *)method_getImplementation(class_getClassMethod(NSBundle.class, @selector(mainBundle)));
    for (int i = 0; i < 20; i++) {
        void **_MergedGlobals = (void **)aarch64_emulate_adrp_add(mainBundleImpl[i], mainBundleImpl[i+1], (uint64_t)&mainBundleImpl[i]);
        if (!_MergedGlobals) continue;
        for (int mgIdx = 0; mgIdx < 4; mgIdx++) {
            if (_MergedGlobals[mgIdx] == (__bridge void *)NSBundle.mainBundle) {
                _MergedGlobals[mgIdx] = (__bridge void *)newBundle;
                break;
            }
        }
    }

    return ![NSBundle.mainBundle.executablePath isEqualToString:oldPath];
}

static void overwriteExecPath_handler(int signum, siginfo_t* siginfo, void* context) {
    struct __darwin_ucontext *ucontext = (struct __darwin_ucontext *)context;

    // x19: size pointer
    // x20: output buffer
    // x21: executable_path

    // Ensure we're not getting SIGSEGV twice
    static uint32_t fakeSize = 0;
    assert(ucontext->uc_mcontext->__ss.__x[19] == 0);
    ucontext->uc_mcontext->__ss.__x[19] = (uint64_t)&fakeSize;

    char *path = (char *)ucontext->uc_mcontext->__ss.__x[21];
    char *newPath = (char *)_dyld_get_image_name(0);
    size_t maxLen = strlen(path);
    size_t newLen = strlen(newPath);
    // Check if it's long enough...
    assert(maxLen >= newLen);
    kern_return_t ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)path, maxLen, false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    if (ret == KERN_SUCCESS) {
        bzero(path, maxLen);
        strncpy(path, newPath, newLen);
    } else {
        // For some reason, changing protection may fail, let's overwrite pointer instead
        // Given x22 is the closest one to reach process.mainExecutablePath
        assert(ucontext->uc_mcontext->__ss.__x[22] >= 0x100000000);
        char **ptrToSomewhere = (char **)ucontext->uc_mcontext->__ss.__x[22];
        for (int i = 0; i < 10; i++) {
            ++ptrToSomewhere;
            if (*ptrToSomewhere == path) {
                break;
            }
        }
        assert(*ptrToSomewhere == path);
        ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)ptrToSomewhere, sizeof(void *), false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
        // fails again?
        assert(ret == KERN_SUCCESS);
        *ptrToSomewhere = newPath;
    }
}
static void overwriteExecPath(NSString *bundlePath) {
    // Silly workaround: we have set our executable name 100 characters long, now just overwrite its path with our fake executable file
    char *path = (char *)_dyld_get_image_name(0);
    const char *newPath = [bundlePath stringByAppendingPathComponent:@"LiveContainer"].UTF8String;
    size_t maxLen = strlen(path);
    size_t newLen = strlen(newPath);
    // Check if it's long enough...
    assert(maxLen >= newLen);
    // Create an empty file so dyld could resolve its path properly
    close(open(newPath, O_CREAT | S_IRUSR | S_IWUSR));

    // Make it RW and overwrite now
    builtin_vm_protect(mach_task_self(), (mach_vm_address_t)path, maxLen, false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    bzero(path, maxLen);
    strncpy(path, newPath, newLen);
    // Don't change back to RO to avoid any issues related to memory access

    // dyld4 stores executable path in a different place
    // https://github.com/apple-oss-distributions/dyld/blob/ce1cc2088ef390df1c48a1648075bbd51c5bbc6a/dyld/DyldAPIs.cpp#L802
    char currPath[PATH_MAX];
    uint32_t len = PATH_MAX;
    _NSGetExecutablePath(currPath, &len);
    if (strncmp(currPath, newPath, newLen)) {
        struct sigaction sa, saOld;
        sa.sa_sigaction = overwriteExecPath_handler;
        sa.sa_flags = SA_SIGINFO;
        sigaction(SIGSEGV, &sa, &saOld);
        // Jump to overwriteExecPath_handler()
        _NSGetExecutablePath((char *)0x41414141, NULL);
        sigaction(SIGSEGV, &saOld, NULL);
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
    return (void *)header + entryoff;
}

static NSString* invokeAppMain(NSString *selectedApp, int argc, char *argv[]) {
    NSString *appError = nil;
    // First of all, let's check if we have JIT
    for (int i = 0; i < 10 && !checkJITEnabled(); i++) {
        usleep(1000*100);
    }
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

    // Bind _dyld_get_all_image_infos
    init_fixCydiaSubstrate();

    // Overwrite @executable_path
    const char **path = _CFGetProcessPath();
    const char *oldPath = *path;
    *path = appBundle.executablePath.UTF8String;
    overwriteExecPath(appBundle.bundlePath);

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

    if (@available(iOS 14.0, *)) {
        if (!overwriteMainBundle(appBundle)) {
            appError = @"Failed to overwrite main bundle";
            *path = oldPath;
            return appError;
        }
    } else {
        // On iOS 12 (and 13?) direct overwriting also overwrites the underlying CFBundle,
        // causing _GSRegisterPurpleNamedPortInPrivateNamespace to fail due to
        // GetIdentifierCString returning guest app's identifier. Use a different route.
        method_exchangeImplementations(class_getClassMethod(NSBundle.class, @selector(mainBundle)), class_getClassMethod(NSBundle.class, @selector(hooked_mainBundle)));
        overwrittenBundle = appBundle;
    }

    // Overwrite executable info
    NSMutableArray<NSString *> *objcArgv = NSProcessInfo.processInfo.arguments.mutableCopy;
    objcArgv[0] = appBundle.executablePath;
    [NSProcessInfo.processInfo performSelector:@selector(setArguments:) withObject:objcArgv];
    NSProcessInfo.processInfo.processName = appBundle.infoDictionary[@"CFBundleExecutable"];
    *_CFGetProgname() = NSProcessInfo.processInfo.processName.UTF8String;

    // Overwrite home path
    NSString *newHomePath = [NSString stringWithFormat:@"%@/Data/Application/%@", docPath, appBundle.infoDictionary[@"LCDataUUID"]];
    setenv("CFFIXED_USER_HOME", newHomePath.UTF8String, 1);
    setenv("HOME", newHomePath.UTF8String, 1);

    // Go!
    NSLog(@"[LCBootstrap] jumping to main %p", appMain);
    argv[0] = (char *)NSBundle.mainBundle.executablePath.UTF8String;
    appMain(argc, argv);

    return nil;
}

static void exceptionHandler(NSException *exception) {
    NSString *error = [NSString stringWithFormat:@"%@\nCall stack: %@", exception.reason, exception.callStackSymbols];
    [NSUserDefaults.standardUserDefaults setObject:error forKey:@"error"];
}

int LiveContainerMain(int argc, char *argv[]) {
    NSString *appError = nil;
    NSString *selectedApp = [NSUserDefaults.standardUserDefaults stringForKey:@"selected"];
    if (selectedApp) {
        NSSetUncaughtExceptionHandler(&exceptionHandler);
        appError = invokeAppMain(selectedApp, argc, argv);
        // don't return, let invokeAppMain takeover or continue to LiveContainerUI
    }

    if (appError) {
        [NSUserDefaults.standardUserDefaults setObject:appError forKey:@"error"];
    }

    void *LiveContainerUIHandle = dlopen("@executable_path/Frameworks/LiveContainerUI.dylib", RTLD_LAZY);
    assert(LiveContainerUIHandle);
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, @"LCAppDelegate");
    }
}

// fake main() used for dlsym(RTLD_DEFAULT, main)
int main(int argc, char *argv[]) {
    assert(appMain != NULL);
    return appMain(argc, argv);
}
