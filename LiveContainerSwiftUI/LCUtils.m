@import Darwin;
@import MachO;
@import UIKit;

#import "AltStoreCore/ALTSigner.h"
#import "LCUtils.h"
#import "LCVersionInfo.h"
#import "../ZSign/zsigner.h"

@implementation LCUtils

#pragma mark Certificate & password

+ (NSURL *)appGroupPath {
    return [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.appGroupID];
}

+ (BOOL)deleteKeychainItem:(NSString *)key ofStore:(NSString *)store {
    NSDictionary *dict = @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: store,
        (id)kSecAttrAccount: key,
        (id)kSecAttrSynchronizable: (id)kSecAttrSynchronizableAny
    };
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)dict);
    return status == errSecSuccess;
}

+ (NSData *)keychainItem:(NSString *)key ofStore:(NSString *)store {
    NSDictionary *dict = @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: store,
        (id)kSecAttrAccount: key,
        (id)kSecAttrSynchronizable: (id)kSecAttrSynchronizableAny,
        (id)kSecMatchLimit: (id)kSecMatchLimitOne,
        (id)kSecReturnData: (id)kCFBooleanTrue
    };
    CFTypeRef result = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)dict, &result);
    if (status == errSecSuccess) {
        return (__bridge NSData *)result;
    } else {
        return nil;
    }
}

+ (NSData *)certificateData {
    NSData* ans = [[[NSUserDefaults alloc] initWithSuiteName:[self appGroupID]] objectForKey:@"LCCertificateData"];
    if(ans) {
        return ans;
    } else {
        return [NSUserDefaults.standardUserDefaults objectForKey:@"LCCertificateData"];
    }
    
}

+ (NSString *)certificatePassword {
    // password of cert retrieved from the store tweak is always @"". We just keep this function so we can check if certificate presents without changing codes.
    if([[[NSUserDefaults alloc] initWithSuiteName:[self appGroupID]] objectForKey:@"LCCertificatePassword"]) {
        return @"";
    } else {
        return nil;
    }
}

+ (void)setCertificatePassword:(NSString *)certPassword {
    [NSUserDefaults.standardUserDefaults setObject:certPassword forKey:@"LCCertificatePassword"];
    [[[NSUserDefaults alloc] initWithSuiteName:[self appGroupID]] setObject:certPassword forKey:@"LCCertificatePassword"];
}

#pragma mark LCSharedUtils wrappers
+ (BOOL)launchToGuestApp {
    return [NSClassFromString(@"LCSharedUtils") launchToGuestApp];
}

+ (BOOL)askForJIT {
    return [NSClassFromString(@"LCSharedUtils") askForJIT];
}

+ (BOOL)launchToGuestAppWithURL:(NSURL *)url {
    return [NSClassFromString(@"LCSharedUtils") launchToGuestAppWithURL:url];
}

#pragma mark Code signing

+ (void)loadStoreFrameworksWithError:(NSError **)error {
    // too lazy to use dispatch_once
    static BOOL loaded = NO;
    if (loaded) return;

    NSArray *signerFrameworks;
    
    if([self store] == AltStore) {
        // AltStore requires 1 more framework than sidestore
        signerFrameworks = @[@"OpenSSL.framework", @"Roxas.framework", @"KeychainAccess.framework", @"AltStoreCore.framework"];
    } else {
        signerFrameworks = @[@"OpenSSL.framework", @"Roxas.framework", @"AltStoreCore.framework"];
    }
    
    
    NSURL *storeFrameworksPath = [self.storeBundlePath URLByAppendingPathComponent:@"Frameworks"];
    for (NSString *framework in signerFrameworks) {
        NSBundle *frameworkBundle = [NSBundle bundleWithURL:[storeFrameworksPath URLByAppendingPathComponent:framework]];
        if (!frameworkBundle) {
            //completionHandler(NO, error);
            abort();
        }
        [frameworkBundle loadAndReturnError:error];
        if (error && *error) return;
    }
    loaded = YES;
}

+ (void)loadStoreFrameworksWithError2:(NSError **)error {
    // too lazy to use dispatch_once
    static BOOL loaded = NO;
    if (loaded) return;

    dlopen("@executable_path/Frameworks/ZSign.dylib", RTLD_GLOBAL);
    
    loaded = YES;
}

