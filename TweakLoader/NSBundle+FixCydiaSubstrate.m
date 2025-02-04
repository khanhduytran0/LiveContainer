#import <Foundation/Foundation.h>
#import "utils.h"

__attribute__((constructor))
static void NSBundleHookInit(void) {
    swizzle(NSBundle.class, @selector(bundlePath), @selector(hook_bundlePath));
    swizzle(NSBundle.class, @selector(executablePath), @selector(hook_executablePath));
    
}

@implementation NSBundle(FixCydiaSubstrate)

- (NSString *)hook_bundlePath {
    NSString *path = self.hook_bundlePath;
    if ([path hasPrefix:@"/var"]) {
        return [@"/private" stringByAppendingPathComponent:path];
    }
    return path;
}

- (NSString *)hook_executablePath {
    NSString *path = self.hook_executablePath;
    if ([path hasPrefix:@"/var"]) {
        return [@"/private" stringByAppendingPathComponent:path];
    }
    return path;
}

@end
