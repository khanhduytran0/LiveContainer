@import UniformTypeIdentifiers;

#import "LCTweakListViewController.h"
#import "LCUtils.h"
#import "MBRoundProgressView.h"
#import "UIKitPrivate.h"
#import "UIViewController+LCAlert.h"

@interface LCTweakListViewController()
@property(nonatomic) NSString *path;
@property(nonatomic) NSMutableArray *objects;

@property(nonatomic) UIButton *signButton;
@property(nonatomic) MBRoundProgressView *progressView;
@end

@implementation LCTweakListViewController

- (void)loadView {
    [super loadView];

    if (!self.path) {
        NSString *docPath = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject.path;
        self.path = [docPath stringByAppendingPathComponent:@"Tweaks"];
    }
    [self loadPath];

    UIMenu *addMenu = [UIMenu menuWithTitle:@"" image:nil identifier:nil
    options:UIMenuOptionsDisplayInline
    children:@[
        [UIAction
            actionWithTitle:@"Tweak"
            image:[UIImage systemImageNamed:@"doc"]
            identifier:nil handler:^(UIAction *action) {
                [self addDylibButtonTapped];
            }],
        [UIAction
            actionWithTitle:@"Folder"
            image:[UIImage systemImageNamed:@"folder"]
            identifier:nil handler:^(UIAction *action) {
                [self addFolderButtonTapped];
            }]
    ]];

    self.signButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.signButton.enabled = !!LCUtils.certificatePassword;
    self.signButton.frame = CGRectMake(0, 0, 40, 40);
    [self.signButton setImage:[UIImage systemImageNamed:@"signature"] forState:UIControlStateNormal];
    [self.signButton addTarget:self action:@selector(signTweaksButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.progressView = [MBRoundProgressView new];
    self.progressView.hidden = YES;
    [self.signButton addSubview:self.progressView];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd menu:addMenu],
        [[UIBarButtonItem alloc] initWithCustomView:self.signButton]
    ];

    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(loadPath) forControlEvents:UIControlEventValueChanged];
}

- (void)loadPath {
    self.title = self.path.lastPathComponent;
    BOOL reload = self.objects != nil;

    NSMutableArray *directories = [NSMutableArray new];
    NSArray *files = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:self.path error:nil] filteredArrayUsingPredicate:
    [NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *bindings) {
        BOOL isDir;
        NSString *path = [self.path stringByAppendingPathComponent:name];
        [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir];
        if (isDir) {
            [directories addObject:name];
        }
        return !isDir && [name hasSuffix:@".dylib"];
    }]];

    self.objects = [NSMutableArray new];
    [self.objects addObjectsFromArray:[directories sortedArrayUsingSelector:@selector(compare:)]];
    [self.objects addObjectsFromArray:[files sortedArrayUsingSelector:@selector(compare:)]];

    if (reload) {
        [self.tableView reloadData];
        [self.refreshControl endRefreshing];
    }
}

- (void)addDylibButtonTapped {
    UIDocumentPickerViewController *documentPickerVC = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[[UTType typeWithFilenameExtension:@"dylib" conformingToType:UTTypeData]]
        asCopy:YES];
    documentPickerVC.allowsMultipleSelection = YES;
    documentPickerVC.delegate = self;
    [self presentViewController:documentPickerVC animated:YES completion:nil];
}

- (void)addFolderButtonTapped {
    [self showInputDialogTitle:@"Add folder" message:@"Enter name" placeholder:@"Name" callback:^(NSString *name) {
        NSError *error;
        NSString *path = [self.path stringByAppendingPathComponent:name];
        [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:NO attributes:@{} error:&error];
        [self loadPath];
        return error.localizedDescription;
    }];
}

- (void)signTweaksButtonTapped {
    [self showConfirmationDialogTitle:@"Re-sign tweaks"
    message:@"Continue will re-sign all files in this folder."
    destructive:NO
    confirmButtonTitle:@"OK"
    handler:^(UIAlertAction *action) {
        if (action.style == UIAlertActionStyleCancel) return;
        [self signFilesInFolder:self.path completionHandler:nil];
    }];
}

