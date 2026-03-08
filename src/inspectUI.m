#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface UIInspectorWindow : UIWindow
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, strong) UIView *inspectorPanel;
@property (nonatomic, assign) BOOL isInspecting;
@end

@implementation UIInspectorWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 100;
        self.backgroundColor = [UIColor clearColor];
        self.hidden = NO;
        [self setupFloatingButton];
    }
    return self;
}

- (void)setupFloatingButton {
    // Create floating button
    self.floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatingButton.frame = CGRectMake(20, 100, 60, 60);
    self.floatingButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.9];
    self.floatingButton.layer.cornerRadius = 30;
    self.floatingButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.floatingButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.floatingButton.layer.shadowOpacity = 0.3;
    self.floatingButton.layer.shadowRadius = 4;
    
    [self.floatingButton setTitle:@"ð" forState:UIControlStateNormal];
    self.floatingButton.titleLabel.font = [UIFont systemFontOfSize:30];
    
    [self.floatingButton addTarget:self action:@selector(toggleInspector) forControlEvents:UIControlEventTouchUpInside];
    
    // Add pan gesture for dragging
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.floatingButton addGestureRecognizer:pan];
    
    [self addSubview:self.floatingButton];
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self];
    CGPoint newCenter = CGPointMake(self.floatingButton.center.x + translation.x,
                                     self.floatingButton.center.y + translation.y);
    
    // Keep button within bounds
    CGFloat radius = 30;
    newCenter.x = MAX(radius, MIN(self.bounds.size.width - radius, newCenter.x));
    newCenter.y = MAX(radius, MIN(self.bounds.size.height - radius, newCenter.y));
    
    self.floatingButton.center = newCenter;
    [gesture setTranslation:CGPointZero inView:self];
}

- (void)toggleInspector {
    if (self.isInspecting) {
        [self stopInspecting];
    } else {
        [self startInspecting];
    }
}

- (void)startInspecting {
    self.isInspecting = YES;
    [self.floatingButton setTitle:@"â" forState:UIControlStateNormal];
    self.floatingButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:0.9];
    
    // Enable tap gesture on window to inspect views
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleInspectorTap:)];
    tap.numberOfTapsRequired = 1;
    [self addGestureRecognizer:tap];
}

- (void)stopInspecting {
    self.isInspecting = NO;
    [self.floatingButton setTitle:@"ð" forState:UIControlStateNormal];
    self.floatingButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.9];
    
    // Remove tap gesture
    for (UIGestureRecognizer *gesture in self.gestureRecognizers) {
        if ([gesture isKindOfClass:[UITapGestureRecognizer class]]) {
            [self removeGestureRecognizer:gesture];
        }
    }
    
    [self hideInspectorPanel];
}

- (void)handleInspectorTap:(UITapGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self];
    
    // Don't inspect if tapping the floating button
    if (CGRectContainsPoint(self.floatingButton.frame, point)) {
        return;
    }
    
    // Find the main app window
    UIWindow *mainWindow = nil;
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window != self && !window.hidden && window.alpha > 0) {
            mainWindow = window;
            break;
        }
    }
    
    if (!mainWindow) return;
    
    // Convert point to main window coordinates
    CGPoint windowPoint = [self convertPoint:point toWindow:mainWindow];
    
    // Find the deepest view at this point
    UIView *targetView = [self findDeepestViewAtPoint:windowPoint inView:mainWindow];
    
    if (targetView) {
        [self showInspectorPanelForView:targetView];
    }
}

- (UIView *)findDeepestViewAtPoint:(CGPoint)point inView:(UIView *)view {
    // Check if point is within view bounds
    if (![view pointInside:[view convertPoint:point fromView:nil] withEvent:nil]) {
        return nil;
    }
    
    // Check subviews in reverse order (topmost first)
    for (UIView *subview in [view.subviews reverseObjectEnumerator]) {
        UIView *deepestView = [self findDeepestViewAtPoint:point inView:subview];
        if (deepestView) {
            return deepestView;
        }
    }
    
    // If no subview contains the point, return this view
    return view;
}

