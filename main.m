#import "FoundationPrivate.h"
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
#include "TPRO.h"
#import "fishhook/fishhook.h"
#import "Tweaks/Tweaks.h"
#include <mach-o/ldsyms.h>

static int (*appMain)(int, char**);
static const char *dyldImageName;
NSUserDefaults *lcUserDefaults;
NSUserDefaults *lcSharedDefaults;
NSString *lcAppGroupPath;
NSString* lcAppUrlScheme;
NSBundle* lcMainBundle;
NSDictionary* guestAppInfo;

@implementation NSUserDefaults(LiveContainer)
+ (instancetype)lcUserDefaults {
    return lcUserDefaults;
}
+ (instancetype)lcSharedDefaults {
    return lcSharedDefaults;
}
+ (NSString *)lcAppGroupPath {
    return lcAppGroupPath;
}
+ (NSString *)lcAppUrlScheme {
    return lcAppUrlScheme;
}
+ (NSBundle *)lcMainBundle {
    return lcMainBundle;
}
+ (NSDictionary *)guestAppInfo {
    return guestAppInfo;
}
@end

static BOOL checkJITEnabled() {
    if([lcUserDefaults boolForKey:@"LCIgnoreJITOnLaunch"]) {
        return NO;
    }
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
    
    // if we don't have TPRO, we will use the old way
    if(!os_thread_self_restrict_tpro_to_rw()) {
        // Make it RW and overwrite now
        kern_return_t ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)path, maxLen, false, PROT_READ | PROT_WRITE);
        if (ret != KERN_SUCCESS) {
            ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)path, maxLen, false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
        }
        assert(ret == KERN_SUCCESS);
    }

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

