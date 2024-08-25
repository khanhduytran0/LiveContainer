#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
@interface LCSwiftBridge : NSObject
+ (UIViewController * _Nonnull)getRootVC;
+ (void)openWebPageWithUrlStr:(NSString*  _Nonnull)urlStr;
@end

@interface LCAppDelegateSwiftUI : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow * _Nullable window;
@property (nonatomic, strong) UIViewController * _Nonnull rootViewController;

@end
