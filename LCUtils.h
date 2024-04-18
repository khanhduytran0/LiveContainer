#import <Foundation/Foundation.h>

@interface PKZipArchiver : NSObject

- (NSData *)zippedDataForURL:(NSURL *)url;

@end

@interface LCUtils : NSObject

+ (NSString *)certPassword;
+ (void)updateCertPassword;
+ (NSData *)storeCertPassword;

+ (BOOL)isAppGroupSideStore;
+ (NSError *)changeMainExecutableTo:(NSString *)exec;

+ (NSURL *)archiveIPAWithError:(NSError **)error;

@end
