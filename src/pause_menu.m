#import <UIKit/UIKit.h>
#import "pause_menu.h"

enum { VisibleRows = 6, RowSpacing = 51, RowHeight = 46 };

static CATextLayer *Label(CALayer *layer, CGRect frame, CGFloat size, UIColor *color)
{
    CATextLayer *label = [CATextLayer layer];
    label.frame = frame;
    label.fontSize = size;
    label.foregroundColor = color.CGColor;
    label.truncationMode = kCATruncationEnd;
    [layer addSublayer:label];
    return label;
}

@implementation ATVSNESPauseMenu {
    CALayer *_overlay, *_preview;
    CATextLayer *_title, *_detail, *_status, *_position;
    NSArray *_options, *_screenshots;
    NSString *_bluetoothStatus, *_message;
    NSMutableArray *_rows;
    NSUInteger _first;
}

- (instancetype)initInLayer:(CALayer *)screen
{
    self = [super init];
    if (!self)
        return nil;
    _overlay = [CALayer layer];
    _overlay.frame = screen.bounds;
    _overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:.60].CGColor;
    _overlay.hidden = YES;
    _overlay.zPosition = 100;
    [screen addSublayer:_overlay];

    CALayer *panel = [CALayer layer];
    panel.frame = CGRectMake(218, 87, 844, 546);
    panel.backgroundColor = [UIColor colorWithRed:.08 green:.06 blue:.15 alpha:.98].CGColor;
    panel.cornerRadius = 16;
    [_overlay addSublayer:panel];

    UIColor *white = [UIColor whiteColor];
    UIColor *muted = [UIColor colorWithRed:.78 green:.74 blue:.88 alpha:1];
    _title = Label(panel, CGRectMake(36, 24, 772, 58), 44, white);
    _detail = Label(panel, CGRectMake(36, 88, 772, 34), 24, muted);
    _status = Label(panel, CGRectMake(36, 451, 772, 54), 22, white);
    _status.wrapped = YES;
    _position = Label(panel, CGRectMake(665, 512, 143, 26), 20, muted);
    _position.alignmentMode = kCAAlignmentRight;
    _preview = [CALayer layer];
    _preview.frame = CGRectMake(462, 133, 346, 272);
    _preview.backgroundColor = [UIColor blackColor].CGColor;
    _preview.contentsGravity = kCAGravityResizeAspect;
    _preview.magnificationFilter = kCAFilterNearest;
    _preview.hidden = YES;
    [panel addSublayer:_preview];
    Label(panel, CGRectMake(36, 512, 620, 26), 20, muted).string =
        @"Up / Down   Browse     •     Select / A   Choose     •     Menu / TV Back   Back";

    _rows = [NSMutableArray arrayWithCapacity:VisibleRows];
    for (NSInteger i = 0; i < VisibleRows; ++i) {
        CALayer *row = [CALayer layer];
        row.frame = CGRectMake(36, 133 + i * RowSpacing, 772, RowHeight);
        row.cornerRadius = 9;
        [panel addSublayer:row];
        [_rows addObject:Label(row, CGRectMake(18, 5, 736, 37), 27, white)];
    }
    return self;
}

- (BOOL)isVisible { return !_overlay.hidden; }

- (void)hide
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _overlay.hidden = YES;
    [CATransaction commit];
}

- (void)showPage:(ATVSNESPausePage)page title:(NSString *)title detail:(NSString *)detail
         options:(NSArray *)options selected:(NSUInteger)selected
{
    _page = page;
    _screenshots = nil;
    _message = nil;
    _status.string = _bluetoothStatus;
    _options = [options copy];
    _selection = _options.count ? MIN(selected, _options.count - 1) : 0;
    _first = _selection / VisibleRows * VisibleRows;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _title.string = title;
    _detail.string = detail;
    _overlay.hidden = NO;
    [self redraw];
    [CATransaction commit];
}

- (void)moveSelection:(NSInteger)direction
{
    if (!_options.count)
        return;
    _selection = (NSUInteger)MAX(0, MIN((NSInteger)_selection + direction, (NSInteger)_options.count - 1));
    if (_selection < _first)
        _first = _selection;
    else if (_selection >= _first + VisibleRows)
        _first = _selection - VisibleRows + 1;
    [self redraw];
}

- (void)redraw
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    UIColor *highlight = [UIColor colorWithRed:.34 green:.23 blue:.60 alpha:1];
    UIColor *normal = [UIColor colorWithRed:.15 green:.12 blue:.23 alpha:1];
    CGFloat width = _screenshots ? 406 : 772;
    for (NSUInteger i = 0; i < VisibleRows; ++i) {
        CATextLayer *label = _rows[i];
        NSUInteger index = _first + i;
        label.superlayer.frame = CGRectMake(36, 133 + i * RowSpacing, width, RowHeight);
        label.frame = CGRectMake(18, 5, width - 36, 37);
        label.superlayer.hidden = index >= _options.count;
        if (index < _options.count) {
            label.string = _options[index];
            label.superlayer.backgroundColor = (index == _selection ? highlight : normal).CGColor;
        }
    }
    _position.string = _options.count > VisibleRows ?
        [NSString stringWithFormat:@"%lu / %lu", (unsigned long)_selection + 1, (unsigned long)_options.count] : @"";
    id imageData = _selection < _screenshots.count ? _screenshots[_selection] : nil;
    UIImage *image = [imageData isKindOfClass:[NSData class]] ? [UIImage imageWithData:imageData] : nil;
    _preview.hidden = _screenshots == nil;
    _preview.contents = image.CGImage ? (__bridge id)image.CGImage : nil;
    [CATransaction commit];
}

- (void)showBluetoothStatus:(NSString *)message
{
    _bluetoothStatus = [message copy];
    if (!_message)
        _status.string = _bluetoothStatus;
}

- (void)showMessage:(NSString *)message
{
    _message = [message copy];
    _status.string = _message ?: _bluetoothStatus;
}

- (void)showPreviews:(NSArray *)screenshots
{
    _screenshots = [screenshots copy];
    [self redraw];
}
@end
