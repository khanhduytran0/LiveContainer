#import "AltStoreCore/ALTSigner.h"
#import "AltStoreCore/ALTProvisioningProfileWrapper.h"
#import "LCUtils.h"
#include <dlfcn.h>

@implementation LCUtils

#pragma mark Certificate password

+ (NSData *)sidestoreKeychainItem:(NSString *)key {
    NSDictionary *dict = @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: @"com.SideStore.SideStore",
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

+ (void)updateCertificate {
    [NSUserDefaults.standardUserDefaults setObject:[self sidestoreKeychainItem:@"signingCertificate"] forKey:@"LCCertificateData"];
}

+ (NSData *)certificateData {
    return [NSUserDefaults.standardUserDefaults objectForKey:@"LCCertificateData"];
}

+ (NSProgress *)signAppBundle:(NSString *)path completionHandler:(void (^)(BOOL success, NSError *error))completionHandler {
    NSError *error;

    // Remove PlugIns folder
    [NSFileManager.defaultManager removeItemAtPath:[path stringByAppendingPathComponent:@"PlugIns"] error:nil];

    // I'm too lazy to reimplement signer, so let's borrow everything from SideStore
    // For sure this will break in the future as SideStore team planned to rewrite it
    NSURL *appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.appGroupID];
    NSURL *storeBundlePath = [appGroupPath URLByAppendingPathComponent:@"Apps/com.SideStore.SideStore/App.app"];
    NSURL *storeFrameworksPath = [storeBundlePath URLByAppendingPathComponent:@"Frameworks"];
    NSURL *storeProfilePath = [storeBundlePath URLByAppendingPathComponent:@"embedded.mobileprovision"];

    // Load libraries from Documents, yeah
    [[NSBundle bundleWithURL:[storeFrameworksPath URLByAppendingPathComponent:@"OpenSSL.framework"]] loadAndReturnError:&error];
    if (error) {
        completionHandler(NO, error);
        return nil;
    }
    [[NSBundle bundleWithURL:[storeFrameworksPath URLByAppendingPathComponent:@"Roxas.framework"]] loadAndReturnError:&error];
    if (error) {
        completionHandler(NO, error);
        return nil;
    }
    [[NSBundle bundleWithURL:[storeFrameworksPath URLByAppendingPathComponent:@"AltStoreCore.framework"]] loadAndReturnError:&error];
    if (error) {
        completionHandler(NO, error);
        return nil;
    }

    ALTCertificate *cert = [[NSClassFromString(@"ALTCertificate") alloc] initWithP12Data:self.certificateData password:@""];
    ALTProvisioningProfile *profile = [[NSClassFromString(@"ALTProvisioningProfile") alloc] initWithURL:storeProfilePath];

    ALTProvisioningProfileWrapper *profileWrapper = [[ALTProvisioningProfileWrapper alloc] initWithProfile:profile];
    profileWrapper.bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;

    ALTAccount *account = [NSClassFromString(@"ALTAccount") new];
    ALTTeam *team = [[NSClassFromString(@"ALTTeam") alloc] initWithName:@"" identifier:@"" /*profile.teamIdentifier*/ type:ALTTeamTypeUnknown account:account];
    ALTSigner *signer = [[NSClassFromString(@"ALTSigner") alloc] initWithTeam:team certificate:cert];

    return [signer signAppAtURL:[NSURL fileURLWithPath:path] provisioningProfiles:@[(id)profileWrapper] completionHandler:completionHandler];
}

#pragma mark Setup

+ (NSString *)appGroupID {
    return [NSBundle.mainBundle.infoDictionary[@"ALTAppGroups"] firstObject];
}

+ (BOOL)isAppGroupSideStore {
    return [self.appGroupID containsString:@"com.SideStore.SideStore"];
}

+ (NSError *)changeMainExecutableTo:(NSString *)exec {
    NSError *error;
    NSURL *appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.appGroupID];
    NSURL *infoPath = [appGroupPath URLByAppendingPathComponent:@"Apps/com.kdt.livecontainer/App.app/Info.plist"];
    NSMutableDictionary *infoDict = [NSMutableDictionary dictionaryWithContentsOfURL:infoPath];
    if (!infoDict) return nil;

    infoDict[@"CFBundleExecutable"] = exec;
    [infoDict writeToURL:infoPath error:&error];
    return error;
}

+ (NSURL *)archiveIPAWithError:(NSError **)error {
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

@end
