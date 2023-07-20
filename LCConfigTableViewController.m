#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "LCConfigTableViewController.h"
#import "UIKitPrivate.h"
#import "utils.h"

@interface LCConfigTableViewController()<UIContextMenuInteractionDelegate>{}
@property(nonatomic) UIMenu* currentMenu;

@end

@implementation LCConfigTableViewController

- (id)init {
    self = [super init];
    [self initViewCreation];
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    if (self.prefSections) {
        self.prefSectionsVisibility = [[NSMutableArray<NSNumber *> alloc] initWithCapacity:self.prefSections.count];
        for (int i = 0; i < self.prefSections.count; i++) {
            [self.prefSectionsVisibility addObject:@(self.prefSectionsVisible)];
        }
    } else {
        // Display one singe section if prefSection is unspecified
        self.prefSectionsVisibility = (id)@[@YES];
    }
}

#pragma mark UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.prefSectionsVisibility.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.prefSectionsVisibility[section].boolValue) {
        return self.prefContents[section].count;
    }
    return 1;
}

- (UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.prefContents[indexPath.section][indexPath.row];

    NSString *cellID;
    UITableViewCellStyle cellStyle;
    if (item[@"type"] == self.typeChildPane || item[@"type"] == self.typePickField) {
        cellID = @"cellValue1";
        cellStyle = UITableViewCellStyleValue1;
    } else {
        cellID = @"cellSubtitle";
        cellStyle = UITableViewCellStyleSubtitle;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:cellStyle reuseIdentifier:cellID];
        cell.textLabel.adjustsFontSizeToFitWidth = YES;
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    }
    // Reset cell properties, as it could be reused
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.textColor = nil;
    cell.detailTextLabel.text = nil;

    NSString *key = item[@"key"];
    if (indexPath.row == 0 && self.prefSections) {
        key = self.prefSections[indexPath.section];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.textLabel.text = key;
    } else {
        CreateView createView = item[@"type"];
        createView(cell, self.prefSections[indexPath.section], key, item);
        if (cell.accessoryView) {
            objc_setAssociatedObject(cell.accessoryView, @"section", self.prefSections[indexPath.section], OBJC_ASSOCIATION_ASSIGN);
            objc_setAssociatedObject(cell.accessoryView, @"key", key, OBJC_ASSOCIATION_ASSIGN);
            objc_setAssociatedObject(cell.accessoryView, @"item", item, OBJC_ASSOCIATION_ASSIGN);
        }
        cell.textLabel.text = item[@"title"];
    }

    // Set general properties
    BOOL destructive = [item[@"destructive"] boolValue];
    cell.imageView.tintColor = destructive ? UIColor.systemRedColor : nil;
    cell.imageView.image = [UIImage systemImageNamed:item[@"icon"]];

    // Check if one has enable condition and call if it does
    BOOL(^checkEnable)(void) = item[@"enableCondition"];
    cell.userInteractionEnabled = !checkEnable || checkEnable();
    cell.textLabel.enabled = cell.detailTextLabel.enabled = cell.userInteractionEnabled;
    [(id)cell.accessoryView setEnabled:cell.userInteractionEnabled];

    return cell;
}

#pragma mark initViewCreation, showAlert

- (void)initViewCreation {
    __weak LCConfigTableViewController *weakSelf = self;

    self.typeButton = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item) {
        BOOL destructive = [item[@"destructive"] boolValue];
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
        cell.textLabel.textColor = destructive ? UIColor.systemRedColor : weakSelf.view.tintColor;
    };

    self.typeChildPane = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
        cell.detailTextLabel.text = weakSelf.getPreference(section, key);
    };

    self.typeTextField = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item) {
        UITextField *view = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, cell.bounds.size.width / 2.1, cell.bounds.size.height)];
        [view addTarget:view action:@selector(resignFirstResponder) forControlEvents:UIControlEventEditingDidEndOnExit];
        view.adjustsFontSizeToFitWidth = YES;
        view.autocorrectionType = UITextAutocorrectionTypeNo;
        view.autocapitalizationType = UITextAutocapitalizationTypeNone;
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin;
        //view.contentVerticalAlignment = UIControlContentVerticalAlignmentTop;
        view.delegate = weakSelf;
        //view.nonEditingLinebreakMode = NSLineBreakByCharWrapping;
        view.returnKeyType = UIReturnKeyDone;
        view.textAlignment = NSTextAlignmentRight;
        view.placeholder = item[@"placeholder"];
        view.text = weakSelf.getPreference(section, key);
        cell.accessoryView = view;
    };

    self.typePickField = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
        cell.detailTextLabel.text = weakSelf.getPreference(section, key);
    };

    self.typeSwitch = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item) {
        UISwitch *view = [[UISwitch alloc] init];
        NSArray *customSwitchValue = item[@"customSwitchValue"];
        if (customSwitchValue == nil) {
            [view setOn:[weakSelf.getPreference(section, key) boolValue] animated:NO];
        } else {
            [view setOn:[weakSelf.getPreference(section, key) isEqualToString:customSwitchValue[1]] animated:NO];
        }
        [view addTarget:weakSelf action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = view;
    };
}

