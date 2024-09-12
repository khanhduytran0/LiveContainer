@import Foundation;
#import "utils.h"
#import "LCSharedUtils.h"

__attribute__((constructor))
static void NSFMGuestHooksInit() {
    swizzle(NSFileManager.class, @selector(containerURLForSecurityApplicationGroupIdentifier:), @selector(hook_containerURLForSecurityApplicationGroupIdentifier:));
}

// NSFileManager simulate app group
@implementation NSFileManager(LiveContainerHooks)

- (nullable NSURL *)hook_containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    if([groupIdentifier isEqualToString:[NSClassFromString(@"LCSharedUtils") appGroupID]]) {
        return [self hook_containerURLForSecurityApplicationGroupIdentifier: groupIdentifier];
    }
    
    NSURL *result = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%s/Documents/Data/AppGroup/%@", getenv("LC_HOME_PATH"), groupIdentifier]];
    [NSFileManager.defaultManager createDirectoryAtURL:result withIntermediateDirectories:YES attributes:nil error:nil];
    return result;
}

@end
