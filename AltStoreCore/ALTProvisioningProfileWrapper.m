#import "ALTProvisioningProfileWrapper.h"

@implementation ALTProvisioningProfileWrapper

- (nullable instancetype)initWithProfile:(ALTProvisioningProfile *)profile {
    self = [self init];
    self.name = profile.name;
    self.identifier = profile.identifier;
    self.UUID = profile.UUID;
    self.name = profile.name;
    self.bundleIdentifier = profile.bundleIdentifier;
    self.teamIdentifier = profile.teamIdentifier;
    self.creationDate = profile.creationDate;
    self.expirationDate = profile.expirationDate;
    self.entitlements = profile.entitlements;
    self.certificates = profile.certificates;
    self.deviceIDs = profile.deviceIDs;
    self.isFreeProvisioningProfile = profile.isFreeProvisioningProfile;
    self.data = profile.data;
    return self;
}

@end
