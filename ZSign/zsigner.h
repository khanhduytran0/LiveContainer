//
//  zsigner.h
//  LiveContainer
//
//  Created by s s on 2024/11/10.
//
#import <Foundation/Foundation.h>

@interface ZSigner : NSObject
+ (NSProgress*)signWithAppPath:(NSString *)appPath prov:(NSData *)prov key:(NSData *)key pass:(NSString *)pass completionHandler:(void (^)(BOOL success, NSDate* expirationDate, NSString* teamId, NSError *error))completionHandler;
@end
