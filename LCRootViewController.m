#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "LCRootViewController.h"
#import "UIKitPrivate.h"
#import "unarchive.h"

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
@property(nonatomic) NSMutableArray *objects;
@property(nonatomic) NSString *bundlePath, *docPath;
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
    self.docPath = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject.path;
    self.bundlePath = [NSString stringWithFormat:@"%@/Applications", self.docPath];
    NSFileManager *fm = [NSFileManager defaultManager];
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

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    for (NSURL* url in urls) {
        BOOL isAccess = [url startAccessingSecurityScopedResource];
        if(!isAccess) {
            return;
        }
        NSError *error = nil;
        NSString* temp = NSTemporaryDirectory();
        extract(url.path, temp);
        NSArray* PayloadContents = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[temp stringByAppendingPathComponent: @"Payload"] error:nil] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            return [object hasSuffix:@".app"];
        }]];
        if (!PayloadContents.firstObject) {
            [self showDialogTitle:@"Error" message:@"App bundle not found"];
            return;
        }
        NSString* AppName = PayloadContents[0];
        [[NSFileManager defaultManager] copyItemAtPath:[temp stringByAppendingFormat:@"/Payload/%@", AppName] toPath: [self.bundlePath stringByAppendingPathComponent: AppName] error:&error];
        if (error) {
            [self showDialogTitle:@"Error" message:error.localizedDescription];
            return;
        }
        [[NSFileManager defaultManager] removeItemAtPath:[temp stringByAppendingPathComponent: @"Payload"] error:&error];
        if (error) {
            [self showDialogTitle:@"Error" message:error.localizedDescription];
            return;
        }
        [_objects insertObject:AppName atIndex:0];
        [self.tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:0]] withRowAnimation:UITableViewRowAnimationAutomatic];
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
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    }
    NSString *infoPath = [NSString stringWithFormat:@"%@/%@/Info.plist", self.bundlePath, self.objects[indexPath.row]];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
    if (!info[@"LCDataUUID"]) {
        info[@"LCDataUUID"] = NSUUID.UUID.UUIDString;
        [info writeToFile:infoPath atomically:YES];
    }
    NSString* version = info[@"CFBundleShortVersionString"];
    if (!version) {
        version = info[@"CFBundleVersion"];
    }
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ - %@\n%@", version, info[@"CFBundleIdentifier"], info[@"LCDataUUID"]];
    if (info[@"CFBundleDisplayName"]) {
        cell.textLabel.text = info[@"CFBundleDisplayName"];
    } else if (info[@"CFBundleName"]) {
        cell.textLabel.text = info[@"CFBundleName"];
    } else if (info[@"CFBundleExecutable"]) {
        cell.textLabel.text = info[@"CFBundleExecutable"];
    } else {
        cell.textLabel.text = self.objects[indexPath.row];
    }
    cell.imageView.layer.borderWidth = 1;
    cell.imageView.layer.borderColor = [UIColor.labelColor colorWithAlphaComponent:0.1].CGColor;
    cell.imageView.layer.cornerRadius = 13.5;
    cell.imageView.layer.masksToBounds = YES;
    cell.imageView.layer.cornerCurve = kCACornerCurveContinuous;
    UIImage* icon = [UIImage imageNamed:[info valueForKeyPath:@"CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconFiles"][0] inBundle:[[NSBundle alloc] initWithPath: [NSString stringWithFormat:@"%@/%@", self.bundlePath, self.objects[indexPath.row]]] compatibleWithTraitCollection:nil];
    if(icon) {
        cell.imageView.image = icon;
    } else {
        cell.imageView.image = [UIImage imageNamed:@"DefaultIcon"];
    }
    cell.preservesSuperviewLayoutMargins = NO;
    cell.separatorInset = UIEdgeInsetsZero;
    cell.layoutMargins = UIEdgeInsetsZero;
    cell.imageView.image = [cell.imageView.image _imageWithSize:CGSizeMake(60, 60)];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 80.0f;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithFormat:@"%@/%@", self.bundlePath, self.objects[indexPath.row]] error:&error];
    if (error) {
        [self showDialogTitle:@"Error" message:error.localizedDescription];
        return;
    }
    [self.objects removeObjectAtIndex:indexPath.row];
    [tableView deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    self.navigationItem.leftBarButtonItems[0].enabled = YES;
    //[tableView deselectRowAtIndexPath:indexPath animated:YES];
    [NSUserDefaults.standardUserDefaults setObject:self.objects[indexPath.row] forKey:@"selected"];
    NSString *appPath = [NSString stringWithFormat:@"%@/%@", self.bundlePath, self.objects[indexPath.row]];
    NSString *infoPath = [NSString stringWithFormat:@"%@/Info.plist", appPath];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
    if (!info) {
        [self showDialogTitle:@"Error" message:@"Info.plist not found"];
        return;
    }
    int currentPatchRev = 3;
    if ([info[@"LCPatchRevision"] intValue] < currentPatchRev) {
        NSString *execPath = [NSString stringWithFormat:@"%@/%@", appPath, info[@"CFBundleExecutable"]];
        [self patchExecutable:execPath.UTF8String];
        info[@"LCPatchRevision"] = @(3);
        [info writeToFile:infoPath atomically:YES];
    }
}
@end
