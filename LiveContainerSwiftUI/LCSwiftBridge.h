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
@end
