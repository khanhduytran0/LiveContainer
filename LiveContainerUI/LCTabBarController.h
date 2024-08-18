#import <UIKit/UIKit.h>
#import "LCAppListViewController.h"

@interface LCTabBarController : UITabBarController
@property() LCAppListViewController* appTableVC;
- (void) openWebPage:(NSString*) urlString;
@end
