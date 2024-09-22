//
//  ObjcBridge.h
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/22.
//

#ifndef ObjcBridge_h
#define ObjcBridge_h
#include <UIKit/UIViewController.h>
#import "LiveContainerSwiftUI-Swift.h"
#endif /* ObjcBridge_h */

@interface LCSwiftBridge : NSObject
+ (UIViewController * _Nonnull)getRootVC;
+ (void)openWebPageWithUrlStr:(NSURL* _Nonnull)url;
+ (void)launchAppWithBundleId:(NSString*  _Nonnull)bundleId;
// + (void)showMachOFileInfo:(NSString*  _Nonnull)filePath (NSString* _Nonnull)resultOutput;
@end
