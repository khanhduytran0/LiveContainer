#import <UIKit/UIKit.h>

@interface NSBundle(private)
- (id)_cfBundle;
@end

@interface NSUserDefaults(private)
+ (void)setStandardUserDefaults:(id)defaults;
@end

@interface UIImage(private)
- (UIImage *)_imageWithSize:(CGSize)size;
@end

@interface UIAlertAction(private)
@property(nonatomic, copy) id shouldDismissHandler;
@end

@interface UIApplication(private)
- (void)suspend;
@end

@interface UIContextMenuInteraction(private)
- (void)_presentMenuAtLocation:(CGPoint)location;
@end

@interface _UIContextMenuStyle : NSObject <NSCopying>
@property(nonatomic) NSInteger preferredLayout;
+ (instancetype)defaultStyle;
@end

@interface UITableViewHeaderFooterView(private)
- (void)setText:(NSString *)text;
- (NSString *)text;
@end
