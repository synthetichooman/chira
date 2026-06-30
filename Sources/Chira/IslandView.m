#import "IslandView.h"
#import "ClipboardHistoryItem.h"

static const CGFloat ChiraMacBookPro14NotchWidth = 210.0;
static const CGFloat ChiraFloatingHiddenWidth = 168.0;
static const CGFloat ChiraFloatingHiddenHeight = 30.0;
static const CGFloat ChiraFloatingTopMargin = 8.0;
static const CGFloat ChiraHiddenNotchCornerRadius = 11.0;
static const CGFloat ChiraIngestPulseVerticalDrop = 13.0;
static const CGFloat ChiraClipboardBaseRowHeight = 28.0;
static const CGFloat ChiraClipboardTextHoverRowHeight = 58.0;
static const CGFloat ChiraClipboardImageHoverRowHeight = 84.0;
static const CGFloat ChiraHeaderTextHeight = 18.0;
static const CGFloat ChiraHeaderButtonSize = 24.0;
static const CGFloat ChiraHeaderIconTextBaselineOffset = -13.0;
static const CGFloat ChiraClipboardRowTextHeight = 18.0;
static const CGFloat ChiraClipboardHoverTextBaselineOffset = -13.0;
static const NSTimeInterval ChiraIngestPulseDuration = 0.34;

static CGFloat ChiraSmoothStep(CGFloat value) {
    CGFloat t = MIN(1.0, MAX(0.0, value));
    return t * t * (3.0 - 2.0 * t);
}

static CGFloat ChiraIngestPulseValue(CGFloat t) {
    if (t < 0.38) {
        return ChiraSmoothStep(t / 0.38);
    }

    CGFloat fallT = (t - 0.38) / 0.62;
    CGFloat settle = 1.0 - ChiraSmoothStep(fallT);
    CGFloat rebound = 0.10 * sin(fallT * M_PI * 3.2) * (1.0 - fallT);
    return MAX(0.0, settle + rebound);
}

@implementation IslandView {
    NSTrackingArea *_trackingArea;
    NSTimer *_animationTimer;
    NSTimer *_collapseTimer;
    CGFloat _progress;
    CGFloat _targetProgress;
    CGFloat _ingestPulse;
    NSTimeInterval _ingestPulseStartTime;
    NSRect _lastInvalidatedIslandRect;
    NSInteger _pressedClipboardIndex;
    NSInteger _hoveredClipboardIndex;
    CGFloat _hoverExpansion;
    CGFloat _targetHoverExpansion;
    BOOL _pressedClipboardInside;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;

    _clipboardSummary = @"";
    _clipboardItems = @[];
    _modules = @[];
    _topSafeInset = 6;
    _notchWidth = 0;
    _hasNotch = NO;
    _maxVisibleClipboardItems = 5;
    _ingestPulse = 0;
    _lastInvalidatedIslandRect = NSZeroRect;
    _pressedClipboardIndex = -1;
    _hoveredClipboardIndex = -1;
    _hoverExpansion = 0;
    _targetHoverExpansion = 0;
    _pressedClipboardInside = NO;
    self.wantsLayer = YES;
    self.layer.backgroundColor = NSColor.clearColor.CGColor;
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                 options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseMoved:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    [self updateHoveredClipboardIndexAtPoint:point];
}

