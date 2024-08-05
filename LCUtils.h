#import <Foundation/Foundation.h>

@interface PKZipArchiver : NSObject

- (NSData *)zippedDataForURL:(NSURL *)url;

@end

@interface LCUtils : NSObject

+ (NSData *)certificateData;
+ (NSString *)certificatePassword;
+ (void)setCertificatePassword:(NSString *)password;

+ (NSData *)keychainItem:(NSString *)key ofStore:(NSString *)store;
+ (void)removeCodeSignatureFromBundleURL:(NSURL *)appURL;
+ (NSProgress *)signAppBundle:(NSURL *)path completionHandler:(void (^)(BOOL success, NSError *error))completionHandler;

+ (BOOL)isAppGroupSideStore;

+ (NSURL *)archiveIPAWithSetupMode:(BOOL)setup error:(NSError **)error;

@end