static void *getAppEntryPoint(void *handle) {
    uint32_t entryoff = 0;
    const struct mach_header_64 *header = (struct mach_header_64 *)getGuestAppHeader();
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


static NSString* invokeAppMain(NSString *selectedApp, NSString *selectedContainer, int argc, char *argv[]) {
    NSString *appError = nil;
    if (!LCSharedUtils.certificatePassword) {
        // First of all, let's check if we have JIT
        for (int i = 0; i < 10 && !checkJITEnabled(); i++) {
            usleep(1000*100);
        }
        if (!checkJITEnabled()) {
            appError = @"JIT was not enabled. If you want to use LiveContainer without JIT, setup JITLess mode in settings.";
            return appError;
        }
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *docPath = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask]
        .lastObject.path;
    
    NSURL *appGroupFolder = nil;
    
    NSString *bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", docPath, selectedApp];
    guestAppInfo = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/LCAppInfo.plist", bundlePath]];
    bool isSharedBundle = false;
    // not found locally, let's look for the app in shared folder
    if(!guestAppInfo) {
        NSURL *appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:[LCSharedUtils appGroupID]];
        appGroupFolder = [appGroupPath URLByAppendingPathComponent:@"LiveContainer"];
        bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", appGroupFolder.path, selectedApp];
        guestAppInfo = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/LCAppInfo.plist", bundlePath]];
        isSharedBundle = true;
    }
    
    if(!guestAppInfo) {
        return @"App bundle not found! Unable to read LCAppInfo.plist.";
    }
    
    if([guestAppInfo[@"doUseLCBundleId"] boolValue] ) {
        NSMutableDictionary* infoPlist = [NSMutableDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath]];
        if(![infoPlist[@"CFBundleIdentifier"] isEqualToString:NSBundle.mainBundle.bundleIdentifier]) {
            infoPlist[@"CFBundleIdentifier"] = NSBundle.mainBundle.bundleIdentifier;
            [infoPlist writeToFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath] atomically:YES];
        }
    }
    
    NSBundle *appBundle = [[NSBundle alloc] initWithPathForMainBundle:bundlePath];
    
    if(!appBundle) {
        return @"App not found";
    }
    
    // find container in Info.plist
    NSString* dataUUID = selectedContainer;
    if(!dataUUID) {
        dataUUID = guestAppInfo[@"LCDataUUID"];
    }

    if(dataUUID == nil) {
        return @"Container not found!";
    }
    
    if(isSharedBundle) {
        [LCSharedUtils setAppRunningByThisLC:selectedApp];
        [LCSharedUtils setContainerUsingByThisLC:dataUUID];
    }
    
    NSError *error;

    // Setup tweak loader
    NSString *tweakFolder = nil;
    if (isSharedBundle) {
        tweakFolder = [appGroupFolder.path  stringByAppendingPathComponent:@"Tweaks"];
    } else {
        tweakFolder = [docPath stringByAppendingPathComponent:@"Tweaks"];
    }
    setenv("LC_GLOBAL_TWEAKS_FOLDER", tweakFolder.UTF8String, 1);

    // Update TweakLoader symlink
    NSString *tweakLoaderPath = [tweakFolder stringByAppendingPathComponent:@"TweakLoader.dylib"];
    if (![fm fileExistsAtPath:tweakLoaderPath]) {
        remove(tweakLoaderPath.UTF8String);
        NSString *target = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"TweakLoader.dylib"];
        symlink(target.UTF8String, tweakLoaderPath.UTF8String);
    }

    // If JIT is enabled, bypass library validation so we can load arbitrary binaries
    bool isJitEnabled = checkJITEnabled();
    if (isJitEnabled) {
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
    if([guestAppInfo[@"doUseLCBundleId"] boolValue]) {
        NSUserDefaults.standardUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:guestAppInfo[@"LCOrignalBundleIdentifier"]];
    } else {
        NSUserDefaults.standardUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:appBundle.bundleIdentifier];
    }

    // Overwrite home and tmp path
    NSString *newHomePath = nil;
    if(isSharedBundle) {
        newHomePath = [NSString stringWithFormat:@"%@/Data/Application/%@", appGroupFolder.path, dataUUID];
        // move data folder to private library
        NSURL *libraryPathUrl = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].lastObject;
        NSString *sharedAppDataFolderPath = [libraryPathUrl.path stringByAppendingPathComponent:@"SharedDocuments"];
        NSString* dataFolderPath = [appGroupFolder.path stringByAppendingPathComponent:[NSString stringWithFormat:@"Data/Application/%@", dataUUID]];
        newHomePath = [sharedAppDataFolderPath stringByAppendingPathComponent: dataUUID];
        [fm moveItemAtPath:dataFolderPath toPath:newHomePath error:&error];
    } else {
        newHomePath = [NSString stringWithFormat:@"%@/Data/Application/%@", docPath, dataUUID];
    }
    
    
    NSString *newTmpPath = [newHomePath stringByAppendingPathComponent:@"tmp"];
    remove(newTmpPath.UTF8String);
    symlink(getenv("TMPDIR"), newTmpPath.UTF8String);
    
    if([guestAppInfo[@"doSymlinkInbox"] boolValue]) {
        NSString* inboxSymlinkPath = [NSString stringWithFormat:@"%s/%@-Inbox", getenv("TMPDIR"), [appBundle bundleIdentifier]];
        NSString* inboxPath = [newHomePath stringByAppendingPathComponent:@"Inbox"];
        
        if (![fm fileExistsAtPath:inboxPath]) {
            [fm createDirectoryAtPath:inboxPath withIntermediateDirectories:YES attributes:nil error:&error];
        }
        if([fm fileExistsAtPath:inboxSymlinkPath]) {
            NSString* fileType = [fm attributesOfItemAtPath:inboxSymlinkPath error:&error][NSFileType];
            if(fileType == NSFileTypeDirectory) {
                NSArray* contents = [fm contentsOfDirectoryAtPath:inboxSymlinkPath error:&error];
                for(NSString* content in contents) {
                    [fm moveItemAtPath:[inboxSymlinkPath stringByAppendingPathComponent:content] toPath:[inboxPath stringByAppendingPathComponent:content] error:&error];
                }
                [fm removeItemAtPath:inboxSymlinkPath error:&error];
            }
        }
        

        symlink(inboxPath.UTF8String, inboxSymlinkPath.UTF8String);
    } else {
        NSString* inboxSymlinkPath = [NSString stringWithFormat:@"%s/%@-Inbox", getenv("TMPDIR"), [appBundle bundleIdentifier]];
        NSDictionary* targetAttribute = [fm attributesOfItemAtPath:inboxSymlinkPath error:&error];
        if(targetAttribute) {
            if(targetAttribute[NSFileType] == NSFileTypeSymbolicLink) {
                [fm removeItemAtPath:inboxSymlinkPath error:&error];
            }
        }

    }
    
    if([guestAppInfo[@"fixBlackScreen"] boolValue]) {
        dlopen("/System/Library/Frameworks/UIKit.framework/UIKit", RTLD_GLOBAL);
        NSLog(@"[LC] Fix BlackScreen2 %@", [NSClassFromString(@"UIScreen") mainScreen]);
    }

    setenv("CFFIXED_USER_HOME", newHomePath.UTF8String, 1);
    setenv("HOME", newHomePath.UTF8String, 1);
    setenv("TMPDIR", newTmpPath.UTF8String, 1);

    // Setup directories
    NSArray *dirList = @[@"Library/Caches", @"Documents", @"SystemData"];
    for (NSString *dir in dirList) {
        NSString *dirPath = [newHomePath stringByAppendingPathComponent:dir];
        [fm createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];
    }

    [lcUserDefaults setObject:dataUUID forKey:@"lastLaunchDataUUID"];
    if(isSharedBundle) {
        [lcUserDefaults setObject:@"Shared" forKey:@"lastLaunchType"];
    } else {
        [lcUserDefaults setObject:@"Private" forKey:@"lastLaunchType"];
    }

    
    // Overwrite NSBundle
    overwriteMainNSBundle(appBundle);

    // Overwrite CFBundle
    overwriteMainCFBundle();

    // Overwrite executable info
    if(!appBundle.executablePath) {
        return @"App's executable path not found. Please try force re-signing or reinstalling this app.";
    }
    
    NSMutableArray<NSString *> *objcArgv = NSProcessInfo.processInfo.arguments.mutableCopy;
    objcArgv[0] = appBundle.executablePath;
    [NSProcessInfo.processInfo performSelector:@selector(setArguments:) withObject:objcArgv];
    NSProcessInfo.processInfo.processName = appBundle.infoDictionary[@"CFBundleExecutable"];
    *_CFGetProgname() = NSProcessInfo.processInfo.processName.UTF8String;
    
    // hook NSUserDefault before running libraries' initializers
    NUDGuestHooksInit();
    SecItemGuestHooksInit();
    NSFMGuestHooksInit();
    // Preload executable to bypass RT_NOLOAD
    uint32_t appIndex = _dyld_image_count();
    appMainImageIndex = appIndex;
    
    DyldHooksInit([guestAppInfo[@"hideLiveContainer"] boolValue]);
    
    bool is32bit = [guestAppInfo[@"is32bit"] boolValue];
    if(is32bit) {
        if (!isJitEnabled) {
            return @"JIT is required to run 32-bit apps.";
        }
        
        NSString *selected32BitLayer = [lcUserDefaults stringForKey:@"selected32BitLayer"];
        if(!selected32BitLayer || [selected32BitLayer length] == 0) {
            appError = @"No 32-bit translation layer installed";
            NSLog(@"[LCBootstrap] %@", appError);
            *path = oldPath;
            return appError;
        }
        NSBundle *selected32bitLayerBundle = [NSBundle bundleWithPath:[docPath stringByAppendingPathComponent:selected32BitLayer]]; //TODO make it user friendly;
        if(!selected32bitLayerBundle) {
            appError = @"The specified LiveExec32.app path is not found";
            NSLog(@"[LCBootstrap] %@", appError);
            *path = oldPath;
            return appError;
        }
        // maybe need to save selected32bitLayerBundle to static variable?
        appExecPath = strdup(selected32bitLayerBundle.executablePath.UTF8String);
    }
    
    if(![guestAppInfo[@"dontInjectTweakLoader"] boolValue]) {
        tweakLoaderLoaded = true;
    }
    void *appHandle = dlopen(appExecPath, RTLD_LAZY|RTLD_GLOBAL|RTLD_FIRST);
    appExecutableHandle = appHandle;
    const char *dlerr = dlerror();
    
    if (!appHandle || (uint64_t)appHandle > 0xf00000000000) {
        if (dlerr) {
            appError = @(dlerr);
        } else {
            appError = @"dlopen: an unknown error occurred";
        }
        NSLog(@"[LCBootstrap] %@", appError);
        *path = oldPath;
        return appError;
    }
    
    if([guestAppInfo[@"dontInjectTweakLoader"] boolValue] && ![guestAppInfo[@"dontLoadTweakLoader"] boolValue]) {
        tweakLoaderLoaded = true;
        dlopen("@loader_path/../../Tweaks/TweakLoader.dylib", RTLD_LAZY|RTLD_GLOBAL);
    }
    
    // Fix dynamic properties of some apps
    [NSUserDefaults performSelector:@selector(initialize)];

    // Attempt to load the bundle. 32-bit bundle will always fail because of 32-bit main executable, so ignore it
    if (!is32bit && ![appBundle loadAndReturnError:&error]) {
        appError = error.localizedDescription;
        NSLog(@"[LCBootstrap] loading bundle failed: %@", error);
        *path = oldPath;
        return appError;
    }
    NSLog(@"[LCBootstrap] loaded bundle");

    // Find main()
    appMain = getAppEntryPoint(appHandle);
    if (!appMain) {
        appError = @"Could not find the main entry point";
        NSLog(@"[LCBootstrap] %@", appError);
        *path = oldPath;
        return appError;
    }

    // Go!
    NSLog(@"[LCBootstrap] jumping to main %p", appMain);
    int ret;
    if(!is32bit) {
        argv[0] = (char *)appExecPath;
        ret = appMain(argc, argv);
    } else {
        char *argv32[] = {(char*)appExecPath, (char*)*path, NULL};
        ret = appMain(sizeof(argv32)/sizeof(*argv32) - 1, argv32);
    }

    return [NSString stringWithFormat:@"App returned from its main function with code %d.", ret];
}

