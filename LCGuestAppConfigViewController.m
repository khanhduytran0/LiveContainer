#import <Foundation/Foundation.h>

#import "LCGuestAppConfigViewController.h"
#import "utils.h"

@implementation LCGuestAppConfigViewController

- (void)viewDidLoad {
    self.title = self.info.bundlePath.lastPathComponent;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(saveAndClose)];

    __weak LCGuestAppConfigViewController *weakSelf = self;
    self.prefSectionsVisible = YES;
    self.getPreference = ^id(NSString *section, NSString *keys){
        for (NSString *key in [keys componentsSeparatedByString:@"|"]) {
            if (weakSelf.info.info[key]) return weakSelf.info.info[key];
        }
        return nil;
    };
    self.setPreference = ^(NSString *section, NSString *key, id value){
        assert(![key containsString:@"|"]);
        weakSelf.info.info[key] = value;
    };

    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *dataPath = [NSString stringWithFormat:@"%@/Data/Application",
        [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject.path];
    NSMutableArray *dataList = [fm contentsOfDirectoryAtPath:dataPath error:nil].mutableCopy;

    self.prefContents = @[
        @[
            @{@"key": @"CFBundleDisplayName|CFBundleName|CFBundleExecutable",
              @"icon": @"tag",
              @"title": @"Name",
              @"type": self.typeTextField,
              @"enableCondition": ^BOOL(){
                  return NO;
              }
            },
            @{@"key": @"LCDataUUID",
              @"icon": @"folder",
              @"title": @"Data",
              @"type": self.typePickField,
              @"pickKeys": dataList,
              @"pickList": dataList
            },
            @{@"key": @"LCTweaksFolder",
              @"icon": @"gearshape.2",
              @"title": @"Tweaks folder",
              @"type": self.typeTextField,
              @"placeholder": @"TODO",
              @"enableCondition": ^BOOL(){
                  return NO;
              }
            },
            @{@"key": @"ResetSettings",
              @"icon": @"trash",
              @"title": @"Reset NSUserDefaults",
              @"type": self.typeButton,
              @"showConfirmPrompt": @YES,
              @"destructive": @YES,
              @"action": ^void(){
                  //[[NSUserDefaults alloc] initWithSuiteName:weakSelf.info.bundleIdentifier];
              }
            }
        ]
    ];

    [super viewDidLoad];
}

- (void)saveAndClose {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.info save];
    [self.presentingViewController viewWillAppear:NO];
}

@end
