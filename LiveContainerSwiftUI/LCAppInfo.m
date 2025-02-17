@import CommonCrypto;

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "LCAppInfo.h"
#import "LCUtils.h"

@implementation LCAppInfo
- (instancetype)initWithBundlePath:(NSString*)bundlePath {
    self = [super init];
    self.isShared = false;
	if(self) {
        _bundlePath = bundlePath;
        _infoPlist = [NSMutableDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath]];
        _info = [NSMutableDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/LCAppInfo.plist", bundlePath]];
        if(!_info) {
            _info = [[NSMutableDictionary alloc] init];
        }
        if(!_infoPlist) {
            _infoPlist = [[NSMutableDictionary alloc] init];
        }
        
        // migrate old appInfo
        if(_infoPlist[@"LCPatchRevision"] && [_info count] == 0) {
            NSArray* lcAppInfoKeys = @[
                @"LCPatchRevision",
                @"LCOrignalBundleIdentifier",
                @"LCDataUUID",
                @"LCTweakFolder",
                @"LCJITLessSignID",
                @"LCSelectedLanguage",
                @"LCExpirationDate",
                @"LCTeamId",
                @"isJITNeeded",
                @"isLocked",
                @"isHidden",
                @"doUseLCBundleId",
                @"doSymlinkInbox",
                @"bypassAssertBarrierOnQueue",
                @"signer",
                @"LCOrientationLock",
                @"cachedColor",
                @"LCContainers",
                @"hideLiveContainer"
            ];
            for(NSString* key in lcAppInfoKeys) {
                _info[key] = _infoPlist[key];
                [_infoPlist removeObjectForKey:key];
            }
            [_infoPlist writeToFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath] atomically:YES];
            [self save];
        }
        
        _autoSaveDisabled = false;
    }
    return self;
}

- (void)setBundlePath:(NSString*)newBundlePath {
    _bundlePath = newBundlePath;
}

- (NSMutableArray*)urlSchemes {
    // find all url schemes
    NSMutableArray* urlSchemes = [[NSMutableArray alloc] init];
    int nowSchemeCount = 0;
    if (_infoPlist[@"CFBundleURLTypes"]) {
        NSMutableArray* urlTypes = _infoPlist[@"CFBundleURLTypes"];

        for(int i = 0; i < [urlTypes count]; ++i) {
            NSMutableDictionary* nowUrlType = [urlTypes objectAtIndex:i];
            if (!nowUrlType[@"CFBundleURLSchemes"]){
                continue;
            }
            NSMutableArray *schemes = nowUrlType[@"CFBundleURLSchemes"];
            for(int j = 0; j < [schemes count]; ++j) {
                [urlSchemes insertObject:[schemes objectAtIndex:j] atIndex:nowSchemeCount];
                ++nowSchemeCount;
            }
        }
    }
    
    return urlSchemes;
}

- (NSString*)displayName {
    if (_infoPlist[@"CFBundleDisplayName"]) {
        return _infoPlist[@"CFBundleDisplayName"];
    } else if (_infoPlist[@"CFBundleName"]) {
        return _infoPlist[@"CFBundleName"];
    } else if (_infoPlist[@"CFBundleExecutable"]) {
        return _infoPlist[@"CFBundleExecutable"];
    } else {
        return @"App Corrupted, Please Reinstall This App";
    }
}

- (NSString*)version {
    NSString* version = _infoPlist[@"CFBundleShortVersionString"];
    if (!version) {
        version = _infoPlist[@"CFBundleVersion"];
    }
    if(version) {
        return version;
    } else {
        return @"Unknown";
    }
}

- (NSString*)bundleIdentifier {
    NSString* ans = nil;
    if([self doUseLCBundleId]) {
        ans = _info[@"LCOrignalBundleIdentifier"];
    } else {
        ans = _infoPlist[@"CFBundleIdentifier"];
    }
    if(ans) {
        return ans;
    } else {
        return @"Unknown";
    }
}

- (NSString*)dataUUID {
    return _info[@"LCDataUUID"];
}

- (NSString*)tweakFolder {
    return _info[@"LCTweakFolder"];
}

- (void)setDataUUID:(NSString *)uuid {
    _info[@"LCDataUUID"] = uuid;
    [self save];
}

- (void)setTweakFolder:(NSString *)tweakFolder {
    _info[@"LCTweakFolder"] = tweakFolder;
    [self save];
}

- (NSString*)selectedLanguage {
    return _info[@"LCSelectedLanguage"];
}

