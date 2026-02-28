// Tweak.m
// Simple Objective-C Tweak - Adds a button to every view controller

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Swizzled method
void swizzled_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    // Call original implementation
    ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(original_viewDidAppear:), animated);
    
    UIViewController *vc = (UIViewController *)self;
    
    // Create button
    UIButton *tweakButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [tweakButton setTitle:@"Tweaked! 🎉" forState:UIControlStateNormal];
    tweakButton.backgroundColor = [UIColor systemBlueColor];
    [tweakButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    tweakButton.layer.cornerRadius = 10;
    tweakButton.translatesAutoresizingMaskIntoConstraints = NO;
    [tweakButton addTarget:vc 
                    action:@selector(tweakButtonTapped) 
          forControlEvents:UIControlEventTouchUpInside];
    
    [vc.view addSubview:tweakButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [tweakButton.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [tweakButton.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [tweakButton.widthAnchor constraintEqualToConstant:150],
        [tweakButton.heightAnchor constraintEqualToConstant:44]
    ]];
}

// Button tap handler
void tweakButtonTapped(id self, SEL _cmd) {
    UIViewController *vc = (UIViewController *)self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Hello!" 
                                                                   message:@"ObjC tweak button tapped!" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

// Constructor - runs when dylib loads
__attribute__((constructor))
static void initialize() {
    NSLog(@"[Tweak] Loading...");
    
    // Add button tap method to UIViewController
    class_addMethod([UIViewController class], 
                   @selector(tweakButtonTapped), 
                   (IMP)tweakButtonTapped, 
                   "v@:");
    
    // Swizzle viewDidAppear
    Method originalMethod = class_getInstanceMethod([UIViewController class], 
                                                    @selector(viewDidAppear:));
    Method swizzledMethod = class_getInstanceMethod([UIViewController class], 
                                                    @selector(original_viewDidAppear:));
    
    // Add original_viewDidAppear as an alias
    class_addMethod([UIViewController class],
                   @selector(original_viewDidAppear:),
                   method_getImplementation(originalMethod),
                   method_getTypeEncoding(originalMethod));
    
    // Replace viewDidAppear with our swizzled version
    class_replaceMethod([UIViewController class],
                       @selector(viewDidAppear:),
                       (IMP)swizzled_viewDidAppear,
                       method_getTypeEncoding(originalMethod));
    
    NSLog(@"[Tweak] Loaded!");
}
