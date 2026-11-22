#import <CoreBluetooth/CoreBluetooth.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>
#include "../src/ble_protocol.h"

@interface Probe : NSObject <CBCentralManagerDelegate>
@property BOOL finished;
@property BOOL poweredOn;
@property BOOL found;
@property(nonatomic, strong) CBUUID *filter;
@end

@implementation Probe
- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    printf("CoreBluetooth central state: %ld (5 = powered on)\n", (long)central.state);
    self.poweredOn = central.state == CBCentralManagerStatePoweredOn;
    self.finished = central.state > CBCentralManagerStateResetting;
    if (self.poweredOn) {
        [central scanForPeripheralsWithServices:self.filter ? @[self.filter] : nil options:nil];
        printf("BLE scan started.\n");
    }
}
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary *)data RSSI:(NSNumber *)rssi
{
    (void)central;
    (void)peripheral;
    if (self.filter && ![data[CBAdvertisementDataServiceUUIDsKey] containsObject:self.filter])
        return;
    self.found = YES;
    printf("Received a BLE advertisement (%d dBm).\n", rssi.intValue);
}
@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        Probe *probe = [Probe new];
        if (argc == 2 && strcmp(argv[1], "--player2") == 0)
            probe.filter = [CBUUID UUIDWithString:@ATVSNES_BLE_SERVICE_P2];
        CBCentralManager *central = [[CBCentralManager alloc] initWithDelegate:probe queue:nil
            options:@{CBCentralManagerOptionShowPowerAlertKey: @NO}];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:probe.filter ? 10 : 5];
        while (deadline.timeIntervalSinceNow > 0 && (!probe.finished || probe.poweredOn) &&
               !(probe.filter && probe.found))
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
        if (probe.poweredOn)
            [central stopScan];
        if (probe.filter)
            puts(probe.found ? "Player 2 advertisement confirmed." : "No Player 2 advertisement received.");
        return probe.poweredOn && (!probe.filter || probe.found) ? 0 : 1;
    }
}
