#import <Foundation/Foundation.h>
#import "pause_menu.h"
#import "playback.h"
#include "game.h"
#include <stdio.h>

@interface ATVSNESPlayback (TestTick)
- (void)tick:(CADisplayLink *)link;
@end

@interface ATVSNESFakeClock : NSObject
@property(nonatomic) CFTimeInterval timestamp;
@end
@implementation ATVSNESFakeClock
@end

#define CHECK(expr) do { if (!(expr)) { fprintf(stderr, "Failed: %s\n", #expr); return 1; } } while (0)

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc != 3) {
            fputs("Usage: atv-pause-test ROM PATH_TO_TEMP_SAVE\n", stderr);
            return 2;
        }
        CALayer *screen = [CALayer layer];
        screen.bounds = CGRectMake(0, 0, 1280, 720);
        NSURL *rom = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSURL *save = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
        ATVSNESPlayback *playback = [ATVSNESPlayback new];
        NSString *error = [playback startInLayer:screen romURL:rom saveURL:save];
        if (error) {
            fprintf(stderr, "%s\n", error.UTF8String);
            return 1;
        }
        ATVSNESFakeClock *clock = [ATVSNESFakeClock new];
        CALayer *backdrop = screen.sublayers.firstObject;
        CALayer *video = backdrop.sublayers.firstObject;
        clock.timestamp = 1;
        [playback tick:(CADisplayLink *)clock];
        id frame = video.contents;
        CHECK(frame != nil);
        CHECK(CGRectEqualToRect(video.frame, CGRectMake(160, 0, 960, 720)));
        size_t saveSize;
        uint8_t *memory = ATVSNESGameSaveRAM(&saveSize);
        CHECK(memory && saveSize);
        memory[0] = 0xA7;

        playback.paused = YES;
        ATVSNESPauseMenu *menu = [[ATVSNESPauseMenu alloc] initInLayer:screen];
        [menu showPage:ATVSNESPauseDisplay title:@"Display" detail:@"Choose an aspect ratio"
                options:@[@"Original 4:3", @"Widescreen"] selected:0];
        [menu moveSelection:1];
        CHECK(menu.visible && menu.page == ATVSNESPauseDisplay && menu.selection == 1);
        playback.aspect = ATVSNESAspectWide;
        CHECK(CGRectEqualToRect(video.frame, screen.bounds));
        [playback setVideoHidden:YES];
        CHECK(backdrop.hidden);
        clock.timestamp = 10;
        [playback tick:(CADisplayLink *)clock];
        CHECK(playback.paused && video.contents == frame && memory[0] == 0xA7);
        CHECK(ATVSNESGameSaveRAM(&saveSize) == memory);
        CHECK(![[NSFileManager defaultManager] fileExistsAtPath:save.path]);
        [menu hide];
        CHECK(!menu.visible);
        [playback setVideoHidden:NO];
        playback.paused = NO;
        [playback tick:(CADisplayLink *)clock];
        CHECK(!playback.paused && !backdrop.hidden && video.contents != frame);
        [playback stop];
        CHECK([[NSFileManager defaultManager] fileExistsAtPath:save.path]);
        CHECK(!ATVSNESGameSaveRAM(&saveSize));
        puts("Playback: paused frame and cartridge RAM preserved; stretch, resume and exit passed.");
    }
    return 0;
}
