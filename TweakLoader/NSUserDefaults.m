//
//  NSUserDefaults.m
//  jump
//
//  Created by s s on 2024/9/2.
//

@import Foundation;
#import "utils.h"

__attribute__((constructor))
static void NSUDGuestHooksInit() {
    swizzle(NSUserDefaults.class, @selector(_container), @selector(hook__container));
}

@interface NSUserDefaults(Private)
- (CFStringRef)_identifier;
@end

@implementation NSUserDefaults(LiveContainerHooks)

- (CFStringRef)hook__container {
    // let LiveContainer it self bypass

    if(self == NSUserDefaults.lcUserDefaults || CFStringHasPrefix([self _identifier], CFSTR("com.apple"))) {
        return [self hook__container];
    }
    const char *homeDir = getenv("HOME");
    CFStringRef cfHomeDir = CFStringCreateWithCString(NULL, homeDir, kCFStringEncodingUTF8);
    return cfHomeDir;
    
}

@end
