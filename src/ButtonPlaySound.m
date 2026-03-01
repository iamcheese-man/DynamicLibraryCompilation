#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static AVPlayer *globalPlayer = nil;

@interface TweakLoader : NSObject
@end

@implementation TweakLoader

+ (void)load {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appDidFinishLaunching)
                                                     name:UIApplicationDidFinishLaunchingNotification
                                                   object:nil];
    });
}

+ (void)appDidFinishLaunching {

    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) {
        keyWindow = [UIApplication sharedApplication].windows.firstObject;
    }

    if (!keyWindow) {
        NSLog(@"[Tweak] No window found.");
        return;
    }

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(40, 120, 140, 50);
    button.backgroundColor = [UIColor colorWithRed:0 green:0.5 blue:1 alpha:0.9];
    button.layer.cornerRadius = 12;
    [button setTitle:@"Play Sound" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

    [button addTarget:self
               action:@selector(buttonTapped)
     forControlEvents:UIControlEventTouchUpInside];

    [keyWindow addSubview:button];

    NSLog(@"[Tweak] Button injected successfully.");
}

+ (void)buttonTapped {

    dispatch_async(dispatch_get_main_queue(), ^{

        NSURL *url = [NSURL URLWithString:@"https://www.soundjay.com/buttons/sounds/button-3.mp3"];

        if (!url) {
            NSLog(@"[Tweak] Invalid URL.");
            return;
        }

        NSError *error = nil;

        // Force audio session (fixes silent playback in some apps)
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
        [[AVAudioSession sharedInstance] setActive:YES error:&error];

        if (error) {
            NSLog(@"[Tweak] Audio session error: %@", error);
        }

        globalPlayer = [AVPlayer playerWithURL:url];
        [globalPlayer play];

        NSLog(@"[Tweak] Streaming sound...");
    });
}

@end
