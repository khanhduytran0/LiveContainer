#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "LCUtils.h"

@interface LCAppInfo : NSObject {
   NSMutableDictionary* _info;
   NSString* _bundlePath;
}
@property NSString* relativeBundlePath;
@property bool isShared;
@property bool isJITNeeded;
@property bool isLocked;
@property bool isHidden;
@property bool doSymlinkInbox;
@property bool bypassAssertBarrierOnQueue;
@property UIColor* cachedColor;
@property Signer signer;
@property bool doUseLCBundleId;
@property NSString* selectedLanguage;
@property NSString* dataUUID;
@property NSArray<NSDictionary*>* containerInfo;

- (void)setBundlePath:(NSString*)newBundlePath;
- (NSMutableDictionary*)info;
- (UIImage*)icon;
- (NSString*)displayName;
- (NSString*)bundlePath;
- (NSString*)bundleIdentifier;
- (NSString*)version;
- (NSString*)tweakFolder;
- (NSMutableArray*) urlSchemes;
- (void)setTweakFolder:(NSString *)tweakFolder;
- (instancetype)initWithBundlePath:(NSString*)bundlePath;
- (UIImage *)generateLiveContainerWrappedIcon;
- (NSDictionary *)generateWebClipConfigWithContainerId:(NSString*)containerId;
- (void)save;
- (void)patchExecAndSignIfNeedWithCompletionHandler:(void(^)(NSString* errorInfo))completetionHandler progressHandler:(void(^)(NSProgress* progress))progressHandler  forceSign:(BOOL)forceSign;
@end
