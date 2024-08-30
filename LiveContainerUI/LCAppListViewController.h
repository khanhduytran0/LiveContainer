#import <UIKit/UIKit.h>

@interface LCAppListViewController : UITableViewController <UIDocumentPickerDelegate>
@property(nonatomic) NSString* acError;
- (void) openWebViewByURLString:(NSString*) urlString;
@end
