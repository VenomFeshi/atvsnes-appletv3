#import <Foundation/Foundation.h>
#include <stdint.h>

@interface ATVSNESBLEClient : NSObject
@property(nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property(nonatomic, readonly) BOOL awaitingApproval;
@property(nonatomic, readonly) unsigned pendingPlayer; // valid only while awaitingApproval
- (instancetype)initWithStatus:(void (^)(NSString *))status input:(void (^)(unsigned, uint16_t))input;
- (void)start;
- (void)addController;
- (void)pairPlayer:(unsigned)player;
- (void)cancelPairing;
- (void)approve;
- (void)stop;
@end
