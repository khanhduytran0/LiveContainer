#import <Foundation/Foundation.h>
#import "LCAppDelegate.h"
#import "UIKitPrivate.h"
#import "utils.h"

#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <objc/runtime.h>

#include <dlfcn.h>
#include <execinfo.h>
#include <libgen.h>
#include <signal.h>
#include <spawn.h>
#include <sys/mman.h>
#include <stdlib.h>

static int (*appMain)(int, char**);

static BOOL isSandboxed() {
    return access("/var/mobile", R_OK) != 0;
}

static BOOL isJITEnabled() {
    // check csflags
    int flags;
    csops(getpid(), 0, &flags, sizeof(flags));
    return (flags & CS_DEBUGGED) != 0;
}

static uint64_t rnd64(uint64_t v, uint64_t r) {
    r--;
    return (v + r) & ~r;
}

static void overwriteMainCFBundle() {
    // Overwrite CFBundleGetMainBundle
    uint32_t *pc = (uint32_t *)CFBundleGetMainBundle;
    void **mainBundleAddr = 0;
    while (true) {
        uint64_t addr = aarch64_get_tbnz_jump_address(*pc, (uint64_t)pc);
        if (addr) {
            // adrp <- pc-1
            // tbnz <- pc
            // ...
            // ldr  <- addr
            mainBundleAddr = (void **)aarch64_emulate_adrp_ldr(*(pc-1), *(uint32_t *)addr, (uint64_t)(pc-1));
            break;
        }
        ++pc;
    }
    assert(mainBundleAddr != NULL);
    *mainBundleAddr = (__bridge void *)NSBundle.mainBundle._cfBundle;
}

static void overwriteMainNSBundle(NSBundle *newBundle) {
    // Overwrite NSBundle.mainBundle
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

    assert(![NSBundle.mainBundle.executablePath isEqualToString:oldPath]);
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
    size_t maxLen = rnd64(strlen(path), 8);
    size_t newLen = strlen(newPath);
    // Check if it's long enough...
    assert(maxLen >= newLen);
    kern_return_t ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)path, rnd64(maxLen, 8), false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    if (ret != KERN_SUCCESS) {
        NSLog(@"Failed to remap rw for executable_path, some apps will not work!");
        return;
    }

#if 0
    // FIXME: mass vm_protect to avoid failing at any chance
    if (ret != KERN_SUCCESS) {
        ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)path, maxLen, false, PROT_READ | PROT_WRITE);
    }
    if (ret != KERN_SUCCESS) {
        ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)path, maxLen, false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    }
    if (ret != KERN_SUCCESS) {
        builtin_vm_protect(mach_task_self(), (mach_vm_address_t)path, maxLen, false, PROT_READ | VM_PROT_COPY);
        ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)path, maxLen, false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    }
    assert(ret == KERN_SUCCESS);
#endif

    bzero(path, maxLen);
    strncpy(path, newPath, newLen);
}
static void overwriteExecPath(NSString *bundlePath) {
    // Silly workaround: we have set our executable name 100 characters long, now just overwrite its path with our fake executable file
    char *path = (char *)_dyld_get_image_name(0);
    const char *newPath = [bundlePath stringByAppendingPathComponent:@"LiveContainer"].UTF8String;
    size_t maxLen = rnd64(strlen(path), 8);
    size_t newLen = strlen(newPath);
    // Check if it's long enough...
    assert(maxLen >= newLen);
    // Create an empty file so dyld could resolve its path properly
    close(open(newPath, O_CREAT | S_IRUSR | S_IWUSR));

    // Make it RW and overwrite now
    kern_return_t ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)path, maxLen, false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    assert(ret == KERN_SUCCESS);
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

