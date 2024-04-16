// https://github.com/evelyneee/ellekit/blob/main/ellekitc/JITLess.c
// This file is licensed under the BSD-3 Clause License
// Copyright 2022 © Charlotte Belanger

#include <stdio.h>

#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif

#include <mach/mach.h>
#include <mach/task.h>
#include <mach/thread_act.h>
#include <mach/thread_state.h>
#include <mach/thread_status.h>
#include <pthread/pthread.h>
#include <stdlib.h>

#include "fishhook/fishhook.h"
#include "mach_excServer.h"

#import <Foundation/Foundation.h>

extern kern_return_t
mach_vm_allocate(mach_port_name_t target, mach_vm_address_t *address, mach_vm_size_t size, int flags);

extern kern_return_t
mach_vm_deallocate(vm_map_t target, mach_vm_address_t address, mach_vm_size_t size);

extern kern_return_t
mach_vm_protect(mach_port_name_t task, mach_vm_address_t address, mach_vm_size_t size, boolean_t set_maximum, vm_prot_t new_protection);

extern kern_return_t
custom_mach_vm_protect(mach_port_name_t task, mach_vm_address_t address, mach_vm_size_t size, boolean_t set_maximum, vm_prot_t new_protection);

extern kern_return_t
mach_vm_write(vm_map_t target_task, mach_vm_address_t address, vm_offset_t data, mach_msg_type_number_t dataCnt);

extern kern_return_t
mach_vm_remap(vm_map_t target_task, mach_vm_address_t *target_address, mach_vm_size_t size, mach_vm_offset_t mask, int flags, vm_map_t src_task, mach_vm_address_t src_address, boolean_t copy, vm_prot_t *cur_protection, vm_prot_t *max_protection, vm_inherit_t inheritance);

extern boolean_t mach_exc_server(mach_msg_header_t *InHeadP, mach_msg_header_t *OutHeadP);

kern_return_t (*orig_task_set_exception_ports)(task_t task, exception_mask_t exception_mask, mach_port_t new_port, exception_behavior_t behavior, thread_state_flavor_t new_flavor);

int hookCount = 0;

void* hook1;
void* hook1rep;

__attribute__((naked))
extern void orig1(void) {
#if __arm64__
    __asm__ volatile(
                     ".extern _hook1\n"
                     "adrp x16, _hook1@PAGE\n"
                     "ldr x16, [x16, _hook1@PAGEOFF]\n"
                     "add x16, x16, #4\n"
                     "pacibsp\n"
                     "br x16\n"
                     );
#endif
}

void* hook2;
void* hook2rep;

__attribute__((naked))
static void orig2(void) {
#if __arm64__
    __asm__ volatile(
                     ".extern _hook2\n"
                     "adrp x16, _hook2@PAGE\n"
                     "ldr x16, [x16, _hook2@PAGEOFF]\n"
                     "add x16, x16, #4\n"
                     "pacibsp\n"
                     "br x16\n"
                     );
#endif
}

void* hook3;
void* hook3rep;

__attribute__((naked))
static void orig3(void) {
#if __arm64__
    __asm__ volatile(
                     ".extern _hook3\n"
                     "adrp x16, _hook3@PAGE\n"
                     "ldr x16, [x16, _hook3@PAGEOFF]\n"
                     "add x16, x16, #4\n"
                     "pacibsp\n"
                     "br x16\n"
                     );
#endif
}

void* hook4;
void* hook4rep;

__attribute__((naked))
static void orig4(void) {
#if __arm64__
    __asm__ volatile(
                     ".extern _hook4\n"
                     "adrp x16, _hook4@PAGE\n"
                     "ldr x16, [x16, _hook4@PAGEOFF]\n"
                     "add x16, x16, #4\n"
                     "pacibsp\n"
                     "br x16\n"
                     );
#endif
}

void* hook5;
void* hook5rep;

__attribute__((naked))
static void orig5(void) {
#if __arm64__
    __asm__ volatile(
                     ".extern _hook5\n"
                     "adrp x16, _hook5@PAGE\n"
                     "ldr x16, [x16, _hook5@PAGEOFF]\n"
                     "add x16, x16, #4\n"
                     "pacibsp\n"
                     "br x16\n"
                     );
#endif
}

