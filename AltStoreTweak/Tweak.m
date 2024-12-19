@import Foundation;
@import Security;

NSData* getKeyChainItemFromService(NSString* key, NSString* service) {
    NSDictionary *query = @{
        (__bridge id)kSecAttrService: service,
        (__bridge id)kSecAttrAccount: key,
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecAttrSynchronizable: (__bridge id)kSecAttrSynchronizableAny,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, &result);

    if (status == errSecSuccess) {
        NSData *data = (__bridge NSData *)result;
        return data;

    } else {
        NSLog(@"[LC] Error retrieving keychain items: %d", (int)status);
        return nil;
    }
}

BOOL synced = NO;
__attribute__((constructor))
static void LCAltstoreHookInit(void) {
    if (synced) {
        return;
    }
    NSLog(@"[LC] LiveContainer AltStore Tweak build %s", CONFIG_COMMIT);
    NSString* bundleId = [NSBundle.mainBundle bundleIdentifier];
    NSString* serviceName;
    NSArray<NSString*>* appGroups = [NSBundle.mainBundle.infoDictionary objectForKey:@"ALTAppGroups"];
    if(appGroups == nil || [appGroups count] == 0) {
        NSLog(@"[LC] Invalid install method! Failed to find App Group ID.");
        return;
    }
    
    NSString* appGroupId = appGroups.firstObject;
    if([bundleId containsString:@"SideStore"]) {
        serviceName = @"com.SideStore.SideStore";
    } else if ([bundleId containsString:@"AltStore"]) {
        serviceName = @"com.rileytestut.AltStore";
    } else {
        NSLog(@"[LC] Failed to figure out which store this is!");
        return;
    }
    NSData *certData = getKeyChainItemFromService(@"signingCertificate", serviceName);
    if(certData == nil) {
        NSLog(@"[LC] Failed to retrive certificate data!");
        return;
    }
    NSData *certPassword = getKeyChainItemFromService(@"signingCertificatePassword", serviceName);
    if(certPassword == nil) {
        NSLog(@"[LC] Failed to retrive certificate password!");
        return;
    }
    NSUserDefaults* appGroupUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:appGroupId];
    [appGroupUserDefaults setObject:certData forKey:@"LCCertificateData"];
    [appGroupUserDefaults setObject:[NSString stringWithUTF8String:certPassword.bytes] forKey:@"LCCertificatePassword"];
    [appGroupUserDefaults setObject:NSDate.now forKey:@"LCCertificateUpdateDate"];
    NSLog(@"[LC] Successfully updated JIT-Less certificate!");
    synced = YES;
}
