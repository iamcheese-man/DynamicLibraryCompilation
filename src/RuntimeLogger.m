#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// ─────────────────────────────────────────────
// IL2CPP function pointers
// ─────────────────────────────────────────────

typedef void* (*il2cpp_domain_get_t)(void);
typedef void** (*il2cpp_domain_get_assemblies_t)(void*, size_t*);
typedef void* (*il2cpp_assembly_get_image_t)(void*);
typedef const char* (*il2cpp_image_get_name_t)(void*);
typedef int (*il2cpp_image_get_class_count_t)(void*);
typedef void* (*il2cpp_image_get_class_t)(void*, int);
typedef const char* (*il2cpp_class_get_name_t)(void*);
typedef const char* (*il2cpp_class_get_namespace_t)(void*);
typedef void* (*il2cpp_class_get_methods_t)(void*, void**);
typedef const char* (*il2cpp_method_get_name_t)(void*);
typedef int (*il2cpp_method_get_param_count_t)(void*);

static il2cpp_domain_get_t            _domain_get;
static il2cpp_domain_get_assemblies_t _domain_get_assemblies;
static il2cpp_assembly_get_image_t    _assembly_get_image;
static il2cpp_image_get_name_t        _image_get_name;
static il2cpp_image_get_class_count_t _image_get_class_count;
static il2cpp_image_get_class_t       _image_get_class;
static il2cpp_class_get_name_t        _class_get_name;
static il2cpp_class_get_namespace_t   _class_get_namespace;
static il2cpp_class_get_methods_t     _class_get_methods;
static il2cpp_method_get_name_t       _method_get_name;
static il2cpp_method_get_param_count_t _method_get_param_count;

// ─────────────────────────────────────────────
// Shared log store
// ─────────────────────────────────────────────

static NSMutableArray<NSString *> *gLogLines;
static NSMutableArray<NSString *> *gFilteredLines;
static NSString *gCurrentFilter = @"";

static void addLog(NSString *line) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gLogLines.count > 2000) [gLogLines removeObjectAtIndex:0];
        [gLogLines addObject:line];
        if (gCurrentFilter.length == 0 ||
            [line rangeOfString:gCurrentFilter options:NSCaseInsensitiveSearch].location != NSNotFound) {
            if (gFilteredLines.count > 2000) [gFilteredLines removeObjectAtIndex:0];
            [gFilteredLines addObject:line];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"HUDLogUpdated" object:nil];
    });
}

// ─────────────────────────────────────────────
// IL2CPP symbol resolution
// ─────────────────────────────────────────────

static BOOL resolveSymbols(void) {
    void *handle = dlopen(NULL, RTLD_NOW);
    #define R(fn) _ ## fn = (fn ## _t)dlsym(handle, #fn); if (!_ ## fn) { NSLog(@"[HUD] Missing: %s", #fn); return NO; }
    R(il2cpp_domain_get)
    R(il2cpp_domain_get_assemblies)
    R(il2cpp_assembly_get_image)
    R(il2cpp_image_get_name)
    R(il2cpp_image_get_class_count)
    R(il2cpp_image_get_class)
    R(il2cpp_class_get_name)
    R(il2cpp_class_get_namespace)
    R(il2cpp_class_get_methods)
    R(il2cpp_method_get_name)
    R(il2cpp_method_get_param_count)
    #undef R
    return YES;
}

// ─────────────────────────────────────────────
// Keywords filter
// ─────────────────────────────────────────────

static NSArray<NSString *> *interestingKeywords(void) {
    return @[@"cooldown", @"Cooldown", @"craft", @"Craft", @"stamina", @"Stamina",
             @"hunger", @"Hunger", @"health", @"Health", @"attack", @"Attack",
             @"player", @"Player", @"item", @"Item", @"inventory", @"Inventory",
             @"timer", @"Timer", @"action", @"Action", @"ability", @"Ability",
             @"thirst", @"Thirst", @"survival", @"Survival", @"sleep", @"Sleep"];
}

static BOOL isInteresting(NSString *name) {
    for (NSString *kw in interestingKeywords()) {
        if ([name containsString:kw]) return YES;
    }
    return NO;
}

// ─────────────────────────────────────────────
// IL2CPP dump (runs on background thread)
// ─────────────────────────────────────────────

