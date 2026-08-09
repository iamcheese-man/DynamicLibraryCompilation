//
//  AudioHUD.m
//  Plain Objective-C dylib — no Theos required.
//
//  A small draggable HUD button. Tap it to either:
//    • scan the folder at $LC_TWEAKS_FOLDER for audio files, or
//    • pick ANY audio file via the system Files picker
//  and play whichever one you choose.
//
//  Build (plain clang, no Theos):
//    xcrun -sdk iphoneos clang \
//      -arch arm64 -miphoneos-version-min=14.0 -fobjc-arc \
//      -framework UIKit -framework AVFoundation -framework UniformTypeIdentifiers \
//      -dynamiclib AudioHUD.m -o AudioHUD.dylib
//    codesign -s - AudioHUD.dylib
//
//  Drop AudioHUD.dylib into LiveContainer as a tweak dylib for the app,
//  set LC_TWEAKS_FOLDER (optional — only needed for the folder-scan option).
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

#pragma mark - HUDView
//
// Handles its own drag-vs-tap logic with raw touch events instead of
// combining UIButton + UIPanGestureRecognizer (which can eat taps).
//

@protocol HUDViewTapHandler <NSObject>
- (void)hudTapped;
@end

@interface HUDView : UIView
@property (nonatomic, weak) id<HUDViewTapHandler> manager;
@property (nonatomic, assign) BOOL didDrag;
@end

@implementation HUDView

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.didDrag = NO;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.anyObject;
    CGPoint prev = [touch previousLocationInView:self];
    CGPoint cur  = [touch locationInView:self];
    CGFloat dx = cur.x - prev.x;
    CGFloat dy = cur.y - prev.y;

    if (fabs(dx) > 1.0 || fabs(dy) > 1.0) {
        self.didDrag = YES;
    }

    UIWindow *window = self.window;
    if (!window) return;

    CGRect frame = window.frame;
    frame.origin.x += dx;
    frame.origin.y += dy;

    // Keep it roughly on-screen.
    CGRect screenBounds = window.screen.bounds;
    frame.origin.x = MAX(-frame.size.width * 0.5, MIN(frame.origin.x, screenBounds.size.width - frame.size.width * 0.5));
    frame.origin.y = MAX(0, MIN(frame.origin.y, screenBounds.size.height - frame.size.height));

    window.frame = frame;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.didDrag) {
        [self.manager hudTapped];
    }
    self.didDrag = NO;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.didDrag = NO;
}

@end

#pragma mark - HUDPlayerManager

@interface HUDPlayerManager : NSObject <UIDocumentPickerDelegate, HUDViewTapHandler>

@property (nonatomic, strong) UIWindow *hudWindow;
@property (nonatomic, strong) HUDView *hudView;
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
@property (nonatomic, copy)   NSString *tweaksFolder;
@property (nonatomic, strong) NSURL *securityScopedURL; // currently-open picked file, if any

+ (instancetype)sharedManager;
- (void)setup;
- (void)hudTapped;

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

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(tryCreateHUD)
                                                  name:UIApplicationDidBecomeActiveNotification
                                                object:nil];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self tryCreateHUD];
    });
}

- (void)tryCreateHUD {
    if (self.hudWindow) return; // already created

    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s;
            break;
        }
    }

    if (!scene) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{
            [self tryCreateHUD];
        });
        return;
    }

    [self createHUDInScene:scene];
}

- (void)createHUDInScene:(UIWindowScene *)scene {
    const CGFloat size = 56.0;

    self.hudWindow = [[UIWindow alloc] initWithWindowScene:scene];
    self.hudWindow.frame = CGRectMake(20, 120, size, size);
    self.hudWindow.windowLevel = UIWindowLevelAlert + 1;
    self.hudWindow.backgroundColor = [UIColor clearColor];
    self.hudWindow.hidden = NO;

    self.hudView = [[HUDView alloc] initWithFrame:CGRectMake(0, 0, size, size)];
    self.hudView.manager = self;
    self.hudView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
    self.hudView.layer.cornerRadius = size / 2.0;
    self.hudView.layer.masksToBounds = YES;
    self.hudView.layer.borderWidth = 1.0;
    self.hudView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.3].CGColor;
    self.hudView.userInteractionEnabled = YES;
    self.hudView.multipleTouchEnabled = NO;

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectInset(self.hudView.bounds, 14, 14)];
    icon.image = [UIImage systemImageNamed:@"music.note"];
    icon.tintColor = [UIColor whiteColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.userInteractionEnabled = NO;
    [self.hudView addSubview:icon];

    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view.backgroundColor = [UIColor clearColor];
    [rootVC.view addSubview:self.hudView];
    self.hudWindow.rootViewController = rootVC;
}

#pragma mark Menu