- (void)setSelectedLanguage:(NSString *)selectedLanguage {
    if([selectedLanguage isEqualToString: @""]) {
        _info[@"LCSelectedLanguage"] = nil;
    } else {
        _info[@"LCSelectedLanguage"] = selectedLanguage;
    }
    
    [self save];
}

- (NSString*)bundlePath {
    return _bundlePath;
}

- (NSMutableDictionary*)info {
    return _info;
}

- (UIImage*)icon {
    NSBundle* bundle = [[NSBundle alloc] initWithPath: _bundlePath];
    UIImage* icon = [UIImage imageNamed:[_infoPlist valueForKeyPath:@"CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconFiles"][0] inBundle:bundle compatibleWithTraitCollection:nil];
    if(!icon) {
        icon = [UIImage imageNamed:[_infoPlist valueForKeyPath:@"CFBundleIconFiles"][0] inBundle:bundle compatibleWithTraitCollection:nil];
    }
    
    if(!icon) {
        icon = [UIImage imageNamed:[_infoPlist valueForKeyPath:@"CFBundleIcons~ipad"][@"CFBundlePrimaryIcon"][@"CFBundleIconName"] inBundle:bundle compatibleWithTraitCollection:nil];
    }
    
    if(!icon) {
        icon = [UIImage imageNamed:@"DefaultIcon"];
    }
    return icon;
}

- (UIImage *)generateLiveContainerWrappedIcon {
    UIImage *icon = self.icon;
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"LCFrameShortcutIcons"]) {
        return icon;
    }

    UIImage *lcIcon = [UIImage imageNamed:@"AppIcon76x76"];
    CGFloat iconXY = (lcIcon.size.width - 40) / 2;
    UIGraphicsBeginImageContextWithOptions(lcIcon.size, NO, 0.0);
    [lcIcon drawInRect:CGRectMake(0, 0, lcIcon.size.width, lcIcon.size.height)];
    CGRect rect = CGRectMake(iconXY, iconXY, 40, 40);
    [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:7] addClip];
    [icon drawInRect:rect];
    UIImage *newIcon = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newIcon;
}

- (NSDictionary *)generateWebClipConfigWithContainerId:(NSString*)containerId {
    NSString* appClipUrl;
    if(containerId) {
        appClipUrl = [NSString stringWithFormat:@"livecontainer://livecontainer-launch?bundle-name=%@&container-folder-name=%@", self.bundlePath.lastPathComponent, containerId];
    } else {
        appClipUrl = [NSString stringWithFormat:@"livecontainer://livecontainer-launch?bundle-name=%@", self.bundlePath.lastPathComponent];
    }
    
    NSDictionary *payload = @{
        @"FullScreen": @YES,
        @"Icon": UIImagePNGRepresentation(self.generateLiveContainerWrappedIcon),
        @"IgnoreManifestScope": @YES,
        @"IsRemovable": @YES,
        @"Label": self.displayName,
        @"PayloadDescription": [NSString stringWithFormat:@"Web Clip for launching %@ (%@) in LiveContainer", self.displayName, self.bundlePath.lastPathComponent],
        @"PayloadDisplayName": self.displayName,
        @"PayloadIdentifier": self.bundleIdentifier,
        @"PayloadType": @"com.apple.webClip.managed",
        @"PayloadUUID": NSUUID.UUID.UUIDString,
        @"PayloadVersion": @(1),
        @"Precomposed": @NO,
        @"toPayloadOrganization": @"LiveContainer",
        @"URL": appClipUrl
    };
    return @{
        @"ConsentText": @{
            @"default": [NSString stringWithFormat:@"This profile installs a web clip which opens %@ (%@) in LiveContainer", self.displayName, self.bundlePath.lastPathComponent]
        },
        @"PayloadContent": @[payload],
        @"PayloadDescription": payload[@"PayloadDescription"],
        @"PayloadDisplayName": self.displayName,
        @"PayloadIdentifier": self.bundleIdentifier,
        @"PayloadOrganization": @"LiveContainer",
        @"PayloadRemovalDisallowed": @(NO),
        @"PayloadType": @"Configuration",
        @"PayloadUUID": @"345097fb-d4f7-4a34-ab90-2e3f1ad62eed",
        @"PayloadVersion": @(1),
    };
}

- (void)save {
    if(!_autoSaveDisabled) {
        [_info writeToFile:[NSString stringWithFormat:@"%@/LCAppInfo.plist", _bundlePath] atomically:YES];
    }

}

