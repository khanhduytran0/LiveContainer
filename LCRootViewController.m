#import <CommonCrypto/CommonDigest.h>
#import <SafariServices/SafariServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "LCRootViewController.h"
#import "LCUtils.h"
#import "MBRoundProgressView.h"
#import "UIKitPrivate.h"
#import "UIViewController+LCAlert.h"
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

static void insertDylibCommand(uint32_t cmd, const char *path, struct mach_header_64 *header) {
    const char *name = cmd==LC_ID_DYLIB ? basename((char *)path) : path;
    struct dylib_command *dylib = (struct dylib_command *)(sizeof(struct mach_header_64) + (void *)header+header->sizeofcmds);
    dylib->cmd = cmd;
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
        header->flags |= MH_NO_REEXPORTED_DYLIBS;
        header->flags &= ~MH_PIE;
    }

    BOOL hasDylibCommand = NO,
         hasLoaderCommand = NO;
    const char *tweakLoaderPath = "@loader_path/../../Tweaks/TweakLoader.dylib";
    struct load_command *command = (struct load_command *)imageHeaderPtr;
    for(int i = 0; i < header->ncmds > 0; i++) {
        if(command->cmd == LC_ID_DYLIB) {
            hasDylibCommand = YES;
        } else if(command->cmd == LC_LOAD_DYLIB) {
            struct dylib_command *dylib = (struct dylib_command *)command;
            char *dylibName = (void *)dylib + dylib->dylib.name.offset;
            if (!strncmp(dylibName, tweakLoaderPath, strlen(tweakLoaderPath))) {
                hasLoaderCommand = YES;
            }
        }
        command = (struct load_command *)((void *)command + command->cmdsize);
    }
    if (!hasDylibCommand) {
        insertDylibCommand(LC_ID_DYLIB, path, header);
    }
    if (!hasLoaderCommand) {
        insertDylibCommand(LC_LOAD_DYLIB, tweakLoaderPath, header);
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

@implementation NSURL(hack)
- (BOOL)safari_isHTTPFamilyURL {
    // Screw it, Apple
    return YES;
}
@end

@interface LCRootViewController ()
@property(atomic) NSMutableArray<NSString *> *objects;
@property(nonatomic) NSString *bundlePath, *docPath, *tweakPath;

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
    [self.objects sortUsingSelector:@selector(caseInsensitiveCompare:)];

    // Setup tweak directory
    self.tweakPath = [NSString stringWithFormat:@"%@/Tweaks", self.docPath];
    [NSFileManager.defaultManager createDirectoryAtPath:self.tweakPath withIntermediateDirectories:NO attributes:nil error:nil];

    // Setup action bar
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPlay target:self action:@selector(launchButtonTapped)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addButtonTapped)]
    ];

    self.progressView = [[MBRoundProgressView alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)addButtonTapped {
    UIDocumentPickerViewController* documentPickerVC = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[[UTType typeWithFilenameExtension:@"ipa" conformingToType:UTTypeData]]];
    documentPickerVC.allowsMultipleSelection = YES;
    documentPickerVC.delegate = self;
    [self presentViewController:documentPickerVC animated:YES completion:nil];
}

- (void)launchButtonTapped {
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:self.tableView.indexPathForSelectedRow];
    if (!cell.userInteractionEnabled) {
        return;
    }

    if ([LCUtils launchToGuestApp]) return;

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
                    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self.objects indexOfObject:AppName] inSection:0];
                    [self.objects removeObjectAtIndex:indexPath.row];
                    [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
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

    AppInfo* appInfo = [[AppInfo alloc] initWithBundlePath:outPath];
    NSString *dataUUID = appInfo.dataUUID;
    NSString *tweakFolder = appInfo.tweakFolder ?: @"";
    switch (selectedAction) {
        case 0: // Replace, handled in the action block
            [NSFileManager.defaultManager removeItemAtPath:outPath error:nil];
            break;
        case 2: // Keep both, don't share data
            dataUUID = NSUUID.UUID.UUIDString;
        case 1: // Keep both, share data
            AppName = [NSString stringWithFormat:@"%@%ld.app", [AppName substringToIndex:AppName.length-4], (long)CFAbsoluteTimeGetCurrent()];
            outPath = [self.bundlePath stringByAppendingPathComponent:AppName];
            break;
    }
    NSString *payloadPath = [temp stringByAppendingPathComponent:@"Payload"];
    if (selectedAction != 3) { // Did not cancel
        self.objects[0] = AppName;
        [fm moveItemAtPath:[payloadPath stringByAppendingPathComponent:oldAppName] toPath:outPath error:&error];
        // Reconstruct AppInfo with the new Info.plist
        appInfo = [[AppInfo alloc] initWithBundlePath:outPath];
        // Write data UUID
        appInfo.dataUUID = dataUUID;
        appInfo.tweakFolder = tweakFolder;
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
                [self patchExecAndSignIfNeed:indexPath shouldSort:YES];
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

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"Version %@-%s (%s/%s)",
        NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"],
        CONFIG_TYPE, CONFIG_BRANCH, CONFIG_COMMIT];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UITableViewHeaderFooterView *header = [UITableViewHeaderFooterView new];
    header.text = [self tableView:tableView titleForHeaderInSection:section];
    UIButton *hiddenHeaderButton = [[UIButton alloc] initWithFrame:header.frame];
    hiddenHeaderButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    hiddenHeaderButton.menu = [UIMenu menuWithChildren:@[
        [UIAction
            actionWithTitle:@"Copy"
            image:[UIImage systemImageNamed:@"doc.on.clipboard"]
            identifier:nil
            handler:^(UIAction *action) {
                UIPasteboard.generalPasteboard.string = header.textLabel.text;
            }],
    ]];
    [header addSubview:hiddenHeaderButton];
    return header;
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
    [NSUserDefaults.standardUserDefaults setObject:self.objects[indexPath.row] forKey:@"selected"];
    [self patchExecAndSignIfNeed:indexPath shouldSort:NO];
}

