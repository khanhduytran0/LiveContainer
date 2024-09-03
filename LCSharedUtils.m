#import "LCSharedUtils.h"
#import "UIKitPrivate.h"

extern NSUserDefaults *lcUserDefaults;
extern NSString *lcAppUrlScheme;

@implementation LCSharedUtils

+ (NSString *)appGroupID {
    static dispatch_once_t once;
    static NSString *appGroupID;
    dispatch_once(&once, ^{
        for (NSString *group in NSBundle.mainBundle.infoDictionary[@"ALTAppGroups"]) {
            NSURL *path = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group];
            NSURL *bundlePath = [path URLByAppendingPathComponent:@"Apps/com.kdt.livecontainer/App.app"];
            if ([NSFileManager.defaultManager fileExistsAtPath:bundlePath.path]) {
                // This will fail if LiveContainer is installed in both stores, but it should never be the case
                appGroupID = group;
                return;
            }
        }
    });
    return appGroupID;
}

+ (NSString *)certificatePassword {
    NSString* ans = [lcUserDefaults objectForKey:@"LCCertificatePassword"];
    if(ans) {
        return ans;
    } else {
        return [[[NSUserDefaults alloc] initWithSuiteName:[self appGroupID]] objectForKey:@"LCCertificatePassword"];
    }
}

+ (BOOL)launchToGuestApp {
    NSString *urlScheme;
    NSString *tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", NSBundle.mainBundle.bundlePath];
    int tries = 1;
    if (!access(tsPath.UTF8String, F_OK)) {
        urlScheme = @"apple-magnifier://enable-jit?bundle-id=%@";
    } else if (self.certificatePassword) {
        tries = 8;
        urlScheme = [NSString stringWithFormat:@"%@://livecontainer-relaunch", lcAppUrlScheme];
    } else {
        urlScheme = @"sidestore://sidejit-enable?bid=%@";
    }
    NSURL *launchURL = [NSURL URLWithString:[NSString stringWithFormat:urlScheme, NSBundle.mainBundle.bundleIdentifier]];
    if ([UIApplication.sharedApplication canOpenURL:launchURL]) {
        //[UIApplication.sharedApplication suspend];
        for (int i = 0; i < tries; i++) {
        [UIApplication.sharedApplication openURL:launchURL options:@{} completionHandler:^(BOOL b) {
            exit(0);
        }];
        }
        return YES;
    }
    return NO;
}

+ (BOOL)launchToGuestAppWithURL:(NSURL *)url {
    NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if(![components.host isEqualToString:@"livecontainer-launch"]) return NO;

    for (NSURLQueryItem* queryItem in components.queryItems) {
        if ([queryItem.name isEqualToString:@"bundle-name"]) {
            [lcUserDefaults setObject:queryItem.value forKey:@"selected"];

            // Attempt to restart LiveContainer with the selected guest app
            return [self launchToGuestApp];
            break;
        }
    }
    return NO;
}

+ (void)setWebPageUrlForNextLaunch:(NSString*) urlString {
    [lcUserDefaults setObject:urlString forKey:@"webPageToOpen"];
}

@end