void* hook6;
void* hook6rep;

__attribute__((naked))
static void orig6(void) {
#if __arm64__
    __asm__ volatile(
                     ".extern _hook6\n"
                     "adrp x16, _hook6@PAGE\n"
                     "ldr x16, [x16, _hook6@PAGEOFF]\n"
                     "add x16, x16, #4\n"
                     "pacibsp\n"
                     "br x16\n"
                     );
#endif
}

struct arm_debug_state64
{
    __uint64_t        bvr[16];
    __uint64_t        bcr[16];
    __uint64_t        wvr[16];
    __uint64_t        wcr[16];
    __uint64_t      mdscr_el1; /* Bit 0 is SS (Hardware Single Step) */
};

struct hook
{
    __uint64_t target;
    __uint64_t replacement;
};

#define ARM_DEBUG_STATE64 15
#define ARM_DEBUG_STATE64_COUNT_ ((mach_msg_type_number_t) \
   (sizeof (struct arm_debug_state64)/sizeof(uint32_t)))

struct arm_debug_state64 globalDebugState = {};
struct hook hooks[16];
mach_port_t server;

kern_return_t catch_mach_exception_raise(mach_port_t exception_port, mach_port_t thread, mach_port_t task, exception_type_t exception, mach_exception_data_t code, mach_msg_type_number_t codeCnt) {
    abort();
}

kern_return_t catch_mach_exception_raise_state_identity(mach_port_t exception_port, mach_port_t thread, mach_port_t task, exception_type_t exception, mach_exception_data_t code, mach_msg_type_number_t codeCnt, int *flavor, thread_state_t old_state, mach_msg_type_number_t old_stateCnt, thread_state_t new_state, mach_msg_type_number_t *new_stateCnt) {
    abort();
}

kern_return_t catch_mach_exception_raise_state( mach_port_t exception_port, exception_type_t exception, const mach_exception_data_t code, mach_msg_type_number_t codeCnt, int *flavor, const thread_state_t old_state, mach_msg_type_number_t old_stateCnt, thread_state_t new_state, mach_msg_type_number_t *new_stateCnt) {
    arm_thread_state64_t *old = (arm_thread_state64_t *)old_state;
    arm_thread_state64_t *new = (arm_thread_state64_t *)new_state;
    for (int i = 0; i < hookCount; ++i) {
        if (hooks[i].target == arm_thread_state64_get_pc(*old)) {
            *new = *old;
            *new_stateCnt = old_stateCnt;
            arm_thread_state64_set_pc_fptr(*new, hooks[i].replacement);
            return KERN_SUCCESS;
        }
    }

    return KERN_FAILURE;
}

void *exception_handler(void *unused) {
    mach_msg_server(mach_exc_server, sizeof(union __RequestUnion__catch_mach_exc_subsystem), server, MACH_MSG_OPTION_NONE);
    abort();
}

kern_return_t hooked_task_set_exception_ports(task_t task, exception_mask_t exception_mask, mach_port_t new_port, exception_behavior_t behavior, thread_state_flavor_t new_flavor) {
    if (exception_mask == EXC_MASK_BREAKPOINT) {
        return KERN_SUCCESS;
    }
    exception_mask &= ~EXC_MASK_BREAKPOINT;
    return orig_task_set_exception_ports(task, exception_mask, new_port, behavior, new_flavor);
}

void EKAddHookToRegistry(void* target, void* replacement) {
    hooks[hookCount] = (struct hook){
        .target = (__uint64_t)target,
        .replacement = (__uint64_t)replacement
    };
}

void EKLaunchExceptionHandler() {
    if (hookCount > 0) return;
    mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &server);
    mach_port_insert_right(mach_task_self(), server, server, MACH_MSG_TYPE_MAKE_SEND);
    task_set_exception_ports(mach_task_self(), EXC_MASK_BREAKPOINT, server, EXCEPTION_STATE | MACH_EXCEPTION_CODES, ARM_THREAD_STATE64);
    pthread_t thread;
    pthread_create(&thread, NULL, exception_handler, NULL);

    // Don't let guest app interfere with this hardware breakpoint exception handler
    // FIXME: does it interfere with emulators' handler?
    struct rebinding rebindings[] = (struct rebinding[]){
        {"task_set_exception_ports", hooked_task_set_exception_ports, (void *)&orig_task_set_exception_ports}
    };
    rebind_symbols(rebindings, sizeof(rebindings)/sizeof(struct rebinding));
}

