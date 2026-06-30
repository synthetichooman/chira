#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, ChiraIslandMode) {
    ChiraIslandModeIdle = 0,
    ChiraIslandModeClipboard
};

NSString *ChiraDisplayTextForClipboardItem(NSString *item);
