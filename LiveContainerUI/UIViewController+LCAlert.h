#import <UIKit/UIKit.h>

@interface UIViewController(LCAlert)

- (void)showDialogTitle:(NSString *)title message:(NSString *)message;
- (void)showDialogTitle:(NSString *)title message:(NSString *)message handler:(void(^)(UIAlertAction *))handler;
- (void)showConfirmationDialogTitle:(NSString *)title message:(NSString *)message destructive:(BOOL)destructive confirmButtonTitle:(NSString *)confirmBtnTitle handler:(void(^)(UIAlertAction *))handler;
- (void)showInputDialogTitle:(NSString *)title message:(NSString *)message placeholder:(NSString *)placeholder callback:(NSString *(^)(NSString *inputText))callback;

@end