- (void)signFilesInFolder:(NSString *)path completionHandler:(void(^)(BOOL success))handler {
    NSString *codesignPath = [path stringByAppendingPathComponent:@"_CodeSignature"];
    NSString *provisionPath = [path stringByAppendingPathComponent:@"embedded.mobileprovision"];
    NSString *tmpExecPath = [path stringByAppendingPathComponent:@"LiveContainer.tmp"];
    NSString *tmpInfoPath = [path stringByAppendingPathComponent:@"Info.plist"];
    [NSFileManager.defaultManager copyItemAtPath:NSBundle.mainBundle.executablePath toPath:tmpExecPath error:nil];
    NSMutableDictionary *info = NSBundle.mainBundle.infoDictionary.mutableCopy;
    info[@"CFBundleExecutable"] = @"LiveContainer.tmp";
    [info writeToFile:tmpInfoPath atomically:YES];

    __block NSProgress *progress = [LCUtils signAppBundle:[NSURL fileURLWithPath:path]
    completionHandler:^(BOOL success, NSError *_Nullable signError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Cleanup
            self.progressView.progress = 0;
            [NSFileManager.defaultManager removeItemAtPath:codesignPath error:nil];
            [NSFileManager.defaultManager removeItemAtPath:provisionPath error:nil];
            [NSFileManager.defaultManager removeItemAtPath:tmpExecPath error:nil];
            [NSFileManager.defaultManager removeItemAtPath:tmpInfoPath error:nil];

            if (handler) {
                handler(signError == nil);
            }
            if (signError) {
                [self showDialogTitle:@"Error while signing tweaks" message:signError.localizedDescription];
            }

            [progress removeObserver:self forKeyPath:@"fractionCompleted"];
            self.progressView.hidden = YES;
            self.signButton.enabled = YES;
            [self loadPath];
        });
    }];

    if (progress) {
        self.progressView.hidden = NO;
        self.signButton.enabled = NO;
        [progress addObserver:self forKeyPath:@"fractionCompleted" options:NSKeyValueObservingOptionNew context:nil];
    }
}

- (UIAction *)destructiveActionWithTitle:(NSString *)title image:(UIImage *)image handler:(id)handler {
    UIAction *action = [UIAction
        actionWithTitle:title
        image:image
        identifier:nil
        handler:handler];
    action.attributes = UIMenuElementAttributesDestructive;
    return action;
}

#pragma mark UITableViewDelegate
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

/*
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"N items";
}
*/

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.objects.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
    }

    UIListContentConfiguration *config = cell.defaultContentConfiguration;
    config.text = self.objects[indexPath.row];

    BOOL isDir;
    NSString *path = [self.path stringByAppendingPathComponent:self.objects[indexPath.row]];
    [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir];
    config.image = [UIImage systemImageNamed:(isDir ? @"folder.fill" : @"doc")];

    if (isDir) {
        config.secondaryText = @"folder";
    } else {
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
        NSNumber *size = attrs[NSFileSize];
        config.secondaryText = [NSByteCountFormatter stringFromByteCount:size.unsignedLongLongValue
            countStyle:NSByteCountFormatterCountStyleFile];
    }

    cell.contentConfiguration = config;
    cell.selectionStyle = isDir ?
        UITableViewCellSelectionStyleDefault :
        UITableViewCellSelectionStyleNone;
    return cell;
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (cell.selectionStyle == UITableViewCellSelectionStyleNone) {
        return nil;
    } else {
        return indexPath;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    NSString *name = self.objects[indexPath.row];
    LCTweakListViewController *childVC = [LCTweakListViewController new];
    childVC.path = [self.path stringByAppendingPathComponent:name];
    [self.navigationController pushViewController:childVC animated:YES];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    NSArray *menuItems = @[
        [UIAction
            actionWithTitle:@"Rename"
            image:[UIImage systemImageNamed:@"pencil"]
            identifier:nil
            handler:^(UIAction *action) {
                [self renameItemAtIndexPath:indexPath];
            }],
        [self
            destructiveActionWithTitle:@"Delete"
            image:[UIImage systemImageNamed:@"trash"]
            handler:^(UIAction *action) {
                [self deleteItemAtIndexPath:indexPath completionHandler:nil];
            }]
    ];

    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
        previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
            return [UIMenu menuWithTitle:self.objects[indexPath.row] children:menuItems];
        }];
}

