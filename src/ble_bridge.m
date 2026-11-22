#import "ble_bridge.h"
#include <errno.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

enum { MaxMessage = 512, MaxQueuedBytes = 64 * 1024 };

static BOOL ConfigureSocket(int fd)
{
    int one = 1;
    int flags = fcntl(fd, F_GETFL);
    return flags != -1 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) != -1 &&
           setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one)) == 0;
}

int ATVSNESOpenBLESocket(BOOL listening)
{
    struct sockaddr_un addr = { .sun_len = sizeof(addr), .sun_family = AF_UNIX,
                                .sun_path = ATVSNES_BLE_SOCKET };
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0)
        return -1;
    if (!ConfigureSocket(fd))
        goto fail;
    if (listening) {
        struct stat existing;
        if (lstat(addr.sun_path, &existing) == 0) {
            if (!S_ISSOCK(existing.st_mode) || existing.st_uid != geteuid() || unlink(addr.sun_path))
                goto fail;
        } else if (errno != ENOENT) {
            goto fail;
        }
        mode_t previous = umask(077);
        int bound = bind(fd, (struct sockaddr *)&addr, sizeof(addr));
        umask(previous);
        if (bound || listen(fd, 2))
            goto fail;
    } else if (connect(fd, (struct sockaddr *)&addr, sizeof(addr))) {
        goto fail;
    }
    return fd;
fail:
    close(fd);
    return -1;
}

@implementation ATVSNESBLEChannel {
    dispatch_source_t _reader;
    dispatch_source_t _writer;
    int _fd;
    NSMutableData *_pending;
    NSMutableData *_outgoing;
    void (^_line)(NSString *);
    void (^_onClose)(void);
}

- (instancetype)initWithSocket:(int)fd line:(void (^)(NSString *))line onClose:(void (^)(void))onClose
{
    self = [super init];
    _fd = -1;
    if (!self || !ConfigureSocket(fd)) {
        close(fd);
        return nil;
    }
    _fd = fd;
    _pending = [NSMutableData data];
    _outgoing = [NSMutableData data];
    _line = [line copy];
    _onClose = [onClose copy];
    _reader = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, dispatch_get_main_queue());
    if (!_reader) {
        close(fd);
        _fd = -1;
        return nil;
    }
    __weak ATVSNESBLEChannel *weakChannel = self;
    dispatch_source_set_event_handler(_reader, ^{ [weakChannel receive]; });
    dispatch_source_set_cancel_handler(_reader, ^{ close(fd); });
    dispatch_resume(_reader);
    return self;
}

- (void)sendLine:(NSString *)line
{
    if (_fd < 0)
        return;
    NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length || data.length > MaxMessage || _outgoing.length + data.length > MaxQueuedBytes) {
        [self close];
        return;
    }
    [_outgoing appendData:data];
    if (!_writer)
        [self flush];
}

- (void)flush
{
    NSUInteger sent = 0;
    while (_fd >= 0 && sent < _outgoing.length) {
        ssize_t n = send(_fd, (const uint8_t *)_outgoing.bytes + sent, _outgoing.length - sent, 0);
        if (n > 0) {
            sent += (NSUInteger)n;
        } else if (n < 0 && errno == EINTR) {
            continue;
        } else if (n < 0 && (errno == EWOULDBLOCK || errno == EAGAIN)) {
            break;
        } else {
            [self close];
            return;
        }
    }
    if (_fd < 0)
        return;
    if (sent)
        [_outgoing replaceBytesInRange:NSMakeRange(0, sent) withBytes:NULL length:0];
    if (!_outgoing.length) {
        if (_writer) {
            dispatch_source_cancel(_writer);
            _writer = nil;
        }
    } else if (!_writer) {
        _writer = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, (uintptr_t)_fd, 0, dispatch_get_main_queue());
        if (!_writer) {
            [self close];
            return;
        }
        __weak ATVSNESBLEChannel *weakChannel = self;
        dispatch_source_set_event_handler(_writer, ^{ [weakChannel flush]; });
        dispatch_resume(_writer);
    }
}

- (void)receive
{
    uint8_t bytes[256];
    while (_fd >= 0) {
        ssize_t count = recv(_fd, bytes, sizeof(bytes), 0);
        if (count <= 0) {
            if (count < 0 && errno == EINTR)
                continue;
            if (count == 0 || (errno != EWOULDBLOCK && errno != EAGAIN))
                [self close];
            return;
        }
        for (ssize_t i = 0; i < count && _fd >= 0; ++i) {
            if (bytes[i] == '\n') {
                NSString *message = [[NSString alloc] initWithData:_pending encoding:NSUTF8StringEncoding];
                [_pending setLength:0];
                if (message)
                    _line(message);
                else
                    [self close];
            } else if (_pending.length >= MaxMessage - 1) {
                [self close];
            } else {
                [_pending appendBytes:&bytes[i] length:1];
            }
        }
    }
}

- (void)close
{
    if (_fd < 0)
        return;
    _fd = -1;
    if (_writer)
        dispatch_source_cancel(_writer);
    _writer = nil;
    dispatch_source_cancel(_reader);
    _reader = nil;
    [_outgoing setLength:0];
    void (^closed)(void) = _onClose;
    _onClose = nil;
    _line = nil;
    if (closed)
        closed();
}

- (void)dealloc
{
    if (_writer)
        dispatch_source_cancel(_writer);
    if (_reader)
        dispatch_source_cancel(_reader);
}
@end
