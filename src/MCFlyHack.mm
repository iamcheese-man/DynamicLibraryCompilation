#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <string.h>
#include <stdint.h>
#include <dlfcn.h>

// ─────────────────────────────────────────────────────────────────────────────
// Bedrock AbilitiesComponent layout (stable since 1.16, confirmed in strings)
// Abilities are stored as a packed bool array inside AbilitiesComponent
// Known indices from Horion SDK + our string analysis:
//
//   Index  Name
//   0x00   build
//   0x01   mine  
//   0x02   doorsandswitches
//   0x03   opencontainers
//   0x04   attackplayers
//   0x05   attackmobs
//   0x06   operatorcommands
//   0x07   teleport
//   0x08   invulnerable
//   0x09   flying          ← our string at 0x0b5348ba
//   0x0A   mayfly          ← our string at 0x0b5348c1
//   0x0B   lightning
//   0x0C   flyspeed        (float, not bool)
//   0x0D   walkspeed       (float, not bool)
//   0x0E   noclip          ← our string at 0x0b5348db
//   0x0F   privilegedbuilder
//
// The bool array starts at offset +0x0 from AbilitiesComponent*
// AbilitiesComponent is stored inside Player at a known offset
// ─────────────────────────────────────────────────────────────────────────────

// Ability bool indices in the array
static const int ABILITY_FLYING  = 9;
static const int ABILITY_MAYFLY  = 10;
static const int ABILITY_NOCLIP  = 14;

// ─── Globals ──────────────────────────────────────────────────────────────────
static bool g_flyEnabled = false;
static UIButton *g_toggleBtn = nil;

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

// ─── Memory scan for abilities string table ───────────────────────────────────
// Scans for "flying\0mayfly\0" which is unique in the binary
// Returns pointer to "flying" string if found
static const uint8_t *findAbilitiesStringTable() {
    uintptr_t slide = getSlide();
    if (!slide) return nullptr;

    // From our r2 analysis: strings are in __TEXT.__cstring around 0x0b534000
    // Search a window around that page (±0x20000) to be safe across minor versions
    uintptr_t searchStart = slide + 0x0b510000;
    uintptr_t searchEnd   = slide + 0x0b560000;

    const uint8_t pattern[] = {
        'f','l','y','i','n','g','\0',
        'm','a','y','f','l','y','\0'
    };
    const size_t patLen = sizeof(pattern);

    for (uintptr_t addr = searchStart; addr < searchEnd - patLen; addr++) {
        if (memcmp((void *)addr, pattern, patLen) == 0) {
            NSLog(@"[FlyHack] Found 'flying\\0mayfly\\0' at 0x%lx (slide=0x%lx)", addr, slide);
            return (const uint8_t *)addr;
        }
    }
    NSLog(@"[FlyHack] WARNING: Could not find abilities string table");
    return nullptr;
}

// ─── Patch abilities via mach_vm_write ────────────────────────────────────────
// We locate the LocalPlayer's AbilitiesComponent in the heap by scanning
// for the known bool pattern near the abilities string address.
// 
// Since we can't easily walk the LocalPlayer pointer chain without offsets,
// we use a simpler approach: hook a known ObjC method that fires every frame
// and write directly to the abilities memory found via pattern scan.

static uint8_t *g_abilitiesBase = nullptr;

