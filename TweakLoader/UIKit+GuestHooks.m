@import UIKit;
#import "LCSharedUtils.h"
#import "UIKitPrivate.h"
#import "utils.h"

__attribute__((constructor))
static void UIKitGuestHooksInit() {
    swizzle(UIApplication.class, @selector(_applicationOpenURLAction:payload:origin:), @selector(hook__applicationOpenURLAction:payload:origin:));
    swizzle(UIScene.class, @selector(scene:didReceiveActions:fromTransitionContext:), @selector(hook_scene:didReceiveActions:fromTransitionContext:));
}

void LCShowSwitchAppConfirmation(NSURL *url) {
    if ([NSUserDefaults.lcUserDefaults boolForKey:@"LCSwitchAppWithoutAsking"]) {
        [NSClassFromString(@"LCSharedUtils") launchToGuestAppWithURL:url];
        return;
    }

    NSString *message = [NSString stringWithFormat:@"%@\nAre you sure you want to switch app? Doing so will terminate this app.", url];
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"LiveContainer" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        [NSClassFromString(@"LCSharedUtils") launchToGuestAppWithURL:url];
        window.windowScene = nil;
    }];
    [alert addAction:okAction];
    if([NSUserDefaults.lcAppUrlScheme isEqualToString:@"livecontainer"] && [UIApplication.sharedApplication canOpenURL:[NSURL URLWithString: @"livecontainer2://"]]) {
        UIAlertAction* openlc2Action = [UIAlertAction actionWithTitle:@"Open In LiveContainer2" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
            NSURLComponents* newUrlComp = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
            [newUrlComp setScheme:@"livecontainer2"];
            [UIApplication.sharedApplication openURL:[newUrlComp URL] options:@{} completionHandler:nil];
            window.windowScene = nil;
        }];
        [alert addAction:openlc2Action];
    }
    
    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
        window.windowScene = nil;
    }];
    [alert addAction:cancelAction];
    window.rootViewController = [UIViewController new];
    window.windowLevel = UIApplication.sharedApplication.windows.lastObject.windowLevel + 1;
    window.windowScene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    [window makeKeyAndVisible];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
    objc_setAssociatedObject(alert, @"window", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void openUniversalLink(NSString* decodedUrl) {
    UIActivityContinuationManager* uacm = [[UIApplication sharedApplication] _getActivityContinuationManager];
    NSUserActivity* activity = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
    activity.webpageURL = [NSURL URLWithString: decodedUrl];
    NSDictionary* dict = @{
        @"UIApplicationLaunchOptionsUserActivityKey": activity,
        @"UICanvasConnectionOptionsUserActivityKey": activity,
        @"UIApplicationLaunchOptionsUserActivityIdentifierKey": NSUUID.UUID.UUIDString,
        @"UINSUserActivitySourceApplicationKey": @"com.apple.mobilesafari",
        @"UIApplicationLaunchOptionsUserActivityTypeKey": NSUserActivityTypeBrowsingWeb,
        @"_UISceneConnectionOptionsUserActivityTypeKey": NSUserActivityTypeBrowsingWeb,
        @"_UISceneConnectionOptionsUserActivityKey": activity,
        @"UICanvasConnectionOptionsUserActivityTypeKey": NSUserActivityTypeBrowsingWeb
    };
    
    [uacm handleActivityContinuation:dict isSuspended:nil];
}

void LCOpenWebPage(NSString* webPageUrlString) {
    NSString *message = [NSString stringWithFormat:@"Are you sure you want to open the web page and launch an app? Doing so will terminate this app. You can try to open it in the current app if it supports Universal Links."];
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"LiveContainer" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        [NSClassFromString(@"LCSharedUtils") setWebPageUrlForNextLaunch:webPageUrlString];
        [NSClassFromString(@"LCSharedUtils") launchToGuestApp];
    }];
    [alert addAction:okAction];
    UIAlertAction* openNowAction = [UIAlertAction actionWithTitle:@"Current App" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        openUniversalLink(webPageUrlString);
        window.windowScene = nil;
    }];
    if([NSUserDefaults.lcAppUrlScheme isEqualToString:@"livecontainer"] && [UIApplication.sharedApplication canOpenURL:[NSURL URLWithString: @"livecontainer2://"]]) {
        UIAlertAction* openlc2Action = [UIAlertAction actionWithTitle:@"Open In LiveContainer2" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
            NSURLComponents* newUrlComp = [NSURLComponents componentsWithString:webPageUrlString];
            [newUrlComp setScheme:@"livecontainer2"];
            [UIApplication.sharedApplication openURL:[newUrlComp URL] options:@{} completionHandler:nil];
            window.windowScene = nil;
        }];
        [alert addAction:openlc2Action];
    }
    
    [alert addAction:openNowAction];
    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
        window.windowScene = nil;
    }];
    [alert addAction:cancelAction];
    window.rootViewController = [UIViewController new];
    window.windowLevel = UIApplication.sharedApplication.windows.lastObject.windowLevel + 1;
    window.windowScene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    [window makeKeyAndVisible];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
    objc_setAssociatedObject(alert, @"window", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    

}

