@import Foundation;
@import Security;
#include <substrate.h>

void LCMoveKeychainItems(NSString *oldService, NSString *newService) {
    // Query to find all keychain items with the old service
    NSDictionary *query = @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: oldService,
        (id)kSecReturnAttributes: @YES,
        (id)kSecReturnData: @YES
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, &result);

    if (status == errSecSuccess) {
        NSArray *items = (__bridge_transfer NSArray *)result;

        for (NSDictionary *item in items) {
            // Retrieve attributes and data of the keychain item
            NSString *account = item[(id)kSecAttrAccount];
            NSData *passwordData = item[(id)kSecValueData];

            // Create a new keychain entry with the new service name
            NSDictionary *newItem = @{
                (id)kSecClass: (id)kSecClassGenericPassword,
                (id)kSecAttrService: newService,
                (id)kSecAttrAccount: account,
                (id)kSecValueData: passwordData
            };

            // Add the new item to the keychain
            OSStatus addStatus = SecItemAdd((CFDictionaryRef)newItem, NULL);
            if (addStatus == errSecSuccess) {
                // Successfully added the new item, now delete the old one
                NSDictionary *deleteQuery = @{
                    (id)kSecClass: (id)kSecClassGenericPassword,
                    (id)kSecAttrService: oldService,
                    (id)kSecAttrAccount: account
                };

                SecItemDelete((CFDictionaryRef)deleteQuery);
            } else if (addStatus == errSecDuplicateItem) {
                NSLog(@"Item already exists in the new service.");
            } else {
                NSLog(@"Error adding item to the new service: %d", (int)addStatus);
            }
        }
    } else {
        NSLog(@"Error retrieving keychain items: %d", (int)status);
    }
}

id (*keychainInitWithServiceName)(id, id) = NULL;
id (*keychainInitWithWithNothing)(id) = NULL;

id hook_keychainInitWithServiceName(id arg1, id self) {
	NSLog(@"Hook succeeded!");
   return keychainInitWithWithNothing(self);
}

__attribute__((constructor))
static void LCAltstoreHookInit() {
	LCMoveKeychainItems(@"com.rileytestut.AltStore", [NSBundle.mainBundle bundleIdentifier]);
	keychainInitWithWithNothing = MSFindSymbol(NULL, "_$s14KeychainAccess0A0CACycfC");
    MSHookFunction(MSFindSymbol(NULL, "_$s14KeychainAccess0A0C7serviceACSS_tcfC"),
                   (void*)hook_keychainInitWithServiceName,
                   (void**)&keychainInitWithServiceName);
}