- (void)preprocessBundleBeforeSiging:(NSURL *)bundleURL completion:(dispatch_block_t)completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Remove faulty file
        [NSFileManager.defaultManager removeItemAtURL:[bundleURL URLByAppendingPathComponent:@"LiveContainer"] error:nil];
        // Remove PlugIns folder
        [NSFileManager.defaultManager removeItemAtURL:[bundleURL URLByAppendingPathComponent:@"PlugIns"] error:nil];
        // Remove code signature from all library files
        if([self signer] == AltSign) {
            [LCUtils removeCodeSignatureFromBundleURL:bundleURL];
        }

        dispatch_async(dispatch_get_main_queue(), completion);
    });
}

- (void)patchExecAndSignIfNeedWithCompletionHandler:(void(^)(bool success, NSString* errorInfo))completetionHandler progressHandler:(void(^)(NSProgress* progress))progressHandler forceSign:(BOOL)forceSign {
    NSString *appPath = self.bundlePath;
    NSString *infoPath = [NSString stringWithFormat:@"%@/Info.plist", appPath];
    NSMutableDictionary *info = _info;
    NSMutableDictionary *infoPlist = _infoPlist;
    if (!info) {
        completetionHandler(NO, @"Info.plist not found");
        return;
    }
    
    NSFileManager* fm = NSFileManager.defaultManager;
    // Update patch
    int currentPatchRev = 6;
    if ([info[@"LCPatchRevision"] intValue] < currentPatchRev) {
        NSString *execPath = [NSString stringWithFormat:@"%@/%@", appPath, _infoPlist[@"CFBundleExecutable"]];
        NSString *backupPath = [NSString stringWithFormat:@"%@/%@_LiveContainerPatchBackUp", appPath, _infoPlist[@"CFBundleExecutable"]];
        // copy-delete-move to avoid EXC_BAD_ACCESS (SIGKILL - CODESIGNING)
        NSError *err;
        [fm copyItemAtPath:execPath toPath:backupPath error:&err];
        [fm removeItemAtPath:execPath error:&err];
        [fm moveItemAtPath:backupPath toPath:execPath error:&err];
        
        NSString *error = LCParseMachO(execPath.UTF8String, ^(const char *path, struct mach_header_64 *header) {
            LCPatchExecSlice(path, header, ![self dontInjectTweakLoader]);
        });
        if (error) {
            completetionHandler(NO, error);
            return;
        }
        info[@"LCPatchRevision"] = @(currentPatchRev);
        forceSign = true;
        // remove ZSign cache since hash is changed after upgrading patch
        NSString* cachePath = [appPath stringByAppendingPathComponent:@"zsign_cache.json"];
        if([fm fileExistsAtPath:cachePath]) {
            NSError* err;
            [fm removeItemAtPath:cachePath error:&err];
        }
        
        [self save];
    }

    if (!LCUtils.certificatePassword) {
        completetionHandler(YES, nil);
        return;
    }

    int signRevision = 1;

    NSDate* expirationDate = info[@"LCExpirationDate"];
    NSString* teamId = info[@"LCTeamId"];
    if(expirationDate && [teamId isEqualToString:[LCUtils teamIdentifier]] && [[[NSUserDefaults alloc] initWithSuiteName:[LCUtils appGroupID]] boolForKey:@"LCSignOnlyOnExpiration"] && !forceSign) {
        if([expirationDate laterDate:[NSDate now]] == expirationDate) {
            // not expired yet, don't sign again
            completetionHandler(YES, nil);
            return;
        }
    }
    
    // We're only getting the first 8 bytes for comparison
    NSUInteger signID;
    if (LCUtils.certificateData) {
        uint8_t digest[CC_SHA1_DIGEST_LENGTH];
        CC_SHA1(LCUtils.certificateData.bytes, (CC_LONG)LCUtils.certificateData.length, digest);
        signID = *(uint64_t *)digest + signRevision;
    } else {
        completetionHandler(NO, @"Failed to find signing certificate. Please refresh your store and try again.");
        return;
    }
    
    // Sign app if JIT-less is set up
    if ([info[@"LCJITLessSignID"] unsignedLongValue] != signID || forceSign) {
        NSURL *appPathURL = [NSURL fileURLWithPath:appPath];
        [self preprocessBundleBeforeSiging:appPathURL completion:^{
            // We need to temporarily fake bundle ID and main executable to sign properly
            NSString *tmpExecPath = [appPath stringByAppendingPathComponent:@"LiveContainer.tmp"];
            if (!info[@"LCBundleIdentifier"]) {
                // Don't let main executable get entitlements
                [fm copyItemAtPath:NSBundle.mainBundle.executablePath toPath:tmpExecPath error:nil];

                infoPlist[@"LCBundleExecutable"] = infoPlist[@"CFBundleExecutable"];
                infoPlist[@"LCBundleIdentifier"] = infoPlist[@"CFBundleIdentifier"];
                infoPlist[@"CFBundleExecutable"] = tmpExecPath.lastPathComponent;
                infoPlist[@"CFBundleIdentifier"] = NSBundle.mainBundle.bundleIdentifier;
                [infoPlist writeToFile:infoPath atomically:YES];
            }
            infoPlist[@"CFBundleExecutable"] = infoPlist[@"LCBundleExecutable"];
            infoPlist[@"CFBundleIdentifier"] = infoPlist[@"LCBundleIdentifier"];
            [infoPlist removeObjectForKey:@"LCBundleExecutable"];
            [infoPlist removeObjectForKey:@"LCBundleIdentifier"];
            
            void (^signCompletionHandler)(BOOL success, NSDate* expirationDate, NSString* teamId, NSError *error)  = ^(BOOL success, NSDate* expirationDate, NSString* teamId, NSError *_Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (success) {
                        info[@"LCJITLessSignID"] = @(signID);
                    }
                    
                    // Remove fake main executable
                    [fm removeItemAtPath:tmpExecPath error:nil];
                    

                    if(success && expirationDate) {
                        info[@"LCExpirationDate"] = expirationDate;
                    }
                    if(success && teamId) {
                        info[@"LCTeamId"] = teamId;
                    }
                    // Save sign ID and restore bundle ID
                    [self save];
                    [infoPlist writeToFile:infoPath atomically:YES];
                    completetionHandler(success, error.localizedDescription);

                });
            };
            
            __block NSProgress *progress;
            
            Signer currentSigner = [NSUserDefaults.standardUserDefaults boolForKey:@"LCCertificateImported"] ? ZSign : [self signer];
            switch (currentSigner) {
                case ZSign:
                    progress = [LCUtils signAppBundleWithZSign:appPathURL completionHandler:signCompletionHandler];
                    break;
                case AltSign:
                    progress = [LCUtils signAppBundle:appPathURL completionHandler:signCompletionHandler];
                    break;
                    
                default:
                    completetionHandler(NO, @"Signer Not Found");
                    break;
            }

            if (progress) {
                progressHandler(progress);
            }
        }];

    } else {
        // no need to sign again
        completetionHandler(YES, nil);
        return;
    }
}

