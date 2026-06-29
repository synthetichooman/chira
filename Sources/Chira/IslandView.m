#import "IslandView.h"

static const CGFloat ChiraMacBookPro14NotchWidth = 210.0;
static const CGFloat ChiraFloatingHiddenWidth = 168.0;
static const CGFloat ChiraFloatingHiddenHeight = 30.0;
static const CGFloat ChiraFloatingTopMargin = 8.0;
static const CGFloat ChiraIngestPulseVerticalDrop = 11.0;

@implementation IslandView {
    NSTrackingArea *_trackingArea;
    NSTimer *_animationTimer;
    NSTimer *_collapseTimer;
    NSTimer *_ingestPulseTimer;
    CGFloat _progress;
    CGFloat _targetProgress;
    CGFloat _ingestPulse;
    NSTimeInterval _ingestPulseStartTime;
    NSInteger _pressedClipboardIndex;
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
    _ingestPulse = 0;
    _pressedClipboardIndex = -1;
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
    _trackingArea = nil;
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect islandRect = [self currentIslandRect];
    if (!NSPointInRect(point, islandRect)) return;

    IslandModule *module = [self displayModule];
    NSInteger index = [self clipboardItemIndexAtPoint:point forModule:module inIslandRect:islandRect];
    if (index >= 0) {
        _pressedClipboardIndex = index;
        _pressedClipboardInside = YES;
        [self setNeedsDisplay:YES];
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
        [self setNeedsDisplay:YES];
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
    [self setNeedsDisplay:YES];

    if (releaseIndex == pressedIndex) {
        [self.delegate islandView:self didSelectClipboardItemAtIndex:pressedIndex];
    }
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
    [self setNeedsDisplay:YES];
}

- (void)playClipboardIngestPulse {
    _ingestPulseStartTime = NSDate.timeIntervalSinceReferenceDate;
    _ingestPulse = 0.0;

    [_ingestPulseTimer invalidate];
    _ingestPulseTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                                         target:self
                                                       selector:@selector(ingestPulseTick)
                                                       userInfo:nil
                                                        repeats:YES];
    [self setNeedsDisplay:YES];
}

- (void)ingestPulseTick {
    NSTimeInterval elapsed = NSDate.timeIntervalSinceReferenceDate - _ingestPulseStartTime;
    CGFloat duration = 0.42;
    CGFloat t = MIN(1.0, MAX(0.0, elapsed / duration));

    CGFloat down = sin(t * M_PI);
    CGFloat rebound = 0.12 * sin(t * M_PI * 4.0) * (1.0 - t);
    _ingestPulse = MAX(0.0, down + rebound);

    if (t >= 1.0) {
        _ingestPulse = 0;
        [_ingestPulseTimer invalidate];
        _ingestPulseTimer = nil;
    }
    [self setNeedsDisplay:YES];
}

- (void)collapseTransientMode {
    if (self.mode != ChiraIslandModeClipboard || !self.hovering) {
        self.mode = ChiraIslandModeIdle;
    }
    [self updateTargetProgress];
    [self setNeedsDisplay:YES];
}

- (void)updateTargetProgress {
    _targetProgress = (self.pointerNearNotch || self.hovering || self.mode != ChiraIslandModeIdle) ? 1.0 : 0.0;
    if (!_animationTimer) {
        _animationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                                           target:self
                                                         selector:@selector(animationTick)
                                                         userInfo:nil
                                                          repeats:YES];
    }
}

