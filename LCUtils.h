#import <Foundation/Foundation.h>

void LCPatchExecutable(const char *path, NSString **error);

@interface PKZipArchiver : NSObject

- (NSData *)zippedDataForURL:(NSURL *)url;

@end

@interface LCSharedUtils : NSObject

+ (NSString *)certificatePassword;
+ (BOOL)launchToGuestApp;
+ (BOOL)launchToGuestAppWithURL:(NSURL *)url;

@end

@interface LCUtils : NSObject

+ (NSURL *)archiveIPAWithSetupMode:(BOOL)setup error:(NSError **)error;
+ (NSData *)certificateData;
+ (NSString *)certificatePassword;
+ (void)setCertificateData:(NSData *)data;
+ (void)setCertificatePassword:(NSString *)password;
+ (NSData *)keychainItem:(NSString *)key ofStore:(NSString *)store;

+ (BOOL)launchToGuestApp;
+ (BOOL)launchToGuestAppWithURL:(NSURL *)url;

+ (void)removeCodeSignatureFromBundleURL:(NSURL *)appURL;
+ (NSProgress *)signAppBundle:(NSURL *)path completionHandler:(void (^)(BOOL success, NSError *error))completionHandler;

+ (BOOL)isAppGroupSideStore;

@end
