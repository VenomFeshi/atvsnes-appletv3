#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <string.h>
#import "bluetooth.h"
#import "ble_client.h"
#include "joypads.h"

// Standalone USB/SSH lab test. The actual SNES menu still requires IR approval.
int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        BOOL two = argc == 2 && !strcmp(argv[1], "--two");
        BOOL scanOnly = argc == 2 && !strcmp(argv[1], "--scan");
        BOOL scanTwo = argc == 2 && !strcmp(argv[1], "--scan2");
        __block BOOL sawScan = NO, canceledScan = NO;
        __block BOOL sawPlayer2 = NO;
        unsigned players = two ? ATVSNES_PLAYER_COUNT : 1;
        __block unsigned sawB = 0, sawRight = 0, released = 0;
        unsigned expected = (1u << players) - 1;
        Class transport = two || scanOnly || scanTwo || (argc == 2 && !strcmp(argv[1], "--helper")) ?
                          [ATVSNESBLEClient class] : [ATVSNESBluetooth class];
        ATVSNESBluetooth *link = [[transport alloc] initWithStatus:^(NSString *status) {
            printf("%s\n", status.UTF8String);
            sawScan |= [status hasPrefix:@"Looking for Player 1"];
            sawPlayer2 |= [status hasPrefix:@"Looking for Player 2"];
            canceledScan |= [status hasPrefix:@"Pairing canceled"];
        } input:^(unsigned player, uint16_t buttons) {
            printf("Player %u mask: 0x%04x\n", player + 1, (unsigned)buttons);
            if (buttons == (1u << 0)) sawB |= 1u << player;
            if (buttons == (1u << 7)) sawRight |= 1u << player;
            if (!buttons) released |= sawB & sawRight & (1u << player);
        }];
        if (scanTwo)
            [link pairPlayer:1];
        else
            [link start];
        BOOL requestedSecond = NO;
        unsigned approved = 0;
        BOOL requestedCancel = NO;
        CFTimeInterval deadline = CACurrentMediaTime() + (two ? 90 : 40);
        while (link.enabled && (scanOnly ? !canceledScan : scanTwo ? !sawPlayer2 : (released & expected) != expected) &&
               CACurrentMediaTime() < deadline) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
            if (scanOnly) {
                if (sawScan && !requestedCancel) {
                    requestedCancel = YES;
                    [(ATVSNESBLEClient *)link cancelPairing];
                }
                continue;
            }
            if (link.awaitingApproval) {
                [link approve];
                ++approved;
                if (two) printf("TEST READY %u\n", approved);
                else puts("TEST READY");
            }
            if (two && !requestedSecond && (released & 1u)) {
                requestedSecond = YES;
                puts("TEST SEARCHING PLAYER 2");
                [link pairPlayer:1];
            }
        }
        BOOL passed = (released & expected) == expected;
        [link stop];
        if (scanTwo) {
            BOOL targeted = sawPlayer2 && !sawScan;
            puts(targeted ? "PASS: helper targeted Player 2 without starting a Player 1 search." :
                            "FAIL: helper did not target Player 2.");
            return targeted ? 0 : 1;
        }
        if (scanOnly) {
            puts(canceledScan ? "PASS: helper started and canceled Player 1 discovery." :
                                "FAIL: helper did not complete discovery smoke test.");
            return canceledScan ? 0 : 1;
        }
        printf("%s: received B, Right and release on %u of %u controller slots.\n",
               passed ? "PASS" : "FAIL", (released & 1u) + ((released >> 1) & 1u), players);
        return passed ? 0 : 1;
    }
}
