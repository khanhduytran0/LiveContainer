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

@end