- (bool)isJITNeeded {
    if(_info[@"isJITNeeded"] != nil) {
        return [_info[@"isJITNeeded"] boolValue];
    } else {
        return NO;
    }
}
- (void)setIsJITNeeded:(bool)isJITNeeded {
    _info[@"isJITNeeded"] = [NSNumber numberWithBool:isJITNeeded];
    [self save];
    
}

- (bool)isLocked {
    if(_info[@"isLocked"] != nil) {
        return [_info[@"isLocked"] boolValue];
    } else {
        return NO;
    }
}
- (void)setIsLocked:(bool)isLocked {
    _info[@"isLocked"] = [NSNumber numberWithBool:isLocked];
    [self save];
    
}

- (bool)isHidden {
    if(_info[@"isHidden"] != nil) {
        return [_info[@"isHidden"] boolValue];
    } else {
        return NO;
    }
}
- (void)setIsHidden:(bool)isHidden {
    _info[@"isHidden"] = [NSNumber numberWithBool:isHidden];
    [self save];
    
}

- (bool)doSymlinkInbox {
    if(_info[@"doSymlinkInbox"] != nil) {
        return [_info[@"doSymlinkInbox"] boolValue];
    } else {
        return NO;
    }
}
- (void)setDoSymlinkInbox:(bool)doSymlinkInbox {
    _info[@"doSymlinkInbox"] = [NSNumber numberWithBool:doSymlinkInbox];
    [self save];
    
}

- (bool)hideLiveContainer {
    if(_info[@"hideLiveContainer"] != nil) {
        return [_info[@"hideLiveContainer"] boolValue];
    } else {
        return NO;
    }
}
- (void)setHideLiveContainer:(bool)hideLiveContainer {
    _info[@"hideLiveContainer"] = [NSNumber numberWithBool:hideLiveContainer];
    [self save];
}

- (bool)fixBlackScreen {
    if(_info[@"fixBlackScreen"] != nil) {
        return [_info[@"fixBlackScreen"] boolValue];
    } else {
        return NO;
    }
}
- (void)setFixBlackScreen:(bool)fixBlackScreen {
    _info[@"fixBlackScreen"] = [NSNumber numberWithBool:fixBlackScreen];
    [self save];
}

