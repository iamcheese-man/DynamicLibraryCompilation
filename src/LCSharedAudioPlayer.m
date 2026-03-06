// LCSharedAudioPlayer.m
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface LCSharedAudioPlayer : NSObject <AVAudioPlayerDelegate, UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
@property (nonatomic, strong) NSArray *audioFiles;
@property (nonatomic, strong) NSString *sharedPath;
@property (nonatomic, strong) UIViewController *playerVC;
- (void)showAudioBrowser;
@end

@implementation LCSharedAudioPlayer

- (instancetype)init {
    self = [super init];
    if (self) {
        // Get LC_SHARED_FOLDER path from environment
        const char *sharedPathC = getenv("LC_SHARED_FOLDER");
        if (sharedPathC) {
            _sharedPath = [NSString stringWithUTF8String:sharedPathC];
        } else {
            // Fallback
            NSString *lcMainPath = [NSHomeDirectory() stringByDeletingLastPathComponent];
            _sharedPath = [lcMainPath stringByAppendingPathComponent:@"LCShared"];
        }
        
        [self loadAudioFiles];
    }
    return self;
}

- (void)loadAudioFiles {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    
    NSArray *allFiles = [fm contentsOfDirectoryAtPath:self.sharedPath error:&error];
    
    if (error) {
        NSLog(@"[LCSharedAudioPlayer] Error reading LCShared: %@", error);
        self.audioFiles = @[];
        return;
    }
    
    // Filter for audio files
    NSPredicate *audioPredicate = [NSPredicate predicateWithBlock:^BOOL(NSString *filename, NSDictionary *bindings) {
        NSString *ext = [[filename pathExtension] lowercaseString];
        return [ext isEqualToString:@"mp3"] ||
               [ext isEqualToString:@"m4a"] ||
               [ext isEqualToString:@"wav"] ||
               [ext isEqualToString:@"aac"] ||
               [ext isEqualToString:@"flac"] ||
               [ext isEqualToString:@"ogg"];
    }];
    
    self.audioFiles = [allFiles filteredArrayUsingPredicate:audioPredicate];
    
    NSLog(@"[LCSharedAudioPlayer] Found %lu audio files in LCShared", (unsigned long)self.audioFiles.count);
}

- (void)playSoundFile:(NSString *)filename {
    NSString *filePath = [self.sharedPath stringByAppendingPathComponent:filename];
    
    NSLog(@"[LCSharedAudioPlayer] Playing: %@", filename);
    
    NSURL *audioURL = [NSURL fileURLWithPath:filePath];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *sessionError = nil;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayback error:&sessionError];
        [session setActive:YES error:&sessionError];
        
        NSError *playerError = nil;
        self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:audioURL error:&playerError];
        
        if (playerError) {
            NSLog(@"[LCSharedAudioPlayer] Player error: %@", playerError);
            [self showAlert:@"Error" message:[NSString stringWithFormat:@"Could not play: %@", playerError.localizedDescription]];
            return;
        }
        
        self.audioPlayer.delegate = self;
        [self.audioPlayer prepareToPlay];
        
        BOOL success = [self.audioPlayer play];
        
        if (success) {
            NSLog(@"[LCSharedAudioPlayer] ✅ Playing: %@ (%.2fs)", filename, self.audioPlayer.duration);
            [self showAlert:@"Now Playing" message:[NSString stringWithFormat:@"%@\n%.1f seconds", filename, self.audioPlayer.duration]];
        } else {
            NSLog(@"[LCSharedAudioPlayer] ❌ Failed to play");
            [self showAlert:@"Error" message:@"Failed to start playback"];
        }
    });
}

- (void)showAudioBrowser {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self loadAudioFiles]; // Refresh file list
        
        UITableViewController *tableVC = [[UITableViewController alloc] initWithStyle:UITableViewStylePlain];
        tableVC.title = @"🔊 LCShared Audio";
        tableVC.tableView.delegate = self;
        tableVC.tableView.dataSource = self;
        [tableVC.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"AudioCell"];
        
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:tableVC];
        
        UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeBrowser)];
        tableVC.navigationItem.rightBarButtonItem = closeButton;
        
        UIBarButtonItem *refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshList:)];
        tableVC.navigationItem.leftBarButtonItem = refreshButton;
        
        self.playerVC = navController;
        
        UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }
        
        if (self.audioFiles.count == 0) {
            [self showAlert:@"No Audio Files" message:[NSString stringWithFormat:@"No audio files found in:\n%@\n\nSupported: mp3, m4a, wav, aac, flac, ogg", self.sharedPath]];
        } else {
            [rootVC presentViewController:navController animated:YES completion:nil];
        }
    });
}

- (void)refreshList:(id)sender {
    [self loadAudioFiles];
    UITableViewController *tableVC = (UITableViewController *)[(UINavigationController *)self.playerVC topViewController];
    [tableVC.tableView reloadData];
    
    [self showAlert:@"Refreshed" message:[NSString stringWithFormat:@"Found %lu audio files", (unsigned long)self.audioFiles.count]];
}

- (void)closeBrowser {
    [self.playerVC dismissViewControllerAnimated:YES completion:nil];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        
        UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }
        [rootVC presentViewController:alert animated:YES completion:nil];
    });
}

// UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.audioFiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AudioCell" forIndexPath:indexPath];
    
    NSString *filename = self.audioFiles[indexPath.row];
    cell.textLabel.text = filename;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    return cell;
}

// UITableViewDelegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSString *filename = self.audioFiles[indexPath.row];
    [self playSoundFile:filename];
}

// AVAudioPlayerDelegate
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    NSLog(@"[LCSharedAudioPlayer] Finished playing (success: %d)", flag);
}

@end

// Global player instance
static LCSharedAudioPlayer *globalPlayer = nil;
static void (*original_viewDidAppear)(id, SEL, BOOL) = NULL;

// Swizzled method
void swizzled_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (original_viewDidAppear) {
        original_viewDidAppear(self, _cmd, animated);
    }
    
    if (!globalPlayer) return;
    
    UIViewController *vc = (UIViewController *)self;
    
    // Avoid duplicate button
    if (objc_getAssociatedObject(vc.view, "audioPlayerButtonAdded")) {
        return;
    }
    
    objc_setAssociatedObject(vc.view, "audioPlayerButtonAdded", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:@"🎵 LCShared Audio" forState:UIControlStateNormal];
    button.backgroundColor = [UIColor systemOrangeColor];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.layer.cornerRadius = 10;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:globalPlayer action:@selector(showAudioBrowser) forControlEvents:UIControlEventTouchUpInside];
    
    [vc.view addSubview:button];
    
    [NSLayoutConstraint activateConstraints:@[
        [button.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [button.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:20],
        [button.widthAnchor constraintEqualToConstant:180],
        [button.heightAnchor constraintEqualToConstant:44]
    ]];
    
    NSLog(@"[LCSharedAudioPlayer] Button added to %@", vc);
}

__attribute__((constructor))
static void initialize() {
    NSLog(@"[LCSharedAudioPlayer] Dylib loaded!");
    
    dispatch_async(dispatch_get_main_queue(), ^{
        globalPlayer = [[LCSharedAudioPlayer alloc] init];
        
        Method method = class_getInstanceMethod([UIViewController class], @selector(viewDidAppear:));
        original_viewDidAppear = (void *)method_getImplementation(method);
        method_setImplementation(method, (IMP)swizzled_viewDidAppear);
        
        NSLog(@"[LCSharedAudioPlayer] Swizzle complete. LC_SHARED_FOLDER path: %@", globalPlayer.sharedPath);
    });
}