static void runDump(void) {
    if (!resolveSymbols()) {
        addLog(@"❌ Could not resolve IL2CPP symbols");
        return;
    }

    void *domain = _domain_get();
    if (!domain) { addLog(@"❌ No IL2CPP domain"); return; }

    size_t count = 0;
    void **assemblies = _domain_get_assemblies(domain, &count);
    addLog([NSString stringWithFormat:@"✅ Found %zu assemblies", count]);
    addLog(@"━━━━ INTERESTING CLASSES ━━━━");

    for (size_t a = 0; a < count; a++) {
        void *image = _assembly_get_image(assemblies[a]);
        if (!image) continue;

        const char *imgName = _image_get_name(image);
        int classCount = _image_get_class_count(image);

        for (int c = 0; c < classCount; c++) {
            void *klass = _image_get_class(image, c);
            if (!klass) continue;

            const char *cname = _class_get_name(klass);
            const char *cns   = _class_get_namespace(klass);
            NSString *className = [NSString stringWithUTF8String:cname ?: ""];
            NSString *classNS   = [NSString stringWithUTF8String:cns   ?: ""];

            if (!isInteresting(className)) continue;

            addLog([NSString stringWithFormat:@"\n📦 [%s] %@.%@", imgName, classNS, className]);

            void *iter = NULL;
            void *method;
            while ((method = _class_get_methods(klass, &iter))) {
                const char *mname = _method_get_name(method);
                int params = _method_get_param_count(method);
                addLog([NSString stringWithFormat:@"   ⚡ %s (%d params)", mname, params]);
            }
        }
    }

    addLog(@"━━━━ DUMP COMPLETE ━━━━");
}

// ─────────────────────────────────────────────
// HUD Panel (UIViewController)
// ─────────────────────────────────────────────

@interface HUDPanelViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UIButton *clearBtn;
@property (nonatomic, strong) UIButton *dumpBtn;
@property (nonatomic, strong) UIButton *exportBtn;
@end

@implementation HUDPanelViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.97];
    self.view.layer.cornerRadius = 16;
    self.view.layer.borderColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:1].CGColor;
    self.view.layer.borderWidth = 1.5;
    self.view.clipsToBounds = YES;

    // Title bar
    UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    titleBar.backgroundColor = [UIColor colorWithRed:0.1 green:0.6 blue:0.3 alpha:1];
    titleBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:titleBar];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, 200, 44)];
    title.text = @"⚡ IL2CPP Live HUD";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:15];
    [titleBar addSubview:title];

    // Count label
    self.countLabel = [[UILabel alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - 80, 0, 70, 44)];
    self.countLabel.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    self.countLabel.font = [UIFont systemFontOfSize:11];
    self.countLabel.textAlignment = NSTextAlignmentRight;
    self.countLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [titleBar addSubview:self.countLabel];

    // Search bar
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 44, self.view.bounds.size.width, 44)];
    self.searchBar.placeholder = @"Filter classes / methods...";
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.delegate = self;
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.searchBar];

    // Button bar
    CGFloat bw = self.view.bounds.size.width / 3.0;
    NSArray *btnTitles = @[@"🔄 Dump", @"🗑 Clear", @"📤 Export"];
    SEL btnActions[]   = {@selector(dumpTapped), @selector(clearTapped), @selector(exportTapped)};
    for (int i = 0; i < 3; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(bw * i, 88, bw, 36);
        btn.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [btn setTitle:btnTitles[i] forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor colorWithRed:0.2 green:0.9 blue:0.5 alpha:1] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:12];
        btn.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
        [btn addTarget:self action:btnActions[i] forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:btn];
    }

    // Table view
    CGFloat tableY = 124;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, tableY,
        self.view.bounds.size.width,
        self.view.bounds.size.height - tableY)
        style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorColor = [UIColor colorWithWhite:0.2 alpha:1];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    [self.view addSubview:self.tableView];

    // Listen for new log lines
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(logsUpdated)
                                                 name:@"HUDLogUpdated"
                                               object:nil];

    [self updateCount];
}

- (void)logsUpdated {
    [self.tableView reloadData];
    [self updateCount];
    // Auto scroll to bottom
    NSInteger rows = gFilteredLines.count;
    if (rows > 0) {
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:rows-1 inSection:0]
                              atScrollPosition:UITableViewScrollPositionBottom animated:NO];
    }
}

- (void)updateCount {
    self.countLabel.text = [NSString stringWithFormat:@"%lu lines", (unsigned long)gFilteredLines.count];
}

// Buttons
- (void)dumpTapped {
    addLog(@"🔍 Starting dump...");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        runDump();
    });
}

- (void)clearTapped {
    [gLogLines removeAllObjects];
    [gFilteredLines removeAllObjects];
    [self.tableView reloadData];
    [self updateCount];
}

- (void)exportTapped {
    NSString *text = [gLogLines componentsJoinedByString:@"\n"];
    UIActivityViewController *vc = [[UIActivityViewController alloc]
        initWithActivityItems:@[text] applicationActivities:nil];
    [self presentViewController:vc animated:YES completion:nil];
}

