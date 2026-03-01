// SoundPlayer.m

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface SoundPlayer : NSObject <AVAudioPlayerDelegate>
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
- (void)playSoundFromURL:(NSString *)urlString;
@end

@implementation SoundPlayer

- (void)playSoundFromURL:(NSString *)urlString {

    NSURL *url = [NSURL URLWithString:urlString];
    NSLog(@"[SoundPlayer] Downloading: %@", urlString);

    NSURLSessionDataTask *task =
    [[NSURLSession sharedSession] dataTaskWithURL:url
                                completionHandler:^(NSData *data,
                                                    NSURLResponse *response,
                                                    NSError *error) {

        if (error || !data) {
            NSLog(@"[SoundPlayer] Download error: %@", error);
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{

            NSError *playerError = nil;

            // Ensure audio session works
            AVAudioSession *session = [AVAudioSession sharedInstance];
            [session setCategory:AVAudioSessionCategoryPlayback error:nil];
            [session setActive:YES error:nil];

            self.audioPlayer =
            [[AVAudioPlayer alloc] initWithData:data error:&playerError];

            if (playerError) {
                NSLog(@"[SoundPlayer] Player error: %@", playerError);
                return;
            }

            self.audioPlayer.delegate = self;
            [self.audioPlayer prepareToPlay];

            BOOL success = [self.audioPlayer play];

            NSLog(@"[SoundPlayer] Play result: %d", success);
        });
    }];

    [task resume];
}

- (void)playButtonTapped {
    NSLog(@"[SoundPlayer] Button tapped!");
    [self playSoundFromURL:
     @"https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"];
}

@end


// ===============================
// Global State
// ===============================

static SoundPlayer *globalPlayer = nil;
static void (*original_viewDidAppear)(id, SEL, BOOL) = NULL;


// ===============================
// Swizzled Method
// ===============================

void swizzled_viewDidAppear(id self, SEL _cmd, BOOL animated) {

    // Call original first
    if (original_viewDidAppear) {
        original_viewDidAppear(self, _cmd, animated);
    }

    if (!globalPlayer) return;

    UIViewController *vc = (UIViewController *)self;

    // Avoid duplicate button using associated object
    if (objc_getAssociatedObject(vc.view, "soundButtonAdded")) {
        return;
    }

    objc_setAssociatedObject(vc.view,
                             "soundButtonAdded",
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIButton *button =
    [UIButton buttonWithType:UIButtonTypeSystem];

    [button setTitle:@"🔊 Play Sound"
            forState:UIControlStateNormal];

    button.backgroundColor = [UIColor systemPurpleColor];
    [button setTitleColor:[UIColor whiteColor]
                 forState:UIControlStateNormal];

    button.layer.cornerRadius = 10;
    button.translatesAutoresizingMaskIntoConstraints = NO;

    [button addTarget:globalPlayer
               action:@selector(playButtonTapped)
     forControlEvents:UIControlEventTouchUpInside];

    [vc.view addSubview:button];

    [NSLayoutConstraint activateConstraints:@[
        [button.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [button.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:20],
        [button.widthAnchor constraintEqualToConstant:150],
        [button.heightAnchor constraintEqualToConstant:44]
    ]];

    NSLog(@"[SoundPlayer] Button added to %@", vc);
}


// ===============================
// Constructor
// ===============================

__attribute__((constructor))
static void initialize() {

    NSLog(@"[SoundPlayer] Dylib loaded!");

    dispatch_async(dispatch_get_main_queue(), ^{

        globalPlayer = [[SoundPlayer alloc] init];

        Method method =
        class_getInstanceMethod([UIViewController class],
                                @selector(viewDidAppear:));

        original_viewDidAppear =
        (void *)method_getImplementation(method);

        method_setImplementation(method,
                                 (IMP)swizzled_viewDidAppear);

        NSLog(@"[SoundPlayer] Swizzle complete.");
    });
}
