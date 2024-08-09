#import "LCSettingsListController.h"
#import "LCUtils.h"
#import "UIViewController+LCAlert.h"

@implementation LCSettingsListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self bundle:NSBundle.mainBundle];
    }

    return _specifiers;
}

- (void)loadView {
    [super loadView];
    NSString *setupJITLessButtonName = LCUtils.certificatePassword ? @"Renew JIT-less certificate" : @"Setup JIT-less certificate";
    PSSpecifier *setupJITLessButton = [self specifierForID:@"setup-jitless"];
    setupJITLessButton.name = setupJITLessButtonName;
}

- (void)setupJITLessPressed {
    if (!LCUtils.isAppGroupAltStoreLike) {
        [self showDialogTitle:@"Error" message:@"Unsupported installation method. Please use AltStore or SideStore to setup this feature."];
        return;
    }

    NSError *error;
    NSURL *url = [LCUtils archiveIPAWithSetupMode:YES error:&error];
    if (!url) {
        [self showDialogTitle:@"Error" message:error.localizedDescription];
        return;
    }

    [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:LCUtils.storeInstallURLScheme, url]] options:@{} completionHandler:nil];
}

- (void)copyAppGroupPathPressed {
    UIPasteboard.generalPasteboard.string = LCUtils.appGroupPath;
}

- (void)copyDocumentsPathPressed {
    UIPasteboard.generalPasteboard.string = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject.path;
}

- (void)openSourceCode {
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://github.com/khanhduytran0/LiveContainer"] options:@{} completionHandler:nil];
}

- (void)openTwitter {
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://twitter.com/TranKha50277352"] options:@{} completionHandler:nil];
}

@end
