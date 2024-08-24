#import <Foundation/Foundation.h>
#import "LiveContainerUI/LCAppDelegate.h"
#import "LCSharedUtils.h"
#import "UIKitPrivate.h"
#import "utils.h"

#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <objc/runtime.h>

#include <dlfcn.h>
#include <execinfo.h>
#include <signal.h>
#include <sys/mman.h>
#include <stdlib.h>

static int (*appMain)(int, char**);
static const char *dyldImageName;
NSUserDefaults *lcUserDefaults;

@implementation NSUserDefaults(LiveContainer)
+ (instancetype)lcUserDefaults {
    return lcUserDefaults;
}
@end

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
    // iOS 16: x19 is _MergedGlobals
    // iOS 17: x19 is _MergedGlobals+4

    NSString *oldPath = NSBundle.mainBundle.executablePath;
    uint32_t *mainBundleImpl = (uint32_t *)method_getImplementation(class_getClassMethod(NSBundle.class, @selector(mainBundle)));
    for (int i = 0; i < 20; i++) {
        void **_MergedGlobals = (void **)aarch64_emulate_adrp_add(mainBundleImpl[i], mainBundleImpl[i+1], (uint64_t)&mainBundleImpl[i]);
        if (!_MergedGlobals) continue;

        // In iOS 17, adrp+add gives _MergedGlobals+4, so it uses ldur instruction instead of ldr
        if ((mainBundleImpl[i+4] & 0xFF000000) == 0xF8000000) {
            uint64_t ptr = (uint64_t)_MergedGlobals - 4;
            _MergedGlobals = (void **)ptr;
        }

        for (int mgIdx = 0; mgIdx < 20; mgIdx++) {
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
    char *newPath = (char *)dyldImageName;
    size_t maxLen = rnd64(strlen(path), 8);
    size_t newLen = strlen(newPath);
    // Check if it's long enough...
    assert(maxLen >= newLen);

    // Make it RW and overwrite now
    kern_return_t ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)path, maxLen, false, PROT_READ | PROT_WRITE);
    if (ret != KERN_SUCCESS) {
        ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)path, maxLen, false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    }
    assert(ret == KERN_SUCCESS);
    bzero(path, maxLen);
    strncpy(path, newPath, newLen);
}
static void overwriteExecPath(NSString *bundlePath) {
    // Silly workaround: we have set our executable name 100 characters long, now just overwrite its path with our fake executable file
    char *path = (char *)dyldImageName;
    const char *newPath = [bundlePath stringByAppendingPathComponent:@"LiveContainer"].UTF8String;
    size_t maxLen = rnd64(strlen(path), 8);
    size_t newLen = strlen(newPath);

    // Check if it's long enough...
    assert(maxLen >= newLen);
    // Create an empty file so dyld could resolve its path properly
    close(open(newPath, O_CREAT | S_IRUSR | S_IWUSR));

    // Make it RW and overwrite now
    kern_return_t ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)path, maxLen, false, PROT_READ | PROT_WRITE);
    assert(ret == KERN_SUCCESS);
    bzero(path, maxLen);
    strncpy(path, newPath, newLen);

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
    if (!LCSharedUtils.certificatePassword) {
        // First of all, let's check if we have JIT
        for (int i = 0; i < 10 && !checkJITEnabled(); i++) {
            usleep(1000*100);
        }
        if (!checkJITEnabled()) {
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
    NSString *tweakFolder = [docPath stringByAppendingPathComponent:@"Tweaks"];
    setenv("LC_GLOBAL_TWEAKS_FOLDER", tweakFolder.UTF8String, 1);

    // Update TweakLoader symlink
    NSString *tweakLoaderPath = [tweakFolder stringByAppendingPathComponent:@"TweakLoader.dylib"];
    if (![fm fileExistsAtPath:tweakLoaderPath]) {
        remove(tweakLoaderPath.UTF8String);
        NSString *target = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"TweakLoader.dylib"];
        symlink(target.UTF8String, tweakLoaderPath.UTF8String);
    }

    // If JIT is enabled, bypass library validation so we can load arbitrary binaries
    if (checkJITEnabled()) {
        init_bypassDyldLibValidation();
    }

    // Locate dyld image name address
    const char **path = _CFGetProcessPath();
    const char *oldPath = *path;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (!strcmp(name, oldPath)) {
            dyldImageName = name;
            break;
        }
    }

    // Overwrite @executable_path
    const char *appExecPath = appBundle.executablePath.UTF8String;
    *path = appExecPath;
    overwriteExecPath(appBundle.bundlePath);

    // Overwrite NSUserDefaults
    NSUserDefaults.standardUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:appBundle.bundleIdentifier];

    // Overwrite NSBundle
    overwriteMainNSBundle(appBundle);

    // Overwrite CFBundle
    overwriteMainCFBundle();

    // Overwrite executable info
    NSMutableArray<NSString *> *objcArgv = NSProcessInfo.processInfo.arguments.mutableCopy;
    objcArgv[0] = appBundle.executablePath;
    [NSProcessInfo.processInfo performSelector:@selector(setArguments:) withObject:objcArgv];
    NSProcessInfo.processInfo.processName = appBundle.infoDictionary[@"CFBundleExecutable"];
    *_CFGetProgname() = NSProcessInfo.processInfo.processName.UTF8String;
    
    // Set & save the folder it it does not exist in Info.plist
    NSString* dataUUID = appBundle.infoDictionary[@"LCDataUUID"];
    if(dataUUID == nil) {
        NSMutableDictionary* infoDict = [NSMutableDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath]];
        dataUUID = NSUUID.UUID.UUIDString;
        infoDict[@"LCDataUUID"] = dataUUID;
        [infoDict writeToFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath] atomically:YES];
    }

    // Overwrite home and tmp path
    NSString *newHomePath = [NSString stringWithFormat:@"%@/Data/Application/%@", docPath, dataUUID];
    NSString *newTmpPath = [newHomePath stringByAppendingPathComponent:@"tmp"];
    remove(newTmpPath.UTF8String);
    symlink(getenv("TMPDIR"), newTmpPath.UTF8String);

    setenv("CFFIXED_USER_HOME", newHomePath.UTF8String, 1);
    setenv("HOME", newHomePath.UTF8String, 1);
    setenv("TMPDIR", newTmpPath.UTF8String, 1);

    // Setup directories
    NSArray *dirList = @[@"Library/Caches", @"Documents", @"SystemData"];
    for (NSString *dir in dirList) {
        NSString *dirPath = [newHomePath stringByAppendingPathComponent:dir];
        [fm createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];
    }

    // Preload executable to bypass RT_NOLOAD
    uint32_t appIndex = _dyld_image_count();
    void *appHandle = dlopen(*path, RTLD_LAZY|RTLD_GLOBAL|RTLD_FIRST);
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
    // Fix dynamic properties of some apps
    [NSUserDefaults performSelector:@selector(initialize)];

    if (![appBundle loadAndReturnError:&error]) {
        appError = error.localizedDescription;
        NSLog(@"[LCBootstrap] loading bundle failed: %@", error);
        *path = oldPath;
        return appError;
    }
    NSLog(@"[LCBootstrap] loaded bundle");

    // Find main()
    appMain = getAppEntryPoint(appHandle, appIndex);
    if (!appMain) {
        appError = @"Could not find the main entry point";
        NSLog(@"[LCBootstrap] %@", appError);
        *path = oldPath;
        return appError;
    }

    // Go!
    NSLog(@"[LCBootstrap] jumping to main %p", appMain);
    argv[0] = (char *)appExecPath;
    appMain(argc, argv);

    return nil;
}

