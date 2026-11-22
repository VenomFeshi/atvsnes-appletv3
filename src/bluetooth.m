#import <CoreBluetooth/CoreBluetooth.h>
#import <QuartzCore/QuartzCore.h>
#import "bluetooth.h"
#include "ble_protocol.h"
#include "joypads.h"

@interface ATVSNESPeripheralSlot : NSObject
@property(nonatomic, strong) CBPeripheral *phone;
@property(nonatomic, strong) CBCharacteristic *input;
@property(nonatomic) CFTimeInterval lastPacket, reconnectUntil, retryAt, connectUntil;
@property(nonatomic) uint16_t buttons;
@property(nonatomic) BOOL approved, pendingApproval, waitingForNeutral;
@end

@implementation ATVSNESPeripheralSlot
@end

static const CFTimeInterval InputGrace = 1.25;
static const CFTimeInterval InputStall = 4;
static const CFTimeInterval ReconnectWindow = 25;

static CBUUID *ServiceForPlayer(NSUInteger player)
{
    return [CBUUID UUIDWithString:player == 0 ? @ATVSNES_BLE_SERVICE_P1 : @ATVSNES_BLE_SERVICE_P2];
}

@interface ATVSNESBluetooth () <CBCentralManagerDelegate, CBPeripheralDelegate>
@end

@implementation ATVSNESBluetooth {
    CBCentralManager *_central;
    NSArray *_players;
    NSTimer *_timer;
    void (^_status)(NSString *);
    void (^_input)(unsigned, uint16_t);
    CFTimeInterval _deadline;
    NSUInteger _pending;
    NSArray *_scanServices;
}

- (instancetype)initWithStatus:(void (^)(NSString *))status input:(void (^)(unsigned, uint16_t))input
{
    self = [super init];
    if (self) {
        _status = [status copy];
        _input = [input copy];
        _pending = NSNotFound;
        NSMutableArray *players = [NSMutableArray arrayWithCapacity:ATVSNES_PLAYER_COUNT];
        for (unsigned i = 0; i < ATVSNES_PLAYER_COUNT; ++i)
            [players addObject:[ATVSNESPeripheralSlot new]];
        _players = [players copy];
    }
    return self;
}

- (BOOL)isEnabled { return _central != nil; }

- (BOOL)awaitingApproval
{
    return _pending != NSNotFound && [(ATVSNESPeripheralSlot *)_players[_pending] pendingApproval];
}

- (unsigned)pendingPlayer { return (unsigned)_pending; }

- (void)start
{
    if (!_central)
        [self pairPlayer:0];
}