static BOOL enableJITSpawnPtrace(char *argv[]) {
    if (isSandboxed()) {
        return NO;
    }

    int pid;
    int ret = posix_spawnp(&pid, argv[0], NULL, NULL, (char *[]){argv[0], "", NULL}, environ);
    if (ret == 0) {
        // Cleanup child process
        waitpid(pid, NULL, WUNTRACED);
        ptrace(PT_DETACH, pid, NULL, 0);
        kill(pid, SIGTERM);
        wait(NULL);

        if (isJITEnabled()) {
            NSLog(@"JIT has been enabled");
#if 0
            // Drop ourselves back to sandboxed app
            char path[PATH_MAX];
            sprintf(path, "%s/LiveContainer_PleaseDoNotShortenTheExecutableNameBecauseItIsUsedToReserveSpaceForOverwritingThankYou", dirname(argv[0]));
            execv(path, (char *[]){argv[0], NULL});
#endif
            return 1;
        } else {
            NSLog(@"Failed to enable JIT: unknown reason");
            return NO;
        }
    } else {
        NSLog(@"Failed to enable JIT: posix_spawn() failed errno %d", errno);
        return NO;
    }
}

static NSString* invokeAppMain(NSString *selectedApp, int argc, char *argv[]) {
    NSString *appError = nil;

    
    // First of all, let's check if we have JIT
    if (!isJITEnabled() && !enableJITSpawnPtrace(argv)) {
        for (int i = 0; i < 10 && !isJITEnabled(); i++) {
            usleep(1000*100);
        }
        if (!isJITEnabled()) {
            appError = @"JIT was not enabled";
            return appError;
        }
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *docPath = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask]
        .lastObject.path;
    NSString *bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", docPath, selectedApp];
    NSBundle *appBundle = [[NSBundle alloc] initWithPath:bundlePath];
    NSError *error;

    // Setup tweak loader
    NSString *tweakFolder = appBundle.infoDictionary[@"LCTweakFolder"];
    if (tweakFolder) {
        tweakFolder = [NSString stringWithFormat:@"%@/Tweaks/%@", docPath, tweakFolder];
        setenv("LC_TWEAK_FOLDER", tweakFolder.UTF8String, 1);
    }
    // Update TweakLoader symlink
    NSString *tweakLoaderPath = [docPath stringByAppendingPathComponent:@"Tweaks/TweakLoader.dylib"];
    if (![fm fileExistsAtPath:tweakLoaderPath]) {
        remove(tweakLoaderPath.UTF8String);
        NSString *target = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"TweakLoader.dylib"];
        symlink(target.UTF8String, tweakLoaderPath.UTF8String);
    }

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
    void *appHandle = dlopen(*path, RTLD_LAZY|RTLD_LOCAL|RTLD_FIRST);
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

    // Overwrite NSBundle
    overwriteMainNSBundle(appBundle);

    // Overwrite CFBundle. This should only be done after run loop starts
    dispatch_async(dispatch_get_main_queue(), ^{
        overwriteMainCFBundle();
    });

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
    setenv("TMPDIR", [@(getenv("TMPDIR")) stringByAppendingFormat:@"/%@/tmp", appBundle.infoDictionary[@"LCDataUUID"]].UTF8String, 1);
    // Setup directories
    NSString *cachePath = [NSString stringWithFormat:@"%@/Library/Caches", newHomePath];
    [fm createDirectoryAtPath:cachePath withIntermediateDirectories:YES attributes:nil error:nil];

    // Overwrite NSUserDefaults
    NSUserDefaults.standardUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:appBundle.bundleIdentifier];

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
    if (!isJITEnabled() && argc == 2) {
        // Child process can call to PT_TRACE_ME
        // then both parent and child processes get CS_DEBUGGED
        int ret = ptrace(PT_TRACE_ME, 0, 0, 0);
        return ret;
    }

    NSString *selectedApp = [NSUserDefaults.standardUserDefaults stringForKey:@"selected"];
    if (selectedApp) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"selected"];
        NSSetUncaughtExceptionHandler(&exceptionHandler);
        LCHomePath(); // init host home path
        NSString *appError = invokeAppMain(selectedApp, argc, argv);
        if (appError) {
            [NSUserDefaults.standardUserDefaults setObject:appError forKey:@"error"];
            // potentially unrecovable state, exit now
            return 1;
        }
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
