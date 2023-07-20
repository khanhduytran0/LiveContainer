#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "LCGuestAppConfigViewController.h"
#import "LCRootViewController.h"
#import "MBRoundProgressView.h"
#import "UIKitPrivate.h"
#import "unarchive.h"
#import "AppInfo.h"

#include <libgen.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <sys/mman.h>
#include <sys/stat.h>

static uint32_t rnd32(uint32_t v, uint32_t r) {
    r--;
    return (v + r) & ~r;
}

static void insertDylibCommand(const char *path, struct mach_header_64 *header) {
    char *name = basename((char *)path);
    struct dylib_command *dylib = (struct dylib_command *)(sizeof(struct mach_header_64) + (void *)header+header->sizeofcmds);
    dylib->cmd = LC_ID_DYLIB;
    dylib->cmdsize = sizeof(struct dylib_command) + rnd32((uint32_t)strlen(name) + 1, 8);
    dylib->dylib.name.offset = sizeof(struct dylib_command);
    dylib->dylib.compatibility_version = 0x10000;
    dylib->dylib.current_version = 0x10000;
    dylib->dylib.timestamp = 2;
    strncpy((void *)dylib + dylib->dylib.name.offset, name, strlen(name));
    header->ncmds++;
    header->sizeofcmds += dylib->cmdsize;
}

static void patchExecSlice(const char *path, struct mach_header_64 *header) {
    uint8_t *imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);

    // Literally convert an executable to a dylib
    if (header->magic == MH_MAGIC_64) {
        //assert(header->flags & MH_PIE);
        header->filetype = MH_DYLIB;
        header->flags &= ~MH_PIE;
    }

    // Add LC_ID_DYLIB
    BOOL hasDylibCommand = NO;
    struct load_command *command = (struct load_command *)imageHeaderPtr;
    for(int i = 0; i < header->ncmds > 0; i++) {
        if(command->cmd == LC_ID_DYLIB) {
            hasDylibCommand = YES;
            break;
        }
        command = (struct load_command *)((void *)command + command->cmdsize);
    }
    if (!hasDylibCommand) {
        insertDylibCommand(path, header);
    }

    // Patch __PAGEZERO to map just a single zero page, fixing "out of address space"
    struct segment_command_64 *seg = (struct segment_command_64 *)imageHeaderPtr;
    assert(seg->cmd == LC_SEGMENT_64);
    if (seg->vmaddr == 0) {
        assert(seg->vmsize == 0x100000000);
        seg->vmaddr = 0x100000000 - 0x4000;
        seg->vmsize = 0x4000;
    }
}

@interface LCRootViewController ()
@property(atomic) NSMutableArray<NSString *> *objects;
@property(nonatomic) NSString *bundlePath, *docPath;

@property(nonatomic) MBRoundProgressView *progressView;
@end

@implementation LCRootViewController

- (void)patchExecutable:(const char *)path {
    int fd = open(path, O_RDWR, (mode_t)0600);
    struct stat s;
    fstat(fd, &s);
    void *map = mmap(NULL, s.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);

    uint32_t magic = *(uint32_t *)map;
    if (magic == FAT_CIGAM) {
        // Find compatible slice
        struct fat_header *header = (struct fat_header *)map;
        struct fat_arch *arch = (struct fat_arch *)(map + sizeof(struct fat_header));
        for (int i = 0; i < OSSwapInt32(header->nfat_arch); i++) {
            if (OSSwapInt32(arch->cputype) == CPU_TYPE_ARM64) {
                patchExecSlice(path, (struct mach_header_64 *)(map + OSSwapInt32(arch->offset)));
            }
            arch = (struct fat_arch *)((void *)arch + sizeof(struct fat_arch));
        }
    } else if (magic == MH_MAGIC_64) {
        patchExecSlice(path, (struct mach_header_64 *)map);
    } else {
        [self showDialogTitle:@"Error" message:@"32-bit app is not supported"];
    }

    msync(map, s.st_size, MS_SYNC);
    munmap(map, s.st_size);
    close(fd);
}

