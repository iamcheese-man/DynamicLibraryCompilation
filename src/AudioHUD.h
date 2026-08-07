#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - AudioFileScanner

@interface AudioFileScanner : NSObject

// Auto-discovers the LCShared folder at runtime (sandbox-local first, then
// scans app containers / app groups for a folder literally named LCShared).
+ (nullable NSString *)resolvedLCSharedPath;

// Recursively scans a directory for common audio file extensions and
// returns file URLs sorted alphabetically by filename.
+ (NSArray<NSURL *> *)scanForAudioFilesAtPath:(nullable NSString *)path;

@end

#pragma mark - AudioHUDButton

// Small draggable floating button. Tapping it presents the audio menu.
@interface AudioHUDButton : UIView

// Attaches (once) a shared HUD button instance to the given window.
+ (void)attachToWindow:(UIWindow *)window;

@end

#pragma mark - AudioHUDMenuController

@interface AudioHUDMenuController : UITableViewController

- (instancetype)initWithAudioFiles:(NSArray<NSURL *> *)files;

@end

NS_ASSUME_NONNULL_END
