#import <Foundation/Foundation.h>

// One guard per active game. Call on the Apple TV UI thread.
@interface ATVSNESIdleGuard : NSObject
@property(nonatomic, readonly) BOOL holdingSleepAssertion;
- (void)notePlaybackAtTime:(NSTimeInterval)time;
- (void)invalidate;
@end
