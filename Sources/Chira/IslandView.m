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
static const CGFloat ChiraClipboardImageHoverRowHeight = 94.0;
static const CGFloat ChiraHeaderTextHeight = 18.0;
static const CGFloat ChiraHeaderButtonSize = 24.0;
static const CGFloat ChiraHeaderIconTextBaselineOffset = -13.0;
static const CGFloat ChiraClipboardRowTextHeight = 18.0;
static const CGFloat ChiraClipboardTitleListGap = 12.0;
static const CGFloat ChiraClipboardContentBottomPadding = 12.0;
static const CGFloat ChiraIslandBottomKeepAlivePadding = 75.0;
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

typedef struct {
    NSRect rowRect;
    NSRect primaryTextRect;
    NSRect continuationTextRect;
    NSRect highlightRect;
    NSRect hoverRect;
    NSRect clickRect;
    NSRect thumbnailRect;
    NSRect visibleThumbnailRect;
    CGFloat rowHeight;
    CGFloat reveal;
    BOOL expanding;
    BOOL textExpanding;
    BOOL imageRevealing;
} ChiraClipboardRowLayout;

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
    NSInteger _expandingClipboardIndex;
    CGFloat _hoverExpansion;
    BOOL _pressedClipboardInside;
    NSImage *_settingsGearImage;
    NSMutableIndexSet *_sessionExpandedClipboardIndexes;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;

    _clipboardItems = @[];
    _topSafeInset = 6;
    _notchWidth = 0;
    _hasNotch = NO;
    _maxVisibleClipboardItems = 5;
    _showsImageClipboardPreviews = NO;
    _ingestPulse = 0;
    _lastInvalidatedIslandRect = NSZeroRect;
    _pressedClipboardIndex = -1;
    _hoveredClipboardIndex = -1;
    _expandingClipboardIndex = -1;
    _hoverExpansion = 0;
    _pressedClipboardInside = NO;
    _sessionExpandedClipboardIndexes = [NSMutableIndexSet indexSet];
    self.wantsLayer = YES;
    self.layer.backgroundColor = NSColor.clearColor.CGColor;
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setClipboardItems:(NSArray<ClipboardHistoryItem *> *)clipboardItems {
    _clipboardItems = [clipboardItems copy] ?: @[];
    [_sessionExpandedClipboardIndexes removeAllIndexes];
    _pressedClipboardIndex = -1;
    _hoveredClipboardIndex = -1;
    _expandingClipboardIndex = -1;
    _hoverExpansion = 0;
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

    NSInteger index = [self clipboardItemIndexAtPoint:point inIslandRect:islandRect];
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
    NSInteger index = [self clipboardItemIndexAtPoint:point inIslandRect:islandRect];
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
    NSInteger releaseIndex = [self clipboardItemIndexAtPoint:point inIslandRect:islandRect];

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

    NSInteger index = [self clipboardItemHoverIndexAtPoint:point inIslandRect:islandRect];
    if (index < 0) {
        [self clearHoveredClipboardIndex];
        return;
    }
    BOOL hoverChanged = index != _hoveredClipboardIndex;
    _hoveredClipboardIndex = index;

    BOOL startsExpansion = ![_sessionExpandedClipboardIndexes containsIndex:index];
    if (startsExpansion) {
        [_sessionExpandedClipboardIndexes addIndex:index];
        _expandingClipboardIndex = index;
        _hoverExpansion = 0;
        [self preparePreviewForHoveredClipboardItem];
        [self startAnimationTimerIfNeeded];
    }

    if (hoverChanged || startsExpansion) {
        [self invalidateIslandDisplay];
    }
}

- (void)clearHoveredClipboardIndex {
    if (_hoveredClipboardIndex < 0) return;

    _hoveredClipboardIndex = -1;
    [self invalidateIslandDisplay];
}

