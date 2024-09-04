#import "LCSharedUtils.h"
#import "UIKitPrivate.h"

extern NSUserDefaults *lcUserDefaults;
extern NSString *lcAppUrlScheme;

@implementation LCSharedUtils

+ (NSString *)appGroupID {
    static dispatch_once_t once;
    static NSString *appGroupID = @"group.com.SideStore.SideStore";
    dispatch_once(&once, ^{
        for (NSString *group in NSBundle.mainBundle.infoDictionary[@"ALTAppGroups"]) {
            NSURL *path = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group];
            NSURL *bundlePath = [path URLByAppendingPathComponent:@"Apps/com.kdt.livecontainer/App.app"];
            if ([NSFileManager.defaultManager fileExistsAtPath:bundlePath.path]) {
                // This will fail if LiveContainer is installed in both stores, but it should never be the case
                appGroupID = group;
                return;
            }
        }
    });
    return appGroupID;
}

+ (NSString *)certificatePassword {
    NSString* ans = [lcUserDefaults objectForKey:@"LCCertificatePassword"];
    if(ans) {
        return ans;
    } else {
        return [[[NSUserDefaults alloc] initWithSuiteName:[self appGroupID]] objectForKey:@"LCCertificatePassword"];
    }
}

+ (BOOL)launchToGuestApp {
    NSString *urlScheme;
    NSString *tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", NSBundle.mainBundle.bundlePath];
    int tries = 1;
    if (!access(tsPath.UTF8String, F_OK)) {
        urlScheme = @"apple-magnifier://enable-jit?bundle-id=%@";
    } else if (self.certificatePassword) {
        tries = 8;
        urlScheme = [NSString stringWithFormat:@"%@://livecontainer-relaunch", lcAppUrlScheme];
    } else {
        urlScheme = @"sidestore://sidejit-enable?bid=%@";
    }
    NSURL *launchURL = [NSURL URLWithString:[NSString stringWithFormat:urlScheme, NSBundle.mainBundle.bundleIdentifier]];
    if ([UIApplication.sharedApplication canOpenURL:launchURL]) {
        //[UIApplication.sharedApplication suspend];
        for (int i = 0; i < tries; i++) {
        [UIApplication.sharedApplication openURL:launchURL options:@{} completionHandler:^(BOOL b) {
            exit(0);
        }];
        }
        return YES;
    }
    return NO;
}

+ (BOOL)launchToGuestAppWithURL:(NSURL *)url {
    NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if(![components.host isEqualToString:@"livecontainer-launch"]) return NO;

    for (NSURLQueryItem* queryItem in components.queryItems) {
        if ([queryItem.name isEqualToString:@"bundle-name"]) {
            [lcUserDefaults setObject:queryItem.value forKey:@"selected"];

            // Attempt to restart LiveContainer with the selected guest app
            return [self launchToGuestApp];
            break;
        }
    }
    return NO;
}

+ (void)setWebPageUrlForNextLaunch:(NSString*) urlString {
    [lcUserDefaults setObject:urlString forKey:@"webPageToOpen"];
}

+ (NSURL*)appLockPath {
    static dispatch_once_t once;
    static NSURL *infoPath;
    
    dispatch_once(&once, ^{
        NSURL *appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:[LCSharedUtils appGroupID]];
        infoPath = [appGroupPath URLByAppendingPathComponent:@"LiveContainer/appLock.plist"];
    });
    return infoPath;
}

+ (NSString*)getAppRunningLCSchemeWithBundleId:(NSString*)bundleId {
    NSURL* infoPath = [self appLockPath];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath.path];
    if (!info) {
        return nil;
    }
    
    for (NSString* key in info) {
        if([bundleId isEqualToString:info[key]]) {
            if([key isEqualToString:lcAppUrlScheme]) {
                return nil;
            }
            return key;
        }
    }
    
    return nil;
}

// if you pass null then remove this lc from appLock
+ (void)setAppRunningByThisLC:(NSString*)bundleId {
    NSURL* infoPath = [self appLockPath];
    
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath.path];
    if (!info) {
        info = [NSMutableDictionary new];
    }
    if(bundleId == nil) {
        [info removeObjectForKey:lcAppUrlScheme];
    } else {
        info[lcAppUrlScheme] = bundleId;
    }
    [info writeToFile:infoPath.path atomically:YES];

}

