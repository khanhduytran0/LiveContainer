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

// NSFileManager simulate app group
@implementation NSUserDefaults(LiveContainerHooks)

- (CFStringRef)hook__container {
    const char *homeDir = getenv("HOME");
    CFStringRef cfHomeDir = CFStringCreateWithCString(NULL, homeDir, kCFStringEncodingUTF8);
    return cfHomeDir;
}

@end