- (void)showAlertOnView:(UIView *)view title:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleActionSheet];
    alert.popoverPresentationController.sourceView = view;
    alert.popoverPresentationController.sourceRect = view.bounds;
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:ok];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark Control event handlers

- (void)switchChanged:(UISwitch *)sender {
    NSDictionary *item = objc_getAssociatedObject(sender, @"item");
    NSString *section = objc_getAssociatedObject(sender, @"section");
    NSString *key = item[@"key"];

    // Special switches may define custom value instead of NO/YES
    NSArray *customSwitchValue = item[@"customSwitchValue"];
    self.setPreference(section, key, customSwitchValue ?
        customSwitchValue[sender.isOn] : @(sender.isOn));

    void(^invokeAction)(BOOL) = item[@"action"];
    if (invokeAction) {
        invokeAction(sender.isOn);
    }

    // Some settings may affect the availability of other settings
    // In this case, a switch may request to reload to apply user interaction change
    if ([item[@"requestReload"] boolValue]) {
        // TODO: only reload needed rows
        [self.tableView reloadData];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    if (indexPath.row == 0 && self.prefSections) {
        self.prefSectionsVisibility[indexPath.section] = @(![self.prefSectionsVisibility[indexPath.section] boolValue]);
        [tableView reloadSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:UITableViewRowAnimationFade];
        return;
    }

    NSDictionary *item = self.prefContents[indexPath.section][indexPath.row];

    if (item[@"type"] == self.typeButton) {
        [self tableView:tableView invokeActionAtIndexPath:indexPath];
        return;
    } else if (item[@"type"] == self.typeChildPane) {
        [self tableView:tableView openChildPaneAtIndexPath:indexPath];
        return;
    } else if (item[@"type"] == self.typePickField) {
        [self tableView:tableView openPickerAtIndexPath:indexPath];
        return;
    }

    // userInterfaceIdiom = tvOS
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (item[@"type"] == self.typeSwitch) {
        UISwitch *view = (id)cell.accessoryView;
        view.on = !view.isOn;
        [view sendActionsForControlEvents:UIControlEventValueChanged];
    }
}

#pragma mark External UITableView functions

- (void)tableView:(UITableView *)tableView openChildPaneAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.prefContents[indexPath.section][indexPath.row];
    UIViewController *vc = [item[@"class"] new];
    if ([item[@"canDismissWithSwipe"] boolValue]) {
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.navigationBar.prefersLargeTitles = YES;
        nav.modalInPresentation = YES;
        [self.navigationController presentViewController:nav animated:YES completion:nil];
    }
}

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location
{
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        return self.currentMenu;
    }];
}

- (_UIContextMenuStyle *)_contextMenuInteraction:(UIContextMenuInteraction *)interaction styleForMenuWithConfiguration:(UIContextMenuConfiguration *)configuration
{
    _UIContextMenuStyle *style = [_UIContextMenuStyle defaultStyle];
    style.preferredLayout = 3; // _UIContextMenuLayoutCompactMenu
    return style;
}

- (void)tableView:(UITableView *)tableView openPickerAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    NSDictionary *item = self.prefContents[indexPath.section][indexPath.row];

    NSArray *pickKeys = item[@"pickKeys"];
    NSArray *pickList = item[@"pickList"];
    NSMutableArray *menuItems = [[NSMutableArray alloc] init];
    for (int i = 0; i < pickList.count; i++) {
        BOOL selected = [cell.detailTextLabel.text isEqualToString:pickKeys[i]];
        [menuItems addObject:[UIAction
            actionWithTitle:pickList[i]
            image:(selected ? [UIImage systemImageNamed:@"checkmark"] : nil)
            identifier:nil
            handler:^(UIAction *action) {
                cell.detailTextLabel.text = pickKeys[i];
                self.setPreference(self.prefSections[indexPath.section], item[@"key"], pickKeys[i]);
                void(^invokeAction)(NSString *) = item[@"action"];
                if (invokeAction) {
                    invokeAction(pickKeys[i]);
                }
            }]];
    }

    self.currentMenu = [UIMenu menuWithTitle:@"" children:menuItems];
    UIContextMenuInteraction *interaction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
    cell.detailTextLabel.interactions = @[interaction];
    [interaction _presentMenuAtLocation:CGPointZero];
}

- (void)tableView:(UITableView *)tableView invokeActionAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.prefContents[indexPath.section][indexPath.row];
    void(^invokeAction)(void) = item[@"action"];
    if (invokeAction) {
        invokeAction();
    }
}

#pragma mark UITextField

- (void)textFieldDidEndEditing:(UITextField *)sender {
    NSString *section = objc_getAssociatedObject(sender, @"section");
    NSString *key = objc_getAssociatedObject(sender, @"key");

    self.setPreference(section, key, sender.text);
}

@end
