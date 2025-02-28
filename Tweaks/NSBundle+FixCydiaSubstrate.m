#import <Foundation/Foundation.h>
#import "Tweaks.h"
#import <objc/runtime.h>

@implementation NSString(LiveContainer)
- (NSString *)lc_realpath {
    // stringByResolvingSymlinksInPath does not fully resolve symlink, and some apps will crash without /private prefix
    char result[PATH_MAX];
    realpath(self.fileSystemRepresentation, result);
    return [NSString stringWithUTF8String:result];
}
@end
@implementation NSBundle(LiveContainer)
// Built-in initWith* will strip out the /private prefix, which could crash certain apps
// This initializer replicates +[NSBundle mainBundle] to solve this issue
- (instancetype)initWithPathForMainBundle:(NSString *)path {
    CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:path.lc_realpath];
    id cfBundle = CFBridgingRelease(CFBundleCreate(NULL, url));
    if(!cfBundle) return nil;
    self = [self init];
    object_setIvar(self, class_getInstanceVariable(self.class, "_cfBundle"), cfBundle);
    return self;
}
@end
