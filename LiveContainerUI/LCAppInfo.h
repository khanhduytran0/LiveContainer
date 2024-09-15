#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface LCAppInfo : NSObject {
   NSMutableDictionary* _info;
   NSString* _bundlePath;
}
@property NSString* relativeBundlePath;
@property bool isShared;
- (bool)isJITNeeded;
- (void)setIsJITNeeded:(bool)isJITNeeded;
- (void)setBundlePath:(NSString*)newBundlePath;
- (NSMutableDictionary*)info;
- (UIImage*)icon;
- (NSString*)displayName;
- (NSString*)bundlePath;
- (NSString*)bundleIdentifier;
- (NSString*)version;
- (NSString*)dataUUID;
- (NSString*)getDataUUIDNoAssign;
- (NSString*)tweakFolder;
- (NSMutableArray*) urlSchemes;
- (void)setDataUUID:(NSString *)uuid;
- (void)setTweakFolder:(NSString *)tweakFolder;
- (instancetype)initWithBundlePath:(NSString*)bundlePath;
- (NSDictionary *)generateWebClipConfig;
- (void)save;
- (void)patchExecAndSignIfNeedWithCompletionHandler:(void(^)(NSString* errorInfo))completetionHandler progressHandler:(void(^)(NSProgress* errorInfo))progressHandler  forceSign:(BOOL)forceSign;
- (bool)isHidden;
- (void)setIsHidden:(bool)isHidden;
@end
