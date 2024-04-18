//
//  ALTProvisioningProfile.h
//  AltSign
//
//  Created by Riley Testut on 5/22/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import <Foundation/Foundation.h>

//#import "ALTCapabilities.h"
#import "ALTCertificate.h"

@class ALTAppID;

NS_ASSUME_NONNULL_BEGIN

@interface ALTProvisioningProfile : NSObject <NSCopying>

@property (copy, nonatomic, readonly) NSString *name;
@property (copy, nonatomic, readonly, nullable) NSString *identifier;
@property (copy, nonatomic, readonly) NSUUID *UUID;

@property (copy, nonatomic, readonly) NSString *bundleIdentifier;
@property (copy, nonatomic, readonly) NSString *teamIdentifier;

@property (copy, nonatomic, readonly) NSDate *creationDate;
@property (copy, nonatomic, readonly) NSDate *expirationDate;

@property (copy, nonatomic, readonly) NSDictionary<NSString *, id> *entitlements;
@property (copy, nonatomic, readonly) NSArray<ALTCertificate *> *certificates;
@property (copy, nonatomic, readonly) NSArray<NSString *> *deviceIDs;

@property (readonly) BOOL isFreeProvisioningProfile;

@property (copy, nonatomic, readonly) NSData *data;

- (nullable instancetype)initWithData:(NSData *)data NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithURL:(NSURL *)fileURL;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
