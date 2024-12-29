@import Foundation;
#import "utils.h"
#import "LCSharedUtils.h"

BOOL isolateAppGroup = NO;
__attribute__((constructor))
static void NSFMGuestHooksInit() {
    NSString* containerInfoPath = [[NSString stringWithUTF8String:getenv("HOME")] stringByAppendingPathComponent:@"LCContainerInfo.plist"];
    NSDictionary* infoDict = [NSDictionary dictionaryWithContentsOfFile:containerInfoPath];
    isolateAppGroup = [infoDict[@"isolateAppGroup"] boolValue];
    swizzle(NSFileManager.class, @selector(containerURLForSecurityApplicationGroupIdentifier:), @selector(hook_containerURLForSecurityApplicationGroupIdentifier:));
}

// NSFileManager simulate app group
@implementation NSFileManager(LiveContainerHooks)

- (nullable NSURL *)hook_containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    if([groupIdentifier isEqualToString:[NSClassFromString(@"LCSharedUtils") appGroupID]]) {
        return [NSURL fileURLWithPath: NSUserDefaults.lcAppGroupPath];
    }
    NSURL *result;
    if(isolateAppGroup) {
        result = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%s/LCAppGroup/%@", getenv("HOME"), groupIdentifier]];
    } else {
        result = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/LiveContainer/Data/AppGroup/%@", NSUserDefaults.lcAppGroupPath, groupIdentifier]];
    }
    [NSFileManager.defaultManager createDirectoryAtURL:result withIntermediateDirectories:YES attributes:nil error:nil];
    return result;
}

@end
