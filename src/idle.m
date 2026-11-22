#import "idle.h"
#import <objc/message.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdint.h>

typedef int (*CreateAssertion)(CFStringRef, uint32_t, CFStringRef, uint32_t *);
typedef int (*ReleaseAssertion)(uint32_t);

@implementation ATVSNESIdleGuard {
    void *_iokit;
    ReleaseAssertion _releaseAssertion;
    uint32_t _assertion;
    BOOL _active, _renewed;
    NSTimeInterval _lastActivity;
}

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;
    _active = YES;
    // Same idle sleep assertion used by playback on this generation.
    _iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    if (_iokit) {
        CreateAssertion create = (CreateAssertion)dlsym(_iokit, "IOPMAssertionCreateWithName");
        _releaseAssertion = (ReleaseAssertion)dlsym(_iokit, "IOPMAssertionRelease");
        if (create && _releaseAssertion)
            _holdingSleepAssertion = create(CFSTR("NoIdleSleepAssertion"), 255,
                                            CFSTR("ATVSNES game"), &_assertion) == 0;
    }
    if (!_holdingSleepAssertion)
        NSLog(@"ATVSNES: idle sleep assertion unavailable");
    return self;
}

- (void)notePlaybackAtTime:(NSTimeInterval)time
{
    if (!_active || (_renewed && time - _lastActivity < 20))
        return;
    _renewed = YES;
    _lastActivity = time;

    // BackRow's screen saver is separate from IOKit's system sleep timer.
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ATVScreenSaverHoldOff" object:nil];
    Class managerClass = objc_getClass("ATVScreenSaverManager");
    SEL singleton = sel_registerName("singleton");
    if ([managerClass respondsToSelector:singleton]) {
        id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, singleton);
        SEL update = sel_registerName("_updateActivity:");
        if ([manager respondsToSelector:update])
            ((void (*)(id, SEL, id))objc_msgSend)(manager, update, nil);
    }
}

- (void)invalidate
{
    _active = NO;
    if (_holdingSleepAssertion) {
        _holdingSleepAssertion = NO;
        int result = _releaseAssertion(_assertion);
        if (result != 0)
            NSLog(@"ATVSNES: idle sleep assertion release failed (%d)", result);
    }
    if (_iokit) {
        dlclose(_iokit);
        _iokit = NULL;
    }
}

- (void)dealloc
{
    [self invalidate];
}
@end
