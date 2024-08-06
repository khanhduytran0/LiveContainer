#import "LCAppListViewController.h"
#import "LCSettingsListController.h"
#import "LCTabBarController.h"

@implementation LCTabBarController

- (void)loadView {
    [super loadView];

    LCAppListViewController* appTableVC = [LCAppListViewController new];
    appTableVC.title = @"Apps";

    LCSettingsListController* settingsListVC = [LCSettingsListController new];
    settingsListVC.title = @"Settings";

    UINavigationController* appNavigationController = [[UINavigationController alloc] initWithRootViewController:appTableVC];
    UINavigationController* settingsNavigationController = [[UINavigationController alloc] initWithRootViewController:settingsListVC];
	
    appNavigationController.tabBarItem.image = [UIImage systemImageNamed:@"square.stack.3d.up.fill"];
    settingsNavigationController.tabBarItem.image = [UIImage systemImageNamed:@"gear"];

    self.viewControllers = @[appNavigationController, settingsNavigationController];
}

@end
