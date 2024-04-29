#import <Foundation/Foundation.h>

@implementation NSBundle(FixCydiaSubstrate)

- (NSString *)bundlePath {
    NSString *path = self.bundleURL.path;
    if ([path hasPrefix:@"/private"]) {
        return path;
    }
    return [@"/private" stringByAppendingPathComponent:path];
}

@end