void EKJITLessHook(void* _target, void* _replacement, void** orig) {
    
    EKLaunchExceptionHandler();
    
    void* target = (void*)((uint64_t)_target & 0x0000007fffffffff);
    void* replacement = (void*)((uint64_t)_replacement & 0x0000007fffffffff);
    
    EKAddHookToRegistry(target, replacement);
            
    uint32_t firstISN = *(uint32_t*)target;
    
    printf("pacibsp? : %02X\n", firstISN);
    
    if (hookCount == 6) {
        return;
    }
    
    switch (hookCount) {
        case 0:
            hook1 = target;
            hook1rep = replacement;
            
            globalDebugState.bvr[0] = (uint64_t)target;
            globalDebugState.bcr[0] = 0x1e5;
            
            if (orig) {
                *orig = &orig1;
            }
            
            printf("[+] ellekit: hook #1 set\n");
            
            break;
        case 1:
            hook2 = target;
            hook2rep = replacement;
            
            globalDebugState.bvr[1] = (uint64_t)target;
            globalDebugState.bcr[1] = 0x1e5;
            
            if (orig) {
                *orig = &orig2;
            }
            
            printf("[+] ellekit: hook #2 set\n");
            break;
        case 2:
            hook3 = target;
            hook3rep = replacement;
            
            globalDebugState.bvr[2] = (uint64_t)target;
            globalDebugState.bcr[2] = 0x1e5;
            
            if (orig) {
                *orig = &orig3;
            }
            
            printf("[+] ellekit: hook #3 set\n");
            break;
        case 3:
            hook4 = target;
            hook4rep = replacement;
            
            globalDebugState.bvr[3] = (uint64_t)target;
            globalDebugState.bcr[3] = 0x1e5;
            
            if (orig) {
                *orig = &orig4;
            }
            
            printf("[+] ellekit: hook #4 set\n");
            break;
        case 4:
            hook5 = target;
            hook5rep = replacement;
            
            globalDebugState.bvr[4] = (uint64_t)target;
            globalDebugState.bcr[4] = 0x1e5;
            
            if (orig) {
                *orig = &orig5;
            }
            
            printf("[+] ellekit: hook #5 set\n");
            break;
        case 5:
            hook6 = target;
            hook6rep = replacement;
            
            globalDebugState.bvr[5] = (uint64_t)target;
            globalDebugState.bcr[5] = 0x1e5;
            
            if (orig) {
                *orig = &orig6;
            }
            
            printf("[+] ellekit: hook #6 set\n");
            break;
    }
    
    hookCount++;
    
    kern_return_t task_setstate_ret = task_set_state(mach_task_self(), ARM_DEBUG_STATE64, (thread_state_t)&globalDebugState, ARM_DEBUG_STATE64_COUNT_);
    
    if (task_setstate_ret != KERN_SUCCESS) {
        printf("[-] ellekit: JIT hook did not work, task_set_state failed with err: %s\n", mach_error_string(task_setstate_ret));
        return;
    }
    
    thread_act_array_t act_list;
    mach_msg_type_number_t listCnt;
    
    kern_return_t task_threads_ret = task_threads(mach_task_self(), &act_list, &listCnt);
    
    if (task_threads_ret != KERN_SUCCESS) {
        printf("[-] ellekit: JIT hook did not work, task_threads failed with err: %s\n", mach_error_string(task_threads_ret));
        return;
    }
    
    for (int i = 0; i < listCnt; i++) {
        thread_t thread = act_list[i];
        
        thread_set_state(thread, ARM_DEBUG_STATE64, (thread_state_t)&globalDebugState, ARM_DEBUG_STATE64_COUNT_);
        
        mach_port_deallocate(mach_task_self_, thread);
    }
    
    mach_vm_deallocate(mach_task_self_, (mach_vm_address_t)act_list, listCnt * sizeof(thread_t));
}
