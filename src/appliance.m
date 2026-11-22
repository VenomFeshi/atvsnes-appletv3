#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

#include "libretro.h"
#include "ble_protocol.h"
#import "ble_client.h"
#import "menu.h"
#import "pause_menu.h"
#import "playback.h"
#import "state_store.h"

// The legacy AppleTV process registers these BackRow classes at runtime.
@interface NSObject (ATVSNESBackRow)
- (id)categoryWithName:(id)name identifier:(id)identifier preferredOrder:(float)order;
- (int)remoteAction;
- (id)stack;
- (id)controllers;
- (void)popController;
@end

static Class RegisterSubclass(const char *name, Class base, Class methods)
{
    if (!base)
        return Nil;
    Class cls = objc_allocateClassPair(base, name, 0);
    if (!cls)
        return Nil;
    unsigned count = 0;
    Method *list = class_copyMethodList(methods, &count);
    for (unsigned i = 0; i < count; ++i)
        class_addMethod(cls, method_getName(list[i]), method_getImplementation(list[i]),
                        method_getTypeEncoding(list[i]));
    free(list);
    objc_registerClassPair(cls);
    return cls;
}

static Class ControllerClass;
static char ScreenKey, MenuKey, PlaybackKey, BluetoothKey, BluetoothMaskKey;
static char PauseMenuKey, CurrentGameKey, ChoicesKey, SwitchGameKey, SwitchFromLibraryKey, SelectTimeKey;
static char StateStoreKey, StateSlotKey, ControllersFromLibraryKey;

enum { PauseResume, PauseStates, PauseAspect, PauseChangeGame, PauseControllers, PauseLibrary };
enum { PairController1, PairController2, CancelPairing };

static NSUserDefaults *DisplayDefaults(void)
{
    static NSUserDefaults *settings;
    if (!settings)
        settings = [[NSUserDefaults alloc] initWithSuiteName:@"org.atvsnes.settings"];
    return settings;
}

static NSString * const WidescreenKey = @"Widescreen";
static NSString * const AspectKey = @"AspectRatio";

static NSArray *DisplayModes(void)
{
    return @[@"Original 4:3", @"Widescreen 16:9 (stretch)", @"Square Pixels (usually 8:7)",
             @"3:2", @"16:10"];
}

static ATVSNESAspect SavedAspect(void)
{
    NSUserDefaults *settings = DisplayDefaults();
    if (![settings objectForKey:AspectKey])
        return [settings boolForKey:WidescreenKey] ? ATVSNESAspectWide : ATVSNESAspectOriginal;
    NSInteger value = [settings integerForKey:AspectKey];
    return value >= 0 && value < ATVSNESAspectCount ? (ATVSNESAspect)value : ATVSNESAspectOriginal;
}

@interface ATVSNESControllerMethods : NSObject
- (void)atvsnesAttach;
- (void)atvsnesLayout;
- (void)atvsnesLaunch:(ATVSNESGameEntry *)game;
- (void)atvsnesChooseLibraryGame;
- (void)atvsnesStop;
- (void)atvsnesBack;
- (void)atvsnesBluetoothInput:(uint16_t)buttons player:(unsigned)player;
- (void)atvsnesShowControllersFromLibrary:(BOOL)fromLibrary;
- (void)atvsnesPairController:(unsigned)player;
- (void)atvsnesShowPause;
- (void)atvsnesResume;
- (void)atvsnesHandleMenuButton:(unsigned)button value:(int)value fromRemote:(BOOL)remote;
- (void)atvsnesConfirmSwitch:(ATVSNESGameEntry *)game fromLibrary:(BOOL)fromLibrary;
- (void)atvsnesSelectPause;
- (void)atvsnesShowStates:(NSUInteger)selected;
- (void)atvsnesShowSlotActions;
- (void)atvsnesSaveState;
@end

static void CallSuperVoid(id controller, SEL method)
{
    Class base = class_getSuperclass(ControllerClass);
    if (class_getInstanceMethod(base, method)) {
        struct objc_super target = { controller, base };
        ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&target, method);
    }
}

