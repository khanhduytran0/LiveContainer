//
//  LCWebview.m
//  jump
//
//  Created by s s on 2024/8/18.
//


#import "LCWebView.h"
#import "LCUtils.h"

@interface MySchemeHandler : NSObject<WKURLSchemeHandler>
- (instancetype)initWithApp:(NSString*)appId viewController:(LCWebView*)lcController;
@property NSString* appId;
@property LCWebView* lcController;
@end

@implementation MySchemeHandler

- (instancetype)initWithApp:(NSString*)appId viewController:(LCWebView*)lcController{
    self = [super init];
    self.appId = appId;
    self.lcController = lcController;
    return self;
}

- (void)webView:(nonnull WKWebView *)webView startURLSchemeTask:(nonnull id<WKURLSchemeTask>)urlSchemeTask {
    [self.lcController askIfLaunchApp:self.appId url: urlSchemeTask.request.URL];
}

- (void)webView:(nonnull WKWebView *)webView stopURLSchemeTask:(nonnull id<WKURLSchemeTask>)urlSchemeTask {
    NSLog(@"stopURLScheme");
}

@end



@implementation LCWebView

- (instancetype)initWithURL:(NSURL *)url apps:(NSMutableArray<LCAppInfo*>*)apps {
    self = [super init];  // Call the superclass's init method
    if (self) {
        self.apps = apps;
        self.url = url;  // Store the URL string
        
    }
    return self;
}


- (void)viewDidLoad {
    [super viewDidLoad];
    
    if (!self.webView.superview) {
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        

        CGRect webViewSize = self.view.bounds;
        webViewSize.size.height -= self.navigationController.navigationBar.frame.size.height;
        webViewSize.size.height -= [self.view.window.windowScene.statusBarManager statusBarFrame].size.height;
        webViewSize.size.height -= 30;
        self.webView = [[WKWebView alloc] initWithFrame:webViewSize configuration:config];
        self.webView.navigationDelegate = self;
        self.webView.customUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_6_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1";
        [self.view addSubview:self.webView];
    }
    UIBarButtonItem *backButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"chevron.backward"] style:UIBarButtonItemStylePlain target:self action:@selector(goBack)];
    UIBarButtonItem *forwardButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"chevron.forward"] style:UIBarButtonItemStylePlain target:self action:@selector(goForward)];
    self.navigationItem.leftBarButtonItems = @[backButton, forwardButton];
    
    // Add a refresh button on the right
    UIBarButtonItem *refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadWebView)];
    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItems = @[closeButton, refreshButton];
    
    // Load the webpage passed via the initializer
    if (self.url) {
        NSURLRequest *request = [NSURLRequest requestWithURL:self.url];
        [self.webView loadRequest:request];
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.title = webView.title;
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    // use private API, get rid of Universal link
    decisionHandler((WKNavigationActionPolicy)(WKNavigationActionPolicyAllow + 2));
    NSString* scheme = navigationAction.request.URL.scheme;
    if([scheme length] == 0 || [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"about"] || [scheme isEqualToString:@"itms-appss"]) {
        return;
    }
    // add a unique urlHandler for each app
    LCAppInfo* appToOpen = nil;
    for(int i = 0; i < [self.apps count] && !appToOpen; ++i) {
        LCAppInfo* nowAppInfo = self.apps[i];
        NSMutableArray* schemes = [nowAppInfo urlSchemes];
        if(!schemes) continue;
        for(int j = 0; j < [schemes count]; ++j) {
            if([scheme isEqualToString:schemes[j]]) {
                appToOpen = nowAppInfo;
                break;
            }
        }
    }
    if(!appToOpen){
        return;
    }
    [self askIfLaunchApp:appToOpen.relativeBundlePath url:navigationAction.request.URL];
}

- (void)goBack {
    if ([self.webView canGoBack]) {
        [self.webView goBack];
    }
}

- (void)goForward {
    if ([self.webView canGoForward]) {
        [self.webView goForward];
    }
}

- (void)reloadWebView {
    [self.webView reload];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)askIfLaunchApp:(NSString*)appId url:(NSURL*)launchUrl {
    NSString* message = [NSString stringWithFormat:@"This web page is trying to launch %@, continue?", appId];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"LiveContainer" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        [NSUserDefaults.standardUserDefaults setObject:appId forKey:@"selected"];
        [NSUserDefaults.standardUserDefaults setObject:launchUrl.absoluteString forKey:@"launchAppUrlScheme"];
        if ([LCUtils launchToGuestApp]) return;
    }];
    [alert addAction:okAction];
    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
        
    }];
    [alert addAction:cancelAction];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
