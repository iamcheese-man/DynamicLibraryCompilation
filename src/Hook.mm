#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

// Function pointer to original objc_msgSend
static void *(*orig_objc_msgSend)(id self, SEL _cmd, ...);

// Show alert helper
void showAlert(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        UIViewController *root = keyWindow.rootViewController;

        if (!root) return;

        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:title
                             message:message
                      preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK"
                                                    style:UIAlertActionStyleDefault
                                                  handler:nil];

        [alert addAction:ok];

        [root presentViewController:alert animated:YES completion:nil];
    });
}

// Hooked objc_msgSend
void *hook_objc_msgSend(id self, SEL _cmd, ...) {
    const char *className = class_getName(object_getClass(self));
    const char *selectorName = sel_getName(_cmd);

    // Filter to reduce spam (IMPORTANT)
    if (strstr(selectorName, "viewDidLoad") ||
        strstr(selectorName, "didFinishLaunching") ||
        strstr(selectorName, "Tapped") ||
        strstr(selectorName, "Pressed")) {

        NSString *msg = [NSString stringWithFormat:@"%s -> %s",
                         className, selectorName];

        showAlert(@"Hook Hit", msg);
    }

    return orig_objc_msgSend(self, _cmd);
}

// Constructor runs when dylib loads
__attribute__((constructor))
static void init() {
    void *handle = dlopen("/usr/lib/libobjc.A.dylib", RTLD_NOW);
    void *symbol = dlsym(handle, "objc_msgSend");

    orig_objc_msgSend = symbol;

    // Simple inline hook (replace pointer)
    // NOTE: In real cases you may use fishhook / substrate / libhooker
    rebind_symbols((struct rebinding[1]) {{
        "objc_msgSend",
        hook_objc_msgSend,
        (void *)&orig_objc_msgSend
    }}, 1);

    showAlert(@"Injected", @"objc_msgSend hooked");
}
