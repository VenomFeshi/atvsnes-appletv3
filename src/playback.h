#import <QuartzCore/QuartzCore.h>
#include "display.h"
#include <stdint.h>

@interface ATVSNESPlayback : NSObject
@property(nonatomic, getter=isPaused) BOOL paused;
@property(nonatomic) ATVSNESAspect aspect;
@property(nonatomic, readonly, copy) NSString *romID;
- (NSString *)startInLayer:(CALayer *)screen romURL:(NSURL *)romURL saveURL:(NSURL *)saveURL;
- (void)setVideoHidden:(BOOL)hidden;
- (void)stop;
- (void)button:(unsigned)button value:(int)value;
- (void)bluetoothButtons:(uint16_t)buttons player:(unsigned)player;
- (NSData *)captureState;
- (NSData *)captureScreenshot;
- (BOOL)restoreState:(NSData *)state screenshot:(NSData *)screenshot;
@end