// Handler for AppDelegate
@implementation UIApplication(LiveContainerHook)
- (void)hook__applicationOpenURLAction:(id)action payload:(NSDictionary *)payload origin:(id)origin {
    NSString *url = payload[UIApplicationLaunchOptionsURLKey];
    if ([url hasPrefix:[NSString stringWithFormat: @"%@://livecontainer-relaunch", NSUserDefaults.lcAppUrlScheme]]) {
        // Ignore
        return;
    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://open-web-page?", NSUserDefaults.lcAppUrlScheme]]) {
        // launch to UI and open web page
        NSURLComponents* lcUrl = [NSURLComponents componentsWithString:url];
        NSString* realUrlEncoded = lcUrl.queryItems[0].value;
        if(!realUrlEncoded) return;
        // Convert the base64 encoded url into String
        NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:realUrlEncoded options:0];
        NSString *decodedUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        LCOpenWebPage(decodedUrl);
        return;
    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://open-url", NSUserDefaults.lcAppUrlScheme]]) {
        // pass url to guest app
        NSURLComponents* lcUrl = [NSURLComponents componentsWithString:url];
        NSString* realUrlEncoded = lcUrl.queryItems[0].value;
        if(!realUrlEncoded) return;
        // Convert the base64 encoded url into String
        NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:realUrlEncoded options:0];
        NSString *decodedUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        // it's a Universal link, let's call -[UIActivityContinuationManager handleActivityContinuation:isSuspended:]
        if([decodedUrl hasPrefix:@"https"]) {
            openUniversalLink(decodedUrl);
        } else {
            NSMutableDictionary* newPayload = [payload mutableCopy];
            newPayload[UIApplicationLaunchOptionsURLKey] = decodedUrl;
            [self hook__applicationOpenURLAction:action payload:newPayload origin:origin];
        }
        
        return;
    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://livecontainer-launch?", NSUserDefaults.lcAppUrlScheme]]) {
        if (![url hasSuffix:NSBundle.mainBundle.bundlePath.lastPathComponent]) {
            LCShowSwitchAppConfirmation([NSURL URLWithString:url]);
        }
        return;
        // Not what we're looking for, pass it
        
    }
    [self hook__applicationOpenURLAction:action payload:payload origin:origin];
    return;
}
@end

// Handler for SceneDelegate
@implementation UIScene(LiveContainerHook)
- (void)hook_scene:(id)scene didReceiveActions:(NSSet *)actions fromTransitionContext:(id)context {
    UIOpenURLAction *urlAction = nil;
    for (id obj in actions.allObjects) {
        if ([obj isKindOfClass:UIOpenURLAction.class]) {
            urlAction = obj;
            break;
        }
    }

    // Don't have UIOpenURLAction? pass it
    if (!urlAction) {
        [self hook_scene:scene didReceiveActions:actions fromTransitionContext:context];
        return;
    }

    NSString *url = urlAction.url.absoluteString;
    if ([url hasPrefix:[NSString stringWithFormat: @"%@://livecontainer-relaunch", NSUserDefaults.lcAppUrlScheme]]) {
        // Ignore
        return;
    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://open-web-page?", NSUserDefaults.lcAppUrlScheme]]) {
        NSURLComponents* lcUrl = [NSURLComponents componentsWithString:url];
        NSString* realUrlEncoded = lcUrl.queryItems[0].value;
        if(!realUrlEncoded) return;
        // launch to UI and open web page
        NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:realUrlEncoded options:0];
        NSString *decodedUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        LCOpenWebPage(decodedUrl);
        return;
    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://open-url", NSUserDefaults.lcAppUrlScheme]]) {
        // Open guest app's URL scheme
        NSURLComponents* lcUrl = [NSURLComponents componentsWithString:url];
        NSString* realUrlEncoded = lcUrl.queryItems[0].value;
        if(!realUrlEncoded) return;
        // Convert the base64 encoded url into String
        NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:realUrlEncoded options:0];
        NSString *decodedUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        
        // it's a Universal link, let's call -[UIActivityContinuationManager handleActivityContinuation:isSuspended:]
        if([decodedUrl hasPrefix:@"https"]) {
            openUniversalLink(decodedUrl);
        } else {
            NSMutableSet *newActions = actions.mutableCopy;
            [newActions removeObject:urlAction];
            UIOpenURLAction *newUrlAction = [[UIOpenURLAction alloc] initWithURL:[NSURL URLWithString:decodedUrl]];
            [newActions addObject:newUrlAction];
            [self hook_scene:scene didReceiveActions:newActions fromTransitionContext:context];
        }

        return;
    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://livecontainer-launch?", NSUserDefaults.lcAppUrlScheme]]){
        // If it's not current app, then switch
        if (![url hasSuffix:NSBundle.mainBundle.bundlePath.lastPathComponent]) {
            LCShowSwitchAppConfirmation(urlAction.url);
        }
        return;
        
    }

    NSMutableSet *newActions = actions.mutableCopy;
    [newActions removeObject:urlAction];
    [self hook_scene:scene didReceiveActions:newActions fromTransitionContext:context];
}
@end
