// ToSAdBypass.mm
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

typedef NS_ENUM(NSInteger, UnityAdsFinishState) {
    kUnityShowCompletionStateError     = 0,
    kUnityShowCompletionStateSkipped   = 1,
    kUnityShowCompletionStateCompleted = 2,
};

@protocol UnityAdsLoadDelegate <NSObject>
@optional
- (void)unityAdsAdLoaded:(NSString *)placementId;
@end

typedef void (*PresentVCIMP)(id, SEL, UIViewController *, BOOL, void(^)(void));
static PresentVCIMP orig_presentVC = NULL;

static void InstallUnityHooks(void) {
    // ---------------------------------------------------------------
    // CORE HOOK: USRVApiSdk sendShowCompleteEvent:listenerID:state:
    // This is what actually signals IL2CPP that the ad finished.
    // Force state to kUnityShowCompletionStateCompleted (2) always.
    // ---------------------------------------------------------------
    Class sdkClass = NSClassFromString(@"USRVApiSdk");
    if (sdkClass) {
        SEL completeSel = NSSelectorFromString(@"sendShowCompleteEvent:listenerID:state:");
        Method cm = class_getClassMethod(sdkClass, completeSel);
        if (cm) {
            IMP origComplete = method_getImplementation(cm);
            method_setImplementation(cm, imp_implementationWithBlock(
                ^(id self, NSString *placementId, NSString *listenerID, NSInteger state) {
                    // Always send Completed regardless of actual state
                    ((void(*)(id,SEL,NSString*,NSString*,NSInteger))origComplete)(
                        self, completeSel, placementId, listenerID, kUnityShowCompletionStateCompleted);
                }
            ));
        }

        // Also hook sendShowStartEvent so the flow looks normal
        SEL startSel = NSSelectorFromString(@"sendShowStartEvent:listenerID:");
        Method sm = class_getClassMethod(sdkClass, startSel);
        if (sm) {
            // Let this one through untouched — just confirm it exists
        }
    }

    // ---------------------------------------------------------------
    // SECONDARY HOOK: UADSApiAdUnit sendShowCompleteEvent (older path)
    // ---------------------------------------------------------------
    Class adUnitClass = NSClassFromString(@"UADSApiAdUnit");
    if (adUnitClass) {
        SEL completeSel2 = NSSelectorFromString(@"sendShowCompleteEvent:listenerID:state:");
        Method cm2 = class_getClassMethod(adUnitClass, completeSel2);
        if (cm2) {
            IMP origComplete2 = method_getImplementation(cm2);
            method_setImplementation(cm2, imp_implementationWithBlock(
                ^(id self, NSString *placementId, NSString *listenerID, NSInteger state) {
                    ((void(*)(id,SEL,NSString*,NSString*,NSInteger))origComplete2)(
                        self, completeSel2, placementId, listenerID, kUnityShowCompletionStateCompleted);
                }
            ));
        }
    }

    // ---------------------------------------------------------------
    // GMARewardedAdDelegateProxy: onAdComplete:network:rewarded:
    // Force rewarded=YES for AdMob path
    // ---------------------------------------------------------------
    Class gmaClass = NSClassFromString(@"GMARewardedAdDelegateProxy");
    if (gmaClass) {
        SEL onCompleteSel = NSSelectorFromString(@"onAdComplete:network:rewarded:");
        Method pm = class_getInstanceMethod(gmaClass, onCompleteSel);
        if (pm) {
            IMP origOnComplete = method_getImplementation(pm);
            method_setImplementation(pm, imp_implementationWithBlock(
                ^(id self, id meta, NSString *network, BOOL rewarded) {
                    ((void(*)(id,SEL,id,NSString*,BOOL))origOnComplete)(
                        self, onCompleteSel, meta, network, YES);
                }
            ));
        }
    }

    // ---------------------------------------------------------------
    // Fake load so isReady passes without real network fetch
    // ---------------------------------------------------------------
    Class UAClass = NSClassFromString(@"UnityAds");
    if (UAClass) {
        SEL loadSel = NSSelectorFromString(@"load:loadDelegate:");
        Method lm = class_getClassMethod(UAClass, loadSel);
        if (lm) {
            method_setImplementation(lm, imp_implementationWithBlock(
                ^(id self, NSString *placementId, id<UnityAdsLoadDelegate> loadDelegate) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([loadDelegate respondsToSelector:@selector(unityAdsAdLoaded:)])
                            [loadDelegate unityAdsAdLoaded:placementId];
                    });
                }
            ));
        }

        SEL loadOptSel = NSSelectorFromString(@"load:options:loadDelegate:");
        Method lm2 = class_getClassMethod(UAClass, loadOptSel);
        if (lm2) {
            method_setImplementation(lm2, imp_implementationWithBlock(
                ^(id self, NSString *placementId, id opts, id<UnityAdsLoadDelegate> loadDelegate) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([loadDelegate respondsToSelector:@selector(unityAdsAdLoaded:)])
                            [loadDelegate unityAdsAdLoaded:placementId];
                    });
                }
            ));
        }
    }
}

// Dismiss any ad VC that gets presented — so the ad UI doesn't appear
static void hooked_presentVC(id self, SEL _cmd, UIViewController *vc, BOOL animated, void(^completion)(void)) {
    NSString *cn = NSStringFromClass([vc class]);
    if ([cn containsString:@"Unity"] ||
        [cn containsString:@"UADS"] ||
        [cn containsString:@"USRV"] ||
        [cn containsString:@"GADFull"] ||
        [cn containsString:@"GMAFull"]) {
        // Dismiss instantly, let the complete event fire from the hook above
        if (completion) completion();
        return;
    }
    orig_presentVC(self, _cmd, vc, animated, completion);
}

__attribute__((constructor))
static void ToSAdBypassInit(void) {
    // UIViewController hook — always available immediately
    Method pm = class_getInstanceMethod([UIViewController class],
        @selector(presentViewController:animated:completion:));
    orig_presentVC = (PresentVCIMP)method_getImplementation(pm);
    method_setImplementation(pm, (IMP)hooked_presentVC);

    // Retry until USRVApiSdk is available
    __block int attempts = 0;
    __block void (^tryHook)(void);
    tryHook = ^{
        if (NSClassFromString(@"USRVApiSdk") || NSClassFromString(@"UnityAds")) {
            InstallUnityHooks();
        } else if (attempts < 60) {
            attempts++;
            void (^captured)(void) = tryHook;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), captured);
        }
    };
    dispatch_async(dispatch_get_main_queue(), tryHook);
}
