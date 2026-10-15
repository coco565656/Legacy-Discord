#import <Cocoa/Cocoa.h>

@interface DLTwemojiRenderer : NSObject

+ (NSImage *)imageForEmoji:(NSString *)emoji size:(CGFloat)size;
+ (NSArray *)standardEmojiItems;
+ (NSString *)displayNameForEmoji:(NSString *)emoji;
+ (void)setText:(NSString *)text forLabel:(NSTextField *)label;
+ (NSUInteger)replaceEmojiInAttributedString:(NSMutableAttributedString *)text
                                       size:(CGFloat)size
                         excludingAttribute:(NSString *)attributeName
                        recordingAttribute:(NSString *)recordingAttribute
                             cursorLocation:(NSUInteger *)cursorLocation;

@end
