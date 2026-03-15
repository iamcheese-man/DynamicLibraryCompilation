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

__attribute__((constructor))
static void init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{

        // Dump ALL generic password keychain items
        NSDictionary *query = @{
            (__bridge id)kSecClass:        (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecReturnAttributes: @YES,
            (__bridge id)kSecReturnData:   @YES,
            (__bridge id)kSecMatchLimit:   (__bridge id)kSecMatchLimitAll,
        };

        CFTypeRef result = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

        if (status == errSecSuccess && result) {
            NSArray *items = (__bridge_transfer NSArray *)result;
            NSMutableString *output = [NSMutableString string];
            for (NSDictionary *item in items) {
                NSString *service = item[(__bridge id)kSecAttrService] ?: @"(nil)";
                NSString *account = item[(__bridge id)kSecAttrAccount] ?: @"(nil)";
                NSData *data = item[(__bridge id)kSecValueData];
                NSString *value = @"(nil)";
                if (data) {
                    value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (!value) value = [data base64EncodedStringWithOptions:0];
                }
                [output appendFormat:@"svc=%@ acct=%@\nval=%@\n\n", service, account, value];
            }
            showAlert(@"All Keychain Items", output.length ? output : @"(empty)");
        } else {
            showAlert(@"Keychain Dump", [NSString stringWithFormat:@"status=%d (no items or error)", (int)status]);
        }
    });
}
