#import "DLUIDiagnostics.h"

#if LEGACY_DISCORD_UI_DIAGNOSTICS

#import "ChatScrollView.h"
#import "ChatItemViewController.h"
#import "DLPreferencesHandler.h"
#import "DLMessage.h"
#import "DLAttachment.h"
#import "CJSONSerializer.h"

static NSMutableArray *DLUIDiagnosticEvents = nil;

static CGFloat DLBackingScaleForWindow(NSWindow *window) {
    SEL selector = @selector(backingScaleFactor);
    if ([window respondsToSelector:selector]) {
        typedef CGFloat (*DLBackingScaleFunction)(id, SEL);
        DLBackingScaleFunction function = (DLBackingScaleFunction)[window methodForSelector:selector];
        if (function) return function(window, selector);
    }
    return 1.0;
}

@implementation DLUIDiagnostics

+ (NSDictionary *)frameDescription:(NSRect)frame {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithDouble:frame.origin.x], @"x",
            [NSNumber numberWithDouble:frame.origin.y], @"y",
            [NSNumber numberWithDouble:frame.size.width], @"width",
            [NSNumber numberWithDouble:frame.size.height], @"height", nil];
}

+ (NSDictionary *)textMetricsForString:(NSString *)string {
    NSUInteger japanese = 0, latin = 0, digits = 0, whitespace = 0, other = 0, newlines = 0;
    NSUInteger index;
    for (index = 0; index < [string length]; index++) {
        unichar character = [string characterAtIndex:index];
        if (character == '\n' || character == '\r') { newlines++; whitespace++; }
        else if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:character]) whitespace++;
        else if ((character >= 0x3040 && character <= 0x30ff) || (character >= 0x3400 && character <= 0x9fff)) japanese++;
        else if ((character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z')) latin++;
        else if (character >= '0' && character <= '9') digits++;
        else other++;
    }
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithUnsignedInteger:[string length]], @"utf16_length",
            [NSNumber numberWithUnsignedInteger:newlines + 1], @"line_count",
            [NSNumber numberWithUnsignedInteger:japanese], @"japanese_characters",
            [NSNumber numberWithUnsignedInteger:latin], @"latin_characters",
            [NSNumber numberWithUnsignedInteger:digits], @"digit_characters",
            [NSNumber numberWithUnsignedInteger:whitespace], @"whitespace_characters",
            [NSNumber numberWithUnsignedInteger:other], @"other_characters", nil];
}

+ (void)appendView:(NSView *)view toArray:(NSMutableArray *)array depth:(NSUInteger)depth {
    if (!view || depth > 12) return;
    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                  NSStringFromClass([view class]), @"class",
                                  [self frameDescription:[view frame]], @"frame",
                                  [NSNumber numberWithBool:[view isHidden]], @"hidden", nil];
    [array addObject:entry];
    NSEnumerator *enumerator = [[view subviews] objectEnumerator];
    NSView *child;
    while (child = [enumerator nextObject]) [self appendView:child toArray:array depth:depth + 1];
}

+ (NSDictionary *)sanitizedMessageDescription:(DLMessage *)message item:(ChatItemViewController *)item index:(NSUInteger)index {
    NSMutableArray *attachments = [NSMutableArray array];
    NSEnumerator *attachmentEnumerator = [[message attachments] objectEnumerator];
    DLAttachment *attachment;
    while (attachment = [attachmentEnumerator nextObject]) {
        [attachments addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                [NSNumber numberWithInteger:[attachment type]], @"type",
                                [NSNumber numberWithInteger:[attachment width]], @"width",
                                [NSNumber numberWithInteger:[attachment height]], @"height",
                                [NSNumber numberWithDouble:[attachment scaledWidth]], @"scaled_width",
                                [NSNumber numberWithDouble:[attachment scaledHeight]], @"scaled_height", nil]];
    }
    NSMutableArray *embeds = [NSMutableArray array];
    NSEnumerator *embedEnumerator = [[message embeds] objectEnumerator];
    NSDictionary *embed;
    while (embed = [embedEnumerator nextObject]) {
        NSString *title = [[embed objectForKey:@"title"] isKindOfClass:[NSString class]] ? [embed objectForKey:@"title"] : @"";
        [embeds addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                            [NSNumber numberWithBool:[[embed objectForKey:@"image"] isKindOfClass:[NSDictionary class]]], @"has_image",
                            [NSNumber numberWithBool:[[embed objectForKey:@"thumbnail"] isKindOfClass:[NSDictionary class]]], @"has_thumbnail",
                            [NSNumber numberWithBool:[[embed objectForKey:@"video"] isKindOfClass:[NSDictionary class]]], @"has_video",
                            [NSNumber numberWithUnsignedInteger:[title length]], @"title_length", nil]];
    }
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSString stringWithFormat:@"message-%lu", (unsigned long)index], @"message",
            [self textMetricsForString:([message content] ? [message content] : @"")], @"content",
            [NSNumber numberWithBool:[message referencedMessage] != nil], @"has_reply",
            [NSNumber numberWithBool:[message editedTimestamp] != nil], @"is_edited",
            [NSNumber numberWithUnsignedInteger:[[message reactions] count]], @"reaction_count",
            [NSNumber numberWithUnsignedInteger:[[message stickerItems] count]], @"sticker_count",
            attachments, @"attachments",
            embeds, @"embeds",
            [NSNumber numberWithBool:[item isCompactDisplay]], @"compact",
            [NSNumber numberWithDouble:[item diagnosticAvailableMessageWidth]], @"available_message_width",
            [NSNumber numberWithDouble:[item diagnosticCalculatedTextHeight]], @"calculated_text_height",
            [NSNumber numberWithDouble:[item diagnosticDisplayedTextHeight]], @"displayed_text_height",
            [NSNumber numberWithDouble:[item expectedHeight]], @"expected_height",
            [NSNumber numberWithDouble:NSHeight([[item view] frame])], @"actual_height",
            [self frameDescription:[[item view] frame]], @"frame", nil];
}