- (void)mouseExited:(NSEvent *)event {
    [self clearHoveredClipboardIndex];
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect islandRect = [self currentIslandRect];
    if (!NSPointInRect(point, islandRect)) return;

    if (NSPointInRect(point, [self settingsButtonRectInIslandRect:islandRect])) {
        [self.delegate islandViewDidRequestSettings:self];
        return;
    }

    IslandModule *module = [self displayModule];
    NSInteger index = [self clipboardItemIndexAtPoint:point forModule:module inIslandRect:islandRect];
    if (index >= 0) {
        _pressedClipboardIndex = index;
        _pressedClipboardInside = YES;
        [self invalidateIslandDisplay];
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (_pressedClipboardIndex < 0) return;

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect islandRect = [self currentIslandRect];
    IslandModule *module = [self displayModule];
    NSInteger index = [self clipboardItemIndexAtPoint:point forModule:module inIslandRect:islandRect];
    BOOL inside = index == _pressedClipboardIndex;
    if (_pressedClipboardInside != inside) {
        _pressedClipboardInside = inside;
        [self invalidateIslandDisplay];
    }
}

- (void)mouseUp:(NSEvent *)event {
    if (_pressedClipboardIndex < 0) return;

    NSInteger pressedIndex = _pressedClipboardIndex;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect islandRect = [self currentIslandRect];
    IslandModule *module = [self displayModule];
    NSInteger releaseIndex = [self clipboardItemIndexAtPoint:point forModule:module inIslandRect:islandRect];

    _pressedClipboardIndex = -1;
    _pressedClipboardInside = NO;
    [self invalidateIslandDisplay];

    if (releaseIndex == pressedIndex) {
        [self.delegate islandView:self didSelectClipboardItemAtIndex:pressedIndex];
    }
}

- (void)updateHoveredClipboardIndexAtPoint:(NSPoint)point {
    NSRect islandRect = [self currentIslandRect];
    if (!NSPointInRect(point, islandRect)) {
        [self clearHoveredClipboardIndex];
        return;
    }

    IslandModule *module = [self displayModule];
    NSInteger index = [self clipboardItemHoverIndexAtPoint:point forModule:module inIslandRect:islandRect];
    if (index < 0) {
        [self clearHoveredClipboardIndex];
        return;
    }
    if (index == _hoveredClipboardIndex) {
        if (_targetHoverExpansion < 1.0) {
            _targetHoverExpansion = 1.0;
            [self startAnimationTimerIfNeeded];
            [self invalidateIslandDisplay];
        }
        return;
    }

    _hoveredClipboardIndex = index;
    _targetHoverExpansion = 1.0;
    [self preparePreviewForHoveredClipboardItem];
    [self startAnimationTimerIfNeeded];
    [self invalidateIslandDisplay];
}

- (void)clearHoveredClipboardIndex {
    if (_hoveredClipboardIndex < 0 && _targetHoverExpansion <= 0) return;

    _targetHoverExpansion = 0;
    [self startAnimationTimerIfNeeded];
    [self invalidateIslandDisplay];
}

- (void)setMode:(ChiraIslandMode)mode transientDuration:(NSTimeInterval)duration {
    self.mode = mode;
    if (mode == ChiraIslandModeIdle) {
        _targetHoverExpansion = 0;
    }

    [_collapseTimer invalidate];
    _collapseTimer = nil;

    if (duration > 0) {
        _collapseTimer = [NSTimer scheduledTimerWithTimeInterval:duration
                                                          target:self
                                                        selector:@selector(collapseTransientMode)
                                                        userInfo:nil
                                                         repeats:NO];
    }

    [self updateTargetProgress];
    [self invalidateIslandDisplay];
}

- (void)playClipboardIngestPulse {
    _ingestPulseStartTime = NSDate.timeIntervalSinceReferenceDate;
    _ingestPulse = 0.0;

    [self startAnimationTimerIfNeeded];
    [self invalidateIslandDisplay];
}

- (void)collapseTransientMode {
    if (self.mode != ChiraIslandModeClipboard || !self.hovering) {
        self.mode = ChiraIslandModeIdle;
    }
    [self updateTargetProgress];
    [self invalidateIslandDisplay];
}

- (void)updateTargetProgress {
    _targetProgress = (self.pointerNearNotch || self.hovering || self.mode != ChiraIslandModeIdle) ? 1.0 : 0.0;
    [self startAnimationTimerIfNeeded];
}

- (void)startAnimationTimerIfNeeded {
    if (!_animationTimer) {
        _animationTimer = [NSTimer timerWithTimeInterval:1.0 / 60.0
                                                  target:self
                                                selector:@selector(animationTick)
                                                userInfo:nil
                                                 repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:_animationTimer forMode:NSRunLoopCommonModes];
    }
}

- (void)setPointerNearNotch:(BOOL)pointerNearNotch {
    if (_pointerNearNotch == pointerNearNotch) return;

    _pointerNearNotch = pointerNearNotch;
    if (!pointerNearNotch && !self.hovering && self.mode == ChiraIslandModeClipboard) {
        self.mode = ChiraIslandModeIdle;
    }
    [self updateTargetProgress];
    [self invalidateIslandDisplay];
}

- (void)invalidateIslandDisplay {
    NSRect currentRect = NSInsetRect([self currentIslandRect], -36, -36);
    currentRect = NSIntersectionRect(currentRect, self.bounds);

    if (!NSIsEmptyRect(_lastInvalidatedIslandRect)) {
        [self setNeedsDisplayInRect:_lastInvalidatedIslandRect];
    }
    if (!NSIsEmptyRect(currentRect)) {
        [self setNeedsDisplayInRect:currentRect];
    }

    _lastInvalidatedIslandRect = currentRect;
}

- (IslandModule *)displayModule {
    IslandModule *clipboardModule = self.modules.firstObject;
    if (clipboardModule) return clipboardModule;

    return [IslandModule moduleWithIdentifier:ChiraModuleIdentifierClipboard
                                        title:@"Clipboard"
                                     subtitle:@"No recent items"
                                        items:@[]
                                  accentColor:NSColor.systemGreenColor
                                        style:ChiraModuleStyleDefault
                                     progress:0];
}

- (NSInteger)visibleClipboardItemLimit {
    return MAX(1, MIN(8, self.maxVisibleClipboardItems > 0 ? self.maxVisibleClipboardItems : 5));
}

- (CGFloat)contentTopForIslandRect:(NSRect)rect {
    return NSMinY(rect) + MAX(self.topSafeInset + 12, 18);
}

- (CGFloat)contentXForIslandRect:(NSRect)rect horizontalPadding:(CGFloat)horizontalPadding {
    return NSMinX(rect) + horizontalPadding;
}

- (CGFloat)contentWidthForIslandRect:(NSRect)rect horizontalPadding:(CGFloat)horizontalPadding {
    return NSWidth(rect) - horizontalPadding * 2;
}

- (NSRect)headerTitleRectInIslandRect:(NSRect)rect horizontalPadding:(CGFloat)horizontalPadding reservesSettings:(BOOL)reservesSettings {
    CGFloat contentTop = [self contentTopForIslandRect:rect];
    CGFloat contentX = [self contentXForIslandRect:rect horizontalPadding:horizontalPadding];
    CGFloat contentWidth = [self contentWidthForIslandRect:rect horizontalPadding:horizontalPadding];
    CGFloat titleWidth = reservesSettings ? contentWidth - 34 : contentWidth;
    return NSMakeRect(contentX, floor(contentTop + 3), titleWidth, ChiraHeaderTextHeight);
}

- (CGFloat)clipboardListTopForIslandRect:(NSRect)rect horizontalPadding:(CGFloat)horizontalPadding {
    NSRect titleRect = [self headerTitleRectInIslandRect:rect horizontalPadding:horizontalPadding reservesSettings:YES];
    return NSMaxY(titleRect) + 21;
}

- (NSRect)settingsButtonRectInIslandRect:(NSRect)rect {
    if (_progress < 0.35) return NSZeroRect;

    CGFloat horizontalPadding = 40;
    NSRect titleRect = [self headerTitleRectInIslandRect:rect horizontalPadding:horizontalPadding reservesSettings:YES];
    return NSMakeRect(NSMaxX(rect) - horizontalPadding - ChiraHeaderButtonSize,
                      floor(NSMidY(titleRect) - ChiraHeaderButtonSize / 2.0 + ChiraHeaderIconTextBaselineOffset),
                      ChiraHeaderButtonSize,
                      ChiraHeaderButtonSize);
}

- (NSRect)singleLineTextRectForRowRect:(NSRect)rowRect {
    return NSMakeRect(NSMinX(rowRect),
                      floor(NSMidY(rowRect) - ChiraClipboardRowTextHeight / 2.0),
                      NSWidth(rowRect),
                      ChiraClipboardRowTextHeight);
}

- (NSRect)clipboardHoverRectForRowRect:(NSRect)rowRect height:(CGFloat)height horizontalInset:(CGFloat)horizontalInset {
    NSRect hoverRect = [self singleLineTextRectForRowRect:rowRect];
    hoverRect = NSInsetRect(hoverRect, -horizontalInset, -(height - ChiraClipboardRowTextHeight) / 2.0);
    hoverRect.origin.y += ChiraClipboardHoverTextBaselineOffset;
    return hoverRect;
}

- (NSRect)clipboardImageHoverRectForRowRect:(NSRect)rowRect {
    CGFloat hoverHeight = MAX(24.0, NSHeight(rowRect) - 8.0);
    return NSMakeRect(NSMinX(rowRect) - 8.0,
                      floor(NSMidY(rowRect) - hoverHeight / 2.0),
                      NSWidth(rowRect) + 16.0,
                      hoverHeight);
}

- (ClipboardHistoryItem *)clipboardItemFromObject:(id)object {
    return [object isKindOfClass:ClipboardHistoryItem.class] ? object : nil;
}

- (NSString *)displayTextForClipboardObject:(id)object {
    ClipboardHistoryItem *item = [self clipboardItemFromObject:object];
    if (item) return item.displayText ?: @"";
    return [object isKindOfClass:NSString.class] ? object : @"";
}

- (NSString *)displayLineForClipboardObject:(id)object atIndex:(NSInteger)index {
    return [NSString stringWithFormat:@"%ld  %@", (long)(index + 1), ChiraDisplayTextForClipboardItem([self displayTextForClipboardObject:object])];
}

- (NSString *)expandedLineForClipboardObject:(id)object atIndex:(NSInteger)index {
    ClipboardHistoryItem *item = [self clipboardItemFromObject:object];
    NSString *source = item.stringValue.length ? item.stringValue : [self displayTextForClipboardObject:object];
    NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSArray<NSString *> *parts = [source componentsSeparatedByCharactersInSet:whitespace];
    NSString *collapsed = [[parts filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *part, NSDictionary *bindings) {
        (void)bindings;
        return part.length > 0;
    }]] componentsJoinedByString:@" "];
    return [NSString stringWithFormat:@"%ld  %@", (long)(index + 1), collapsed.length ? collapsed : source];
}

