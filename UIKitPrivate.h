#import <UIKit/UIKit.h>

@interface UIImage(private)
- (UIImage *)_imageWithSize:(CGSize)size;
@end

@interface UIAlertAction(private)
@property(nonatomic, copy) id shouldDismissHandler;
@end

@interface UIActivityContinuationManager : UIResponder
- (NSDictionary*)handleActivityContinuation:(NSDictionary*)activityDict isSuspended:(id)isSuspended;
@end

@interface UIApplication(private)
- (void)suspend;
- (UIActivityContinuationManager*)_getActivityContinuationManager;
@end

@interface UIContextMenuInteraction(private)
- (void)_presentMenuAtLocation:(CGPoint)location;
@end

@interface _UIContextMenuStyle : NSObject <NSCopying>
@property(nonatomic) NSInteger preferredLayout;
+ (instancetype)defaultStyle;
@end

@interface UIOpenURLAction : NSObject
- (NSURL *)url;
- (instancetype)initWithURL:(NSURL *)arg1;
@end

@interface FBSSceneTransitionContext : NSObject
@property (nonatomic,copy) NSSet * actions;
@end

@interface UIApplicationSceneTransitionContext : FBSSceneTransitionContext
@property (nonatomic,retain) NSDictionary * payload;
@end

@interface UITableViewHeaderFooterView(private)
- (void)setText:(NSString *)text;
- (NSString *)text;
@end

@interface UIApplicationSceneSettings : NSObject
@end

@interface UIApplicationSceneClientSettings : NSObject
@end

@interface UIMutableApplicationSceneSettings : UIApplicationSceneSettings
@property (assign,nonatomic) UIDeviceOrientation deviceOrientation;
- (void)setInterfaceOrientation:(NSInteger)o;
@end



@interface UIMutableApplicationSceneClientSettings : UIApplicationSceneClientSettings
@property (assign,nonatomic) UIDeviceOrientation deviceOrientation;
@property(nonatomic, assign) NSInteger interfaceOrientation;
@property(nonatomic, assign) NSInteger statusBarStyle;
@end



@interface FBSMutableSceneParameters : NSObject
@property(nonatomic, copy) UIMutableApplicationSceneSettings *settings;
@end


@interface FBSSceneParameters : NSObject
@property(nonatomic, copy) UIApplicationSceneSettings *settings;
@property(nonatomic, copy) UIApplicationSceneClientSettings *clientSettings;
- (instancetype)initWithXPCDictionary:(NSDictionary*)dict;
@end

@interface UIWindow (private)
- (void)setAutorotates:(BOOL)autorotates forceUpdateInterfaceOrientation:(BOOL)force;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(NSString *)arg1 ;
@end
