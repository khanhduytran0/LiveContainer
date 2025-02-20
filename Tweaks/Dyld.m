//
//  Dyld.m
//  LiveContainer
//
//  Created by s s on 2025/2/7.
//
#include <dlfcn.h>
#include <stdlib.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <mach-o/ldsyms.h>
#import "../fishhook/fishhook.h"
@import Foundation;

@interface NSUserDefaults(LiveContainer)
+ (NSBundle *)lcMainBundle;
@end


uint32_t lcImageIndex = 0;
uint32_t tweakLoaderIndex = 0;
uint32_t appMainImageIndex = 0;
void* appExecutableHandle = 0;
bool tweakLoaderLoaded = false;

void* (*orig_dlsym)(void * __handle, const char * __symbol);
uint32_t (*orig_dyld_image_count)(void);
const struct mach_header* (*orig_dyld_get_image_header)(uint32_t image_index);
intptr_t (*orig_dyld_get_image_vmaddr_slide)(uint32_t image_index);
const char* (*orig_dyld_get_image_name)(uint32_t image_index);

static inline int translateImageIndex(int origin) {
    if(origin == lcImageIndex) {
        return appMainImageIndex;
    }
    
    // find tweakloader index
    if(tweakLoaderLoaded && tweakLoaderIndex == 0) {
        const char* tweakloaderPath = [[[[NSUserDefaults lcMainBundle] bundlePath] stringByAppendingPathComponent:@"Frameworks/TweakLoader.dylib"] UTF8String];
        uint32_t imageCount = orig_dyld_image_count();
        for(uint32_t i = imageCount - 1; i >= 0; --i) {
            const char* imgName = orig_dyld_get_image_name(i);
            if(strcmp(imgName, tweakloaderPath) == 0) {
                tweakLoaderIndex = i;
                break;
            }
        }
        if(tweakLoaderIndex == 0) {
            tweakLoaderIndex = -1; // can't find, don't search again in the future
        }
    }
    
    if(tweakLoaderLoaded && tweakLoaderIndex > 0 && origin >= tweakLoaderIndex) {
        return origin + 2;
    } else if(origin >= appMainImageIndex) {
        return origin + 1;
    }
    return origin;
}


void* hook_dlsym(void * __handle, const char * __symbol) {
    if(__handle == (void*)RTLD_MAIN_ONLY) {
        if(strcmp(__symbol, MH_EXECUTE_SYM) == 0) {
            return (void*)orig_dyld_get_image_header(appMainImageIndex);
        }
        __handle = appExecutableHandle;
    }
    
    __attribute__((musttail)) return orig_dlsym(__handle, __symbol);
}

uint32_t hook_dyld_image_count(void) {
    return orig_dyld_image_count() - 1 - (uint32_t)tweakLoaderLoaded;
}

const struct mach_header* hook_dyld_get_image_header(uint32_t image_index) {
    __attribute__((musttail)) return orig_dyld_get_image_header(translateImageIndex(image_index));
}

intptr_t hook_dyld_get_image_vmaddr_slide(uint32_t image_index) {
    __attribute__((musttail)) return orig_dyld_get_image_vmaddr_slide(translateImageIndex(image_index));
}

const char* hook_dyld_get_image_name(uint32_t image_index) {
    __attribute__((musttail)) return orig_dyld_get_image_name(translateImageIndex(image_index));
}



void DyldHooksInit(bool hideLiveContainer) {
    // iterate through loaded images and find LiveContainer it self
    int imageCount = _dyld_image_count();
    for(int i = 0; i < imageCount; ++i) {
        const struct mach_header* currentImageHeader = _dyld_get_image_header(i);
        if(currentImageHeader->filetype == MH_EXECUTE) {
            lcImageIndex = i;
            break;
        }
    }
    
    orig_dyld_get_image_header = _dyld_get_image_header;
    
    // hook dlsym to solve RTLD_MAIN_ONLY, hook other functions to hide LiveContainer itself
    rebind_symbols((struct rebinding[5]){
        {"dlsym", (void *)hook_dlsym, (void **)&orig_dlsym},
        {"_dyld_image_count", (void *)hook_dyld_image_count, (void **)&orig_dyld_image_count},
        {"_dyld_get_image_header", (void *)hook_dyld_get_image_header, (void **)&orig_dyld_get_image_header},
        {"_dyld_get_image_vmaddr_slide", (void *)hook_dyld_get_image_vmaddr_slide, (void **)&orig_dyld_get_image_vmaddr_slide},
        {"_dyld_get_image_name", (void *)hook_dyld_get_image_name, (void **)&orig_dyld_get_image_name},
    }, hideLiveContainer ? 5: 1);
}

void* getGuestAppHeader(void) {
    return (void*)orig_dyld_get_image_header(appMainImageIndex);
}
