@import Foundation;
@import ObjectiveC;

void swizzle(Class class, SEL originalAction, SEL swizzledAction);
void swizzleClassMethod(Class class, SEL originalAction, SEL swizzledAction);

// Exported from the main executable
@interface NSUserDefaults(LiveContainer)
+ (instancetype)lcSharedDefaults;
+ (instancetype)lcUserDefaults;
+ (NSString *)lcAppUrlScheme;
+ (NSString *)lcAppGroupPath;
+ (NSBundle *)lcMainBundle;
+ (NSDictionary*)guestAppInfo;
@end