- (bool)dontInjectTweakLoader {
    if(_info[@"dontInjectTweakLoader"] != nil) {
        return [_info[@"dontInjectTweakLoader"] boolValue];
    } else {
        return NO;
    }
}
- (void)setDontInjectTweakLoader:(bool)dontInjectTweakLoader {
    if([_info[@"dontInjectTweakLoader"] boolValue] == dontInjectTweakLoader) {
        return;
    }
    
    _info[@"dontInjectTweakLoader"] = [NSNumber numberWithBool:dontInjectTweakLoader];
    // we have to update patch to achieve this
    _info[@"LCPatchRevision"] = @(-1);
    [self save];
}

- (bool)dontLoadTweakLoader {
    if(_info[@"dontLoadTweakLoader"] != nil) {
        return [_info[@"dontLoadTweakLoader"] boolValue];
    } else {
        return NO;
    }
}
- (void)setDontLoadTweakLoader:(bool)dontLoadTweakLoader {
    _info[@"dontLoadTweakLoader"] = [NSNumber numberWithBool:dontLoadTweakLoader];
    [self save];
}

- (bool)doUseLCBundleId {
    if(_info[@"doUseLCBundleId"] != nil) {
        return [_info[@"doUseLCBundleId"] boolValue];
    } else {
        return NO;
    }
}
- (void)setDoUseLCBundleId:(bool)doUseLCBundleId {
    _info[@"doUseLCBundleId"] = [NSNumber numberWithBool:doUseLCBundleId];
    NSString *infoPath = [NSString stringWithFormat:@"%@/Info.plist", self.bundlePath];
    if(doUseLCBundleId) {
        _info[@"LCOrignalBundleIdentifier"] = _infoPlist[@"CFBundleIdentifier"];
        _infoPlist[@"CFBundleIdentifier"] = NSBundle.mainBundle.bundleIdentifier;
    } else if (_info[@"LCOrignalBundleIdentifier"]) {
        _infoPlist[@"CFBundleIdentifier"] = _info[@"LCOrignalBundleIdentifier"];
        [_info removeObjectForKey:@"LCOrignalBundleIdentifier"];
    }
    [_infoPlist writeToFile:infoPath atomically:YES];
    [self save];
}

- (bool)bypassAssertBarrierOnQueue {
    if(_info[@"bypassAssertBarrierOnQueue"] != nil) {
        return [_info[@"bypassAssertBarrierOnQueue"] boolValue];
    } else {
        return NO;
    }
}
- (void)setBypassAssertBarrierOnQueue:(bool)enabled {
    _info[@"bypassAssertBarrierOnQueue"] = [NSNumber numberWithBool:enabled];
    [self save];
    
}

- (Signer)signer {
    return (Signer) [((NSNumber*) _info[@"signer"]) intValue];

}
- (void)setSigner:(Signer)newSigner {
    _info[@"signer"] = [NSNumber numberWithInt:(int) newSigner];
    [self save];
    
}

- (LCOrientationLock)orientationLock {
    return (LCOrientationLock) [((NSNumber*) _info[@"LCOrientationLock"]) intValue];

}
- (void)setOrientationLock:(LCOrientationLock)orientationLock {
    _info[@"LCOrientationLock"] = [NSNumber numberWithInt:(int) orientationLock];
    [self save];
    
}

- (UIColor*)cachedColor {
    if(_info[@"cachedColor"] != nil) {
        NSData *colorData = _info[@"cachedColor"];
        NSError* error;
        UIColor *color = [NSKeyedUnarchiver unarchivedObjectOfClass:UIColor.class fromData:colorData error:&error];
        if (!error) {
            return color;
        } else {
            NSLog(@"[LC] failed to get color %@", error);
            return nil;
        }
    } else {
        return nil;
    }
}

- (void)setCachedColor:(UIColor*) color {
    if(color == nil) {
        _info[@"cachedColor"] = nil;
    } else {
        NSError* error;
        NSData *colorData = [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:YES error:&error];
        [_info setObject:colorData forKey:@"cachedColor"];
        if(error) {
            NSLog(@"[LC] failed to set color %@", error);
        }

    }
    [self save];
}

- (NSArray<NSDictionary*>* )containerInfo {
    return _info[@"LCContainers"];
}

- (void)setContainerInfo:(NSArray<NSDictionary *> *)containerInfo {
    _info[@"LCContainers"] = containerInfo;
    [self save];
}

@end
