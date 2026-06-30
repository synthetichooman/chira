#import "AppDelegate.h"
#import "ClipboardHistoryItem.h"
#import <CoreGraphics/CoreGraphics.h>

static const NSTimeInterval ChiraClipboardIngestDelay = 0.42;
static const NSTimeInterval ChiraClipboardPollingPause = 0.48;
static NSString * const ChiraMaxVisibleClipboardItemsKey = @"maxVisibleClipboardItems";
static NSString * const ChiraPreviewImageClipboardKey = @"previewImageClipboard";

@implementation AppDelegate {
    NSPanel *_panel;
    NSPanel *_settingsPanel;
    IslandView *_islandView;
    NSStatusItem *_statusItem;
    NSTimer *_pointerTimer;
    NSTimer *_clipboardTimer;
    NSTimer *_clipboardIngestTimer;
    NSTextField *_settingsCountValueLabel;
    NSStepper *_settingsCountStepper;
    NSButton *_settingsImagePreviewCheckbox;
    NSTimeInterval _clipboardPollingResumeTime;
    NSInteger _lastClipboardChangeCount;
    NSMutableArray<ClipboardHistoryItem *> *_clipboardHistory;
    NSRect _notchHotZone;
    BOOL _panelIgnoringMouseEvents;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        ChiraMaxVisibleClipboardItemsKey: @5,
        ChiraPreviewImageClipboardKey: @NO
    }];

    [self cleanupTemporaryClipboardItems];

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
    [_clipboardIngestTimer invalidate];
}

- (void)cleanupTemporaryClipboardItems {
    NSString *directoryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ChiraClipboardItems"];
    [NSFileManager.defaultManager removeItemAtPath:directoryPath error:nil];
}

- (void)setupPanel {
    NSSize panelSize = NSMakeSize(560, 440);
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
    _panelIgnoringMouseEvents = YES;
    _panel.level = CGWindowLevelForKey(kCGStatusWindowLevelKey);
    _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorFullScreenAuxiliary |
        NSWindowCollectionBehaviorStationary |
        NSWindowCollectionBehaviorIgnoresCycle;

    _islandView = [[IslandView alloc] initWithFrame:NSMakeRect(0, 0, panelSize.width, panelSize.height)];
    _islandView.delegate = self;
    _islandView.maxVisibleClipboardItems = [self maxVisibleClipboardItems];
    _islandView.showsImageClipboardPreviews = [self showsImageClipboardPreviews];
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
    if (_panelIgnoringMouseEvents) {
        _panel.ignoresMouseEvents = NO;
        _panelIgnoringMouseEvents = NO;
    }
    [_islandView setMode:ChiraIslandModeClipboard transientDuration:1.4];
}

- (NSInteger)maxVisibleClipboardItems {
    NSInteger value = [NSUserDefaults.standardUserDefaults integerForKey:ChiraMaxVisibleClipboardItemsKey];
    return MAX(1, MIN(8, value > 0 ? value : 5));
}

- (BOOL)showsImageClipboardPreviews {
    return [NSUserDefaults.standardUserDefaults boolForKey:ChiraPreviewImageClipboardKey];
}

- (NSTextField *)settingsLabelWithString:(NSString *)string frame:(NSRect)frame {
    NSTextField *label = [NSTextField labelWithString:string];
    label.frame = frame;
    label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    label.textColor = NSColor.secondaryLabelColor;
    return label;
}

- (NSTextField *)settingsValueLabelWithString:(NSString *)string frame:(NSRect)frame {
    NSTextField *label = [NSTextField labelWithString:string];
    label.frame = frame;
    label.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightSemibold];
    label.alignment = NSTextAlignmentCenter;
    label.textColor = NSColor.labelColor;
    return label;
}

