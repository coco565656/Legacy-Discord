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

@implementation DLTextParser

const CGFloat MESSAGE_VIEW_FONT_SIZE = 13.0;

+(NSColor *)DEFAULT_TEXT_COLOR {
    return [DLUtil nativePrimaryTextColor];
}

+(NSColor *)DEFAULT_TEXT_HIGHLIGHT_COLOR {
    return [NSColor selectedTextBackgroundColor];
}

+(NSColor *)DEFAULT_LINK_TEXT_COLOR {
    return [DLUtil nativeLinkColor];
}

+(NSAttributedString *)attributedContentStringForMessage:(DLMessage *)m {
    if ([[m content] length] > 0) {
        CGFloat displayScale = [[DLPreferencesHandler sharedInstance] messageDisplayScale];
        CGFloat messageFontSize = MESSAGE_VIEW_FONT_SIZE * displayScale;
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
        
        NSArray *urlMatches = [[m content] componentsMatchedByRegex:urlRegex];
        e = [urlMatches objectEnumerator];
        NSString *matchedUrl;
        while (matchedUrl = [e nextObject]) {
            NSRange urlRange = [[as string] rangeOfString:matchedUrl];
            [as addAttribute: NSLinkAttributeName value:matchedUrl range:urlRange];
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
            NSString *emojiID = [matchedEmoji stringByMatching:@"[0-9]+"];
            NSArray *parts = [matchedEmoji componentsSeparatedByString:@":"];
            NSString *emojiName = [parts count] > 1 ? [parts objectAtIndex:1] : @"emoji";
            NSString *emojiURL = [NSString stringWithFormat:@"https://cdn.discordapp.com/emojis/%@.png?size=32&quality=lossless", emojiID];
            NSData *emojiData = [[HTTPCache sharedInstance] cachedDataForURL:emojiURL];
            if (emojiData) {
                NSImage *image = [[[NSImage alloc] initWithData:emojiData] autorelease];
                [image setSize:NSMakeSize(18 * displayScale, 18 * displayScale)];
                NSTextAttachmentCell *cell = [[[NSTextAttachmentCell alloc] initImageCell:image] autorelease];
                NSTextAttachment *attachment = [[[NSTextAttachment alloc] init] autorelease];
                [attachment setAttachmentCell:cell];
                [as replaceCharactersInRange:emojiRange withAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
            } else {
                [as replaceCharactersInRange:emojiRange withString:[NSString stringWithFormat:@":%@:", emojiName]];
            }
        }
        
        return [as autorelease];
    }
    return [[[NSAttributedString alloc] init] autorelease];
}

@end