// Search
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    gCurrentFilter = text ?: @"";
    [gFilteredLines removeAllObjects];
    if (text.length == 0) {
        [gFilteredLines addObjectsFromArray:gLogLines];
    } else {
        for (NSString *line in gLogLines) {
            if ([line rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [gFilteredLines addObject:line];
            }
        }
    }
    [self.tableView reloadData];
    [self updateCount];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

// TableView
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return gFilteredLines.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
    cell.backgroundColor = UIColor.clearColor;
    cell.textLabel.textColor = [UIColor colorWithRed:0.3 green:1.0 blue:0.5 alpha:1];
    cell.textLabel.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.text = gFilteredLines[ip.row];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tv estimatedHeightForRowAtIndexPath:(NSIndexPath *)ip {
    return 22;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    // Copy tapped line to clipboard
    UIPasteboard.generalPasteboard.string = gFilteredLines[ip.row];
    addLog(@"📋 Copied to clipboard");
}

@end

// ─────────────────────────────────────────────
// Floating button window
// ─────────────────────────────────────────────

@interface HUDWindow : UIWindow
@end
@implementation HUDWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return YES; }
@end

static HUDWindow        *gHUDWindow;
static UIWindow         *gPanelWindow;
static BOOL              gPanelVisible = NO;

static void showPanel(void) {
    if (!gPanelWindow) {
        UIWindowScene *scene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
        }

        gPanelWindow = [[UIWindow alloc] initWithWindowScene:scene];
        gPanelWindow.windowLevel = UIWindowLevelAlert + 1;
        gPanelWindow.backgroundColor = UIColor.clearColor;

        CGRect screen = UIScreen.mainScreen.bounds;
        CGFloat w = MIN(screen.size.width - 20, 420);
        CGFloat h = screen.size.height * 0.7;
        gPanelWindow.frame = CGRectMake((screen.size.width - w) / 2,
                                        screen.size.height * 0.15,
                                        w, h);

        HUDPanelViewController *vc = [[HUDPanelViewController alloc] init];
        gPanelWindow.rootViewController = vc;
    }

    gPanelVisible = !gPanelVisible;
    gPanelWindow.hidden = !gPanelVisible;
    if (gPanelVisible) [gPanelWindow makeKeyAndVisible];
}

static void createFloatingButton(void) {
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
    }

    gHUDWindow = [[HUDWindow alloc] initWithWindowScene:scene];
    gHUDWindow.windowLevel = UIWindowLevelAlert + 2;
    gHUDWindow.backgroundColor = UIColor.clearColor;
    gHUDWindow.frame = CGRectMake(20, 100, 56, 56);
    gHUDWindow.hidden = NO;
    gHUDWindow.layer.cornerRadius = 28;
    gHUDWindow.clipsToBounds = YES;

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = UIColor.clearColor;
    gHUDWindow.rootViewController = vc;

    // Floating button
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0, 0, 56, 56);
    btn.backgroundColor = [UIColor colorWithRed:0.1 green:0.7 blue:0.3 alpha:0.95];
    btn.layer.cornerRadius = 28;
    btn.layer.shadowColor = UIColor.blackColor.CGColor;
    btn.layer.shadowOffset = CGSizeMake(0, 3);
    btn.layer.shadowRadius = 6;
    btn.layer.shadowOpacity = 0.5;
    [btn setTitle:@"⚡" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:22];
    [vc.view addSubview:btn];

    // Tap to toggle panel
    [btn addTarget:nil action:@selector(hudButtonTapped) forControlEvents:UIControlEventTouchUpInside];

    // Drag to move
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:@selector(hudDragged:)];
    [gHUDWindow addGestureRecognizer:pan];

    [gHUDWindow makeKeyAndVisible];
}

// ─────────────────────────────────────────────
// Category on UIApplication for button actions
// ─────────────────────────────────────────────

@interface NSObject (HUDActions)
- (void)hudButtonTapped;
- (void)hudDragged:(UIPanGestureRecognizer *)pan;
@end

@implementation NSObject (HUDActions)

- (void)hudButtonTapped {
    showPanel();
}

- (void)hudDragged:(UIPanGestureRecognizer *)pan {
    CGPoint delta = [pan translationInView:nil];
    CGRect frame = gHUDWindow.frame;
    frame.origin.x += delta.x;
    frame.origin.y += delta.y;

    // Keep on screen
    CGRect screen = UIScreen.mainScreen.bounds;
    frame.origin.x = MAX(0, MIN(frame.origin.x, screen.size.width  - frame.size.width));
    frame.origin.y = MAX(0, MIN(frame.origin.y, screen.size.height - frame.size.height));

    gHUDWindow.frame = frame;
    [pan setTranslation:CGPointZero inView:nil];
}

@end

// ─────────────────────────────────────────────
// Constructor
// ─────────────────────────────────────────────

__attribute__((constructor))
static void initialize(void) {
    gLogLines      = [NSMutableArray array];
    gFilteredLines = [NSMutableArray array];

    NSLog(@"[HUD] Loaded — waiting for app to be ready...");

    // Wait for UIApplication to be ready
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        createFloatingButton();
        addLog(@"⚡ IL2CPP HUD ready — tap 🔄 Dump to scan classes");
        addLog(@"💡 Tap any line to copy it");
        addLog(@"🔍 Use search to filter by keyword");
    });
}
