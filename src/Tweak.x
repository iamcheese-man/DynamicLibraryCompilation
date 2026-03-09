#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ─────────────────────────────────────────────
// UnityAds SDK forward declarations
// ─────────────────────────────────────────────

typedef NS_ENUM(NSInteger, UnityAdsShowCompletionState) {
    kUnityAdsShowCompletionStateSkipped   = 0,
    kUnityAdsShowCompletionStateCompleted = 1,
    kUnityAdsShowCompletionStateError     = 2,
};

typedef NS_ENUM(NSInteger, UnityAdsShowError) {
    kUnityAdsShowErrorNotInitialized   = 0,
    kUnityAdsShowErrorNotReady         = 1,
    kUnityAdsShowErrorVideoPlayerError = 2,
    kUnityAdsShowErrorInvalidArgument  = 3,
    kUnityAdsShowErrorNoConnection     = 4,
    kUnityAdsShowErrorAlreadyShowing   = 5,
    kUnityAdsShowErrorInternalError    = 6,
    kUnityAdsShowErrorTimeout          = 7,
};

@protocol UnityAdsShowDelegate <NSObject>
- (void)unityAdsShowStart:(NSString *)placementId;
- (void)unityAdsShowClick:(NSString *)placementId;
- (void)unityAdsShowComplete:(NSString *)placementId withCompletionState:(UnityAdsShowCompletionState)state;
- (void)unityAdsShowFailed:(NSString *)placementId withError:(UnityAdsShowError)error withMessage:(NSString *)message;
@end

@interface UnityAds : NSObject
+ (void)show:(UIViewController *)viewController 
 placementId:(NSString *)placementId 
withShowDelegate:(id<UnityAdsShowDelegate>)showDelegate;
@end

// ─────────────────────────────────────────────
// Hook UnityAds show — fire completion instantly
// ─────────────────────────────────────────────

%hook UnityAds

+ (void)show:(UIViewController *)viewController
 placementId:(NSString *)placementId
withShowDelegate:(id<UnityAdsShowDelegate>)showDelegate {

    NSLog(@"[AdSkip] Intercepted Unity Ad for placement: %@", placementId);

    // Tell the delegate the ad started (some games check this)
    if ([showDelegate respondsToSelector:@selector(unityAdsShowStart:)]) {
        [showDelegate unityAdsShowStart:placementId];
    }

    // Immediately fire completion as COMPLETED so rewards are granted
    if ([showDelegate respondsToSelector:@selector(unityAdsShowComplete:withCompletionState:)]) {
        [showDelegate unityAdsShowComplete:placementId
                       withCompletionState:kUnityAdsShowCompletionStateCompleted];
    }

    // Do NOT call %orig — this prevents the ad from ever loading or showing
}

%end

// ─────────────────────────────────────────────
// Hook UADSBannerView — collapse banner ads
// ─────────────────────────────────────────────

%hook UADSBannerView

- (void)load {
    NSLog(@"[AdSkip] Blocked UADSBannerView load");
    // Don't call %orig — banner never loads
}

- (void)layoutSubviews {
    // Zero out the frame so banner takes no space
    self.frame = CGRectZero;
    self.hidden = YES;
    %orig;
}

%end

// ─────────────────────────────────────────────
// Hook UADSApiAdUnit — catches internal ad unit show calls
// Used by newer Unity Ads SDK versions (4.x+)
// ─────────────────────────────────────────────

%hook UADSApiAdUnit

+ (void)show:(NSString *)adUnitId
      params:(NSDictionary *)params
    resolver:(id)resolver
    rejecter:(id)rejecter {
    NSLog(@"[AdSkip] Intercepted UADSApiAdUnit show: %@", adUnitId);
    if (resolver) {
        resolver(@"COMPLETED");
    }
    // Do NOT call %orig
}

%end

// ─────────────────────────────────────────────
// Hook USRVWebViewApp — blocks web-based ad views
// Catches fullscreen HTML ads rendered in a webview
// ─────────────────────────────────────────────

%hook USRVWebViewApp

- (void)invokeMethod:(NSString *)methodName
           className:(NSString *)className
           callback:(NSString *)callback
           params:(NSArray *)params {

    // Intercept the "show" invocation for ad units
    if ([methodName isEqualToString:@"show"] || 
        [methodName isEqualToString:@"initAdUnit"]) {
        NSLog(@"[AdSkip] Blocked WebViewApp invoke: %@ on %@", methodName, className);
        return;
    }
    %orig;
}

%end

// ─────────────────────────────────────────────
// Constructor — confirm tweak loaded
// ─────────────────────────────────────────────

%ctor {
    NSLog(@"[AdSkip] Unity Ad Skip dylib loaded successfully");
}
