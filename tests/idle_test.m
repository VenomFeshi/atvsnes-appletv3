#import "idle.h"
#include <stdio.h>

// Stand-in for BackRow in this standalone test executable only.
static unsigned updates;
@interface ATVScreenSaverManager : NSObject
+ (instancetype)singleton;
- (void)_updateActivity:(id)object;
@end

@implementation ATVScreenSaverManager
+ (instancetype)singleton { return [self new]; }
- (void)_updateActivity:(id)object { (void)object; ++updates; }
@end

int main(void)
{
    @autoreleasepool {
        __block unsigned notices = 0;
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        id observer = [center addObserverForName:@"ATVScreenSaverHoldOff" object:nil queue:nil
                                     usingBlock:^(NSNotification *notification) {
            (void)notification;
            ++notices;
        }];
        ATVSNESIdleGuard *idle = [ATVSNESIdleGuard new];
        BOOL held = idle.holdingSleepAssertion;
        [idle notePlaybackAtTime:0];
        [idle notePlaybackAtTime:19.9];
        [idle notePlaybackAtTime:20.0];
        [idle invalidate];
        [idle notePlaybackAtTime:55];
        [center removeObserver:observer];
        BOOL passed = held && !idle.holdingSleepAssertion && updates == 2 && notices == 2;
        printf("Sleep assertion: %s; screen saver refreshes: %u / %u; guard inactive: %s.\n",
               held ? "acquired" : "failed", updates, notices,
               idle.holdingSleepAssertion ? "no" : "yes");
        return passed ? 0 : 1;
    }
}
