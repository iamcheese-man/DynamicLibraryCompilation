// Bluebutton.m
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

void swizzled_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(original_viewDidAppear:), animated);
    
    UIViewController *vc = (UIViewController *)self;
    
    UIButton *tweakButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [tweakButton setTitle:@"Tweaked! 🎉" forState:UIControlStateNormal];
    tweakButton.backgroundColor = [UIColor systemBlueColor];
    [tweakButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    tweakButton.layer.cornerRadius = 10;
    tweakButton.translatesAutoresizingMaskIntoConstraints = NO;
    [tweakButton addTarget:vc action:@selector(tweakButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    [vc.view addSubview:tweakButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [tweakButton.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [tweakButton.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [tweakButton.widthAnchor constraintEqualToConstant:150],
        [tweakButton.heightAnchor constraintEqualToConstant:44]
    ]];
}

void tweakButtonTapped(id self, SEL _cmd) {
    UIViewController *vc = (UIViewController *)self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Hello!" message:@"ObjC tweak button tapped!" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

__attribute__((constructor))
static void initialize() {
    NSLog(@"[Tweak] Loading...");
    
    class_addMethod([UIViewController class], @selector(tweakButtonTapped), (IMP)tweakButtonTapped, "v@:");
    
    Method originalMethod = class_getInstanceMethod([UIViewController class], @selector(viewDidAppear:));
    
    class_addMethod([UIViewController class], @selector(original_viewDidAppear:), method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    
    class_replaceMethod([UIViewController class], @selector(viewDidAppear:), (IMP)swizzled_viewDidAppear, method_getTypeEncoding(originalMethod));
    
    NSLog(@"[Tweak] Loaded!");
}
