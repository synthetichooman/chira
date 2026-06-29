#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, ChiraIslandMode) {
    ChiraIslandModeIdle = 0,
    ChiraIslandModeClipboard
};

typedef NS_ENUM(NSInteger, ChiraModuleStyle) {
    ChiraModuleStyleDefault = 0,
    ChiraModuleStyleList,
    ChiraModuleStyleProgress
};

extern NSString * const ChiraModuleIdentifierClipboard;

NSString *ChiraDisplayTextForClipboardItem(NSString *item);
