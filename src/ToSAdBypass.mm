// ToSAdBypass.mm
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

typedef NS_ENUM(NSInteger, UnityAdsFinishState) {
    kUnityShowCompletionStateError     = 0,
    kUnityShowCompletionStateSkipped   = 1,
    kUnityShowCompletionStateCompleted = 2,
};

@protocol UnityAdsShowDelegate <NSObject>
@optional
- (void)unityAdsShowComplete:(NSString *)placementId withFinish:(UnityAdsFinishState)state;
- (void)unityAdsShowStart:(NSString *)placementId;
@end

@protocol UnityAdsLoadDelegate <NSObject>
@optional
- (void)unityAdsAdLoaded:(NSString *)placementId;
@end

@protocol GADFullScreenContentDelegate <NSObject>
@optional
- (void)adDidDismissFullScreenContent:(id)ad;
@end

// Track the last show delegate and placement so we can fire complete
static id gLastShowDelegate = nil;
static NSString *gLastPlacementId = nil;

static void FireComplete(void) {
    id delegate = gLastShowDelegate;
    NSString *placement = gLastPlacementId;
    if (!delegate || !placement) return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([delegate respondsToSelector:@selector(unityAdsShowStart:)])
            ((void(*)(id,SEL,NSString*))objc_msgSend)(delegate, @selector(unityAdsShowStart:), placement);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([delegate respondsToSelector:@selector(unityAdsShowComplete:withFinish:)])
                ((void(*)(id,SEL,NSString*,NSInteger))objc_msgSend)(delegate,
                    @selector(unityAdsShowComplete:withFinish:), placement, 2);
            gLastShowDelegate = nil;
            gLastPlacementId = nil;
        });
    });
}

static IMP orig_loadRequest = NULL;

// Hook WKWebView loadRequest to intercept Unity Ads webview navigation
static id hooked_loadRequest(WKWebView *self, SEL _cmd, NSURLRequest *request) {
    NSString *host = request.URL.host;
    if ([host containsString:@"unity3d.com"] ||
        [host containsString:@"unityads.unity3d.com"] ||
        [host containsString:@"webview.unity3d.com"] ||
        [host containsString:@"auction.unityads.unity3d.com"] ||
        [host containsString:@"googlesyndication.com"] ||
        [host containsString:@"doubleclick.net"]) {

        // Block the webview from loading, fire reward immediately
        FireComplete();

        // Also fire GAD reward if this webview belongs to a GAD ad
        // Walk up the responder chain to find the ad VC
        UIResponder *responder = self;
        while (responder) {
            NSString *cn = NSStringFromClass([responder class]);
            if ([cn containsString:@"GAD"] || [cn containsString:@"GMA"]) {
                SEL rewardSel = NSSelectorFromString(@"userDidEarnRewardHandler");
                if ([responder respondsToSelector:rewardSel]) {
                    dispatch_block_t handler = ((id(*)(id,SEL))objc_msgSend)(responder, rewardSel);
                    if (handler) handler();
                }
                SEL fsSel = NSSelectorFromString(@"fullScreenContentDelegate");
                if ([responder respondsToSelector:fsSel]) {
                    id fsDel = ((id(*)(id,SEL))objc_msgSend)(responder, fsSel);
                    if ([fsDel respondsToSelector:@selector(adDidDismissFullScreenContent:)])
                        [fsDel adDidDismissFullScreenContent:responder];
                }
                break;
            }
            responder = [responder nextResponder];
        }

        return nil; // Block load
    }

    return orig_loadRequest(self, _cmd, request);
}

static IMP orig_presentVC = NULL;

static void hooked_presentVC(UIViewController *self, SEL _cmd, UIViewController *vc, BOOL animated, void(^completion)(void)) {
    NSString *cn = NSStringFromClass([vc class]);
    if ([cn containsString:@"UnityAds"] ||
        [cn containsString:@"UADS"] ||
        [cn containsString:@"GADFullScreen"] ||
        [cn containsString:@"GMAFullScreen"]) {
        if (completion) completion();
        FireComplete();
        return;
    }
    orig_presentVC(self, _cmd, vc, animated, completion);
}

__attribute__((constructor))
static void ToSAdBypassInit(void) {
    // Hook WKWebView -loadRequest:
    Class wkClass = NSClassFromString(@"WKWebView");
    if (wkClass) {
        Method m = class_getInstanceMethod(wkClass, @selector(loadRequest:));
        if (m) {
            orig_loadRequest = method_getImplementation(m);
            method_setImplementation(m, (IMP)hooked_loadRequest);
        }
    }

    // Hook UIViewController presentation as backup
    Method pm = class_getInstanceMethod([UIViewController class],
        @selector(presentViewController:animated:completion:));
    orig_presentVC = method_getImplementation(pm);
    method_setImplementation(pm, (IMP)hooked_presentVC);

    // Hook Unity Ads show to capture delegate + placement before ad fires
    __block int attempts = 0;
    __block void (^tryHook)(void);
    tryHook = ^{
        Class UAClass = NSClassFromString(@"UnityAds");
        if (UAClass) {
            SEL showSel = NSSelectorFromString(@"show:placementId:showDelegate:");
            Method sm = class_getClassMethod(UAClass, showSel);
            if (sm) {
                method_setImplementation(sm, imp_implementationWithBlock(
                    ^(id self, UIViewController *vc, NSString *placementId, id<UnityAdsShowDelegate> delegate) {
                        gLastShowDelegate = delegate;
                        gLastPlacementId = placementId;
                        // Don't call original — WKWebView hook will fire complete
                        // If webview hook misses for any reason, fire after 1s
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                            dispatch_get_main_queue(), ^{
                            if (gLastShowDelegate) FireComplete();
                        });
                    }
                ));
            }

            SEL showOptSel = NSSelectorFromString(@"show:placementId:options:showDelegate:");
            Method sm2 = class_getClassMethod(UAClass, showOptSel);
            if (sm2) {
                method_setImplementation(sm2, imp_implementationWithBlock(
                    ^(id self, UIViewController *vc, NSString *placementId, id options, id<UnityAdsShowDelegate> delegate) {
                        gLastShowDelegate = delegate;
                        gLastPlacementId = placementId;
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                            dispatch_get_main_queue(), ^{
                            if (gLastShowDelegate) FireComplete();
                        });
                    }
                ));
            }

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
        } else if (attempts < 60) {
            attempts++;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), tryHook);
        }
    };

    dispatch_async(dispatch_get_main_queue(), tryHook);
}
