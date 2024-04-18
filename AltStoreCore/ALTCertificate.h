//
//  ALTCertificate.h
//  AltSign
//
//  Created by Riley Testut on 5/10/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ALTCertificate : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *serialNumber;

@property (nonatomic, copy, nullable) NSString *identifier;
@property (nonatomic, copy, nullable) NSString *machineName;
@property (nonatomic, copy, nullable) NSString *machineIdentifier;

@property (nonatomic, copy, nullable) NSData *data;
@property (nonatomic, copy, nullable) NSData *privateKey;

- (nullable instancetype)initWithData:(NSData *)data;
- (nullable instancetype)initWithP12Data:(NSData *)p12Data password:(nullable NSString *)password;

- (nullable NSData *)p12Data;
- (nullable NSData *)encryptedP12DataWithPassword:(NSString *)password;

@end

NS_ASSUME_NONNULL_END
