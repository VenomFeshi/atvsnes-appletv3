#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "playback.h"
#import "state_store.h"
#include "game.h"
#include <stdio.h>
#include <string.h>

@interface ATVSNESPlayback (StateTestTick)
- (void)tick:(CADisplayLink *)link;
@end

@interface ATVSNESStateClock : NSObject
@property(nonatomic) CFTimeInterval timestamp;
@end
@implementation ATVSNESStateClock
@end

#define CHECK(expr) do { if (!(expr)) { fprintf(stderr, "Failed: %s\n", #expr); return 1; } } while (0)

static void Advance(ATVSNESPlayback *playback, ATVSNESStateClock *clock, unsigned count)
{
    for (unsigned i = 0; i < count; ++i) {
        @autoreleasepool {
            clock.timestamp += 1.0 / 60.0;
            [playback tick:(CADisplayLink *)clock];
        }
    }
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc != 4 || (strcmp(argv[1], "--write") && strcmp(argv[1], "--read"))) {
            fputs("Usage: atv-state-test --write|--read ROM TEMP_DIRECTORY\n", stderr);
            return 2;
        }
        NSURL *rom = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
        NSURL *directory = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[3]] isDirectory:YES];
        NSURL *ram = [directory URLByAppendingPathComponent:@"test.srm"];
        CALayer *screen = [CALayer layer];
        screen.bounds = CGRectMake(0, 0, 1280, 720);
        ATVSNESPlayback *playback = [ATVSNESPlayback new];
        CHECK(![playback startInLayer:screen romURL:rom saveURL:ram]);
        ATVSNESStateStore *store = [[ATVSNESStateStore alloc] initInSavesDirectory:directory romID:playback.romID];
        ATVSNESStateClock *clock = [ATVSNESStateClock new];
        size_t size = 0;
        uint8_t *saveRAM = ATVSNESGameSaveRAM(&size);
        CHECK(size && saveRAM);
        if (!strcmp(argv[1], "--write")) {
            for (NSUInteger slot = 0; slot < ATVSNESStateSlotCount; ++slot) {
                Advance(playback, clock, slot == 0 ? 480 : 60);
                playback.paused = YES;
                saveRAM[0] = 0xA7 + slot;
                NSData *state = [playback captureState], *png = [playback captureScreenshot];
                CHECK(state.length == ATVSNESGameStateSize());
                CHECK([UIImage imageWithData:png].CGImage);
                CHECK([store writeCore:state screenshot:png slot:slot]);
                playback.paused = NO;
            }
            // Verify the next process recovered the marker from the state, not the .srm.
            saveRAM[0] = 0;
            puts("Wrote both slots with game frame PNGs.");
        } else {
            CHECK(saveRAM[0] == 0);
            for (NSUInteger slot = 0; slot < ATVSNESStateSlotCount; ++slot) {
                playback.paused = YES;
                ATVSNESStoredState *saved = [store stateInSlot:slot];
                CHECK(saved && [playback restoreState:saved.core screenshot:saved.screenshot]);
                CHECK(saveRAM[0] == 0xA7 + slot);
                CALayer *backdrop = screen.sublayers.firstObject;
                CALayer *video = backdrop.sublayers.firstObject;
                CHECK(video.contents != nil);
                id restoredFrame = video.contents;
                playback.paused = NO;
                Advance(playback, clock, 180);
                CHECK(video.contents != restoredFrame);
            }
            puts("Restored both states in a fresh process and ran 180 more frames from each.");
        }
        [playback stop];
    }
    return 0;
}
