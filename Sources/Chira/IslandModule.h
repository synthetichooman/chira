#import <AppKit/AppKit.h>
#import "ChiraConstants.h"

@interface IslandModule : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSArray<NSString *> *items;
@property (nonatomic, strong) NSColor *accentColor;
@property (nonatomic) ChiraModuleStyle style;
@property (nonatomic) double progress;

+ (instancetype)moduleWithIdentifier:(NSString *)identifier
                                title:(NSString *)title
                             subtitle:(NSString *)subtitle
                                items:(NSArray<NSString *> *)items
                          accentColor:(NSColor *)accentColor
                                style:(ChiraModuleStyle)style
                             progress:(double)progress;
@end