- (void)showInspectorPanelForView:(UIView *)view {
    [self hideInspectorPanel];
    
    // Highlight the selected view
    [self highlightView:view];
    
    // Create inspector panel
    CGFloat panelHeight = 400;
    self.inspectorPanel = [[UIView alloc] initWithFrame:CGRectMake(0, self.bounds.size.height - panelHeight, self.bounds.size.width, panelHeight)];
    self.inspectorPanel.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    self.inspectorPanel.layer.cornerRadius = 20;
    self.inspectorPanel.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    
    // Create scroll view for content
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(10, 50, self.bounds.size.width - 20, panelHeight - 60)];
    scrollView.backgroundColor = [UIColor clearColor];
    [self.inspectorPanel addSubview:scrollView];
    
    // Title
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 10, self.bounds.size.width - 40, 30)];
    titleLabel.text = @"UI Inspector";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [self.inspectorPanel addSubview:titleLabel];
    
    // Get view info
    NSString *info = [self getViewInfo:view];
    
    // Create info label
    UILabel *infoLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, scrollView.bounds.size.width - 20, 1000)];
    infoLabel.text = info;
    infoLabel.textColor = [UIColor whiteColor];
    infoLabel.font = [UIFont systemFontOfSize:12];
    infoLabel.numberOfLines = 0;
    [infoLabel sizeToFit];
    [scrollView addSubview:infoLabel];
    
    scrollView.contentSize = CGSizeMake(scrollView.bounds.size.width, infoLabel.frame.size.height + 20);
    
    // Add close button
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.frame = CGRectMake(self.bounds.size.width - 60, 10, 50, 30);
    [closeButton setTitle:@"Close" forState:UIControlStateNormal];
    [closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(hideInspectorPanel) forControlEvents:UIControlEventTouchUpInside];
    [self.inspectorPanel addSubview:closeButton];
    
    [self addSubview:self.inspectorPanel];
    
    // Animate in
    self.inspectorPanel.transform = CGAffineTransformMakeTranslation(0, panelHeight);
    [UIView animateWithDuration:0.3 animations:^{
        self.inspectorPanel.transform = CGAffineTransformIdentity;
    }];
}

- (void)highlightView:(UIView *)view {
    // Remove old highlights
    for (UIView *subview in self.subviews) {
        if ([subview isKindOfClass:[UIView class]] && subview.tag == 9999) {
            [subview removeFromSuperview];
        }
    }
    
    // Get view's frame in window coordinates
    CGRect frame = [view.superview convertRect:view.frame toView:nil];
    
    // Create highlight overlay
    UIView *highlight = [[UIView alloc] initWithFrame:frame];
    highlight.backgroundColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.3];
    highlight.layer.borderColor = [UIColor redColor].CGColor;
    highlight.layer.borderWidth = 2;
    highlight.tag = 9999;
    highlight.userInteractionEnabled = NO;
    [self addSubview:highlight];
    
    // Fade out after 2 seconds
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 animations:^{
            highlight.alpha = 0;
        } completion:^(BOOL finished) {
            [highlight removeFromSuperview];
        }];
    });
}

