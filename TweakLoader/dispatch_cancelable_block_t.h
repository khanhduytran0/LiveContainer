// https://gist.github.com/priore/0ae461cf6e12e64bdc0d
#ifndef dispatch_cancellable_block_h
#define dispatch_cancellable_block_h

#import <Foundation/Foundation.h>

// https://github.com/SebastienThiebaud/dispatch_cancelable_block/issues/2
typedef void(^dispatch_cancelable_block_t)(BOOL cancel, BOOL runNow);

NS_INLINE dispatch_cancelable_block_t dispatch_after_delay(NSTimeInterval delay, dispatch_block_t block) {
    if (block == nil) {
        return nil;
    }
    
    // First we have to create a new dispatch_cancelable_block_t and we also need to copy the block given (if you want more explanations about the __block storage type, read this: https://developer.apple.com/library/ios/documentation/cocoa/conceptual/Blocks/Articles/bxVariables.html#//apple_ref/doc/uid/TP40007502-CH6-SW6
    __block dispatch_cancelable_block_t cancelableBlock = nil;
    __block dispatch_block_t originalBlock = [block copy];
    
    // This block will be executed in NOW() + delay
    dispatch_cancelable_block_t delayBlock = ^(BOOL cancel, BOOL runNow){
        if(runNow) {
            originalBlock();
            originalBlock = nil;
            return;
        }
        
        if (cancel == NO && originalBlock) {
            originalBlock();
        }
        
        // We don't want to hold any objects in the memory
        originalBlock = nil;
    };
    
    cancelableBlock = [delayBlock copy];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // We are now in the future (NOW() + delay). It means the block hasn't been canceled so we can execute it
        if (cancelableBlock) {
            cancelableBlock(NO, NO);
            cancelableBlock = nil;
        }
    });
    
    return cancelableBlock;
}

NS_INLINE void cancel_block(dispatch_cancelable_block_t block) {
    if (block == nil) {
        return;
    }
    
    block(YES, NO);
    block = nil;
}

NS_INLINE void run_block_now(dispatch_cancelable_block_t block) {
    if (block == nil) {
        return;
    }
    
    block(NO, YES);
    block = nil;
}

#endif /* dispatch_cancellable_block_h */
