#import <AppKit/AppKit.h>
#import "ChiraConstants.h"

@class IslandView;
@class ClipboardHistoryItem;

@protocol IslandViewDelegate <NSObject>
- (void)islandView:(IslandView *)view didSelectClipboardItemAtIndex:(NSInteger)index;
- (void)islandViewDidRequestSettings:(IslandView *)view;
- (void)islandViewDidRequestQuit:(IslandView *)view;
@end

@interface IslandView : NSView
@property (nonatomic) ChiraIslandMode mode;
@property (nonatomic) BOOL hovering;
@property (nonatomic) BOOL pointerNearNotch;
@property (nonatomic, copy) NSArray<ClipboardHistoryItem *> *clipboardItems;
@property (nonatomic, weak) id<IslandViewDelegate> delegate;
@property (nonatomic) CGFloat topSafeInset;
@property (nonatomic) CGFloat notchWidth;
@property (nonatomic) BOOL hasNotch;
@property (nonatomic) NSInteger maxVisibleClipboardItems;
@property (nonatomic) BOOL showsImageClipboardPreviews;

- (void)setMode:(ChiraIslandMode)mode transientDuration:(NSTimeInterval)duration;
- (void)playClipboardIngestPulse;
- (BOOL)containsInteractivePoint:(NSPoint)point;
@end
