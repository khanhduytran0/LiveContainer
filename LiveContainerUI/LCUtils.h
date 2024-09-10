#import <Foundation/Foundation.h>

typedef void (^LCParseMachOCallback)(const char *path, struct mach_header_64 *header);

NSString *LCParseMachO(const char *path, LCParseMachOCallback callback);
void LCPatchAddRPath(const char *path, struct mach_header_64 *header);
void LCPatchExecSlice(const char *path, struct mach_header_64 *header);
void LCChangeExecUUID(struct mach_header_64 *header);

@interface PKZipArchiver : NSObject

- (NSData *)zippedDataForURL:(NSURL *)url;

@end

@interface LCUtils : NSObject

+ (NSURL *)archiveIPAWithSetupMode:(BOOL)setup error:(NSError **)error;
+ (NSURL *)archiveIPAWithBundleName:(NSString*)newBundleName error:(NSError **)error;
+ (NSData *)certificateData;
+ (NSString *)certificatePassword;
+ (void)setCertificateData:(NSData *)data;
+ (void)setCertificatePassword:(NSString *)password;
+ (BOOL)deleteKeychainItem:(NSString *)key ofStore:(NSString *)store;
+ (NSData *)keychainItem:(NSString *)key ofStore:(NSString *)store;

+ (BOOL)askForJIT;
+ (BOOL)launchToGuestApp;
+ (BOOL)launchToGuestAppWithURL:(NSURL *)url;

+ (void)removeCodeSignatureFromBundleURL:(NSURL *)appURL;
+ (NSProgress *)signAppBundle:(NSURL *)path completionHandler:(void (^)(BOOL success, NSError *error))completionHandler;

+ (BOOL)isAppGroupAltStoreLike;
+ (NSString *)appGroupID;
+ (NSString *)appUrlScheme;
+ (NSURL *)appGroupPath;
+ (NSString *)storeInstallURLScheme;
+ (NSString *)getVersionInfo;
@end