- (NSString *)getViewInfo:(UIView *)view {
    NSMutableString *info = [NSMutableString string];
    
    // Class name
    [info appendFormat:@"ð¦ Class: %@\n\n", NSStringFromClass([view class])];
    
    // Frame
    [info appendFormat:@"ð Frame:\n"];
    [info appendFormat:@"  Origin: (%.1f, %.1f)\n", view.frame.origin.x, view.frame.origin.y];
    [info appendFormat:@"  Size: %.1f Ã %.1f\n\n", view.frame.size.width, view.frame.size.height];
    
    // Bounds
    [info appendFormat:@"ð Bounds:\n"];
    [info appendFormat:@"  Origin: (%.1f, %.1f)\n", view.bounds.origin.x, view.bounds.origin.y];
    [info appendFormat:@"  Size: %.1f Ã %.1f\n\n", view.bounds.size.width, view.bounds.size.height];
    
    // Properties
    [info appendFormat:@"âï¸ Properties:\n"];
    [info appendFormat:@"  Hidden: %@\n", view.hidden ? @"YES" : @"NO"];
    [info appendFormat:@"  Alpha: %.2f\n", view.alpha];
    [info appendFormat:@"  Background: %@\n", view.backgroundColor ?: @"nil"];
    [info appendFormat:@"  User Interaction: %@\n", view.userInteractionEnabled ? @"YES" : @"NO"];
    [info appendFormat:@"  Tag: %ld\n\n", (long)view.tag];
    
    // Special properties for specific classes
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        [info appendFormat:@"ð Label Properties:\n"];
        [info appendFormat:@"  Text: %@\n", label.text ?: @"nil"];
        [info appendFormat:@"  Font: %@\n", label.font.fontName];
        [info appendFormat:@"  Font Size: %.1f\n", label.font.pointSize];
        [info appendFormat:@"  Text Color: %@\n", label.textColor];
        [info appendFormat:@"  Lines: %ld\n\n", (long)label.numberOfLines];
    } else if ([view isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)view;
        [info appendFormat:@"ð Button Properties:\n"];
        [info appendFormat:@"  Title: %@\n", [button titleForState:UIControlStateNormal] ?: @"nil"];
        [info appendFormat:@"  Enabled: %@\n", button.enabled ? @"YES" : @"NO"];
        [info appendFormat:@"  Selected: %@\n\n", button.selected ? @"YES" : @"NO"];
    } else if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView *imageView = (UIImageView *)view;
        [info appendFormat:@"ð¼ ImageView Properties:\n"];
        [info appendFormat:@"  Image: %@\n", imageView.image ? @"Present" : @"nil"];
        [info appendFormat:@"  Content Mode: %ld\n\n", (long)imageView.contentMode];
    } else if ([view isKindOfClass:[UITextField class]]) {
        UITextField *textField = (UITextField *)view;
        [info appendFormat:@"âï¸ TextField Properties:\n"];
        [info appendFormat:@"  Text: %@\n", textField.text ?: @"nil"];
        [info appendFormat:@"  Placeholder: %@\n", textField.placeholder ?: @"nil"];
        [info appendFormat:@"  Secure: %@\n\n", textField.secureTextEntry ? @"YES" : @"NO"];
    }
    
    // Gesture recognizers
    if (view.gestureRecognizers.count > 0) {
        [info appendFormat:@"ð Gesture Recognizers (%lu):\n", (unsigned long)view.gestureRecognizers.count];
        for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
            [info appendFormat:@"  â¢ %@\n", NSStringFromClass([gesture class])];
        }
        [info appendString:@"\n"];
    }
    
    // Subviews
    [info appendFormat:@"ð³ Subviews (%lu):\n", (unsigned long)view.subviews.count];
    for (UIView *subview in view.subviews) {
        [info appendFormat:@"  â¢ %@\n", NSStringFromClass([subview class])];
    }
    
    // Accessibility
    if (view.accessibilityLabel || view.accessibilityHint) {
        [info appendString:@"\nâ¿ï¸ Accessibility:\n"];
        if (view.accessibilityLabel) {
            [info appendFormat:@"  Label: %@\n", view.accessibilityLabel];
        }
        if (view.accessibilityHint) {
            [info appendFormat:@"  Hint: %@\n", view.accessibilityHint];
        }
    }
    
    // Actions (for UIControl subclasses)
    if ([view isKindOfClass:[UIControl class]]) {
        UIControl *control = (UIControl *)view;
        NSArray *targets = [control allTargets].allObjects;
        if (targets.count > 0) {
            [info appendString:@"\nð¯ Target-Actions:\n"];
            for (id target in targets) {
                NSArray *actions = [control actionsForTarget:target forControlEvent:UIControlEventAllEvents];
                for (NSString *action in actions) {
                    [info appendFormat:@"  â¢ %@ -> %@\n", NSStringFromClass([target class]), action];
                }
            }
        }
    }
    
    return info;
}

- (void)hideInspectorPanel {
    if (self.inspectorPanel) {
        [UIView animateWithDuration:0.3 animations:^{
            self.inspectorPanel.transform = CGAffineTransformMakeTranslation(0, self.inspectorPanel.frame.size.height);
        } completion:^(BOOL finished) {
            [self.inspectorPanel removeFromSuperview];
            self.inspectorPanel = nil;
        }];
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // Allow touches on floating button and inspector panel
    if (CGRectContainsPoint(self.floatingButton.frame, point)) {
        return [self.floatingButton hitTest:[self.floatingButton convertPoint:point fromView:self] withEvent:event];
    }
    
    if (self.inspectorPanel && CGRectContainsPoint(self.inspectorPanel.frame, point)) {
        return [self.inspectorPanel hitTest:[self.inspectorPanel convertPoint:point fromView:self] withEvent:event];
    }
    
    // Pass through all other touches
    return nil;
}

@end

// Constructor to inject the inspector window
__attribute__((constructor))
static void initialize() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIInspectorWindow *window = [[UIInspectorWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        window.rootViewController = [[UIViewController alloc] init];
        [window makeKeyAndVisible];
        
        // Make sure the main app window is still key
        for (UIWindow *win in [UIApplication sharedApplication].windows) {
            if (win != window && win.rootViewController) {
                [win makeKeyWindow];
                break;
            }
        }
    });
}
