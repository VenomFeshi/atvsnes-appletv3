#import <UIKit/UIKit.h>
#import "menu.h"
#include "game.h"

enum { VisibleRows = 6 };

static CATextLayer *Label(CALayer *parent, CGRect frame, CGFloat size, UIColor *color)
{
    CATextLayer *text = [CATextLayer layer];
    text.frame = frame;
    text.fontSize = size;
    text.foregroundColor = color.CGColor;
    text.truncationMode = kCATruncationEnd;
    [parent addSublayer:text];
    return text;
}

@implementation ATVSNESMenu {
    NSInteger _selected;
    NSMutableArray *_rows;
    CATextLayer *_subtitle, *_message, *_footer, *_position, *_bluetoothStatus, *_controllerLabel;
}

- (void)setSuspendedROM:(NSURL *)suspendedROM
{
    _suspendedROM = [suspendedROM copy];
    [self redraw];
}

- (instancetype)initInLayer:(CALayer *)screen
{
    self = [super init];
    if (!self)
        return nil;

    CALayer *panel = [CALayer layer];
    panel.frame = screen.bounds;
    panel.backgroundColor = [UIColor colorWithRed:.065 green:.055 blue:.12 alpha:1].CGColor;
    [screen addSublayer:panel];

    UIColor *white = [UIColor whiteColor];
    UIColor *muted = [UIColor colorWithRed:.76 green:.72 blue:.86 alpha:1];
    Label(panel, CGRectMake(80, 55, 1120, 76), 60, white).string = @"SNES";
    _subtitle = Label(panel, CGRectMake(84, 137, 1112, 42), 30, muted);
    _message = Label(panel, CGRectMake(84, 582, 1112, 30), 23, muted);
    _bluetoothStatus = Label(panel, CGRectMake(84, 614, 744, 34), 23, white);
    _bluetoothStatus.string = @"Play/Pause opens the controller menu";
    CALayer *controllerButton = [CALayer layer];
    controllerButton.frame = CGRectMake(840, 601, 360, 47);
    controllerButton.cornerRadius = 9;
    [panel addSublayer:controllerButton];
    _controllerLabel = Label(controllerButton, CGRectMake(14, 6, 332, 36), 26, white);
    _controllerLabel.alignmentMode = kCAAlignmentCenter;
    _controllerLabel.string = @"Bluetooth Controllers";
    _footer = Label(panel, CGRectMake(84, 650, 870, 36), 24, muted);
    _position = Label(panel, CGRectMake(966, 650, 230, 36), 24, muted);
    _position.alignmentMode = kCAAlignmentRight;

    _rows = [NSMutableArray arrayWithCapacity:VisibleRows];
    for (NSInteger i = 0; i < VisibleRows; ++i) {
        CALayer *row = [CALayer layer];
        row.frame = CGRectMake(80, 192 + 65 * i, 1120, 58);
        row.cornerRadius = 10;
        row.hidden = YES;
        [panel addSublayer:row];
        [_rows addObject:Label(row, CGRectMake(20, 7, 1080, 44), 31, white)];
    }
    return self;
}

- (ATVSNESGameEntry *)selectedGame
{
    return _selected < (NSInteger)_games.count ? _games[_selected] : nil;
}

- (BOOL)isControllerSelected
{
    return _selected == (NSInteger)_games.count;
}

- (void)reload
{
    NSURL *previous = self.selectedGame.romURL;
    BOOL selectedControllers = _games && self.controllerSelected;
    NSURL *directory = [NSURL fileURLWithPath:@ATVSNES_LIBRARY_PATH isDirectory:YES];
    NSError *error = nil;
    _games = ATVSNESReadLibrary(directory, &error);
    _selected = selectedControllers ? (NSInteger)_games.count : 0;
    for (NSInteger i = 0; i < (NSInteger)_games.count; ++i) {
        ATVSNESGameEntry *game = _games[i];
        if ([game.romURL isEqual:previous]) {
            _selected = i;
            break;
        }
    }
    [self redraw];
    if (error && !([error.domain isEqualToString:NSCocoaErrorDomain] &&
                   (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError))) {
        [self showError:@"Could not read the game folder."];
        NSLog(@"ATVSNES: library scan failed: %@", error);
    }
}

- (void)moveSelection:(NSInteger)direction
{
    if (!_games.count)
        return;
    NSInteger next = MAX(0, MIN(_selected + direction, (NSInteger)_games.count));
    if (next != _selected) {
        _selected = next;
        [self redraw];
    }
}

- (void)highlightSuspendedGame
{
    if (!_suspendedROM)
        return;
    for (NSUInteger i = 0; i < _games.count; ++i) {
        ATVSNESGameEntry *game = _games[i];
        if ([game.romURL isEqual:_suspendedROM]) {
            _selected = (NSInteger)i;
            [self redraw];
            return;
        }
    }
}

- (void)redraw
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _subtitle.string = _games.count ? @"Choose a game" : @"No games found";
    if (self.suspendedROM && [self.selectedGame.romURL isEqual:self.suspendedROM])
        _message.string = @"Game paused  •  Select to resume where you left off";
    else
        _message.string = _games.count ? @"" : @"Upload a .sfc or .smc file to ATVSNES/roms.";
    _footer.string = @"↑ / ↓  Browse    •    Select  Open    •    Menu  Exit";
    _position.string = _games.count && !self.controllerSelected ?
        [NSString stringWithFormat:@"%lu / %lu", (unsigned long)_selected + 1, (unsigned long)_games.count] : @"";
    NSInteger lastGame = MAX(0, (NSInteger)_games.count - 1);
    NSInteger first = MIN(_selected, lastGame) / VisibleRows * VisibleRows;
    UIColor *highlight = [UIColor colorWithRed:.34 green:.23 blue:.60 alpha:1];
    UIColor *normal = [UIColor colorWithRed:.12 green:.10 blue:.20 alpha:1];
    _controllerLabel.superlayer.backgroundColor = (self.controllerSelected ? highlight : normal).CGColor;
    for (NSInteger i = 0; i < VisibleRows; ++i) {
        CATextLayer *label = _rows[i];
        CALayer *row = label.superlayer;
        NSInteger index = first + i;
        row.hidden = index >= (NSInteger)_games.count;
        if (!row.hidden) {
            ATVSNESGameEntry *game = _games[index];
            label.string = [game.romURL isEqual:self.suspendedROM] ?
                [game.title stringByAppendingString:@"  •  Paused"] : game.title;
            row.backgroundColor = (index == _selected ? highlight : normal).CGColor;
        }
    }
    [CATransaction commit];
}

- (void)showError:(NSString *)message
{
    _message.string = message;
}

- (void)showBluetoothStatus:(NSString *)message
{
    _bluetoothStatus.string = message;
}
@end
