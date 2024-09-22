//
//  ObjcBridge.m
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/22.
//

#import <Foundation/Foundation.h>

#import "LCSwiftBridge.h"

@implementation LCSwiftBridge

+ (UIViewController * _Nonnull)getRootVC {
    return [LCObjcBridge getRootVC];
}

+ (void)openWebPageWithUrlStr:(NSString*  _Nonnull)urlStr {
    [LCObjcBridge openWebPageWithUrlStr:urlStr];
}

+ (void)launchAppWithBundleId:(NSString*  _Nonnull)bundleId {
    [LCObjcBridge launchAppWithBundleId:bundleId];
}

/*
+ (void)showMachOFileInfo:(NSString*  _Nonnull)filePath resultOutput:(NSString* _Nonnull)result {
    [LCObjcBridge showMachOFileInfo:filePath resultOutput:result];
}
*/

@end

// make SFSafariView happy and open data: URLs
@implementation NSURL(hack)
- (BOOL)safari_isHTTPFamilyURL {
    // Screw it, Apple
    return YES;
}
@end
