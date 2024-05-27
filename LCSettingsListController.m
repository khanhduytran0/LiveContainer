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

        NSString *setupJITLessButtonName = LCUtils.certificateData ? @"Renew JIT-less certificate" : @"Setup JIT-less certificate";
        PSSpecifier* setupJITLessButton = [PSSpecifier preferenceSpecifierNamed:setupJITLessButtonName target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        setupJITLessButton.identifier = @"setup-jitless";
        setupJITLessButton.buttonAction = @selector(setupJITLessPressed);
        [_specifiers addObject:setupJITLessButton];

        PSSpecifier* signTweaksButton = [PSSpecifier preferenceSpecifierNamed:@"Sign tweaks" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        signTweaksButton.identifier = @"sign-tweaks";
        [signTweaksButton setProperty:@(!!LCUtils.certificateData) forKey:@"enabled"];
        signTweaksButton.buttonAction = @selector(signTweaksPressed);
        [_specifiers addObject:signTweaksButton];
        
        PSSpecifier* addToHomeScreenGroup = [PSSpecifier emptyGroupSpecifier];
        addToHomeScreenGroup.name = @"Helper Shortcut";
        [addToHomeScreenGroup setProperty:@"The helper shortcut allows you to add apps from LiveContainer to your homescreen. Requires Apple Shortcuts." forKey:@"footerText"];
        [_specifiers addObject:addToHomeScreenGroup];
        
        NSString *setupHelperShortcutButtonName = [[NSUserDefaults.standardUserDefaults stringForKey:@"shortcutAdded"] isEqualToString:@"true"] ? @"Reinstall Helper Shortcut" : @"Install Helper Shortcut";
        PSSpecifier* setupHelperShortcutButton = [PSSpecifier preferenceSpecifierNamed:setupHelperShortcutButtonName target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        setupHelperShortcutButton.identifier = @"setup-helper-shortcut";
        setupHelperShortcutButton.buttonAction = @selector(setupHelperShortcutPressed);
        [_specifiers addObject:setupHelperShortcutButton];
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

- (void)setupHelperShortcutPressed {
    NSURL *url = [NSURL URLWithString:@"https://www.icloud.com/shortcuts/df529a91277542e180dda2a00a2a9cab"];
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler: ^(BOOL b) {
        [NSUserDefaults.standardUserDefaults setObject:@"true" forKey:@"shortcutAdded"];
        exit(0);
    }];
}

- (void)signTweaksPressed {
    
}

@end
