#import "LCRootViewController.h"
#import "unarchive.h"

#include <libgen.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <sys/mman.h>
#include <sys/stat.h>
@import UniformTypeIdentifiers;

static uint32_t rnd32(uint32_t v, uint32_t r) {
    r--;
    return (v + r) & ~r;
}

static void patchExecutable(const char *path) {
    int fd = open(path, O_RDWR, (mode_t)0600);
    struct stat s;
    fstat(fd, &s);
    s.st_size = MIN(s.st_size, 0x8000);
    void *map = mmap(NULL, s.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    struct mach_header_64 *header = (struct mach_header_64 *)map;
    uint8_t *imageHeaderPtr = (uint8_t*)map + sizeof(struct mach_header_64);

    // Literally convert an executable to a dylib
    if (header->magic == MH_MAGIC_64) {
        //assert(header->flags & MH_PIE);
        header->filetype = MH_DYLIB;
        header->flags &= ~MH_PIE;
    }

    // Add LC_ID_DYLIB
    char *name = basename((char *)path);
    struct dylib_command *dylib = (struct dylib_command *)(imageHeaderPtr + header->sizeofcmds);
    dylib->cmd = LC_ID_DYLIB;
    dylib->cmdsize = sizeof(struct dylib_command) + rnd32((uint32_t)strlen(name) + 1, 8);
    dylib->dylib.name.offset = sizeof(struct dylib_command);
    dylib->dylib.compatibility_version = 0x10000;
    dylib->dylib.current_version = 0x10000;
    dylib->dylib.timestamp = 2;
    strncpy((void *)dylib + dylib->dylib.name.offset, name, strlen(name));
    header->ncmds++;
    header->sizeofcmds += dylib->cmdsize;

    // Patch __PAGEZERO to map just a single zero page, fixing "out of address space"
    struct segment_command_64 *seg = (struct segment_command_64 *)imageHeaderPtr;
    assert(seg->cmd == LC_SEGMENT_64);
    if (seg->vmaddr == 0) {
        assert(seg->vmsize == 0x100000000);
        seg->vmaddr = 0x100000000 - 0x4000;
        seg->vmsize = 0x4000;
    }

    msync(map, s.st_size, MS_SYNC);
    munmap(map, s.st_size);
    close(fd);
}

@interface LCRootViewController ()
@property(nonatomic) NSMutableArray *objects;
@property(nonatomic) NSString *bundlePath, *docPath;
@end

@implementation LCRootViewController

- (void)loadView {
    [super loadView];
    NSString *appError = [NSUserDefaults.standardUserDefaults stringForKey:@"error"];
    if (appError) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"error"];
        [self showDialogTitle:@"Error" message:appError];
    }
    self.docPath = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask]
.lastObject.path;
    self.bundlePath = [NSString stringWithFormat:@"%@/Applications", self.docPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:self.bundlePath withIntermediateDirectories:YES attributes:nil error:nil];
    self.objects = [[fm contentsOfDirectoryAtPath:self.bundlePath error:nil] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return [object hasSuffix:@".app"];
    }]].mutableCopy;
    self.title = @"LiveContainer";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addButtonTapped:)];
}

- (void)showDialogTitle:(NSString *)title message:(NSString *)message {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    UIAlertAction* copyAction = [UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction * action) {
            UIPasteboard.generalPasteboard.string = message;
        }];
    [alert addAction:copyAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addButtonTapped:(id)sender {
    UIDocumentPickerViewController* documentPickerVC = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[[UTType typeWithFilenameExtension:@"ipa" conformingToType:UTTypeData]]];
    documentPickerVC.allowsMultipleSelection = NO;
    documentPickerVC.delegate = self;
    [self presentViewController:documentPickerVC animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    BOOL isAccess = [urls.firstObject startAccessingSecurityScopedResource];
    if(!isAccess)
    {
        return;
    }
    NSError *error = nil;
    NSString* temp = NSTemporaryDirectory();
    extract(urls.firstObject.path, temp);
    NSArray* PayloadContents = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[temp stringByAppendingPathComponent: @"Payload"] error:nil] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return [object hasSuffix:@".app"];
    }]];
    if (!PayloadContents) {
        return;
    }
    NSString* AppName = PayloadContents[0];
    [[NSFileManager defaultManager] copyItemAtPath:[[temp stringByAppendingPathComponent: @"Payload"] stringByAppendingPathComponent: AppName] toPath: [self.bundlePath stringByAppendingPathComponent: AppName] error:&error];
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

#pragma mark - Table View Data Source

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
    }
    NSString *infoPath = [NSString stringWithFormat:@"%@/%@/Info.plist", self.bundlePath, self.objects[indexPath.row]];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
    if (!info[@"LCDataUUID"]) {
        info[@"LCDataUUID"] = NSUUID.UUID.UUIDString;
        [info writeToFile:infoPath atomically:YES];
    }
    cell.detailTextLabel.text = info[@"CFBundleIdentifier"];
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
    UIImage* icon = [UIImage imageWithContentsOfFile: [NSString stringWithFormat:@"%@/%@/AppIcon60x60@2x.png", self.bundlePath, self.objects[indexPath.row]]];
    if(icon) {
        cell.imageView.image = icon;
    } else {
        cell.imageView.image = [UIImage imageNamed:@"DefaultIcon"];
    }
    cell.preservesSuperviewLayoutMargins = NO;
    cell.separatorInset = UIEdgeInsetsZero;
    cell.layoutMargins = UIEdgeInsetsZero;
    CGSize itemSize = CGSizeMake(60, 60);
    UIGraphicsBeginImageContextWithOptions(itemSize, NO, UIScreen.mainScreen.scale);
    CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
    [cell.imageView.image drawInRect:imageRect];
    cell.imageView.image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
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
    }
    [self.objects removeObjectAtIndex:indexPath.row];
    [tableView deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - Table View Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    //[tableView deselectRowAtIndexPath:indexPath animated:YES];

    [NSUserDefaults.standardUserDefaults setObject:self.objects[indexPath.row] forKey:@"selected"];

    NSString *appPath = [NSString stringWithFormat:@"%@/%@", self.bundlePath, self.objects[indexPath.row]];
    NSString *infoPath = [NSString stringWithFormat:@"%@/Info.plist", appPath];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
    if (!info) {
        [self showDialogTitle:@"Error" message:@"Info.plist not found"];
        return;
    }
    if ([info[@"LCPatchRevision"] intValue] < 2) {
        info[@"LCPatchRevision"] = @(2);
        [info writeToFile:infoPath atomically:YES];
        NSString *execPath = [NSString stringWithFormat:@"%@/%@", appPath, info[@"CFBundleExecutable"]];
        patchExecutable(execPath.UTF8String);
    }

    //NSString *dataPath = [NSString stringWithFormat:@"%@/Data/Application/%@", self.docPath, info[@"LCDataUUID"]];
    // TODO
}

@end