- (void)setupSettingsPanelIfNeeded {
    if (_settingsPanel) return;

    NSSize panelSize = NSMakeSize(300, 206);
    _settingsPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, panelSize.width, panelSize.height)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    _settingsPanel.title = @"Chira Settings";
    _settingsPanel.releasedWhenClosed = NO;
    _settingsPanel.hidesOnDeactivate = NO;
    _settingsPanel.opaque = YES;
    _settingsPanel.backgroundColor = NSColor.windowBackgroundColor;
    _settingsPanel.hasShadow = YES;
    _settingsPanel.ignoresMouseEvents = NO;
    _settingsPanel.movableByWindowBackground = NO;
    _settingsPanel.level = NSFloatingWindowLevel;
    _settingsPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorFullScreenAuxiliary |
        NSWindowCollectionBehaviorStationary;

    NSView *contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, panelSize.width, panelSize.height)];
    contentView.wantsLayer = YES;
    contentView.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    _settingsPanel.contentView = contentView;

    NSTextField *title = [NSTextField labelWithString:@"Chira"];
    title.frame = NSMakeRect(20, 168, 180, 22);
    title.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    title.textColor = NSColor.labelColor;
    [contentView addSubview:title];

    NSTextField *subtitle = [NSTextField labelWithString:@"Clipboard island settings"];
    subtitle.frame = NSMakeRect(20, 149, 210, 18);
    subtitle.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    subtitle.textColor = NSColor.secondaryLabelColor;
    [contentView addSubview:subtitle];

    [contentView addSubview:[self settingsLabelWithString:@"Visible clipboard items" frame:NSMakeRect(20, 116, 170, 18)]];

    _settingsCountValueLabel = [self settingsValueLabelWithString:@"" frame:NSMakeRect(202, 114, 28, 22)];
    [contentView addSubview:_settingsCountValueLabel];

    _settingsCountStepper = [[NSStepper alloc] initWithFrame:NSMakeRect(242, 110, 18, 28)];
    _settingsCountStepper.minValue = 1;
    _settingsCountStepper.maxValue = 8;
    _settingsCountStepper.increment = 1;
    _settingsCountStepper.target = self;
    _settingsCountStepper.action = @selector(settingsCountStepperChanged:);
    [contentView addSubview:_settingsCountStepper];

    _settingsImagePreviewCheckbox = [NSButton checkboxWithTitle:@"Show image previews on hover"
                                                         target:self
                                                         action:@selector(settingsImagePreviewChanged:)];
    _settingsImagePreviewCheckbox.frame = NSMakeRect(16, 80, 260, 24);
    _settingsImagePreviewCheckbox.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    [contentView addSubview:_settingsImagePreviewCheckbox];

    NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(20, 62, 260, 1)];
    divider.boxType = NSBoxCustom;
    divider.transparent = NO;
    divider.fillColor = NSColor.separatorColor;
    [contentView addSubview:divider];

    [contentView addSubview:[self settingsLabelWithString:@"Developer: kimminpyo" frame:NSMakeRect(20, 34, 240, 18)]];

    NSTextField *github = [self settingsLabelWithString:@"GitHub: synthetichooman/chira" frame:NSMakeRect(20, 12, 250, 18)];
    github.selectable = YES;
    [contentView addSubview:github];
}

- (void)refreshSettingsPanelValues {
    NSInteger count = [self maxVisibleClipboardItems];
    _settingsCountStepper.integerValue = count;
    _settingsCountValueLabel.stringValue = [NSString stringWithFormat:@"%ld", (long)count];
    _settingsImagePreviewCheckbox.state = [self showsImageClipboardPreviews]
        ? NSControlStateValueOn
        : NSControlStateValueOff;
}

- (void)showSettingsPanel {
    [self setupSettingsPanelIfNeeded];
    [self refreshSettingsPanelValues];

    NSScreen *screen = _panel.screen ?: NSScreen.mainScreen;
    NSRect visibleFrame = screen.visibleFrame;
    NSSize size = _settingsPanel.frame.size;
    CGFloat x = NSMidX(visibleFrame) - size.width / 2.0;
    CGFloat y = NSMidY(visibleFrame) - size.height / 2.0;
    [_settingsPanel setFrame:NSMakeRect(x, y, size.width, size.height) display:YES];
    [NSApp activateIgnoringOtherApps:YES];
    [_settingsPanel makeKeyAndOrderFront:nil];
}

- (void)toggleSettingsPanel {
    if (_settingsPanel.isVisible) {
        [_settingsPanel orderOut:nil];
        return;
    }

    [self showSettingsPanel];
}

