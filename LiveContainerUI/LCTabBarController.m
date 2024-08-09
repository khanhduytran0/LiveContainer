#import "LCAppListViewController.h"
#import "LCSettingsListController.h"
#import "LCTweakListViewController.h"
#import "LCTabBarController.h"

@implementation LCTabBarController

- (void)loadView {
    [super loadView];

    LCAppListViewController* appTableVC = [LCAppListViewController new];
    appTableVC.title = @"Apps";

    LCTweakListViewController* tweakTableVC = [LCTweakListViewController new];
    tweakTableVC.title = @"Tweaks";

    LCSettingsListController* settingsListVC = [LCSettingsListController new];
    settingsListVC.title = @"Settings";

    UINavigationController* appNavigationController = [[UINavigationController alloc] initWithRootViewController:appTableVC];
    UINavigationController* tweakNavigationController = [[UINavigationController alloc] initWithRootViewController:tweakTableVC];
    UINavigationController* settingsNavigationController = [[UINavigationController alloc] initWithRootViewController:settingsListVC];

    appNavigationController.tabBarItem.image = [UIImage systemImageNamed:@"square.stack.3d.up.fill"];
    tweakNavigationController.tabBarItem.image = [UIImage systemImageNamed:@"wrench.and.screwdriver"];
    settingsNavigationController.tabBarItem.image = [UIImage systemImageNamed:@"gear"];

    self.viewControllers = @[appNavigationController, tweakNavigationController, settingsNavigationController];
}

@end
