#import "ble_bridge.h"
#import "bluetooth.h"
#include "joypads.h"
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

static void LogEvent(NSString *message)
{
    int fd = open("/var/mobile/Media/ATVSNES/.controller-events.log",
                  O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW | O_NONBLOCK, 0600);
    if (fd < 0)
        return;
    struct stat info;
    if (fstat(fd, &info) == 0 && S_ISREG(info.st_mode)) {
        if (info.st_size >= 32768)
            ftruncate(fd, 0);
        NSString *line = [NSString stringWithFormat:@"%.0f %@\n", [NSDate date].timeIntervalSince1970, message];
        NSData *record = [line dataUsingEncoding:NSUTF8StringEncoding];
        write(fd, record.bytes, record.length);
    }
    close(fd);
}

@interface ATVSNESBLEHelper : NSObject
- (BOOL)listen;
@end

@implementation ATVSNESBLEHelper {
    dispatch_source_t _listener;
    ATVSNESBLEChannel *_peer;
    ATVSNESBluetooth *_bluetooth;
    BOOL _legacyClient;
}

- (BOOL)listen
{
    int fd = ATVSNESOpenBLESocket(YES);
    if (fd < 0)
        return NO;
    _listener = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, dispatch_get_main_queue());
    if (!_listener) {
        close(fd);
        return NO;
    }
    __weak ATVSNESBLEHelper *weakHelper = self;
    dispatch_source_set_event_handler(_listener, ^{ [weakHelper acceptPeer:fd]; });
    dispatch_source_set_cancel_handler(_listener, ^{ close(fd); });
    dispatch_resume(_listener);
    LogEvent(@"Bluetooth helper ready");
    return YES;
}

- (void)acceptPeer:(int)listener
{
    int fd;
    while ((fd = accept(listener, NULL, NULL)) >= 0) {
        uid_t user;
        gid_t group;
        if (getpeereid(fd, &user, &group) != 0 || user != geteuid()) {
            close(fd);
            continue;
        }
        if (_peer) {
            LogEvent(@"Rejected another local client while SNES was connected");
            close(fd);
            continue;
        }
        __weak ATVSNESBLEHelper *weakHelper = self;
        _peer = [[ATVSNESBLEChannel alloc] initWithSocket:fd line:^(NSString *line) {
            [weakHelper receive:line];
        } onClose:^{
            [weakHelper peerClosed];
        }];
    }
}

- (void)receive:(NSString *)line
{
    BOOL start = [line isEqualToString:@"START2"] || [line isEqualToString:@"START"];
    unsigned player = ATVSNES_PLAYER_COUNT;
    if (line.length == 6 && [line hasPrefix:@"PAIR "])
        player = [line characterAtIndex:5] - '0';
    if ((start || player < ATVSNES_PLAYER_COUNT) && !_bluetooth) {
        _legacyClient = [line isEqualToString:@"START"];
        __weak ATVSNESBLEHelper *weakHelper = self;
        _bluetooth = [[ATVSNESBluetooth alloc] initWithStatus:^(NSString *status) {
            [weakHelper reportStatus:status];
        } input:^(unsigned player, uint16_t buttons) {
            [weakHelper reportButtons:buttons player:player];
        }];
        if (start)
            [_bluetooth start];
    }
    if (!_legacyClient && player < ATVSNES_PLAYER_COUNT) {
        [_bluetooth pairPlayer:player];
    } else if (!_legacyClient && [line isEqualToString:@"ADD"]) {
        [_bluetooth addController];
    } else if (!_legacyClient && [line isEqualToString:@"CANCEL"]) {
        BOOL canceled = [_bluetooth cancelPairing];
        [_peer sendLine:canceled ? @"C Pairing canceled  •  Choose a slot to start again" :
                                  @"C No pairing in progress"];
    } else if ([line isEqualToString:@"APPROVE"]) {
        [_bluetooth approve];
    } else if ([line hasPrefix:@"APPROVE "] && line.length == 9 && _bluetooth.awaitingApproval &&
               (unsigned)([line characterAtIndex:8] - '0') == _bluetooth.pendingPlayer) {
        [_bluetooth approve];
    }
}

- (void)reportStatus:(NSString *)status
{
    if (_peer)
        LogEvent(status);
    NSString *type = !_bluetooth.enabled ? @"E" : _bluetooth.awaitingApproval ? @"P" : @"S";
    if (!_legacyClient && _bluetooth.awaitingApproval) {
        [_peer sendLine:[NSString stringWithFormat:@"P %u %@", _bluetooth.pendingPlayer, status]];
        return;
    }
    [_peer sendLine:[NSString stringWithFormat:@"%@ %@", type, status]];
}

- (void)reportButtons:(uint16_t)buttons player:(unsigned)player
{
    if (!_legacyClient)
        [_peer sendLine:[NSString stringWithFormat:@"B %u %u", player, (unsigned)buttons]];
    else if (player == 0)
        [_peer sendLine:[NSString stringWithFormat:@"B %u", (unsigned)buttons]];
}

- (void)peerClosed
{
    LogEvent(@"Local SNES connection closed; stopping controller session");
    _peer = nil;
    ATVSNESBluetooth *link = _bluetooth;
    _bluetooth = nil;
    [link stop];
}
@end

int main(void)
{
    @autoreleasepool {
        // iOS 8's CoreBluetooth client expects a live main run loop.
        ATVSNESBLEHelper *helper __attribute__((objc_precise_lifetime)) = [ATVSNESBLEHelper new];
        if (![helper listen])
            return 1;
        NSRunLoop *loop = [NSRunLoop mainRunLoop];
        [loop addPort:[NSPort port] forMode:NSDefaultRunLoopMode];
        [loop run];
        return 1;
    }
}