- (BOOL)clipboardTextNeedsExpansion:(id)object atIndex:(NSInteger)index width:(CGFloat)width {
    ClipboardHistoryItem *item = [self clipboardItemFromObject:object];
    if (item.image) return YES;

    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium]
    };
    NSString *line = [self expandedLineForClipboardObject:object atIndex:index];
    return ceil([line sizeWithAttributes:attributes].width) > width;
}

- (CGFloat)clipboardRowHeightForObject:(id)object atIndex:(NSInteger)index width:(CGFloat)width {
    if (index != _hoveredClipboardIndex) return ChiraClipboardBaseRowHeight;

    CGFloat expandedHeight = [self expandedClipboardRowHeightForObject:object atIndex:index width:width];
    return ChiraClipboardBaseRowHeight + (expandedHeight - ChiraClipboardBaseRowHeight) * _hoverExpansion;
}

- (CGFloat)expandedClipboardRowHeightForObject:(id)object atIndex:(NSInteger)index width:(CGFloat)width {
    ClipboardHistoryItem *item = [self clipboardItemFromObject:object];
    if (item.image) {
        return ChiraClipboardImageHoverRowHeight;
    }
    if ([self clipboardTextNeedsExpansion:object atIndex:index width:width]) {
        return ChiraClipboardTextHoverRowHeight;
    }
    return ChiraClipboardBaseRowHeight;
}

