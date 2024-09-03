@import CommonCrypto;

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "LCAppInfo.h"
#import "LCUtils.h"

@implementation SignTmpStatus
@end

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
        @"PayloadUUID": self.dataUUID,
        @"PayloadVersion": @(1),
        @"Precomposed": @NO,
        @"toPayloadOrganization": @"LiveContainer",
        @"URL": [NSString stringWithFormat:@"%@://livecontainer-launch?bundle-name=%@", [LCUtils appUrlScheme], self.bundlePath.lastPathComponent]
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

- (void)preprocessBundleBeforeSiging:(NSURL *)bundleURL {
    // Remove faulty file
    [NSFileManager.defaultManager removeItemAtURL:[bundleURL URLByAppendingPathComponent:@"LiveContainer"] error:nil];
    // Remove PlugIns folder
    [NSFileManager.defaultManager removeItemAtURL:[bundleURL URLByAppendingPathComponent:@"PlugIns"] error:nil];
    // Remove code signature from all library files
    [LCUtils removeCodeSignatureFromBundleURL:bundleURL];
    
}

// return "SignNeeded" if sign is needed, other wise return an error
- (NSString*)patchExec {
    NSString *appPath = self.bundlePath;
    NSString *infoPath = [NSString stringWithFormat:@"%@/Info.plist", appPath];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
    if (!info) {
        return @"Info.plist not found";
    }
    
    // Update patch
    int currentPatchRev = 5;
    if ([info[@"LCPatchRevision"] intValue] < currentPatchRev) {
        NSString *execPath = [NSString stringWithFormat:@"%@/%@", appPath, info[@"CFBundleExecutable"]];
        NSString *error = LCParseMachO(execPath.UTF8String, ^(const char *path, struct mach_header_64 *header) {
            LCPatchExecSlice(path, header);
        });
        if (error) {
            return error;
        }
        info[@"LCPatchRevision"] = @(currentPatchRev);
        [info writeToFile:infoPath atomically:YES];
    }

    if (!LCUtils.certificatePassword) {
        return nil;
    }

    int signRevision = 1;

    // We're only getting the first 8 bytes for comparison
    NSUInteger signID;
    if (LCUtils.certificateData) {
        uint8_t digest[CC_SHA1_DIGEST_LENGTH];
        CC_SHA1(LCUtils.certificateData.bytes, (CC_LONG)LCUtils.certificateData.length, digest);
        signID = *(uint64_t *)digest + signRevision;
    } else {
        return @"Failed to find ALTCertificate.p12. Please refresh your store and try again.";
    }
    
    // Sign app if JIT-less is set up
    if ([info[@"LCJITLessSignID"] unsignedLongValue] != signID) {
        NSURL *appPathURL = [NSURL fileURLWithPath:appPath];
        [self preprocessBundleBeforeSiging:appPathURL];
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
        self._signStatus = [[SignTmpStatus alloc] init];
        self._signStatus.newSignId = signID;
        self._signStatus.tmpExecPath = tmpExecPath;
        self._signStatus.infoPath = infoPath;
        
        return @"SignNeeded";

    }
    return nil;
}

- (void) signCleanUpWithSuccessStatus:(BOOL)isSignSuccess {
    if(self._signStatus == nil) {
        return;
    }
    if (isSignSuccess) {
        _info[@"LCJITLessSignID"] = @(self._signStatus.newSignId);
    }
    
    // Remove fake main executable
    [NSFileManager.defaultManager removeItemAtPath:self._signStatus.tmpExecPath error:nil];
    
    // Save sign ID and restore bundle ID
    [_info writeToFile:self._signStatus.infoPath atomically:YES];
    self._signStatus = nil;
    return;
}
@end
