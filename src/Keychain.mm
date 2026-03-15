#import <UIKit/UIKit.h>
#import <Security/Security.h>

static void showKeychainDump(NSString *label) {
    NSDictionary *query = @{
        (__bridge id)kSecClass:                (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecReturnAttributes:     @YES,
        (__bridge id)kSecReturnData:           @YES,
        (__bridge id)kSecMatchLimit:           (__bridge id)kSecMatchLimitAll,
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

    NSMutableString *output = [NSMutableString string];
    if (status == errSecSuccess && result) {
        NSArray *items = (__bridge_transfer NSArray *)result;
        for (NSDictionary *item in items) {
            NSString *service = item[(__bridge id)kSecAttrService] ?: @"(nil)";
            NSString *account = item[(__bridge id)kSecAttrAccount] ?: @"(nil)";
            NSData *data = item[(__bridge id)kSecValueData];
            NSString *value = @"(nil)";
            if (data) {
                value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (!value) value = [data base64EncodedStringWithOptions:0];
            }
            [output appendFormat:@"svc=%@\nacct=%@\nval=%@\n---\n", service, account, value];
        }
    } else {
        [output appendFormat:@"status=%d", (int)status];
    }

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
            alertControllerWithTitle:label
            message:output
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [UIPasteboard generalPasteboard].string = output;
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [window.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

static UIButton *gDumpButton = nil;

__attribute__((constructor))
static void init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                window = ((UIWindowScene *)scene).windows.firstObject;
                break;
            }
        }
        if (!window) return;

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(10, 60, 140, 40);
        btn.backgroundColor = [UIColor colorWithRed:1 green:0.2 blue:0.2 alpha:0.9];
        [btn setTitle:@"Dump Keychain" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.layer.cornerRadius = 8;
        btn.layer.zPosition = 9999;

        static int dumpCount = 0;
        [btn addTarget:[NSBlockOperation blockOperationWithBlock:^{
            dumpCount++;
            showKeychainDump([NSString stringWithFormat:@"Dump #%d", dumpCount]);
        }] action:@selector(main) forControlEvents:UIControlEventTouchUpInside];

        [window addSubview:btn];
        gDumpButton = btn;
    });
}
