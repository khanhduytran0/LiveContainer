#import "UIKitPrivate.h"
#import "UIViewController+LCAlert.h"

@implementation UIViewController(LCAlert)

- (void)showDialogTitle:(NSString *)title message:(NSString *)message {
    [self showDialogTitle:title message:message handler:nil];
}

- (void)showDialogTitle:(NSString *)title message:(NSString *)message handler:(void(^)(UIAlertAction *))handler {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:handler];
    [alert addAction:okAction];
    UIAlertAction* copyAction = [UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction * action) {
            UIPasteboard.generalPasteboard.string = message;
            if (handler) handler(action);
        }];
    [alert addAction:copyAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showInputDialogTitle:(NSString *)title message:(NSString *)message placeholder:(NSString *)placeholder callback:(NSString *(^)(NSString *inputText))callback {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = placeholder;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.borderStyle = UITextBorderStyleRoundedRect;
    }];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *textField = alert.textFields[0];
        NSString *error = callback(textField.text.length == 0 ? placeholder : textField.text);
        if (error) {
            alert.message = error;
        } else {
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    }];
    okAction.shouldDismissHandler = ^{
        return NO;
    };
    [alert addAction:okAction];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
