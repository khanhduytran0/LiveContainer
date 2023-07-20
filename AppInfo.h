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
- (NSString*)dataUUID;
- (void)setDataUUID:(NSString *)uuid;
- (instancetype)initWithBundlePath:(NSString*)bundlePath;
- (void)save;
@end