#import <UIKit/UIKit.h>
#import "playback.h"

#include <math.h>
#include <stdlib.h>
#include "audio.h"
#include "ble_protocol.h"
#include "display.h"
#include "game.h"
#include "joypads.h"
#import "idle.h"

@interface ATVSNESPlayback () {
    CALayer *_backdrop, *_video;
    CADisplayLink *_clock;
    NSURL *_saveURL;
    ATVSNESIdleGuard *_idleGuard;
    CGColorSpaceRef _colors;
    ATVSNESAudio *_audio;
    ATVSNESGameInfo _info;
    BOOL _active, _presentFrame;
    uint16_t _bluetoothButtons[ATVSNES_PLAYER_COUNT], _bluetoothPressed[ATVSNES_PLAYER_COUNT];
    uint16_t _bluetoothRaw[ATVSNES_PLAYER_COUNT], _waitForRelease[ATVSNES_PLAYER_COUNT];
    double _last, _accumulated;
    double _heldUntil[16], _pulseUntil[16];
    CGFloat _pixelAspect;
}
- (void)drawPixels:(const uint16_t *)pixels width:(unsigned)width height:(unsigned)height
             pitch:(size_t)pitch;
- (void)playSamples:(const int16_t *)samples frames:(size_t)frames;
- (void)startClock;
- (void)stopClock;
- (void)layoutVideo;
- (void)presentImage:(CGImageRef)image;
@end

static void OutputVideo(void *context, const uint16_t *pixels,
                        unsigned width, unsigned height, size_t pitch)
{
    [(__bridge ATVSNESPlayback *)context drawPixels:pixels width:width height:height pitch:pitch];
}

static void OutputAudio(void *context, const int16_t *samples, size_t frames)
{
    [(__bridge ATVSNESPlayback *)context playSamples:samples frames:frames];
}

static void FreePixels(void *context, const void *pixels, size_t bytes)
{
    (void)context;
    (void)bytes;
    free((void *)pixels);
}

@implementation ATVSNESPlayback
- (NSString *)startInLayer:(CALayer *)screen romURL:(NSURL *)romURL saveURL:(NSURL *)saveURL
{
    ATVSNESOutput output = {(__bridge void *)self, OutputVideo, OutputAudio};
    const char *error = ATVSNESGameOpen(romURL.fileSystemRepresentation, output, &_info);
    if (error)
        return [NSString stringWithUTF8String:error];
    _active = YES;
    _saveURL = saveURL;
    _romID = [NSString stringWithUTF8String:_info.romID];

    size_t saveSize;
    void *save = ATVSNESGameSaveRAM(&saveSize);
    if (save) {
        NSData *saved = [NSData dataWithContentsOfURL:_saveURL];
        if (saved.length == saveSize)
            memcpy(save, saved.bytes, saveSize);
    }

    _colors = CGColorSpaceCreateDeviceRGB();
    if (!_colors) {
        [self stop];
        return @"Could not create the game display.";
    }
    _backdrop = [CALayer layer];
    _backdrop.frame = screen.bounds;
    _backdrop.backgroundColor = [UIColor blackColor].CGColor;
    _video = [CALayer layer];
    _video.magnificationFilter = kCAFilterNearest;
    [self layoutVideo];
    [_backdrop addSublayer:_video];
    [screen addSublayer:_backdrop];

    [self startClock];
    return nil;
}

- (void)layoutVideo
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _video.frame = ATVSNESVideoFrame(_backdrop.bounds, _aspect, _pixelAspect);
    [CATransaction commit];
}

- (void)setAspect:(ATVSNESAspect)aspect
{
    _aspect = aspect;
    if (_video)
        [self layoutVideo];
}

- (NSData *)captureState
{
    if (!_active || !_paused)
        return nil;
    NSMutableData *data = [NSMutableData dataWithLength:ATVSNESGameStateSize()];
    return ATVSNESGameCaptureState(data.mutableBytes, data.length) ? data : nil;
}

- (NSData *)captureScreenshot
{
    id frame = _video.contents;
    return frame ? UIImagePNGRepresentation([UIImage imageWithCGImage:(__bridge CGImageRef)frame]) : nil;
}

- (BOOL)restoreState:(NSData *)state screenshot:(NSData *)screenshot
{
    if (!_active || !_paused || !ATVSNESGameRestoreState(state.bytes, state.length))
        return NO;
    UIImage *image = [UIImage imageWithData:screenshot];
    if (image.CGImage)
        [self presentImage:image.CGImage];
    return YES;
}

- (void)setVideoHidden:(BOOL)hidden
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _backdrop.hidden = hidden;
    [CATransaction commit];
}

