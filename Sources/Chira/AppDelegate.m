#import "AppDelegate.h"
#import "ClipboardHistoryItem.h"

static const NSTimeInterval ChiraClipboardRevealDelay = 0.34;

@implementation AppDelegate {
    NSPanel *_panel;
    IslandView *_islandView;
    NSStatusItem *_statusItem;
    NSTimer *_pointerTimer;
    NSTimer *_clipboardTimer;
    NSTimer *_clipboardRevealTimer;
    NSInteger _lastClipboardChangeCount;
    NSMutableArray<ClipboardHistoryItem *> *_clipboardHistory;
    NSRect _notchHotZone;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    _clipboardHistory = [NSMutableArray array];
    [self setupPanel];
    [self setupStatusItem];

    _lastClipboardChangeCount = NSPasteboard.generalPasteboard.changeCount;
    [self syncModules];

    _pointerTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0
                                                     target:self
                                                   selector:@selector(pointerTimerTick)
                                                   userInfo:nil
                                                    repeats:YES];
    _clipboardTimer = [NSTimer scheduledTimerWithTimeInterval:0.2
                                                       target:self
                                                     selector:@selector(clipboardTimerTick)
                                                     userInfo:nil
                                                      repeats:YES];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(recenterIsland)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:nil];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [_pointerTimer invalidate];
    [_clipboardTimer invalidate];
    [_clipboardRevealTimer invalidate];
}

- (void)setupPanel {
    NSSize panelSize = NSMakeSize(560, 280);
    _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, panelSize.width, panelSize.height)
                                        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    _panel.hasShadow = NO;
    _panel.hidesOnDeactivate = NO;
    _panel.movable = NO;
    _panel.ignoresMouseEvents = YES;
    _panel.level = CGWindowLevelForKey(kCGStatusWindowLevelKey);
    _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorFullScreenAuxiliary |
        NSWindowCollectionBehaviorStationary |
        NSWindowCollectionBehaviorIgnoresCycle;

    _islandView = [[IslandView alloc] initWithFrame:NSMakeRect(0, 0, panelSize.width, panelSize.height)];
    _islandView.delegate = self;
    _panel.contentView = _islandView;

    [self recenterIsland];
    [_panel orderFrontRegardless];
}

- (void)setupStatusItem {
    _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.button.image = [NSImage imageWithSystemSymbolName:@"capsule.tophalf.filled" accessibilityDescription:@"Chira"];
    _statusItem.button.imagePosition = NSImageOnly;

    NSMenu *menu = [NSMenu new];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Show Chira" action:@selector(showIsland) keyEquivalent:@""]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Recenter" action:@selector(recenterIsland) keyEquivalent:@""]];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Save Clipboard Text" action:@selector(saveClipboardText) keyEquivalent:@""]];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(quit) keyEquivalent:@"q"]];
    _statusItem.menu = menu;
}

- (void)showIsland {
    [_panel orderFrontRegardless];
    _panel.ignoresMouseEvents = NO;
    [_islandView setMode:ChiraIslandModeClipboard transientDuration:1.4];
}

- (void)recenterIsland {
    NSScreen *screen = NSScreen.mainScreen;
    NSPoint mouse = NSEvent.mouseLocation;
    for (NSScreen *candidate in NSScreen.screens) {
        if (NSPointInRect(mouse, candidate.frame)) {
            screen = candidate;
            break;
        }
    }

    NSSize size = _panel.frame.size;
    NSEdgeInsets safeInsets = screen.safeAreaInsets;
    NSRect topLeftArea = screen.auxiliaryTopLeftArea;
    NSRect topRightArea = screen.auxiliaryTopRightArea;
    BOOL hasNotchDeadZone = !NSIsEmptyRect(topLeftArea) && !NSIsEmptyRect(topRightArea);

    CGFloat anchorX = NSMidX(screen.frame);
    CGFloat notchWidth = 0;
    if (hasNotchDeadZone) {
        CGFloat notchMinX = NSMaxX(topLeftArea);
        CGFloat notchMaxX = NSMinX(topRightArea);
        if (notchMaxX > notchMinX) {
            notchWidth = notchMaxX - notchMinX;
            anchorX = (notchMinX + notchMaxX) / 2.0;
        }
    }

    _islandView.notchWidth = notchWidth;
    _islandView.topSafeInset = hasNotchDeadZone ? safeInsets.top : 0;
    _islandView.hasNotch = hasNotchDeadZone;
    [_islandView setNeedsDisplay:YES];

    CGFloat x = anchorX - size.width / 2.0;
    CGFloat y = NSMaxY(screen.frame) - size.height;
    [_panel setFrame:NSMakeRect(x, y, size.width, size.height) display:YES];

    CGFloat hotPadding = 8;
    CGFloat hotWidth = hasNotchDeadZone ? MAX(notchWidth + hotPadding * 2, 1) : 180;
    CGFloat hotHeight = hasNotchDeadZone ? MAX(safeInsets.top + hotPadding, 1) : 34;
    _notchHotZone = NSMakeRect(anchorX - hotWidth / 2.0, NSMaxY(screen.frame) - hotHeight, hotWidth, hotHeight);
}

- (void)quit {
    [NSApp terminate:nil];
}

