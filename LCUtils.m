#import "LCUtils.h"
#include <dlfcn.h>

@implementation LCUtils

#pragma mark Certificate password

+ (NSString *)storeCertPassword {
    NSDictionary *dict = @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: @"com.SideStore.SideStore",
        (id)kSecAttrAccount: @"signingCertificatePassword",
        (id)kSecAttrSynchronizable: (id)kSecAttrSynchronizableAny,
        (id)kSecMatchLimit: (id)kSecMatchLimitOne,
        (id)kSecReturnData: (id)kCFBooleanTrue
    };
    CFTypeRef result = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)dict, &result);
    if (status == errSecSuccess) {
        return [[NSString alloc] initWithData:(__bridge NSData *)result encoding:NSUTF8StringEncoding];
    } else {
        return nil;
    }
}

+ (void)updateCertPassword {
    [NSUserDefaults.standardUserDefaults setObject:self.storeCertPassword forKey:@"LCCertificateID"];
}

+ (NSString *)certPassword {
    return [NSUserDefaults.standardUserDefaults objectForKey:@"LCCertificateID"];
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