- (void)preparePreviewForHoveredClipboardItem {
    IslandModule *module = [self displayModule];
    if (_hoveredClipboardIndex < 0 || _hoveredClipboardIndex >= (NSInteger)module.items.count) return;

    ClipboardHistoryItem *item = [self clipboardItemFromObject:module.items[_hoveredClipboardIndex]];
    if (!item.image || item.previewImage || !item.dataValue.length) return;

    item.previewImage = [[NSImage alloc] initWithData:item.dataValue];
}

- (NSInteger)clipboardItemIndexAtPoint:(NSPoint)point forModule:(IslandModule *)module inIslandRect:(NSRect)rect {
    for (NSDictionary *target in [self clipboardItemCopyTargetsForModule:module inIslandRect:rect]) {
        NSValue *rectValue = target[@"rect"];
        NSNumber *index = target[@"index"];
        if (rectValue && index && NSPointInRect(point, rectValue.rectValue)) {
            return index.integerValue;
        }
    }
    return -1;
}

- (NSInteger)clipboardItemHoverIndexAtPoint:(NSPoint)point forModule:(IslandModule *)module inIslandRect:(NSRect)rect {
    if (![module.identifier isEqualToString:ChiraModuleIdentifierClipboard] || module.items.count == 0) {
        return -1;
    }

    CGFloat horizontalPadding = 40;
    CGFloat rowTop = [self clipboardListTopForIslandRect:rect horizontalPadding:horizontalPadding];
    CGFloat contentX = [self contentXForIslandRect:rect horizontalPadding:horizontalPadding];
    CGFloat contentWidth = [self contentWidthForIslandRect:rect horizontalPadding:horizontalPadding];
    NSInteger count = MIN((NSInteger)module.items.count, [self visibleClipboardItemLimit]);

    for (NSInteger index = 0; index < count; index++) {
        CGFloat rowHeight = [self clipboardRowHeightForObject:module.items[index] atIndex:index width:contentWidth];
        NSRect rowRect = NSMakeRect(contentX - 10, rowTop + 1, contentWidth + 20, MAX(24, rowHeight - 2));
        if (NSPointInRect(point, rowRect)) {
            return index;
        }
        rowTop += rowHeight;
    }

    return -1;
}

- (NSArray<NSDictionary *> *)clipboardItemCopyTargetsForModule:(IslandModule *)module inIslandRect:(NSRect)rect {
    if (![module.identifier isEqualToString:ChiraModuleIdentifierClipboard] || module.items.count == 0) {
        return @[];
    }

    CGFloat horizontalPadding = 40;
    CGFloat listTop = [self clipboardListTopForIslandRect:rect horizontalPadding:horizontalPadding];
    CGFloat contentX = [self contentXForIslandRect:rect horizontalPadding:horizontalPadding];
    CGFloat contentWidth = [self contentWidthForIslandRect:rect horizontalPadding:horizontalPadding];
    NSDictionary *targetAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold]
    };

    NSMutableArray<NSDictionary *> *targets = [NSMutableArray array];
    NSInteger count = MIN((NSInteger)module.items.count, [self visibleClipboardItemLimit]);
    CGFloat rowTop = listTop;
    for (NSInteger index = 0; index < count; index++) {
        id object = module.items[index];
        CGFloat rowHeight = [self clipboardRowHeightForObject:object atIndex:index width:contentWidth];
        NSString *line = [self displayLineForClipboardObject:object atIndex:index];
        CGFloat textWidth = ceil([line sizeWithAttributes:targetAttributes].width);
        CGFloat targetWidth = MIN(contentWidth, MAX(textWidth + 8, [self clipboardItemFromObject:object].image ? 220 : 0));
        NSRect rowRect = NSMakeRect(contentX - 4, rowTop, targetWidth, rowHeight);
        CGFloat targetHeight = MIN(MAX(22, rowHeight - 6), rowHeight);
        NSRect targetRect = [self clipboardHoverRectForRowRect:rowRect height:targetHeight horizontalInset:0];
        targetRect.origin.x = NSMinX(rowRect);
        targetRect.size.width = NSWidth(rowRect);
        [targets addObject:@{
            @"rect": [NSValue valueWithRect:targetRect],
            @"index": @(index)
        }];
        rowTop += rowHeight;
    }
    return targets;
}

