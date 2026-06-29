#import <AppKit/AppKit.h>
#import "ChiraConstants.h"
#import "IslandModule.h"

@class IslandView;

@protocol IslandViewDelegate <NSObject>
- (void)islandView:(IslandView *)view didSelectClipboardItemAtIndex:(NSInteger)index;
@end

@interface IslandView : NSView
@property (nonatomic) ChiraIslandMode mode;
@property (nonatomic) BOOL hovering;
@property (nonatomic) BOOL pointerNearNotch;
@property (nonatomic, copy) NSString *clipboardSummary;
@property (nonatomic, copy) NSArray<NSString *> *clipboardItems;
@property (nonatomic, copy) NSArray<IslandModule *> *modules;
@property (nonatomic, weak) id<IslandViewDelegate> delegate;
@property (nonatomic) CGFloat topSafeInset;
@property (nonatomic) CGFloat notchWidth;

- (void)setMode:(ChiraIslandMode)mode transientDuration:(NSTimeInterval)duration;
- (BOOL)containsInteractivePoint:(NSPoint)point;
@end