- (void)setPointerNearNotch:(BOOL)pointerNearNotch {
    if (_pointerNearNotch == pointerNearNotch) return;

    _pointerNearNotch = pointerNearNotch;
    if (!pointerNearNotch && !self.hovering && self.mode == ChiraIslandModeClipboard) {
        self.mode = ChiraIslandModeIdle;
    }
    [self updateTargetProgress];
    [self setNeedsDisplay:YES];
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

- (NSArray<NSDictionary *> *)clipboardItemCopyTargetsForModule:(IslandModule *)module inIslandRect:(NSRect)rect {
    if (![module.identifier isEqualToString:ChiraModuleIdentifierClipboard] || module.items.count == 0) {
        return @[];
    }

    CGFloat contentTop = NSMinY(rect) + MAX(self.topSafeInset + 12, 18);
    CGFloat horizontalPadding = 40;
    CGFloat listTop = contentTop + 42;
    CGFloat rowHeight = 28;
    CGFloat contentX = NSMinX(rect) + horizontalPadding;
    CGFloat contentWidth = NSWidth(rect) - horizontalPadding * 2;
    NSDictionary *targetAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold]
    };

    NSMutableArray<NSDictionary *> *targets = [NSMutableArray array];
    NSInteger count = MIN((NSInteger)module.items.count, 5);
    for (NSInteger index = 0; index < count; index++) {
        NSString *line = [NSString stringWithFormat:@"%ld  %@", (long)(index + 1), ChiraDisplayTextForClipboardItem(module.items[index])];
        CGFloat textWidth = ceil([line sizeWithAttributes:targetAttributes].width);
        CGFloat targetWidth = MIN(contentWidth, textWidth + 8);
        CGFloat rowTop = listTop + index * rowHeight;
        [targets addObject:@{
            @"rect": [NSValue valueWithRect:NSMakeRect(contentX - 4, rowTop + 3, targetWidth, 22)],
            @"index": @(index)
        }];
    }
    return targets;
}

- (void)scrollWheel:(NSEvent *)event {
    [super scrollWheel:event];
}

- (void)animationTick {
    CGFloat delta = _targetProgress - _progress;
    if (fabs(delta) < 0.01) {
        _progress = _targetProgress;
        [_animationTimer invalidate];
        _animationTimer = nil;
    } else {
        _progress += delta * 0.22;
    }
    [self setNeedsDisplay:YES];
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
        NSInteger rowCount = MIN((NSInteger)module.items.count, 5);
        return rowCount > 0 ? 78 + rowCount * 28 : 96;
    }
    return 122;
}

- (BOOL)containsInteractivePoint:(NSPoint)point {
    if (_progress < 0.25) return NO;
    return NSPointInRect(point, [self currentIslandRect]);
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
    CGFloat radius = 18 + (30 - 18) * visualProgress;
    CGFloat topShoulderRadius = self.hasNotch ? 16 * visualProgress : 0;
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
    CGFloat contentTop = NSMinY(rect) + MAX(self.topSafeInset + 12, 18);
    CGFloat contentX = NSMinX(rect) + horizontalPadding;
    CGFloat contentWidth = NSWidth(rect) - horizontalPadding * 2;

    NSDictionary *primaryAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:contentAlpha]
    };
    NSDictionary *secondaryAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:0.62 * contentAlpha]
    };

    [primary drawWithRect:NSMakeRect(contentX, contentTop + 3, contentWidth, 18)
                  options:NSStringDrawingTruncatesLastVisibleLine
               attributes:primaryAttributes];

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
                         inRect:NSMakeRect(contentX, contentTop + 42, contentWidth, 140)
                    contentAlpha:contentAlpha];
        return;
    }

    [secondary drawWithRect:NSMakeRect(contentX, contentTop + 29, contentWidth, 18)
                    options:NSStringDrawingTruncatesLastVisibleLine
                 attributes:secondaryAttributes];
}

- (void)drawClipboardItems:(NSArray<NSString *> *)items inRect:(NSRect)rect contentAlpha:(CGFloat)contentAlpha {
    CGFloat rowHeight = 28;
    NSInteger count = MIN((NSInteger)items.count, 5);

    for (NSInteger index = 0; index < count; index++) {
        BOOL pressed = _pressedClipboardInside && _pressedClipboardIndex == index;
        NSDictionary *itemAttributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:12 weight:(pressed ? NSFontWeightSemibold : NSFontWeightMedium)],
            NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:(pressed ? 0.96 : 0.64) * contentAlpha]
        };
        NSString *line = [NSString stringWithFormat:@"%ld  %@", (long)(index + 1), ChiraDisplayTextForClipboardItem(items[index])];
        NSRect itemRect = NSMakeRect(NSMinX(rect), NSMinY(rect) + index * rowHeight + 5, NSWidth(rect), 18);
        [line drawWithRect:itemRect options:NSStringDrawingTruncatesLastVisibleLine attributes:itemAttributes];
    }
}

@end
