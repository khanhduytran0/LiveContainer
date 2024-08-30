#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "LCAppInfo.h"

@interface LCWebView : UIViewController <WKNavigationDelegate>
- (instancetype)initWithURL:(NSURL *)url apps:(NSMutableArray<LCAppInfo*>*)apps;
- (void)askIfLaunchApp:(NSString*)appId url:(NSURL*)launchUrl;
@property (nonatomic) NSURL *url;
@property (nonatomic) NSMutableArray<LCAppInfo*>* apps;
@property (strong, nonatomic) WKWebView *webView;
@end
