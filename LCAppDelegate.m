#import "LCAppDelegate.h"
#import "LCJITLessSetupViewController.h"
#import "LCRootViewController.h"

@implementation LCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    UIViewController *viewController;
    if ([NSBundle.mainBundle.executablePath.lastPathComponent isEqualToString:@"JITLessSetup"]) {
        viewController = [[LCJITLessSetupViewController alloc] init];
    } else {
        viewController = [[LCRootViewController alloc] init];
    }
    _window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _rootViewController = [[UINavigationController alloc] initWithRootViewController:viewController];
    _window.rootViewController = _rootViewController;
    [_window makeKeyAndVisible];
    return YES;
}

@end
