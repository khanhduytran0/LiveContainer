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
    NSString *label = attributesCopy[(__bridge id)kSecAttrLabel];
    NSString* newLabel;
    if(label) {
        newLabel = [NSString stringWithFormat:@"%@.%@", SecItemLabelPrefix, label];
    } else {
        newLabel = SecItemLabelPrefix;
    }
    attributesCopy[(__bridge id)kSecAttrLabel] = newLabel;

    OSStatus status = orig_SecItemAdd((__bridge CFDictionaryRef)attributesCopy, result);
    
    if(status == errSecSuccess && result) {
        id objcResult = (__bridge id)(*result);
        // recover original label
        if([objcResult isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary* finalQueryResult = [objcResult mutableCopy];
            NSString* origLabel = finalQueryResult[(__bridge id)kSecAttrLabel];
            finalQueryResult[(__bridge id)kSecAttrLabel] = [origLabel substringFromIndex:[SecItemLabelPrefix length]];
            *result = (__bridge CFTypeRef)finalQueryResult;
        } else if ([objcResult isKindOfClass:[NSArray class]]) {
            NSMutableArray* finalQueryResult = [objcResult mutableCopy];
            for(id item in finalQueryResult) {
                if([item isKindOfClass:[NSDictionary class]]) {
                    NSString* origLabel = item[(__bridge id)kSecAttrLabel];
                    item[(__bridge id)kSecAttrLabel] = [origLabel substringFromIndex:[SecItemLabelPrefix length]];
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
    NSString *label = queryCopy[(__bridge id)kSecAttrLabel];
    NSString* newLabel;
    if(label) {
        newLabel = [NSString stringWithFormat:@"%@.%@", SecItemLabelPrefix, label];
    } else {
        newLabel = SecItemLabelPrefix;
    }
    queryCopy[(__bridge id)kSecAttrLabel] = newLabel;

    OSStatus status = orig_SecItemCopyMatching((__bridge CFDictionaryRef)queryCopy, result);
    if(status == errSecSuccess && result) {
        id objcResult = (__bridge id)(*result);
        // recover original label
        if([objcResult isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary* finalQueryResult = [objcResult mutableCopy];
            NSString* origLabel = finalQueryResult[(__bridge id)kSecAttrLabel];
            finalQueryResult[(__bridge id)kSecAttrLabel] = [origLabel substringFromIndex:[SecItemLabelPrefix length]];
            *result = (__bridge CFTypeRef)finalQueryResult;
        } else if ([objcResult isKindOfClass:[NSArray class]]) {
            NSMutableArray* finalQueryResult = [objcResult mutableCopy];
            for(id item in finalQueryResult) {
                if([item isKindOfClass:[NSDictionary class]]) {
                    NSString* origLabel = item[(__bridge id)kSecAttrLabel];
                    item[(__bridge id)kSecAttrLabel] = [origLabel substringFromIndex:[SecItemLabelPrefix length]];
                }

            }
            *result = (__bridge CFTypeRef)finalQueryResult;
        }
        return status;
    }
    
    if(status != errSecItemNotFound) {
        // return other error
        return status;
    }
    
    // try to find result in original keychain
    status = orig_SecItemCopyMatching(query, result);
    return status;
}

OSStatus new_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    NSMutableDictionary *queryCopy = ((__bridge NSDictionary *)query).mutableCopy;
    NSString *queryLabel = queryCopy[(__bridge id)kSecAttrLabel];
    NSString* newQueryLabel;
    if(queryLabel) {
        newQueryLabel = [NSString stringWithFormat:@"%@.%@", SecItemLabelPrefix, queryLabel];
    } else {
        newQueryLabel = SecItemLabelPrefix;
    }
    queryCopy[(__bridge id)kSecAttrLabel] = newQueryLabel;
    
    NSMutableDictionary *attrCopy = ((__bridge NSDictionary *)attributesToUpdate).mutableCopy;
    NSString *attrLabel = attrCopy[(__bridge id)kSecAttrLabel];
    NSString* newAttrLabel;
    if(attrLabel) {
        newAttrLabel = [NSString stringWithFormat:@"%@.%@", SecItemLabelPrefix, queryLabel];
    } else {
        newAttrLabel = SecItemLabelPrefix;
    }
    queryCopy[(__bridge id)kSecAttrLabel] = newAttrLabel;

    return orig_SecItemUpdate((__bridge CFDictionaryRef)queryCopy, (__bridge CFDictionaryRef)attrCopy);
}

OSStatus new_SecItemDelete(CFDictionaryRef query){
    NSMutableDictionary *queryCopy = ((__bridge NSDictionary *)query).mutableCopy;
    NSString *queryLabel = queryCopy[(__bridge id)kSecAttrLabel];
    NSString* newQueryLabel;
    if(queryLabel) {
        newQueryLabel = [NSString stringWithFormat:@"%@.%@", SecItemLabelPrefix, queryLabel];
    } else {
        newQueryLabel = SecItemLabelPrefix;
    }
    queryCopy[(__bridge id)kSecAttrLabel] = newQueryLabel;

    return orig_SecItemDelete((__bridge CFDictionaryRef)queryCopy);
}

__attribute__((constructor))
static void SecItemGuestHooksInit()  {
    SecItemLabelPrefix = [NSString stringWithUTF8String:getenv("HOME")].lastPathComponent;
    rebind_symbols((struct rebinding[1]){{"SecItemAdd", (void *)new_SecItemAdd, (void **)&orig_SecItemAdd}},1);
    rebind_symbols((struct rebinding[1]){{"SecItemCopyMatching", (void *)new_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching}},1);
    rebind_symbols((struct rebinding[1]){{"SecItemUpdate", (void *)new_SecItemUpdate, (void **)&orig_SecItemUpdate}},1);
    rebind_symbols((struct rebinding[1]){{"SecItemDelete", (void *)new_SecItemDelete, (void **)&orig_SecItemDelete}},1);
}
