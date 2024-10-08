#import "LCAppDelegate.h"
#import "LCJITLessSetupViewController.h"
#import "LCTabBarController.h"
#import "LCUtils.h"
#import <UIKit/UIKit.h>

@implementation LCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    UIViewController *viewController;
    if ([NSBundle.mainBundle.executablePath.lastPathComponent isEqualToString:@"JITLessSetup"]) {
        viewController = [LCJITLessSetupViewController new];
        _rootViewController = [[UINavigationController alloc] initWithRootViewController:viewController];
    } else {
        _rootViewController = [LCTabBarController new];
    }
    _window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _window.rootViewController = _rootViewController;
    [_window makeKeyAndVisible];
    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    // handle page open request from URL scheme
    if([url.host isEqualToString:@"open-web-page"]) {
        NSURLComponents* urlComponent = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        if(urlComponent.queryItems.count == 0){
            return YES;
        }
        
        NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:urlComponent.queryItems[0].value options:0];
        NSString *decodedUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        [((LCTabBarController*)_rootViewController) openWebPage:decodedUrl];
    }
    return [LCUtils launchToGuestAppWithURL:url];
}

@end
