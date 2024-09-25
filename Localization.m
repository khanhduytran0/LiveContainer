//
//  Localization.m
//  LiveContainer
//
//  Created by s s on 2024/9/21.
//
#import "Localization.h"

@implementation NSString (Localization)

// Class method for the English language bundle
+ (NSBundle *)enBundle {
    static NSBundle *enBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *language = @"en";
        NSString *path = [[NSUserDefaults lcMainBundle] pathForResource:language ofType:@"lproj"];
        enBundle = [NSBundle bundleWithPath:path];
    });
    return enBundle;
}

// Instance method to return a localized string
- (NSString *)localized {
    NSString *message = [[NSUserDefaults lcMainBundle] localizedStringForKey:self value:@"" table:nil];
    
    if (![message isEqualToString:self]) {
        return message;
    }

    NSString *forcedString = [[NSString enBundle] localizedStringForKey:self value:nil table:nil];
    
    if (forcedString) {
        return forcedString;
    } else {
        return self;
    }
}

// Instance method for localization with format
- (NSString *)localizeWithFormat:(NSString*)arg1, ... {
    va_list args;
    va_start(args, arg1);
    NSString *formattedString = [NSString localizedStringWithFormat:[self localized], arg1, args];
//    NSString *formattedString = [[NSString alloc] localized:[self localized] arguments:arg1, args];
    va_end(args);
    return formattedString;
}

@end
