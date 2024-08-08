@import Darwin;
#import "LCJITLessSetupViewController.h"
#import "LCUtils.h"
#import "UIKitPrivate.h"

@implementation LCJITLessSetupViewController

- (void)showDialogTitle:(NSString *)title message:(NSString *)message handler:(void(^)(UIAlertAction *))handler {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:handler];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)loadView {
    [super loadView];

    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"LiveContainer JIT-less setup";

/* TODO: support AltStore
    if (!certData) {
        certData = [LCUtils keychainItem:@"signingCertificate" ofStore:@"com.rileytestut.AltStore"];
    }
*/
    NSData *certData = [LCUtils keychainItem:@"signingCertificate" ofStore:@"com.SideStore.SideStore"];
    if (!certData) {
        [self showDialogTitle:@"Error" message:@"Failed to find certificate data. Refresh app in SideStore and try again." handler:nil];
        return;
    }
    LCUtils.certificateData = certData;

    NSData *certPassword = [LCUtils keychainItem:@"signingCertificatePassword" ofStore:@"com.SideStore.SideStore"];
    if (!certPassword) {
        [self showDialogTitle:@"Error" message:@"Failed to find certificate password" handler:nil];
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
                [self showDialogTitle:@"Error while performing signing test" message:error.localizedDescription handler:nil];
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
        [self showDialogTitle:@"Error" message:error.localizedDescription handler:nil];
        return;
    }

    if (!success) {
        [self showDialogTitle:@"Error" message:@"The test library has failed to load. This means your certificate may be having issue. LiveContainer will try to repair it. SideStore will refresh LiveContainer and then you will try again. Press OK to continue."
        handler:^(UIAlertAction * action) {
            // Erase signingCertificate
            [LCUtils deleteKeychainItem:@"signingCertificate" ofStore:@"com.rileytestut.AltStore"];
            [LCUtils deleteKeychainItem:@"signingCertificate" ofStore:@"com.SideStore.SideStore"];
            [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:@"sidestore://install?url=%@", url]] options:@{} completionHandler:nil];
        }];
        return;
    }

    [self showDialogTitle:@"Instruction" message:@"Done. Press OK to finish setting up."
    handler:^(UIAlertAction * action) {
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:@"sidestore://install?url=%@", url]] options:@{} completionHandler:nil];
    }];
}

@end
