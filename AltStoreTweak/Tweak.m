@import Foundation;
@import Security;

void LCCopyKeychainItems(NSString *oldService, NSString *newService) {
    // Query to find all keychain items with the old service
    NSDictionary *query = @{
        (__bridge id)kSecAttrService: oldService,
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecAttrSynchronizable: (__bridge id)kSecAttrSynchronizableAny,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
        (__bridge id)kSecReturnAttributes: @YES
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, &result);

    if (status == errSecSuccess) {
        NSArray *items = (__bridge NSArray *)result;

        for (NSDictionary *item in items) {
            // Retrieve attributes and data of the keychain item
            NSString *account = item[(id)kSecAttrAccount];
            NSData *passwordData = item[(id)kSecValueData];
            
            NSDictionary *deleteQuery = @{
                (__bridge id)kSecAttrService: newService,
                (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                (__bridge id)kSecAttrSynchronizable: (__bridge id)kSecAttrSynchronizableAny,
                (__bridge id)kSecAttrAccount: account
            };

            OSStatus deleteStatus = SecItemDelete((CFDictionaryRef)deleteQuery);
            if (deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound) {
                NSLog(@"[LC] Delete failed %d", (int)deleteStatus);
                continue;
            }

            // Create a new keychain entry with the new service name
            NSDictionary *newItem = @{
                (__bridge id)kSecAttrService: newService,
                (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                (__bridge id)kSecAttrSynchronizable: (__bridge id)kSecAttrSynchronizableAny,
                (__bridge id)kSecAttrAccount: account,
                (__bridge id)kSecValueData: passwordData
            };
            OSStatus addStatus = SecItemAdd((CFDictionaryRef)newItem, NULL);
            if (addStatus != errSecSuccess) {
                NSLog(@"[LC] Add item failed %d", (int)deleteStatus);
            }
        }
    } else {
        NSLog(@"[LC] Error retrieving keychain items: %d", (int)status);
    }
}

BOOL synced = NO;
__attribute__((constructor))
static void LCAltstoreHookInit(void) {
    if (!synced) {
        LCCopyKeychainItems(@"com.rileytestut.AltStore", [NSBundle.mainBundle bundleIdentifier]);
        synced = YES;
    }
}
