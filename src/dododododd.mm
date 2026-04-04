#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

%hook ALTServerManager

- (void)fetchProvisioningProfileForApp:(id)app
                            completion:(void (^)(id, NSError *))completion {
    %orig(app, ^(id profile, NSError *error) {
        if (profile) {
            NSData *profileData = [profile valueForKey:@"data"];
            if (profileData) {
                NSString *docsPath = NSSearchPathForDirectoriesInDomains(
                    NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
                NSString *outPath = [docsPath stringByAppendingPathComponent:@"embedded.mobileprovision"];
                [profileData writeToFile:outPath atomically:YES];
                NSLog(@"[MProvDump] Saved mobileprovision to %@", outPath);
            }
        }
        completion(profile, error);
    });
}

%end
