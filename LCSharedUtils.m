#import "LCSharedUtils.h"
#import "UIKitPrivate.h"

extern NSUserDefaults *lcUserDefaults;
extern NSString *lcAppUrlScheme;
extern NSBundle *lcMainBundle;

@implementation LCSharedUtils

+ (NSString*) teamIdentifier {
    static NSString* ans = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ans = [[lcMainBundle.bundleIdentifier componentsSeparatedByString:@"."] lastObject];
    });
    return ans;
}

+ (NSString *)appGroupID {
    static dispatch_once_t once;
    static NSString *appGroupID = @"Unknown";
    dispatch_once(&once, ^{
        NSArray* possibleAppGroups = @[
            [@"group.com.SideStore.SideStore." stringByAppendingString:[self teamIdentifier]],
            [@"group.com.rileytestut.AltStore." stringByAppendingString:[self teamIdentifier]]
        ];

        for (NSString *group in possibleAppGroups) {
            NSURL *path = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group];
            NSURL *bundlePath = [path URLByAppendingPathComponent:@"Apps"];
            if ([NSFileManager.defaultManager fileExistsAtPath:bundlePath.path]) {
                // This will fail if LiveContainer is installed in both stores, but it should never be the case
                appGroupID = group;
                return;
            }
        }
    });
    return appGroupID;
}

+ (NSURL*) appGroupPath {
    static NSURL *appGroupPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:[LCSharedUtils appGroupID]];
    });
    return appGroupPath;
}

+ (NSString *)certificatePassword {
    if([NSUserDefaults.standardUserDefaults boolForKey:@"LCCertificateImported"]) {
        NSString* ans = [NSUserDefaults.standardUserDefaults objectForKey:@"LCCertificatePassword"];
        return ans;
    } else {
        // password of cert retrieved from the store tweak is always @"". We just keep this function so we can check if certificate presents without changing codes.
        NSString* ans = [[[NSUserDefaults alloc] initWithSuiteName:[self appGroupID]] objectForKey:@"LCCertificatePassword"];
        if(ans) {
            return @"";
        } else {
            return nil;
        }
    }
}

+ (BOOL)launchToGuestApp {
    NSString *urlScheme;
    NSString *tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", NSBundle.mainBundle.bundlePath];
    UIApplication *application = [NSClassFromString(@"UIApplication") sharedApplication];
    
    int tries = 1;
    if (!access(tsPath.UTF8String, F_OK)) {
        urlScheme = @"apple-magnifier://enable-jit?bundle-id=%@";
    } else if (self.certificatePassword) {
        tries = 2;
        urlScheme = [NSString stringWithFormat:@"%@://livecontainer-relaunch", lcAppUrlScheme];
    } else if ([application canOpenURL:[NSURL URLWithString:@"sidestore://"]]) {
        urlScheme = @"sidestore://sidejit-enable?bid=%@";
    } else {
        tries = 2;
        urlScheme = [NSString stringWithFormat:@"%@://livecontainer-relaunch", lcAppUrlScheme];
    }
    NSURL *launchURL = [NSURL URLWithString:[NSString stringWithFormat:urlScheme, NSBundle.mainBundle.bundleIdentifier]];

    if ([application canOpenURL:launchURL]) {
        //[UIApplication.sharedApplication suspend];
        for (int i = 0; i < tries; i++) {
        [application openURL:launchURL options:@{} completionHandler:^(BOOL b) {
            exit(0);
        }];
        }
        return YES;
    } else {
        // none of the ways work somehow (e.g. LC itself was hidden), we just exit and wait for user to manually launch it
        exit(0);
    }
    return NO;
}

+ (BOOL)launchToGuestAppWithURL:(NSURL *)url {
    NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if(![components.host isEqualToString:@"livecontainer-launch"]) return NO;

    NSString* launchBundleId = nil;
    NSString* openUrl = nil;
    NSString* containerFolderName = nil;
    for (NSURLQueryItem* queryItem in components.queryItems) {
        if ([queryItem.name isEqualToString:@"bundle-name"]) {
            launchBundleId = queryItem.value;
        } else if ([queryItem.name isEqualToString:@"open-url"]){
            NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:queryItem.value options:0];
            openUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        } else if ([queryItem.name isEqualToString:@"container-folder-name"]) {
            containerFolderName = queryItem.value;
        }
    }
    if(launchBundleId) {
        if (openUrl) {
            [lcUserDefaults setObject:openUrl forKey:@"launchAppUrlScheme"];
        }
        
        // Attempt to restart LiveContainer with the selected guest app
        [lcUserDefaults setObject:launchBundleId forKey:@"selected"];
        [lcUserDefaults setObject:containerFolderName forKey:@"selectedContainer"];
        return [self launchToGuestApp];
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
        infoPath = [[LCSharedUtils appGroupPath] URLByAppendingPathComponent:@"LiveContainer/appLock.plist"];
    });
    return infoPath;
}

