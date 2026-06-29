#import "ClipboardHistoryItem.h"
#import "ChiraConstants.h"

static NSString *ChiraMiddleTruncatedString(NSString *string, NSUInteger limit) {
    if (string.length <= limit) return string;
    if (limit < 10) return [string substringToIndex:limit];

    NSUInteger headLength = (limit - 3) / 2;
    NSUInteger tailLength = limit - 3 - headLength;
    NSString *head = [string substringToIndex:headLength];
    NSString *tail = [string substringFromIndex:string.length - tailLength];
    return [NSString stringWithFormat:@"%@...%@", head, tail];
}

static NSURL *ChiraFirstPasteboardURL(NSPasteboard *pasteboard, BOOL fileOnly) {
    NSDictionary *options = @{ NSPasteboardURLReadingFileURLsOnlyKey: @(fileOnly) };
    NSArray<NSURL *> *urls = [pasteboard readObjectsForClasses:@[NSURL.class] options:options];
    for (NSURL *url in urls) {
        if (fileOnly == url.isFileURL) return url;
    }

    NSPasteboardType type = fileOnly ? NSPasteboardTypeFileURL : NSPasteboardTypeURL;
    NSString *urlString = [pasteboard stringForType:type];
    NSURL *url = urlString.length ? [NSURL URLWithString:urlString] : nil;
    if (url && fileOnly == url.isFileURL) return url;

    return nil;
}

static BOOL ChiraIsImageExtension(NSString *extension) {
    NSSet<NSString *> *imageExtensions = [NSSet setWithArray:@[@"png", @"jpg", @"jpeg", @"gif", @"webp", @"heic", @"heif", @"tif", @"tiff", @"avif"]];
    return [imageExtensions containsObject:extension.lowercaseString];
}

static NSString *ChiraImageNameFromPasteboard(NSPasteboard *pasteboard) {
    NSURL *fileURL = ChiraFirstPasteboardURL(pasteboard, YES);
    NSString *filename = fileURL.lastPathComponent;
    if (filename.length) {
        return ChiraMiddleTruncatedString(filename, 36);
    }

    NSURL *url = ChiraFirstPasteboardURL(pasteboard, NO);
    NSString *urlFilename = url.lastPathComponent;
    NSString *extension = urlFilename.pathExtension.lowercaseString;
    if (urlFilename.length && ChiraIsImageExtension(extension)) {
        return ChiraMiddleTruncatedString(urlFilename, 36);
    }
    if (url.host.length) {
        return [NSString stringWithFormat:@"Image from %@", ChiraMiddleTruncatedString(url.host, 28)];
    }

    return nil;
}

static NSString *ChiraImageTypeLabel(NSPasteboardType pasteboardType) {
    if ([pasteboardType isEqualToString:NSPasteboardTypePNG]) return @"PNG";
    if ([pasteboardType isEqualToString:NSPasteboardTypeTIFF]) return @"TIFF";
    if ([pasteboardType localizedCaseInsensitiveContainsString:@"jpeg"] ||
        [pasteboardType localizedCaseInsensitiveContainsString:@"jpg"]) return @"JPEG";
    if ([pasteboardType localizedCaseInsensitiveContainsString:@"gif"]) return @"GIF";
    return @"Image";
}

static NSString *ChiraShortImageFingerprint(NSData *data) {
    if (!data.length) return @"0000";

    const uint8_t *bytes = data.bytes;
    NSUInteger count = MIN((NSUInteger)32768, data.length);
    uint32_t hash = 2166136261u;
    for (NSUInteger index = 0; index < count; index++) {
        hash ^= bytes[index];
        hash *= 16777619u;
    }
    return [NSString stringWithFormat:@"%04X", hash & 0xFFFF];
}

static NSSize ChiraPixelSizeForImage(NSImage *image) {
    if (!image) return NSZeroSize;

    CGImageRef cgImage = [image CGImageForProposedRect:nil context:nil hints:nil];
    if (cgImage) {
        return NSMakeSize(CGImageGetWidth(cgImage), CGImageGetHeight(cgImage));
    }
    return image.size;
}

