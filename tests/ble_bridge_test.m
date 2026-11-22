#import "ble_bridge.h"
#include <stdio.h>
#include <sys/socket.h>
#include <unistd.h>

int main(void)
{
    @autoreleasepool {
        enum { Count = 1600 };
        int sockets[2], buffer = 1024;
        if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets))
            return 1;
        if (setsockopt(sockets[0], SOL_SOCKET, SO_SNDBUF, &buffer, sizeof(buffer))) {
            close(sockets[0]);
            close(sockets[1]);
            return 1;
        }
        __block BOOL closed = NO, correct = YES;
        __block unsigned received = 0;
        ATVSNESBLEChannel *writer = [[ATVSNESBLEChannel alloc] initWithSocket:sockets[0]
            line:^(NSString *line) { (void)line; } onClose:^{ closed = YES; }];
        if (!writer) {
            close(sockets[1]);
            return 1;
        }
        // Fill the kernel buffer while the other endpoint is not reading.
        for (unsigned i = 0; i < Count; ++i)
            [writer sendLine:[NSString stringWithFormat:@"B %u %u", i % 2, i]];
        ATVSNESBLEChannel *reader = [[ATVSNESBLEChannel alloc] initWithSocket:sockets[1]
            line:^(NSString *line) {
                NSString *expected = [NSString stringWithFormat:@"B %u %u", received % 2, received];
                correct &= [line isEqualToString:expected];
                ++received;
            } onClose:^{ closed = YES; }];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while (reader && !closed && received < Count && deadline.timeIntervalSinceNow > 0)
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        BOOL passed = !closed && correct && received == Count;
        [reader close];
        [writer close];
        printf("Local controller bridge: %u/%u ordered messages with a slow reader (%s).\n",
               received, Count, passed ? "passed" : "failed");
        return passed ? 0 : 1;
    }
}
