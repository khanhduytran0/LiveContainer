#import "AltStoreCore/ALTSigner.h"
#import "LCUtils.h"

#include <dlfcn.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <sys/sysctl.h>

@implementation LCUtils

#pragma mark Certificate password

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

+ (NSData *)certificateData {
    return [NSUserDefaults.standardUserDefaults objectForKey:@"LCCertificateData"];
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

        NSMutableData *data = [NSMutableData dataWithContentsOfURL:fileURL];
        const char *map = data.mutableBytes;
        uint32_t magic = *(uint32_t *)map;
        struct mach_header_64 *header = NULL;
        
        if (magic == FAT_CIGAM) {
            // Find compatible slice
            struct fat_header *fatHeader = (struct fat_header *)map;
            struct fat_arch *arch = (struct fat_arch *)(map + sizeof(struct fat_header));
            struct fat_arch *chosenArch = NULL;
            for (int i = 0; i < OSSwapInt32(fatHeader->nfat_arch); i++) {
                if (OSSwapInt32(arch->cputype) == CPU_TYPE_ARM64) {
                    header = (struct mach_header_64 *)(map + OSSwapInt32(arch->offset));
                    chosenArch = arch;
                    if (OSSwapInt32(arch->cpusubtype) == cpusubtype) {
                        break;
                    }
                }
                arch = (struct fat_arch *)((void *)arch + sizeof(struct fat_arch));
            }
            if (header) {
                // Extract slice
                data = [data subdataWithRange:NSMakeRange(OSSwapInt32(chosenArch->offset), OSSwapInt32(chosenArch->size))].mutableCopy;
                map = data.mutableBytes;
                header = (struct mach_header_64 *)map;
            } else {
                continue;
            }
        } else if (magic == MH_MAGIC_64) {
            header = (struct mach_header_64 *)map;
        }

        if (!header || header->cputype != CPU_TYPE_ARM64 || header->filetype != MH_DYLIB) {
            continue;
        }

        uint8_t *imageHeaderPtr = (uint8_t *)header + sizeof(struct mach_header_64);
        struct load_command *command = (struct load_command *)imageHeaderPtr;
        for(int i = 0; i < header->ncmds > 0; i++) {
            if (command->cmd == LC_CODE_SIGNATURE) {
                struct linkedit_data_command *csCommand = (struct linkedit_data_command *)command;
                void *csData = (void *)((uint8_t *)header + csCommand->dataoff);
                // Nuke it.
                NSLog(@"Removing code signature of %@", fileURL);
                bzero(csData, csCommand->datasize);
                [data writeToURL:fileURL atomically:YES];
                break;
            }
            command = (struct load_command *)((void *)command + command->cmdsize);
        }
    }
}

+ (NSProgress *)signAppBundle:(NSString *)path completionHandler:(void (^)(BOOL success, NSError *error))completionHandler {
    NSError *error;

    // Remove faulty file
    [NSFileManager.defaultManager removeItemAtPath:[path stringByAppendingPathComponent:@"LiveContainer"] error:nil];
    // Remove PlugIns folder
    [NSFileManager.defaultManager removeItemAtPath:[path stringByAppendingPathComponent:@"PlugIns"] error:nil];

    // Remove code signature from all library files
    NSURL *bundleURL = [NSURL fileURLWithPath:path];
    [self removeCodeSignatureFromBundleURL:bundleURL];

    // I'm too lazy to reimplement signer, so let's borrow everything from SideStore
    // For sure this will break in the future as SideStore team planned to rewrite it
    NSURL *appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.appGroupID];
    NSURL *storeBundlePath = [appGroupPath URLByAppendingPathComponent:@"Apps/com.SideStore.SideStore/App.app"];
    NSURL *storeFrameworksPath = [storeBundlePath URLByAppendingPathComponent:@"Frameworks"];
    NSURL *profilePath = [NSBundle.mainBundle URLForResource:@"embedded" withExtension:@"mobileprovision"];

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
    ALTProvisioningProfile *profile = [[NSClassFromString(@"ALTProvisioningProfile") alloc] initWithURL:profilePath];

    ALTAccount *account = [NSClassFromString(@"ALTAccount") new];
    ALTTeam *team = [[NSClassFromString(@"ALTTeam") alloc] initWithName:@"" identifier:@"" /*profile.teamIdentifier*/ type:ALTTeamTypeUnknown account:account];
    ALTSigner *signer = [[NSClassFromString(@"ALTSigner") alloc] initWithTeam:team certificate:cert];

    return [signer signAppAtURL:[NSURL fileURLWithPath:path] provisioningProfiles:@[(id)profile] completionHandler:completionHandler];
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