- (void)setMode:(ChiraIslandMode)mode transientDuration:(NSTimeInterval)duration {
    self.mode = mode;

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

- (NSInteger)visibleClipboardItemLimit {
    return MAX(1, MIN(8, self.maxVisibleClipboardItems > 0 ? self.maxVisibleClipboardItems : 5));
}

- (BOOL)clipboardRowIsSessionExpandedAtIndex:(NSInteger)index {
    return index >= 0 && [_sessionExpandedClipboardIndexes containsIndex:index];
}

- (CGFloat)clipboardExpansionRevealForIndex:(NSInteger)index {
    if (![self clipboardRowIsSessionExpandedAtIndex:index]) return 0;
    if (index == _expandingClipboardIndex) return ChiraSmoothStep(_hoverExpansion);
    return 1.0;
}

- (BOOL)resetClipboardSessionExpansionIfClosed {
    if (_progress > 0.01 || _targetProgress > 0.01) return NO;
    if (_sessionExpandedClipboardIndexes.count == 0 && _hoveredClipboardIndex < 0 && _expandingClipboardIndex < 0) return NO;

    [_sessionExpandedClipboardIndexes removeAllIndexes];
    _hoveredClipboardIndex = -1;
    _expandingClipboardIndex = -1;
    _hoverExpansion = 0;
    return YES;
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
    return NSMaxY(titleRect) + ChiraClipboardTitleListGap;
}

- (CGFloat)hiddenIslandHeight {
    return self.hasNotch ? MAX(1, self.topSafeInset - 2) : ChiraFloatingHiddenHeight;
}

- (CGFloat)clipboardExpandedContentHeightForRowsHeight:(CGFloat)rowsHeight {
    CGFloat listTop = [self clipboardListTopForIslandRect:NSMakeRect(0, 0, 470, 200)
                                        horizontalPadding:40];
    CGFloat visibleHeight = listTop + rowsHeight + ChiraClipboardContentBottomPadding;
    return MAX(0, visibleHeight - [self hiddenIslandHeight]);
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
    CGFloat baseMidY = NSMinY(rowRect) + ChiraClipboardBaseRowHeight / 2.0;
    return NSMakeRect(NSMinX(rowRect),
                      floor(baseMidY - ChiraClipboardRowTextHeight / 2.0),
                      NSWidth(rowRect),
                      ChiraClipboardRowTextHeight);
}

- (NSRect)continuationTextRectBelowTextRect:(NSRect)textRect inRowRect:(NSRect)rowRect {
    CGFloat y = NSMaxY(textRect) + 2.0;
    CGFloat height = MAX(0, NSMaxY(rowRect) - y - 4.0);
    return NSMakeRect(NSMinX(textRect), y, NSWidth(textRect), MIN(ChiraClipboardRowTextHeight, height));
}

- (NSDictionary *)clipboardTextMetricAttributes {
    return @{
        NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium]
    };
}

- (NSRect)clipboardLineBoundsForLine:(NSString *)line
                          inTextRect:(NSRect)textRect
                          attributes:(NSDictionary *)attributes {
    if (line.length == 0 || NSWidth(textRect) <= 0 || NSHeight(textRect) <= 0) {
        return NSZeroRect;
    }

    NSSize measuredSize = [line sizeWithAttributes:attributes];
    CGFloat width = MIN(NSWidth(textRect), ceil(measuredSize.width));
    if (width <= 0) return NSZeroRect;

    NSFont *font = attributes[NSFontAttributeName] ?: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    CGFloat ascender = ceil(font.ascender);
    CGFloat descender = ceil(fabs(font.descender));
    CGFloat height = MAX(1.0, ascender + descender);
    return NSMakeRect(NSMinX(textRect),
                      floor(NSMinY(textRect) - ascender),
                      width,
                      height);
}

- (NSRect)clipboardHighlightRectForPrimaryTextRect:(NSRect)primaryTextRect
                                       primaryLine:(NSString *)primaryLine
                              continuationTextRect:(NSRect)continuationTextRect
                                  continuationLine:(NSString *)continuationLine
                                        attributes:(NSDictionary *)attributes {
    NSRect bounds = [self clipboardLineBoundsForLine:primaryLine inTextRect:primaryTextRect attributes:attributes];
    if (continuationLine.length && NSHeight(continuationTextRect) > 1.0) {
        NSRect continuationBounds = [self clipboardLineBoundsForLine:continuationLine
                                                          inTextRect:continuationTextRect
                                                          attributes:attributes];
        if (!NSIsEmptyRect(continuationBounds)) {
            bounds = NSIsEmptyRect(bounds) ? continuationBounds : NSUnionRect(bounds, continuationBounds);
        }
    }
    if (NSIsEmptyRect(bounds)) bounds = primaryTextRect;

    CGFloat horizontalPadding = 8.0;
    CGFloat verticalPadding = 3.0;
    NSRect highlightRect = NSMakeRect(floor(NSMinX(bounds) - horizontalPadding),
                                      floor(NSMinY(bounds) - verticalPadding),
                                      ceil(NSWidth(bounds) + horizontalPadding * 2.0),
                                      ceil(NSHeight(bounds) + verticalPadding * 2.0));
    if (NSHeight(highlightRect) < 24.0) {
        CGFloat extraHeight = 24.0 - NSHeight(highlightRect);
        highlightRect.origin.y = floor(NSMinY(highlightRect) - extraHeight / 2.0);
        highlightRect.size.height = 24.0;
    }
    return highlightRect;
}

