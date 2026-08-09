//
//  Tweak.m
//  AudioHUD
//
//  Floating HUD button. Tap it to scan the folder given by the
//  LC_TWEAKS_FOLDER environment variable for audio files, show them
//  in a menu, and play whichever one is tapped.
//
//  Build with Theos (works as a normal dylib tweak, no MobileSubstrate
//  hooking required — everything runs from a constructor, so it also
//  works fine as a LiveContainer-style injected plugin).
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

#pragma mark - HUDPlayerManager

@interface HUDPlayerManager : NSObject <UIGestureRecognizerDelegate>

@property (nonatomic, strong) UIWindow *hudWindow;
@property (nonatomic, strong) UIButton *hudButton;
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
@property (nonatomic, strong) NSArray<NSString *> *audioFiles;
@property (nonatomic, copy)   NSString *tweaksFolder;

+ (instancetype)sharedManager;
- (void)setup;

@end

@implementation HUDPlayerManager

+ (instancetype)sharedManager {
    static HUDPlayerManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[HUDPlayerManager alloc] init];
    });
    return shared;
}

#pragma mark Setup

- (void)setup {
    const char *env = getenv("LC_TWEAKS_FOLDER");
    self.tweaksFolder = env ? [NSString stringWithUTF8String:env] : nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self createHUD];
    });
}

- (void)createHUD {
    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s;
            break;
        }
    }
    if (!scene) {
        // Scene not ready yet — retry shortly.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{
            [self createHUD];
        });
        return;
    }

    const CGFloat size = 56.0;

    self.hudWindow = [[UIWindow alloc] initWithWindowScene:scene];
    self.hudWindow.frame = CGRectMake(20, 100, size, size);
    self.hudWindow.windowLevel = UIWindowLevelAlert + 1;
    self.hudWindow.backgroundColor = [UIColor clearColor];
    self.hudWindow.hidden = NO;

    self.hudButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.hudButton.frame = CGRectMake(0, 0, size, size);
    self.hudButton.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
    self.hudButton.layer.cornerRadius = size / 2.0;
    self.hudButton.layer.masksToBounds = YES;
    self.hudButton.layer.borderWidth = 1.0;
    self.hudButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.3].CGColor;

    UIImage *musicIcon = [UIImage systemImageNamed:@"music.note"];
    [self.hudButton setImage:musicIcon forState:UIControlStateNormal];
    self.hudButton.tintColor = [UIColor whiteColor];

    [self.hudButton addTarget:self
                        action:@selector(hudTapped)
              forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.delegate = self;
    [self.hudButton addGestureRecognizer:pan];

    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view.backgroundColor = [UIColor clearColor];
    [rootVC.view addSubview:self.hudButton];
    self.hudWindow.rootViewController = rootVC;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan ||
        gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:self.hudWindow];
        CGRect frame = self.hudWindow.frame;
        frame.origin.x += translation.x;
        frame.origin.y += translation.y;
        self.hudWindow.frame = frame;
        [gesture setTranslation:CGPointZero inView:self.hudWindow];
    }
}

#pragma mark Folder scan

- (NSArray<NSString *> *)scanForAudioFiles {
    NSMutableArray<NSString *> *results = [NSMutableArray array];

    if (self.tweaksFolder.length == 0) {
        return results;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:self.tweaksFolder isDirectory:&isDir] || !isDir) {
        return results;
    }

    static NSArray<NSString *> *audioExtensions = nil;
    if (!audioExtensions) {
        audioExtensions = @[@"mp3", @"m4a", @"wav", @"aac", @"flac", @"caf", @"aiff"];
    }

    NSError *error = nil;
    NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:self.tweaksFolder error:&error];
    if (error || !contents) {
        return results;
    }

    for (NSString *filename in contents) {
        NSString *ext = filename.pathExtension.lowercaseString;
        if ([audioExtensions containsObject:ext]) {
            [results addObject:filename];
        }
    }

    return [results sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

#pragma mark Menu

- (void)hudTapped {
    self.audioFiles = [self scanForAudioFiles];
    UIViewController *presenter = self.hudWindow.rootViewController;

    if (self.tweaksFolder.length == 0) {
        [self presentAlertTitle:@"No Folder Set"
                         message:@"Environment variable LC_TWEAKS_FOLDER is not set."
                            from:presenter];
        return;
    }

    if (self.audioFiles.count == 0) {
        [self presentAlertTitle:@"No Audio Files"
                         message:[NSString stringWithFormat:@"No audio files found in:\n%@", self.tweaksFolder]
                            from:presenter];
        return;
    }

    UIAlertController *menu =
        [UIAlertController alertControllerWithTitle:@"Audio Files"
                                             message:self.tweaksFolder
                                      preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSString *filename in self.audioFiles) {
        BOOL isCurrentlyPlaying = self.audioPlayer.isPlaying &&
            [self.audioPlayer.url.lastPathComponent isEqualToString:filename];
        NSString *title = isCurrentlyPlaying ? [NSString stringWithFormat:@"▶ %@", filename] : filename;

        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction * _Nonnull a) {
            [self playAudioFile:filename];
        }];
        [menu addAction:action];
    }

    if (self.audioPlayer.isPlaying) {
        UIAlertAction *stopAction = [UIAlertAction actionWithTitle:@"Stop Playback"
                                                               style:UIAlertActionStyleDestructive
                                                             handler:^(UIAlertAction * _Nonnull a) {
            [self.audioPlayer stop];
            self.audioPlayer = nil;
        }];
        [menu addAction:stopAction];
    }

    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    // iPad requires a popover source.
    if (menu.popoverPresentationController) {
        menu.popoverPresentationController.sourceView = self.hudButton;
        menu.popoverPresentationController.sourceRect = self.hudButton.bounds;
    }

    [presenter presentViewController:menu animated:YES completion:nil];
}

- (void)presentAlertTitle:(NSString *)title message:(NSString *)message from:(UIViewController *)vc {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                     message:message
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

#pragma mark Playback

- (void)playAudioFile:(NSString *)filename {
    NSString *fullPath = [self.tweaksFolder stringByAppendingPathComponent:filename];
    NSURL *url = [NSURL fileURLWithPath:fullPath];

    NSError *sessionError = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:&sessionError];
    [session setActive:YES error:&sessionError];

    NSError *playerError = nil;
    self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&playerError];

    if (playerError) {
        [self presentAlertTitle:@"Playback Error"
                         message:playerError.localizedDescription
                            from:self.hudWindow.rootViewController];
        return;
    }

    [self.audioPlayer prepareToPlay];
    [self.audioPlayer play];
}

@end

#pragma mark - Constructor

__attribute__((constructor))
static void AudioHUDInit(void) {
    // Only run inside app processes with a UI, not daemons/tools.
    if (![UIApplication respondsToSelector:@selector(sharedApplication)]) {
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{
        [[HUDPlayerManager sharedManager] setup];
    });
}
