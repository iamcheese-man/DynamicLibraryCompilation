#import <UIKit/UIKit.h>
#import <Security/Security.h>

static void showAlert(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                window = ((UIWindowScene *)scene).windows.firstObject;
                break;
            }
        }
        if (!window) return;

        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:title
            message:message
            preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [UIPasteboard generalPasteboard].string = message;
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];

        [window.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

static void dumpKeychainEntry(NSString *service, NSString *account) {
    NSDictionary *query = @{
        (__bridge id)kSecClass:            (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:      service,
        (__bridge id)kSecAttrAccount:      account,
        (__bridge id)kSecReturnData:       @YES,
        (__bridge id)kSecMatchLimit:       (__bridge id)kSecMatchLimitOne,
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

    if (status == errSecSuccess && result) {
        NSData *data = (__bridge_transfer NSData *)result;
        NSString *value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!value) {
            value = [data base64EncodedStringWithOptions:0];
        }
        showAlert([NSString stringWithFormat:@"Keychain: %@/%@", service, account], value);
    } else {
        showAlert(@"Keychain Miss", [NSString stringWithFormat:@"service=%@ account=%@ status=%d", service, account, (int)status]);
    }
}

__attribute__((constructor))
static void init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        dumpKeychainEntry(@"com.gloop.deltamobile", @"deviceUUID");
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        dumpKeychainEntry(@"com.gloop.deltamobile", @".deviceUUID");
    });
}
