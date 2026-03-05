// SoundPlayerFromFile.m
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface SoundPlayerFromFile : NSObject <AVAudioPlayerDelegate>
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
- (void)playSoundFromFile;
@end

@implementation SoundPlayerFromFile

// Replace the playSoundFromFile method with this version that shows alerts:

- (void)playSoundFromFile {
    NSString *lcMainPath = [NSHomeDirectory() stringByDeletingLastPathComponent];
    NSString *audioPath = [lcMainPath stringByAppendingPathComponent:@"PRIVATEUSERFOLDER/60Parsecs-2.mp3"];
    
    // Check if file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:audioPath]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
            UIViewController *rootVC = keyWindow.rootViewController;
            
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                           message:[NSString stringWithFormat:@"File not found at:\n%@", audioPath]
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [rootVC presentViewController:alert animated:YES completion:nil];
        });
        return;
    }
    
    NSURL *audioURL = [NSURL fileURLWithPath:audioPath];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *sessionError = nil;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayback error:&sessionError];
        [session setActive:YES error:&sessionError];
        
        NSError *playerError = nil;
        self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:audioURL error:&playerError];
        
        if (playerError) {
            UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
            UIViewController *rootVC = keyWindow.rootViewController;
            
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Player Error"
                                                                           message:playerError.localizedDescription
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [rootVC presentViewController:alert animated:YES completion:nil];
            return;
        }
        
        self.audioPlayer.delegate = self;
        [self.audioPlayer prepareToPlay];
        
        BOOL success = [self.audioPlayer play];
        
        if (!success) {
            UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
            UIViewController *rootVC = keyWindow.rootViewController;
            
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Playback Failed"
                                                                           message:@"Could not start audio playback"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [rootVC presentViewController:alert animated:YES completion:nil];
        }
    });
}


- (void)playButtonTapped {
    NSLog(@"[SoundPlayer] Button tapped!");
    [self playSoundFromFile];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    NSLog(@"[SoundPlayer] Finished playing (success: %d)", flag);
}

@end

// Global player instance
static SoundPlayerFromFile *globalPlayer = nil;
static void (*original_viewDidAppear)(id, SEL, BOOL) = NULL;

// Swizzled method
void swizzled_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (original_viewDidAppear) {
        original_viewDidAppear(self, _cmd, animated);
    }
    
    if (!globalPlayer) return;
    
    UIViewController *vc = (UIViewController *)self;
    
    // Avoid duplicate button using associated object
    if (objc_getAssociatedObject(vc.view, "soundButtonAdded")) {
        return;
    }
    
    objc_setAssociatedObject(vc.view, "soundButtonAdded", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:@"🔊 Play File" forState:UIControlStateNormal];
    button.backgroundColor = [UIColor systemPurpleColor];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.layer.cornerRadius = 10;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:globalPlayer action:@selector(playButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    [vc.view addSubview:button];
    
    [NSLayoutConstraint activateConstraints:@[
        [button.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [button.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:20],
        [button.widthAnchor constraintEqualToConstant:150],
        [button.heightAnchor constraintEqualToConstant:44]
    ]];
    
    NSLog(@"[SoundPlayer] Button added to %@", vc);
}

__attribute__((constructor))
static void initialize() {
    NSLog(@"[SoundPlayer] Dylib loaded!");
    
    dispatch_async(dispatch_get_main_queue(), ^{
        globalPlayer = [[SoundPlayerFromFile alloc] init];
        
        Method method = class_getInstanceMethod([UIViewController class], @selector(viewDidAppear:));
        original_viewDidAppear = (void *)method_getImplementation(method);
        method_setImplementation(method, (IMP)swizzled_viewDidAppear);
        
        NSLog(@"[SoundPlayer] Swizzle complete.");
    });
}
