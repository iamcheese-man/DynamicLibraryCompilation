// ToSAdBypass.mm
// Hooks both Unity Ads 4.4.2 and Google Mobile Ads rewarded ads in Town of Salem
// Suppresses ad display, immediately fires completion callbacks with “reward earned”
// Inject via TweakLoader inside LiveContainer

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - Unity Ads types

typedef NS_ENUM(NSInteger, UnityAdsFinishState) {
kUnityShowCompletionStateError     = 0,
kUnityShowCompletionStateSkipped   = 1,
kUnityShowCompletionStateCompleted = 2,
};

typedef NS_ENUM(NSInteger, UnityAdsShowError) {
kUnityShowErrorNotInitialized   = 0,
kUnityShowErrorNotReady         = 1,
kUnityShowErrorVideoPlayerError = 2,
kUnityShowErrorInvalidArgument  = 3,
kUnityShowErrorNoConnection     = 4,
kUnityShowErrorAlreadyShowing   = 5,
kUnityShowErrorInternalError    = 6,
};

@protocol UnityAdsShowDelegate <NSObject>
@optional

- (void)unityAdsShowComplete:(NSString *)placementId withFinish:(UnityAdsFinishState)state;
- (void)unityAdsShowFailed:(NSString *)placementId withError:(UnityAdsShowError)error withMessage:(NSString *)message;
- (void)unityAdsShowStart:(NSString *)placementId;
- (void)unityAdsShowClick:(NSString *)placementId;
  @end

@protocol UnityAdsLoadDelegate <NSObject>
@optional

- (void)unityAdsAdLoaded:(NSString *)placementId;
- (void)unityAdsAdFailedToLoad:(NSString *)placementId withError:(NSInteger)error withMessage:(NSString *)message;
  @end

#pragma mark - GAD types (AdMob)

@protocol GADUserDidEarnRewardHandler
@end

@interface GADAdReward : NSObject
@property(nonatomic, copy) NSString *type;
@property(nonatomic, copy) NSDecimalNumber *amount;
@end

@protocol GADFullScreenContentDelegate <NSObject>
@optional

- (void)adDidPresentFullScreenContent:(id)ad;
- (void)ad:(id)ad didFailToPresentFullScreenContentWithError:(NSError *)error;
- (void)adWillDismissFullScreenContent:(id)ad;
- (void)adDidDismissFullScreenContent:(id)ad;
  @end

#pragma mark - Helpers

static void FireUnityAdsComplete(NSString *placementId, id<UnityAdsShowDelegate> delegate) {
dispatch_async(dispatch_get_main_queue(), ^{
if ([delegate respondsToSelector:@selector(unityAdsShowStart:)]) {
[delegate unityAdsShowStart:placementId];
}
// Small delay to mimic real ad duration (prevents instant-grant detection)
dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
if ([delegate respondsToSelector:@selector(unityAdsShowComplete:withFinish:)]) {
[delegate unityAdsShowComplete:placementId
withFinish:kUnityShowCompletionStateCompleted];
}
NSLog(@”[ToSAdBypass] Unity Ads: fired Completed for placement: %@”, placementId);
});
});
}

#pragma mark - Init

__attribute__((constructor))
static void ToSAdBypassInit(void) {
NSLog(@”[ToSAdBypass] Initializing…”);

// ----------------------------------------------------------------
// 1. Unity Ads 4.x — show:placementId:showDelegate:
// ----------------------------------------------------------------
Class UAClass = NSClassFromString(@"UnityAds");
if (UAClass) {
    // Primary: show:placementId:showDelegate:
    SEL showSel = NSSelectorFromString(@"show:placementId:showDelegate:");
    Method m1 = class_getClassMethod(UAClass, showSel);
    if (m1) {
        method_setImplementation(m1, imp_implementationWithBlock(
            ^(id self, UIViewController *vc, NSString *placementId, id<UnityAdsShowDelegate> delegate) {
                NSLog(@"[ToSAdBypass] Intercepted show:placementId:showDelegate: (%@)", placementId);
                FireUnityAdsComplete(placementId, delegate);
            }
        ));
        NSLog(@"[ToSAdBypass] Hooked show:placementId:showDelegate:");
    }

    // Secondary: show:placementId:options:showDelegate: (4.x with options)
    SEL showOptSel = NSSelectorFromString(@"show:placementId:options:showDelegate:");
    Method m2 = class_getClassMethod(UAClass, showOptSel);
    if (m2) {
        method_setImplementation(m2, imp_implementationWithBlock(
            ^(id self, UIViewController *vc, NSString *placementId, id options, id<UnityAdsShowDelegate> delegate) {
                NSLog(@"[ToSAdBypass] Intercepted show:placementId:options:showDelegate: (%@)", placementId);
                FireUnityAdsComplete(placementId, delegate);
            }
        ));
        NSLog(@"[ToSAdBypass] Hooked show:placementId:options:showDelegate:");
    }

    // Block load — prevent network requests to Unity Ads servers
    // But fire the loaded callback so the game's isReady check passes
    SEL loadSel = NSSelectorFromString(@"load:loadDelegate:");
    Method m3 = class_getClassMethod(UAClass, loadSel);
    if (m3) {
        method_setImplementation(m3, imp_implementationWithBlock(
            ^(id self, NSString *placementId, id<UnityAdsLoadDelegate> loadDelegate) {
                NSLog(@"[ToSAdBypass] Intercepted load:loadDelegate: (%@)", placementId);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([loadDelegate respondsToSelector:@selector(unityAdsAdLoaded:)]) {
                        [loadDelegate unityAdsAdLoaded:placementId];
                    }
                });
            }
        ));
        NSLog(@"[ToSAdBypass] Hooked load:loadDelegate:");
    }

    SEL loadOptSel = NSSelectorFromString(@"load:options:loadDelegate:");
    Method m4 = class_getClassMethod(UAClass, loadOptSel);
    if (m4) {
        method_setImplementation(m4, imp_implementationWithBlock(
            ^(id self, NSString *placementId, id options, id<UnityAdsLoadDelegate> loadDelegate) {
                NSLog(@"[ToSAdBypass] Intercepted load:options:loadDelegate: (%@)", placementId);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([loadDelegate respondsToSelector:@selector(unityAdsAdLoaded:)]) {
                        [loadDelegate unityAdsAdLoaded:placementId];
                    }
                });
            }
        ));
        NSLog(@"[ToSAdBypass] Hooked load:options:loadDelegate:");
    }
} else {
    NSLog(@"[ToSAdBypass] UnityAds class not found");
}

