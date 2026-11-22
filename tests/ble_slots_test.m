#import <CoreBluetooth/CoreBluetooth.h>
#import "bluetooth.h"
#include "ble_protocol.h"
#include <stdio.h>

// Exercise the real delegate/state code with scripted radio events.
@interface ATVSNESBluetooth (TestClock)
- (void)checkDeadlines:(NSTimer *)timer;
@end

@interface TestPhone : NSObject
@property(nonatomic, strong) NSUUID *identifier;
@property(nonatomic) CBPeripheralState state;
@property(nonatomic, weak) id delegate;
- (void)discoverServices:(NSArray *)services;
@end

@implementation TestPhone
- (void)discoverServices:(NSArray *)services { (void)services; }
@end

@interface TestCentral : NSObject
@property(nonatomic, strong) TestPhone *lastConnection;
@property(nonatomic, weak) id delegate;
@property(nonatomic, copy) NSArray *services;
- (void)scanForPeripheralsWithServices:(NSArray *)services options:(NSDictionary *)options;
- (void)stopScan;
- (void)connectPeripheral:(TestPhone *)phone options:(NSDictionary *)options;
- (void)cancelPeripheralConnection:(TestPhone *)phone;
@end

@implementation TestCentral
- (NSInteger)state { return CBCentralManagerStatePoweredOn; }
- (void)scanForPeripheralsWithServices:(NSArray *)services options:(NSDictionary *)options
{
    (void)options;
    self.services = services;
}
- (void)stopScan { self.services = nil; }
- (void)connectPeripheral:(TestPhone *)phone options:(NSDictionary *)options
{
    (void)options;
    self.lastConnection = phone;
    phone.state = CBPeripheralStateConnected;
}
- (void)cancelPeripheralConnection:(TestPhone *)phone { phone.state = CBPeripheralStateDisconnected; }
@end

@interface TestCharacteristic : NSObject
@property(nonatomic, copy) NSData *value;
@end

@implementation TestCharacteristic
@end

static TestPhone *NewPhone(void)
{
    TestPhone *phone = [TestPhone new];
    phone.identifier = [NSUUID UUID];
    return phone;
}

static void Advertise(id<CBCentralManagerDelegate> link, TestCentral *central, TestPhone *phone, NSString *service)
{
    [link centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)phone
         advertisementData:@{CBAdvertisementDataServiceUUIDsKey: @[[CBUUID UUIDWithString:service]]}
                     RSSI:@(-50)];
}

static void Packet(id<CBPeripheralDelegate> link, TestPhone *phone, TestCharacteristic *input, uint16_t mask)
{
    uint8_t bytes[] = {1, mask & 0xff, mask >> 8};
    input.value = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    [link peripheral:(CBPeripheral *)phone didUpdateValueForCharacteristic:(CBCharacteristic *)input error:nil];
}

#define CHECK(expr) do { if (!(expr)) { fprintf(stderr, "Failed at line %d: %s\n", __LINE__, #expr); return 1; } } while (0)

