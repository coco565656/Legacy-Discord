#import <Cocoa/Cocoa.h>
#import "DLTwemojiRenderer.h"

static void Require(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSArray *catalog = [DLTwemojiRenderer standardEmojiItems];
    Require([catalog count] == 3781, "bundled standard catalog incomplete");
    for (NSDictionary *item in catalog) {
        NSAutoreleasePool *imagePool = [[NSAutoreleasePool alloc] init];
        NSImage *image = [DLTwemojiRenderer imageForEmoji:[item objectForKey:@"name"] size:18.0];
        Require(image && [image isValid], "catalog entry has no valid PNG");
        [imagePool drain];
    }

    NSString *source = @"日本語 😀 ❤️ 👍 👍🏻 🇯🇵 1️⃣ 👩‍💻 👨‍👩‍👧‍👦\nemoji at end 😀";
    NSMutableAttributedString *text = [[[NSMutableAttributedString alloc]
        initWithString:source attributes:[NSDictionary dictionaryWithObject:@"preserved" forKey:@"style"]] autorelease];
    NSUInteger cursor = [source length];
    NSUInteger replaced = [DLTwemojiRenderer replaceEmojiInAttributedString:text size:18.0
        excludingAttribute:nil recordingAttribute:@"originalUnicode" cursorLocation:&cursor];
    Require(replaced == 9, "Unicode sequence split or missed");
    Require(cursor == [text length], "end cursor moved to wrong position");
    NSMutableString *restored = [NSMutableString string];
    NSUInteger attachmentCount = 0;
    for (NSUInteger index = 0; index < [text length]; index++) {
        NSString *original = [text attribute:@"originalUnicode" atIndex:index effectiveRange:NULL];
        if (original) {
            Require([text attribute:NSAttachmentAttributeName atIndex:index effectiveRange:NULL] != nil,
                    "Unicode replacement lost its image attachment");
            Require([[text attribute:@"style" atIndex:index effectiveRange:NULL] isEqual:@"preserved"],
                    "emoji replacement lost surrounding text attributes");
            [restored appendString:original];
            attachmentCount++;
        } else {
            [restored appendString:[[text string] substringWithRange:NSMakeRange(index, 1)]];
        }
    }
    Require(attachmentCount == 9 && [restored isEqualToString:source], "logical Unicode text changed");
    Require([DLTwemojiRenderer replaceEmojiInAttributedString:text size:18.0
        excludingAttribute:nil recordingAttribute:@"originalUnicode" cursorLocation:&cursor] == 0,
        "normalizing already converted content changed it again");

    NSMutableAttributedString *excluded = [[[NSMutableAttributedString alloc] initWithString:@"😀 👍"] autorelease];
    [excluded addAttribute:@"literal" value:[NSNumber numberWithBool:YES] range:NSMakeRange(0, 2)];
    Require([DLTwemojiRenderer replaceEmojiInAttributedString:excluded size:18.0
        excludingAttribute:@"literal" recordingAttribute:nil cursorLocation:NULL] == 1,
        "excluded text converted unexpectedly");
    NSMutableAttributedString *inside = [[[NSMutableAttributedString alloc] initWithString:@"A👍🏻B"] autorelease];
    cursor = 3;
    [DLTwemojiRenderer replaceEmojiInAttributedString:inside size:18.0
        excludingAttribute:nil recordingAttribute:nil cursorLocation:&cursor];
    Require(cursor == 2 && [[inside string] length] == 3, "cursor inside a combined emoji is invalid");
    printf("PASS: %lu catalog images; Unicode round trip, variants, flags, keycaps, ZWJ, attributes and cursor\n",
           (unsigned long)[catalog count]);
    [pool drain];
    return 0;
}