// ----------------------------------------------------------------
// 2. Google Mobile Ads (AdMob) — GADRewardedAd
//    presentFromRootViewController:userDidEarnRewardHandler:
//    This fires the userDidEarnRewardHandler block immediately
//    then calls adDidDismissFullScreenContent on the delegate
// ----------------------------------------------------------------
Class GADClass = NSClassFromString(@"GADRewardedAd");
if (GADClass) {
    SEL presentSel = NSSelectorFromString(@"presentFromRootViewController:userDidEarnRewardHandler:");
    Method gm = class_getInstanceMethod(GADClass, presentSel);
    if (gm) {
        method_setImplementation(gm, imp_implementationWithBlock(
            ^(id self, UIViewController *vc, dispatch_block_t rewardHandler) {
                NSLog(@"[ToSAdBypass] Intercepted GADRewardedAd presentFromRootViewController:userDidEarnRewardHandler:");
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Fire the reward block — this is what grants the in-game reward
                    if (rewardHandler) {
                        rewardHandler();
                    }
                    // Also notify fullscreen delegate if present
                    id<GADFullScreenContentDelegate> fsDelegate = nil;
                    SEL fsSel = NSSelectorFromString(@"fullScreenContentDelegate");
                    if ([self respondsToSelector:fsSel]) {
                        fsDelegate = ((id(*)(id,SEL))objc_msgSend)(self, fsSel);
                    }
                    if ([fsDelegate respondsToSelector:@selector(adDidDismissFullScreenContent:)]) {
                        [fsDelegate adDidDismissFullScreenContent:self];
                    }
                    NSLog(@"[ToSAdBypass] GADRewardedAd: fired userDidEarnRewardHandler");
                });
            }
        ));
        NSLog(@"[ToSAdBypass] Hooked GADRewardedAd presentFromRootViewController:userDidEarnRewardHandler:");
    }
} else {
    NSLog(@"[ToSAdBypass] GADRewardedAd class not found");
}

// ----------------------------------------------------------------
// 3. GMARewardedAdDelegateProxy — onAdComplete:network:rewarded:
//    This is the Unity-GMA bridge that relays reward back to IL2CPP
//    Hook it to always pass rewarded=YES
// ----------------------------------------------------------------
Class GMAProxyClass = NSClassFromString(@"GMARewardedAdDelegateProxy");
if (GMAProxyClass) {
    SEL onCompleteSel = NSSelectorFromString(@"onAdComplete:network:rewarded:");
    Method pm = class_getInstanceMethod(GMAProxyClass, onCompleteSel);
    if (pm) {
        IMP origOnComplete = method_getImplementation(pm);
        method_setImplementation(pm, imp_implementationWithBlock(
            ^(id self, id meta, NSString *network, BOOL rewarded) {
                NSLog(@"[ToSAdBypass] GMARewardedAdDelegateProxy onAdComplete - forcing rewarded=YES (was %d)", rewarded);
                ((void(*)(id,SEL,id,NSString*,BOOL))origOnComplete)(self, onCompleteSel, meta, network, YES);
            }
        ));
        NSLog(@"[ToSAdBypass] Hooked GMARewardedAdDelegateProxy onAdComplete:network:rewarded:");
    }
}

NSLog(@"[ToSAdBypass] Done.");

}
