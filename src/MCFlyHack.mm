#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <string.h>
#include <stdint.h>
#include <dlfcn.h>

// ─── Ability indices (stable across Bedrock versions) ─────────────────────────
static const int ABILITY_FLYING  = 9;
static const int ABILITY_MAYFLY  = 10;
static const int ABILITY_NOCLIP  = 14;

// ─── Globals ──────────────────────────────────────────────────────────────────
static bool g_flyEnabled = false;
static UIButton *g_toggleBtn = nil;
static CADisplayLink *g_displayLink = nil;
static uint8_t *g_abilitiesBase = nullptr;

// ─── ASLR slide ───────────────────────────────────────────────────────────────
static uintptr_t getSlide() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "minecraftpe")) {
            return (uintptr_t)_dyld_get_image_vmaddr_slide(i);
        }
    }
    return 0;
}

// ─── String table verification ────────────────────────────────────────────────
static const uint8_t *findAbilitiesStringTable() {
    uintptr_t slide = getSlide();
    if (!slide) return nullptr;

    const uint8_t pattern[] = {
        'f','l','y','i','n','g','\0',
        'm','a','y','f','l','y','\0'
    };

    uintptr_t searchStart = slide + 0x0b510000;
    uintptr_t searchEnd   = slide + 0x0b560000;

    for (uintptr_t addr = searchStart; addr < searchEnd - sizeof(pattern); addr++) {
        if (memcmp((void *)addr, pattern, sizeof(pattern)) == 0) {
            NSLog(@"[FlyHack] String table found at 0x%lx", addr);
            return (const uint8_t *)addr;
        }
    }
    NSLog(@"[FlyHack] WARNING: String table not found");
    return nullptr;
}

// ─── Heap scan for AbilitiesComponent ────────────────────────────────────────
static uint8_t *findAbilitiesInHeap() {
    // Survival default ability pattern:
    // build=1 mine=1 doorsandswitches=1 opencontainers=1
    // attackplayers=1 attackmobs=1 operatorcommands=0 teleport=0
    // invulnerable=0 flying=0 mayfly=0 lightning=0
    const uint8_t pattern[] = {1,1,1,1,1,1,0,0,0,0,0,0};

    vm_address_t addr = 0;
    vm_size_t size = 0;
    mach_port_t task = mach_task_self();

    while (true) {
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t objectName;

        kern_return_t kr = vm_region_64(task, &addr, &size,
                                        VM_REGION_BASIC_INFO_64,
                                        (vm_region_info_t)&info,
                                        &infoCount, &objectName);
        if (kr != KERN_SUCCESS) break;

        if ((info.protection & VM_PROT_READ) &&
            (info.protection & VM_PROT_WRITE) &&
            size < 50 * 1024 * 1024) {

            uint8_t *ptr = (uint8_t *)addr;
            uint8_t *end = ptr + size - sizeof(pattern);

            while (ptr < end) {
                if (memcmp(ptr, pattern, sizeof(pattern)) == 0) {
                    NSLog(@"[FlyHack] Candidate abilities struct at %p", ptr);
                    return ptr;
                }
                ptr += 4;
            }
        }
        addr += size;
    }
    return nullptr;
}

// ─── Apply fly ────────────────────────────────────────────────────────────────
static void applyFly(bool enable) {
    if (!g_abilitiesBase) {
        NSLog(@"[FlyHack] Scanning heap for abilities struct...");
        g_abilitiesBase = findAbilitiesInHeap();
    }
    if (!g_abilitiesBase) {
        NSLog(@"[FlyHack] Could not find abilities struct — are you in a world?");
        return;
    }

    vm_protect(mach_task_self(),
               (vm_address_t)g_abilitiesBase,
               32, FALSE,
               VM_PROT_READ | VM_PROT_WRITE);

    g_abilitiesBase[ABILITY_FLYING] = enable ? 1 : 0;
    g_abilitiesBase[ABILITY_MAYFLY] = enable ? 1 : 0;
    NSLog(@"[FlyHack] flying=%d mayfly=%d @ %p", enable, enable, g_abilitiesBase);
}

