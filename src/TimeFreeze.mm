#include <sys/time.h>
#include <time.h>

static time_t FROZEN_TIME = 1774147680;

static int my_gettimeofday(struct timeval *tv, struct timezone *tz) {
    if (tv) {
        tv->tv_sec = FROZEN_TIME;
        tv->tv_usec = 0;
    }
    return 0;
}

static int my_clock_gettime(clockid_t clk, struct timespec *ts) {
    if (ts) {
        ts->tv_sec = FROZEN_TIME;
        ts->tv_nsec = 0;
    }
    return 0;
}

static time_t my_time(time_t *t) {
    if (t) *t = FROZEN_TIME;
    return FROZEN_TIME;
}

#ifndef DYLD_INTERPOSE
#define DYLD_INTERPOSE(_replacement, _replacee) \
    __attribute__((used)) static struct { const void *replacement; const void *replacee; } \
    _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = \
    { (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee };
#endif

DYLD_INTERPOSE(my_gettimeofday, gettimeofday)
DYLD_INTERPOSE(my_clock_gettime, clock_gettime)
DYLD_INTERPOSE(my_time, time)