- (void)settingsCountStepperChanged:(NSStepper *)sender {
    NSInteger count = MAX(1, MIN(8, sender.integerValue));
    [NSUserDefaults.standardUserDefaults setInteger:count forKey:ChiraMaxVisibleClipboardItemsKey];
    _islandView.maxVisibleClipboardItems = count;
    [self refreshSettingsPanelValues];
    [_islandView setNeedsDisplay:YES];
}

- (void)settingsImagePreviewChanged:(NSButton *)sender {
    BOOL enabled = sender.state == NSControlStateValueOn;
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:ChiraPreviewImageClipboardKey];
    _islandView.showsImageClipboardPreviews = enabled;
    if (!enabled) {
        [self clearImagePreviewCaches];
    }
    [_islandView setNeedsDisplay:YES];
}

- (void)clearImagePreviewCaches {
    for (ClipboardHistoryItem *item in _clipboardHistory) {
        if (!item.image) continue;
        item.previewImage = nil;
        item.thumbnailImage = nil;
    }
}

- (void)closeSettingsPanel:(id)sender {
    (void)sender;
    [_settingsPanel orderOut:nil];
}

- (NSScreen *)builtInScreen {
    for (NSScreen *screen in NSScreen.screens) {
        NSNumber *screenNumber = screen.deviceDescription[@"NSScreenNumber"];
        CGDirectDisplayID displayID = (CGDirectDisplayID)screenNumber.unsignedIntValue;
        if (displayID != 0 && CGDisplayIsBuiltin(displayID)) {
            return screen;
        }
    }
    return NSScreen.mainScreen;
}

- (void)recenterIsland {
    NSScreen *screen = [self builtInScreen];

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
    if (NSDate.timeIntervalSinceReferenceDate < _clipboardPollingResumeTime) return;

    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    NSInteger changeCount = pasteboard.changeCount;
    if (changeCount == _lastClipboardChangeCount) return;

    _lastClipboardChangeCount = changeCount;
    _clipboardPollingResumeTime = NSDate.timeIntervalSinceReferenceDate + ChiraClipboardPollingPause;
    if (!_panel.isVisible) {
        [_panel orderFrontRegardless];
    }
    [_islandView playClipboardIngestPulse];

    [_clipboardIngestTimer invalidate];
    _clipboardIngestTimer = [NSTimer scheduledTimerWithTimeInterval:ChiraClipboardIngestDelay
                                                             target:self
                                                           selector:@selector(ingestClipboardAfterPulse)
                                                           userInfo:nil
                                                            repeats:NO];
}

- (void)ingestClipboardAfterPulse {
    _clipboardIngestTimer = nil;

    ClipboardHistoryItem *item = [ClipboardHistoryItem itemFromPasteboard:NSPasteboard.generalPasteboard
                                                          preparesPreview:[self showsImageClipboardPreviews]];
    if (!item) return;

    [self addClipboardHistoryItem:item];
}

- (void)syncModules {
    NSUInteger count = _clipboardHistory.count;
    NSString *subtitle = count == 0
        ? @"No recent items"
        : [NSString stringWithFormat:@"%lu recent item%@", (unsigned long)count, count == 1 ? @"" : @"s"];

    IslandModule *clipboardModule = [IslandModule moduleWithIdentifier:ChiraModuleIdentifierClipboard
                                                                  title:@"Clipboard"
                                                               subtitle:subtitle
                                                                  items:[_clipboardHistory copy]
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

    BOOL shouldIgnoreMouseEvents = !overIsland;
    if (_panelIgnoringMouseEvents != shouldIgnoreMouseEvents) {
        _panel.ignoresMouseEvents = shouldIgnoreMouseEvents;
        _panelIgnoringMouseEvents = shouldIgnoreMouseEvents;
    }
    if (_islandView.hovering != overIsland) {
        _islandView.hovering = overIsland;
    }
    if (_islandView.pointerNearNotch != inHotZone) {
        _islandView.pointerNearNotch = inHotZone;
    }

    if (inHotZone) {
        if (!_panel.isVisible) {
            [_panel orderFrontRegardless];
        }
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
        ClipboardHistoryItem *item = [ClipboardHistoryItem itemFromPasteboard:NSPasteboard.generalPasteboard
                                                              preparesPreview:[self showsImageClipboardPreviews]];
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

- (void)islandViewDidRequestSettings:(IslandView *)view {
    (void)view;
    [self toggleSettingsPanel];
}

@end