- (void)clipboardTimerTick {
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    NSInteger changeCount = pasteboard.changeCount;
    if (changeCount == _lastClipboardChangeCount) return;

    _lastClipboardChangeCount = changeCount;
    ClipboardHistoryItem *item = [ClipboardHistoryItem itemFromPasteboard:pasteboard];
    if (!item) return;

    [self addClipboardHistoryItem:item];
    [_panel orderFrontRegardless];
    [_islandView playClipboardIngestPulse];

    [_clipboardRevealTimer invalidate];
    _clipboardRevealTimer = [NSTimer scheduledTimerWithTimeInterval:ChiraClipboardRevealDelay
                                                             target:self
                                                           selector:@selector(revealClipboardIslandAfterPulse)
                                                           userInfo:nil
                                                            repeats:NO];
}

- (void)revealClipboardIslandAfterPulse {
    _clipboardRevealTimer = nil;
    [_islandView setMode:ChiraIslandModeClipboard transientDuration:2.3];
}

- (void)syncModules {
    NSUInteger count = _clipboardHistory.count;
    NSString *subtitle = count == 0
        ? @"No recent items"
        : [NSString stringWithFormat:@"%lu recent item%@", (unsigned long)count, count == 1 ? @"" : @"s"];

    NSMutableArray<NSString *> *displayItems = [NSMutableArray array];
    for (ClipboardHistoryItem *item in _clipboardHistory) {
        [displayItems addObject:item.displayText ?: @""];
    }

    IslandModule *clipboardModule = [IslandModule moduleWithIdentifier:ChiraModuleIdentifierClipboard
                                                                  title:@"Clipboard"
                                                               subtitle:subtitle
                                                                  items:displayItems
                                                            accentColor:NSColor.systemGreenColor
                                                                  style:(count > 0 ? ChiraModuleStyleList : ChiraModuleStyleDefault)
                                                               progress:0];

    _islandView.modules = @[clipboardModule];
    [_islandView setNeedsDisplay:YES];
}

- (void)pointerTimerTick {
    NSPoint mouse = NSEvent.mouseLocation;
    BOOL inHotZone = !NSIsEmptyRect(_notchHotZone) && NSPointInRect(mouse, _notchHotZone);
    NSPoint windowPoint = [_panel convertPointFromScreen:mouse];
    NSPoint localPoint = [_islandView convertPoint:windowPoint fromView:nil];
    BOOL overIsland = [_islandView containsInteractivePoint:localPoint];

    _panel.ignoresMouseEvents = !overIsland;
    _islandView.hovering = overIsland;
    _islandView.pointerNearNotch = inHotZone;

    if (inHotZone) {
        [_panel orderFrontRegardless];
        if (_islandView.mode == ChiraIslandModeIdle) {
            [self showRememberedIslandMode];
        }
    } else if (!overIsland && _islandView.mode == ChiraIslandModeClipboard) {
        [_islandView setMode:ChiraIslandModeIdle transientDuration:0];
    }
}

- (NSString *)capturesDirectoryPath {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [documents stringByAppendingPathComponent:@"Chira Captures"];
}

- (NSString *)timestampString {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyy-MM-dd_HH-mm-ss";
    return [formatter stringFromDate:NSDate.date];
}

- (void)showRememberedIslandMode {
    if (_clipboardHistory.count == 0) {
        ClipboardHistoryItem *item = [ClipboardHistoryItem itemFromPasteboard:NSPasteboard.generalPasteboard];
        if (item) {
            [self addClipboardHistoryItem:item];
        }
    }

    [self syncModules];
    [_islandView setMode:ChiraIslandModeClipboard transientDuration:0];
}

- (void)addClipboardHistoryItem:(ClipboardHistoryItem *)item {
    if (!item) return;

    for (NSInteger index = (NSInteger)_clipboardHistory.count - 1; index >= 0; index--) {
        if ([_clipboardHistory[index] matchesItem:item]) {
            [_clipboardHistory removeObjectAtIndex:index];
        }
    }
    [_clipboardHistory insertObject:item atIndex:0];

    while (_clipboardHistory.count > 8) {
        [_clipboardHistory removeLastObject];
    }

    _islandView.clipboardSummary = item.displayText ?: @"Clipboard updated";
    NSMutableArray<NSString *> *displayItems = [NSMutableArray array];
    for (ClipboardHistoryItem *historyItem in _clipboardHistory) {
        [displayItems addObject:historyItem.displayText ?: @""];
    }
    _islandView.clipboardItems = displayItems;
    [self syncModules];
}

- (void)saveClipboardText {
    NSString *text = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
    if (!text.length) {
        [self addClipboardHistoryItem:[ClipboardHistoryItem textItemWithString:@"No text on clipboard"]];
        [_islandView setMode:ChiraIslandModeClipboard transientDuration:1.8];
        return;
    }

    NSString *directory = [self capturesDirectoryPath];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *filename = [NSString stringWithFormat:@"clipboard-%@.txt", [self timestampString]];
    NSString *path = [directory stringByAppendingPathComponent:filename];
    NSError *error = nil;
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];

    [self addClipboardHistoryItem:[ClipboardHistoryItem textItemWithString:(error ? @"Could not save clipboard" : filename)]];
    [_panel orderFrontRegardless];
    [_islandView setMode:ChiraIslandModeClipboard transientDuration:2.2];
}

- (void)islandView:(IslandView *)view didSelectClipboardItemAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_clipboardHistory.count) return;

    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    ClipboardHistoryItem *item = _clipboardHistory[index];
    [item writeToPasteboard:pasteboard];
    _lastClipboardChangeCount = pasteboard.changeCount;
    _islandView.clipboardSummary = item.image ? @"Copied image" : @"Copied item";

    [_panel orderFrontRegardless];
    [_islandView setMode:ChiraIslandModeClipboard transientDuration:1.8];
}

@end