- (NSRect)clipboardImageHighlightRectForRowRect:(NSRect)rowRect {
    CGFloat hoverHeight = MAX(24.0, NSHeight(rowRect) - 8.0);
    return NSMakeRect(NSMinX(rowRect) - 8.0,
                      floor(NSMinY(rowRect) + 2.0),
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

- (NSString *)continuationLineForExpandedLine:(NSString *)line
                                        width:(CGFloat)width
                                   attributes:(NSDictionary *)attributes {
    if (ceil([line sizeWithAttributes:attributes].width) <= width) return @"";

    NSUInteger low = 0;
    NSUInteger high = line.length;
    while (low < high) {
        NSUInteger mid = (low + high + 1) / 2;
        NSString *prefix = [line substringToIndex:mid];
        if (ceil([prefix sizeWithAttributes:attributes].width) <= width) {
            low = mid;
        } else {
            high = mid - 1;
        }
    }

    if (low >= line.length) return @"";

    NSUInteger cutIndex = low;
    NSRange searchRange = NSMakeRange(0, cutIndex);
    NSRange whitespaceRange = [line rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet
                                                    options:NSBackwardsSearch
                                                      range:searchRange];
    if (whitespaceRange.location != NSNotFound && cutIndex - whitespaceRange.location < 18) {
        cutIndex = NSMaxRange(whitespaceRange);
    } else if (cutIndex > 0 && cutIndex < line.length) {
        NSRange safeRange = [line rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, cutIndex)];
        cutIndex = MIN(NSMaxRange(safeRange), line.length);
    }
    NSString *tail = [line substringFromIndex:cutIndex];
    return [tail stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (BOOL)clipboardTextNeedsExpansion:(id)object atIndex:(NSInteger)index width:(CGFloat)width {
    ClipboardHistoryItem *item = [self clipboardItemFromObject:object];
    if (item.image) return self.showsImageClipboardPreviews;

    NSDictionary *attributes = [self clipboardTextMetricAttributes];
    NSString *line = [self expandedLineForClipboardObject:object atIndex:index];
    return ceil([line sizeWithAttributes:attributes].width) > width;
}

- (CGFloat)clipboardRowHeightForObject:(id)object atIndex:(NSInteger)index width:(CGFloat)width {
    if (![self clipboardRowIsSessionExpandedAtIndex:index]) return ChiraClipboardBaseRowHeight;

    CGFloat expandedHeight = [self expandedClipboardRowHeightForObject:object atIndex:index width:width];
    CGFloat reveal = [self clipboardExpansionRevealForIndex:index];
    return ChiraClipboardBaseRowHeight + (expandedHeight - ChiraClipboardBaseRowHeight) * reveal;
}

- (CGFloat)expandedClipboardRowHeightForObject:(id)object atIndex:(NSInteger)index width:(CGFloat)width {
    ClipboardHistoryItem *item = [self clipboardItemFromObject:object];
    if (item.image && self.showsImageClipboardPreviews) {
        return ChiraClipboardImageHoverRowHeight;
    }
    if ([self clipboardTextNeedsExpansion:object atIndex:index width:width]) {
        return ChiraClipboardTextHoverRowHeight;
    }
    return ChiraClipboardBaseRowHeight;
}

- (ChiraClipboardRowLayout)clipboardRowLayoutForObject:(id)object
                                               atIndex:(NSInteger)index
                                                rowTop:(CGFloat)rowTop
                                              contentX:(CGFloat)contentX
                                          contentWidth:(CGFloat)contentWidth
                                            attributes:(NSDictionary *)attributes
                                           displayLine:(NSString **)displayLineOut
                                           primaryLine:(NSString **)primaryLineOut
                                      continuationLine:(NSString **)continuationLineOut {
    ClipboardHistoryItem *item = [self clipboardItemFromObject:object];
    BOOL expanded = [self clipboardRowIsSessionExpandedAtIndex:index];
    CGFloat rowHeight = [self clipboardRowHeightForObject:object atIndex:index width:contentWidth];
    CGFloat reveal = [self clipboardExpansionRevealForIndex:index];
    BOOL expanding = expanded && rowHeight > ChiraClipboardBaseRowHeight + 0.5;
    BOOL imageRevealing = expanding && item.image && self.showsImageClipboardPreviews && reveal > 0.01;
    BOOL textExpanding = expanding && !item.image && [self clipboardTextNeedsExpansion:object atIndex:index width:contentWidth];

    NSString *displayLine = [self displayLineForClipboardObject:object atIndex:index];
    NSString *primaryLine = textExpanding ? [self expandedLineForClipboardObject:object atIndex:index] : displayLine;
    NSString *continuationLine = @"";
    if (textExpanding) {
        continuationLine = [self continuationLineForExpandedLine:primaryLine
                                                           width:contentWidth
                                                      attributes:attributes];
    }

    NSRect rowRect = NSMakeRect(contentX, rowTop, contentWidth, rowHeight);
    NSRect primaryTextRect = [self singleLineTextRectForRowRect:rowRect];
    NSRect continuationTextRect = textExpanding
        ? [self continuationTextRectBelowTextRect:primaryTextRect inRowRect:rowRect]
        : NSZeroRect;

    NSRect highlightRect;
    if (imageRevealing) {
        highlightRect = [self clipboardImageHighlightRectForRowRect:rowRect];
    } else {
        NSString *visibleContinuationLine = (textExpanding && reveal > 0.01) ? continuationLine : nil;
        highlightRect = [self clipboardHighlightRectForPrimaryTextRect:primaryTextRect
                                                            primaryLine:primaryLine
                                                   continuationTextRect:continuationTextRect
                                                       continuationLine:visibleContinuationLine
                                                             attributes:attributes];
    }

    CGFloat thumbnailSize = 58.0;
    CGFloat thumbnailScale = 0.82 + 0.18 * reveal;
    CGFloat visibleThumbnailSize = thumbnailSize * thumbnailScale;
    NSRect thumbnailRect = NSMakeRect(NSMinX(rowRect),
                                      NSMinY(rowRect) + ChiraClipboardBaseRowHeight + 4.0,
                                      thumbnailSize,
                                      thumbnailSize);
    NSRect visibleThumbnailRect = NSMakeRect(NSMidX(thumbnailRect) - visibleThumbnailSize / 2.0,
                                             NSMidY(thumbnailRect) - visibleThumbnailSize / 2.0,
                                             visibleThumbnailSize,
                                             visibleThumbnailSize);

    ChiraClipboardRowLayout layout;
    layout.rowRect = rowRect;
    layout.primaryTextRect = primaryTextRect;
    layout.continuationTextRect = continuationTextRect;
    layout.highlightRect = highlightRect;
    layout.hoverRect = NSMakeRect(NSMinX(rowRect) - 10.0,
                                  NSMinY(rowRect) + 1.0,
                                  NSWidth(rowRect) + 20.0,
                                  MAX(24.0, NSHeight(rowRect) - 2.0));
    layout.clickRect = highlightRect;
    layout.thumbnailRect = thumbnailRect;
    layout.visibleThumbnailRect = visibleThumbnailRect;
    layout.rowHeight = rowHeight;
    layout.reveal = reveal;
    layout.expanding = expanding;
    layout.textExpanding = textExpanding;
    layout.imageRevealing = imageRevealing;

    if (displayLineOut) *displayLineOut = displayLine;
    if (primaryLineOut) *primaryLineOut = primaryLine;
    if (continuationLineOut) *continuationLineOut = continuationLine;

    return layout;
}

- (void)preparePreviewForHoveredClipboardItem {
    if (_hoveredClipboardIndex < 0 || _hoveredClipboardIndex >= (NSInteger)self.clipboardItems.count) return;

    ClipboardHistoryItem *item = [self clipboardItemFromObject:self.clipboardItems[_hoveredClipboardIndex]];
    if (!item.image) return;
    if (!self.showsImageClipboardPreviews) return;
    if (item.thumbnailImage) return;

    if (!item.previewImage && item.dataValue.length) {
        item.previewImage = [[NSImage alloc] initWithData:item.dataValue];
    }
    [item prepareThumbnailIfNeeded];
    if (item.thumbnailImage) item.previewImage = nil;
}

- (NSInteger)clipboardItemIndexAtPoint:(NSPoint)point inIslandRect:(NSRect)rect {
    if (self.clipboardItems.count == 0) {
        return -1;
    }

    CGFloat horizontalPadding = 40;
    CGFloat rowTop = [self clipboardListTopForIslandRect:rect horizontalPadding:horizontalPadding];
    CGFloat contentX = [self contentXForIslandRect:rect horizontalPadding:horizontalPadding];
    CGFloat contentWidth = [self contentWidthForIslandRect:rect horizontalPadding:horizontalPadding];
    NSDictionary *attributes = [self clipboardTextMetricAttributes];
    NSInteger count = MIN((NSInteger)self.clipboardItems.count, [self visibleClipboardItemLimit]);

    for (NSInteger index = 0; index < count; index++) {
        ChiraClipboardRowLayout layout = [self clipboardRowLayoutForObject:self.clipboardItems[index]
                                                                    atIndex:index
                                                                     rowTop:rowTop
                                                                   contentX:contentX
                                                               contentWidth:contentWidth
                                                                 attributes:attributes
                                                                displayLine:nil
                                                                primaryLine:nil
                                                           continuationLine:nil];
        if (NSPointInRect(point, layout.clickRect)) {
            return index;
        }
        rowTop += layout.rowHeight;
    }

    return -1;
}

- (NSInteger)clipboardItemHoverIndexAtPoint:(NSPoint)point inIslandRect:(NSRect)rect {
    if (self.clipboardItems.count == 0) {
        return -1;
    }

    CGFloat horizontalPadding = 40;
    CGFloat rowTop = [self clipboardListTopForIslandRect:rect horizontalPadding:horizontalPadding];
    CGFloat contentX = [self contentXForIslandRect:rect horizontalPadding:horizontalPadding];
    CGFloat contentWidth = [self contentWidthForIslandRect:rect horizontalPadding:horizontalPadding];
    NSDictionary *attributes = [self clipboardTextMetricAttributes];
    NSInteger count = MIN((NSInteger)self.clipboardItems.count, [self visibleClipboardItemLimit]);

    for (NSInteger index = 0; index < count; index++) {
        ChiraClipboardRowLayout layout = [self clipboardRowLayoutForObject:self.clipboardItems[index]
                                                                    atIndex:index
                                                                     rowTop:rowTop
                                                                   contentX:contentX
                                                               contentWidth:contentWidth
                                                                 attributes:attributes
                                                                displayLine:nil
                                                                primaryLine:nil
                                                           continuationLine:nil];
        if (NSPointInRect(point, layout.hoverRect)) {
            return index;
        }
        rowTop += layout.rowHeight;
    }

    return -1;
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

    if (_expandingClipboardIndex >= 0) {
        CGFloat hoverDelta = 1.0 - _hoverExpansion;
        if (fabs(hoverDelta) < 0.01) {
            _hoverExpansion = 1.0;
            _expandingClipboardIndex = -1;
        } else {
            _hoverExpansion += hoverDelta * 0.24;
            needsNextFrame = YES;
        }
    }

    if ([self resetClipboardSessionExpansionIfClosed]) {
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
    CGFloat hiddenHeight = [self hiddenIslandHeight];
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

- (NSRect)interactiveIslandRectForVisibleRect:(NSRect)rect {
    if (_progress < 0.85) return rect;

    NSRect interactiveRect = rect;
    interactiveRect.size.height += ChiraIslandBottomKeepAlivePadding * ChiraSmoothStep(_progress);
    return interactiveRect;
}

- (CGFloat)expandedContentHeight {
    NSInteger rowCount = MIN((NSInteger)self.clipboardItems.count, [self visibleClipboardItemLimit]);
    if (rowCount == 0) return 96;

    CGFloat contentWidth = 470 - 40 * 2;
    CGFloat rowsHeight = 0;
    for (NSInteger index = 0; index < rowCount; index++) {
        rowsHeight += [self clipboardRowHeightForObject:self.clipboardItems[index] atIndex:index width:contentWidth];
    }
    return [self clipboardExpandedContentHeightForRowsHeight:rowsHeight];
}

- (CGFloat)expandedContentHeightForFullClipboardSession {
    NSInteger rowCount = MIN((NSInteger)self.clipboardItems.count, [self visibleClipboardItemLimit]);
    if (rowCount == 0) return 96;
    if (_sessionExpandedClipboardIndexes.count == 0) return [self expandedContentHeight];

    CGFloat contentWidth = 470 - 40 * 2;
    CGFloat rowsHeight = 0;
    for (NSInteger index = 0; index < rowCount; index++) {
        id object = self.clipboardItems[index];
        rowsHeight += [_sessionExpandedClipboardIndexes containsIndex:index]
            ? [self expandedClipboardRowHeightForObject:object atIndex:index width:contentWidth]
            : ChiraClipboardBaseRowHeight;
    }
    return [self clipboardExpandedContentHeightForRowsHeight:rowsHeight];
}

- (BOOL)containsInteractivePoint:(NSPoint)point {
    if (_progress < 0.25) return NO;

    NSRect islandRect = [self currentIslandRect];
    if (NSPointInRect(point, islandRect)) return YES;
    if (NSPointInRect(point, [self interactiveIslandRectForVisibleRect:islandRect])) return YES;

    if (self.mode == ChiraIslandModeClipboard && _sessionExpandedClipboardIndexes.count > 0) {
        CGFloat extraHeight = MAX(0, [self expandedContentHeightForFullClipboardSession] - [self expandedContentHeight]) * _progress;
        if (extraHeight > 0) {
            islandRect.size.height += extraHeight;
            return NSPointInRect(point, [self interactiveIslandRectForVisibleRect:islandRect]);
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

- (NSImage *)settingsGearImage {
    if (_settingsGearImage) return _settingsGearImage;

    NSImage *gear = [NSImage imageWithSystemSymbolName:@"gearshape.fill" accessibilityDescription:@"Settings"];
    if (!gear) return nil;

    NSImageSymbolConfiguration *sizeConfig = [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightMedium];
    NSImageSymbolConfiguration *colorConfig = [NSImageSymbolConfiguration configurationWithHierarchicalColor:[NSColor colorWithWhite:1 alpha:0.62]];
    _settingsGearImage = [[gear imageWithSymbolConfiguration:sizeConfig] imageWithSymbolConfiguration:colorConfig];
    return _settingsGearImage;
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
    CGFloat contentAlpha = MIN(1, MAX(0, (_progress - 0.35) / 0.35));
    [self drawClipboardContentInRect:rect contentAlpha:contentAlpha horizontalPadding:40];
}

- (void)drawClipboardContentInRect:(NSRect)rect
                       contentAlpha:(CGFloat)contentAlpha
                  horizontalPadding:(CGFloat)horizontalPadding {
    CGFloat contentTop = [self contentTopForIslandRect:rect];
    CGFloat contentX = [self contentXForIslandRect:rect horizontalPadding:horizontalPadding];
    CGFloat contentWidth = [self contentWidthForIslandRect:rect horizontalPadding:horizontalPadding];
    NSRect titleRect = [self headerTitleRectInIslandRect:rect horizontalPadding:horizontalPadding reservesSettings:YES];

    NSDictionary *primaryAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:contentAlpha]
    };
    NSDictionary *secondaryAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:0.62 * contentAlpha]
    };

    [@"Clipboard" drawWithRect:titleRect
                       options:NSStringDrawingTruncatesLastVisibleLine
                    attributes:primaryAttributes];

    NSRect settingsRect = [self settingsButtonRectInIslandRect:rect];
    NSImage *gear = [self settingsGearImage];
    NSRect imageRect = NSInsetRect(settingsRect, 4, 4);
    if (gear) {
        [gear drawInRect:imageRect
                fromRect:NSZeroRect
               operation:NSCompositingOperationSourceOver
                fraction:contentAlpha
          respectFlipped:NO
                   hints:nil];
    }

    if (self.clipboardItems.count > 0) {
        [self drawClipboardItems:self.clipboardItems
                         inRect:NSMakeRect(contentX, [self clipboardListTopForIslandRect:rect horizontalPadding:horizontalPadding], contentWidth, NSHeight(rect) - contentTop - 52)
                    contentAlpha:contentAlpha];
        return;
    }

    [@"No recent items" drawWithRect:NSMakeRect(contentX, contentTop + 29, contentWidth, 18)
                             options:NSStringDrawingTruncatesLastVisibleLine
                          attributes:secondaryAttributes];
}

- (void)drawClipboardItems:(NSArray *)items inRect:(NSRect)rect contentAlpha:(CGFloat)contentAlpha {
    NSInteger count = MIN((NSInteger)items.count, [self visibleClipboardItemLimit]);
    CGFloat rowTop = NSMinY(rect);
    NSDictionary *layoutAttributes = [self clipboardTextMetricAttributes];

    for (NSInteger index = 0; index < count; index++) {
        id object = items[index];
        ClipboardHistoryItem *item = [self clipboardItemFromObject:object];
        NSString *displayLine = nil;
        NSString *primaryLine = nil;
        NSString *continuationLine = nil;
        ChiraClipboardRowLayout layout = [self clipboardRowLayoutForObject:object
                                                                   atIndex:index
                                                                    rowTop:rowTop
                                                                  contentX:NSMinX(rect)
                                                              contentWidth:NSWidth(rect)
                                                                attributes:layoutAttributes
                                                               displayLine:&displayLine
                                                               primaryLine:&primaryLine
                                                          continuationLine:&continuationLine];

        BOOL hovered = _hoveredClipboardIndex == index;
        BOOL pressed = _pressedClipboardInside && _pressedClipboardIndex == index;
        BOOL activelyHovered = hovered;

        CGFloat itemTextAlpha = (pressed || activelyHovered ? 0.96 : 0.64) * contentAlpha;
        NSDictionary *itemAttributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:12 weight:(pressed ? NSFontWeightSemibold : NSFontWeightMedium)],
            NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:itemTextAlpha]
        };

        if (activelyHovered || pressed) {
            CGFloat highlightAlpha = 0.07 * contentAlpha;
            if (layout.expanding && !pressed) {
                highlightAlpha *= MAX(0.35, layout.reveal);
            }
            [[NSColor colorWithWhite:1 alpha:highlightAlpha] setFill];
            CGFloat radius = MIN(10.0, NSHeight(layout.highlightRect) / 2.0);
            [[NSBezierPath bezierPathWithRoundedRect:layout.highlightRect xRadius:radius yRadius:radius] fill];
        }

        if (layout.imageRevealing) {
            CGFloat previewAlpha = contentAlpha * layout.reveal;
            [[NSColor colorWithWhite:1 alpha:0.10 * previewAlpha] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:layout.visibleThumbnailRect xRadius:8 yRadius:8] fill];

            NSImage *thumbnailImage = item.thumbnailImage ?: item.previewImage;
            if (thumbnailImage) {
                [thumbnailImage drawInRect:layout.visibleThumbnailRect
                                  fromRect:NSZeroRect
                                 operation:NSCompositingOperationSourceOver
                                  fraction:previewAlpha
                            respectFlipped:YES
                                     hints:nil];
            }

            [displayLine drawWithRect:layout.primaryTextRect
                       options:NSStringDrawingTruncatesLastVisibleLine
                    attributes:itemAttributes];
        } else if (layout.textExpanding) {
            [primaryLine drawWithRect:layout.primaryTextRect
                              options:NSStringDrawingTruncatesLastVisibleLine
                           attributes:itemAttributes];

            if (continuationLine.length && layout.reveal > 0.01) {
                NSMutableDictionary *continuationAttributes = [itemAttributes mutableCopy];
                continuationAttributes[NSForegroundColorAttributeName] = [NSColor colorWithWhite:1 alpha:itemTextAlpha * layout.reveal];
                [continuationLine drawWithRect:layout.continuationTextRect
                                       options:NSStringDrawingTruncatesLastVisibleLine
                                    attributes:continuationAttributes];
            }
        } else {
            [displayLine drawWithRect:layout.primaryTextRect
                              options:NSStringDrawingTruncatesLastVisibleLine
                           attributes:itemAttributes];
        }

        rowTop += layout.rowHeight;
    }
}

@end