- (void)hudTapped {
    UIViewController *presenter = self.hudWindow.rootViewController;

    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Play Audio"
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleActionSheet];

    [menu addAction:[UIAlertAction actionWithTitle:@"Choose File…"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull a) {
        [self presentFilePicker];
    }]];

    [menu addAction:[UIAlertAction actionWithTitle:@"Browse LC_TWEAKS_FOLDER"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull a) {
        [self presentFolderMenu];
    }]];

    if (self.audioPlayer.isPlaying) {
        [menu addAction:[UIAlertAction actionWithTitle:@"Stop Playback"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction * _Nonnull a) {
            [self stopPlayback];
        }]];
    }

    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (menu.popoverPresentationController) {
        menu.popoverPresentationController.sourceView = self.hudView;
        menu.popoverPresentationController.sourceRect = self.hudView.bounds;
    }

    [presenter presentViewController:menu animated:YES completion:nil];
}

#pragma mark Folder scan (existing behavior)

- (NSArray<NSString *> *)scanForAudioFiles {
    NSMutableArray<NSString *> *results = [NSMutableArray array];
    if (self.tweaksFolder.length == 0) return results;

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:self.tweaksFolder isDirectory:&isDir] || !isDir) return results;

    static NSArray<NSString *> *audioExtensions = nil;
    if (!audioExtensions) {
        audioExtensions = @[@"mp3", @"m4a", @"wav", @"aac", @"flac", @"caf", @"aiff"];
    }

    NSError *error = nil;
    NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:self.tweaksFolder error:&error];
    if (error || !contents) return results;

    for (NSString *filename in contents) {
        if ([audioExtensions containsObject:filename.pathExtension.lowercaseString]) {
            [results addObject:filename];
        }
    }
    return [results sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (void)presentFolderMenu {
    UIViewController *presenter = self.hudWindow.rootViewController;

    if (self.tweaksFolder.length == 0) {
        [self presentAlertTitle:@"No Folder Set"
                         message:@"Environment variable LC_TWEAKS_FOLDER is not set."
                            from:presenter];
        return;
    }

    NSArray<NSString *> *files = [self scanForAudioFiles];
    if (files.count == 0) {
        [self presentAlertTitle:@"No Audio Files"
                         message:[NSString stringWithFormat:@"No audio files found in:\n%@", self.tweaksFolder]
                            from:presenter];
        return;
    }

    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Audio Files"
                                                                    message:self.tweaksFolder
                                                             preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSString *filename in files) {
        [menu addAction:[UIAlertAction actionWithTitle:filename
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull a) {
            NSString *fullPath = [self.tweaksFolder stringByAppendingPathComponent:filename];
            [self playLocalFileAtURL:[NSURL fileURLWithPath:fullPath]];
        }]];
    }

    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (menu.popoverPresentationController) {
        menu.popoverPresentationController.sourceView = self.hudView;
        menu.popoverPresentationController.sourceRect = self.hudView.bounds;
    }

    [presenter presentViewController:menu animated:YES completion:nil];
}

#pragma mark File picker (new — play any audio file you choose)

- (void)presentFilePicker {
    // "public.audio" is a system UTI string — no UniformTypeIdentifiers
    // framework import/link required for this initializer.
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.audio"]
                                                                 inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self.hudWindow.rootViewController presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    [self playLocalFileAtURL:url isSecurityScoped:YES];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    // no-op
}

#pragma mark Playback

- (void)playLocalFileAtURL:(NSURL *)url {
    [self playLocalFileAtURL:url isSecurityScoped:NO];
}

- (void)playLocalFileAtURL:(NSURL *)url isSecurityScoped:(BOOL)isSecurityScoped {
    [self stopPlayback];

    if (isSecurityScoped) {
        if (![url startAccessingSecurityScopedResource]) {
            [self presentAlertTitle:@"Access Denied"
                             message:@"Couldn't get permission to read that file."
                                from:self.hudWindow.rootViewController];
            return;
        }
        self.securityScopedURL = url;
    }

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
        [self stopPlayback];
        return;
    }

    [self.audioPlayer prepareToPlay];
    [self.audioPlayer play];
}

- (void)stopPlayback {
    [self.audioPlayer stop];
    self.audioPlayer = nil;

    if (self.securityScopedURL) {
        [self.securityScopedURL stopAccessingSecurityScopedResource];
        self.securityScopedURL = nil;
    }
}

#pragma mark Alerts

- (void)presentAlertTitle:(NSString *)title message:(NSString *)message from:(UIViewController *)vc {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                     message:message
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - Constructor

__attribute__((constructor))
static void AudioHUDInit(void) {
    if (![UIApplication respondsToSelector:@selector(sharedApplication)]) {
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{
        [[HUDPlayerManager sharedManager] setup];
    });
}
