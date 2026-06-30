#import "ClipboardHistoryItem.h"
#import "ChiraConstants.h"
#import <ImageIO/ImageIO.h>

static const CGFloat ChiraClipboardThumbnailSide = 58.0;
static const NSUInteger ChiraMaxInMemoryImageDataBytes = 1024 * 1024;

@interface ClipboardHistoryItem ()
@property (nonatomic, strong) NSURL *dataFileURL;
@property (nonatomic, copy) NSString *dataFingerprint;
@property (nonatomic) NSUInteger dataLength;
- (void)recordImageDataIdentityIfNeeded;
- (void)spillImageDataToDiskIfNeeded;
@end

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

static NSSize ChiraPixelSizeForImageData(NSData *data) {
    if (!data.length) return NSZeroSize;

    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, nil);
    if (!source) return NSZeroSize;

    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, nil));
    CFRelease(source);

    NSNumber *width = properties[(NSString *)kCGImagePropertyPixelWidth];
    NSNumber *height = properties[(NSString *)kCGImagePropertyPixelHeight];
    if (width.doubleValue <= 0 || height.doubleValue <= 0) return NSZeroSize;
    return NSMakeSize(width.doubleValue, height.doubleValue);
}

static NSData *ChiraPNGDataForImage(NSImage *image) {
    if (!image) return nil;

    CGImageRef cgImage = [image CGImageForProposedRect:nil context:nil hints:nil];
    if (!cgImage) return nil;

    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

static NSImage *ChiraThumbnailImageForImageData(NSData *data) {
    if (!data.length) return nil;

    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, nil);
    if (!source) return nil;

    NSDictionary *options = @{
        (NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (NSString *)kCGImageSourceShouldCacheImmediately: @NO,
        (NSString *)kCGImageSourceThumbnailMaxPixelSize: @(ChiraClipboardThumbnailSide * 2.0)
    };
    CGImageRef thumbnailRef = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!thumbnailRef) return nil;

    NSImage *thumbnail = [[NSImage alloc] initWithCGImage:thumbnailRef
                                                     size:NSMakeSize(ChiraClipboardThumbnailSide, ChiraClipboardThumbnailSide)];
    CGImageRelease(thumbnailRef);
    return thumbnail;
}

static NSImage *ChiraThumbnailImageForImage(NSImage *image) {
    if (!image) return nil;

    NSSize imageSize = image.size;
    if (imageSize.width <= 0 || imageSize.height <= 0) {
        imageSize = ChiraPixelSizeForImage(image);
    }
    if (imageSize.width <= 0 || imageSize.height <= 0) return nil;

    CGFloat side = ChiraClipboardThumbnailSide;
    CGFloat scale = MIN(side / imageSize.width, side / imageSize.height);
    NSSize drawSize = NSMakeSize(floor(imageSize.width * scale), floor(imageSize.height * scale));
    NSRect drawRect = NSMakeRect(floor((side - drawSize.width) / 2.0),
                                 floor((side - drawSize.height) / 2.0),
                                 drawSize.width,
                                 drawSize.height);

    NSImage *thumbnail = [[NSImage alloc] initWithSize:NSMakeSize(side, side)];
    [thumbnail lockFocus];
    [NSColor.clearColor setFill];
    NSRectFill(NSMakeRect(0, 0, side, side));
    [image drawInRect:drawRect
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:1.0
        respectFlipped:NO
                 hints:nil];
    [thumbnail unlockFocus];
    return thumbnail;
}