- (void)loadView {
    [super loadView];

    NSString *appError = [NSUserDefaults.standardUserDefaults stringForKey:@"error"];
    if (appError) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"error"];
        [self showDialogTitle:@"Error" message:appError];
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    self.docPath = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject.path;
    self.bundlePath = [NSString stringWithFormat:@"%@/Applications", self.docPath];
    [fm createDirectoryAtPath:self.bundlePath withIntermediateDirectories:YES attributes:nil error:nil];
    self.objects = [[fm contentsOfDirectoryAtPath:self.bundlePath error:nil] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return [object hasSuffix:@".app"];
    }]].mutableCopy;
    self.title = @"LiveContainer";
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPlay target:self action:@selector(launchButtonTapped)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addButtonTapped)]
    ];
    self.navigationItem.leftBarButtonItems[0].enabled = NO;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)showDialogTitle:(NSString *)title message:(NSString *)message {
    [self showDialogTitle:title message:message handler:nil];
}
- (void)showDialogTitle:(NSString *)title message:(NSString *)message handler:(void(^)(UIAlertAction *))handler {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:handler];
    [alert addAction:okAction];
    UIAlertAction* copyAction = [UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction * action) {
            UIPasteboard.generalPasteboard.string = message;
            if (handler) handler(action);
        }];
    [alert addAction:copyAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addButtonTapped {
    UIDocumentPickerViewController* documentPickerVC = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[[UTType typeWithFilenameExtension:@"ipa" conformingToType:UTTypeData]]];
    documentPickerVC.allowsMultipleSelection = YES;
    documentPickerVC.delegate = self;
    [self presentViewController:documentPickerVC animated:YES completion:nil];
}

- (void)launchButtonTapped {
    if (!self.tableView.indexPathForSelectedRow) {
        return;
    }

    NSURL *sidejitURL = [NSURL URLWithString:[NSString stringWithFormat:@"sidestore://sidejit-enable?bid=%@", NSBundle.mainBundle.bundleIdentifier]];
    if ([UIApplication.sharedApplication canOpenURL:sidejitURL]) {
        [UIApplication.sharedApplication openURL:sidejitURL options:@{} completionHandler:^(BOOL b){
            exit(0);
        }];
        return;
    }

    [self showDialogTitle:@"Instruction" message:@"To use this button, you need a build of SideStore that supports enabling JIT through URL scheme. Otherwise, you need to manually enable it."
    handler:^(UIAlertAction * action) {
        [UIApplication.sharedApplication suspend];
        exit(0);
    }];
}

