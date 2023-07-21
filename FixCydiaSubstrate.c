#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include "fishhook/fishhook.h"

// Provide _dyld_get_all_image_infos for CydiaSubstrate
struct dyld_all_image_infos *_alt_dyld_get_all_image_infos() {
    static struct dyld_all_image_infos *result;
    if (result) {
        return result;
    }
    struct task_dyld_info dyld_info;
    mach_vm_address_t image_infos;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t ret;
    ret = task_info(mach_task_self_,
                    TASK_DYLD_INFO,
                    (task_info_t)&dyld_info,
                    &count);
    if (ret != KERN_SUCCESS) {
        return NULL;
    }
    image_infos = dyld_info.all_image_info_addr;
    result = (struct dyld_all_image_infos *)image_infos;
    return result;
}

void init_fixCydiaSubstrate(void) {
    void *orig__dyld_get_all_image_infos;
    struct rebinding rebindings[] = (struct rebinding[]){
        {"_dyld_get_all_image_infos", _alt_dyld_get_all_image_infos, (void *)&orig__dyld_get_all_image_infos}
    };
    rebind_symbols(rebindings, sizeof(rebindings)/sizeof(struct rebinding));
}
