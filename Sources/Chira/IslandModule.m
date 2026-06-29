#import "IslandModule.h"

@implementation IslandModule

+ (instancetype)moduleWithIdentifier:(NSString *)identifier
                                title:(NSString *)title
                             subtitle:(NSString *)subtitle
                                items:(NSArray<NSString *> *)items
                          accentColor:(NSColor *)accentColor
                                style:(ChiraModuleStyle)style
                             progress:(double)progress {
    IslandModule *module = [IslandModule new];
    module.identifier = identifier ?: @"";
    module.title = title ?: @"";
    module.subtitle = subtitle ?: @"";
    module.items = items ?: @[];
    module.accentColor = accentColor ?: NSColor.whiteColor;
    module.style = style;
    module.progress = fmin(fmax(progress, 0), 1);
    return module;
}

@end