+ (NSString *)storeBundleID {
    // Assuming this format never changes...
    // group.BUNDLEID.YOURTEAMID
    return [self.appGroupID substringWithRange:NSMakeRange(6, self.appGroupID.length - 17)];
}

+ (NSURL *)storeBundlePath {
    return [self.appGroupPath URLByAppendingPathComponent:[NSString stringWithFormat:@"Apps/%@/App.app", self.storeBundleID]];
}

+ (NSString *)storeInstallURLScheme {
    if ([self.storeBundleID containsString:@"SideStore"]) {
        return @"sidestore://install?url=%@";
    } else {
        return @"altstore://install?url=%@";
    }
}

+ (void)removeCodeSignatureFromBundleURL:(NSURL *)appURL {
    int32_t cpusubtype;
    sysctlbyname("hw.cpusubtype", &cpusubtype, NULL, NULL, 0);

    NSDirectoryEnumerator *countEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:appURL includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLFileSizeKey]
    options:0 errorHandler:^BOOL(NSURL * _Nonnull url, NSError * _Nonnull error) {
        if (error) {
            NSLog(@"[Error] %@ (%@)", error, url);
            return NO;
        }
        return YES;
    }];

    for (NSURL *fileURL in countEnumerator) {
        NSNumber *isFile = nil;
        if (![fileURL getResourceValue:&isFile forKey:NSURLIsRegularFileKey error:nil] || !isFile.boolValue) {
            continue;
        }

        NSNumber *fileSize = nil;
        [fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
        if (fileSize.unsignedLongLongValue < 0x4000) {
            continue;
        }

        // Remove LC_CODE_SIGNATURE
        NSString *error = LCParseMachO(fileURL.path.UTF8String, ^(const char *path, struct mach_header_64 *header) {
            uint8_t *imageHeaderPtr = (uint8_t *)header + sizeof(struct mach_header_64);
            struct load_command *command = (struct load_command *)imageHeaderPtr;
            for(int i = 0; i < header->ncmds > 0; i++) {
                if (command->cmd == LC_CODE_SIGNATURE) {
                    struct linkedit_data_command *csCommand = (struct linkedit_data_command *)command;
                    void *csData = (void *)((uint8_t *)header + csCommand->dataoff);
                    // Nuke it.
                    NSLog(@"Removing code signature of %@", fileURL);
                    bzero(csData, csCommand->datasize);
                    break;
                }
                command = (struct load_command *)((void *)command + command->cmdsize);
            }
        });
        if (error) {
            NSLog(@"[Error] %@ (%@)", error, fileURL);
        }
    }
}