static void exceptionHandler(NSException *exception) {
    NSString *error = [NSString stringWithFormat:@"%@\nCall stack: %@", exception.reason, exception.callStackSymbols];
    [lcUserDefaults setObject:error forKey:@"error"];
}

int LiveContainerMain(int argc, char *argv[]) {
    // This strangely fixes some apps getting stuck on black screen
    NSLog(@"Ignore this: %@", dispatch_get_main_queue());

    lcMainBundle = [NSBundle mainBundle];
    lcUserDefaults = NSUserDefaults.standardUserDefaults;
    lcSharedDefaults = [[NSUserDefaults alloc] initWithSuiteName: [LCSharedUtils appGroupID]];
    lcAppUrlScheme = NSBundle.mainBundle.infoDictionary[@"CFBundleURLTypes"][0][@"CFBundleURLSchemes"][0];
    lcAppGroupPath = [[NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:[NSClassFromString(@"LCSharedUtils") appGroupID]] path];
    
    NSString* lastLaunchDataUUID = [lcUserDefaults objectForKey:@"lastLaunchDataUUID"];
    if(lastLaunchDataUUID) {
        NSString* lastLaunchType = [lcUserDefaults objectForKey:@"lastLaunchType"];
        NSString* preferencesTo;
        NSURL *libraryPathUrl = [NSFileManager.defaultManager URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].lastObject;
        NSURL *docPathUrl = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject;
        if([lastLaunchType isEqualToString:@"Shared"]) {
            preferencesTo = [libraryPathUrl.path stringByAppendingPathComponent:[NSString stringWithFormat:@"SharedDocuments/%@/Library/Preferences", lastLaunchDataUUID]];
        } else {
            preferencesTo = [docPathUrl.path stringByAppendingPathComponent:[NSString stringWithFormat:@"Data/Application/%@/Library/Preferences", lastLaunchDataUUID]];
        }
        // recover preferences
        [LCSharedUtils dumpPreferenceToPath:preferencesTo dataUUID:lastLaunchDataUUID];
        [lcUserDefaults removeObjectForKey:@"lastLaunchDataUUID"];
        [lcUserDefaults removeObjectForKey:@"lastLaunchType"];
    }

    [LCSharedUtils moveSharedAppFolderBack];
    
    NSString *selectedApp = [lcUserDefaults stringForKey:@"selected"];
    NSString *selectedContainer = [lcUserDefaults stringForKey:@"selectedContainer"];
    if(selectedApp && !selectedContainer) {
        selectedContainer = [LCSharedUtils findDefaultContainerWithBundleId:selectedApp];
    }
    NSString* runningLC = [LCSharedUtils getContainerUsingLCSchemeWithFolderName:selectedContainer];
    // if another instance is running, we just switch to that one, these should be called after uiapplication initialized
    if(selectedApp && runningLC) {
        [lcUserDefaults removeObjectForKey:@"selected"];
        [lcUserDefaults removeObjectForKey:@"selectedContainer"];
        NSString* selectedAppBackUp = selectedApp;
        selectedApp = nil;
        dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC));
        dispatch_after(delay, dispatch_get_main_queue(), ^{
            // Base64 encode the data
            NSString* urlStr;
            if(selectedContainer) {
                urlStr = [NSString stringWithFormat:@"%@://livecontainer-launch?bundle-name=%@&container-folder-name=%@", runningLC, selectedAppBackUp, selectedContainer];
            } else {
                urlStr = [NSString stringWithFormat:@"%@://livecontainer-launch?bundle-name=%@", runningLC, selectedAppBackUp];
            }
            
            NSURL* url = [NSURL URLWithString:urlStr];
            if([[NSClassFromString(@"UIApplication") sharedApplication] canOpenURL:url]){
                [[NSClassFromString(@"UIApplication") sharedApplication] openURL:url options:@{} completionHandler:nil];
                
                NSString *launchUrl = [lcUserDefaults stringForKey:@"launchAppUrlScheme"];
                // also pass url scheme to another lc
                if(launchUrl) {
                    [lcUserDefaults removeObjectForKey:@"launchAppUrlScheme"];

                    // Base64 encode the data
                    NSData *data = [launchUrl dataUsingEncoding:NSUTF8StringEncoding];
                    NSString *encodedUrl = [data base64EncodedStringWithOptions:0];
                    
                    NSString* finalUrl = [NSString stringWithFormat:@"%@://open-url?url=%@", runningLC, encodedUrl];
                    NSURL* url = [NSURL URLWithString: finalUrl];
                    
                    [[NSClassFromString(@"UIApplication") sharedApplication] openURL:url options:@{} completionHandler:nil];

                }
            } else {
                [LCSharedUtils removeAppRunningByLC: runningLC];
                [LCSharedUtils removeContainerUsingByLC: runningLC];
            }
        });

    }
    
    if (selectedApp) {
        
        NSString *launchUrl = [lcUserDefaults stringForKey:@"launchAppUrlScheme"];
        [lcUserDefaults removeObjectForKey:@"selected"];
        [lcUserDefaults removeObjectForKey:@"selectedContainer"];
        // wait for app to launch so that it can receive the url
        if(launchUrl) {
            [lcUserDefaults removeObjectForKey:@"launchAppUrlScheme"];
            dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC));
            dispatch_after(delay, dispatch_get_main_queue(), ^{
                // Base64 encode the data
                NSData *data = [launchUrl dataUsingEncoding:NSUTF8StringEncoding];
                NSString *encodedUrl = [data base64EncodedStringWithOptions:0];
                
                NSString* finalUrl = [NSString stringWithFormat:@"%@://open-url?url=%@", lcAppUrlScheme, encodedUrl];
                NSURL* url = [NSURL URLWithString: finalUrl];
                
                [[NSClassFromString(@"UIApplication") sharedApplication] openURL:url options:@{} completionHandler:nil];
            });
        }
        NSSetUncaughtExceptionHandler(&exceptionHandler);
        setenv("LC_HOME_PATH", getenv("HOME"), 1);
        NSString *appError = invokeAppMain(selectedApp, selectedContainer, argc, argv);
        if (appError) {
            [lcUserDefaults setObject:appError forKey:@"error"];
            // potentially unrecovable state, exit now
            return 1;
        }
    }
    [LCSharedUtils setAppRunningByThisLC:nil];
    [LCSharedUtils setContainerUsingByThisLC:nil];
    // recover language before reaching UI
    NSArray* savedLaunguage = [lcUserDefaults objectForKey:@"LCLastLanguages"];
    if(savedLaunguage) {
        [lcUserDefaults setObject:savedLaunguage forKey:@"AppleLanguages"];
        [lcUserDefaults removeObjectForKey:@"LCLastLanguages"];
        [lcUserDefaults synchronize];
    }
    void *LiveContainerSwiftUIHandle = dlopen("@executable_path/Frameworks/LiveContainerSwiftUI.framework/LiveContainerSwiftUI", RTLD_LAZY);
    assert(LiveContainerSwiftUIHandle);
    @autoreleasepool {
        if ([lcUserDefaults boolForKey:@"LCLoadTweaksToSelf"]) {
            dlopen("@executable_path/Frameworks/TweakLoader.dylib", RTLD_LAZY);
        }

        void *uikitHandle = dlopen("/System/Library/Frameworks/UIKit.framework/UIKit", RTLD_GLOBAL);
        int (*UIApplicationMain)(int, char**, NSString *, NSString *) = dlsym(uikitHandle, "UIApplicationMain");
        return UIApplicationMain(argc, argv, nil, @"LiveContainerSwiftUI.AppDelegate");
    }
}

// fake main() used for dlsym(RTLD_DEFAULT, main)
int main(int argc, char *argv[]) {
    assert(appMain != NULL);
    return appMain(argc, argv);
}
