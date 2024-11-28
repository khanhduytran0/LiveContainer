@import Foundation;

@interface LCSharedUtils : NSObject
+ (NSString *)appGroupID;
+ (NSString *)certificatePassword;
+ (BOOL)askForJIT;
+ (BOOL)launchToGuestApp;
+ (BOOL)launchToGuestAppWithURL:(NSURL *)url;
+ (void)setWebPageUrlForNextLaunch:(NSString*)urlString;
+ (NSString*)getAppRunningLCSchemeWithBundleId:(NSString*)bundleId;
+ (void)setAppRunningByThisLC:(NSString*)bundleId;
+ (void)moveSharedAppFolderBack;
+ (void)removeAppRunningByLC:(NSString*)LCScheme;
+ (NSBundle*)findBundleWithBundleId:(NSString*)bundleId;
+ (void)dumpPreferenceToPath:(NSString*)plistLocationTo dataUUID:(NSString*)dataUUID;
@end
