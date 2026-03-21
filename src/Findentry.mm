#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <dlfcn.h>
#include <string.h>

static void showAlert(NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                window = ((UIWindowScene *)scene).windows.lastObject;
                break;
            }
        }
        if (!window) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Inject" message:msg preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [UIPasteboard generalPasteboard].string = msg;
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [window.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

@interface ScanButton : NSObject
+ (void)scan;
@end

@implementation ScanButton
+ (void)scan {
    void *robloxLib = dlopen("/private/var/mobile/Containers/Data/Application/7387409E-8C5F-4161-BB43-175BF6FEEE03/Documents/Applications/com.gloop.deltamobile.app/Frameworks/RobloxLib.framework/RobloxLib", RTLD_NOLOAD);
    
    NSMutableString *result = [NSMutableString string];
    if (robloxLib) {
        const char *syms[] = {
            "lua_pushstring", "lua_getfield", "lua_pcall",
            "luaL_newstate", "lua_newstate", "lua_getglobal",
            "luaL_openlibs", "lua_call", "lua_settop",
            "rbx_lua_pushstring", "rbx_lua_pcall",
            NULL
        };
        for (int i = 0; syms[i]; i++) {
            void *sym = dlsym(robloxLib, syms[i]);
            if (sym) [result appendFormat:@"FOUND: %s = %p\n", syms[i], sym];
        }
        if (!result.length) [result appendString:@"No exports found"];
    } else {
        [result appendFormat:@"dlopen failed: %s", dlerror()];
    }
    showAlert(result);
}
@end

__attribute__((constructor))
static void init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                window = ((UIWindowScene *)scene).windows.lastObject;
                break;
            }
        }
        if (!window) return;
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(10, 100, 120, 40);
        btn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1 alpha:0.9];
        [btn setTitle:@"Scan Lua" forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.layer.cornerRadius = 8;
        btn.layer.zPosition = 9999;
        [btn addTarget:[ScanButton class] action:@selector(scan) forControlEvents:UIControlEventTouchUpInside];
        [window addSubview:btn];
    });
}
