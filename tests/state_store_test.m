#import "state_store.h"
#include <stdio.h>

static BOOL TestSlots(NSURL *root)
{
    ATVSNESStateStore *zelda = [[ATVSNESStateStore alloc] initInSavesDirectory:root romID:@"game-a"];
    ATVSNESStateStore *mario = [[ATVSNESStateStore alloc] initInSavesDirectory:root romID:@"game-b"];
    NSData *one = [@"one" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *two = [@"two" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *photo = [@"test screenshot" dataUsingEncoding:NSUTF8StringEncoding];
    if ([zelda hasFileInSlot:0] || [zelda stateInSlot:1] ||
        [zelda writeCore:one screenshot:photo slot:2] ||
        ![zelda writeCore:one screenshot:photo slot:0] ||
        ![zelda writeCore:two screenshot:photo slot:1] ||
        ![mario writeCore:two screenshot:photo slot:0])
        return NO;
    ATVSNESStateStore *reopened = [[ATVSNESStateStore alloc] initInSavesDirectory:root romID:@"game-a"];
    ATVSNESStoredState *a = [reopened stateInSlot:0], *b = [reopened stateInSlot:1];
    if (![a.core isEqual:one] || ![b.core isEqual:two] || ![a.screenshot isEqual:photo] ||
        !a.date || ![[mario stateInSlot:0].core isEqual:two] || [mario hasFileInSlot:1] ||
        ![reopened writeCore:two screenshot:photo slot:0] || ![[reopened stateInSlot:0].core isEqual:two])
        return NO;

    NSURL *slot = [[[root URLByAppendingPathComponent:@"states"] URLByAppendingPathComponent:@"game-a"]
                   URLByAppendingPathComponent:@"slot-1.atvstate"];
    NSMutableDictionary *record = [NSMutableDictionary dictionaryWithContentsOfURL:slot];
    record[@"hash"] = one;
    if (![record writeToURL:slot atomically:YES] || ![reopened hasFileInSlot:0] || [reopened stateInSlot:0])
        return NO;
    record[@"version"] = @999;
    return [record writeToURL:slot atomically:YES] && ![reopened stateInSlot:0] &&
           [[reopened stateInSlot:1].core isEqual:two];
}

int main(void)
{
    @autoreleasepool {
        NSURL *root = [NSURL fileURLWithPath:
            [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
        BOOL passed = TestSlots(root);
        [[NSFileManager defaultManager] removeItemAtURL:root error:NULL];
        puts(passed ? "Save states: two slots, per-ROM isolation, overwrite and corruption checks passed." :
                      "Save-state store test failed.");
        return passed ? 0 : 1;
    }
}
