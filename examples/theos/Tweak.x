// Example Theos Tweak
// Tweak.x

#import <UIKit/UIKit.h>

%hook UIViewController

- (void)viewDidLoad {
    %orig;
    NSLog(@"[MyTweak] View controller loaded: %@", NSStringFromClass([self class]));
}

%end

%hook UILabel

- (void)setText:(NSString *)text {
    // Modify all UILabel text to add a prefix
    NSString *modifiedText = [NSString stringWithFormat:@"[Tweaked] %@", text];
    %orig(modifiedText);
}

%end

%ctor {
    NSLog(@"[MyTweak] Tweak initialized!");
    
    // Show alert when tweak loads
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
        UIViewController *rootVC = keyWindow.rootViewController;
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Tweak Loaded"
                                                                       message:@"MyTweak is now active!"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [rootVC presentViewController:alert animated:YES completion:nil];
    });
}
