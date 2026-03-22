#import <Foundation/Foundation.h>
#import <Security/Security.h>

#define VALID_KEY @"FREE_8661126ab66c0fcf8021213aaf0b0177"

static void restoreLicense(void) {
    NSString *home = NSHomeDirectory();
    NSString *deltaDir = [home stringByAppendingPathComponent:@"Library/Delta/Cache"];
    NSString *licenseFile = [deltaDir stringByAppendingPathComponent:@"license"];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:deltaDir])
        [fm createDirectoryAtPath:deltaDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *existing = [NSString stringWithContentsOfFile:licenseFile encoding:NSUTF8StringEncoding error:nil];
    if (!existing || ![existing hasPrefix:@"FREE_"])
        [VALID_KEY writeToFile:licenseFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

#ifndef DYLD_INTERPOSE
#define DYLD_INTERPOSE(_replacement, _replacee) \
    __attribute__((used)) static struct { const void *replacement; const void *replacee; } \
    _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = \
    { (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee };
#endif

static OSStatus my_SecItemDelete(CFDictionaryRef query) {
    NSDictionary *dict = (__bridge NSDictionary *)query;
    NSString *service = dict[(__bridge id)kSecAttrService];
    if (service && [service containsString:@"gloop"])
        return errSecSuccess;
    return SecItemDelete(query);
}

DYLD_INTERPOSE(my_SecItemDelete, SecItemDelete)

__attribute__((constructor))
static void init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        restoreLicense();
    });
}