static NSString *ChiraGeneratedImageLabel(NSData *data, NSPasteboardType type, NSImage *image) {
    NSSize size = ChiraPixelSizeForImage(image);
    NSString *typeLabel = ChiraImageTypeLabel(type);
    NSString *fingerprint = ChiraShortImageFingerprint(data);

    if (size.width > 0 && size.height > 0) {
        return [NSString stringWithFormat:@"Image %.0fx%.0f - %@ - %@", size.width, size.height, typeLabel, fingerprint];
    }
    return [NSString stringWithFormat:@"Image - %@ - %@", typeLabel, fingerprint];
}

static NSString *ChiraDisplayTextForImage(NSPasteboard *pasteboard, NSData *data, NSPasteboardType type, NSImage *image) {
    NSString *sourceName = ChiraImageNameFromPasteboard(pasteboard);
    if (sourceName.length) return sourceName;
    return ChiraGeneratedImageLabel(data, type, image);
}

static ClipboardHistoryItem *ChiraImageItemFromFileURL(NSPasteboard *pasteboard, NSURL *fileURL) {
    if (!fileURL.isFileURL || !ChiraIsImageExtension(fileURL.pathExtension)) return nil;

    NSImage *image = [[NSImage alloc] initWithContentsOfURL:fileURL];
    NSData *data = nil;
    NSPasteboardType type = NSPasteboardTypeTIFF;

    if ([fileURL.pathExtension.lowercaseString isEqualToString:@"png"]) {
        data = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe error:nil];
        type = NSPasteboardTypePNG;
    } else if ([fileURL.pathExtension.lowercaseString isEqualToString:@"tif"] ||
               [fileURL.pathExtension.lowercaseString isEqualToString:@"tiff"]) {
        data = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe error:nil];
        type = NSPasteboardTypeTIFF;
    } else {
        data = image.TIFFRepresentation;
    }

    if (!data.length || !image) return nil;

    ClipboardHistoryItem *item = [ClipboardHistoryItem new];
    item.dataValue = data;
    item.pasteboardType = type;
    item.previewImage = image;
    item.image = YES;
    item.displayText = ChiraDisplayTextForImage(pasteboard, data, type, image);
    return item;
}

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
    ClipboardHistoryItem *fileImageItem = ChiraImageItemFromFileURL(pasteboard, ChiraFirstPasteboardURL(pasteboard, YES));
    if (fileImageItem) return fileImageItem;

    NSData *pngData = [pasteboard dataForType:NSPasteboardTypePNG];
    NSData *tiffData = [pasteboard dataForType:NSPasteboardTypeTIFF];
    NSData *imageData = pngData.length ? pngData : tiffData;
    NSPasteboardType imageType = pngData.length ? NSPasteboardTypePNG : NSPasteboardTypeTIFF;

    if (imageData.length) {
        ClipboardHistoryItem *item = [ClipboardHistoryItem new];
        item.dataValue = imageData;
        item.pasteboardType = imageType;
        item.image = YES;
        item.previewImage = [[NSImage alloc] initWithData:imageData];
        item.displayText = ChiraDisplayTextForImage(pasteboard, imageData, imageType, item.previewImage);
        return item;
    }

    NSImage *pasteboardImage = [[NSImage alloc] initWithPasteboard:pasteboard];
    NSData *pasteboardImageData = pasteboardImage.TIFFRepresentation;
    if (pasteboardImageData.length) {
        ClipboardHistoryItem *item = [ClipboardHistoryItem new];
        item.dataValue = pasteboardImageData;
        item.pasteboardType = NSPasteboardTypeTIFF;
        item.previewImage = pasteboardImage;
        item.image = YES;
        item.displayText = ChiraDisplayTextForImage(pasteboard, pasteboardImageData, NSPasteboardTypeTIFF, pasteboardImage);
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