- (void)scrollWheel:(NSEvent *)event {
    [super scrollWheel:event];
}

- (void)animationTick {
    BOOL needsNextFrame = NO;

    CGFloat delta = _targetProgress - _progress;
    if (fabs(delta) < 0.01) {
        _progress = _targetProgress;
    } else {
        _progress += delta * 0.22;
        needsNextFrame = YES;
    }

    CGFloat hoverDelta = _targetHoverExpansion - _hoverExpansion;
    if (fabs(hoverDelta) < 0.01) {
        _hoverExpansion = _targetHoverExpansion;
        if (_hoverExpansion <= 0 && _targetHoverExpansion <= 0) {
            _hoveredClipboardIndex = -1;
        }
    } else {
        _hoverExpansion += hoverDelta * 0.24;
        needsNextFrame = YES;
    }

    if (_ingestPulseStartTime > 0) {
        NSTimeInterval elapsed = NSDate.timeIntervalSinceReferenceDate - _ingestPulseStartTime;
        CGFloat t = MIN(1.0, MAX(0.0, elapsed / ChiraIngestPulseDuration));

        _ingestPulse = ChiraIngestPulseValue(t);

        if (t >= 1.0) {
            _ingestPulse = 0;
            _ingestPulseStartTime = 0;
        } else {
            needsNextFrame = YES;
        }
    }

    if (!needsNextFrame) {
        [_animationTimer invalidate];
        _animationTimer = nil;
    }

    [self invalidateIslandDisplay];
}

- (NSRect)currentIslandRect {
    CGFloat detectedNotchWidth = self.notchWidth > 0 ? self.notchWidth : ChiraMacBookPro14NotchWidth;
    CGFloat hiddenWidth = self.hasNotch ? MAX(ChiraMacBookPro14NotchWidth, detectedNotchWidth) : ChiraFloatingHiddenWidth;
    CGFloat hiddenHeight = self.hasNotch ? MAX(1, self.topSafeInset - 2) : ChiraFloatingHiddenHeight;
    CGFloat expandedWidth = 470;
    CGFloat expandedHeight = hiddenHeight + [self expandedContentHeight];
    CGFloat width = hiddenWidth + (expandedWidth - hiddenWidth) * _progress;
    CGFloat height = hiddenHeight + (expandedHeight - hiddenHeight) * _progress;

    CGFloat hiddenBias = 1.0 - MIN(1.0, _progress * 1.7);
    CGFloat pulseHeight = (ChiraIngestPulseVerticalDrop * hiddenBias + 4 * (1.0 - hiddenBias)) * _ingestPulse;
    height += pulseHeight;

    CGFloat baseY = (self.hasNotch || _ingestPulse > 0.01) ? 0 : ChiraFloatingTopMargin;
    return NSMakeRect((NSWidth(self.bounds) - width) / 2.0, baseY, width, height);
}

- (CGFloat)expandedContentHeight {
    IslandModule *module = [self displayModule];
    if ([module.identifier isEqualToString:ChiraModuleIdentifierClipboard]) {
        NSInteger rowCount = MIN((NSInteger)module.items.count, [self visibleClipboardItemLimit]);
        if (rowCount == 0) return 96;

        CGFloat contentWidth = 470 - 40 * 2;
        CGFloat rowsHeight = 0;
        for (NSInteger index = 0; index < rowCount; index++) {
            rowsHeight += [self clipboardRowHeightForObject:module.items[index] atIndex:index width:contentWidth];
        }
        return 78 + rowsHeight;
    }
    return 122;
}

