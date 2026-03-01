#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <AVFoundation/AVFoundation.h>

static AVAudioPlayer *audioPlayer;

#pragma mark - Button Action

void tweakButtonTapped(id self, SEL _cmd) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"sound" ofType:@"wav"];
    if (!path) {
        NSLog(@"[Tweak] sound.wav not found in bundle");
        return;
    }

    NSURL *url = [NSURL fileURLWithPath:path];
    NSError *error = nil;

    audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
    if (error) {
        NSLog(@"[Tweak] Audio error: %@", error);
        return;
    }

    [audioPlayer prepareToPlay];
    [audioPlayer play];

    NSLog(@"[Tweak] Sound played!");
}

#pragma mark - Swizzled viewDidAppear

void swizzled_viewDidAppear(id self, SEL _cmd, BOOL animated) {

    // Call original
    ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(original_viewDidAppear:), animated);

    UIViewController *vc = (UIViewController *)self;

    // Prevent duplicate button
    if ([vc.view viewWithTag:9999]) return;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = 9999;
    [button setTitle:@"Play Sound 🔊" forState:UIControlStateNormal];
    button.backgroundColor = [UIColor systemBlueColor];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.layer.cornerRadius = 10;
    button.translatesAutoresizingMaskIntoConstraints = NO;

    [button addTarget:vc action:@selector(tweakButtonTapped) forControlEvents:UIControlEventTouchUpInside];

    [vc.view addSubview:button];

    [NSLayoutConstraint activateConstraints:@[
        [button.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [button.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor constant:-40],
        [button.widthAnchor constraintEqualToConstant:160],
        [button.heightAnchor constraintEqualToConstant:50]
    ]];
}

#pragma mark - Constructor

__attribute__((constructor))
static void initialize() {

    NSLog(@"[Tweak] Sound tweak loading...");

    // Add button action method
    class_addMethod([UIViewController class],
                    @selector(tweakButtonTapped),
                    (IMP)tweakButtonTapped,
                    "v@:");

    // Get original method
    Method originalMethod =
    class_getInstanceMethod([UIViewController class], @selector(viewDidAppear:));

    // Save original implementation
    class_addMethod([UIViewController class],
                    @selector(original_viewDidAppear:),
                    method_getImplementation(originalMethod),
                    method_getTypeEncoding(originalMethod));

    // Replace with our version
    class_replaceMethod([UIViewController class],
                        @selector(viewDidAppear:),
                        (IMP)swizzled_viewDidAppear,
                        method_getTypeEncoding(originalMethod));

    NSLog(@"[Tweak] Sound tweak loaded!");
}
