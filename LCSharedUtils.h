@import Foundation;

@interface LCSharedUtils : NSObject
+ (NSString *)appGroupID;
+ (NSString *)certificatePassword;
+ (BOOL)launchToGuestApp;
+ (BOOL)launchToGuestAppWithURL:(NSURL *)url;
+ (void)setWebPageUrlForNextLaunch:(NSString*)urlString;
+ (NSString*)getAppRunningLCSchemeWithBundleId:(NSString*)bundleId;
+ (void)setAppRunningByThisLC:(NSString*)bundleId;
+ (void)setupPreferences:(NSString*) newHomePath;
+ (void)moveSharedAppFolderBack;
+ (void)removeAppRunningByLC:(NSString*)LCScheme;
@end