- (CGFloat)expandedContentHeightForFullCurrentHover {
    IslandModule *module = [self displayModule];
    if (![module.identifier isEqualToString:ChiraModuleIdentifierClipboard]) return [self expandedContentHeight];

    NSInteger rowCount = MIN((NSInteger)module.items.count, [self visibleClipboardItemLimit]);
    if (rowCount == 0) return 96;
    if (_hoveredClipboardIndex < 0 || _hoveredClipboardIndex >= rowCount) return [self expandedContentHeight];

    CGFloat contentWidth = 470 - 40 * 2;
    CGFloat rowsHeight = 0;
    for (NSInteger index = 0; index < rowCount; index++) {
        id object = module.items[index];
        rowsHeight += (index == _hoveredClipboardIndex)
            ? [self expandedClipboardRowHeightForObject:object atIndex:index width:contentWidth]
            : ChiraClipboardBaseRowHeight;
    }
    return 78 + rowsHeight;
}

- (BOOL)containsInteractivePoint:(NSPoint)point {
    if (_progress < 0.25) return NO;

    NSRect islandRect = [self currentIslandRect];
    if (NSPointInRect(point, islandRect)) return YES;

    if (self.mode == ChiraIslandModeClipboard && _hoveredClipboardIndex >= 0 && (_hoverExpansion > 0.01 || _targetHoverExpansion > 0.01)) {
        CGFloat extraHeight = MAX(0, [self expandedContentHeightForFullCurrentHover] - [self expandedContentHeight]) * _progress;
        if (extraHeight > 0) {
            islandRect.size.height += extraHeight;
            return NSPointInRect(point, islandRect);
        }
    }

    return NO;
}

- (NSBezierPath *)topAttachedPathForRect:(NSRect)rect bottomRadius:(CGFloat)radius topShoulderRadius:(CGFloat)topShoulderRadius {
    CGFloat shoulderRadius = MIN(topShoulderRadius, MIN(NSWidth(rect) / 4.0, NSHeight(rect) / 2.0));
    CGFloat bodyWidth = MAX(1, NSWidth(rect) - shoulderRadius * 2.0);
    CGFloat maxRadius = MIN(radius, MIN(bodyWidth, NSHeight(rect)) / 2.0);
    CGFloat minX = NSMinX(rect);
    CGFloat maxX = NSMaxX(rect);
    CGFloat minY = NSMinY(rect);
    CGFloat maxY = NSMaxY(rect);
    CGFloat bodyMinX = minX + shoulderRadius;
    CGFloat bodyMaxX = maxX - shoulderRadius;

    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(minX, minY)];
    [path lineToPoint:NSMakePoint(maxX, minY)];

    if (shoulderRadius > 0.1) {
        [path curveToPoint:NSMakePoint(bodyMaxX, minY + shoulderRadius)
             controlPoint1:NSMakePoint(maxX - shoulderRadius * 0.72, minY)
             controlPoint2:NSMakePoint(bodyMaxX, minY + shoulderRadius * 0.28)];
    }

    [path lineToPoint:NSMakePoint(bodyMaxX, maxY - maxRadius)];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(bodyMaxX, maxY)
                                   toPoint:NSMakePoint(bodyMaxX - maxRadius, maxY)
                                    radius:maxRadius];
    [path lineToPoint:NSMakePoint(bodyMinX + maxRadius, maxY)];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(bodyMinX, maxY)
                                   toPoint:NSMakePoint(bodyMinX, maxY - maxRadius)
                                    radius:maxRadius];
    [path lineToPoint:NSMakePoint(bodyMinX, minY + shoulderRadius)];

    if (shoulderRadius > 0.1) {
        [path curveToPoint:NSMakePoint(minX, minY)
             controlPoint1:NSMakePoint(bodyMinX, minY + shoulderRadius * 0.28)
             controlPoint2:NSMakePoint(minX + shoulderRadius * 0.72, minY)];
    }

    [path closePath];
    return path;
}

- (NSBezierPath *)islandShapeForRect:(NSRect)rect bottomRadius:(CGFloat)radius topShoulderRadius:(CGFloat)topShoulderRadius {
    if (self.hasNotch || _ingestPulse > 0.01) {
        return [self topAttachedPathForRect:rect bottomRadius:radius topShoulderRadius:topShoulderRadius];
    }

    CGFloat floatingRadius = MIN(radius, NSHeight(rect) / 2.0);
    return [NSBezierPath bezierPathWithRoundedRect:rect xRadius:floatingRadius yRadius:floatingRadius];
}