static NSString *ChiraGeneratedImageLabel(NSData *data, NSPasteboardType type, NSImage *image) {
    NSSize size = ChiraPixelSizeForImageData(data);
    if (size.width <= 0 || size.height <= 0) {
        size = ChiraPixelSizeForImage(image);
    }
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

static NSPasteboardType ChiraPasteboardTypeForImageExtension(NSString *extension) {
    NSString *lowercaseExtension = extension.lowercaseString;
    if ([lowercaseExtension isEqualToString:@"png"]) return NSPasteboardTypePNG;
    if ([lowercaseExtension isEqualToString:@"tif"] || [lowercaseExtension isEqualToString:@"tiff"]) return NSPasteboardTypeTIFF;
    if ([lowercaseExtension isEqualToString:@"jpg"] || [lowercaseExtension isEqualToString:@"jpeg"]) return (NSPasteboardType)@"public.jpeg";
    if ([lowercaseExtension isEqualToString:@"gif"]) return (NSPasteboardType)@"com.compuserve.gif";
    if ([lowercaseExtension isEqualToString:@"heic"]) return (NSPasteboardType)@"public.heic";
    if ([lowercaseExtension isEqualToString:@"heif"]) return (NSPasteboardType)@"public.heif";
    return nil;
}

static NSString *ChiraFileExtensionForPasteboardType(NSPasteboardType type) {
    if ([type isEqualToString:NSPasteboardTypePNG]) return @"png";
    if ([type isEqualToString:NSPasteboardTypeTIFF]) return @"tiff";
    if ([type localizedCaseInsensitiveContainsString:@"jpeg"] ||
        [type localizedCaseInsensitiveContainsString:@"jpg"]) return @"jpg";
    if ([type localizedCaseInsensitiveContainsString:@"gif"]) return @"gif";
    if ([type localizedCaseInsensitiveContainsString:@"heic"]) return @"heic";
    if ([type localizedCaseInsensitiveContainsString:@"heif"]) return @"heif";
    return @"image";
}

static ClipboardHistoryItem *ChiraImageItemFromFileURL(NSPasteboard *pasteboard, NSURL *fileURL, BOOL preparesPreview) {
    if (!fileURL.isFileURL || !ChiraIsImageExtension(fileURL.pathExtension)) return nil;

    NSData *data = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe error:nil];
    NSPasteboardType type = ChiraPasteboardTypeForImageExtension(fileURL.pathExtension);
    NSImage *image = nil;
    if (!type) {
        image = [[NSImage alloc] initWithContentsOfURL:fileURL];
        data = ChiraPNGDataForImage(image);
        type = NSPasteboardTypePNG;
    }
    if (!data.length || !type.length) return nil;

    ClipboardHistoryItem *item = [ClipboardHistoryItem new];
    item.dataValue = data;
    item.pasteboardType = type;
    item.image = YES;
    if (preparesPreview) {
        item.thumbnailImage = ChiraThumbnailImageForImageData(data);
    }
    if (preparesPreview && !item.thumbnailImage && image) {
        item.previewImage = image;
        [item prepareThumbnailIfNeeded];
    }
    item.displayText = ChiraDisplayTextForImage(pasteboard, data, type, image);
    if (item.thumbnailImage) item.previewImage = nil;
    [item recordImageDataIdentityIfNeeded];
    [item spillImageDataToDiskIfNeeded];
    return item;
}

@implementation ClipboardHistoryItem

- (void)dealloc {
    if (self.dataFileURL) {
        [NSFileManager.defaultManager removeItemAtURL:self.dataFileURL error:nil];
    }
}

- (void)recordImageDataIdentityIfNeeded {
    if (!self.image || !self.dataValue.length) return;

    self.dataLength = self.dataValue.length;
    if (!self.dataFingerprint.length) {
        self.dataFingerprint = ChiraShortImageFingerprint(self.dataValue);
    }
}

- (void)spillImageDataToDiskIfNeeded {
    if (!self.image || self.dataFileURL || self.dataValue.length <= ChiraMaxInMemoryImageDataBytes) return;

    [self recordImageDataIdentityIfNeeded];

    NSString *directoryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ChiraClipboardItems"];
    NSURL *directoryURL = [NSURL fileURLWithPath:directoryPath isDirectory:YES];
    if (![NSFileManager.defaultManager createDirectoryAtURL:directoryURL
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil]) {
        return;
    }

    NSString *extension = ChiraFileExtensionForPasteboardType(self.pasteboardType);
    NSString *filename = [NSString stringWithFormat:@"%@.%@", NSUUID.UUID.UUIDString, extension];
    NSURL *fileURL = [directoryURL URLByAppendingPathComponent:filename];
    if ([self.dataValue writeToURL:fileURL options:NSDataWritingAtomic error:nil]) {
        self.dataFileURL = fileURL;
        self.dataValue = nil;
    }
}

+ (instancetype)textItemWithString:(NSString *)string {
    if (!string.length) return nil;

    ClipboardHistoryItem *item = [ClipboardHistoryItem new];
    item.stringValue = string;
    item.displayText = ChiraDisplayTextForClipboardItem(string);
    item.image = NO;
    return item;
}

+ (instancetype)itemFromPasteboard:(NSPasteboard *)pasteboard {
    return [self itemFromPasteboard:pasteboard preparesPreview:YES];
}

