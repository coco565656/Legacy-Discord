//
//  DLTextParser.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/28/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLTextParser.h"
#import "DLUtil.h"
#import "HTTPCache.h"
#import "DLPreferencesHandler.h"
#import "DLTwemojiRenderer.h"

@implementation DLTextParser

const CGFloat MESSAGE_VIEW_FONT_SIZE = 13.0;
static NSString * const DLCodeSpanAttributeName = @"DLCodeSpanAttributeName";

static void DLApplyDelimitedAttributes(NSMutableAttributedString *text, NSString *delimiter, NSDictionary *attributes) {
    NSUInteger searchLocation = 0;
    NSUInteger delimiterLength = [delimiter length];
    while (searchLocation < [[text string] length]) {
        NSRange remaining = NSMakeRange(searchLocation, [[text string] length] - searchLocation);
        NSRange opening = [[text string] rangeOfString:delimiter options:0 range:remaining];
        if (opening.location == NSNotFound) break;
        if ([text attribute:DLCodeSpanAttributeName atIndex:opening.location effectiveRange:NULL]) {
            searchLocation = NSMaxRange(opening);
            continue;
        }
        NSUInteger contentLocation = NSMaxRange(opening);
        if (contentLocation >= [[text string] length]) break;
        NSRange closingSearch = NSMakeRange(contentLocation, [[text string] length] - contentLocation);
        NSRange closing = [[text string] rangeOfString:delimiter options:0 range:closingSearch];
        if (closing.location == NSNotFound) break;
        NSUInteger contentLength = closing.location - contentLocation;
        if (contentLength == 0) {
            searchLocation = NSMaxRange(closing);
            continue;
        }
        [text deleteCharactersInRange:closing];
        [text deleteCharactersInRange:opening];
        NSRange styledRange = NSMakeRange(opening.location, contentLength);
        NSEnumerator *keyEnumerator = [attributes keyEnumerator];
        id key;
        while (key = [keyEnumerator nextObject]) {
            [text addAttribute:key value:[attributes objectForKey:key] range:styledRange];
        }
        searchLocation = NSMaxRange(styledRange);
        if (delimiterLength == 0) break;
    }
}

static void DLApplyCodeBlocks(NSMutableAttributedString *text, CGFloat fontSize) {
    NSUInteger searchLocation = 0;
    NSString *delimiter = @"```";
    while (searchLocation < [[text string] length]) {
        NSRange remaining = NSMakeRange(searchLocation, [[text string] length] - searchLocation);
        NSRange opening = [[text string] rangeOfString:delimiter options:0 range:remaining];
        if (opening.location == NSNotFound) break;
        NSUInteger afterOpening = NSMaxRange(opening);
        NSRange closingSearch = NSMakeRange(afterOpening, [[text string] length] - afterOpening);
        NSRange closing = [[text string] rangeOfString:delimiter options:0 range:closingSearch];
        if (closing.location == NSNotFound) break;

        NSUInteger contentLocation = afterOpening;
        NSRange firstLineRange = NSMakeRange(afterOpening, closing.location - afterOpening);
        NSRange newline = [[text string] rangeOfString:@"\n" options:0 range:firstLineRange];
        if (newline.location != NSNotFound) {
            contentLocation = NSMaxRange(newline);
        }
        NSUInteger contentLength = closing.location - contentLocation;
        [text deleteCharactersInRange:closing];
        [text deleteCharactersInRange:NSMakeRange(opening.location, contentLocation - opening.location)];
        NSRange codeRange = NSMakeRange(opening.location, contentLength);
        NSFont *codeFont = [NSFont fontWithName:@"Menlo" size:fontSize];
        if (!codeFont) codeFont = [NSFont userFixedPitchFontOfSize:fontSize];
        [text addAttribute:NSFontAttributeName value:codeFont range:codeRange];
        [text addAttribute:NSBackgroundColorAttributeName value:[DLUtil nativeInputColor] range:codeRange];
        [text addAttribute:DLCodeSpanAttributeName value:[NSNumber numberWithBool:YES] range:codeRange];
        searchLocation = NSMaxRange(codeRange);
    }
}

static void DLApplyQuoteStyling(NSMutableAttributedString *text) {
    NSUInteger location = 0;
    while (location < [[text string] length]) {
        NSUInteger lineStart = 0;
        NSUInteger lineEnd = 0;
        NSUInteger contentsEnd = 0;
        [[text string] getLineStart:&lineStart end:&lineEnd contentsEnd:&contentsEnd forRange:NSMakeRange(location, 0)];
        NSRange lineRange = NSMakeRange(lineStart, contentsEnd - lineStart);
        NSString *line = [[text string] substringWithRange:lineRange];
        NSUInteger prefixLength = [line hasPrefix:@">>> "] ? 4 : ([line hasPrefix:@"> "] ? 2 : 0);
        if (prefixLength > 0) {
            [text replaceCharactersInRange:NSMakeRange(lineStart, prefixLength) withString:@"▎ "];
            [text addAttribute:NSForegroundColorAttributeName value:[DLUtil nativeSecondaryTextColor] range:NSMakeRange(lineStart, 1)];
            location = lineEnd - prefixLength + 2;
        } else {
            location = lineEnd;
        }
        if (lineEnd == lineStart) location++;
    }
}