// ─── Display link ticker ──────────────────────────────────────────────────────
@interface FlyHackTicker : NSObject
+ (void)tick:(CADisplayLink *)link;
@end
@implementation FlyHackTicker
+ (void)tick:(CADisplayLink *)link {
    if (g_flyEnabled && g_abilitiesBase) {
        g_abilitiesBase[ABILITY_FLYING] = 1;
        g_abilitiesBase[ABILITY_MAYFLY] = 1;
    }
}
@end

// ─── Button actions ───────────────────────────────────────────────────────────
@interface FlyHackUI : NSObject
+ (void)toggle:(UIButton *)btn;
+ (void)handlePan:(UIPanGestureRecognizer *)pan;
@end

@implementation FlyHackUI

+ (void)toggle:(UIButton *)btn {
    g_flyEnabled = !g_flyEnabled;

    if (g_flyEnabled) {
        g_abilitiesBase = nullptr; // rescan fresh each time
        applyFly(true);
        [btn setTitle:@"✈ FLY ON" forState:UIControlStateNormal];
        btn.backgroundColor = [UIColor colorWithRed:0.0 green:0.75 blue:0.2 alpha:0.9];

        g_displayLink = [CADisplayLink displayLinkWithTarget:[FlyHackTicker class]
                                                    selector:@selector(tick:)];
        [g_displayLink addToRunLoop:NSRunLoop.mainRunLoop
                            forMode:NSRunLoopCommonModes];
    } else {
        applyFly(false);
        [btn setTitle:@"✈ FLY" forState:UIControlStateNormal];
        btn.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.9];

        [g_displayLink invalidate];
        g_displayLink = nil;
        g_abilitiesBase = nullptr;
    }

    NSLog(@"[FlyHack] Toggled: %s", g_flyEnabled ? "ON" : "OFF");
}

+ (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *v = pan.view;
    CGPoint delta = [pan translationInView:v.superview];
    v.center = CGPointMake(v.center.x + delta.x, v.center.y + delta.y);
    [pan setTranslation:CGPointZero inView:v.superview];
}

@end

// ─── Setup UI ─────────────────────────────────────────────────────────────────
static void setupUI() {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Get all windows from all scenes
        UIWindow *window = nil;
        NSArray<UIWindow *> *allWindows = nil;

        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                allWindows = ((UIWindowScene *)scene).windows;
            }
        }

        // MC puts its Metal render window last — use lastObject
        window = allWindows.lastObject;

        if (!window) {
            NSLog(@"[FlyHack] No window found, retrying in 2s...");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{ setupUI(); });
            return;
        }

        NSLog(@"[FlyHack] Using window: %@ (level: %f)", window, window.windowLevel);

        CGRect screen = UIScreen.mainScreen.bounds;

        g_toggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        g_toggleBtn.frame = CGRectMake(screen.size.width - 100, 100, 90, 36);
        g_toggleBtn.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.9];
        g_toggleBtn.layer.cornerRadius = 8;
        g_toggleBtn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.3].CGColor;
        g_toggleBtn.layer.borderWidth = 1;
        g_toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [g_toggleBtn setTitle:@"✈ FLY" forState:UIControlStateNormal];
        [g_toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

        // Raise above MC's Metal layer
        g_toggleBtn.layer.zPosition = 9999;

        // Bump window level so our button isn't buried
        window.windowLevel = UIWindowLevelAlert + 1;

        [g_toggleBtn addTarget:[FlyHackUI class]
                        action:@selector(toggle:)
              forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
            initWithTarget:[FlyHackUI class]
                    action:@selector(handlePan:)];
        [g_toggleBtn addGestureRecognizer:pan];

        [window addSubview:g_toggleBtn];
        [window bringSubviewToFront:g_toggleBtn];

        NSLog(@"[FlyHack] Button added to window successfully");
    });
}

// ─── Constructor ──────────────────────────────────────────────────────────────
__attribute__((constructor))
static void FlyHackInit() {
    NSLog(@"[FlyHack] Injected into %@", NSBundle.mainBundle.bundleIdentifier);

    // Verify binary layout
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        const uint8_t *strTable = findAbilitiesStringTable();
        NSLog(@"[FlyHack] String table: %s", strTable ? "FOUND ✓" : "NOT FOUND ✗");
    });

    // Wait 8 seconds for MC to fully initialize its Metal window
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        setupUI();
    });
}
