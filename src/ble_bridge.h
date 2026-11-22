#import <Foundation/Foundation.h>

#define ATVSNES_BLE_SOCKET "/var/mobile/Media/ATVSNES/.controller.sock"

int ATVSNESOpenBLESocket(BOOL listening);

// A small newline-framed protocol over the private, on-device Unix socket.
@interface ATVSNESBLEChannel : NSObject
- (instancetype)initWithSocket:(int)fd line:(void (^)(NSString *))line onClose:(void (^)(void))onClose;
- (void)sendLine:(NSString *)line;
- (void)close;
@end