- (void)drawRect:(NSRect)dirtyRect {
    [NSColor.clearColor setFill];
    NSRectFill(self.bounds);

    if (_progress < 0.01 && _ingestPulse < 0.01) return;

    NSRect islandRect = [self currentIslandRect];
    CGFloat visualProgress = MAX(_progress, _ingestPulse * 0.08);
    CGFloat radius = ChiraHiddenNotchCornerRadius + (30 - ChiraHiddenNotchCornerRadius) * _progress;
    CGFloat topShoulderRadius = self.hasNotch ? 16 * _progress : 0;
    NSBezierPath *shape = [self islandShapeForRect:islandRect bottomRadius:radius topShoulderRadius:topShoulderRadius];

    NSShadow *shadow = [NSShadow new];
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.34 * visualProgress];
    shadow.shadowBlurRadius = 24 * visualProgress;
    shadow.shadowOffset = NSMakeSize(0, -10 * visualProgress);

    [NSGraphicsContext saveGraphicsState];
    [shadow set];
    [[NSColor colorWithWhite:0 alpha:0.985] setFill];
    [shape fill];
    [NSGraphicsContext restoreGraphicsState];

    [[NSColor colorWithWhite:1 alpha:0.08 * visualProgress] setStroke];
    NSBezierPath *border = [self islandShapeForRect:NSInsetRect(islandRect, 0.5, 0.5)
                                      bottomRadius:radius
                                 topShoulderRadius:MAX(0, topShoulderRadius - 0.5)];
    border.lineWidth = 1;
    [border stroke];

    if (_progress >= 0.35) {
        [NSGraphicsContext saveGraphicsState];
        [shape addClip];
        [self drawExpandedInRect:islandRect];
        [NSGraphicsContext restoreGraphicsState];
    }
}

- (void)drawExpandedInRect:(NSRect)rect {
    IslandModule *module = [self displayModule];
    CGFloat contentAlpha = MIN(1, MAX(0, (_progress - 0.35) / 0.35));
    [self drawModuleContent:module inRect:rect contentAlpha:contentAlpha horizontalPadding:40];
}

- (void)drawModuleContent:(IslandModule *)module
                   inRect:(NSRect)rect
             contentAlpha:(CGFloat)contentAlpha
        horizontalPadding:(CGFloat)horizontalPadding {
    NSColor *tint = module.accentColor ?: NSColor.whiteColor;
    NSString *primary = module.title.length ? module.title : @"Chira";
    NSString *secondary = module.subtitle.length ? module.subtitle : @"Ready";
    CGFloat contentTop = [self contentTopForIslandRect:rect];
    CGFloat contentX = [self contentXForIslandRect:rect horizontalPadding:horizontalPadding];
    CGFloat contentWidth = [self contentWidthForIslandRect:rect horizontalPadding:horizontalPadding];
    BOOL isClipboardModule = [module.identifier isEqualToString:ChiraModuleIdentifierClipboard];
    NSRect titleRect = [self headerTitleRectInIslandRect:rect horizontalPadding:horizontalPadding reservesSettings:isClipboardModule];

    NSDictionary *primaryAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:contentAlpha]
    };
    NSDictionary *secondaryAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:0.62 * contentAlpha]
    };

    [primary drawWithRect:titleRect
                  options:NSStringDrawingTruncatesLastVisibleLine
               attributes:primaryAttributes];

    if (isClipboardModule) {
        NSRect settingsRect = [self settingsButtonRectInIslandRect:rect];
        NSImage *gear = [NSImage imageWithSystemSymbolName:@"gearshape.fill" accessibilityDescription:@"Settings"];
        NSImageSymbolConfiguration *sizeConfig = [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightMedium];
        NSImageSymbolConfiguration *colorConfig = [NSImageSymbolConfiguration configurationWithHierarchicalColor:[NSColor colorWithWhite:1 alpha:0.62 * contentAlpha]];
        gear = [[gear imageWithSymbolConfiguration:sizeConfig] imageWithSymbolConfiguration:colorConfig];
        NSRect imageRect = NSInsetRect(settingsRect, 4, 4);
        [gear drawInRect:imageRect
                fromRect:NSZeroRect
               operation:NSCompositingOperationSourceOver
                fraction:1.0
          respectFlipped:NO
                   hints:nil];
    }

    if (module.style == ChiraModuleStyleProgress) {
        NSRect barRect = NSMakeRect(contentX, contentTop + 33, contentWidth, 8);
        [[NSColor colorWithWhite:1 alpha:0.14] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:barRect xRadius:4 yRadius:4] fill];

        NSRect fillRect = barRect;
        fillRect.size.width = MAX(8, NSWidth(barRect) * module.progress);
        [tint setFill];
        [[NSBezierPath bezierPathWithRoundedRect:fillRect xRadius:4 yRadius:4] fill];
        return;
    }

    if (module.style == ChiraModuleStyleList && module.items.count > 0) {
        [self drawClipboardItems:module.items
                         inRect:NSMakeRect(contentX, [self clipboardListTopForIslandRect:rect horizontalPadding:horizontalPadding], contentWidth, NSHeight(rect) - contentTop - 52)
                    contentAlpha:contentAlpha];
        return;
    }

    [secondary drawWithRect:NSMakeRect(contentX, contentTop + 29, contentWidth, 18)
                    options:NSStringDrawingTruncatesLastVisibleLine
                 attributes:secondaryAttributes];
}

