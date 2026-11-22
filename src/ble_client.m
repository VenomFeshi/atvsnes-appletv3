#import "ble_client.h"
#import "ble_bridge.h"
#include "ble_protocol.h"
#include "joypads.h"

@implementation ATVSNESBLEClient {
    ATVSNESBLEChannel *_channel;
    void (^_status)(NSString *);
    void (^_input)(unsigned, uint16_t);
    unsigned _approvedPlayers, _pendingPlayer;
    BOOL _cancelingPairing;
}

- (instancetype)initWithStatus:(void (^)(NSString *))status input:(void (^)(unsigned, uint16_t))input
{
    self = [super init];
    if (self) {
        _status = [status copy];
        _input = [input copy];
    }
    return self;
}

- (BOOL)isEnabled { return _channel != nil; }
- (unsigned)pendingPlayer { return _pendingPlayer; }

- (BOOL)openChannel
{
    if (_channel)
        return YES;
    int fd = ATVSNESOpenBLESocket(NO);
    if (fd < 0) {
        _status(@"Bluetooth helper unavailable  •  Use the Apple remote");
        return NO;
    }
    __weak ATVSNESBLEClient *weakClient = self;
    _channel = [[ATVSNESBLEChannel alloc] initWithSocket:fd line:^(NSString *line) {
        [weakClient receive:line];
    } onClose:^{
        [weakClient finish:@"Bluetooth helper disconnected  •  Play/Pause to retry"];
    }];
    if (!_channel)
        _status(@"Could not open the Bluetooth helper");
    return _channel != nil;
}

- (void)start
{
    if (!_channel && [self openChannel]) {
        _status(@"Bluetooth: starting…");
        [_channel sendLine:@"START2"];
    }
}

- (void)pairPlayer:(unsigned)player
{
    if (player < ATVSNES_PLAYER_COUNT && [self openChannel])
        [_channel sendLine:[NSString stringWithFormat:@"PAIR %u", player]];
}

- (void)cancelPairing
{
    if (!_channel) {
        _status(@"No pairing in progress");
        return;
    }
    _awaitingApproval = NO;
    _cancelingPairing = YES;
    [_channel sendLine:@"CANCEL"];
}

- (void)addController
{
    if (_channel)
        [_channel sendLine:@"ADD"];
    else
        [self start];
}

- (void)approve
{
    if (!_awaitingApproval || !_channel)
        return;
    _awaitingApproval = NO;
    _approvedPlayers |= 1u << _pendingPlayer;
    [_channel sendLine:[NSString stringWithFormat:@"APPROVE %u", _pendingPlayer]];
}

- (void)receive:(NSString *)line
{
    if (line.length < 2 || [line characterAtIndex:1] != ' ')
        return;
    NSString *payload = [line substringFromIndex:2];
    switch ([line characterAtIndex:0]) {
        case 'S':
            _awaitingApproval = NO;
            _status(payload);
            break;
        case 'C':
            _cancelingPairing = _awaitingApproval = NO;
            _status(payload);
            break;
        case 'P':
            if (!_cancelingPairing && payload.length > 2 && [payload characterAtIndex:1] == ' ') {
                unsigned player = [payload characterAtIndex:0] - '0';
                if (player < ATVSNES_PLAYER_COUNT) {
                    _pendingPlayer = player;
                    _approvedPlayers &= ~(1u << player);
                    _awaitingApproval = YES;
                    _status([payload substringFromIndex:2]);
                }
            }
            break;
        case 'E': [self finish:payload]; break;
        case 'B': {
            int player = -1, value = -1;
            NSScanner *scanner = [NSScanner scannerWithString:payload];
            if ([scanner scanInt:&player] && player >= 0 && player < ATVSNES_PLAYER_COUNT &&
                (_approvedPlayers & (1u << player)) && [scanner scanInt:&value] && scanner.isAtEnd &&
                value >= 0 && (unsigned)value <= (ATVSNES_PAD_MASK | ATVSNES_BLE_BACK))
                _input((unsigned)player, (uint16_t)value);
            break;
        }
    }
}

- (void)finish:(NSString *)message
{
    ATVSNESBLEChannel *channel = _channel;
    if (!channel)
        return;
    _channel = nil;
    _approvedPlayers = 0;
    _cancelingPairing = _awaitingApproval = NO;
    [channel close];
    for (unsigned i = 0; i < ATVSNES_PLAYER_COUNT; ++i)
        _input(i, 0);
    _status(message);
}

- (void)stop
{
    [self finish:@"Choose a controller slot to pair"];
}
@end
