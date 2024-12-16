#import <Foundation/Foundation.h>
#import "utils.h"
#import <VideoSubscriberAccount/VideoSubscriberAccount.h>

@interface FBSSerialQueue1 : NSObject
-(void)assertBarrierOnQueue1;
-(void)assertBarrierOnQueue2;
@end

@implementation FBSSerialQueue1
- (void)assertBarrierOnQueue1 {

}
- (void)assertBarrierOnQueue2 {

}
@end

@implementation VSSubscriptionRegistrationCenter(LiveContainerHook)

- (void)setCurrentSubscription:(id)sub {
    
}

@end

__attribute__((constructor))
static void NSFMGuestHooksInit() {
    if(![[NSBundle.mainBundle infoDictionary][@"bypassAssertBarrierOnQueue"] boolValue]) {
        return;
    }
    
    // Use empty function to replace these functions so assertion will never fail
    method_exchangeImplementations(class_getInstanceMethod(NSClassFromString(@"FBSSerialQueue"), @selector(assertBarrierOnQueue)), class_getInstanceMethod(FBSSerialQueue1.class, @selector(assertBarrierOnQueue1)));
    
    method_exchangeImplementations(class_getInstanceMethod(NSClassFromString(@"FBSMainRunLoopSerialQueue"), @selector(assertBarrierOnQueue)), class_getInstanceMethod(FBSSerialQueue1.class, @selector(assertBarrierOnQueue2)));
}
