//
//  ALTProvisioningProfile.h
//  AltSign
//
//  Created by Riley Testut on 5/22/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ALTProvisioningProfile.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALTProvisioningProfileWrapper : NSObject

@property (copy, nonatomic) NSString *name;
@property (copy, nonatomic, nullable) NSString *identifier;
@property (copy, nonatomic) NSUUID *UUID;

@property (copy, nonatomic) NSString *bundleIdentifier;
@property (copy, nonatomic) NSString *teamIdentifier;

@property (copy, nonatomic) NSDate *creationDate;
@property (copy, nonatomic) NSDate *expirationDate;

@property (copy, nonatomic) NSDictionary<NSString *, id> *entitlements;
@property (copy, nonatomic) NSArray<ALTCertificate *> *certificates;
@property (copy, nonatomic) NSArray<NSString *> *deviceIDs;

@property BOOL isFreeProvisioningProfile;

@property (copy, nonatomic) NSData *data;

- (nullable instancetype)initWithProfile:(ALTProvisioningProfile *)profile;
@end

NS_ASSUME_NONNULL_END
