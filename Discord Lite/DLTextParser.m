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
#import "DLController.h"

@implementation DLTextParser

static NSString * const DLCodeSpanAttributeName = @"DLCodeSpanAttributeName";

// Links using this scheme hide spoiler text; ChatItemViewController reveals
// the range when it is clicked.
NSString * const DLSpoilerLinkScheme = @"dlspoiler";

typedef NSAttributedString *(*DLTokenRenderer)(NSArray *captures, NSDictionary *baseAttributes, NSDictionary *context);

// Replaces every match of regex outside code spans with the renderer's result.
static void DLReplaceTokens(NSMutableAttributedString *text, NSString *regex, DLTokenRenderer renderer, NSDictionary *context) {
    NSUInteger location = 0;
    while (location < [text length]) {
        NSRange search = NSMakeRange(location, [text length] - location);
        NSRange match = [[text string] rangeOfRegex:regex options:RKLNoOptions inRange:search capture:0 error:NULL];
        if (match.location == NSNotFound || match.length == 0) break;
        if ([text attribute:DLCodeSpanAttributeName atIndex:match.location effectiveRange:NULL]) {
            location = NSMaxRange(match);
            continue;
        }
        NSArray *captures = [[text string] captureComponentsMatchedByRegex:regex range:match];
        NSDictionary *baseAttributes = [text attributesAtIndex:match.location effectiveRange:NULL];
        NSAttributedString *replacement = renderer(captures, baseAttributes, context);
        if (!replacement) {
            location = NSMaxRange(match);
            continue;
        }
        [text replaceCharactersInRange:match withAttributedString:replacement];
        location = match.location + [replacement length];
    }
}

static NSAttributedString *DLMentionPill(NSString *string, NSDictionary *baseAttributes, NSDictionary *context, NSColor *foreground, NSColor *background) {
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithDictionary:baseAttributes];
    [attributes setObject:[NSFont boldSystemFontOfSize:[[context objectForKey:@"fontSize"] doubleValue]] forKey:NSFontAttributeName];
    [attributes setObject:(background ? background : [DLUtil nativeTagColor]) forKey:NSBackgroundColorAttributeName];
    if (foreground) [attributes setObject:foreground forKey:NSForegroundColorAttributeName];
    return [[[NSAttributedString alloc] initWithString:string attributes:attributes] autorelease];
}

// <#channel_id>
static NSAttributedString *DLRenderChannelMention(NSArray *captures, NSDictionary *baseAttributes, NSDictionary *context) {
    if ([captures count] < 2) return nil;
    DLChannel *channel = [[DLController sharedInstance] loadedChannelWithID:[captures objectAtIndex:1]];
    NSString *name = [channel name];
    return DLMentionPill([NSString stringWithFormat:@"#%@", ([name length] ? name : @"unknown")], baseAttributes, context, nil, nil);
}

// <@&role_id>: drawn in the role's color like the official client.
static NSAttributedString *DLRenderRoleMention(NSArray *captures, NSDictionary *baseAttributes, NSDictionary *context) {
    if ([captures count] < 2) return nil;
    DLServer *server = [context objectForKey:@"server"];
    NSDictionary *role = [server roleWithID:[captures objectAtIndex:1]];
    NSString *name = [role objectForKey:@"name"];
    if (![name isKindOfClass:[NSString class]] || ![name length]) name = @"unknown-role";
    NSColor *color = [DLUtil colorFromDiscordColorValue:[role objectForKey:@"color"]];
    return DLMentionPill([NSString stringWithFormat:@"@%@", name], baseAttributes, context,
                         color, (color ? [color colorWithAlphaComponent:0.18] : nil));
}

// </command:id>
static NSAttributedString *DLRenderCommandMention(NSArray *captures, NSDictionary *baseAttributes, NSDictionary *context) {
    if ([captures count] < 2) return nil;
    return DLMentionPill([NSString stringWithFormat:@"/%@", [captures objectAtIndex:1]], baseAttributes, context, nil, nil);
}

