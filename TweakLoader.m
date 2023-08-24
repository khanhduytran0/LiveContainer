#import <Foundation/Foundation.h>
#include <dlfcn.h>

 __attribute__((constructor))
static void TweakLoaderConstructor() {
    const char *tweakFolderC = getenv("LC_TWEAK_FOLDER");
    if (!tweakFolderC) return;
    NSString *tweakFolder = @(tweakFolderC);
    unsetenv("LC_TWEAK_FOLDER");

    NSArray *tweaks = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:tweakFolder error:nil]
      filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return [object hasSuffix:@".dylib"];
    }]];
    for(NSString *tweak in tweaks) {
        NSString *tweakPath = [tweakFolder stringByAppendingPathComponent:tweak];
        void *handle = dlopen(tweakPath.UTF8String, RTLD_LAZY | RTLD_GLOBAL);
        const char *error = dlerror();
        if(handle) {
            NSLog(@"Loaded tweak %@", tweak);
        } else if(error) {
            NSLog(@"Error: %s", error);
        } else {
            NSLog(@"Error: dlopen(%@): Unknown error because dlerror() returns NULL", tweak);
        }
    }
}
