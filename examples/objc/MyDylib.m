// Example Objective-C Dylib Implementation
// MyDylib.m

#import "MyDylib.h"

@implementation MyDylib

+ (instancetype)sharedInstance {
    static MyDylib *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)sayHello {
    NSLog(@"Hello from Objective-C dylib!");
}

- (void)showAlert {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
        UIViewController *rootVC = keyWindow.rootViewController;
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Dylib"
                                                                       message:@"Hello from ObjC dylib!"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                          style:UIAlertActionStyleDefault
                                                        handler:nil];
        [alert addAction:okAction];
        
        [rootVC presentViewController:alert animated:YES completion:nil];
    });
}

@end

// Constructor - called when dylib loads
__attribute__((constructor))
void dylibLoaded(void) {
    NSLog(@"Dylib has been loaded!");
    [[MyDylib sharedInstance] sayHello];
}
