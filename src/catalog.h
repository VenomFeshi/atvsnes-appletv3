#import <Foundation/Foundation.h>

@interface ATVSNESGameEntry : NSObject
@property(nonatomic, readonly, copy) NSURL *romURL;
@property(nonatomic, readonly, copy) NSURL *saveURL;
@property(nonatomic, readonly, copy) NSString *title;
@end

NSArray *ATVSNESReadLibrary(NSURL *directory, NSError **error);
