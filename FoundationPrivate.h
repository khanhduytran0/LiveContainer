#include <Foundation/Foundation.h>

@interface NSBundle(private)
- (id)_cfBundle;
@end

@interface NSUserDefaults(private)
+ (void)setStandardUserDefaults:(id)defaults;
- (NSString*)_identifier;
@end