+ (void)removeAppRunningByLC:(NSString*)LCScheme {
    NSURL* infoPath = [self appLockPath];
    
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath.path];
    if (!info) {
        return;
    }
    [info removeObjectForKey:LCScheme];
    [info writeToFile:infoPath.path atomically:YES];

}

+ (void)setupPreferences:(NSString*) newHomePath {
    NSFileManager* fm = [[NSFileManager alloc] init];
    NSError* error1;
    NSString* plistLocationFrom = [NSString stringWithFormat:@"%@/Library/Preferences/", newHomePath];
    NSArray<NSString *> * plists = [fm contentsOfDirectoryAtPath:plistLocationFrom error:&error1];

    NSString* plistLocationTo = [NSString stringWithFormat:@"%s/Library/Preferences/", getenv("LC_HOME_PATH")];
    // remove all symbolic links first
    NSArray *directoryContents = [fm contentsOfDirectoryAtPath:plistLocationTo error:&error1];
    for (NSString *item in directoryContents) {
        NSString *itemPath = [plistLocationTo stringByAppendingPathComponent:item];

        // Get the attributes of the item
        NSDictionary *attributes = [fm attributesOfItemAtPath:itemPath error:&error1];
        if (error1) {
            NSLog(@"Error reading attributes of item: %@, %@", item, error1.localizedDescription);
            continue;
        }

        // Check if the item is a symbolic link
        if ([attributes[NSFileType] isEqualToString:NSFileTypeSymbolicLink]) {
            // Attempt to delete the symbolic link
            [fm removeItemAtPath:itemPath error:&error1];
        }
    }
    
    // link all plists
    for(int i =0; i < [plists count]; ++i) {
        NSString* linkPath = [NSString stringWithFormat:@"%@/%@", plistLocationTo, plists[i]];
        if([fm fileExistsAtPath:linkPath] && ![linkPath containsString:@"livecontainer"]) {
            [fm removeItemAtPath:linkPath error:&error1];
        }
        symlink([NSString stringWithFormat:@"%@/%@", plistLocationFrom, plists[i]].UTF8String, linkPath.UTF8String);
    }
}

+ (void)moveSharedAppFolderBack {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *libraryPathUrl = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask]
        .lastObject;
    NSURL *docPathUrl = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask]
        .lastObject;
    NSURL *appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:[LCSharedUtils appGroupID]];
    NSURL *appGroupFolder = [appGroupPath URLByAppendingPathComponent:@"LiveContainer"];
    
    NSError *error;
    NSString *sharedAppDataFolderPath = [libraryPathUrl.path stringByAppendingPathComponent:@"SharedDocuments"];
    if(![fm fileExistsAtPath:sharedAppDataFolderPath]){
        [fm createDirectoryAtPath:sharedAppDataFolderPath withIntermediateDirectories:YES attributes:@{} error:&error];
    }
    // move all apps in shared folder back
    NSArray<NSString *> * sharedDataFoldersToMove = [fm contentsOfDirectoryAtPath:sharedAppDataFolderPath error:&error];
    for(int i = 0; i < [sharedDataFoldersToMove count]; ++i) {
        NSString* destPath = [appGroupFolder.path stringByAppendingPathComponent:[NSString stringWithFormat:@"Data/Application/%@", sharedDataFoldersToMove[i]]];
        if([fm fileExistsAtPath:destPath]) {
            [fm
             moveItemAtPath:[sharedAppDataFolderPath stringByAppendingPathComponent:sharedDataFoldersToMove[i]]
             toPath:[docPathUrl.path stringByAppendingPathComponent:[NSString stringWithFormat:@"FOLDER_EXISTS_AT_APP_GROUP_%@", sharedDataFoldersToMove[i]]]
             error:&error
            ];
            
        } else {
            [fm
             moveItemAtPath:[sharedAppDataFolderPath stringByAppendingPathComponent:sharedDataFoldersToMove[i]]
             toPath:destPath
             error:&error
            ];
        }
    }
    
}

@end
