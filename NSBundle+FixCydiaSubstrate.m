#import <Foundation/Foundation.h>

@implementation NSBundle(FixCydiaSubstrate)

- (NSString *)bundlePath {
    NSString *path = self.bundleURL.path;
    if ([path hasPrefix:@"/var"]) {
        return [@"/private" stringByAppendingPathComponent:path];
    }
    return path;
}

@end
