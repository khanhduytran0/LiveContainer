#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface SignTmpStatus : NSObject
@property NSUInteger newSignId;
@property NSString *tmpExecPath;
@property NSString *infoPath;

@end

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
@property SignTmpStatus* _signStatus;
- (NSString*)patchExec;
- (void) signCleanUpWithSuccessStatus:(BOOL)isSignSuccess;
- (bool)isHidden;
- (void)setIsHidden:(bool)isHidden;
@end
