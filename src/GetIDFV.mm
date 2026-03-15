#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

__attribute__((constructor))
static void showIDFV(void) {
dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
dispatch_get_main_queue(), ^{

    NSString *idfv = [[[UIDevice currentDevice] identifierForVendor] UUIDString];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"IDFV"
        message:idfv
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Copy"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            [UIPasteboard generalPasteboard].string = idfv;
        }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
        style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *root = [UIApplication sharedApplication]
        .windows.firstObject.rootViewController;
    [root presentViewController:alert animated:YES completion:nil];
});
}