static NSString *DLRelativeTimeString(NSDate *date) {
    NSTimeInterval seconds = [date timeIntervalSinceNow];
    BOOL future = seconds > 0;
    double value = fabs(seconds);
    NSString *unit;
    if (value < 60.0) { unit = @"second"; }
    else if ((value /= 60.0) < 60.0) { unit = @"minute"; }
    else if ((value /= 60.0) < 24.0) { unit = @"hour"; }
    else if ((value /= 24.0) < 30.0) { unit = @"day"; }
    else if ((value /= 30.0) < 12.0) { unit = @"month"; }
    else { value /= 12.0; unit = @"year"; }
    long amount = MAX(1L, (long)floor(value));
    NSString *phrase = [NSString stringWithFormat:@"%ld %@%@", amount, unit, (amount == 1 ? @"" : @"s")];
    return future ? [NSString stringWithFormat:@"in %@", phrase] : [NSString stringWithFormat:@"%@ ago", phrase];
}

// <t:unix_seconds:style>, styles t T d D f F R (default f).
static NSAttributedString *DLRenderTimestamp(NSArray *captures, NSDictionary *baseAttributes, NSDictionary *context) {
    if ([captures count] < 2) return nil;
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[[captures objectAtIndex:1] doubleValue]];
    NSString *style = [captures count] > 2 ? [captures objectAtIndex:2] : @"";
    NSString *string;
    if ([style isEqualToString:@"R"]) {
        string = DLRelativeTimeString(date);
    } else {
        NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
        NSDateFormatterStyle dateStyle = NSDateFormatterLongStyle;
        NSDateFormatterStyle timeStyle = NSDateFormatterShortStyle;
        if ([style isEqualToString:@"t"]) { dateStyle = NSDateFormatterNoStyle; }
        else if ([style isEqualToString:@"T"]) { dateStyle = NSDateFormatterNoStyle; timeStyle = NSDateFormatterMediumStyle; }
        else if ([style isEqualToString:@"d"]) { dateStyle = NSDateFormatterShortStyle; timeStyle = NSDateFormatterNoStyle; }
        else if ([style isEqualToString:@"D"]) { timeStyle = NSDateFormatterNoStyle; }
        else if ([style isEqualToString:@"F"]) { dateStyle = NSDateFormatterFullStyle; }
        [formatter setDateStyle:dateStyle];
        [formatter setTimeStyle:timeStyle];
        string = [formatter stringFromDate:date];
    }
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithDictionary:baseAttributes];
    [attributes setObject:[DLUtil nativeInputColor] forKey:NSBackgroundColorAttributeName];
    NSDateFormatter *full = [[[NSDateFormatter alloc] init] autorelease];
    [full setDateStyle:NSDateFormatterFullStyle];
    [full setTimeStyle:NSDateFormatterShortStyle];
    [attributes setObject:[full stringFromDate:date] forKey:NSToolTipAttributeName];
    return [[[NSAttributedString alloc] initWithString:(string ? string : @"") attributes:attributes] autorelease];
}

// [text](https://url)
static NSAttributedString *DLRenderMaskedLink(NSArray *captures, NSDictionary *baseAttributes, NSDictionary *context) {
    if ([captures count] < 3) return nil;
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithDictionary:baseAttributes];
    [attributes setObject:[captures objectAtIndex:2] forKey:NSLinkAttributeName];
    [attributes setObject:[DLUtil nativeLinkColor] forKey:NSForegroundColorAttributeName];
    [attributes setObject:[captures objectAtIndex:2] forKey:NSToolTipAttributeName];
    return [[[NSAttributedString alloc] initWithString:[captures objectAtIndex:1] attributes:attributes] autorelease];
}