+ (void)recordEvent:(NSString *)event details:(NSDictionary *)details {
    if (!DLUIDiagnosticEvents) DLUIDiagnosticEvents = [[NSMutableArray alloc] init];
    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                  event ? event : @"unknown", @"event",
                                  [[NSDate date] descriptionWithLocale:nil], @"timestamp", nil];
    if (details) [entry setObject:details forKey:@"details"];
    [DLUIDiagnosticEvents addObject:entry];
    if ([DLUIDiagnosticEvents count] > 200) [DLUIDiagnosticEvents removeObjectAtIndex:0];
}

+ (NSString *)writeSanitizedSnapshotForWindow:(NSWindow *)window chatScrollView:(ChatScrollView *)chatScrollView {
    if (!window || !chatScrollView) return nil;
    NSMutableArray *views = [NSMutableArray array];
    [self appendView:[window contentView] toArray:views depth:0];
    NSMutableArray *messages = [NSMutableArray array];
    NSEnumerator *enumerator = [[chatScrollView content] objectEnumerator];
    ChatItemViewController *item;
    NSUInteger index = 0;
    while (item = [enumerator nextObject]) {
        [messages addObject:[self sanitizedMessageDescription:[item representedObject] item:item index:index]];
        index++;
    }
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                     @"legacy-discord-ui-diagnostics-v1", @"format",
                                     [[NSDate date] descriptionWithLocale:nil], @"created_at",
                                     [self frameDescription:[[window contentView] bounds]], @"content_bounds",
                                     [NSNumber numberWithDouble:DLBackingScaleForWindow(window)], @"backing_scale",
                                     [NSNumber numberWithDouble:[[DLPreferencesHandler sharedInstance] messageDisplayScale]], @"display_scale",
                                     [[DLPreferencesHandler sharedInstance] appearanceTheme], @"theme",
                                     views, @"view_hierarchy",
                                     messages, @"messages",
                                     (DLUIDiagnosticEvents ? DLUIDiagnosticEvents : [NSArray array]), @"events", nil];
    NSString *root = @"/tmp/legacy-discord-ui-diagnostics";
    NSString *identifier = [[NSDate date] descriptionWithLocale:nil];
    identifier = [[identifier stringByReplacingOccurrencesOfString:@":" withString:@"-"] stringByReplacingOccurrencesOfString:@" " withString:@"-"];
    NSString *directory = [root stringByAppendingPathComponent:identifier];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]) return nil;
    NSData *data = [[CJSONSerializer serializer] serializeDictionary:snapshot error:nil];
    NSString *path = [directory stringByAppendingPathComponent:@"sanitized-ui-state.json"];
    if (![data writeToFile:path atomically:YES]) return nil;
    return path;
}

@end

#else

@implementation DLUIDiagnostics
+ (NSString *)writeSanitizedSnapshotForWindow:(NSWindow *)window chatScrollView:(ChatScrollView *)chatScrollView { return nil; }
+ (void)recordEvent:(NSString *)event details:(NSDictionary *)details {}
@end

#endif
