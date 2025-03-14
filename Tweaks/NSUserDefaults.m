//
//  NSUserDefaults.m
//  LiveContainer
//
//  Created by s s on 2024/11/29.
//

#import "FoundationPrivate.h"
#import "LCSharedUtils.h"
#import "utils.h"
#import "LCSharedUtils.h"

void swizzle(Class class, SEL originalAction, SEL swizzledAction) {
    method_exchangeImplementations(class_getInstanceMethod(class, originalAction), class_getInstanceMethod(class, swizzledAction));
}

NSMutableDictionary* LCPreferences = 0;

void NUDGuestHooksInit() {
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
    
    [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationWillTerminateNotification"
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull notification) {
        // restore language if needed
        NSArray* savedLaunguage = [NSUserDefaults.lcUserDefaults objectForKey:@"LCLastLanguages"];
        if(savedLaunguage) {
            [NSUserDefaults.lcUserDefaults setObject:savedLaunguage forKey:@"AppleLanguages"];
        }
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

// save preference to livecontainer's user default
void LCSavePreference(void) {
    NSString* containerId = [[NSString stringWithUTF8String:getenv("HOME")] lastPathComponent];
    [NSUserDefaults.lcUserDefaults setObject:LCPreferences forKey:containerId];
}

@implementation NSUserDefaults(LiveContainerHooks)

- (NSString*)realIdentifier {
    NSString* identifier = [self _identifier];
    if([identifier hasPrefix:@"com.kdt.livecontainer"]) {
        return NSUserDefaults.standardUserDefaults._identifier;
    } else {
        return identifier;
    }
}

- (id)hook_objectForKey:(NSString*)key {
    // let LiveContainer itself bypass
    NSString* identifier = [self realIdentifier];
    if(self == [NSUserDefaults lcUserDefaults]) {
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
        NSString* lowered = [(NSString*)obj lowercaseString];
        if([lowered isEqualToString:@"yes"] || [lowered isEqualToString:@"true"] || [lowered boolValue]) {
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
    NSString* identifier = [self realIdentifier];
    if(self == [NSUserDefaults lcUserDefaults]) {
        return [self hook_setObject:obj forKey:key];
    }
    @synchronized (LCPreferences) {
        NSMutableDictionary* preferenceDict = LCGetPreference(identifier);
        if(!preferenceDict) {
            preferenceDict = [[NSMutableDictionary alloc] init];
            LCPreferences[identifier] = preferenceDict;
        }
        preferenceDict[key] = obj;
        LCSavePreference();
    }
}

- (void)hook_removeObjectForKey:(NSString*)key {
    NSString* identifier = [self realIdentifier];
    if([self hook_objectForKey:key]) {
        [self hook_removeObjectForKey:key];
        return;
    }
    @synchronized (LCPreferences) {
        NSMutableDictionary* preferenceDict = LCGetPreference(identifier);
        if(!preferenceDict) {
            return;
        }
        [preferenceDict removeObjectForKey:key];
        LCSavePreference();
    }
}

- (NSDictionary*) hook_dictionaryRepresentation {
    NSString* identifier = [self realIdentifier];
    NSMutableDictionary* ans = [[self hook_dictionaryRepresentation] mutableCopy];
    if(ans) {
        @synchronized (LCPreferences) {
            [ans addEntriesFromDictionary:LCGetPreference(identifier)];
        }
    } else {
        ans = LCGetPreference(identifier);
    }
    return ans;
    
}

- (NSDictionary*) hook_persistentDomainForName:(NSString*)domainName {
    if([domainName hasPrefix:@"com.kdt.livecontainer"]) {
        domainName = NSUserDefaults.standardUserDefaults._identifier;
    }
    
    NSMutableDictionary* ans = [[self hook_persistentDomainForName:domainName] mutableCopy];
    if(ans) {
        @synchronized (LCPreferences) {
            [ans addEntriesFromDictionary:LCGetPreference(domainName)];
        }
    } else {
        ans = LCGetPreference(domainName);
    }
    return ans;
    
}

- (void) hook_removePersistentDomainForName:(NSString*)domainName {
    NSMutableDictionary* ans = [[self hook_persistentDomainForName:domainName] mutableCopy];
    @synchronized (LCPreferences) {
        if(ans) {
            [self hook_removePersistentDomainForName:domainName];
        } else {
            // empty dictionary means deletion
            [LCPreferences setObject:[[NSMutableDictionary alloc] init] forKey:domainName];
            LCSavePreference();
        }
        NSURL* preferenceFilePath = LCGetPreferencePath(domainName);
        NSFileManager* fm = NSFileManager.defaultManager;
        if([fm fileExistsAtPath:preferenceFilePath.path]) {
            NSError* error;
            [fm removeItemAtURL:preferenceFilePath error:&error];
        }
    }
}

@end