// Line-level Markdown: "# " / "## " / "### " headings, "-# " subtext and
// "- " / "* " bulleted lists. Lines inside code blocks are left alone.
static void DLApplyLineMarkdown(NSMutableAttributedString *text, CGFloat fontSize) {
    NSUInteger location = 0;
    while (location < [text length]) {
        NSUInteger lineStart = 0, lineEnd = 0, contentsEnd = 0;
        [[text string] getLineStart:&lineStart end:&lineEnd contentsEnd:&contentsEnd forRange:NSMakeRange(location, 0)];
        if (lineEnd <= lineStart) break;
        if ([text attribute:DLCodeSpanAttributeName atIndex:lineStart effectiveRange:NULL]) {
            location = lineEnd;
            continue;
        }
        NSString *line = [[text string] substringWithRange:NSMakeRange(lineStart, contentsEnd - lineStart)];
        NSUInteger prefixLength = 0;
        NSFont *font = nil;
        NSColor *color = nil;
        BOOL bullet = NO;
        if ([line hasPrefix:@"### "]) { prefixLength = 4; font = [NSFont boldSystemFontOfSize:round(fontSize * 1.0)]; }
        else if ([line hasPrefix:@"## "]) { prefixLength = 3; font = [NSFont boldSystemFontOfSize:round(fontSize * 1.25)]; }
        else if ([line hasPrefix:@"# "]) { prefixLength = 2; font = [NSFont boldSystemFontOfSize:round(fontSize * 1.5)]; }
        else if ([line hasPrefix:@"-# "]) { prefixLength = 3; font = [NSFont systemFontOfSize:round(fontSize * 0.82)]; color = [DLUtil nativeSecondaryTextColor]; }
        else if ([line hasPrefix:@"- "] || [line hasPrefix:@"* "]) { prefixLength = 2; bullet = YES; }
        if (prefixLength == 0 || contentsEnd - lineStart <= prefixLength) {
            location = lineEnd;
            continue;
        }
        if (bullet) {
            [text replaceCharactersInRange:NSMakeRange(lineStart, prefixLength) withString:@"•  "];
            NSUInteger newContentsEnd = contentsEnd + 1;
            NSFont *bodyFont = [text attribute:NSFontAttributeName atIndex:lineStart effectiveRange:NULL];
            CGFloat indent = ceil([@"•  " sizeWithAttributes:[NSDictionary dictionaryWithObject:(bodyFont ? bodyFont : [NSFont systemFontOfSize:fontSize]) forKey:NSFontAttributeName]].width);
            NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
            [style setFirstLineHeadIndent:4.0];
            [style setHeadIndent:indent + 4.0];
            [text addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(lineStart, newContentsEnd - lineStart)];
            location = lineEnd + 1;
        } else {
            [text deleteCharactersInRange:NSMakeRange(lineStart, prefixLength)];
            NSRange contentRange = NSMakeRange(lineStart, contentsEnd - prefixLength - lineStart);
            if (font) [text addAttribute:NSFontAttributeName value:font range:contentRange];
            if (color) [text addAttribute:NSForegroundColorAttributeName value:color range:contentRange];
            location = lineEnd - prefixLength;
        }
    }
}

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
        CGFloat messageFontSize = (jumboEmoji ? 52.0 : [[DLPreferencesHandler sharedInstance] chatFontSize]) * displayScale;
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
            DLApplyLineMarkdown(as, messageFontSize);
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
            NSColor *spoilerColor = [DLUtil nativeServerRailColor];
            DLApplyDelimitedAttributes(as, @"||", [NSDictionary dictionaryWithObjectsAndKeys:
                [NSString stringWithFormat:@"%@:", DLSpoilerLinkScheme], NSLinkAttributeName,
                spoilerColor, NSForegroundColorAttributeName,
                spoilerColor, NSBackgroundColorAttributeName,
                @"Spoiler — click to reveal", NSToolTipAttributeName, nil]);
            DLApplyQuoteStyling(as);
        }

        DLServer *server = [m serverID] ? [[DLController sharedInstance] loadedServerWithID:[m serverID]] : nil;
        if (!server) server = [[DLController sharedInstance] selectedServer];
        NSMutableDictionary *tokenContext = [NSMutableDictionary dictionaryWithObject:[NSNumber numberWithDouble:messageFontSize] forKey:@"fontSize"];
        if (server) [tokenContext setObject:server forKey:@"server"];
        DLReplaceTokens(as, @"<#([0-9]+)>", DLRenderChannelMention, tokenContext);
        DLReplaceTokens(as, @"<@&([0-9]+)>", DLRenderRoleMention, tokenContext);
        DLReplaceTokens(as, @"</([^:<>]+):[0-9]+>", DLRenderCommandMention, tokenContext);
        DLReplaceTokens(as, @"<t:(-?[0-9]+)(?::([tTdDfFR]))?>", DLRenderTimestamp, tokenContext);
        DLReplaceTokens(as, @"\\[([^\\]\\n]+)\\]\\((https?://[^\\s)]+)\\)", DLRenderMaskedLink, tokenContext);
        
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
                [as addAttribute:NSForegroundColorAttributeName value:[DLUtil nativeLinkColor] range:urlRange];
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