static void exceptionHandler(NSException *exception) {
    NSString *error = [NSString stringWithFormat:@"%@\nCall stack: %@", exception.reason, exception.callStackSymbols];
    [lcUserDefaults setObject:error forKey:@"error"];
}

int LiveContainerMain(int argc, char *argv[]) {
    // This strangely fixes some apps getting stuck on black screen
    NSLog(@"Ignore this: %@", UIScreen.mainScreen);

    lcUserDefaults = NSUserDefaults.standardUserDefaults;
    NSString *selectedApp = [lcUserDefaults stringForKey:@"selected"];
    NSLog(@"[NMSL]: selectedApp = %@", selectedApp);
    if (selectedApp) {
        NSString *launchUrl = [lcUserDefaults stringForKey:@"launchAppUrlScheme"];
        [lcUserDefaults removeObjectForKey:@"selected"];
        // wait for app to launch so that it can receive the url
        if(launchUrl) {
            [lcUserDefaults removeObjectForKey:@"launchAppUrlScheme"];
            dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC));
            dispatch_after(delay, dispatch_get_main_queue(), ^{
                // Base64 encode the data
                NSData *data = [launchUrl dataUsingEncoding:NSUTF8StringEncoding];
                NSString *encodedUrl = [data base64EncodedStringWithOptions:0];
                
                NSString* finalUrl = [NSString stringWithFormat:@"livecontainer://open-url?url=%@", encodedUrl];
                NSURL* url = [NSURL URLWithString: finalUrl];
                
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            });
        }
        NSSetUncaughtExceptionHandler(&exceptionHandler);
        setenv("LC_HOME_PATH", getenv("HOME"), 1);
        NSString *appError = invokeAppMain(selectedApp, argc, argv);
        if (appError) {
            [lcUserDefaults setObject:appError forKey:@"error"];
            // potentially unrecovable state, exit now
            return 1;
        }
    }

    void *LiveContainerUIHandle = dlopen("@executable_path/Frameworks/LiveContainerSwiftUI.framework/LiveContainerSwiftUI", RTLD_LAZY);
    assert(LiveContainerUIHandle);
    @autoreleasepool {
        if ([lcUserDefaults boolForKey:@"LCLoadTweaksToSelf"]) {
            dlopen("@executable_path/Frameworks/TweakLoader.dylib", RTLD_LAZY);
        }
        return UIApplicationMain(argc, argv, nil, @"LCAppDelegateSwiftUI");
    }
}

// fake main() used for dlsym(RTLD_DEFAULT, main)
int main(int argc, char *argv[]) {
    assert(appMain != NULL);
    return appMain(argc, argv);
}