+ (NSProgress *)signAppBundle:(NSURL *)path completionHandler:(void (^)(BOOL success, NSDate* expirationDate, NSError *error))completionHandler {
    NSError *error;

    // I'm too lazy to reimplement signer, so let's borrow everything from SideStore
    // For sure this will break in the future as SideStore team planned to rewrite it
    NSURL *profilePath = [NSBundle.mainBundle URLForResource:@"embedded" withExtension:@"mobileprovision"];

    // Load libraries from Documents, yeah
    [self loadStoreFrameworksWithError:&error];
    if (error) {
        completionHandler(NO, nil, error);
        return nil;
    }

    ALTCertificate *cert = [[NSClassFromString(@"ALTCertificate") alloc] initWithP12Data:self.certificateData password:self.certificatePassword];
    if (!cert) {
        error = [NSError errorWithDomain:NSBundle.mainBundle.bundleIdentifier code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create ALTCertificate. Please try: 1. make sure your store is patched 2. reopen your store 3. refresh all apps"}];
        completionHandler(NO, nil, error);
        return nil;
    }
    ALTProvisioningProfile *profile = [[NSClassFromString(@"ALTProvisioningProfile") alloc] initWithURL:profilePath];
    if (!profile) {
        error = [NSError errorWithDomain:NSBundle.mainBundle.bundleIdentifier code:2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create ALTProvisioningProfile. Please try: 1. make sure your store is patched 2. reopen your store 3. refresh all apps"}];
        completionHandler(NO, nil, error);
        return nil;
    }

    ALTAccount *account = [NSClassFromString(@"ALTAccount") new];
    ALTTeam *team = [[NSClassFromString(@"ALTTeam") alloc] initWithName:@"" identifier:@"" /*profile.teamIdentifier*/ type:ALTTeamTypeUnknown account:account];
    ALTSigner *signer = [[NSClassFromString(@"ALTSigner") alloc] initWithTeam:team certificate:cert];
    
    void (^signCompletionHandler)(BOOL success, NSError *error)  = ^(BOOL success, NSError *_Nullable error) {
        completionHandler(success, [profile expirationDate], error);
    };

    return [signer signAppAtURL:path provisioningProfiles:@[(id)profile] completionHandler:signCompletionHandler];
}

+ (NSProgress *)signAppBundleWithZSign:(NSURL *)path execName:(NSString*)execName completionHandler:(void (^)(BOOL success, NSError *error))completionHandler {
    NSError *error;

    // use zsign as our signer~
    NSURL *profilePath = [NSBundle.mainBundle URLForResource:@"embedded" withExtension:@"mobileprovision"];
    NSData *profileData = [NSData dataWithContentsOfURL:profilePath];
    // Load libraries from Documents, yeah
    [self loadStoreFrameworksWithError2:&error];

    if (error) {
        completionHandler(NO, error);
        return nil;
    }

    NSLog(@"[LC] starting signing...");
    
    NSProgress* ans = [NSClassFromString(@"ZSigner") signWithAppPath:[path path] execName:execName prov:profileData key: self.certificateData pass:self.certificatePassword completionHandler:completionHandler];
    
    return ans;
}

#pragma mark Setup

+ (NSString *)appGroupID {
    static dispatch_once_t once;
    static NSString *appGroupID = @"group.com.SideStore.SideStore";;
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

+ (Store) store {
    static Store ans;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if([[self appGroupID] containsString:@"AltStore"]) {
            ans = AltStore;
        } else {
            ans = SideStore;
        }
    });
    return ans;
}

+ (NSString *)appUrlScheme {
    return NSBundle.mainBundle.infoDictionary[@"CFBundleURLTypes"][0][@"CFBundleURLSchemes"][0];
}

+ (BOOL)isAppGroupAltStoreLike {
    if (self.appGroupID.length == 0) return NO;
    return [NSFileManager.defaultManager fileExistsAtPath:self.storeBundlePath.path];
}

+ (void)changeMainExecutableTo:(NSString *)exec error:(NSError **)error {
    NSURL *infoPath = [self.appGroupPath URLByAppendingPathComponent:@"Apps/com.kdt.livecontainer/App.app/Info.plist"];
    NSMutableDictionary *infoDict = [NSMutableDictionary dictionaryWithContentsOfURL:infoPath];
    if (!infoDict) return;

    infoDict[@"CFBundleExecutable"] = exec;
    [infoDict writeToURL:infoPath error:error];
}

+ (void)writeStoreIDToSetupExecutableWithError:(NSError **)error {
    NSURL *execPath = [self.appGroupPath URLByAppendingPathComponent:@"Apps/com.kdt.livecontainer/App.app/JITLessSetup"];
    NSMutableData *data = [NSMutableData dataWithContentsOfURL:execPath options:0 error:error];
    if (!data) return;

    // We must get SideStore's exact application-identifier, otherwise JIT-less setup will bug out to hell for using the wrong, expired certificate
    [self loadStoreFrameworksWithError:nil];
    NSURL *profilePath = [self.storeBundlePath URLByAppendingPathComponent:@"embedded.mobileprovision"];
    ALTProvisioningProfile *profile = [[NSClassFromString(@"ALTProvisioningProfile") alloc] initWithURL:profilePath];
    NSString *storeKeychainID = profile.entitlements[@"application-identifier"];
    assert(storeKeychainID);

    NSData *findPattern = [@"KeychainAccessGroupWillBeWrittenByLiveContainerAAAAAAAAAAAAAAAAAAAA</string>" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange range = [data rangeOfData:findPattern options:0 range:NSMakeRange(0, data.length)];
    if (range.location == NSNotFound) return;

    memset((char *)data.mutableBytes + range.location, ' ', range.length);
    NSString *replacement = [NSString stringWithFormat:@"%@</string>", storeKeychainID];
    assert(replacement.length < range.length);
    memcpy((char *)data.mutableBytes + range.location, replacement.UTF8String, replacement.length);
    [data writeToURL:execPath options:0 error:error];
}

+ (void)validateJITLessSetupWithCompletionHandler:(void (^)(BOOL success, NSError *error))completionHandler {
    // Verify that the certificate is usable
    // Create a test app bundle
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"CertificateValidation"];
    [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *tmpExecPath = [path stringByAppendingPathComponent:@"LiveContainer.tmp"];
    NSString *tmpLibPath = [path stringByAppendingPathComponent:@"TestJITLess.dylib"];
    NSString *tmpInfoPath = [path stringByAppendingPathComponent:@"Info.plist"];
    [NSFileManager.defaultManager copyItemAtPath:NSBundle.mainBundle.executablePath toPath:tmpExecPath error:nil];
    [NSFileManager.defaultManager copyItemAtPath:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/TestJITLess.dylib"] toPath:tmpLibPath error:nil];
    NSMutableDictionary *info = NSBundle.mainBundle.infoDictionary.mutableCopy;
    info[@"CFBundleExecutable"] = @"LiveContainer.tmp";
    [info writeToFile:tmpInfoPath atomically:YES];

    // Sign the test app bundle
    [LCUtils signAppBundle:[NSURL fileURLWithPath:path]
    completionHandler:^(BOOL success, NSDate* expirationDate, NSError *_Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(success, error);
        });
    }];
}

+ (NSURL *)archiveIPAWithBundleName:(NSString*)newBundleName error:(NSError **)error {
    if (*error) return nil;

    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.appGroupID];
    NSURL *bundlePath = [appGroupPath URLByAppendingPathComponent:@"Apps/com.kdt.livecontainer"];

    NSURL *tmpPath = [appGroupPath URLByAppendingPathComponent:@"tmp"];
    [manager removeItemAtURL:tmpPath error:nil];

    NSURL *tmpPayloadPath = [tmpPath URLByAppendingPathComponent:@"Payload"];
    NSURL *tmpIPAPath = [appGroupPath URLByAppendingPathComponent:@"tmp.ipa"];

    [manager createDirectoryAtURL:tmpPath withIntermediateDirectories:YES attributes:nil error:error];
    if (*error) return nil;

    [manager copyItemAtURL:bundlePath toURL:tmpPayloadPath error:error];
    if (*error) return nil;
    
    NSURL *infoPath = [tmpPayloadPath URLByAppendingPathComponent:@"App.app/Info.plist"];
    NSMutableDictionary *infoDict = [NSMutableDictionary dictionaryWithContentsOfURL:infoPath];
    if (!infoDict) return nil;

    infoDict[@"CFBundleDisplayName"] = newBundleName;
    infoDict[@"CFBundleName"] = newBundleName;
    infoDict[@"CFBundleIdentifier"] = [NSString stringWithFormat:@"com.kdt.%@", newBundleName];
    infoDict[@"CFBundleURLTypes"][0][@"CFBundleURLSchemes"][0] = [newBundleName lowercaseString];
    infoDict[@"CFBundleIcons~ipad"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"][0] = @"AppIcon60x60_2";
    infoDict[@"CFBundleIcons~ipad"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"][1] = @"AppIcon76x76_2";
    infoDict[@"CFBundleIcons"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"][0] = @"AppIcon60x60_2";
    // reset a executable name so they don't look the same on the log
    NSURL* appBundlePath = [tmpPayloadPath URLByAppendingPathComponent:@"App.app"];
    
    NSURL* execFromPath = [appBundlePath URLByAppendingPathComponent:infoDict[@"CFBundleExecutable"]];
    infoDict[@"CFBundleExecutable"] = @"LiveContainer_PleaseDoNotShortenTheExecutableNameBecauseItIsUsedToReserveSpaceForOverwritingThankYou2";
    NSURL* execToPath = [appBundlePath URLByAppendingPathComponent:infoDict[@"CFBundleExecutable"]];
    
    [manager moveItemAtURL:execFromPath toURL:execToPath error:error];
    if (*error) {
        NSLog(@"[LC] %@", *error);
        return nil;
    }
    
    // We have to change executable's UUID so iOS won't consider 2 executables the same
    NSString* errorChangeUUID = LCParseMachO([execToPath.path UTF8String], ^(const char *path, struct mach_header_64 *header) {
        LCChangeExecUUID(header);
    });
    if (errorChangeUUID) {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:errorChangeUUID forKey:NSLocalizedDescriptionKey];
        // populate the error object with the details
        *error = [NSError errorWithDomain:@"world" code:200 userInfo:details];
        NSLog(@"[LC] %@", errorChangeUUID);
        return nil;
    }
    
    [infoDict writeToURL:infoPath error:error];

    dlopen("/System/Library/PrivateFrameworks/PassKitCore.framework/PassKitCore", RTLD_GLOBAL);
    NSData *zipData = [[NSClassFromString(@"PKZipArchiver") new] zippedDataForURL:tmpPayloadPath.URLByDeletingLastPathComponent];
    if (!zipData) return nil;

    [manager removeItemAtURL:tmpPath error:error];
    if (*error) return nil;

    [zipData writeToURL:tmpIPAPath options:0 error:error];
    if (*error) return nil;

    return tmpIPAPath;
}

+ (NSURL *)archiveTweakedAltStoreWithError:(NSError **)error {
    if (*error) return nil;

    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.appGroupID];
    NSURL *lcBundlePath = [appGroupPath URLByAppendingPathComponent:@"Apps/com.kdt.livecontainer"];
    NSURL *bundlePath;
    if ([self store] == SideStore) {
        bundlePath = [appGroupPath URLByAppendingPathComponent:@"Apps/com.SideStore.SideStore"];
    } else {
        bundlePath = [appGroupPath URLByAppendingPathComponent:@"Apps/com.rileytestut.AltStore"];
    }

    NSURL *tmpPath = [appGroupPath URLByAppendingPathComponent:@"tmp"];
    [manager removeItemAtURL:tmpPath error:nil];

    NSURL *tmpPayloadPath = [tmpPath URLByAppendingPathComponent:@"Payload"];
    NSURL *tmpIPAPath = [appGroupPath URLByAppendingPathComponent:@"tmp.ipa"];

    [manager createDirectoryAtURL:tmpPath withIntermediateDirectories:YES attributes:nil error:error];
    if (*error) return nil;

    [manager copyItemAtURL:bundlePath toURL:tmpPayloadPath error:error];
    if (*error) return nil;
    
    // copy altstore tweak
    NSURL* tweakToURL = [tmpPayloadPath URLByAppendingPathComponent:@"App.app/Frameworks/AltStoreTweak.dylib"];
    if([manager fileExistsAtPath:tweakToURL.path]) {
        [manager removeItemAtURL:tweakToURL error:error];
    }
    
    [manager copyItemAtURL:[lcBundlePath URLByAppendingPathComponent:@"App.app/Frameworks/AltStoreTweak.dylib"] toURL:tweakToURL error:error];
    NSURL* execToPatch;
    if ([self store] == SideStore) {
        execToPatch = [tmpPayloadPath URLByAppendingPathComponent:@"App.app/SideStore"];
    } else {
        execToPatch = [tmpPayloadPath URLByAppendingPathComponent:@"App.app/AltStore"];;
    }
    
    NSString* errorPatchAltStore = LCParseMachO([execToPatch.path UTF8String], ^(const char *path, struct mach_header_64 *header) {
        LCPatchAltStore(execToPatch.path.UTF8String, header);
    });
    if (errorPatchAltStore) {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:errorPatchAltStore forKey:NSLocalizedDescriptionKey];
        // populate the error object with the details
        *error = [NSError errorWithDomain:@"world" code:200 userInfo:details];
        NSLog(@"[LC] %@", errorPatchAltStore);
        return nil;
    }
    

    dlopen("/System/Library/PrivateFrameworks/PassKitCore.framework/PassKitCore", RTLD_GLOBAL);
    NSData *zipData = [[NSClassFromString(@"PKZipArchiver") new] zippedDataForURL:tmpPayloadPath.URLByDeletingLastPathComponent];
    if (!zipData) return nil;

    [manager removeItemAtURL:tmpPath error:error];
    if (*error) return nil;

    [zipData writeToURL:tmpIPAPath options:0 error:error];
    if (*error) return nil;

    return tmpIPAPath;
}

+ (NSString *)getVersionInfo {
    return [NSClassFromString(@"LCVersionInfo") getVersionStr];
}

@end
