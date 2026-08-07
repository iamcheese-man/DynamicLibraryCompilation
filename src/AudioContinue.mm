#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

__attribute__((constructor))
static void EnableBackgroundAudio(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        AVAudioSession *session = [AVAudioSession sharedInstance];

        [session setCategory:AVAudioSessionCategoryPlayback
                 withOptions:AVAudioSessionCategoryOptionMixWithOthers
                       error:nil];

        [session setActive:YES error:nil];
    });
}