- (void)drawClipboardItems:(NSArray *)items inRect:(NSRect)rect contentAlpha:(CGFloat)contentAlpha {
    NSInteger count = MIN((NSInteger)items.count, [self visibleClipboardItemLimit]);
    CGFloat rowTop = NSMinY(rect);

    for (NSInteger index = 0; index < count; index++) {
        id object = items[index];
        ClipboardHistoryItem *item = [self clipboardItemFromObject:object];
        BOOL hovered = _hoveredClipboardIndex == index;
        BOOL expanded = hovered && _hoverExpansion > 0.45;
        BOOL pressed = _pressedClipboardInside && _pressedClipboardIndex == index;
        CGFloat rowHeight = [self clipboardRowHeightForObject:object atIndex:index width:NSWidth(rect)];
        NSRect rowRect = NSMakeRect(NSMinX(rect), rowTop, NSWidth(rect), rowHeight);

        if (hovered) {
            NSRect highlightRect;
            if (item.image) {
                highlightRect = [self clipboardImageHoverRectForRowRect:rowRect];
            } else {
                CGFloat highlightHeight = MIN(24, rowHeight);
                highlightRect = [self clipboardHoverRectForRowRect:rowRect height:highlightHeight horizontalInset:8];
            }
            [[NSColor colorWithWhite:1 alpha:0.07 * contentAlpha * MAX(0.25, _hoverExpansion)] setFill];
            CGFloat radius = MIN(10.0, NSHeight(highlightRect) / 2.0);
            [[NSBezierPath bezierPathWithRoundedRect:highlightRect xRadius:radius yRadius:radius] fill];
        }

        NSDictionary *itemAttributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:12 weight:(pressed ? NSFontWeightSemibold : NSFontWeightMedium)],
            NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:(pressed || hovered ? 0.96 : 0.64) * contentAlpha]
        };
        NSString *line = [self displayLineForClipboardObject:object atIndex:index];

        if (expanded && item.image) {
            CGFloat thumbnailSize = 58;
            NSRect thumbnailRect = NSMakeRect(NSMinX(rowRect),
                                              floor(NSMidY(rowRect) - thumbnailSize / 2.0),
                                              thumbnailSize,
                                              thumbnailSize);
            [[NSColor colorWithWhite:1 alpha:0.10 * contentAlpha] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:thumbnailRect xRadius:8 yRadius:8] fill];

            if (item.previewImage) {
                NSSize imageSize = item.previewImage.size;
                CGFloat scale = MIN(NSWidth(thumbnailRect) / MAX(imageSize.width, 1), NSHeight(thumbnailRect) / MAX(imageSize.height, 1));
                NSSize drawSize = NSMakeSize(imageSize.width * scale, imageSize.height * scale);
                NSRect drawRect = NSMakeRect(NSMidX(thumbnailRect) - drawSize.width / 2.0,
                                             NSMidY(thumbnailRect) - drawSize.height / 2.0,
                                             drawSize.width,
                                             drawSize.height);
                [item.previewImage drawInRect:drawRect
                                      fromRect:NSZeroRect
                                     operation:NSCompositingOperationSourceOver
                                      fraction:contentAlpha
                                respectFlipped:YES
                                         hints:nil];
            }

            NSRect imageLabelRect = [self singleLineTextRectForRowRect:rowRect];
            imageLabelRect.origin.x = NSMaxX(thumbnailRect) + 14;
            imageLabelRect.size.width = NSWidth(rowRect) - thumbnailSize - 14;
            [line drawWithRect:imageLabelRect
                       options:NSStringDrawingTruncatesLastVisibleLine
                    attributes:itemAttributes];
        } else if (expanded && [self clipboardTextNeedsExpansion:object atIndex:index width:NSWidth(rect)]) {
            NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
            paragraph.lineBreakMode = NSLineBreakByCharWrapping;
            paragraph.lineSpacing = 1.5;
            NSMutableDictionary *expandedAttributes = [itemAttributes mutableCopy];
            expandedAttributes[NSParagraphStyleAttributeName] = paragraph;
            NSString *expandedLine = [self expandedLineForClipboardObject:object atIndex:index];

            CGFloat expandedTextHeight = 45;
            [expandedLine drawWithRect:NSMakeRect(NSMinX(rowRect),
                                                  floor(NSMidY(rowRect) - expandedTextHeight / 2.0),
                                                  NSWidth(rowRect),
                                                  expandedTextHeight)
                               options:NSStringDrawingUsesLineFragmentOrigin
                            attributes:expandedAttributes];
        } else {
            NSRect itemRect = [self singleLineTextRectForRowRect:rowRect];
            [line drawWithRect:itemRect options:NSStringDrawingTruncatesLastVisibleLine attributes:itemAttributes];
        }

        rowTop += rowHeight;
    }
}

@end
