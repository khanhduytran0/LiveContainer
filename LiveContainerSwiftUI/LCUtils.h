#import <Foundation/Foundation.h>

typedef void (^LCParseMachOCallback)(const char *path, struct mach_header_64 *header);

typedef NS_ENUM(NSInteger, Store){
    SideStore,
    AltStore
};

NSString *LCParseMachO(const char *path, LCParseMachOCallback callback);
void LCPatchAddRPath(const char *path, struct mach_header_64 *header);
void LCPatchExecSlice(const char *path, struct mach_header_64 *header);
void LCChangeExecUUID(struct mach_header_64 *header);
void LCPatchAltStore(const char *path, struct mach_header_64 *header);

@interface PKZipArchiver : NSObject

- (NSData *)zippedDataForURL:(NSURL *)url;

@end

@interface LCUtils : NSObject

+ (void)validateJITLessSetupWithCompletionHandler:(void (^)(BOOL success, NSError *error))completionHandler;
+ (NSURL *)archiveIPAWithBundleName:(NSString*)newBundleName error:(NSError **)error;
+ (NSURL *)archiveTweakedAltStoreWithError:(NSError **)error;
+ (NSData *)certificateData;
+ (NSString *)certificatePassword;
+ (BOOL)deleteKeychainItem:(NSString *)key ofStore:(NSString *)store;
+ (NSData *)keychainItem:(NSString *)key ofStore:(NSString *)store;

+ (BOOL)askForJIT;
+ (BOOL)launchToGuestApp;
+ (BOOL)launchToGuestAppWithURL:(NSURL *)url;

+ (void)removeCodeSignatureFromBundleURL:(NSURL *)appURL;
+ (NSProgress *)signAppBundle:(NSURL *)path completionHandler:(void (^)(BOOL success, NSDate* expirationDate, NSError *error))completionHandler;
+ (BOOL)isAppGroupAltStoreLike;
+ (Store)store;
+ (NSString *)appGroupID;
+ (NSString *)appUrlScheme;
+ (NSURL *)appGroupPath;
+ (NSString *)storeInstallURLScheme;
+ (NSString *)getVersionInfo;
@end