int main(void)
{
    @autoreleasepool {
        __block uint16_t player1 = 0, player2 = 0;
        ATVSNESBluetooth *link = [[ATVSNESBluetooth alloc] initWithStatus:^(NSString *message) {
            (void)message;
        } input:^(unsigned player, uint16_t mask) {
            if (!player) player1 = mask;
            else player2 = mask;
        }];
        id<CBCentralManagerDelegate> centralDelegate = (id<CBCentralManagerDelegate>)link;
        id<CBPeripheralDelegate> peripheralDelegate = (id<CBPeripheralDelegate>)link;
        TestCentral *central = [TestCentral new];
        [link setValue:central forKey:@"central"];
        NSArray *slots = [link valueForKey:@"players"];
        TestPhone *one = NewPhone(), *two = NewPhone(), *unknown = NewPhone();
        TestCharacteristic *input1 = [TestCharacteristic new], *input2 = [TestCharacteristic new];

        [link pairPlayer:0];
        Advertise(centralDelegate, central, two, @ATVSNES_BLE_SERVICE_P2);
        CHECK(!central.lastConnection);
        Advertise(centralDelegate, central, one, @ATVSNES_BLE_SERVICE_P1);
        CHECK(central.lastConnection == one);
        [slots[0] setValue:input1 forKey:@"input"];
        Packet(peripheralDelegate, one, input1, 1);
        CHECK(link.awaitingApproval && link.pendingPlayer == 0 && !player1);
        [link approve];
        Packet(peripheralDelegate, one, input1, 0);
        Packet(peripheralDelegate, one, input1, 1);

        CHECK(![link cancelPairing]);
        [link pairPlayer:1];
        CHECK([link cancelPairing] && !central.services);
        Advertise(centralDelegate, central, two, @ATVSNES_BLE_SERVICE_P2);
        CHECK(central.lastConnection == one && player1 == 1);
        [link pairPlayer:1];
        Advertise(centralDelegate, central, unknown, @ATVSNES_BLE_SERVICE_P1);
        CHECK(central.lastConnection == one);
        Advertise(centralDelegate, central, two, @ATVSNES_BLE_SERVICE_P2);
        CHECK(central.lastConnection == two);
        [slots[1] setValue:input2 forKey:@"input"];
        Packet(peripheralDelegate, two, input2, 0);
        CHECK(link.awaitingApproval && link.pendingPlayer == 1);
        CHECK([link cancelPairing] && !link.awaitingApproval && !central.services);
        [link approve];
        Packet(peripheralDelegate, two, input2, 128);
        CHECK(two.state == CBPeripheralStateDisconnected && player1 == 1 && player2 == 0);
        [link pairPlayer:1];
        Advertise(centralDelegate, central, two, @ATVSNES_BLE_SERVICE_P2);
        [slots[1] setValue:input2 forKey:@"input"];
        Packet(peripheralDelegate, two, input2, 0);
        CHECK(link.awaitingApproval && link.pendingPlayer == 1);
        [link approve];
        Packet(peripheralDelegate, two, input2, 0);
        Packet(peripheralDelegate, two, input2, 128);
        CHECK(player1 == 1 && player2 == 128);

        two.state = CBPeripheralStateDisconnected;
        [centralDelegate centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)two error:nil];
        CHECK(player1 == 1 && player2 == 0);
        [slots[1] setValue:@0 forKey:@"retryAt"];
        [link checkDeadlines:nil];
        central.lastConnection = nil;
        Advertise(centralDelegate, central, unknown, @ATVSNES_BLE_SERVICE_P2);
        CHECK(!central.lastConnection); // a different phone cannot take over a slot
        Advertise(centralDelegate, central, two, @ATVSNES_BLE_SERVICE_P2);
        CHECK(central.lastConnection == two);
        [slots[1] setValue:input2 forKey:@"input"];
        Packet(peripheralDelegate, two, input2, 128);
        CHECK(player1 == 1 && player2 == 0 && !link.awaitingApproval);
        Packet(peripheralDelegate, two, input2, 0);
        Packet(peripheralDelegate, two, input2, 128);
        CHECK(player1 == 1 && player2 == 128);
        [link pairPlayer:0]; // Already connected; pairing is not a disconnect toggle.
        [link pairPlayer:1];
        CHECK(!central.services && one.state == CBPeripheralStateConnected &&
              two.state == CBPeripheralStateConnected && player1 == 1 && player2 == 128);
        [link stop];
        CHECK(!player1 && !player2);
        [link setValue:central forKey:@"central"];
        central.lastConnection = nil;
        [link pairPlayer:1]; // Player 2 can be paired first.
        CHECK([central.services isEqual:@[[CBUUID UUIDWithString:@ATVSNES_BLE_SERVICE_P2]]]);
        Advertise(centralDelegate, central, one, @ATVSNES_BLE_SERVICE_P1);
        CHECK(!central.lastConnection);
        Advertise(centralDelegate, central, two, @ATVSNES_BLE_SERVICE_P2);
        CHECK(central.lastConnection == two);
        [slots[1] setValue:input2 forKey:@"input"];
        Packet(peripheralDelegate, two, input2, 0);
        CHECK(link.awaitingApproval && link.pendingPlayer == 1);
        [link pairPlayer:0]; // Changing the search cannot carry over approval.
        CHECK(!link.awaitingApproval && two.state == CBPeripheralStateDisconnected);
        CHECK([central.services isEqual:@[[CBUUID UUIDWithString:@ATVSNES_BLE_SERVICE_P1]]]);
        [link stop];
        puts("Controller slots: targeted pairing, cancel, approval, independent input, and isolated reconnect passed.");
    }
    return 0;
}