- (void)startClock
{
    _last = _accumulated = 0;
    _audio = ATVSNESAudioCreate(_info.sampleRate);
    if (!_audio)
        NSLog(@"ATVSNES: audio unavailable; continuing without sound");
    _idleGuard = [ATVSNESIdleGuard new];
    [_idleGuard notePlaybackAtTime:CACurrentMediaTime()];
    _clock = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [_clock addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopClock
{
    [_clock invalidate];
    _clock = nil;
    [_idleGuard invalidate];
    _idleGuard = nil;

    ATVSNESAudioDestroy(_audio);
    _audio = NULL;
}

- (void)setPaused:(BOOL)paused
{
    if (!_active || _paused == paused)
        return;
    _paused = paused;
    memset(_heldUntil, 0, sizeof(_heldUntil));
    memset(_pulseUntil, 0, sizeof(_pulseUntil));
    for (unsigned player = 0; player < ATVSNES_PLAYER_COUNT; ++player) {
        _bluetoothPressed[player] = _bluetoothButtons[player] = 0;
        _waitForRelease[player] = _bluetoothRaw[player];
    }
    if (paused)
        [self stopClock];
    else
        [self startClock];
}

- (void)stop
{
    if (!_active)
        return;
    _active = NO;
    [self stopClock];
    size_t saveSize;
    void *save = ATVSNESGameSaveRAM(&saveSize);
    if (save && ![[NSData dataWithBytes:save length:saveSize] writeToURL:_saveURL atomically:YES])
        NSLog(@"ATVSNES: could not write cartridge save");
    ATVSNESGameClose();
    [_backdrop removeFromSuperlayer];
    _video = nil;
    _backdrop = nil;
    if (_colors)
        CGColorSpaceRelease(_colors);
    _colors = NULL;
}

- (void)button:(unsigned)button value:(int)value
{
    if (!_active || _paused || button >= 16)
        return;
    double now = CACurrentMediaTime();
    if (value > 0) {
        // Some IR events arrive as repeats without an explicit release.
        _heldUntil[button] = now + .50;
        _pulseUntil[button] = now + .08;
    } else {
        _heldUntil[button] = 0;
    }
}

- (void)bluetoothButtons:(uint16_t)buttons player:(unsigned)player
{
    if (player >= ATVSNES_PLAYER_COUNT)
        return;
    buttons &= ATVSNES_PAD_MASK;
    _bluetoothRaw[player] = buttons;
    if (_paused)
        return;
    _waitForRelease[player] &= buttons;
    buttons &= ~_waitForRelease[player];
    _bluetoothPressed[player] |= buttons & ~_bluetoothButtons[player];
    _bluetoothButtons[player] = buttons;
}

- (void)tick:(CADisplayLink *)link
{
    if (!_active || _paused)
        return;
    double step = 1.0 / _info.fps;
    double now = link.timestamp;
    _accumulated += _last ? MIN(MAX(now - _last, 0), 3 * step) : step;
    _last = now;
    unsigned frames = MIN(3u, (unsigned)((_accumulated + 1.e-7) / step));
    _accumulated = MAX(0, _accumulated - frames * step);
    uint16_t player1 = _bluetoothButtons[0] | _bluetoothPressed[0];
    uint16_t player2 = _bluetoothButtons[1] | _bluetoothPressed[1];
    if (frames)
        _bluetoothPressed[0] = _bluetoothPressed[1] = 0;
    double inputTime = CACurrentMediaTime();
    [_idleGuard notePlaybackAtTime:inputTime];
    for (unsigned i = 0; i < 16; ++i)
        if (inputTime < _heldUntil[i] || inputTime < _pulseUntil[i])
            player1 |= 1u << i;
    for (unsigned i = 0; i < frames; ++i) {
        _presentFrame = i + 1 == frames;
        ATVSNESGameRun(player1, player2);
    }
}

- (void)drawPixels:(const uint16_t *)pixels width:(unsigned)width height:(unsigned)height
             pitch:(size_t)pitch
{
    if (!_presentFrame)
        return;
    size_t bytes = (size_t)width * height * sizeof(uint32_t);
    uint32_t *bgra = malloc(bytes);
    if (!bgra)
        return;
    for (unsigned y = 0; y < height; ++y) {
        const uint16_t *row = (const uint16_t *)((const uint8_t *)pixels + y * pitch);
        for (unsigned x = 0; x < width; ++x) {
            unsigned pixel = row[x];
            unsigned r = pixel >> 11, g = (pixel >> 5) & 63, b = pixel & 31;
            bgra[y * width + x] = ((r << 3) | (r >> 2)) << 16 |
                                  ((g << 2) | (g >> 4)) << 8 | (b << 3) | (b >> 2);
        }
    }
    CGDataProviderRef data = CGDataProviderCreateWithData(NULL, bgra, bytes, FreePixels);
    if (!data) {
        free(bgra);
        return;
    }
    CGImageRef image = CGImageCreate(width, height, 8, 32, width * sizeof(*bgra), _colors,
                                    kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst,
                                    data, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(data);
    if (image) {
        [self presentImage:image];
        CGImageRelease(image);
    }
}

- (void)presentImage:(CGImageRef)image
{
    CGFloat aspect = ATVSNESPixelAspect(CGImageGetWidth(image), CGImageGetHeight(image));
    if (_pixelAspect != aspect) {
        _pixelAspect = aspect;
        if (_aspect == ATVSNESAspectSquarePixels)
            [self layoutVideo];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _video.contents = (__bridge id)image;
    [CATransaction commit];
}

- (void)playSamples:(const int16_t *)samples frames:(size_t)frames
{
    ATVSNESAudioPush(_audio, samples, frames);
}
@end
