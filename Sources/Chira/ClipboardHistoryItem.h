#import <AppKit/AppKit.h>

@interface ClipboardHistoryItem : NSObject
@property (nonatomic, copy) NSString *displayText;
@property (nonatomic, copy) NSString *stringValue;
@property (nonatomic, copy) NSData *dataValue;
@property (nonatomic, copy) NSPasteboardType pasteboardType;
@property (nonatomic, strong) NSImage *previewImage;
@property (nonatomic, strong) NSImage *thumbnailImage;
@property (nonatomic) BOOL image;

+ (instancetype)textItemWithString:(NSString *)string;
+ (instancetype)itemFromPasteboard:(NSPasteboard *)pasteboard;
- (BOOL)matchesItem:(ClipboardHistoryItem *)item;
- (void)prepareThumbnailIfNeeded;
- (void)writeToPasteboard:(NSPasteboard *)pasteboard;
@end
