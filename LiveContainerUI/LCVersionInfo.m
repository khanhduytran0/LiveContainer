#import "LCVersionInfo.h"

@implementation LCVersionInfo
+ (NSString*)getVersionStr {
    return [NSString stringWithFormat:@"Version %@-%s (%s/%s)",
        NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"],
        CONFIG_TYPE, CONFIG_BRANCH, CONFIG_COMMIT];
}
@end