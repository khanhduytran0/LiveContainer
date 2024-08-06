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
        [self showDialogTitle:@"Error" message:@"Failed to find certificate data" handler:nil];
        return;
    }
    LCUtils.certificateData = certData;

    NSData *certPassword = [LCUtils keychainItem:@"signingCertificatePassword" ofStore:@"com.SideStore.SideStore"];
    if (!certPassword) {
        [self showDialogTitle:@"Error" message:@"Failed to find certificate password" handler:nil];
        return;
    }
    LCUtils.certificatePassword = [NSString stringWithUTF8String:certPassword.bytes];

    NSError *error;
    NSURL *url = [LCUtils archiveIPAWithSetupMode:NO error:&error];
    if (!url) {
        [self showDialogTitle:@"Error" message:error.localizedDescription handler:nil];
        return;
    }

    [self showDialogTitle:@"Instruction" message:@"Done. Press OK to finish setting up."
    handler:^(UIAlertAction * action) {
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:@"sidestore://install?url=%@", url]] options:@{} completionHandler:nil];
    }];
}

@end
