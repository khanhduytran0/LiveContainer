#import <UIKit/UIKit.h>

@interface UIImage(private)
- (UIImage *)_imageWithSize:(CGSize)size;
@end

@interface UIApplication(private)
- (void)suspend;
@end
