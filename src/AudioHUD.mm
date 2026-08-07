#import "AudioHUD.h"
#import <AVFoundation/AVFoundation.h>

#pragma mark - AudioFileScanner

static NSArray<NSString *> *AudioExtensions(void) {
    return @[@"mp3", @"m4a", @"wav", @"aac", @"flac", @"aiff", @"aif", @"caf", @"alac"];
}

@implementation AudioFileScanner

+ (nullable NSString *)resolvedLCSharedPath {
    const char *envPath = getenv("LC_SHARED_FOLDER");
    if (!envPath) {
        NSLog(@"[AudioHUD] LC_SHARED_FOLDER env var not set.");
        return nil;
    }

    NSString *path = [NSString stringWithUTF8String:envPath];
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && isDir) {
        NSLog(@"[AudioHUD] Using LCShared path from LC_SHARED_FOLDER: %@", path);
        return path;
    }

    NSLog(@"[AudioHUD] LC_SHARED_FOLDER (%@) does not exist or isn't a directory.", path);
    return nil;
}

+ (NSArray<NSURL *> *)scanForAudioFilesAtPath:(nullable NSString *)path {
    NSMutableArray<NSURL *> *results = [NSMutableArray array];
    if (path.length == 0) {
        return results;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *rootURL = [NSURL fileURLWithPath:path isDirectory:YES];
    NSSet<NSString *> *exts = [NSSet setWithArray:AudioExtensions()];

    NSDirectoryEnumerator<NSURL *> *enumerator =
        [fm enumeratorAtURL:rootURL
 includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                    options:0
               errorHandler:^BOOL(NSURL * _Nonnull url, NSError * _Nonnull error) {
        NSLog(@"[AudioHUD] Enumeration error at %@: %@", url, error);
        return YES; // keep going
    }];

    for (NSURL *fileURL in enumerator) {
        NSNumber *isDir = nil;
        [fileURL getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if (isDir.boolValue) {
            continue;
        }
        NSString *ext = fileURL.pathExtension.lowercaseString;
        if ([exts containsObject:ext]) {
            [results addObject:fileURL];
        }
    }

    return [results sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        return [a.lastPathComponent caseInsensitiveCompare:b.lastPathComponent];
    }];
}

@end

#pragma mark - AudioHUDButton

@interface AudioHUDButton ()
@property (nonatomic, weak) UIWindow *hostWindow;
@end

@implementation AudioHUDButton

static AudioHUDButton *sSharedButton = nil;

+ (void)attachToWindow:(UIWindow *)window {
    if (sSharedButton && sSharedButton.superview) {
        [window bringSubviewToFront:sSharedButton];
        return;
    }

    CGRect frame = CGRectMake(window.bounds.size.width - 64, 120, 48, 48);
    AudioHUDButton *button = [[AudioHUDButton alloc] initWithFrame:frame];
    button.hostWindow = window;
    [window addSubview:button];
    [window bringSubviewToFront:button];
    sSharedButton = button;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
        self.layer.cornerRadius = frame.size.width / 2.0;
        self.layer.masksToBounds = YES;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
        self.layer.borderWidth = 1.0;

        UILabel *icon = [[UILabel alloc] initWithFrame:self.bounds];
        icon.text = @"\U0001F3B5"; // musical note
        icon.textAlignment = NSTextAlignmentCenter;
        icon.font = [UIFont systemFontOfSize:22];
        icon.userInteractionEnabled = NO;
        [self addSubview:icon];

        UIPanGestureRecognizer *pan =
            [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];

        UITapGestureRecognizer *tap =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *superview = self.superview;
    if (!superview) return;

    CGPoint translation = [pan translationInView:superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:superview];

    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        [self snapToNearestEdgeInSuperview:superview];
    }
}

