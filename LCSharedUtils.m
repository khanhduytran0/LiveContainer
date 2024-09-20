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
    NSString* ans = [[[NSUserDefaults alloc] initWithSuiteName:[self appGroupID]] objectForKey:@"LCCertificatePassword"];
    if(ans) {
        return ans;
    } else {
        return [lcUserDefaults objectForKey:@"LCCertificatePassword"];
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

+ (BOOL)askForJIT {
    NSString *urlScheme;
    NSString *tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", NSBundle.mainBundle.bundlePath];
    if (!access(tsPath.UTF8String, F_OK)) {
        urlScheme = @"apple-magnifier://enable-jit?bundle-id=%@";
        NSURL *launchURL = [NSURL URLWithString:[NSString stringWithFormat:urlScheme, NSBundle.mainBundle.bundleIdentifier]];
        if ([UIApplication.sharedApplication canOpenURL:launchURL]) {
            [UIApplication.sharedApplication openURL:launchURL options:@{} completionHandler:nil];
            [LCSharedUtils launchToGuestApp];
            return YES;
        }
    } else {
        NSUserDefaults* groupUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:[self appGroupID]];
        
        NSString* sideJITServerAddress = [groupUserDefaults objectForKey:@"LCSideJITServerAddress"];
        NSString* deviceUDID = [groupUserDefaults objectForKey:@"LCDeviceUDID"];
        if (!sideJITServerAddress || !deviceUDID) {
            return NO;
        }
        NSString* launchJITUrlStr = [NSString stringWithFormat: @"%@/%@/%@", sideJITServerAddress, deviceUDID, NSBundle.mainBundle.bundleIdentifier];
        NSURLSession* session = [NSURLSession sharedSession];
        NSURL* launchJITUrl = [NSURL URLWithString:launchJITUrlStr];
        NSURLRequest* req = [[NSURLRequest alloc] initWithURL:launchJITUrl];
        NSURLSessionDataTask *task = [session dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if(error) {
                NSLog(@"[LC] failed to contact SideJITServer: %@", error);
            }
        }];
        [task resume];
        
    }
    return NO;
}

+ (BOOL)launchToGuestAppWithURL:(NSURL *)url {
    NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if(![components.host isEqualToString:@"livecontainer-launch"]) return NO;

    NSString* launchBundleId = nil;
    NSString* openUrl = nil;
    for (NSURLQueryItem* queryItem in components.queryItems) {
        if ([queryItem.name isEqualToString:@"bundle-name"]) {
            launchBundleId = queryItem.value;
        } else if ([queryItem.name isEqualToString:@"open-url"]){
            NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:queryItem.value options:0];
            openUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        }
    }
    if(launchBundleId) {
        if (openUrl) {
            [lcUserDefaults setObject:openUrl forKey:@"launchAppUrlScheme"];
        }
        
        // Attempt to restart LiveContainer with the selected guest app
        [lcUserDefaults setObject:launchBundleId forKey:@"selected"];
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

// move all plists file from fromPath to toPath
+ (void)movePreferencesFromPath:(NSString*) plistLocationFrom toPath:(NSString*)plistLocationTo {
    NSFileManager* fm = [[NSFileManager alloc] init];
    NSError* error1;
    NSArray<NSString *> * plists = [fm contentsOfDirectoryAtPath:plistLocationFrom error:&error1];

    // remove all plists in toPath first
    NSArray *directoryContents = [fm contentsOfDirectoryAtPath:plistLocationTo error:&error1];
    for (NSString *item in directoryContents) {
        // Check if the item is a plist and does not contain "LiveContainer"
        if(![item hasSuffix:@".plist"] || [item containsString:@"livecontainer"]) {
            continue;
        }
        NSString *itemPath = [plistLocationTo stringByAppendingPathComponent:item];
        // Attempt to delete the file
        [fm removeItemAtPath:itemPath error:&error1];
    }
    
    [fm createDirectoryAtPath:plistLocationTo withIntermediateDirectories:YES attributes:@{} error:&error1];
    // move all plists in fromPath to toPath
    for (NSString* item in plists) {
        if(![item hasSuffix:@".plist"] || [item containsString:@"livecontainer"]) {
            continue;
        }
        NSString* toPlistPath = [NSString stringWithFormat:@"%@/%@", plistLocationTo, item];
        NSString* fromPlistPath = [NSString stringWithFormat:@"%@/%@", plistLocationFrom, item];
        
        [fm moveItemAtPath:fromPlistPath toPath:toPlistPath error:&error1];
        if(error1) {
            NSLog(@"[LC] error1 = %@", error1.description);
        }
        
    }

}

// to make apple happy and prevent, we have to load all preferences into NSUserDefault so that guest app can read them
+ (void)loadPreferencesFromPath:(NSString*) plistLocationFrom {
    NSFileManager* fm = [[NSFileManager alloc] init];
    NSError* error1;
    NSArray<NSString *> * plists = [fm contentsOfDirectoryAtPath:plistLocationFrom error:&error1];
    
    // move all plists in fromPath to toPath
    for (NSString* item in plists) {
        if(![item hasSuffix:@".plist"] || [item containsString:@"livecontainer"]) {
            continue;
        }
        NSString* fromPlistPath = [NSString stringWithFormat:@"%@/%@", plistLocationFrom, item];
        // load, the file and sync
        NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithContentsOfFile:fromPlistPath];
        NSUserDefaults* nud = [[NSUserDefaults alloc] initWithSuiteName: [item substringToIndex:[item length]-6]];
        for(NSString* key in dict) {
            [nud setObject:dict[key] forKey:key];
        }
        
        [nud synchronize];
        
    }

}

// move app data to private folder to prevent 0xdead10cc https://forums.developer.apple.com/forums/thread/126438
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

+ (NSBundle*)findBundleWithBundleId:(NSString*)bundleId {
    NSString *docPath = [NSString stringWithFormat:@"%s/Documents", getenv("LC_HOME_PATH")];
    
    NSURL *appGroupFolder = nil;
    
    NSString *bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", docPath, bundleId];
    NSBundle *appBundle = [[NSBundle alloc] initWithPath:bundlePath];
    // not found locally, let's look for the app in shared folder
    if (!appBundle) {
        NSURL *appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:[LCSharedUtils appGroupID]];
        appGroupFolder = [appGroupPath URLByAppendingPathComponent:@"LiveContainer"];
        
        bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", appGroupFolder.path, bundleId];
        appBundle = [[NSBundle alloc] initWithPath:bundlePath];
    }
    return appBundle;
}

@end
