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

typedef void (*PresentVCIMP)(id, SEL, UIViewController *, BOOL, void(^)(void));
typedef void (*SetNavDelegateIMP)(id, SEL, id);

static PresentVCIMP orig_presentVC = NULL;
static SetNavDelegateIMP orig_setNavDelegate = NULL;

static id gLastShowDelegate = nil;
static NSString *gLastPlacementId = nil;
static NSMutableArray *gNavDelegates = nil;

static void FireComplete(void) {
    id delegate = gLastShowDelegate;
    NSString *placement = gLastPlacementId;
    if (!delegate || !placement) return;
    gLastShowDelegate = nil;
    gLastPlacementId = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([delegate respondsToSelector:@selector(unityAdsShowStart:)])
            ((void(*)(id,SEL,NSString*))objc_msgSend)(delegate, @selector(unityAdsShowStart:), placement);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([delegate respondsToSelector:@selector(unityAdsShowComplete:withFinish:)])
                ((void(*)(id,SEL,NSString*,NSInteger))objc_msgSend)(delegate,
                    @selector(unityAdsShowComplete:withFinish:), placement, 2);
        });
    });
}

static void DismissTopVC(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
#pragma clang diagnostic pop
        UIViewController *top = root;
        while (top.presentedViewController) top = top.presentedViewController;
        if (top != root) {
            [top dismissViewControllerAnimated:NO completion:nil];
        }
    });
}

static BOOL IsAdHost(NSString *host) {
    if (!host) return NO;
    return [host containsString:@"unity3d.com"] ||
           [host containsString:@"googlesyndication.com"] ||
           [host containsString:@"doubleclick.net"] ||
           [host containsString:@"googleadservices.com"] ||
           [host containsString:@"unityads.unity3d.com"] ||
           [host containsString:@"webview.unity3d.com"];
}

@interface ToSNavDelegate : NSObject <WKNavigationDelegate>
@property (nonatomic, weak) id<WKNavigationDelegate> original;
@end

@implementation ToSNavDelegate

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    if (IsAdHost(webView.URL.host)) {
        [webView stopLoading];
        if (gLastShowDelegate) FireComplete();
        else DismissTopVC();
        return;
    }
    if ([self.original respondsToSelector:@selector(webView:didStartProvisionalNavigation:)])
        [self.original webView:webView didStartProvisionalNavigation:navigation];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (IsAdHost(navigationAction.request.URL.host)) {
        decisionHandler(WKNavigationActionPolicyCancel);
        if (gLastShowDelegate) FireComplete();
        else DismissTopVC();
        return;
    }
    if ([self.original respondsToSelector:@selector(webView:decidePolicyForNavigationAction:decisionHandler:)])
        [self.original webView:webView decidePolicyForNavigationAction:navigationAction decisionHandler:decisionHandler];
    else
        decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    if ([self.original respondsToSelector:invocation.selector])
        [invocation invokeWithTarget:self.original];
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    return [super respondsToSelector:aSelector] || [self.original respondsToSelector:aSelector];
}

@end

static void hooked_setNavDelegate(WKWebView *self, SEL _cmd, id<WKNavigationDelegate> delegate) {
    if (delegate) {
        ToSNavDelegate *spy = [[ToSNavDelegate alloc] init];
        spy.original = delegate;
        [gNavDelegates addObject:spy];
        orig_setNavDelegate(self, _cmd, spy);
    } else {
        orig_setNavDelegate(self, _cmd, delegate);
    }
}

static void hooked_presentVC(id self, SEL _cmd, UIViewController *vc, BOOL animated, void(^completion)(void)) {
    NSString *cn = NSStringFromClass([vc class]);
    if ([cn containsString:@"UnityAds"] ||
        [cn containsString:@"UADS"] ||
        [cn containsString:@"GADFullScreen"] ||
        [cn containsString:@"GMAFullScreen"]) {
        if (completion) completion();
        if (gLastShowDelegate) FireComplete();
        else DismissTopVC();
        return;
    }
    orig_presentVC(self, _cmd, vc, animated, completion);
}

static void InstallUnityHooks(void) {
    Class UAClass = NSClassFromString(@"UnityAds");
    if (!UAClass) return;

    SEL showSel = NSSelectorFromString(@"show:placementId:showDelegate:");
    Method sm = class_getClassMethod(UAClass, showSel);
    if (sm) {
        IMP origShow = method_getImplementation(sm);
        method_setImplementation(sm, imp_implementationWithBlock(
            ^(id self, UIViewController *vc, NSString *placementId, id<UnityAdsShowDelegate> delegate) {
                gLastShowDelegate = delegate;
                gLastPlacementId = placementId;
                ((void(*)(id,SEL,UIViewController*,NSString*,id))origShow)(self, showSel, vc, placementId, delegate);
            }
        ));
    }

    SEL showOptSel = NSSelectorFromString(@"show:placementId:options:showDelegate:");
    Method sm2 = class_getClassMethod(UAClass, showOptSel);
    if (sm2) {
        IMP origShow2 = method_getImplementation(sm2);
        method_setImplementation(sm2, imp_implementationWithBlock(
            ^(id self, UIViewController *vc, NSString *placementId, id opts, id<UnityAdsShowDelegate> delegate) {
                gLastShowDelegate = delegate;
                gLastPlacementId = placementId;
                ((void(*)(id,SEL,UIViewController*,NSString*,id,id))origShow2)(self, showOptSel, vc, placementId, opts, delegate);
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

__attribute__((constructor))
static void ToSAdBypassInit(void) {
    gNavDelegates = [NSMutableArray array];

    Class wkClass = NSClassFromString(@"WKWebView");
    if (wkClass) {
        Method m = class_getInstanceMethod(wkClass, @selector(setNavigationDelegate:));
        if (m) {
            orig_setNavDelegate = (SetNavDelegateIMP)method_getImplementation(m);
            method_setImplementation(m, (IMP)hooked_setNavDelegate);
        }
    }

    Method pm = class_getInstanceMethod([UIViewController class],
        @selector(presentViewController:animated:completion:));
    orig_presentVC = (PresentVCIMP)method_getImplementation(pm);
    method_setImplementation(pm, (IMP)hooked_presentVC);

    __block int attempts = 0;
    __block void (^tryHook)(void);
    tryHook = ^{
        if (NSClassFromString(@"UnityAds")) {
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
