#import <Foundation/Foundation.h>
#import "Tweaks.h"
#import <objc/runtime.h>

@implementation NSString(LiveContainer)
- (NSString *)lc_realpath {
    // stringByResolvingSymlinksInPath does not fully resolve symlink, and some apps will cradh without /private prefix
    char result[PATH_MAX];
    realpath(self.fileSystemRepresentation, result);
    return [NSString stringWithUTF8String:result];
}
@end
@implementation NSBundle(LiveContainer)
// Built-in initWith* will strip out the /private prefix, which could crash certain apps
// This initializer replicates +[NSBundle mainBundle] to solve this issue (FIXME: may not work)
- (instancetype)initWithPathForMainBundle:(NSString *)path {
    self = [self init];
    CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:path.lc_realpath];
    object_setIvar(self, class_getInstanceVariable(self.class, "_cfBundle"), CFBridgingRelease(CFBundleCreate(NULL, url)));
    return self;
}
@end
