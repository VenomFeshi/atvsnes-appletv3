#import "catalog.h"

#include <stdio.h>
#include <string.h>

static BOOL TestCatalog(NSURL *directory, BOOL split)
{
    NSFileManager *files = [NSFileManager defaultManager];
    NSData *fixture = [NSData dataWithBytes:"test" length:4];
    NSURL *roms = split ? [directory URLByAppendingPathComponent:@"roms" isDirectory:YES] : directory;
    NSURL *saves = split ? [directory URLByAppendingPathComponent:@"saves" isDirectory:YES] : directory;
    if (split) {
        for (NSURL *folder in @[roms, saves])
            if (![files createDirectoryAtURL:folder withIntermediateDirectories:NO attributes:nil error:NULL])
                return NO;
        if (![fixture writeToURL:[directory URLByAppendingPathComponent:@"old.smc"] atomically:YES])
            return NO;
    }
    for (NSString *name in @[@"game.sfc", @"game.srm", @"A game.SMC", @"A game.sfc",
                              @"archive.zip", @".hidden.sfc"]) {
        if (![fixture writeToURL:[roms URLByAppendingPathComponent:name] atomically:YES])
            return NO;
    }
    if (![@{@"game.sfc": @"Zelda"}
          writeToURL:[directory URLByAppendingPathComponent:@"titles.plist"] atomically:YES])
        return NO;
    if (![files createDirectoryAtURL:[roms URLByAppendingPathComponent:@"folder.sfc"]
         withIntermediateDirectories:NO attributes:nil error:NULL])
        return NO;
    if (![files createSymbolicLinkAtURL:[roms URLByAppendingPathComponent:@"link.sfc"]
                   withDestinationURL:[roms URLByAppendingPathComponent:@"game.sfc"] error:NULL])
        return NO;

    NSError *error = nil;
    NSArray *games = ATVSNESReadLibrary(directory, &error);
    NSArray *titles = [games valueForKey:@"title"];
    if (error || ![titles isEqualToArray:@[@"A game", @"A game", @"Zelda"]])
        return NO;
    ATVSNESGameEntry *smc = games[0], *sfc = games[1], *legacy = games[2];
    return [smc.saveURL.lastPathComponent isEqualToString:@"A game.SMC.srm"] &&
           [sfc.saveURL.lastPathComponent isEqualToString:@"A game.sfc.srm"] &&
           [legacy.saveURL.lastPathComponent isEqualToString:@"game.srm"] &&
           [legacy.romURL.URLByDeletingLastPathComponent.lastPathComponent isEqualToString:roms.lastPathComponent] &&
           [legacy.saveURL.URLByDeletingLastPathComponent.lastPathComponent isEqualToString:saves.lastPathComponent];
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc == 3 && strcmp(argv[1], "--list") == 0) {
            NSURL *root = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]
                                    isDirectory:YES];
            NSError *error = nil;
            NSArray *games = ATVSNESReadLibrary(root, &error);
            if (!games) {
                fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
                return 1;
            }
            for (ATVSNESGameEntry *game in games)
                printf("%s: %s  →  %s\n", game.title.UTF8String, game.romURL.path.UTF8String,
                       game.saveURL.path.UTF8String);
            return games.count ? 0 : 1;
        }
        NSURL *directory = [NSURL fileURLWithPath:
            [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]
                                     isDirectory:YES];
        NSFileManager *files = [NSFileManager defaultManager];
        if (![files createDirectoryAtURL:directory withIntermediateDirectories:NO
                              attributes:nil error:NULL])
            return 1;
        BOOL passed = YES;
        for (NSString *name in @[@"legacy", @"split"]) {
            NSURL *fixture = [directory URLByAppendingPathComponent:name isDirectory:YES];
            passed = [files createDirectoryAtURL:fixture withIntermediateDirectories:NO
                                     attributes:nil error:NULL] &&
                     TestCatalog(fixture, [name isEqualToString:@"split"]) && passed;
        }
        [files removeItemAtURL:directory error:NULL];
        puts(passed ? "Catalog: filtering, sorting, and independent save paths passed." :
                      "Catalog test failed.");
        return passed ? 0 : 1;
    }
}
