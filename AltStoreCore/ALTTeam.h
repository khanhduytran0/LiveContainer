//
//  ALTTeam.h
//  AltSign
//
//  Created by Riley Testut on 5/10/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ALTAccount.h"

typedef NS_ENUM(int16_t, ALTTeamType)
{
    ALTTeamTypeUnknown = 0,
    ALTTeamTypeFree = 1,
    ALTTeamTypeIndividual = 2,
    ALTTeamTypeOrganization = 3,
};

NS_ASSUME_NONNULL_BEGIN

@interface ALTTeam : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) ALTTeamType type;

@property (nonatomic) ALTAccount *account;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithName:(NSString *)name identifier:(NSString *)identifier type:(ALTTeamType)type account:(ALTAccount *)account NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
