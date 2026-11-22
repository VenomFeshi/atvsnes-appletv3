#import "catalog.h"

@interface ATVSNESGameEntry ()
- (instancetype)initWithROM:(NSURL *)romURL saves:(NSURL *)saves title:(NSString *)title;
@end

@implementation ATVSNESGameEntry
- (instancetype)initWithROM:(NSURL *)romURL saves:(NSURL *)saves title:(NSString *)title
{
    self = [super init];
    if (self) {
        _romURL = [romURL copy];
        _title = [title copy];
        // v0.2 saved the original test ROM to game.srm. Keep that file in use.
        // Include the extension for other ROMs to distinguish same-stem titles.
        NSString *name = romURL.lastPathComponent;
        NSString *saveName = [name isEqualToString:@"game.sfc"] ? @"game.srm" :
                             [name stringByAppendingPathExtension:@"srm"];
        _saveURL = [saves URLByAppendingPathComponent:saveName isDirectory:NO];
    }
    return self;
}
@end

NSArray *ATVSNESReadLibrary(NSURL *directory, NSError **error)
{
    NSFileManager *files = [NSFileManager defaultManager];
    NSURL *roms = [directory URLByAppendingPathComponent:@"roms" isDirectory:YES];
    NSURL *saves = [directory URLByAppendingPathComponent:@"saves" isDirectory:YES];
    // Keep older installations readable until they run the migration.
    if (![files fileExistsAtPath:roms.path]) {
        roms = directory;
        saves = directory;
    }
    NSArray *urls = [files contentsOfDirectoryAtURL:roms
                        includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLIsSymbolicLinkKey]
                                           options:NSDirectoryEnumerationSkipsHiddenFiles
                                             error:error];
    if (!urls)
        return nil;
    NSDictionary *titles = [NSDictionary dictionaryWithContentsOfURL:
                            [directory URLByAppendingPathComponent:@"titles.plist"]];
    NSMutableArray *games = [NSMutableArray array];
    for (NSURL *url in urls) {
        NSString *name = url.lastPathComponent;
        NSString *extension = name.pathExtension.lowercaseString;
        if (![extension isEqualToString:@"sfc"] && ![extension isEqualToString:@"smc"])
            continue;
        NSNumber *regular = nil, *symlink = nil;
        if (![url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:NULL] ||
            ![url getResourceValue:&symlink forKey:NSURLIsSymbolicLinkKey error:NULL] ||
            !regular.boolValue || symlink.boolValue)
            continue;

        NSString *title = titles[name];
        if (![title isKindOfClass:[NSString class]] || !title.length)
            title = [name isEqualToString:@"game.sfc"] ? @"Previously installed game" :
                                                        name.stringByDeletingPathExtension;
        [games addObject:[[ATVSNESGameEntry alloc] initWithROM:url saves:saves title:title]];
    }
    [games sortUsingComparator:^NSComparisonResult(ATVSNESGameEntry *a, ATVSNESGameEntry *b) {
        NSComparisonResult order = [a.title localizedCaseInsensitiveCompare:b.title];
        return order != NSOrderedSame ? order :
               [a.romURL.lastPathComponent compare:b.romURL.lastPathComponent];
    }];
    return games;
}
