#import "ClipboardHistoryItem.h"
#import "ChiraConstants.h"

@implementation ClipboardHistoryItem

+ (instancetype)textItemWithString:(NSString *)string {
    if (!string.length) return nil;

    ClipboardHistoryItem *item = [ClipboardHistoryItem new];
    item.stringValue = string;
    item.displayText = ChiraDisplayTextForClipboardItem(string);
    item.image = NO;
    return item;
}

+ (instancetype)itemFromPasteboard:(NSPasteboard *)pasteboard {
    NSData *pngData = [pasteboard dataForType:NSPasteboardTypePNG];
    NSData *tiffData = [pasteboard dataForType:NSPasteboardTypeTIFF];
    NSData *imageData = pngData.length ? pngData : tiffData;
    NSPasteboardType imageType = pngData.length ? NSPasteboardTypePNG : NSPasteboardTypeTIFF;

    if (imageData.length) {
        ClipboardHistoryItem *item = [ClipboardHistoryItem new];
        item.dataValue = imageData;
        item.pasteboardType = imageType;
        item.image = YES;

        NSImage *image = [[NSImage alloc] initWithData:imageData];
        if (image && image.size.width > 0 && image.size.height > 0) {
            item.displayText = [NSString stringWithFormat:@"Image - %.0fx%.0f", image.size.width, image.size.height];
        } else {
            item.displayText = @"Image copied";
        }
        return item;
    }

    NSString *text = [pasteboard stringForType:NSPasteboardTypeString];
    if (text.length) {
        return [ClipboardHistoryItem textItemWithString:text];
    }

    if ([pasteboard.types containsObject:NSPasteboardTypeFileURL]) {
        return [ClipboardHistoryItem textItemWithString:@"File copied"];
    }
    return nil;
}

- (BOOL)matchesItem:(ClipboardHistoryItem *)item {
    if (!item || self.image != item.image) return NO;
    if (self.image) {
        return [self.pasteboardType isEqualToString:item.pasteboardType] && [self.dataValue isEqualToData:item.dataValue];
    }
    return [self.stringValue isEqualToString:item.stringValue];
}

- (void)writeToPasteboard:(NSPasteboard *)pasteboard {
    [pasteboard clearContents];

    if (self.image && self.dataValue.length && self.pasteboardType.length) {
        [pasteboard setData:self.dataValue forType:self.pasteboardType];
        return;
    }

    if (self.stringValue.length) {
        [pasteboard setString:self.stringValue forType:NSPasteboardTypeString];
    }
}

@end
