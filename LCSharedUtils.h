@import Foundation;

@interface LCSharedUtils : NSObject
+ (NSString*) teamIdentifier;
+ (NSString *)appGroupID;
+ (NSURL*) appGroupPath;
+ (NSString *)certificatePassword;
+ (BOOL)launchToGuestApp;
+ (BOOL)launchToGuestAppWithURL:(NSURL *)url;
+ (void)setWebPageUrlForNextLaunch:(NSString*)urlString;
+ (NSString*)getAppRunningLCSchemeWithBundleId:(NSString*)bundleId;
+ (NSString*)getContainerUsingLCSchemeWithFolderName:(NSString*)folderName;
+ (void)setAppRunningByThisLC:(NSString*)bundleId;
+ (void)setContainerUsingByThisLC:(NSString*)folderName;
+ (void)moveSharedAppFolderBack;
+ (void)removeAppRunningByLC:(NSString*)LCScheme;
+ (void)removeContainerUsingByLC:(NSString*)LCScheme;
+ (NSBundle*)findBundleWithBundleId:(NSString*)bundleId;
+ (void)dumpPreferenceToPath:(NSString*)plistLocationTo dataUUID:(NSString*)dataUUID;
+ (NSString*)findDefaultContainerWithBundleId:(NSString*)bundleId;
@end
