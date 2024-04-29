#import "LCSettingsListController.h"
#import "LCUtils.h"
#import "UIViewController+LCAlert.h"

@implementation LCSettingsListController

- (NSMutableArray*)specifiers {
    if(!_specifiers) {
        _specifiers = [NSMutableArray new];
        PSSpecifier* jitlessGroup = [PSSpecifier emptyGroupSpecifier];
        jitlessGroup.name = @"JIT-less";
        [jitlessGroup setProperty:@"JIT-less allows you to use LiveContainer without having to enable JIT. Requires SideStore." forKey:@"footerText"];
        [_specifiers addObject:jitlessGroup];

        NSString *setupJITLessButtonName = LCUtils.certificateData ? @"JIT-less is set up" : @"Setup JIT-less";
        PSSpecifier* setupJITLessButton = [PSSpecifier preferenceSpecifierNamed:setupJITLessButtonName target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        setupJITLessButton.identifier = @"setup-jitless";
        [setupJITLessButton setProperty:@(!LCUtils.certificateData) forKey:@"enabled"];
        setupJITLessButton.buttonAction = @selector(setupJITLessPressed);
        [_specifiers addObject:setupJITLessButton];

        PSSpecifier* signTweaksButton = [PSSpecifier preferenceSpecifierNamed:@"Sign tweaks" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        signTweaksButton.identifier = @"sign-tweaks";
        [signTweaksButton setProperty:@(!!LCUtils.certificateData) forKey:@"enabled"];
        signTweaksButton.buttonAction = @selector(signTweaksPressed);
        [_specifiers addObject:signTweaksButton];
    }
    return _specifiers;
}

- (void)setupJITLessPressed {
    if (!LCUtils.isAppGroupSideStore) {
        [self showDialogTitle:@"Error" message:@"Unsupported installation method. Please use SideStore to setup this feature."];
        return;
    }

    NSError *error;
    NSURL *url = [LCUtils archiveIPAWithSetupMode:YES error:&error];
    if (!url) {
        [self showDialogTitle:@"Error" message:error.localizedDescription];
        return;
    }

    [UIApplication.sharedApplication openURL:[NSURL URLWithString:[NSString stringWithFormat:@"sidestore://install?url=%@", url]] options:@{} completionHandler:nil];
}

- (void)signTweaksPressed {
    
}

@end
