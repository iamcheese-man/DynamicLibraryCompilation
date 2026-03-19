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

@protocol GADFullScreenContentDelegate <NSObject>
@optional
- (void)adDidPresentFullScreenContent:(id)ad;
- (void)ad:(id)ad didFailToPresentFullScreenContentWithError:(NSError *)error;
- (void)adWillDismissFullScreenContent:(id)ad;
- (void)adDidDismissFullScreenContent:(id)ad;
@end

static BOOL hooksInstalled = NO;

static void FireUnityAdsComplete(NSString *placementId, id<UnityAdsShowDelegate> delegate) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([delegate respondsToSelector:@selector(unityAdsShowStart:)]) {
            [delegate unityAdsShowStart:placementId];
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([delegate respondsToSelector:@selector(unityAdsShowComplete:withFinish:)]) {
                [delegate unityAdsShowComplete:placementId withFinish:kUnityShowCompletionStateCompleted];
            }
            NSLog(@"[ToSAdBypass] Unity Ads: fired Completed for placement: %@", placementId);
        });
    });
}

static void InstallHooks(void) {
    if (hooksInstalled) return;

    BOOL anyInstalled = NO;

    // 1. Unity Ads 4.x
    Class UAClass = NSClassFromString(@"UnityAds");
    if (UAClass) {
        SEL showSel = NSSelectorFromString(@"show:placementId:showDelegate:");
        Method m1 = class_getClassMethod(UAClass, showSel);
        if (m1) {
            method_setImplementation(m1, imp_implementationWithBlock(
                ^(id self, UIViewController *vc, NSString *placementId, id<UnityAdsShowDelegate> delegate) {
                    NSLog(@"[ToSAdBypass] Intercepted show:placementId:showDelegate: (%@)", placementId);
                    FireUnityAdsComplete(placementId, delegate);
                }
            ));
            anyInstalled = YES;
        }

        SEL showOptSel = NSSelectorFromString(@"show:placementId:options:showDelegate:");
        Method m2 = class_getClassMethod(UAClass, showOptSel);
        if (m2) {
            method_setImplementation(m2, imp_implementationWithBlock(
                ^(id self, UIViewController *vc, NSString *placementId, id options, id<UnityAdsShowDelegate> delegate) {
                    NSLog(@"[ToSAdBypass] Intercepted show:placementId:options:showDelegate: (%@)", placementId);
                    FireUnityAdsComplete(placementId, delegate);
                }
            ));
            anyInstalled = YES;
        }

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
        }

        NSLog(@"[ToSAdBypass] Unity Ads hooks installed");
    }

    // 2. Google Mobile Ads
    Class GADClass = NSClassFromString(@"GADRewardedAd");
    if (GADClass) {
        SEL presentSel = NSSelectorFromString(@"presentFromRootViewController:userDidEarnRewardHandler:");
        Method gm = class_getInstanceMethod(GADClass, presentSel);
        if (gm) {
            method_setImplementation(gm, imp_implementationWithBlock(
                ^(id self, UIViewController *vc, dispatch_block_t rewardHandler) {
                    NSLog(@"[ToSAdBypass] Intercepted GADRewardedAd present");
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (rewardHandler) {
                            rewardHandler();
                        }
                        id<GADFullScreenContentDelegate> fsDelegate = nil;
                        SEL fsSel = NSSelectorFromString(@"fullScreenContentDelegate");
                        if ([self respondsToSelector:fsSel]) {
                            fsDelegate = ((id(*)(id,SEL))objc_msgSend)(self, fsSel);
                        }
                        if ([fsDelegate respondsToSelector:@selector(adDidDismissFullScreenContent:)]) {
                            [fsDelegate adDidDismissFullScreenContent:self];
                        }
                        NSLog(@"[ToSAdBypass] GADRewardedAd: fired reward handler");
                    });
                }
            ));
            anyInstalled = YES;
        }
        NSLog(@"[ToSAdBypass] GAD hooks installed");
    }

    // 3. GMARewardedAdDelegateProxy
    Class GMAProxyClass = NSClassFromString(@"GMARewardedAdDelegateProxy");
    if (GMAProxyClass) {
        SEL onCompleteSel = NSSelectorFromString(@"onAdComplete:network:rewarded:");
        Method pm = class_getInstanceMethod(GMAProxyClass, onCompleteSel);
        if (pm) {
            IMP origOnComplete = method_getImplementation(pm);
            method_setImplementation(pm, imp_implementationWithBlock(
                ^(id self, id meta, NSString *network, BOOL rewarded) {
                    NSLog(@"[ToSAdBypass] GMARewardedAdDelegateProxy forcing rewarded=YES");
                    ((void(*)(id,SEL,id,NSString*,BOOL))origOnComplete)(self, onCompleteSel, meta, network, YES);
                }
            ));
            anyInstalled = YES;
        }
        NSLog(@"[ToSAdBypass] GMA proxy hook installed");
    }

    if (anyInstalled) {
        hooksInstalled = YES;
        NSLog(@"[ToSAdBypass] All hooks installed successfully");
    }
}

__attribute__((constructor))
static void ToSAdBypassInit(void) {
    NSLog(@"[ToSAdBypass] Constructor fired, waiting for Unity to load...");

    __block int attempts = 0;
    __block void (^tryHook)(void);
    tryHook = ^{
        Class UAClass = NSClassFromString(@"UnityAds");
        Class GADClass = NSClassFromString(@"GADRewardedAd");
        if (UAClass && GADClass) {
            InstallHooks();
        } else if (attempts < 60) {
            attempts++;
            NSLog(@"[ToSAdBypass] Classes not ready yet, attempt %d...", attempts);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), tryHook);
        } else {
            NSLog(@"[ToSAdBypass] Giving up after 60 attempts - UAClass=%d GADClass=%d",
                UAClass != nil, GADClass != nil);
        }
    };

    dispatch_async(dispatch_get_main_queue(), tryHook);
}