- (NSString *)performInstallIPA:(NSURL *)url progress:(NSProgress *)progress {
    if(![url startAccessingSecurityScopedResource]) {
        return @"Failed to access IPA";
    }
    NSError *error = nil;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString* temp = NSTemporaryDirectory();
    extract(url.path, temp, progress);
    [url stopAccessingSecurityScopedResource];

    NSArray* PayloadContents = [[fm contentsOfDirectoryAtPath:[temp stringByAppendingPathComponent: @"Payload"] error:nil] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return [object hasSuffix:@".app"];
    }]];
    if (!PayloadContents.firstObject) {
        return @"App bundle not found";
    }

    NSString *AppName = PayloadContents[0];
    NSString *oldAppName = AppName;
    NSString *outPath = [self.bundlePath stringByAppendingPathComponent: AppName];

    __block int selectedAction = -1;
    if ([fm fileExistsAtPath:outPath isDirectory:nil]) {
        dispatch_group_t group = dispatch_group_create();
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Install"
                message:@"There is an existing application with the same bundle folder name, what would you like to do?"
                preferredStyle:UIAlertControllerStyleAlert];
            id handler = ^(UIAlertAction *action) {
                selectedAction = [alert.actions indexOfObject:action];
                if (selectedAction == 0) { // Replace
                    [self deleteAppAtIndexPath:[NSIndexPath indexPathForRow:[self.objects indexOfObject:AppName] inSection:0]];
                }
                dispatch_group_leave(group);
            };
            for (NSString *action in @[@"Replace", @"Keep both, share data", @"Keep both, don't share data"]) {
                [alert addAction:[UIAlertAction actionWithTitle:action style:UIAlertActionStyleDefault handler:handler]];
            }
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:handler]];
            [self presentViewController:alert animated:YES completion:nil];
        });
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    }

    NSString *dataUUID = NSUUID.UUID.UUIDString;
    switch (selectedAction) {
        case 0: // Replace, handled in the action block
            break;
        case 1: // Keep both, share data
            dataUUID = [NSDictionary dictionaryWithContentsOfFile:
                [outPath stringByAppendingPathComponent:@"Info.plist"]][@"LCDataUUID"];
            // note: don't break; here!
        case 2: // Keep both, don't share data
            AppName = [NSString stringWithFormat:@"%@%ld.app", [AppName substringToIndex:AppName.length-4], (long)CFAbsoluteTimeGetCurrent()];
            outPath = [self.bundlePath stringByAppendingPathComponent:AppName];
            break;
    }
    NSString *payloadPath = [temp stringByAppendingPathComponent:@"Payload"];
    if (selectedAction != 3) { // Did not cancel
        self.objects[0] = AppName;
        [fm moveItemAtPath:[payloadPath stringByAppendingPathComponent:oldAppName] toPath:outPath error:&error];
        // Write data UUID
        NSString *infoPath = [outPath stringByAppendingPathComponent:@"Info.plist"];
        NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
        info[@"LCDataUUID"] = dataUUID;
        [info writeToFile:infoPath atomically:YES];
    }
    [fm removeItemAtPath:payloadPath error:(selectedAction==3 ? &error : nil)];
    if (error) {
        return error.localizedDescription;
    }

    if (selectedAction == 3) {
        return @""; // Cancelled
    } else {
        return nil; // Succeeded
    }
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSProgress *progress = [NSProgress new];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableString *errorString = [NSMutableString string];
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:0];
        for (NSURL* url in urls) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [progress addObserver:self forKeyPath:@"fractionCompleted" options:NSKeyValueObservingOptionNew context:nil];
                progress.completedUnitCount = 0;
                progress.totalUnitCount = 0;
                [self.objects insertObject:@"" atIndex:0];
                [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            });

            NSString *error = [self performInstallIPA:url progress:progress];
            if (error.length > 0) {
                [errorString appendFormat:@"%@: %@\n", url.lastPathComponent, error];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [self.progressView removeFromSuperview];
                [progress removeObserver:self forKeyPath:@"fractionCompleted"];
                if (error) {
                    [self.objects removeObjectAtIndex:indexPath.row];
                    [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
                    return;
                }
                [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
                [self patchExecAtIndexPathIfNeed:indexPath];
            });
        }

        if (errorString.length == 0) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showDialogTitle:@"Error" message:errorString];
        });
    });
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _objects.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
        cell.preservesSuperviewLayoutMargins = NO;
        cell.separatorInset = UIEdgeInsetsZero;
        cell.layoutMargins = UIEdgeInsetsZero;
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
        cell.imageView.layer.borderWidth = 1;
        cell.imageView.layer.borderColor = [UIColor.labelColor colorWithAlphaComponent:0.1].CGColor;
        cell.imageView.layer.cornerRadius = 13.5;
        cell.imageView.layer.masksToBounds = YES;
        cell.imageView.layer.cornerCurve = kCACornerCurveContinuous;
    }

    cell.userInteractionEnabled = self.objects[indexPath.row].length > 0;
    if (!cell.userInteractionEnabled) {
        if (!self.progressView) {
            self.progressView = [[MBRoundProgressView alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
        }

        cell.textLabel.text = @"Installing";
        cell.detailTextLabel.text = nil;
        cell.imageView.image = [[UIImage imageNamed:@"DefaultIcon"] _imageWithSize:CGSizeMake(60, 60)];
        [cell.imageView addSubview:self.progressView];
        return cell;
    }
    AppInfo* appInfo = [[AppInfo alloc] initWithBundlePath: [NSString stringWithFormat:@"%@/%@", self.bundlePath, self.objects[indexPath.row]]];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ - %@\n%@", [appInfo version], [appInfo bundleIdentifier], [appInfo dataUUID]];
    cell.textLabel.text = [appInfo displayName];
    cell.imageView.image = [[appInfo icon] _imageWithSize:CGSizeMake(60, 60)];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 80.0f;
}

- (void)deleteAppAtIndexPath:(NSIndexPath *)indexPath {
    AppInfo* appInfo = [[AppInfo alloc] initWithBundlePath: [NSString stringWithFormat:@"%@/%@", self.bundlePath, self.objects[indexPath.row]]];
    UIAlertController* uninstallAlert = [UIAlertController alertControllerWithTitle:@"Confirm Uninstallation" message:[NSString stringWithFormat:@"Are you sure you want to uninstall %@?", [appInfo displayName]] preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* uninstallApp = [UIAlertAction actionWithTitle:@"Uninstall" style:UIAlertActionStyleDestructive handler:^(UIAlertAction* action) {
	NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithFormat:@"%@/%@", self.bundlePath, self.objects[indexPath.row]] error:&error];
        if (error) {
            [self showDialogTitle:@"Error" message:error.localizedDescription];
            return;
        }
        [self.objects removeObjectAtIndex:indexPath.row];
        [self.tableView deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
    }];
    [uninstallAlert addAction:uninstallApp];
    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [uninstallAlert addAction:cancelAction];
    [self presentViewController:uninstallAlert animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    [self deleteAppAtIndexPath:indexPath];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return self.objects[indexPath.row].length==0 ? UITableViewCellEditingStyleNone : UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    self.navigationItem.leftBarButtonItems[0].enabled = YES;
    //[tableView deselectRowAtIndexPath:indexPath animated:YES];
    [NSUserDefaults.standardUserDefaults setObject:self.objects[indexPath.row] forKey:@"selected"];
    [self patchExecAtIndexPathIfNeed:indexPath];
}

- (void)patchExecAtIndexPathIfNeed:(NSIndexPath *)indexPath {
    NSString *appPath = [NSString stringWithFormat:@"%@/%@", self.bundlePath, self.objects[indexPath.row]];
    NSString *infoPath = [NSString stringWithFormat:@"%@/Info.plist", appPath];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
    if (!info) {
        [self showDialogTitle:@"Error" message:@"Info.plist not found"];
        return;
    }

    int currentPatchRev = 4;
    if ([info[@"LCPatchRevision"] intValue] < currentPatchRev) {
        NSString *execPath = [NSString stringWithFormat:@"%@/%@", appPath, info[@"CFBundleExecutable"]];
        [self patchExecutable:execPath.UTF8String];
        info[@"LCPatchRevision"] = @(currentPatchRev);
        [info writeToFile:infoPath atomically:YES];
    }
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    if (self.objects[indexPath.row].length == 0) return nil;

    AppInfo* appInfo = [[AppInfo alloc] initWithBundlePath:[NSString stringWithFormat:@"%@/%@", self.bundlePath, self.objects[indexPath.row]]];
    NSArray *menuItems = @[
        [UIAction
            actionWithTitle:@"Edit"
            image:[UIImage systemImageNamed:@"pencil"]
            identifier:nil
            handler:^(UIAction *action) {
                LCGuestAppConfigViewController *vc = [LCGuestAppConfigViewController new];
                vc.info = appInfo;
                UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
                [self presentViewController:nav animated:YES completion:nil];
            }
        ],
        [UIAction
            actionWithTitle:@"Open data folder"
            image:[UIImage systemImageNamed:@"folder"]
            identifier:nil
            handler:^(UIAction *action) {
                NSString *url = [NSString stringWithFormat:@"shareddocuments://%@/Data/Application/%@", self.docPath, appInfo.dataUUID];
                [UIApplication.sharedApplication openURL:[NSURL URLWithString:url] options:@{} completionHandler:nil];
            }
        ]
    ];

    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
        previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
            return [UIMenu menuWithTitle:self.objects[indexPath.row] children:menuItems];
        }
    ];
}

@end