+(NSColor *)DEFAULT_TEXT_COLOR {
    return [DLUtil nativePrimaryTextColor];
}

+(NSColor *)DEFAULT_TEXT_HIGHLIGHT_COLOR {
    return [NSColor selectedTextBackgroundColor];
}

+(NSColor *)DEFAULT_LINK_TEXT_COLOR {
    return [DLUtil nativeLinkColor];
}

+(BOOL)isEmojiOnlyMessage:(DLMessage *)m {
    NSString *content = [[m content] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([content length] == 0 || [content length] > 128) {
        return NO;
    }
    NSString *customEmojiRegex = @"<a?:[A-Za-z0-9_]+:[0-9]+>";
    NSArray *customEmoji = [content componentsMatchedByRegex:customEmojiRegex];
    NSString *remainder = [content stringByReplacingOccurrencesOfRegex:customEmojiRegex withString:@""];
    remainder = [remainder stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([remainder length] == 0) {
        return [customEmoji count] > 0;
    }
    return [remainder isMatchedByRegex:@"^(?:\\s|[\\p{So}\\p{Sk}\\x{FE0F}\\x{200D}\\x{20E3}])+$"];
}

+(NSAttributedString *)attributedContentStringForMessage:(DLMessage *)m {
    if ([[m content] length] > 0) {
        CGFloat displayScale = [[DLPreferencesHandler sharedInstance] messageDisplayScale];
        BOOL jumboEmoji = [self isEmojiOnlyMessage:m];
        CGFloat messageFontSize = (jumboEmoji ? 52.0 : MESSAGE_VIEW_FONT_SIZE) * displayScale;
        NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:[m content]];
        [as addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:messageFontSize] range:NSMakeRange(0, [m content].length)];
        [as addAttribute:NSForegroundColorAttributeName value:[DLTextParser DEFAULT_TEXT_COLOR] range:NSMakeRange(0, [m content].length)];
        
        NSString *userTagRegex = @"<@(!)?([0-9]*)>";
        NSString *userIDRegex = @"[0-9]+";
        
        NSArray *tagMatches = [[m content] componentsMatchedByRegex:userTagRegex];
        NSEnumerator *e = [tagMatches objectEnumerator];
        NSString *matchedTag;
        while (matchedTag = [e nextObject]) {
            NSString *userID = [matchedTag stringByMatching:userIDRegex];
            NSEnumerator *ee = [[m mentionedUsers] objectEnumerator];
            DLUser *user;
            while (user = [ee nextObject]) {
                if ([[user userID] isEqualToString:userID]) {
                    NSRange replacementRange = [[as string] rangeOfString:matchedTag];
                    if (replacementRange.location != NSNotFound && [user globalName]) {
                        NSString *globalName = [NSString stringWithFormat:@"@%@", [user globalName]];
                        [as replaceCharactersInRange:replacementRange withString:globalName];
                        [as addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:messageFontSize] range:NSMakeRange(replacementRange.location, globalName.length)];
                        [as addAttribute:NSBackgroundColorAttributeName value:[DLUtil nativeTagColor] range:NSMakeRange(replacementRange.location, globalName.length)];
                    }
                }
            }
        }

        if (!jumboEmoji) {
            NSFont *boldFont = [NSFont boldSystemFontOfSize:messageFontSize];
            NSDictionary *boldItalicAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                boldFont, NSFontAttributeName, [NSNumber numberWithFloat:0.20], NSObliquenessAttributeName, nil];
            DLApplyCodeBlocks(as, messageFontSize - 1.0);
            DLApplyDelimitedAttributes(as, @"`", [NSDictionary dictionaryWithObjectsAndKeys:
                ([NSFont fontWithName:@"Menlo" size:messageFontSize - 1.0] ? [NSFont fontWithName:@"Menlo" size:messageFontSize - 1.0] : [NSFont userFixedPitchFontOfSize:messageFontSize - 1.0]), NSFontAttributeName,
                [DLUtil nativeInputColor], NSBackgroundColorAttributeName,
                [NSNumber numberWithBool:YES], DLCodeSpanAttributeName, nil]);
            DLApplyDelimitedAttributes(as, @"***", boldItalicAttributes);
            DLApplyDelimitedAttributes(as, @"___", boldItalicAttributes);
            DLApplyDelimitedAttributes(as, @"**", [NSDictionary dictionaryWithObject:boldFont forKey:NSFontAttributeName]);
            DLApplyDelimitedAttributes(as, @"__", [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:NSUnderlineStyleSingle] forKey:NSUnderlineStyleAttributeName]);
            DLApplyDelimitedAttributes(as, @"~~", [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:NSUnderlineStyleSingle] forKey:NSStrikethroughStyleAttributeName]);
            DLApplyDelimitedAttributes(as, @"*", [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:0.20] forKey:NSObliquenessAttributeName]);
            DLApplyQuoteStyling(as);
        }
        
        NSInteger lastLocation = -1;
        while (lastLocation != NSNotFound) {
            NSRange everyoneRange = [[as string] rangeOfString:@"@everyone" options:0 range:NSMakeRange(lastLocation + 1, [as string].length - (lastLocation + 1))];
            lastLocation = everyoneRange.location;
            if (lastLocation != NSNotFound) {
                [as addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:messageFontSize] range:everyoneRange];
                [as addAttribute:NSBackgroundColorAttributeName value:[DLUtil nativeTagColor] range:everyoneRange];
            }
        }
        
        NSString *urlRegex = @"(?i)\\b(?:(?:https?|ftp)://)(?:\\S+(?::\\S*)?@)?(?:(?!(?:10|127)(?:\\.\\d{1,3}){3})(?!(?:169\\.254|192\\.168)(?:\\.\\d{1,3}){2})(?!172\\.(?:1[6-9]|2\\d|3[0-1])(?:\\.\\d{1,3}){2})(?:[1-9]\\d?|1\\d\\d|2[01]\\d|22[0-3])(?:\\.(?:1?\\d{1,2}|2[0-4]\\d|25[0-5])){2}(?:\\.(?:[1-9]\\d?|1\\d\\d|2[0-4]\\d|25[0-4]))|(?:(?:[a-z\\u00a1-\\uffff0-9]-*)*[a-z\\u00a1-\\uffff0-9]+)(?:\\.(?:[a-z\\u00a1-\\uffff0-9]-*)*[a-z\\u00a1-\\uffff0-9]+)*(?:\\.(?:[a-z\\u00a1-\\uffff]{2,}))\\.?)(?::\\d{2,5})?(?:[/?#]\\S*)?\\b";
        
        NSArray *urlMatches = [[as string] componentsMatchedByRegex:urlRegex];
        e = [urlMatches objectEnumerator];
        NSString *matchedUrl;
        while (matchedUrl = [e nextObject]) {
            NSRange urlRange = [[as string] rangeOfString:matchedUrl];
            if (urlRange.location != NSNotFound && ![as attribute:DLCodeSpanAttributeName atIndex:urlRange.location effectiveRange:NULL]) {
                [as addAttribute: NSLinkAttributeName value:matchedUrl range:urlRange];
            }
        }

        NSString *customEmojiRegex = @"<a?:[A-Za-z0-9_]+:[0-9]+>";
        NSArray *emojiMatches = [[as string] componentsMatchedByRegex:customEmojiRegex];
        e = [emojiMatches objectEnumerator];
        NSString *matchedEmoji;
        while (matchedEmoji = [e nextObject]) {
            NSRange emojiRange = [[as string] rangeOfString:matchedEmoji];
            if (emojiRange.location == NSNotFound) {
                continue;
            }
            if ([as attribute:DLCodeSpanAttributeName atIndex:emojiRange.location effectiveRange:NULL]) {
                continue;
            }
            NSString *emojiID = [matchedEmoji stringByMatching:@"[0-9]+"];
            NSArray *parts = [matchedEmoji componentsSeparatedByString:@":"];
            NSString *emojiName = [parts count] > 1 ? [parts objectAtIndex:1] : @"emoji";
            BOOL animated = [matchedEmoji hasPrefix:@"<a:"];
            NSString *emojiURL = [NSString stringWithFormat:@"https://cdn.discordapp.com/emojis/%@.%@?size=64&quality=lossless", emojiID, animated ? @"gif" : @"png"];
            NSData *emojiData = [[HTTPCache sharedInstance] cachedDataForURL:emojiURL];
            if (emojiData) {
                NSImage *image = [[[NSImage alloc] initWithData:emojiData] autorelease];
                CGFloat emojiSide = (jumboEmoji ? 52.0 : 18.0) * displayScale;
                [image setSize:NSMakeSize(emojiSide, emojiSide)];
                NSTextAttachmentCell *cell = [[[NSTextAttachmentCell alloc] initImageCell:image] autorelease];
                NSTextAttachment *attachment = [[[NSTextAttachment alloc] init] autorelease];
                [attachment setAttachmentCell:cell];
                [as replaceCharactersInRange:emojiRange withAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
            } else {
                [as replaceCharactersInRange:emojiRange withString:[NSString stringWithFormat:@":%@:", emojiName]];
            }
        }
        
        [DLTwemojiRenderer replaceEmojiInAttributedString:as
                                                   size:(jumboEmoji ? 52.0 : 18.0) * displayScale
                                     excludingAttribute:DLCodeSpanAttributeName
                                    recordingAttribute:nil
                                         cursorLocation:NULL];
        return [as autorelease];
    }
    return [[[NSAttributedString alloc] init] autorelease];
}

@end
