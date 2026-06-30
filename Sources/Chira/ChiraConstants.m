#import "ChiraConstants.h"

NSString *ChiraDisplayTextForClipboardItem(NSString *item) {
    if (!item.length) return @"";

    NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSArray<NSString *> *parts = [item componentsSeparatedByCharactersInSet:whitespace];
    NSString *collapsed = [[parts filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *part, NSDictionary *bindings) {
        (void)bindings;
        return part.length > 0;
    }]] componentsJoinedByString:@" "];

    if (collapsed.length > 84) {
        return [[collapsed substringToIndex:84] stringByAppendingString:@"..."];
    }
    return collapsed.length ? collapsed : item;
}
