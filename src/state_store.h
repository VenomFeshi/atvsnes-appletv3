#import <Foundation/Foundation.h>

enum { ATVSNESStateSlotCount = 2 };

@interface ATVSNESStoredState : NSObject
@property(nonatomic, readonly, copy) NSData *core;
@property(nonatomic, readonly, copy) NSData *screenshot;
@property(nonatomic, readonly, copy) NSDate *date;
@end

@interface ATVSNESStateStore : NSObject
- (instancetype)initInSavesDirectory:(NSURL *)directory romID:(NSString *)romID;
- (BOOL)hasFileInSlot:(NSUInteger)slot;
- (ATVSNESStoredState *)stateInSlot:(NSUInteger)slot;
- (BOOL)writeCore:(NSData *)core screenshot:(NSData *)screenshot slot:(NSUInteger)slot;
@end