- (void)pairPlayer:(unsigned)player
{
    if (player >= _players.count || _pending == player)
        return;
    ATVSNESPeripheralSlot *slot = _players[player];
    if (slot.approved) {
        [self reportPlayer:player state:slot.reconnectUntil ? @"is reconnecting…" : @"is already connected"];
        return;
    }
    if (_pending != NSNotFound)
        [self cancelPending:@"search canceled"];
    _pending = player;
    _deadline = CACurrentMediaTime() + 30;
    if (_central) {
        [self announcePairingSearch];
        return;
    }
    _timer = [NSTimer timerWithTimeInterval:.1 target:self selector:@selector(checkDeadlines:)
                                 userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    _central = [[CBCentralManager alloc] initWithDelegate:self queue:nil
        options:@{ CBCentralManagerOptionShowPowerAlertKey: @NO }];
    if (_central)
        _status([NSString stringWithFormat:@"Bluetooth: starting Player %u…", player + 1]);
    else
        [self finishWithStatus:@"Could not initialize Bluetooth"];
}

- (void)announcePairingSearch
{
    [self updateScan];
    if (_pending != NSNotFound)
        _status([NSString stringWithFormat:@"Looking for Player %lu’s phone…",
                                           (unsigned long)(_pending + 1)]);
}

- (void)addController
{
    if (!_central) {
        [self start];
        return;
    }
    if (_pending != NSNotFound) {
        [self cancelPending:@"search canceled"];
        return;
    }
    for (NSUInteger i = 0; i < _players.count; ++i) {
        ATVSNESPeripheralSlot *slot = _players[i];
        if (!slot.phone) {
            [self pairPlayer:(unsigned)i];
            return;
        }
    }
    for (NSUInteger i = 0; i < _players.count; ++i) {
        ATVSNESPeripheralSlot *slot = _players[i];
        if (slot.reconnectUntil) {
            [self reportPlayer:i state:@"reconnecting…"];
            return;
        }
    }
    _status(@"Players 1 and 2 connected  •  Leave SNES to disconnect");
}

- (void)setButtons:(uint16_t)buttons forPlayer:(NSUInteger)player
{
    ATVSNESPeripheralSlot *slot = _players[player];
    if (buttons != slot.buttons) {
        slot.buttons = buttons;
        _input((unsigned)player, buttons);
    }
}

- (void)stopScan
{
    if (_scanServices && _central.state == CBCentralManagerStatePoweredOn)
        [_central stopScan];
    _scanServices = nil;
}

- (BOOL)searchingForPlayer:(NSUInteger)player at:(CFTimeInterval)now
{
    ATVSNESPeripheralSlot *slot = _players[player];
    return (_pending == player && !slot.phone) ||
           (slot.reconnectUntil > now && slot.retryAt <= now && !slot.connectUntil &&
            slot.phone.state == CBPeripheralStateDisconnected);
}

- (void)updateScan
{
    if (_central.state != CBCentralManagerStatePoweredOn)
        return;
    CFTimeInterval now = CACurrentMediaTime();
    NSMutableArray *services = [NSMutableArray arrayWithCapacity:ATVSNES_PLAYER_COUNT];
    for (NSUInteger i = 0; i < _players.count; ++i)
        if ([self searchingForPlayer:i at:now])
            [services addObject:ServiceForPlayer(i)];
    if ([_scanServices isEqualToArray:services] || (!_scanServices && !services.count))
        return;
    [self stopScan];
    if (services.count) {
        _scanServices = [services copy];
        [_central scanForPeripheralsWithServices:_scanServices options:nil];
    }
}

- (void)reportPlayer:(NSUInteger)player state:(NSString *)state
{
    // Do not overwrite another player's approval prompt.
    if (_pending == NSNotFound)
        _status([NSString stringWithFormat:@"Player %lu %@", (unsigned long)(player + 1), state]);
}

- (NSUInteger)indexForPhone:(CBPeripheral *)phone
{
    for (NSUInteger i = 0; i < _players.count; ++i) {
        ATVSNESPeripheralSlot *slot = _players[i];
        if (slot.phone == phone)
            return i;
    }
    return NSNotFound;
}

- (void)dropPlayer:(NSUInteger)player
{
    ATVSNESPeripheralSlot *slot = _players[player];
    CBPeripheral *phone = slot.phone;
    phone.delegate = nil;
    slot.phone = nil;
    slot.input = nil;
    slot.approved = slot.pendingApproval = slot.waitingForNeutral = NO;
    slot.lastPacket = slot.reconnectUntil = slot.retryAt = slot.connectUntil = 0;
    if (phone && _central.state == CBCentralManagerStatePoweredOn &&
        phone.state != CBPeripheralStateDisconnected)
        [_central cancelPeripheralConnection:phone];
    [self setButtons:0 forPlayer:player];
}

- (void)cancelPending:(NSString *)reason
{
    NSUInteger player = _pending;
    if (player == NSNotFound)
        return;
    _pending = NSNotFound;
    _deadline = 0;
    [self dropPlayer:player];
    [self updateScan];
    _status([NSString stringWithFormat:@"Player %lu %@  •  Select its slot to retry",
                                       (unsigned long)(player + 1), reason]);
}

- (BOOL)cancelPairing
{
    if (_pending == NSNotFound)
        return NO;
    [self cancelPending:@"pairing canceled"];
    return YES;
}

- (void)recoverPlayer:(NSUInteger)player reason:(NSString *)reason
{
    ATVSNESPeripheralSlot *slot = _players[player];
    CFTimeInterval now = CACurrentMediaTime();
    BOOL first = !slot.reconnectUntil;
    if (first)
        slot.reconnectUntil = now + ReconnectWindow;
    slot.waitingForNeutral = YES;
    slot.input = nil;
    slot.lastPacket = slot.connectUntil = 0;
    slot.retryAt = now + .5;
    slot.phone.delegate = nil;
    if (_central.state == CBCentralManagerStatePoweredOn && slot.phone.state != CBPeripheralStateDisconnected)
        [_central cancelPeripheralConnection:slot.phone];
    [self setButtons:0 forPlayer:player];
    [self updateScan];
    if (first)
        [self reportPlayer:player state:[NSString stringWithFormat:@"%@  •  Reconnecting…", reason]];
}

- (void)lostPhone:(CBPeripheral *)phone reason:(NSString *)reason
{
    NSUInteger player = [self indexForPhone:phone];
    if (player == NSNotFound)
        return;
    if (player == _pending) {
        [self cancelPending:reason];
    } else {
        [self recoverPlayer:player reason:reason];
    }
}

- (void)finishWithStatus:(NSString *)message
{
    [_timer invalidate];
    _timer = nil;
    _central.delegate = nil;
    _pending = NSNotFound;
    _deadline = 0;
    [self stopScan];
    for (NSUInteger i = 0; i < _players.count; ++i)
        [self dropPlayer:i];
    _central = nil;
    _status(message);
}

- (void)stop
{
    [self finishWithStatus:@"Play/Pause  Connect a Bluetooth controller"];
}

- (void)approve
{
    if (!self.awaitingApproval)
        return;
    NSUInteger player = _pending;
    ATVSNESPeripheralSlot *slot = _players[player];
    slot.pendingApproval = NO;
    slot.approved = YES;
    slot.waitingForNeutral = YES;
    _pending = NSNotFound;
    _deadline = 0;
    ATVSNESPeripheralSlot *other = _players[1 - player];
    if (other.approved && !other.reconnectUntil)
        _status(@"Players 1 and 2 connected  •  Leave SNES to disconnect");
    else if (other.reconnectUntil)
        [self reportPlayer:(1 - player) state:@"reconnecting…"];
    else
        _status([NSString stringWithFormat:@"Player %lu connected  •  Play/Pause to add Player %lu",
                                           (unsigned long)(player + 1), (unsigned long)(2 - player)]);
}

- (void)checkDeadlines:(NSTimer *)timer
{
    (void)timer;
    CFTimeInterval now = CACurrentMediaTime();
    if (_deadline && now >= _deadline)
        [self cancelPending:@"Bluetooth timed out"];
    for (NSUInteger i = 0; i < _players.count; ++i) {
        ATVSNESPeripheralSlot *slot = _players[i];
        if (slot.reconnectUntil) {
            if (now >= slot.reconnectUntil) {
                [self dropPlayer:i];
                [self reportPlayer:i state:@"reconnect timed out  •  Play/Pause in the library to retry"];
            } else if (slot.connectUntil && now >= slot.connectUntil) {
                [self recoverPlayer:i reason:@"reconnect attempt timed out"];
            }
        } else if (slot.approved && now - slot.lastPacket > InputStall) {
            [self recoverPlayer:i reason:@"input stopped"];
        } else if (slot.approved && now - slot.lastPacket > InputGrace) {
            slot.waitingForNeutral = YES;
            [self setButtons:0 forPlayer:i];
        }
    }
    [self updateScan];
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    if (central != _central)
        return;
    switch (central.state) {
        case CBCentralManagerStatePoweredOn:
            [self announcePairingSearch];
            break;
        case CBCentralManagerStatePoweredOff:
            [self finishWithStatus:@"Apple TV Bluetooth is off  •  Play/Pause to retry"];
            break;
        case CBCentralManagerStateUnsupported:
        case CBCentralManagerStateUnauthorized:
            [self finishWithStatus:@"This Apple TV does not allow Bluetooth LE access"];
            break;
        case CBCentralManagerStateResetting:
            [self finishWithStatus:@"Bluetooth restarted  •  Play/Pause to retry"];
            break;
        case CBCentralManagerStateUnknown:
            break;
    }
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)phone
     advertisementData:(NSDictionary *)data RSSI:(NSNumber *)rssi
{
    (void)rssi;
    if (central != _central || !_scanServices)
        return;
    NSArray *advertised = data[CBAdvertisementDataServiceUUIDsKey];
    CFTimeInterval now = CACurrentMediaTime();
    for (NSUInteger i = 0; i < _players.count; ++i) {
        ATVSNESPeripheralSlot *slot = _players[i], *other = _players[1 - i];
        CBUUID *service = ServiceForPlayer(i);
        BOOL matched = [advertised containsObject:service];
        if (!advertised.count)
            matched = [_scanServices containsObject:service] &&
                      (_scanServices.count == 1 || [slot.phone.identifier isEqual:phone.identifier]);
        if (![self searchingForPlayer:i at:now] || !matched)
            continue;
        if ([other.phone.identifier isEqual:phone.identifier])
            return;
        if (slot.reconnectUntil) {
            if (![slot.phone.identifier isEqual:phone.identifier])
                continue; // A new device still needs explicit approval in the library.
            slot.connectUntil = now + 8;
        } else {
            _deadline = now + 12;
        }
        slot.phone = phone;
        [central connectPeripheral:phone options:nil];
        [self updateScan];
        if (_pending == i)
            _status([NSString stringWithFormat:@"Connecting Player %lu…", (unsigned long)(i + 1)]);
        return;
    }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)phone
{
    NSUInteger player = [self indexForPhone:phone];
    if (central != _central || player == NSNotFound)
        return;
    phone.delegate = self;
    [phone discoverServices:@[ServiceForPlayer(player)]];
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)phone
                 error:(NSError *)error
{
    if (central == _central)
        [self lostPhone:phone reason:[NSString stringWithFormat:@"connection failed (BLE %ld)", (long)error.code]];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)phone
                 error:(NSError *)error
{
    if (central == _central)
        [self lostPhone:phone reason:[NSString stringWithFormat:@"disconnected (BLE %ld)", (long)error.code]];
}

- (void)peripheral:(CBPeripheral *)phone didDiscoverServices:(NSError *)error
{
    NSUInteger player = [self indexForPhone:phone];
    if (player == NSNotFound)
        return;
    CBUUID *uuid = ServiceForPlayer(player);
    if (!error) {
        for (CBService *service in phone.services) {
            if ([service.UUID isEqual:uuid]) {
                [phone discoverCharacteristics:@[[CBUUID UUIDWithString:@ATVSNES_BLE_INPUT]]
                                      forService:service];
                return;
            }
        }
    }
    [self lostPhone:phone reason:@"controller service not found"];
}

- (void)peripheral:(CBPeripheral *)phone didDiscoverCharacteristicsForService:(CBService *)service
             error:(NSError *)error
{
    NSUInteger player = [self indexForPhone:phone];
    if (player == NSNotFound)
        return;
    ATVSNESPeripheralSlot *slot = _players[player];
    CBUUID *uuid = [CBUUID UUIDWithString:@ATVSNES_BLE_INPUT];
    if (!error) {
        for (CBCharacteristic *characteristic in service.characteristics) {
            if ([characteristic.UUID isEqual:uuid] &&
                (characteristic.properties & CBCharacteristicPropertyNotify)) {
                slot.input = characteristic;
                [phone setNotifyValue:YES forCharacteristic:characteristic];
                return;
            }
        }
    }
    [self lostPhone:phone reason:@"controller input service is incompatible"];
}

- (void)peripheral:(CBPeripheral *)phone didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)c
             error:(NSError *)error
{
    NSUInteger player = [self indexForPhone:phone];
    if (player != NSNotFound && c == [(ATVSNESPeripheralSlot *)_players[player] input] &&
        (error || !c.isNotifying))
        [self lostPhone:phone reason:@"could not enable controller input"];
}

- (void)peripheral:(CBPeripheral *)phone didUpdateValueForCharacteristic:(CBCharacteristic *)c
             error:(NSError *)error
{
    NSUInteger player = [self indexForPhone:phone];
    if (player == NSNotFound)
        return;
    ATVSNESPeripheralSlot *slot = _players[player];
    uint16_t buttons;
    if (c != slot.input || error ||
        !ATVSNESDecodeInput(c.value.bytes, c.value.length, &buttons))
        return;
    slot.lastPacket = CACurrentMediaTime();
    if (!slot.approved) {
        if (!slot.pendingApproval && player == _pending) {
            slot.pendingApproval = YES;
            _deadline = slot.lastPacket + 30;
            _status([NSString stringWithFormat:@"Player %lu found  •  Press Select on the Apple remote to approve",
                                               (unsigned long)(player + 1)]);
        }
        return;
    }
    if (slot.reconnectUntil) {
        slot.reconnectUntil = slot.retryAt = slot.connectUntil = 0;
        [self updateScan];
        [self reportPlayer:player state:@"reconnected"];
    }
    if (slot.waitingForNeutral && buttons)
        return;
    slot.waitingForNeutral = NO;
    [self setButtons:buttons forPlayer:player];
}
@end
