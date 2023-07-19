#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface AppInfo : NSObject {
   NSMutableDictionary* _info;
   NSString* _bundlePath;
}

- (NSMutableDictionary*)info;
- (UIImage*)icon;
- (NSString*)displayName;
- (NSString*)bundlePath;
- (NSString*)bundleIdentifier;
- (NSString*)version;
- (NSString*)LCDataUUID;
- (instancetype)initWithBundlePath:(NSString*)bundlePath;
@end