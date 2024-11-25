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
#import "dispatch_cancelable_block_t.h"

NSMutableDictionary* LCPreferences = 0;
NSMutableDictionary<NSString*, dispatch_cancelable_block_t>* LCPreferencesDispatchBlock = 0;
BOOL LCIsTerminateFlushHappened = NO;
dispatch_semaphore_t LCPreferencesDispatchBlockSemaphore;

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
    LCPreferencesDispatchBlock = [[NSMutableDictionary alloc] init];
    LCPreferencesDispatchBlockSemaphore = dispatch_semaphore_create(1);
    NSFileManager* fm = NSFileManager.defaultManager;
    NSURL* libraryPath = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].lastObject;
    NSURL* preferenceFolderPath = [libraryPath URLByAppendingPathComponent:@"Preferences"];
    if(![fm fileExistsAtPath:preferenceFolderPath.path]) {
        NSError* error;
        [fm createDirectoryAtPath:preferenceFolderPath.path withIntermediateDirectories:YES attributes:@{} error:&error];
    }
    
    // flush any scheduled write to disk now
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillTerminateNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull notification) {
        LCIsTerminateFlushHappened = YES;
        dispatch_semaphore_wait(LCPreferencesDispatchBlockSemaphore, DISPATCH_TIME_FOREVER);
        for(NSString* key in LCPreferencesDispatchBlock) {
            if(LCPreferencesDispatchBlock[key]) {
                run_block_now(LCPreferencesDispatchBlock[key]);
            }
        }
        dispatch_semaphore_signal(LCPreferencesDispatchBlockSemaphore);
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull notification) {
        dispatch_semaphore_wait(LCPreferencesDispatchBlockSemaphore, DISPATCH_TIME_FOREVER);
        for(NSString* key in LCPreferencesDispatchBlock) {
            LCIsTerminateFlushHappened = YES;
            if(LCPreferencesDispatchBlock[key]) {
                run_block_now(LCPreferencesDispatchBlock[key]);
            }
        }
        [LCPreferencesDispatchBlock removeAllObjects];
        LCIsTerminateFlushHappened = NO;
        dispatch_semaphore_signal(LCPreferencesDispatchBlockSemaphore);
    }];
    
    
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
        return LCPreferences[identifier];
    } else {
        return nil;
    }
    
}

void LCScheduleWriteBack(NSString* identifier) {
    // debounce, write to disk if no write takes place after 2s
    dispatch_cancelable_block_t task = dispatch_after_delay(2, ^{
        NSURL* preferenceFilePath = LCGetPreferencePath(identifier);
        [LCPreferences[identifier] writeToURL:preferenceFilePath atomically:YES];
        if(!LCIsTerminateFlushHappened) {
            LCPreferencesDispatchBlock[identifier] = nil;
        }
    });
    if(LCIsTerminateFlushHappened) {
        // flush now
        run_block_now(task);
        return;
    }
    
    if(LCPreferencesDispatchBlock[identifier]) {
        cancel_block(LCPreferencesDispatchBlock[identifier]);
    }
    dispatch_semaphore_wait(LCPreferencesDispatchBlockSemaphore, DISPATCH_TIME_FOREVER);
    LCPreferencesDispatchBlock[identifier] = task;
    dispatch_semaphore_signal(LCPreferencesDispatchBlockSemaphore);
}

@implementation NSUserDefaults(LiveContainerHooks)

- (id)hook_objectForKey:(NSString*)key {
    // let LiveContainer itself bypass
    NSString* identifier = [self _identifier];
    if([identifier isEqualToString:(__bridge id)kCFPreferencesCurrentApplication]) {
        return [self hook_objectForKey:key];
    }
    
    // priortize local preference file over values in native NSUserDefaults
    NSMutableDictionary* preferenceDict = LCGetPreference(identifier);
    if(preferenceDict && preferenceDict[key]) {
        return preferenceDict[key];
    } else {
        return [self hook_objectForKey:key];
    }
}

- (BOOL)hook_boolForKey:(NSString*)key {
    id obj = [self objectForKey:key];
    if(!obj) {
        return NO;
    } else if ([obj isKindOfClass:[NSNumber class]]) {
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
    if(!obj) {
        return 0;
    } else if([obj isKindOfClass:[NSString class]]) {
        return [(NSString*)obj integerValue];
    } else if ([obj isKindOfClass:[NSNumber class]]) {
        return [(NSNumber*)obj integerValue];
    }
    return 0;
}

- (void)hook_setObject:(id)obj forKey:(NSString*)key {
    // let LiveContainer itself bypess
    NSString* identifier = [self _identifier];
    if([identifier isEqualToString:(__bridge id)kCFPreferencesCurrentApplication]) {
        return [self hook_setObject:obj forKey:key];
    }
    NSMutableDictionary* preferenceDict = LCGetPreference(identifier);
    if(!preferenceDict) {
        preferenceDict = [[NSMutableDictionary alloc] init];
        LCPreferences[identifier] = preferenceDict;
    }
    preferenceDict[key] = obj;
    LCScheduleWriteBack(identifier);
    
}

- (void)hook_removeObjectForKey:(NSString*)key {
    NSString* identifier = [self _identifier];
    if([self hook_objectForKey:key]) {
        [self hook_removeObjectForKey:key];
        return;
    }
    NSMutableDictionary* preferenceDict = LCGetPreference(identifier);
    if(!preferenceDict) {
        return;
    }

    [preferenceDict removeObjectForKey:key];
    // debounce, write to disk if no write takes place after 3s
    LCScheduleWriteBack(identifier);
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
        // delete NOW
        if(LCPreferencesDispatchBlock[domainName]) {
            cancel_block(LCPreferencesDispatchBlock[domainName]);
            dispatch_semaphore_wait(LCPreferencesDispatchBlockSemaphore, DISPATCH_TIME_FOREVER);
            LCPreferencesDispatchBlock[domainName] = nil;
            dispatch_semaphore_signal(LCPreferencesDispatchBlockSemaphore);
        }
    }
    NSURL* preferenceFilePath = LCGetPreferencePath(domainName);
    NSFileManager* fm = NSFileManager.defaultManager;
    if([fm fileExistsAtPath:preferenceFilePath.path]) {
        NSError* error;
        [fm removeItemAtURL:preferenceFilePath error:&error];
    }
    
}

@end
