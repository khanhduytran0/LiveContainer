@import Darwin;
@import MachO;
@import UIKit;

#import "AltStoreCore/ALTSigner.h"
#import "LCUtils.h"
#import "LCVersionInfo.h"

@implementation LCUtils

#pragma mark Certificate & password

+ (NSString *)appGroupPath {
    return [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.appGroupID].path;
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

+ (void)setCertificateData:(NSData *)certData {
    [NSUserDefaults.standardUserDefaults setObject:certData forKey:@"LCCertificateData"];
}

+ (NSData *)certificateDataFile {
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"LCIgnoreALTCertificate"]) {
        return nil;
    }
    NSURL *appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.appGroupID];
    NSURL *url = [appGroupPath URLByAppendingPathComponent:[NSString stringWithFormat:@"Apps/%@/App.app/ALTCertificate.p12", self.storeBundleID]];
    return [NSData dataWithContentsOfURL:url];
}

+ (NSData *)certificateDataProperty {
    NSData* ans = [NSUserDefaults.standardUserDefaults objectForKey:@"LCCertificateData"];
    if(ans) {
        return ans;
    } else {
        return [[[NSUserDefaults alloc] initWithSuiteName:[self appGroupID]] objectForKey:@"LCCertificateData"];
    }
    
}

+ (NSData *)certificateData {
    // Prefer certificate file over keychain data
    return self.certificateDataFile ?: self.certificateDataProperty;
}

+ (NSString *)certificatePassword {
    if (self.certificateDataFile) {
        NSString* ans = [NSUserDefaults.standardUserDefaults objectForKey:@"LCCertificatePassword"];
        if(ans) {
            return ans;
        }
        return [[[NSUserDefaults alloc] initWithSuiteName:[self appGroupID]] objectForKey:@"LCCertificatePassword"];
    } else if (self.certificateDataProperty) {
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

+ (BOOL)launchToGuestAppWithURL:(NSURL *)url {
    return [NSClassFromString(@"LCSharedUtils") launchToGuestAppWithURL:url];
}

#pragma mark Code signing

+ (void)loadStoreFrameworksWithError:(NSError **)error {
    // too lazy to use dispatch_once
    static BOOL loaded = NO;
    if (loaded) return;

    NSArray *signerFrameworks = @[@"OpenSSL.framework", @"Roxas.framework", @"AltStoreCore.framework"];
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

+ (NSString *)storeBundleID {
    // Assuming this format never changes...
    // group.BUNDLEID.YOURTEAMID
    return [self.appGroupID substringWithRange:NSMakeRange(6, self.appGroupID.length - 17)];
}

+ (NSURL *)storeBundlePath {
    NSURL *appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.appGroupID];
    appGroupPath = [appGroupPath URLByAppendingPathComponent:[NSString stringWithFormat:@"Apps/%@/App.app", self.storeBundleID]];
    return appGroupPath;
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

+ (NSProgress *)signAppBundle:(NSURL *)path completionHandler:(void (^)(BOOL success, NSError *error))completionHandler {
    NSError *error;

    // I'm too lazy to reimplement signer, so let's borrow everything from SideStore
    // For sure this will break in the future as SideStore team planned to rewrite it
    NSURL *profilePath = [NSBundle.mainBundle URLForResource:@"embedded" withExtension:@"mobileprovision"];

    // Load libraries from Documents, yeah
    [self loadStoreFrameworksWithError:&error];
    if (error) {
        completionHandler(NO, error);
        return nil;
    }

    ALTCertificate *cert = [[NSClassFromString(@"ALTCertificate") alloc] initWithP12Data:self.certificateData password:self.certificatePassword];
    ALTProvisioningProfile *profile = [[NSClassFromString(@"ALTProvisioningProfile") alloc] initWithURL:profilePath];

    ALTAccount *account = [NSClassFromString(@"ALTAccount") new];
    ALTTeam *team = [[NSClassFromString(@"ALTTeam") alloc] initWithName:@"" identifier:@"" /*profile.teamIdentifier*/ type:ALTTeamTypeUnknown account:account];
    ALTSigner *signer = [[NSClassFromString(@"ALTSigner") alloc] initWithTeam:team certificate:cert];

    return [signer signAppAtURL:path provisioningProfiles:@[(id)profile] completionHandler:completionHandler];
}

#pragma mark Setup

+ (NSString *)appGroupID {
    return [NSBundle.mainBundle.infoDictionary[@"ALTAppGroups"] firstObject];
}

+ (BOOL)isAppGroupAltStoreLike {
    if (self.appGroupID.length == 0) return NO;
    return [NSFileManager.defaultManager fileExistsAtPath:self.storeBundlePath.path];
}

+ (void)changeMainExecutableTo:(NSString *)exec error:(NSError **)error {
    NSURL *appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.appGroupID];
    NSURL *infoPath = [appGroupPath URLByAppendingPathComponent:@"Apps/com.kdt.livecontainer/App.app/Info.plist"];
    NSMutableDictionary *infoDict = [NSMutableDictionary dictionaryWithContentsOfURL:infoPath];
    if (!infoDict) return;

    infoDict[@"CFBundleExecutable"] = exec;
    [infoDict writeToURL:infoPath error:error];
}

+ (void)writeStoreIDToSetupExecutableWithError:(NSError **)error {
    NSURL *appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.appGroupID];
    NSURL *execPath = [appGroupPath URLByAppendingPathComponent:@"Apps/com.kdt.livecontainer/App.app/JITLessSetup"];
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

+ (NSURL *)archiveIPAWithSetupMode:(BOOL)setup error:(NSError **)error {
    if (setup) {
        [self writeStoreIDToSetupExecutableWithError:error];
        if (*error) return nil;
        [self changeMainExecutableTo:@"JITLessSetup" error:error];
    } else {
        [self changeMainExecutableTo:@"LiveContainer_PleaseDoNotShortenTheExecutableNameBecauseItIsUsedToReserveSpaceForOverwritingThankYou" error:error];
    }
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

    dlopen("/System/Library/PrivateFrameworks/PassKitCore.framework/PassKitCore", RTLD_GLOBAL);
    NSData *zipData = [[NSClassFromString(@"PKZipArchiver") new] zippedDataForURL:tmpPayloadPath.URLByDeletingLastPathComponent];
    if (!zipData) return nil;

    [manager removeItemAtURL:tmpPath error:error];
    if (*error) return nil;

    [zipData writeToURL:tmpIPAPath options:0 error:error];
    if (*error) return nil;

    return tmpIPAPath;
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
    infoDict[@"CFBundleURLTypes"][0][@"CFBundleURLSchemes"][0] = newBundleName;
    infoDict[@"CFBundleIcons~ipad"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"][0] = @"AppIcon2_60x60@2x";
    infoDict[@"CFBundleIcons~ipad"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"][1] = @"AppIcon2_76x76@2x~ipad";
    infoDict[@"CFBundleIcons"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"][0] = @"AppIcon2_60x60@2x";
    
    
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

+ (NSString *)getVersionInfo {
    return [NSClassFromString(@"LCVersionInfo") getVersionStr];
}

@end
