#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static void (*orig_fetchProfile)(id self, SEL _cmd, id app, void (^completion)(id, NSError *));

static void hook_fetchProfile(id self, SEL _cmd, id app, void (^completion)(id, NSError *)) {
    orig_fetchProfile(self, _cmd, app, ^(id profile, NSError *error) {
        if (profile) {
            NSData *profileData = [profile valueForKey:@"data"];
            if (profileData) {
                NSString *docs = NSSearchPathForDirectoriesInDomains(
                    NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
                NSString *out = [docs stringByAppendingPathComponent:@"embedded.mobileprovision"];
                [profileData writeToFile:out atomically:YES];
                NSLog(@"[MProvDump] Saved to %@", out);
            }
        }
        completion(profile, error);
    });
}

__attribute__((constructor))
static void init() {
    Class cls = NSClassFromString(@"ALTServerManager");
    if (!cls) {
        NSLog(@"[MProvDump] ALTServerManager not found");
        return;
    }
    Method m = class_getInstanceMethod(cls, @selector(fetchProvisioningProfileForApp:completion:));
    if (!m) {
        NSLog(@"[MProvDump] Method not found");
        return;
    }
    orig_fetchProfile = (void (*)(id, SEL, id, void (^)(id, NSError *)))method_getImplementation(m);

    method_setImplementation(m, (IMP)hook_fetchProfile);
    NSLog(@"[MProvDump] Hooked successfully");
}