- (void)snapToNearestEdgeInSuperview:(UIView *)superview {
    CGFloat midX = superview.bounds.size.width / 2.0;
    CGFloat halfWidth = self.bounds.size.width / 2.0;
    CGFloat targetX = (self.center.x < midX) ? (24 + halfWidth)
                                              : (superview.bounds.size.width - 24 - halfWidth);
    CGFloat minY = 60;
    CGFloat maxY = superview.bounds.size.height - 60;
    CGFloat clampedY = MAX(minY, MIN(maxY, self.center.y));

    [UIView animateWithDuration:0.25 animations:^{
        self.center = CGPointMake(targetX, clampedY);
    }];
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    UIWindow *window = self.hostWindow;
    if (!window) return;

    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) {
        root = root.presentedViewController;
    }
    if (!root) return;

    NSString *path = [AudioFileScanner resolvedLCSharedPath];
    NSArray<NSURL *> *files = [AudioFileScanner scanForAudioFilesAtPath:path];

    AudioHUDMenuController *menu = [[AudioHUDMenuController alloc] initWithAudioFiles:files];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:menu];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [root presentViewController:nav animated:YES completion:nil];
}

@end

#pragma mark - AudioHUDMenuController

@interface AudioHUDMenuController () <AVAudioPlayerDelegate>
@property (nonatomic, strong) NSArray<NSURL *> *files;
@property (nonatomic, strong, nullable) AVAudioPlayer *player;
@property (nonatomic, assign) NSInteger playingIndex;
@end

@implementation AudioHUDMenuController

- (instancetype)initWithAudioFiles:(NSArray<NSURL *> *)files {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _files = files;
        _playingIndex = NSNotFound;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [NSString stringWithFormat:@"LCShared Audio (%lu)", (unsigned long)self.files.count];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                        target:self
                                                        action:@selector(closeTapped)];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];

    NSError *sessionError = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:&sessionError];
    [session setActive:YES error:&sessionError];
    if (sessionError) {
        NSLog(@"[AudioHUD] Audio session error: %@", sessionError);
    }

    if (self.files.count == 0) {
        UILabel *empty = [[UILabel alloc] initWithFrame:CGRectZero];
        empty.text = @"No audio files found in LCShared.";
        empty.numberOfLines = 0;
        empty.textAlignment = NSTextAlignmentCenter;
        empty.textColor = [UIColor secondaryLabelColor];
        self.tableView.backgroundView = empty;
        empty.frame = self.tableView.bounds;
    }
}

- (void)closeTapped {
    [self.player stop];
    self.player = nil;
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.files.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    NSURL *url = self.files[indexPath.row];
    cell.textLabel.text = url.lastPathComponent;
    cell.accessoryType = (indexPath.row == self.playingIndex && self.player.isPlaying)
        ? UITableViewCellAccessoryCheckmark
        : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row == self.playingIndex && self.player.isPlaying) {
        [self.player pause];
        [tableView reloadData];
        return;
    }

    NSURL *url = self.files[indexPath.row];
    NSError *error = nil;
    self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
    if (error) {
        NSLog(@"[AudioHUD] Failed to play %@: %@", url, error);
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"Playback Error"
                                                  message:error.localizedDescription
                                           preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    self.player.delegate = self;
    [self.player play];
    self.playingIndex = indexPath.row;
    [tableView reloadData];
}

#pragma mark AVAudioPlayerDelegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    self.playingIndex = NSNotFound;
    [self.tableView reloadData];
}

@end

#pragma mark - Constructor entry point

// Runs automatically as soon as the dylib is loaded into the host process —
// no swizzling or Theos/Logos hooks required. We just wait for a key window
// to appear and attach the floating HUD button to it.
__attribute__((constructor))
static void AudioHUDInit(void) {
    NSLog(@"[AudioHUD] dylib loaded");

    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIWindowDidBecomeKeyNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification * _Nonnull note) {
        UIWindow *window = (UIWindow *)note.object;
        if (![window isKindOfClass:[UIWindow class]]) {
            return;
        }
        if (window.windowLevel != UIWindowLevelNormal) {
            return; // ignore alert / status bar windows
        }
        [AudioHUDButton attachToWindow:window];
    }];
}