+ (instancetype)itemFromPasteboard:(NSPasteboard *)pasteboard preparesPreview:(BOOL)preparesPreview {
    ClipboardHistoryItem *fileImageItem = ChiraImageItemFromFileURL(pasteboard, ChiraFirstPasteboardURL(pasteboard, YES), preparesPreview);
    if (fileImageItem) return fileImageItem;

    NSData *pngData = [pasteboard dataForType:NSPasteboardTypePNG];
    NSData *tiffData = [pasteboard dataForType:NSPasteboardTypeTIFF];

    if (pngData.length || tiffData.length) {
        ClipboardHistoryItem *item = [ClipboardHistoryItem new];
        item.image = YES;
        if (pngData.length) {
            item.dataValue = pngData;
            item.pasteboardType = NSPasteboardTypePNG;
        } else {
            item.dataValue = tiffData;
            item.pasteboardType = NSPasteboardTypeTIFF;
        }
        if (preparesPreview) {
            item.thumbnailImage = ChiraThumbnailImageForImageData(item.dataValue);
        }
        if (preparesPreview && !item.thumbnailImage) {
            item.previewImage = [[NSImage alloc] initWithData:item.dataValue];
            [item prepareThumbnailIfNeeded];
        }
        item.displayText = ChiraDisplayTextForImage(pasteboard, item.dataValue, item.pasteboardType, item.previewImage);
        if (item.thumbnailImage) item.previewImage = nil;
        [item recordImageDataIdentityIfNeeded];
        [item spillImageDataToDiskIfNeeded];
        return item;
    }

    NSImage *pasteboardImage = [[NSImage alloc] initWithPasteboard:pasteboard];
    NSData *pasteboardImageData = ChiraPNGDataForImage(pasteboardImage);
    NSPasteboardType pasteboardImageType = NSPasteboardTypePNG;
    if (!pasteboardImageData.length) {
        pasteboardImageData = pasteboardImage.TIFFRepresentation;
        pasteboardImageType = NSPasteboardTypeTIFF;
    }
    if (pasteboardImageData.length) {
        ClipboardHistoryItem *item = [ClipboardHistoryItem new];
        item.dataValue = pasteboardImageData;
        item.pasteboardType = pasteboardImageType;
        item.previewImage = pasteboardImage;
        item.image = YES;
        item.displayText = ChiraDisplayTextForImage(pasteboard, pasteboardImageData, pasteboardImageType, pasteboardImage);
        if (preparesPreview) {
            [item prepareThumbnailIfNeeded];
        }
        if (item.thumbnailImage) item.previewImage = nil;
        [item recordImageDataIdentityIfNeeded];
        [item spillImageDataToDiskIfNeeded];
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
        if (![self.pasteboardType isEqualToString:item.pasteboardType]) return NO;
        if (self.dataValue.length && item.dataValue.length) {
            return [self.dataValue isEqualToData:item.dataValue];
        }
        return self.dataLength > 0 &&
            self.dataLength == item.dataLength &&
            self.dataFingerprint.length > 0 &&
            [self.dataFingerprint isEqualToString:item.dataFingerprint];
    }
    return [self.stringValue isEqualToString:item.stringValue];
}

- (void)prepareThumbnailIfNeeded {
    if (!self.image || self.thumbnailImage) return;

    NSData *data = self.dataValue;
    if (!data.length && self.dataFileURL) {
        data = [NSData dataWithContentsOfURL:self.dataFileURL options:NSDataReadingMappedIfSafe error:nil];
    }
    if (data.length) {
        self.thumbnailImage = ChiraThumbnailImageForImageData(data);
        if (self.thumbnailImage) return;
    }

    if (!self.previewImage) return;

    self.thumbnailImage = ChiraThumbnailImageForImage(self.previewImage);
}

- (void)writeToPasteboard:(NSPasteboard *)pasteboard {
    [pasteboard clearContents];

    if (self.image && self.pasteboardType.length) {
        NSData *data = self.dataValue;
        if (!data.length && self.dataFileURL) {
            data = [NSData dataWithContentsOfURL:self.dataFileURL options:NSDataReadingMappedIfSafe error:nil];
        }
        if (data.length) {
            [pasteboard setData:data forType:self.pasteboardType];
        }
        return;
    }

    if (self.stringValue.length) {
        [pasteboard setString:self.stringValue forType:NSPasteboardTypeString];
    }
}

@end
