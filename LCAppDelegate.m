#import "LCAppDelegate.h"
#import "LCRootViewController.h"

@implementation LCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
   LCRootViewController *viewController = [[LCRootViewController alloc] init];
    _window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _rootViewController = [[UINavigationController alloc] initWithRootViewController:viewController];
    _window.rootViewController = _rootViewController;
    [_window makeKeyAndVisible];
    return YES;
}

@end
