#import <QuartzCore/QuartzCore.h>
#import "catalog.h"

@interface ATVSNESMenu : NSObject
@property(nonatomic, readonly, copy) NSArray *games;
@property(nonatomic, copy) NSURL *suspendedROM;
@property(nonatomic, readonly, getter=isControllerSelected) BOOL controllerSelected;
- (instancetype)initInLayer:(CALayer *)screen;
- (void)reload;
- (void)moveSelection:(NSInteger)direction;
- (void)highlightSuspendedGame;
- (ATVSNESGameEntry *)selectedGame;
- (void)showError:(NSString *)message;
- (void)showBluetoothStatus:(NSString *)message;
@end
