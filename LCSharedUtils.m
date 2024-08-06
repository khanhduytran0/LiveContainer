@import UIKit;
#import "LCUtils.h"
#import "UIKitPrivate.h"

extern NSUserDefaults *lcUserDefaults;

@implementation LCSharedUtils
+ (NSString *)certificatePassword {
    return [lcUserDefaults objectForKey:@"LCCertificatePassword"];
}

+ (BOOL)launchToGuestApp {
    NSString *urlScheme;
    NSString *tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", NSBundle.mainBundle.bundlePath];
    int tries = 1;
    if (!access(tsPath.UTF8String, F_OK)) {
        urlScheme = @"apple-magnifier://enable-jit?bundle-id=%@";
    } else if (self.certificatePassword) {
        tries = 8;
        urlScheme = @"livecontainer://livecontainer-relaunch";
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

@end
