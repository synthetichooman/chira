#import <AppKit/AppKit.h>

@interface ClipboardHistoryItem : NSObject
@property (nonatomic, copy) NSString *displayText;
@property (nonatomic, copy) NSString *stringValue;
@property (nonatomic, copy) NSData *dataValue;
@property (nonatomic, copy) NSPasteboardType pasteboardType;
@property (nonatomic) BOOL image;

+ (instancetype)textItemWithString:(NSString *)string;
+ (instancetype)itemFromPasteboard:(NSPasteboard *)pasteboard;
- (BOOL)matchesItem:(ClipboardHistoryItem *)item;
- (void)writeToPasteboard:(NSPasteboard *)pasteboard;
@end
