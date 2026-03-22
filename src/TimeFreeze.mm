#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#define VALID_KEY @"FREE_5d8403dc1e33a0c250703d170b9ed6fc"
static time_t FROZEN_TIME = 1774243410;


// =====================
// DYLD_INTERPOSE MACRO
// =====================
#ifndef DYLD_INTERPOSE
#define DYLD_INTERPOSE(_replacement, _replacee) \
    __attribute__((used)) static struct { const void *replacement; const void *replacee; } \
    _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = \
    { (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee };
#endif

// =====================
// 1. CLOCK FREEZE
// =====================
static int my_gettimeofday(struct timeval *tv, struct timezone *tz) {
    if (tv) { tv->tv_sec = FROZEN_TIME; tv->tv_usec = 0; }
    return 0;
}

static int my_clock_gettime(clockid_t clk, struct timespec *ts) {
    if (ts) { ts->tv_sec = FROZEN_TIME; ts->tv_nsec = 0; }
    return 0;
}

static time_t my_time(time_t *t) {
    if (t) *t = FROZEN_TIME;
    return FROZEN_TIME;
}

DYLD_INTERPOSE(my_gettimeofday, gettimeofday)
DYLD_INTERPOSE(my_clock_gettime, clock_gettime)
DYLD_INTERPOSE(my_time, time)

// =====================
// 2. BLOCK SecItemDelete FOR GLOOP
// =====================
static OSStatus my_SecItemDelete(CFDictionaryRef query) {
    NSDictionary *dict = (__bridge NSDictionary *)query;
    NSString *service = dict[(__bridge id)kSecAttrService];
    if (service && [service containsString:@"gloop"])
        return errSecSuccess;
    return SecItemDelete(query);
}

DYLD_INTERPOSE(my_SecItemDelete, SecItemDelete)

// =====================
// 3. CONTINUOUS LICENSE FILE WATCHER (every 500ms)
// =====================
static void startLicenseWatcher(void) {
    NSString *home = NSHomeDirectory();
    NSString *deltaDir = [home stringByAppendingPathComponent:@"Library/Delta/Cache"];
    NSString *licenseFile = [deltaDir stringByAppendingPathComponent:@"license"];
    NSString *validKey = VALID_KEY;

    dispatch_queue_t queue = dispatch_queue_create("com.delta.licensewatcher", DISPATCH_QUEUE_SERIAL);
    dispatch_async(queue, ^{
        while (1) {
            NSFileManager *fm = [NSFileManager defaultManager];
            if (![fm fileExistsAtPath:deltaDir])
                [fm createDirectoryAtPath:deltaDir withIntermediateDirectories:YES attributes:nil error:nil];

            NSString *existing = [NSString stringWithContentsOfFile:licenseFile encoding:NSUTF8StringEncoding error:nil];
            if (!existing || ![existing hasPrefix:@"FREE_"])
                [validKey writeToFile:licenseFile atomically:YES encoding:NSUTF8StringEncoding error:nil];

            usleep(500000);
        }
    });
}

// =====================
// CONSTRUCTOR
// =====================
__attribute__((constructor))
static void init(void) {
    startLicenseWatcher();
}
