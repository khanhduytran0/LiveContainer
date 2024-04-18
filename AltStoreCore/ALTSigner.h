//
//  ALTSigner.h
//  AltSign
//
//  Created by Riley Testut on 5/22/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ALTCertificate.h"
#import "ALTProvisioningProfile.h"
#import "ALTTeam.h"

@class ALTAppID;

NS_ASSUME_NONNULL_BEGIN

@interface ALTSigner : NSObject

@property (nonatomic) ALTTeam *team;
@property (nonatomic) ALTCertificate *certificate;

- (instancetype)initWithTeam:(ALTTeam *)team certificate:(ALTCertificate *)certificate;

- (NSProgress *)signAppAtURL:(NSURL *)appURL provisioningProfiles:(NSArray<ALTProvisioningProfile *> *)profiles completionHandler:(void (^)(BOOL success, NSError * error))completionHandler;

@end

NS_ASSUME_NONNULL_END