- (void)preprocessBundleBeforeSiging:(NSURL *)bundleURL completion:(dispatch_block_t)completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Remove faulty file
        [NSFileManager.defaultManager removeItemAtURL:[bundleURL URLByAppendingPathComponent:@"LiveContainer"] error:nil];
        // Remove PlugIns folder
        [NSFileManager.defaultManager removeItemAtURL:[bundleURL URLByAppendingPathComponent:@"PlugIns"] error:nil];
        // Remove code signature from all library files
        [LCUtils removeCodeSignatureFromBundleURL:bundleURL];
        dispatch_async(dispatch_get_main_queue(), completion);
    });
}

- (void)patchExecAndSignIfNeed:(NSIndexPath *)indexPath shouldSort:(BOOL)sortNames {
    NSString *appPath = [NSString stringWithFormat:@"%@/%@", self.bundlePath, self.objects[indexPath.row]];
    NSString *infoPath = [NSString stringWithFormat:@"%@/Info.plist", appPath];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
    if (!info) {
        [self showDialogTitle:@"Error" message:@"Info.plist not found"];
        return;
    }

    // Setup data directory
    NSString *dataPath = [NSString stringWithFormat:@"%@/Data/Application/%@", self.docPath, info[@"LCDataUUID"]];
    [NSFileManager.defaultManager createDirectoryAtPath:dataPath withIntermediateDirectories:YES attributes:nil error:nil];

    // Update patch
    int currentPatchRev = 5;
    if ([info[@"LCPatchRevision"] intValue] < currentPatchRev) {
        NSString *execPath = [NSString stringWithFormat:@"%@/%@", appPath, info[@"CFBundleExecutable"]];
        [self patchExecutable:execPath.UTF8String];
        info[@"LCPatchRevision"] = @(currentPatchRev);
        [info writeToFile:infoPath atomically:YES];
    }

    if (!LCUtils.certificatePassword) {
        if (sortNames) {
            [self.objects sortUsingSelector:@selector(caseInsensitiveCompare:)];
            [self.tableView reloadData];
        }
        return;
    }

    int signRevision = 1;

    // We're only getting the first 8 bytes for comparison
    NSUInteger signID;
    if (LCUtils.certificateData) {
        uint8_t digest[CC_SHA1_DIGEST_LENGTH];
        CC_SHA1(LCUtils.certificateData.bytes, (CC_LONG)LCUtils.certificateData.length, digest);
        signID = *(uint64_t *)digest + signRevision;
    } else {
        [self showDialogTitle:@"Error" message:@"Could not open ALTCertificate.p12"];
        return;
    }

    // Sign app if JIT-less is set up
    if ([info[@"LCJITLessSignID"] unsignedLongValue] != signID) {
        NSURL *appPathURL = [NSURL fileURLWithPath:appPath];
        [self preprocessBundleBeforeSiging:appPathURL completion:^{
            // We need to temporarily fake bundle ID and main executable to sign properly
            NSString *tmpExecPath = [appPath stringByAppendingPathComponent:@"LiveContainer.tmp"];
            if (!info[@"LCBundleIdentifier"]) {
                // Don't let main executable get entitlements
                [NSFileManager.defaultManager copyItemAtPath:NSBundle.mainBundle.executablePath toPath:tmpExecPath error:nil];

                info[@"LCBundleExecutable"] = info[@"CFBundleExecutable"];
                info[@"LCBundleIdentifier"] = info[@"CFBundleIdentifier"];
                info[@"CFBundleExecutable"] = tmpExecPath.lastPathComponent;
                info[@"CFBundleIdentifier"] = NSBundle.mainBundle.bundleIdentifier;
                [info writeToFile:infoPath atomically:YES];
            }
            info[@"CFBundleExecutable"] = info[@"LCBundleExecutable"];
            info[@"CFBundleIdentifier"] = info[@"LCBundleIdentifier"];
            [info removeObjectForKey:@"LCBundleExecutable"];
            [info removeObjectForKey:@"LCBundleIdentifier"];

            __block NSProgress *progress = [LCUtils signAppBundle:appPathURL

            completionHandler:^(BOOL success, NSError *_Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error) {
                        [self showDialogTitle:@"Error while signing app" message:error.localizedDescription];
                    } else {
                        info[@"LCJITLessSignID"] = @(signID);
                    }

                    // Remove fake main executable
                    [NSFileManager.defaultManager removeItemAtPath:tmpExecPath error:nil];

                    // Save sign ID and restore bundle ID
                    [info writeToFile:infoPath atomically:YES];

                    [progress removeObserver:self forKeyPath:@"fractionCompleted"];
                    [self.progressView removeFromSuperview];
                    if (sortNames) {
                        [self.objects sortUsingSelector:@selector(caseInsensitiveCompare:)];
                    }
                    [self.tableView reloadData];
                });
            }];
            if (progress) {
                [progress addObserver:self forKeyPath:@"fractionCompleted" options:NSKeyValueObservingOptionNew context:nil];
                UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
                cell.textLabel.text = @"Signing";
                [cell.imageView addSubview:self.progressView];
                cell.userInteractionEnabled = NO;
            }
        }];
    }
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    if (self.objects[indexPath.row].length == 0) return nil;

    NSFileManager *fm = NSFileManager.defaultManager;
    AppInfo* appInfo = [[AppInfo alloc] initWithBundlePath:[NSString stringWithFormat:@"%@/%@", self.bundlePath, self.objects[indexPath.row]]];

    NSString *dataPath = [NSString stringWithFormat:@"%@/Data/Application", self.docPath];
    NSArray *dataFolderNames = [fm contentsOfDirectoryAtPath:dataPath error:nil];
    NSMutableArray<UIAction *> *dataFolderItems = [NSMutableArray array];
    dataFolderItems[0] = [UIAction
        actionWithTitle:@"Add data folder"
        image:[UIImage systemImageNamed:@"plus"]
        identifier:nil
        handler:^(UIAction *action) {
            [self showInputDialogTitle:dataFolderItems[0].title message:@"Enter name" placeholder:NSUUID.UUID.UUIDString callback:^(NSString *name) {
                NSString *path = [dataPath stringByAppendingPathComponent:name];
                NSError *error;
                [fm createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:&error];
                if (error) {
                    return error.localizedDescription;
                }
                appInfo.dataUUID = name;
                [self.tableView reloadData];
                return (NSString *)nil;
            }];
        }];
    dataFolderItems[1] = [UIAction
        actionWithTitle:@"Rename data folder"
        image:[UIImage systemImageNamed:@"pencil"]
        identifier:nil
        handler:^(UIAction *action) {
            [self showInputDialogTitle:dataFolderItems[1].title message:@"Enter name" placeholder:appInfo.dataUUID callback:^(NSString *name) {
                if ([name isEqualToString:appInfo.dataUUID]) {
                    return (NSString *)nil;
                }
                NSString *source = [dataPath stringByAppendingPathComponent:appInfo.dataUUID];
                NSString *dest = [dataPath stringByAppendingPathComponent:name];
                NSError *error;
                [fm moveItemAtPath:source toPath:dest error:&error];
                if (error) {
                    return error.localizedDescription;
                }
                appInfo.dataUUID = name;
                [self.tableView reloadData];
                return (NSString *)nil;
            }];
        }];
    int reservedCount = dataFolderItems.count;
    for (int i = 0; i < dataFolderNames.count; i++) {
        dataFolderItems[i + reservedCount] = [UIAction
            actionWithTitle:dataFolderNames[i]
            image:nil identifier:nil
            handler:^(UIAction *action) {
                appInfo.dataUUID = dataFolderNames[i];
                [self.tableView reloadData];
            }];
        if ([appInfo.dataUUID isEqualToString:dataFolderNames[i]]) {
            dataFolderItems[i + reservedCount].state = UIMenuElementStateOn;
        }
    }

    NSArray *tweakFolderNames = [[fm contentsOfDirectoryAtPath:self.tweakPath error:nil]
    filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *bindings) {
        BOOL isDir = NO;
        [fm fileExistsAtPath:[self.tweakPath stringByAppendingPathComponent:name] isDirectory:&isDir];
        return isDir;
    }]];
    NSMutableArray<UIAction *> *tweakFolderItems = [NSMutableArray array];
    tweakFolderItems[0] = [UIAction
        actionWithTitle:@"<None>"
        image:nil
        identifier:nil
        handler:^(UIAction *action) {
            appInfo.tweakFolder = @"";
        }];
    if (appInfo.tweakFolder.length == 0) {
        tweakFolderItems[0].state = UIMenuElementStateOn;
    }

    reservedCount = tweakFolderItems.count;
    for (int i = 0; i < tweakFolderNames.count; i++) {
        tweakFolderItems[i + reservedCount] = [UIAction
            actionWithTitle:tweakFolderNames[i]
            image:nil identifier:nil
            handler:^(UIAction *action) {
                appInfo.tweakFolder = tweakFolderNames[i];
                //[self.tableView reloadData];
            }];
        if ([appInfo.tweakFolder isEqualToString:tweakFolderNames[i]]) {
            tweakFolderItems[i + reservedCount].state = UIMenuElementStateOn;
        }
    }

    NSArray *menuItems = @[
        [UIAction
            actionWithTitle:@"Add to Home Screen"
            image:[UIImage systemImageNamed:@"plus.app"]
            identifier:nil
            handler:^(UIAction *action) {
                NSData *data = [NSPropertyListSerialization dataWithPropertyList:appInfo.generateWebClipConfig format:NSPropertyListXMLFormat_v1_0 options:0 error:0];
                NSString *url = [NSString stringWithFormat:@"data:application/x-apple-aspen-config;base64,%@", [data base64EncodedStringWithOptions:0]];
                SFSafariViewController *svc = [[SFSafariViewController alloc] initWithURL:[NSURL URLWithString:url]];
                [self presentViewController:svc animated:YES completion:nil];
            }],
        [UIMenu
            menuWithTitle:@"Change tweak folder"
            image:[UIImage systemImageNamed:@"gearshape.2"]
            identifier:nil
            options:0
            children:tweakFolderItems],
        [UIMenu
            menuWithTitle:@"Change data folder"
            image:[UIImage systemImageNamed:@"folder.badge.questionmark"]
            identifier:nil
            options:0
            children:dataFolderItems],
        [UIAction
            actionWithTitle:@"Open data folder"
            image:[UIImage systemImageNamed:@"folder"]
            identifier:nil
            handler:^(UIAction *action) {
                NSString *url = [NSString stringWithFormat:@"shareddocuments://%@/Data/Application/%@", self.docPath, appInfo.dataUUID];
                [UIApplication.sharedApplication openURL:[NSURL URLWithString:url] options:@{} completionHandler:nil];
            }],
        [self
            destructiveActionWithTitle:@"Reset settings"
            image:[UIImage systemImageNamed:@"trash"]
            handler:^(UIAction *action) {
                // FIXME: delete non-standard user defaults?
                NSError *error;
                NSString *prefPath = [NSString stringWithFormat:@"%s/Library/Preferences/%@.plist", getenv("HOME"), appInfo.bundleIdentifier];
                [fm removeItemAtPath:prefPath error:&error];
                if (error) {
                    [self showDialogTitle:@"Error" message:error.localizedDescription];
                }
            }],
        [self
            destructiveActionWithTitle:@"Reset app data"
            image:[UIImage systemImageNamed:@"trash"]
            handler:^(UIAction *action) {
                NSError *error;
                NSString *uuidPath = [dataPath stringByAppendingPathComponent:appInfo.dataUUID];
                [fm removeItemAtPath:uuidPath error:&error];
                if (error) {
                    [self showDialogTitle:@"Error" message:error.localizedDescription];
                    return;
                }
                [fm createDirectoryAtPath:uuidPath withIntermediateDirectories:YES attributes:nil error:nil];
            }]
    ];

    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
        previewProvider:nil
        actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
            return [UIMenu menuWithTitle:self.objects[indexPath.row] children:menuItems];
        }];
}

- (UIMenu *)destructiveActionWithTitle:(NSString *)title image:(UIImage *)image handler:(id)handler {
    UIAction *confirmAction = [UIAction
        actionWithTitle:title
        image:image
        identifier:nil
        handler:handler];
    confirmAction.attributes = UIMenuElementAttributesDestructive;
    UIMenu *menu = [UIMenu
        menuWithTitle:title
        image:image
        identifier:nil
        options:UIMenuOptionsDestructive
        children:@[confirmAction]];
    return menu;
}

@end
