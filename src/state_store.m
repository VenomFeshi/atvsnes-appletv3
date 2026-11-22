#import "state_store.h"
#include <CommonCrypto/CommonDigest.h>

enum { MaxState = 2 * 1024 * 1024, MaxScreenshot = 2 * 1024 * 1024 };

static NSData *Digest(NSData *data)
{
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    return [NSData dataWithBytes:hash length:sizeof(hash)];
}

// Only snapshots from the same pinned core and build architecture are supported.
static NSString *CoreFormat(void)
{
    return [NSString stringWithFormat:@"%s/%lu", ATVSNES_CORE_REV, (unsigned long)sizeof(void *)];
}

@interface ATVSNESStoredState ()
@property(nonatomic, readwrite, copy) NSData *core;
@property(nonatomic, readwrite, copy) NSData *screenshot;
@property(nonatomic, readwrite, copy) NSDate *date;
@end
@implementation ATVSNESStoredState
@end

@implementation ATVSNESStateStore {
    NSURL *_directory;
    NSString *_romID;
}

- (instancetype)initInSavesDirectory:(NSURL *)directory romID:(NSString *)romID
{
    self = [super init];
    if (self) {
        _romID = [romID copy];
        _directory = [[directory URLByAppendingPathComponent:@"states" isDirectory:YES]
                                  URLByAppendingPathComponent:romID isDirectory:YES];
    }
    return self;
}

- (NSURL *)urlForSlot:(NSUInteger)slot
{
    if (slot >= ATVSNESStateSlotCount)
        return nil;
    NSString *name = [NSString stringWithFormat:@"slot-%lu.atvstate", (unsigned long)slot + 1];
    return [_directory URLByAppendingPathComponent:name isDirectory:NO];
}

- (BOOL)hasFileInSlot:(NSUInteger)slot
{
    NSString *path = [self urlForSlot:slot].path;
    return path && [[NSFileManager defaultManager] fileExistsAtPath:path];
}

- (ATVSNESStoredState *)stateInSlot:(NSUInteger)slot
{
    NSURL *url = [self urlForSlot:slot];
    if (!url)
        return nil;
    NSNumber *size = nil;
    if (![url getResourceValue:&size forKey:NSURLFileSizeKey error:NULL] ||
        size.unsignedLongLongValue > MaxState + MaxScreenshot + 4096)
        return nil;
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (!data)
        return nil;
    id object = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable
                                                           format:NULL error:NULL];
    if (![object isKindOfClass:[NSDictionary class]])
        return nil;
    NSDictionary *record = object;
    NSData *core = record[@"core"], *png = record[@"screenshot"];
    NSDate *date = record[@"date"];
    if (![record[@"version"] isEqual:@1] || ![record[@"rom"] isEqual:_romID] ||
        ![record[@"format"] isEqual:CoreFormat()] ||
        ![core isKindOfClass:[NSData class]] || !core.length || core.length > MaxState ||
        ![png isKindOfClass:[NSData class]] || !png.length || png.length > MaxScreenshot ||
        ![date isKindOfClass:[NSDate class]] || ![record[@"hash"] isEqual:Digest(core)])
        return nil;
    ATVSNESStoredState *state = [ATVSNESStoredState new];
    state.core = core;
    state.screenshot = png;
    state.date = date;
    return state;
}

- (BOOL)writeCore:(NSData *)core screenshot:(NSData *)screenshot slot:(NSUInteger)slot
{
    NSURL *url = [self urlForSlot:slot];
    if (!url || !core.length || core.length > MaxState || !screenshot.length ||
        screenshot.length > MaxScreenshot)
        return NO;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:_directory
                                 withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700}
                                                        error:NULL])
        return NO;
    NSDictionary *record = @{@"version": @1, @"rom": _romID, @"format": CoreFormat(),
        @"core": core, @"hash": Digest(core), @"screenshot": screenshot, @"date": [NSDate date]};
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:record
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    return [data writeToURL:url atomically:YES];
}
@end
