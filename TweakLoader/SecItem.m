//
//  SecItem.m
//  LiveContainer
//
//  Created by s s on 2024/11/29.
//
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "../fishhook/fishhook.h"

NSString* SecItemLabelPrefix = 0;
OSStatus (*orig_SecItemAdd)(CFDictionaryRef attributes, CFTypeRef *result);
OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef query, CFTypeRef *result);
OSStatus (*orig_SecItemUpdate)(CFDictionaryRef query, CFDictionaryRef attributesToUpdate);
OSStatus (*orig_SecItemDelete)(CFDictionaryRef query);

OSStatus new_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    NSMutableDictionary *attributesCopy = ((__bridge NSDictionary *)attributes).mutableCopy;
    attributesCopy[@"alis"] = SecItemLabelPrefix;

    OSStatus status = orig_SecItemAdd((__bridge CFDictionaryRef)attributesCopy, result);
    if(status == errSecSuccess && result && *result) {
        id objcResult = (__bridge id)(*result);
        if(CFGetTypeID(*result) == CFDictionaryGetTypeID()) {
            NSMutableDictionary* finalQueryResult = [objcResult mutableCopy];
            finalQueryResult[@"alis"] = @"";
            *result = (__bridge CFTypeRef)finalQueryResult;
        } else if (CFGetTypeID(*result) == CFArrayGetTypeID()) {
            NSMutableArray* finalQueryResult = [objcResult mutableCopy];
            for(id item in finalQueryResult) {
                if([item isKindOfClass:[NSDictionary class]]) {
                    item[@"alis"] = @"";
                }

            }
            *result = (__bridge CFTypeRef)finalQueryResult;
        }
        return status;
    }
    return status;
}

OSStatus new_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    NSMutableDictionary *queryCopy = ((__bridge NSDictionary *)query).mutableCopy;
    queryCopy[@"alis"] = SecItemLabelPrefix;

    OSStatus status = orig_SecItemCopyMatching((__bridge CFDictionaryRef)queryCopy, result);
    if(status == errSecSuccess && result && *result) {
        id objcResult = (__bridge id)(*result);
        if([objcResult isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary* finalQueryResult = [objcResult mutableCopy];
            finalQueryResult[@"alis"] = @"";
            *result = (__bridge CFTypeRef)finalQueryResult;
        } else if ([objcResult isKindOfClass:[NSArray class]]) {
            NSMutableArray* finalQueryResult = [objcResult mutableCopy];
            for(id item in finalQueryResult) {
                if([item isKindOfClass:[NSDictionary class]]) {
                    item[@"alis"] = @"";
                }

            }
            *result = (__bridge CFTypeRef)finalQueryResult;
        }
        return status;
    }
    
    if(status != errSecParam) {
        return status;
    }
    
    // if this search don't support comment, we just use the original search
    status = orig_SecItemCopyMatching(query, result);
    return status;
}

OSStatus new_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    NSMutableDictionary *queryCopy = ((__bridge NSDictionary *)query).mutableCopy;
    queryCopy[@"alis"] = SecItemLabelPrefix;
    
    NSMutableDictionary *attrCopy = ((__bridge NSDictionary *)attributesToUpdate).mutableCopy;
    attrCopy[@"alis"] = SecItemLabelPrefix;

    OSStatus status = orig_SecItemUpdate((__bridge CFDictionaryRef)queryCopy, (__bridge CFDictionaryRef)attrCopy);
    if(status != errSecParam) {
        return status;
    }
    
    // if this search don't support comment, we just use the original search
    status = orig_SecItemUpdate(query, attributesToUpdate);
    return status;
}

OSStatus new_SecItemDelete(CFDictionaryRef query){
    NSMutableDictionary *queryCopy = ((__bridge NSDictionary *)query).mutableCopy;
    queryCopy[@"alis"] = SecItemLabelPrefix;

    OSStatus status = orig_SecItemDelete((__bridge CFDictionaryRef)queryCopy);
    if(status != errSecParam) {
        return status;
    }
    
    // if this search don't support comment, we just use the original search
    status = orig_SecItemDelete(query);
    return status;
}

__attribute__((constructor))
static void SecItemGuestHooksInit()  {
    SecItemLabelPrefix = [NSString stringWithUTF8String:getenv("HOME")].lastPathComponent;
    rebind_symbols((struct rebinding[1]){{"SecItemAdd", (void *)new_SecItemAdd, (void **)&orig_SecItemAdd}},1);
    rebind_symbols((struct rebinding[1]){{"SecItemCopyMatching", (void *)new_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching}},1);
    rebind_symbols((struct rebinding[1]){{"SecItemUpdate", (void *)new_SecItemUpdate, (void **)&orig_SecItemUpdate}},1);
    rebind_symbols((struct rebinding[1]){{"SecItemDelete", (void *)new_SecItemDelete, (void **)&orig_SecItemDelete}},1);
}
