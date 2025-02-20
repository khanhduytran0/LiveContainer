#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "LCUtils.h"

typedef NS_ENUM(NSInteger, LCOrientationLock){
    Disabled = 0,
    Landscape = 1,
    Portrait = 2
};

@interface LCAppInfo : NSObject {
    NSMutableDictionary* _info;
    NSMutableDictionary* _infoPlist;
    NSString* _bundlePath;
}
@property NSString* relativeBundlePath;
@property bool isShared;
@property bool isJITNeeded;
@property bool isLocked;
@property bool isHidden;
@property bool doSymlinkInbox;
@property bool hideLiveContainer;
@property bool fixBlackScreen;
@property bool dontLoadTweakLoader;
@property bool dontInjectTweakLoader;
@property bool bypassAssertBarrierOnQueue;
@property UIColor* cachedColor;
@property Signer signer;
@property LCOrientationLock orientationLock;
@property bool doUseLCBundleId;
@property NSString* selectedLanguage;
@property NSString* dataUUID;
@property NSString* tweakFolder;
@property NSArray<NSDictionary*>* containerInfo;
@property bool autoSaveDisabled;

@property bool is32bit;

- (void)setBundlePath:(NSString*)newBundlePath;
- (NSMutableDictionary*)info;
- (UIImage*)icon;
- (NSString*)displayName;
- (NSString*)bundlePath;
- (NSString*)bundleIdentifier;
- (NSString*)version;
- (NSMutableArray*) urlSchemes;
- (instancetype)initWithBundlePath:(NSString*)bundlePath;
- (UIImage *)generateLiveContainerWrappedIcon;
- (NSDictionary *)generateWebClipConfigWithContainerId:(NSString*)containerId;
- (void)save;
- (void)patchExecAndSignIfNeedWithCompletionHandler:(void(^)(bool success, NSString* errorInfo))completetionHandler progressHandler:(void(^)(NSProgress* progress))progressHandler  forceSign:(BOOL)forceSign;
@end
