#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface LCAppInfo : NSObject {
   NSMutableDictionary* _info;
   NSString* _bundlePath;
}
@property NSString* relativeBundlePath;
- (NSMutableDictionary*)info;
- (UIImage*)icon;
- (NSString*)displayName;
- (NSString*)bundlePath;
- (NSString*)bundleIdentifier;
- (NSString*)version;
- (NSString*)dataUUID;
- (NSString*)tweakFolder;
- (NSMutableArray*) urlSchemes;
- (void)setDataUUID:(NSString *)uuid;
- (void)setTweakFolder:(NSString *)tweakFolder;
- (instancetype)initWithBundlePath:(NSString*)bundlePath;
- (NSDictionary *)generateWebClipConfig;
- (void)save;
@end