+ (NSURL*)containerLockPath {
    static dispatch_once_t once;
    static NSURL *infoPath;
    
    dispatch_once(&once, ^{
        infoPath = [[LCSharedUtils appGroupPath] URLByAppendingPathComponent:@"LiveContainer/containerLock.plist"];
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

+ (NSString*)getContainerUsingLCSchemeWithFolderName:(NSString*)folderName {
    NSURL* infoPath = [self containerLockPath];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath.path];
    if (!info) {
        return nil;
    }
    
    for (NSString* key in info) {
        if([folderName isEqualToString:info[key]]) {
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

+ (void)setContainerUsingByThisLC:(NSString*)folderName {
    NSURL* infoPath = [self containerLockPath];
    
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath.path];
    if (!info) {
        info = [NSMutableDictionary new];
    }
    if(folderName == nil) {
        [info removeObjectForKey:lcAppUrlScheme];
    } else {
        info[lcAppUrlScheme] = folderName;
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

+ (void)removeContainerUsingByLC:(NSString*)LCScheme {
    NSURL* infoPath = [self containerLockPath];
    
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath.path];
    if (!info) {
        return;
    }
    [info removeObjectForKey:LCScheme];
    [info writeToFile:infoPath.path atomically:YES];

}

// move app data to private folder to prevent 0xdead10cc https://forums.developer.apple.com/forums/thread/126438
+ (void)moveSharedAppFolderBack {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *libraryPathUrl = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask]
        .lastObject;
    NSURL *docPathUrl = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask]
        .lastObject;
    NSURL *appGroupFolder = [[LCSharedUtils appGroupPath] URLByAppendingPathComponent:@"LiveContainer"];
    
    NSError *error;
    NSString *sharedAppDataFolderPath = [libraryPathUrl.path stringByAppendingPathComponent:@"SharedDocuments"];
    if(![fm fileExistsAtPath:sharedAppDataFolderPath]){
        [fm createDirectoryAtPath:sharedAppDataFolderPath withIntermediateDirectories:YES attributes:@{} error:&error];
    }
    // move all apps in shared folder back
    NSArray<NSString *> * sharedDataFoldersToMove = [fm contentsOfDirectoryAtPath:sharedAppDataFolderPath error:&error];
    
    // something went wrong with app group
    if(!appGroupFolder && sharedDataFoldersToMove.count > 0) {
        [lcUserDefaults setObject:@"LiveContainer was unable to move the data of shared app back because LiveContainer cannot access app group. Please check JITLess diagnose page in LiveContainer settings for more information." forKey:@"error"];
        return;
    }
    
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

+ (NSBundle*)findBundleWithBundleId:(NSString*)bundleId {
    NSString *docPath = [NSString stringWithFormat:@"%s/Documents", getenv("LC_HOME_PATH")];
    
    NSURL *appGroupFolder = nil;
    
    NSString *bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", docPath, bundleId];
    NSBundle *appBundle = [[NSBundle alloc] initWithPath:bundlePath];
    // not found locally, let's look for the app in shared folder
    if (!appBundle) {
        appGroupFolder = [[LCSharedUtils appGroupPath] URLByAppendingPathComponent:@"LiveContainer"];
        
        bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", appGroupFolder.path, bundleId];
        appBundle = [[NSBundle alloc] initWithPath:bundlePath];
    }
    return appBundle;
}

+ (void)dumpPreferenceToPath:(NSString*)plistLocationTo dataUUID:(NSString*)dataUUID {
    NSFileManager* fm = [[NSFileManager alloc] init];
    NSError* error1;
    
    NSDictionary* preferences = [lcUserDefaults objectForKey:dataUUID];
    if(!preferences) {
        return;
    }
    
    [fm createDirectoryAtPath:plistLocationTo withIntermediateDirectories:YES attributes:@{} error:&error1];
    for(NSString* identifier in preferences) {
        NSDictionary* preference = preferences[identifier];
        NSString *itemPath = [plistLocationTo stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", identifier]];
        if([preference count] == 0) {
            // Attempt to delete the file
            [fm removeItemAtPath:itemPath error:&error1];
            continue;
        }
        [preference writeToFile:itemPath atomically:YES];
    }
    [lcUserDefaults removeObjectForKey:dataUUID];
}

+ (NSString*)findDefaultContainerWithBundleId:(NSString*)bundleId {
    // find app's default container
    NSURL* appGroupFolder = [[LCSharedUtils appGroupPath] URLByAppendingPathComponent:@"LiveContainer"];
    
    NSString* bundleInfoPath = [NSString stringWithFormat:@"%@/Applications/%@/LCAppInfo.plist", appGroupFolder.path, bundleId];
    NSDictionary* infoDict = [NSDictionary dictionaryWithContentsOfFile:bundleInfoPath];
    return infoDict[@"LCDataUUID"];
}

@end
