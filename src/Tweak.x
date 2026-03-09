#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

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

// UADSBannerView inherits UIView so frame/hidden are available
@interface UADSBannerView : UIView
- (void)load;
@end

// ─────────────────────────────────────────────
// Hook UnityAds show — fire completion instantly
// ─────────────────────────────────────────────

%hook UnityAds

+ (void)show:(UIViewController *)viewController
 placementId:(NSString *)placementId
withShowDelegate:(id<UnityAdsShowDelegate>)showDelegate {
    NSLog(@"[AdSkip] Intercepted Unity Ad: %@", placementId);
    if ([showDelegate respondsToSelector:@selector(unityAdsShowStart:)])
        [showDelegate unityAdsShowStart:placementId];
    if ([showDelegate respondsToSelector:@selector(unityAdsShowComplete:withCompletionState:)])
        [showDelegate unityAdsShowComplete:placementId
                       withCompletionState:kUnityAdsShowCompletionStateCompleted];
}

%end

// ─────────────────────────────────────────────
// Hook UADSBannerView — collapse banner ads
// ─────────────────────────────────────────────

%hook UADSBannerView

- (void)load {
    NSLog(@"[AdSkip] Blocked UADSBannerView load");
}

- (void)layoutSubviews {
    self.frame  = CGRectMake(0, 0, 0, 0);
    self.hidden = YES;
    %orig;
}

%end

// ─────────────────────────────────────────────
// Hook UADSApiAdUnit — Unity Ads 4.x+
// resolver is a block, not a function pointer
// ─────────────────────────────────────────────

%hook UADSApiAdUnit

+ (void)show:(NSString *)adUnitId
      params:(NSDictionary *)params
    resolver:(void (^)(id))resolver
    rejecter:(void (^)(NSString *, NSString *, NSError *))rejecter {
    NSLog(@"[AdSkip] Intercepted UADSApiAdUnit show: %@", adUnitId);
    if (resolver) resolver(@"COMPLETED");
}

%end

// ─────────────────────────────────────────────
// Hook USRVWebViewApp — block HTML ad views
// ─────────────────────────────────────────────

%hook USRVWebViewApp

- (void)invokeMethod:(NSString *)methodName
           className:(NSString *)className
            callback:(NSString *)callback
              params:(NSArray *)params {
    if ([methodName isEqualToString:@"show"] ||
        [methodName isEqualToString:@"initAdUnit"]) {
        NSLog(@"[AdSkip] Blocked WebViewApp: %@ on %@", methodName, className);
        return;
    }
    %orig;
}

%end

%ctor {
    NSLog(@"[AdSkip] Unity Ad Skip loaded");
}
