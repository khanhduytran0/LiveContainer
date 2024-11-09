#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <objc/runtime.h>

static NSString *loadTweakAtURL(NSURL *url) {
    NSString *tweakPath = url.path;
    NSString *tweak = tweakPath.lastPathComponent;
    if (![tweakPath hasSuffix:@".dylib"]) {
        return nil;
    }
    void *handle = dlopen(tweakPath.UTF8String, RTLD_LAZY | RTLD_GLOBAL);
    const char *error = dlerror();
    if (handle) {
        NSLog(@"Loaded tweak %@", tweak);
        return nil;
    } else if (error) {
        NSLog(@"Error: %s", error);
        return @(error);
    } else {
        NSLog(@"Error: dlopen(%@): Unknown error because dlerror() returns NULL", tweak);
        return [NSString stringWithFormat:@"dlopen(%@): unknown error, handle is NULL", tweakPath];
    }
}

static void showDlerrAlert(NSString *error) {
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Failed to load tweaks" message:error preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        window.windowScene = nil;
    }];
    [alert addAction:okAction];
    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
        UIPasteboard.generalPasteboard.string = error;
        window.windowScene = nil;
    }];
    [alert addAction:cancelAction];
    window.rootViewController = [UIViewController new];
    window.windowLevel = 1000;
    window.windowScene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    [window makeKeyAndVisible];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
    objc_setAssociatedObject(alert, @"window", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

 __attribute__((constructor))
static void TweakLoaderConstructor() {
    const char *tweakFolderC = getenv("LC_GLOBAL_TWEAKS_FOLDER");
    NSString *globalTweakFolder = @(tweakFolderC);
    unsetenv("LC_GLOBAL_TWEAKS_FOLDER");

    NSMutableArray *errors = [NSMutableArray new];

    // Load CydiaSubstrate
    dlopen("@loader_path/CydiaSubstrate.framework/CydiaSubstrate", RTLD_LAZY | RTLD_GLOBAL);
    const char *substrateError = dlerror();
    if (substrateError) {
        [errors addObject:@(substrateError)];
    }

    // Load global tweaks
    NSLog(@"Loading tweaks from the global folder");
    NSArray<NSURL *> *globalTweaks = [NSFileManager.defaultManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:globalTweakFolder]
    includingPropertiesForKeys:@[] options:0 error:nil];
    for (NSURL *fileURL in globalTweaks) {
        NSString *error = loadTweakAtURL(fileURL);
        if (error) {
            [errors addObject:error];
        }
    }

    // Load selected tweak folder, recursively
    NSString *tweakFolderName = NSBundle.mainBundle.infoDictionary[@"LCTweakFolder"];
    if (tweakFolderName.length > 0) {
        NSLog(@"Loading tweaks from the selected folder");
        NSString *tweakFolder = [globalTweakFolder stringByAppendingPathComponent:tweakFolderName];
        NSURL *tweakFolderURL = [NSURL fileURLWithPath:tweakFolder];
        NSDirectoryEnumerator *directoryEnumerator = [NSFileManager.defaultManager enumeratorAtURL:tweakFolderURL includingPropertiesForKeys:@[] options:0 errorHandler:^BOOL(NSURL *url, NSError *error) {
            NSLog(@"Error while enumerating tweak directory: %@", error);
            return YES;
        }];
        for (NSURL *fileURL in directoryEnumerator) {
            NSString *error = loadTweakAtURL(fileURL);
            if (error) {
                [errors addObject:error];
            }
        }
    }

    if (errors.count > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *error = [errors componentsJoinedByString:@"\n"];
            showDlerrAlert(error);
        });
    }
}

// fix dlsym(RTLD_DEFAULT, bd_requestURLParameters): symbol not found
// by declearing a dummy funtion that generates trash data since it's just a user tracking function
// see https://github.com/volcengine/datarangers-sdk-ios/blob/7ca475f90be36016d35281a02b4e44b6f99f4c72/BDAutoTracker/Classes/Core/Network/BDAutoTrackNetworkRequest.m#L22
NSMutableDictionary * bd_requestURLParameters(NSString *appID) {
    NSMutableDictionary *result = [NSMutableDictionary new];
    [result setValue:@"ios" forKey:@"platform"];
    [result setValue:@"ios" forKey:@"sdk_lib"];
    [result setValue:@"iPhone" forKey:@"device_platform"];
    [result setValue:@(61002) forKey:@"sdk_version"];
    [result setValue:@"iOS" forKey:@"os"];
    [result setValue:@"18.0" forKey:@"os_version"];
    [result setValue:@"6.9.69" forKey:@"app_version"];
    [result setValue:@"iPhone14,2" forKey:@"device_model"];
    [result setValue:@(NO) forKey:@"is_upgrade_user"];
    [result setValue:@"00000000-0000-0000-0000-000000000000" forKey:@"idfa"];
    [result setValue:@"00000000-0000-0000-0000-000000000000" forKey:@"idfv"];
    [result setValue:@"6.9.69" forKey:@"version_code"];
    return result;
}
