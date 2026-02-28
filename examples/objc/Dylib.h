// Example Objective-C Dylib Header
// MyDylib.h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface MyDylib : NSObject

+ (instancetype)sharedInstance;
- (void)sayHello;
- (void)showAlert;

@end

// Global function
void dylibLoaded(void);
