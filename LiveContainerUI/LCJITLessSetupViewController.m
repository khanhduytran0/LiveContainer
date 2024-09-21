@import Darwin;
#import "LCJITLessSetupViewController.h"
#import "LCUtils.h"
#import "UIKitPrivate.h"
#import "Localization.h"

@implementation LCJITLessAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    UIViewController *viewController;
    viewController = [LCJITLessSetupViewController new];
    _rootViewController = [[UINavigationController alloc] initWithRootViewController:viewController];
    _window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _window.rootViewController = _rootViewController;
    [_window makeKeyAndVisible];
    return YES;
}

@end

@implementation LCJITLessSetupViewController

- (void)showDialogTitle:(NSString *)title message:(NSString *)message handler:(void(^)(UIAlertAction *))handler {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"lc.common.ok".loc style:UIAlertActionStyleDefault handler:handler];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)loadView {
    [super loadView];

    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"lc.jitlessSetup.title".loc;

/* TODO: support AltStore */

    NSData *certData = [LCUtils keychainItem:@"signingCertificate" ofStore:@"com.SideStore.SideStore"];
    if (!certData) {
        certData = [LCUtils keychainItem:@"signingCertificate" ofStore:@"com.rileytestut.AltStore"];
    }
    if (!certData) {
        [self showDialogTitle:@"lc.common.error".loc message:@"lc.jitlessSetup.error.certDataNotFound".loc handler:nil];
        return;
    }
    LCUtils.certificateData = certData;

    NSData *certPassword = [LCUtils keychainItem:@"signingCertificatePassword".loc ofStore:@"com.SideStore.SideStore"];
    if (!certPassword) {
        [self showDialogTitle:@"lc.common.error".loc message:@"lc.jitlessSetup.error.passwordNotFound".loc handler:nil];
        return;
    }
    LCUtils.certificatePassword = [NSString stringWithUTF8String:certPassword.bytes];

    // Verify that the certificate is usable
    // Create a test app bundle
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"CertificateValidation"];
    [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *tmpExecPath = [path stringByAppendingPathComponent:@"LiveContainer.tmp"];
    NSString *tmpLibPath = [path stringByAppendingPathComponent:@"TestJITLess.dylib"];
    NSString *tmpInfoPath = [path stringByAppendingPathComponent:@"Info.plist"];
    [NSFileManager.defaultManager copyItemAtPath:NSBundle.mainBundle.executablePath toPath:tmpExecPath error:nil];
    [NSFileManager.defaultManager copyItemAtPath:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/TestJITLess.dylib"] toPath:tmpLibPath error:nil];
    NSMutableDictionary *info = NSBundle.mainBundle.infoDictionary.mutableCopy;
    info[@"CFBundleExecutable"] = @"LiveContainer.tmp";
    [info writeToFile:tmpInfoPath atomically:YES];

    // Sign the test app bundle
    [LCUtils signAppBundle:[NSURL fileURLWithPath:path]
    completionHandler:^(BOOL success, NSError *_Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!success) {
                [self showDialogTitle:@"lc.jitlessSetup.error.testFailed".loc message:error.localizedDescription handler:nil];
            } else {
                // Attempt to load the signed library
                void *handle = dlopen(tmpLibPath.UTF8String, RTLD_LAZY);
                [self validateSigningTest:(handle != NULL)];
            }
        });
    }];
}

- (void)validateSigningTest:(BOOL)loaded {
    BOOL success = loaded && getenv("LC_JITLESS_TEST_LOADED");

    NSError *error;
    NSURL *url = [LCUtils archiveIPAWithSetupMode:!success error:&error];
    if (!url) {
        [self showDialogTitle:@"lc.common.error".loc message:error.localizedDescription handler:nil];
        return;
    }

    if (!success) {
        [self showDialogTitle:@"lc.common.error".loc message:@"lc.jitlessSetup.error.testLibLoadFailed".loc
        handler:^(UIAlertAction * action) {
            // Erase signingCertificate
            [LCUtils deleteKeychainItem:@"signingCertificate" ofStore:@"com.rileytestut.AltStore"];
            [LCUtils deleteKeychainItem:@"signingCertificate" ofStore:@"com.SideStore.SideStore"];
            [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:LCUtils.storeInstallURLScheme, url]] options:@{} completionHandler:nil];
        }];
        return;
    }

    [self showDialogTitle:@"lc.common.success".loc message:@"lc.jitlessSetup.success".loc
    handler:^(UIAlertAction * action) {
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:LCUtils.storeInstallURLScheme, url]] options:@{} completionHandler:nil];
    }];
}

@end