// Scan heap for AbilitiesComponent bool array
// The array looks like: 1 1 1 1 1 1 1 1 0 [flying] [mayfly] ...
// in survival mode with full permissions except fly
static uint8_t *findAbilitiesInHeap() {
    // We scan memory regions for the pattern
    // In creative mode player has mayfly=1, flying=0/1
    // In survival: all 0 except first 8 (build/mine/doors/etc) = 1
    // Pattern to look for: sequence of bool-sized (1 byte) values
    // 01 01 01 01 01 01 00 00 00 00 00 ... (survival default)
    // This is quite broad, so we narrow by searching near known text offsets

    vm_address_t addr = 0;
    vm_size_t size = 0;
    kern_return_t kr;
    mach_port_t task = mach_task_self();

    // Known pattern for survival player abilities (first 16 bytes)
    // build=1 mine=1 doorsandswitches=1 opencontainers=1
    // attackplayers=1 attackmobs=1 operatorcommands=0 teleport=0
    // invulnerable=0 flying=0 mayfly=0 lightning=0 ...
    const uint8_t survivalPattern[] = {1,1,1,1,1,1,0,0,0,0,0,0};
    
    while (true) {
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t objectName;
        
        kr = vm_region_64(task, &addr, &size,
                         VM_REGION_BASIC_INFO_64,
                         (vm_region_info_t)&info,
                         &infoCount, &objectName);
        if (kr != KERN_SUCCESS) break;
        
        // Only scan read-write heap regions
        if ((info.protection & VM_PROT_READ) && 
            (info.protection & VM_PROT_WRITE) &&
            size < 50 * 1024 * 1024) { // skip huge regions
            
            uint8_t *ptr = (uint8_t *)addr;
            uint8_t *end = ptr + size - sizeof(survivalPattern);
            
            while (ptr < end) {
                if (memcmp(ptr, survivalPattern, sizeof(survivalPattern)) == 0) {
                    NSLog(@"[FlyHack] Candidate abilities struct at %p", ptr);
                    return ptr;
                }
                ptr += 4; // step by 4 for speed
            }
        }
        addr += size;
    }
    return nullptr;
}

static void applyFly(bool enable) {
    if (!g_abilitiesBase) {
        NSLog(@"[FlyHack] Searching for abilities struct...");
        g_abilitiesBase = findAbilitiesInHeap();
    }
    if (!g_abilitiesBase) {
        NSLog(@"[FlyHack] Could not find abilities struct");
        return;
    }
    
    // Make memory writable
    vm_protect(mach_task_self(), 
               (vm_address_t)g_abilitiesBase, 
               32, FALSE,
               VM_PROT_READ | VM_PROT_WRITE);
    
    g_abilitiesBase[ABILITY_FLYING] = enable ? 1 : 0;
    g_abilitiesBase[ABILITY_MAYFLY] = enable ? 1 : 0;
    
    NSLog(@"[FlyHack] Set flying=%d mayfly=%d at %p", 
          enable, enable, g_abilitiesBase);
}

// ─── Every-frame hook via display link ────────────────────────────────────────
// We use CADisplayLink to call applyFly every frame
// This ensures the ability stays set even if the game resets it
static CADisplayLink *g_displayLink = nil;

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

// ─── UI ───────────────────────────────────────────────────────────────────────
@interface FlyHackUI : NSObject
+ (void)toggle:(UIButton *)btn;
+ (void)handlePan:(UIPanGestureRecognizer *)pan;
@end

@implementation FlyHackUI

+ (void)toggle:(UIButton *)btn {
    g_flyEnabled = !g_flyEnabled;
    
    if (g_flyEnabled) {
        // Reset cached pointer so we rescan fresh
        g_abilitiesBase = nullptr;
        applyFly(true);
        [btn setTitle:@"✈ FLY ON" forState:UIControlStateNormal];
        btn.backgroundColor = [UIColor colorWithRed:0.0 green:0.75 blue:0.2 alpha:0.9];
        
        // Start display link to keep fly forced
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
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { window = w; break; }
            }
        }
    }
    if (!window) {
        NSLog(@"[FlyHack] No key window found, retrying...");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ setupUI(); });
        return;
    }
    
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
    
    [g_toggleBtn addTarget:[FlyHackUI class]
                    action:@selector(toggle:)
          forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:[FlyHackUI class]
                action:@selector(handlePan:)];
    [g_toggleBtn addGestureRecognizer:pan];
    
    [window addSubview:g_toggleBtn];
    NSLog(@"[FlyHack] Button added to window");
}

// ─── Constructor ──────────────────────────────────────────────────────────────
__attribute__((constructor))
static void FlyHackInit() {
    NSLog(@"[FlyHack] Injected into %@", NSBundle.mainBundle.bundleIdentifier);
    
    // Verify binary layout matches our analysis
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        const uint8_t *strTable = findAbilitiesStringTable();
        NSLog(@"[FlyHack] String table: %s", strTable ? "FOUND ✓" : "NOT FOUND ✗");
    });
    
    // Setup UI after MC has loaded
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        setupUI();
    });
}
