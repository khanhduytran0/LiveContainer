#import <UIKit/UIKit.h>

typedef void(^CreateView)(UITableViewCell *, NSString *,NSString *, NSDictionary *);
typedef id (^GetPreferenceBlock)(NSString *, NSString *);
typedef void (^SetPreferenceBlock)(NSString *, NSString *, id);

@interface LCConfigTableViewController : UITableViewController<UITextFieldDelegate>

@property(nonatomic) CreateView typeButton, typeChildPane, typePickField, typeTextField, typeSlider, typeSwitch;

@property(nonatomic) GetPreferenceBlock getPreference;
@property(nonatomic) SetPreferenceBlock setPreference;
@property(nonatomic) BOOL prefSectionsVisible, hasDetail;

@property(nonatomic) NSArray<NSString*>* prefSections;
@property(nonatomic) NSMutableArray<NSNumber*>* prefSectionsVisibility;
@property(nonatomic) NSArray<NSArray<NSDictionary*>*>* prefContents;
@property(nonatomic) BOOL prefDetailVisible;

@end
