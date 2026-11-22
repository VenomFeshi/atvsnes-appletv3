#import <QuartzCore/QuartzCore.h>

typedef NS_ENUM(NSUInteger, ATVSNESPausePage) {
    ATVSNESPauseActions,
    ATVSNESPauseDisplay,
    ATVSNESPauseGames,
    ATVSNESPauseConfirmSwitch,
    ATVSNESPauseStates,
    ATVSNESPauseStateActions,
    ATVSNESPauseConfirmOverwrite,
    ATVSNESPauseControllers
};

@interface ATVSNESPauseMenu : NSObject
@property(nonatomic, readonly) ATVSNESPausePage page;
@property(nonatomic, readonly) NSUInteger selection;
@property(nonatomic, readonly, getter=isVisible) BOOL visible;
- (instancetype)initInLayer:(CALayer *)screen;
- (void)showPage:(ATVSNESPausePage)page title:(NSString *)title detail:(NSString *)detail
         options:(NSArray *)options selected:(NSUInteger)selected;
- (void)hide;
- (void)moveSelection:(NSInteger)direction;
- (void)showBluetoothStatus:(NSString *)message;
- (void)showMessage:(NSString *)message;
- (void)showPreviews:(NSArray *)screenshots;
@end
