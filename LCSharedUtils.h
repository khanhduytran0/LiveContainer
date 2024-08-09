@import Foundation;

@interface LCSharedUtils : NSObject

+ (NSString *)certificatePassword;
+ (BOOL)launchToGuestApp;
+ (BOOL)launchToGuestAppWithURL:(NSURL *)url;

@end
