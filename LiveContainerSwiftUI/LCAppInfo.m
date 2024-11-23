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
        _info = [NSMutableDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath]];
        
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
    if (_info[@"CFBundleURLTypes"]) {
        NSMutableArray* urlTypes = _info[@"CFBundleURLTypes"];

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
    if (_info[@"CFBundleDisplayName"]) {
        return _info[@"CFBundleDisplayName"];
    } else if (_info[@"CFBundleName"]) {
        return _info[@"CFBundleName"];
    } else if (_info[@"CFBundleExecutable"]) {
        return _info[@"CFBundleExecutable"];
    } else {
        return nil;
    }
}

- (NSString*)version {
    NSString* version = _info[@"CFBundleShortVersionString"];
    if (!version) {
        version = _info[@"CFBundleVersion"];
    }
    return version;
}

- (NSString*)bundleIdentifier {
    return _info[@"CFBundleIdentifier"];
}

- (NSString*)dataUUID {
    if (!_info[@"LCDataUUID"]) {
        self.dataUUID = NSUUID.UUID.UUIDString;
    }
    return _info[@"LCDataUUID"];
}

- (NSString*)getDataUUIDNoAssign {
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

- (NSString*)bundlePath {
    return _bundlePath;
}

- (NSMutableDictionary*)info {
    return _info;
}

- (UIImage*)icon {
    UIImage* icon = [UIImage imageNamed:[_info valueForKeyPath:@"CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconFiles"][0] inBundle:[[NSBundle alloc] initWithPath: _bundlePath] compatibleWithTraitCollection:nil];
    if(!icon) {
        icon = [UIImage imageNamed:[_info valueForKeyPath:@"CFBundleIconFiles"][0] inBundle:[[NSBundle alloc] initWithPath: _bundlePath] compatibleWithTraitCollection:nil];
    }
    
    if(!icon) {
        icon = [UIImage imageNamed:[_info valueForKeyPath:@"CFBundleIcons~ipad"][@"CFBundlePrimaryIcon"][@"CFBundleIconName"] inBundle:[[NSBundle alloc] initWithPath: _bundlePath] compatibleWithTraitCollection:nil];
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

- (NSDictionary *)generateWebClipConfig {
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
        @"URL": [NSString stringWithFormat:@"livecontainer://livecontainer-launch?bundle-name=%@", self.bundlePath.lastPathComponent]
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
    [_info writeToFile:[NSString stringWithFormat:@"%@/Info.plist", _bundlePath] atomically:YES];
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

// return "SignNeeded" if sign is needed, other wise return an error
- (void)patchExecAndSignIfNeedWithCompletionHandler:(void(^)(NSString* errorInfo))completetionHandler progressHandler:(void(^)(NSProgress* progress))progressHandler forceSign:(BOOL)forceSign {
    NSString *appPath = self.bundlePath;
    NSString *infoPath = [NSString stringWithFormat:@"%@/Info.plist", appPath];
    NSMutableDictionary *info = _info;
    if (!info) {
        completetionHandler(@"Info.plist not found");
        return;
    }
    
    // Update patch
    int currentPatchRev = 5;
    if ([info[@"LCPatchRevision"] intValue] < currentPatchRev) {
        NSString *execPath = [NSString stringWithFormat:@"%@/%@", appPath, info[@"CFBundleExecutable"]];
        NSString *error = LCParseMachO(execPath.UTF8String, ^(const char *path, struct mach_header_64 *header) {
            LCPatchExecSlice(path, header);
        });
        if (error) {
            completetionHandler(error);
            return;
        }
        info[@"LCPatchRevision"] = @(currentPatchRev);
        [info writeToFile:infoPath atomically:YES];
    }

    if (!LCUtils.certificatePassword) {
        completetionHandler(nil);
        return;
    }

    int signRevision = 1;

    NSDate* expirationDate = info[@"LCExpirationDate"];
    if(expirationDate && [[[NSUserDefaults alloc] initWithSuiteName:[LCUtils appGroupID]] boolForKey:@"LCSignOnlyOnExpiration"]) {
        if([expirationDate laterDate:[NSDate now]] == expirationDate) {
            // not expired yet, don't sign again
            completetionHandler(nil);
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
        completetionHandler(@"Failed to find signing certificate. Please refresh your store and try again.");
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
            
            void (^signCompletionHandler)(BOOL success, NSDate* expirationDate, NSError *error)  = ^(BOOL success, NSDate* expirationDate, NSError *_Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!error) {
                        info[@"LCJITLessSignID"] = @(signID);
                    }
                    
                    // Remove fake main executable
                    [NSFileManager.defaultManager removeItemAtPath:tmpExecPath error:nil];
                    

                    if(!error && expirationDate) {
                        info[@"LCExpirationDate"] = expirationDate;
                    }
                    // Save sign ID and restore bundle ID
                    [self save];
                    
                    if(error) {
                        completetionHandler(error.localizedDescription);
                        return;
                    } else {
                        completetionHandler(nil);
                        return;
                    }

                });
            };
            
            __block NSProgress *progress;
            
            progress = [LCUtils signAppBundle:appPathURL completionHandler:signCompletionHandler];
            if (progress) {
                progressHandler(progress);
            }
        }];

    } else {
        // no need to sign again
        completetionHandler(nil);
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

@end