- (void)deleteItemAtIndexPath:(NSIndexPath *)indexPath completionHandler:(void(^)(BOOL actionPerformed))handler {
    NSString *name = self.objects[indexPath.row];
    NSString *path = [self.path stringByAppendingPathComponent:name];
    [self showConfirmationDialogTitle:@"Confirm"
    message:[NSString stringWithFormat:@"Are you sure you want to delete %@?", name]
    destructive:YES
    confirmButtonTitle:@"Delete"
    handler:^(UIAlertAction * action) {
        if (action.style != UIAlertActionStyleCancel) {
            NSError *error = nil;
            [NSFileManager.defaultManager removeItemAtPath:path error:&error];
            if (error) {
                [self showDialogTitle:@"Error" message:error.localizedDescription];
            } else {
                [self.objects removeObjectAtIndex:indexPath.row];
                [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            }
        }
        if (handler) handler(YES);
    }];
}

- (void)renameItemAtIndexPath:(NSIndexPath *)indexPath {
    [self showInputDialogTitle:@"Rename" message:@"Enter name" placeholder:self.objects[indexPath.row] callback:^(NSString *name) {
        NSError *error;
        NSString *fromPath = [self.path stringByAppendingPathComponent:self.objects[indexPath.row]];
        NSString *toPath = [self.path stringByAppendingPathComponent:name];
        [NSFileManager.defaultManager moveItemAtPath:fromPath toPath:toPath error:&error];
        [self loadPath];
        return error.localizedDescription;
    }];
}

- (UISwipeActionsConfiguration *) tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [UISwipeActionsConfiguration configurationWithActions:@[
        [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"Delete" handler:^(UIContextualAction *action, __kindof UIView *sourceView, void (^completionHandler)(BOOL actionPerformed)) {
            [self deleteItemAtIndexPath:indexPath completionHandler:completionHandler];
        }]
    ]];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSError *error;
    NSString *path = self.path;
    if (LCUtils.certificatePassword) {
        // Move them to a tmp folder to sign them
        path = [self.path stringByAppendingPathComponent:@".tmp"];
        [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:@{} error:&error];
        if (error) {
            [self showDialogTitle:@"Error" message:error.localizedDescription];
            return;
        }
    }

    for (NSURL *url in urls) {
        NSString *filePath = [path stringByAppendingPathComponent:url.path.lastPathComponent];
        [NSFileManager.defaultManager moveItemAtPath:url.path toPath:filePath error:&error];
        if (error) {
            [self showDialogTitle:@"Error" message:error.localizedDescription];
            return;
        }
        LCParseMachO(filePath.UTF8String, ^(const char *path, struct mach_header_64 *header) {
            LCPatchAddRPath(path, header);
        });
    }

    if (!LCUtils.certificatePassword) {
        // JIT stop here
        return;
    }

    // Setup a fake app bundle for signing
    [self signFilesInFolder:path completionHandler:^(BOOL success){
        if (success) {
            // Move tweaks back
            for (NSURL *url in urls) {
                NSString *fromPath = [path stringByAppendingPathComponent:url.path.lastPathComponent];
                NSString *toPath = [self.path stringByAppendingPathComponent:url.path.lastPathComponent];
                [NSFileManager.defaultManager moveItemAtPath:fromPath toPath:toPath error:nil];
            }
        }

        // Remove tmp folder
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    }];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"fractionCompleted"]) {
        NSProgress *progress = (NSProgress *)object;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressView.progress = progress.fractionCompleted;
        });
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end