@implementation ATVSNESControllerMethods
- (void)atvsnesAttach
{
    UIView *view = (UIView *)self;
    view.backgroundColor = [UIColor blackColor];
    CALayer *screen = [CALayer layer];
    screen.bounds = CGRectMake(0, 0, 1280, 720);
    screen.geometryFlipped = YES;
    ATVSNESMenu *menu = [[ATVSNESMenu alloc] initInLayer:screen];
    [view.layer addSublayer:screen];
    objc_setAssociatedObject(self, &ScreenKey, screen, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &MenuKey, menu, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ATVSNESPauseMenu *pause = [[ATVSNESPauseMenu alloc] initInLayer:screen];
    objc_setAssociatedObject(self, &PauseMenuKey, pause, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self atvsnesLayout];
}

- (void)atvsnesLayout
{
    CALayer *screen = objc_getAssociatedObject(self, &ScreenKey);
    CGRect bounds = ((UIView *)self).bounds;
    if (!screen || CGRectIsEmpty(bounds))
        return;
    CGFloat scale = MIN(bounds.size.width / 1280, bounds.size.height / 720);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    screen.position = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    screen.transform = CATransform3DMakeScale(scale, scale, 1);
    [CATransaction commit];
}

- (void)layoutSubcontrols
{
    CallSuperVoid(self, _cmd);
    [self atvsnesLayout];
}

- (void)atvsnesLaunch:(ATVSNESGameEntry *)game
{
    ATVSNESMenu *menu = objc_getAssociatedObject(self, &MenuKey);
    if (!game)
        return;
    CALayer *screen = objc_getAssociatedObject(self, &ScreenKey);
    ATVSNESPlayback *playback = [[ATVSNESPlayback alloc] init];
    playback.aspect = SavedAspect();
    NSString *error = [playback startInLayer:screen romURL:game.romURL saveURL:game.saveURL];
    if (error) {
        [menu showError:error];
        NSLog(@"ATVSNES: %@", error);
        return;
    }
    objc_setAssociatedObject(self, &PlaybackKey, playback, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &CurrentGameKey, game, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSURL *saves = [game.saveURL URLByDeletingLastPathComponent];
    ATVSNESStateStore *store = [[ATVSNESStateStore alloc] initInSavesDirectory:saves romID:playback.romID];
    objc_setAssociatedObject(self, &StateStoreKey, store, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [menu setSuspendedROM:game.romURL];
    NSLog(@"ATVSNES: started %@", game.title);
}

- (void)atvsnesChooseLibraryGame
{
    ATVSNESMenu *menu = objc_getAssociatedObject(self, &MenuKey);
    if (menu.controllerSelected) {
        [self atvsnesShowControllersFromLibrary:YES];
        return;
    }
    ATVSNESGameEntry *game = menu.selectedGame;
    if (!game)
        return;
    ATVSNESGameEntry *current = objc_getAssociatedObject(self, &CurrentGameKey);
    if (!current)
        [self atvsnesLaunch:game];
    else if ([current.romURL isEqual:game.romURL])
        [self atvsnesResume];
    else
        [self atvsnesConfirmSwitch:game fromLibrary:YES];
}

- (void)atvsnesStop
{
    [objc_getAssociatedObject(self, &PauseMenuKey) hide];
    [objc_getAssociatedObject(self, &PlaybackKey) stop];
    objc_setAssociatedObject(self, &PlaybackKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &CurrentGameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &StateStoreKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &StateSlotKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &ChoicesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &SwitchGameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [objc_getAssociatedObject(self, &MenuKey) setSuspendedROM:nil];
}

- (void)atvsnesShowPause
{
    ATVSNESPlayback *playback = objc_getAssociatedObject(self, &PlaybackKey);
    if (!playback)
        return;
    playback.paused = YES;
    [playback setVideoHidden:NO];
    ATVSNESPauseMenu *pause = objc_getAssociatedObject(self, &PauseMenuKey);
    ATVSNESGameEntry *current = objc_getAssociatedObject(self, &CurrentGameKey);
    NSString *display = [@"Display: " stringByAppendingString:DisplayModes()[playback.aspect]];
    [pause showPage:ATVSNESPauseActions title:@"Game Paused" detail:current.title
             options:@[@"Resume Game", @"Save States", display, @"Change Game", @"Bluetooth Controllers",
                       @"Return to Library"] selected:PauseResume];
}

- (void)atvsnesResume
{
    [objc_getAssociatedObject(self, &PauseMenuKey) hide];
    ATVSNESPlayback *playback = objc_getAssociatedObject(self, &PlaybackKey);
    [playback setVideoHidden:NO];
    playback.paused = NO;
}

- (void)atvsnesConfirmSwitch:(ATVSNESGameEntry *)game fromLibrary:(BOOL)fromLibrary
{
    objc_setAssociatedObject(self, &SwitchGameKey, game, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &SwitchFromLibraryKey, @(fromLibrary), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ATVSNESPauseMenu *pause = objc_getAssociatedObject(self, &PauseMenuKey);
    [pause showPage:ATVSNESPauseConfirmSwitch title:@"Switch games?" detail:game.title
             options:@[@"Keep Current Game", @"Switch Game (unsaved progress is lost)"] selected:0];
}

- (void)atvsnesShowGameChoices
{
    ATVSNESMenu *menu = objc_getAssociatedObject(self, &MenuKey);
    [menu reload];
    NSArray *games = menu.games ?: @[];
    objc_setAssociatedObject(self, &ChoicesKey, games, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ATVSNESGameEntry *current = objc_getAssociatedObject(self, &CurrentGameKey);
    NSMutableArray *titles = [NSMutableArray arrayWithCapacity:games.count];
    NSUInteger selection = 0;
    for (ATVSNESGameEntry *game in games) {
        if ([game.romURL isEqual:current.romURL]) {
            selection = titles.count;
            [titles addObject:[game.title stringByAppendingString:@"  •  Resume"]];
        } else {
            [titles addObject:game.title];
        }
    }
    ATVSNESPauseMenu *pause = objc_getAssociatedObject(self, &PauseMenuKey);
    [pause showPage:ATVSNESPauseGames title:@"Change Game"
              detail:games.count ? @"Choose a title. Your current game stays paused until you switch." :
                                   @"No games found in the library."
             options:titles selected:selection];
}

- (void)atvsnesDismissSwitch
{
    NSNumber *fromLibrary = objc_getAssociatedObject(self, &SwitchFromLibraryKey);
    objc_setAssociatedObject(self, &SwitchGameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (fromLibrary.boolValue)
        [objc_getAssociatedObject(self, &PauseMenuKey) hide];
    else
        [self atvsnesShowGameChoices];
}

- (void)atvsnesShowStates:(NSUInteger)selected
{
    ATVSNESPauseMenu *pause = objc_getAssociatedObject(self, &PauseMenuKey);
    ATVSNESStateStore *store = objc_getAssociatedObject(self, &StateStoreKey);
    NSMutableArray *titles = [NSMutableArray array], *previews = [NSMutableArray array];
    for (NSUInteger i = 0; i < ATVSNESStateSlotCount; ++i) {
        ATVSNESStoredState *state = [store stateInSlot:i];
        NSString *status = state ? @"Saved" : ([store hasFileInSlot:i] ? @"Unavailable" : @"Empty");
        [titles addObject:[NSString stringWithFormat:@"Slot %lu  •  %@", (unsigned long)i + 1, status]];
        [previews addObject:state ? state.screenshot : [NSNull null]];
    }
    [pause showPage:ATVSNESPauseStates title:@"Save States"
              detail:@"Choose one of this game's two slots."
             options:titles selected:selected];
    [pause showPreviews:previews];
}

- (void)atvsnesShowSlotActions
{
    ATVSNESPauseMenu *pause = objc_getAssociatedObject(self, &PauseMenuKey);
    ATVSNESStateStore *store = objc_getAssociatedObject(self, &StateStoreKey);
    NSNumber *selection = objc_getAssociatedObject(self, &StateSlotKey);
    NSUInteger slot = selection.unsignedIntegerValue;
    ATVSNESStoredState *state = [store stateInSlot:slot];
    NSString *title = [NSString stringWithFormat:@"Slot %lu", (unsigned long)slot + 1];
    NSString *detail = state ? [NSDateFormatter localizedStringFromDate:state.date
                    dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle] :
                    ([store hasFileInSlot:slot] ? @"This state is damaged or from an incompatible build." :
                                                 @"No state saved here yet.");
    [pause showPage:ATVSNESPauseStateActions title:title detail:detail
             options:state ? @[@"Load State", @"Save State"] : @[@"Save State"] selected:0];
    if (state) {
        [pause showPreviews:@[state.screenshot, state.screenshot]];
        [pause showMessage:@"Loading replaces your current progress."];
    }
}

- (void)atvsnesSaveState
{
    ATVSNESPlayback *playback = objc_getAssociatedObject(self, &PlaybackKey);
    ATVSNESStateStore *store = objc_getAssociatedObject(self, &StateStoreKey);
    NSNumber *selection = objc_getAssociatedObject(self, &StateSlotKey);
    NSUInteger slot = selection.unsignedIntegerValue;
    NSData *image = [playback captureScreenshot];
    BOOL saved = image && [store writeCore:[playback captureState] screenshot:image slot:slot];
    [self atvsnesShowStates:slot];
    ATVSNESPauseMenu *pause = objc_getAssociatedObject(self, &PauseMenuKey);
    [pause showMessage:saved ? @"Save state created." :
                       (image ? @"Could not write the save state." : @"Resume briefly before saving the first frame.")];
}

- (void)atvsnesSelectPause
{
    ATVSNESPauseMenu *pause = objc_getAssociatedObject(self, &PauseMenuKey);
    ATVSNESPlayback *playback = objc_getAssociatedObject(self, &PlaybackKey);
    switch (pause.page) {
        case ATVSNESPauseActions:
            switch (pause.selection) {
                case PauseResume: [self atvsnesResume]; break;
                case PauseStates: [self atvsnesShowStates:0]; break;
                case PauseAspect:
                    [pause showPage:ATVSNESPauseDisplay title:@"Display"
                             detail:@"Choose a shape for the game picture. No mode crops it."
                            options:DisplayModes() selected:playback.aspect];
                    break;
                case PauseChangeGame: [self atvsnesShowGameChoices]; break;
                case PauseControllers: [self atvsnesShowControllersFromLibrary:NO]; break;
                case PauseLibrary: {
                    [pause hide];
                    [playback setVideoHidden:YES];
                    ATVSNESMenu *menu = objc_getAssociatedObject(self, &MenuKey);
                    [menu reload];
                    [menu highlightSuspendedGame];
                    break;
                }
            }
            break;
        case ATVSNESPauseDisplay:
            playback.aspect = (ATVSNESAspect)pause.selection;
            [DisplayDefaults() setInteger:playback.aspect forKey:AspectKey];
            [self atvsnesShowPause];
            break;
        case ATVSNESPauseStates:
            objc_setAssociatedObject(self, &StateSlotKey, @(pause.selection), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [self atvsnesShowSlotActions];
            break;
        case ATVSNESPauseStateActions: {
            ATVSNESStateStore *store = objc_getAssociatedObject(self, &StateStoreKey);
            NSNumber *selection = objc_getAssociatedObject(self, &StateSlotKey);
            NSUInteger slot = selection.unsignedIntegerValue;
            ATVSNESStoredState *state = [store stateInSlot:slot];
            if (state && pause.selection == 0) {
                if ([playback restoreState:state.core screenshot:state.screenshot])
                    [self atvsnesResume];
                else
                    [pause showMessage:@"Could not load this state."];
            } else if ([store hasFileInSlot:slot]) {
                [pause showPage:ATVSNESPauseConfirmOverwrite title:@"Overwrite this slot?"
                         detail:@"The previous state in this slot will be replaced."
                        options:@[@"Keep Previous State", @"Overwrite State"] selected:0];
            } else {
                [self atvsnesSaveState];
            }
            break;
        }
        case ATVSNESPauseConfirmOverwrite:
            if (pause.selection == 1)
                [self atvsnesSaveState];
            else
                [self atvsnesShowSlotActions];
            break;
        case ATVSNESPauseControllers: {
            if (pause.selection == CancelPairing) {
                ATVSNESBLEClient *link = objc_getAssociatedObject(self, &BluetoothKey);
                if (link)
                    [link cancelPairing];
                else
                    [pause showBluetoothStatus:@"No pairing in progress"];
            } else {
                [self atvsnesPairController:(unsigned)pause.selection];
            }
            break;
        }
        case ATVSNESPauseGames: {
            NSArray *games = objc_getAssociatedObject(self, &ChoicesKey);
            if (pause.selection < games.count) {
                ATVSNESGameEntry *game = games[pause.selection];
                ATVSNESGameEntry *current = objc_getAssociatedObject(self, &CurrentGameKey);
                if ([game.romURL isEqual:current.romURL])
                    [self atvsnesResume];
                else
                    [self atvsnesConfirmSwitch:game fromLibrary:NO];
            }
            break;
        }
        case ATVSNESPauseConfirmSwitch: {
            if (!pause.selection) {
                [self atvsnesDismissSwitch];
                break;
            }
            ATVSNESGameEntry *game = objc_getAssociatedObject(self, &SwitchGameKey);
            [self atvsnesStop];
            [self atvsnesLaunch:game];
            break;
        }
    }
}

- (void)atvsnesBack
{
    ATVSNESPauseMenu *pause = objc_getAssociatedObject(self, &PauseMenuKey);
    ATVSNESPlayback *playback = objc_getAssociatedObject(self, &PlaybackKey);
    if (pause.visible) {
        if (pause.page == ATVSNESPauseActions)
            [self atvsnesResume];
        else if (pause.page == ATVSNESPauseConfirmSwitch)
            [self atvsnesDismissSwitch];
        else if (pause.page == ATVSNESPauseConfirmOverwrite)
            [self atvsnesShowSlotActions];
        else if (pause.page == ATVSNESPauseStateActions) {
            NSNumber *slot = objc_getAssociatedObject(self, &StateSlotKey);
            [self atvsnesShowStates:slot.unsignedIntegerValue];
        }
        else if (pause.page == ATVSNESPauseControllers) {
            NSNumber *fromLibrary = objc_getAssociatedObject(self, &ControllersFromLibraryKey);
            if (fromLibrary.boolValue)
                [pause hide];
            else
                [self atvsnesShowPause];
        }
        else
            [self atvsnesShowPause];
    } else if (playback && !playback.paused) {
        [self atvsnesShowPause];
    } else if ([[[self stack] controllers] count] > 1) {
        [[self stack] popController];
    }
}

- (void)atvsnesBluetoothInput:(uint16_t)buttons player:(unsigned)player
{
    ATVSNESPlayback *playback = objc_getAssociatedObject(self, &PlaybackKey);
    if (player != 0) {
        [playback bluetoothButtons:buttons player:player];
        return; // Player 2 controls the game but not the SNES library.
    }
    NSNumber *previous = objc_getAssociatedObject(self, &BluetoothMaskKey);
    uint16_t pressed = buttons & ~previous.unsignedShortValue;
    objc_setAssociatedObject(self, &BluetoothMaskKey, @(buttons), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (pressed & ATVSNES_BLE_BACK) {
        [playback bluetoothButtons:buttons player:player];
        [self atvsnesBack];
        return;
    }
    [playback bluetoothButtons:buttons player:player];
    if (!playback || playback.paused) {
        if (pressed & (1u << RETRO_DEVICE_ID_JOYPAD_UP))
            [self atvsnesHandleMenuButton:RETRO_DEVICE_ID_JOYPAD_UP value:1 fromRemote:NO];
        else if (pressed & (1u << RETRO_DEVICE_ID_JOYPAD_DOWN))
            [self atvsnesHandleMenuButton:RETRO_DEVICE_ID_JOYPAD_DOWN value:1 fromRemote:NO];
        else if (pressed & ((1u << RETRO_DEVICE_ID_JOYPAD_A) | (1u << RETRO_DEVICE_ID_JOYPAD_START)))
            [self atvsnesHandleMenuButton:RETRO_DEVICE_ID_JOYPAD_A value:1 fromRemote:NO];
    }
}

- (void)atvsnesHandleMenuButton:(unsigned)button value:(int)value fromRemote:(BOOL)remote
{
    if (value <= 0)
        return;
    ATVSNESPauseMenu *pause = objc_getAssociatedObject(self, &PauseMenuKey);
    ATVSNESMenu *menu = objc_getAssociatedObject(self, &MenuKey);
    ATVSNESBLEClient *link = objc_getAssociatedObject(self, &BluetoothKey);
    if (button == RETRO_DEVICE_ID_JOYPAD_UP || button == RETRO_DEVICE_ID_JOYPAD_DOWN) {
        NSInteger delta = button == RETRO_DEVICE_ID_JOYPAD_UP ? -1 : 1;
        if (pause.visible)
            [pause moveSelection:delta];
        else
            [menu moveSelection:delta];
    } else if (button == RETRO_DEVICE_ID_JOYPAD_START && value == 1 && remote) {
        if (!pause.visible || pause.page == ATVSNESPauseActions)
            [self atvsnesShowControllersFromLibrary:!pause.visible];
    } else if (button == RETRO_DEVICE_ID_JOYPAD_A && value == 1) {
        // An Apple remote can report the same Select press under two action codes.
        double now = CACurrentMediaTime();
        NSNumber *previous = objc_getAssociatedObject(self, &SelectTimeKey);
        if (previous && now - previous.doubleValue < .20)
            return;
        objc_setAssociatedObject(self, &SelectTimeKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        BOOL choosingController = pause.visible && pause.page == ATVSNESPauseControllers;
        if (remote && link.awaitingApproval && (!choosingController || pause.selection == link.pendingPlayer))
            [link approve];
        else if (pause.visible)
            [self atvsnesSelectPause];
        else
            [self atvsnesChooseLibraryGame];
    }
}

- (void)atvsnesShowControllersFromLibrary:(BOOL)fromLibrary
{
    objc_setAssociatedObject(self, &ControllersFromLibraryKey, @(fromLibrary), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ATVSNESPauseMenu *pause = objc_getAssociatedObject(self, &PauseMenuKey);
    ATVSNESBLEClient *link = objc_getAssociatedObject(self, &BluetoothKey);
    [pause showPage:ATVSNESPauseControllers title:@"Bluetooth Controllers"
              detail:@"Set each phone to the matching player role, then start Bluetooth."
             options:@[@"Pair Controller 1", @"Pair Controller 2", @"Cancel Pairing"]
             selected:link.awaitingApproval ? link.pendingPlayer : PairController1];
}

- (void)atvsnesPairController:(unsigned)player
{
    ATVSNESBLEClient *link = objc_getAssociatedObject(self, &BluetoothKey);
    if (!link) {
        __weak ATVSNESControllerMethods *weakController = self;
        link = [[ATVSNESBLEClient alloc] initWithStatus:^(NSString *status) {
            [objc_getAssociatedObject(weakController, &MenuKey) showBluetoothStatus:status];
            [objc_getAssociatedObject(weakController, &PauseMenuKey) showBluetoothStatus:status];
        } input:^(unsigned player, uint16_t buttons) {
            [weakController atvsnesBluetoothInput:buttons player:player];
        }];
        objc_setAssociatedObject(self, &BluetoothKey, link, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [link pairPlayer:player];
}

- (void)wasPushed
{
    CallSuperVoid(self, _cmd);
    [self atvsnesLayout];
    [objc_getAssociatedObject(self, &MenuKey) reload];
}

- (void)wasExhumed
{
    CallSuperVoid(self, _cmd);
    [self atvsnesLayout];
    [objc_getAssociatedObject(self, &MenuKey) reload];
}

- (void)wasBuried
{
    [self atvsnesStop];
    [objc_getAssociatedObject(self, &BluetoothKey) stop];
    CallSuperVoid(self, _cmd);
}

- (void)wasPopped
{
    [self atvsnesStop];
    [objc_getAssociatedObject(self, &BluetoothKey) stop];
    CallSuperVoid(self, _cmd);
}

- (char)brEventAction:(id)event
{
    int action = [event remoteAction];
    int value = ((int (*)(id, SEL))objc_msgSend)(event, sel_registerName("value"));
    ATVSNESPlayback *playback = objc_getAssociatedObject(self, &PlaybackKey);
    if (action == 1) {
        if (value == 1)
            [self atvsnesBack];
        return 1;
    }
    int snesButton = -1;
    switch (action) {
        case 2: case 11: case 22: case 23:
            return 1; // don't forward long-press shortcuts to BackRow
        case 3: snesButton = RETRO_DEVICE_ID_JOYPAD_UP; break;
        case 4: snesButton = RETRO_DEVICE_ID_JOYPAD_DOWN; break;
        case 5: case 12: snesButton = RETRO_DEVICE_ID_JOYPAD_A; break;
        case 6: case 8: snesButton = RETRO_DEVICE_ID_JOYPAD_LEFT; break;
        case 7: case 9: snesButton = RETRO_DEVICE_ID_JOYPAD_RIGHT; break;
        case 10: case 15: case 16: snesButton = RETRO_DEVICE_ID_JOYPAD_START; break;
    }
    if (snesButton >= 0) {
        if (playback && !playback.paused) {
            NSNumber *lastSelect = objc_getAssociatedObject(self, &SelectTimeKey);
            if (snesButton == RETRO_DEVICE_ID_JOYPAD_A && value > 0 && lastSelect &&
                CACurrentMediaTime() - lastSelect.doubleValue < .20)
                return 1;
            [playback button:(unsigned)snesButton value:value];
        } else {
            [self atvsnesHandleMenuButton:(unsigned)snesButton value:value fromRemote:YES];
        }
        return 1;
    }
    Class base = class_getSuperclass(ControllerClass);
    if (!class_getInstanceMethod(base, _cmd))
        return 0;
    struct objc_super target = { self, base };
    return ((char (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&target, _cmd, event);
}
@end

static id MakeController(void)
{
    id controller = [[ControllerClass alloc] init];
    [controller atvsnesAttach];
    return controller;
}

@interface ATVSNESApplianceMethods : NSObject
@end

@implementation ATVSNESApplianceMethods
- (id)applianceCategories
{
    id category = [objc_getClass("BRApplianceCategory") categoryWithName:@"SNES"
                            identifier:@"atvsnes-main" preferredOrder:0.0f];
    return category ? @[category] : @[];
}

- (id)controllerForIdentifier:(id)identifier args:(id)args
{
    (void)identifier;
    (void)args;
    return MakeController();
}

- (id)applianceController { return MakeController(); }
- (id)rootController { return MakeController(); }
@end

__attribute__((constructor)) static void ATVSNESLoad(void)
{
    @autoreleasepool {
        ControllerClass = RegisterSubclass("ATVSNESController", objc_getClass("BRController"),
                                           [ATVSNESControllerMethods class]);
        Class base = objc_getClass("BRBaseAppliance");
        if (!base)
            base = objc_getClass("BRAppliance");
        if (ControllerClass && RegisterSubclass("ATVSNESAppliance", base, [ATVSNESApplianceMethods class]))
            NSLog(@"ATVSNES: registered native appliance");
    }
}
