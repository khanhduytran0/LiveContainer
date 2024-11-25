//
//  NSUserDefaults.m
//  LiveContainer
//
//  Created by s s on 2024/11/23.
//

#import <Foundation/Foundation.h>
#import "LCSharedUtils.h"
#import "UIKitPrivate.h"
#import "utils.h"
#import "LCSharedUtils.h"

NSMutableDictionary* LCPreferences = 0;

__attribute__((constructor))
static void UIKitGuestHooksInit() {
    NSLog(@"[LC] hook init");
    swizzle(NSUserDefaults.class, @selector(objectForKey:), @selector(hook_objectForKey:));
    swizzle(NSUserDefaults.class, @selector(boolForKey:), @selector(hook_boolForKey:));
    swizzle(NSUserDefaults.class, @selector(integerForKey:), @selector(hook_integerForKey:));
    swizzle(NSUserDefaults.class, @selector(setObject:forKey:), @selector(hook_setObject:forKey:));
    swizzle(NSUserDefaults.class, @selector(removeObjectForKey:), @selector(hook_removeObjectForKey:));
    swizzle(NSUserDefaults.class, @selector(dictionaryRepresentation), @selector(hook_dictionaryRepresentation));
    swizzle(NSUserDefaults.class, @selector(persistentDomainForName:), @selector(hook_persistentDomainForName:));
    swizzle(NSUserDefaults.class, @selector(removePersistentDomainForName:), @selector(hook_removePersistentDomainForName:));
    LCPreferences = [[NSMutableDictionary alloc] init];
    NSFileManager* fm = NSFileManager.defaultManager;
    NSURL* libraryPath = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].lastObject;
    NSURL* preferenceFolderPath = [libraryPath URLByAppendingPathComponent:@"Preferences"];
    if(![fm fileExistsAtPath:preferenceFolderPath.path]) {
        NSError* error;
        [fm createDirectoryAtPath:preferenceFolderPath.path withIntermediateDirectories:YES attributes:@{} error:&error];
    }
    
}

NSURL* LCGetPreferencePath(NSString* identifier) {
    NSFileManager* fm = NSFileManager.defaultManager;
    NSURL* libraryPath = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].lastObject;
    NSURL* preferenceFilePath = [libraryPath URLByAppendingPathComponent:[NSString stringWithFormat: @"Preferences/%@.plist", identifier]];
    return preferenceFilePath;
}

NSMutableDictionary* LCGetPreference(NSString* identifier) {
    if(LCPreferences[identifier]) {
        return LCPreferences[identifier];
    }
    NSURL* preferenceFilePath = LCGetPreferencePath(identifier);
    if([NSFileManager.defaultManager fileExistsAtPath:preferenceFilePath.path]) {
        LCPreferences[identifier] = [NSMutableDictionary dictionaryWithContentsOfFile:preferenceFilePath.path];
    } else {
        LCPreferences[identifier] = [[NSMutableDictionary alloc] init];
    }
    return LCPreferences[identifier];
}



@implementation NSUserDefaults(LiveContainerHooks)

- (id)hook_objectForKey:(NSString*)key {
    // let LiveContainer itself and Apple stuff bypass
    NSString* identifier = [self _identifier];
    NSLog(@"[LC] hook_objectForKey key = %@, identifier = %@", key, identifier);
    id ans = [self hook_objectForKey:key];
    if(ans || [identifier isEqualToString:(__bridge id)kCFPreferencesCurrentApplication]) {
        return ans;
    }
    NSMutableDictionary* preferenceDict = LCGetPreference(identifier);
    return preferenceDict[key];
}

- (BOOL)hook_boolForKey:(NSString*)key {
    id obj = [self objectForKey:key];
    
    if ([obj isKindOfClass:[NSNumber class]]) {
        return [(NSNumber*)obj boolValue];
    } else if([obj isKindOfClass:[NSString class]]) {
        if([[(NSString*)obj lowercaseString] isEqualToString:@"yes"] || [[(NSString*)obj lowercaseString] isEqualToString:@"true"]) {
            return YES;
        } else {
            return NO;
        }
    } else {
        return obj != 0;
    }
    
}

- (NSInteger)hook_integerForKey:(NSString*)key {
    id obj = [self objectForKey:key];
    if([obj isKindOfClass:[NSString class]]) {
        return [(NSString*)obj integerValue];
    } else if ([obj isKindOfClass:[NSNumber class]]) {
        return [(NSNumber*)obj integerValue];
    }
    return 0;
}

- (void)hook_setObject:(id)obj forKey:(NSString*)key {
    // let apple bypass
    NSString* identifier = [self _identifier];
    NSLog(@"[LC] hook_setObjectForKey key = %@, identifier = %@", key, identifier);
    if([self hook_objectForKey:key]) {
        [self hook_setObject:obj forKey:key];
        return;
    }

    NSMutableDictionary* preferenceDict = LCGetPreference(identifier);
    preferenceDict[key] = obj;
    NSURL* preferenceFilePath = LCGetPreferencePath(identifier);
    [preferenceDict writeToURL:preferenceFilePath atomically:YES];

    
}

- (void)hook_removeObjectForKey:(NSString*)key {
    NSString* identifier = [self _identifier];
    if([self hook_objectForKey:key]) {
        [self hook_removeObjectForKey:key];
        return;
    }
    NSMutableDictionary* preferenceDict = LCGetPreference(identifier);
    [preferenceDict removeObjectForKey:key];
    NSURL* preferenceFilePath = LCGetPreferencePath(identifier);
    [preferenceDict writeToURL:preferenceFilePath atomically:YES];
}

- (NSDictionary*) hook_dictionaryRepresentation {
    NSString* identifier = [self _identifier];
    NSMutableDictionary* ans = [[self hook_dictionaryRepresentation] mutableCopy];
    if(ans) {
        [ans addEntriesFromDictionary:LCGetPreference(identifier)];
    } else {
        ans = LCGetPreference(identifier);
    }
    return ans;
    
}

- (NSDictionary*) hook_persistentDomainForName:(NSString*)domainName {
    NSMutableDictionary* ans = [[self hook_persistentDomainForName:domainName] mutableCopy];
    if(ans) {
        [ans addEntriesFromDictionary:LCGetPreference(domainName)];
    } else {
        ans = LCGetPreference(domainName);
    }
    return ans;
    
}

- (void) hook_removePersistentDomainForName:(NSString*)domainName {
    NSMutableDictionary* ans = [[self hook_persistentDomainForName:domainName] mutableCopy];
    if(ans) {
        [self hook_removePersistentDomainForName:domainName];
    } else {
        [LCPreferences removeObjectForKey:domainName];
    }
    NSURL* preferenceFilePath = LCGetPreferencePath(domainName);
    NSFileManager* fm = NSFileManager.defaultManager;
    if([fm fileExistsAtPath:preferenceFilePath.path]) {
        NSError* error;
        [fm removeItemAtURL:preferenceFilePath error:&error];
    }
    
}

@end
