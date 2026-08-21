//
//  ChatItemViewController.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/1/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "ChatItemViewController.h"
#import "DLPreferencesHandler.h"
#import <WebKit/WebKit.h>

NSString * const DLMessageActionBarDidShowNotification = @"DLMessageActionBarDidShowNotification";
NSString * const DLMessageActionBarDidHideNotification = @"DLMessageActionBarDidHideNotification";

static NSString *DLCustomEmojiURL(id emojiID, BOOL animated) {
    return [NSString stringWithFormat:@"https://cdn.discordapp.com/emojis/%@.%@?size=64&quality=lossless",
            emojiID, animated ? @"gif" : @"png"];
}

static NSString *DLStickerURL(NSDictionary *sticker) {
    id stickerID = [sticker objectForKey:@"id"];
    NSInteger formatType = [[sticker objectForKey:@"format_type"] integerValue];
    if (!stickerID || [stickerID isKindOfClass:[NSNull class]] || formatType == 3) {
        return nil;
    }
    if (formatType == 4) {
        return [NSString stringWithFormat:@"https://media.discordapp.net/stickers/%@.gif", stickerID];
    }
    return [NSString stringWithFormat:@"https://cdn.discordapp.com/stickers/%@.png", stickerID];
}

@interface DLMessageActionButton : NSButton
@end

@implementation DLMessageActionButton

-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = NSInsetRect([self bounds], 1.0, 1.0);
    NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:5.0 yRadius:5.0];
    NSColor *fill = [[self cell] isHighlighted] ? [DLUtil nativeSelectionColor] : [NSColor clearColor];
    [fill set];
    [background fill];

    NSImage *image = [self image];
    if (image) {
        CGFloat side = MIN(18.0, MIN(NSWidth(bounds) - 6.0, NSHeight(bounds) - 6.0));
        NSRect imageRect = NSMakeRect(floor(NSMidX(bounds) - side / 2.0),
                                      floor(NSMidY(bounds) - side / 2.0), side, side);
        [image drawInRect:imageRect
                 fromRect:NSZeroRect
                operation:NSCompositeSourceOver
                 fraction:1.0
           respectFlipped:YES
                    hints:nil];
        return;
    }

    NSString *title = [self title] ? [self title] : @"";
    CGFloat fontSize = [title length] > 3 ? 11.0 : 14.0;
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont systemFontOfSize:fontSize], NSFontAttributeName,
                                [DLUtil nativePrimaryTextColor], NSForegroundColorAttributeName, nil];
    NSSize titleSize = [title sizeWithAttributes:attributes];
    [title drawAtPoint:NSMakePoint(floor(NSMidX(bounds) - titleSize.width / 2.0),
                                   floor(NSMidY(bounds) - titleSize.height / 2.0))
         withAttributes:attributes];
}

@end

@implementation ChatItemViewController

const NSInteger ATTACHMENT_SPACING = 15;

+(CGFloat)AVATAR_RADIUS {
    return 20.0f * [[DLPreferencesHandler sharedInstance] messageDisplayScale];
}
+(CGFloat)REFERENCED_AVATAR_RADIUS {
    return 11.0f * [[DLPreferencesHandler sharedInstance] messageDisplayScale];
}

-(void)syncAvatarProfileButton {
    if (!avatarProfileButton || !avatarImageView || !insetView) {
        return;
    }
    [avatarProfileButton setFrame:[avatarImageView frame]];
    [avatarProfileButton setHidden:[avatarImageView isHidden]];
    [insetView addSubview:avatarProfileButton positioned:NSWindowAbove relativeTo:avatarImageView];
}

-(void)awakeFromNib {
    baseViewHeight = view.frame.size.height;
    //[insetView setBackgroundColor:[NSColor redColor]];
    [chatTextView setInsertionPointColor:[DLTextParser DEFAULT_TEXT_COLOR]];
    [chatTextView setBackgroundColor:[DLUtil nativeContentColor]];
    [chatTextView setSelectedTextAttributes:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[DLUtil nativeSelectedTextColor], [DLTextParser DEFAULT_TEXT_HIGHLIGHT_COLOR], nil] forKeys:[NSArray arrayWithObjects:NSForegroundColorAttributeName, NSBackgroundColorAttributeName, nil]]];
    NSMutableDictionary *linkTextAttributes = [NSMutableDictionary dictionaryWithDictionary:[chatTextView linkTextAttributes]];
    [linkTextAttributes setObject:[DLTextParser DEFAULT_LINK_TEXT_COLOR] forKey:NSForegroundColorAttributeName];
    
    [chatTextView setLinkTextAttributes:linkTextAttributes];
    [chatTextView setEditable:NO];
    CGFloat displayScale = [[DLPreferencesHandler sharedInstance] messageDisplayScale];
    [chatTextView setFont:[NSFont systemFontOfSize:13 * displayScale]];
    [chatTextView setMenuDelegate:self];
    [chatTextView setDrawsBackground:NO];
    [chatTextView setDelegate:self];
    [view setBackgroundColor:[DLUtil nativeContentColor]];
    [insetView setBackgroundColor:[NSColor clearColor]];
    [usernameTextField setTextColor:[DLUtil nativePrimaryTextColor]];
    [usernameTextField setFont:[NSFont boldSystemFontOfSize:13 * displayScale]];
    [timestampTextField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [timestampTextField setFont:[NSFont systemFontOfSize:11 * displayScale]];
    [timestampTextField setAlignment:NSLeftTextAlignment];
    [editedInfoLabel setTextColor:[DLUtil nativeSecondaryTextColor]];
    [editDismissInfoLabel setTextColor:[DLUtil nativeSecondaryTextColor]];
    [referencedMessageTextField setTextColor:[DLUtil nativePrimaryTextColor]];
    reactionTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(72, 3, view.frame.size.width - 88, 17)];
    [reactionTextField setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [reactionTextField setEditable:NO];
    [reactionTextField setSelectable:NO];
    [reactionTextField setBordered:NO];
    [reactionTextField setDrawsBackground:NO];
    [reactionTextField setFont:[NSFont systemFontOfSize:12 * displayScale]];
    [reactionTextField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [reactionTextField setToolTip:@"Reactions and counts"];
    [reactionTextField setHidden:YES];
    [insetView addSubview:reactionTextField];
    reactionButtons = [[NSMutableArray alloc] init];
    embedViews = [[NSMutableArray alloc] init];
    embedsHeight = 0.0;
    stickerViews = [[NSMutableArray alloc] init];
    stickersHeight = 0.0;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cachedEmojiDidUpdate:) name:HTTPCacheDataDidUpdateNotification object:nil];
    viewHasLoaded = NO;
    isEditing = NO;
    compactDisplay = NO;
    groupedMessageFollows = NO;

    NSRect avatarFrame = [avatarImageView frame];
    NSPoint avatarCenter = NSMakePoint(NSMidX(avatarFrame), NSMidY(avatarFrame));
    CGFloat avatarSide = round(40.0 * displayScale);
    avatarFrame = NSMakeRect(avatarCenter.x - avatarSide / 2.0, avatarCenter.y - avatarSide / 2.0, avatarSide, avatarSide);
    [avatarImageView setFrame:avatarFrame];
    avatarProfileButton = [[NSButton alloc] initWithFrame:avatarFrame];
    [avatarProfileButton setBordered:NO];
    [avatarProfileButton setRefusesFirstResponder:YES];
    [avatarProfileButton setTitle:@""];
    [avatarProfileButton setToolTip:@"View profile"];
    [avatarProfileButton setTarget:self];
    [avatarProfileButton setAction:@selector(showAuthorProfile:)];
    [avatarProfileButton setButtonType:NSMomentaryChangeButton];
    [avatarProfileButton sendActionOn:NSLeftMouseUpMask];
    [insetView addSubview:avatarProfileButton positioned:NSWindowAbove relativeTo:avatarImageView];
    NSRect referencedAvatarFrame = [referencedMessageAvatarImageView frame];
    NSPoint referencedCenter = NSMakePoint(NSMidX(referencedAvatarFrame), NSMidY(referencedAvatarFrame));
    CGFloat referencedSide = round(22.0 * displayScale);
    referencedAvatarFrame = NSMakeRect(referencedCenter.x - referencedSide / 2.0, referencedCenter.y - referencedSide / 2.0, referencedSide, referencedSide);
    [referencedMessageAvatarImageView setFrame:referencedAvatarFrame];
    
    [insetView setDelegate:self];
    
    contextMenu = [[NSMenu alloc] init];

    messageActionBar = [[NSView alloc] initWithFrame:NSMakeRect(NSWidth([insetView bounds]) - 196, NSHeight([insetView bounds]) - 31, 188, 30)];
    [messageActionBar setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [messageActionBar setHidden:YES];
    [self rebuildMessageActionBar];

    reactionMenu = [[NSMenu alloc] initWithTitle:@"Reactions"];
    NSMenuItem *reactionRootItem = [[NSMenuItem alloc] initWithTitle:@"Reactions" action:NULL keyEquivalent:@""];
    [reactionRootItem setSubmenu:reactionMenu];
    [contextMenu addItem:reactionRootItem];
    [reactionRootItem release];

    [contextMenu addItem:[NSMenuItem separatorItem]];
    
    /*NSMenuItem *copySelectionItem = [[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copySelectedMessageContent) keyEquivalent:@""];
    [copySelectionItem setTarget:self];
    [contextMenu addItem:copySelectionItem];
    [copySelectionItem release];
    
    [contextMenu addItem:[NSMenuItem separatorItem]];*/
    
    NSMenuItem *replyItem = [[NSMenuItem alloc] initWithTitle:@"Reply" action:@selector(addReply) keyEquivalent:@""];
    [replyItem setTarget:self];
    [contextMenu addItem:replyItem];
    [replyItem release];
    
    editItem = [[NSMenuItem alloc] initWithTitle:@"Edit Message" action:@selector(beginEditingContent) keyEquivalent:@""];
    [editItem setTarget:self];
    
    deleteItem = [[NSMenuItem alloc] initWithTitle:@"Delete Message" action:@selector(beginDeletingMessage) keyEquivalent:@""];
    [deleteItem setTarget:self];
    
}

-(CGFloat)headerSpacing {
    CGFloat scale = [[DLPreferencesHandler sharedInstance] messageDisplayScale];
    return compactDisplay ? MAX(3.0, round(4.0 * scale)) : MAX(46.0, round(50.0 * scale));
}

-(void)layoutMessageHeaderFields {
    if (!usernameTextField || !timestampTextField || compactDisplay) {
        return;
    }
    CGFloat left = NSMinX([usernameTextField frame]);
    CGFloat availableWidth = MAX(0.0, NSWidth([insetView bounds]) - left - 12.0);
    NSDictionary *usernameAttributes = [NSDictionary dictionaryWithObject:[usernameTextField font]
                                                                    forKey:NSFontAttributeName];
    NSDictionary *timestampAttributes = [NSDictionary dictionaryWithObject:[timestampTextField font]
                                                                     forKey:NSFontAttributeName];
    CGFloat usernameWidth = ceil([[usernameTextField stringValue] sizeWithAttributes:usernameAttributes].width) + 5.0;
    CGFloat timestampWidth = ceil([[timestampTextField stringValue] sizeWithAttributes:timestampAttributes].width) + 5.0;
    timestampWidth = MIN(timestampWidth, MAX(0.0, availableWidth * 0.48));
    usernameWidth = MIN(usernameWidth, MAX(0.0, availableWidth - timestampWidth - 5.0));

    NSRect usernameFrame = [usernameTextField frame];
    usernameFrame.size.width = usernameWidth;
    [usernameTextField setFrame:usernameFrame];

    NSRect timestampFrame = [timestampTextField frame];
    timestampFrame.origin.x = NSMaxX(usernameFrame) + 5.0;
    timestampFrame.size.width = timestampWidth;
    [timestampTextField setFrame:timestampFrame];
}

-(void)refreshMessageHeaderLayout {
    [self layoutMessageHeaderFields];
}

-(CGFloat)contentBottomPadding {
    if (compactDisplay) {
        return 0.0;
    }
    CGFloat scale = [[DLPreferencesHandler sharedInstance] messageDisplayScale];
    return groupedMessageFollows ? MAX(3.0, round(4.0 * scale)) : round(16.0 * scale);
}

-(CGFloat)reactionViewHeight {
    return MAX(19.0, round(22.0 * [[DLPreferencesHandler sharedInstance] messageDisplayScale]));
}

-(CGFloat)expectedHeight {
    CGFloat textViewHeight = 0;
    if (![[representedObject content] isEqualToString:@""]) {
        textViewHeight = chatTextView.frame.size.height;
    }
    CGFloat height = [self headerSpacing];
    height += textViewHeight;
    BOOL hasReactions = [[[representedObject reactionSummary] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0;
    if (hasReactions) {
        height += [self reactionViewHeight];
    }
    CGFloat attachmentsHeight = 0;
    NSEnumerator *e = [[representedObject attachments] objectEnumerator];
    DLAttachment *attachment;
    while (attachment = [e nextObject]) {
        attachmentsHeight += [attachment scaledHeight] + ATTACHMENT_SPACING;
    }
    NSRect frame = chatTextView.frame;
    frame.origin.y = attachmentsHeight + embedsHeight + stickersHeight + [self contentBottomPadding] + (hasReactions ? [self reactionViewHeight] : 0);
    frame.size.height = textViewHeight;
    [chatTextView setFrame:frame];
    height += attachmentsHeight;
    height += embedsHeight;
    height += stickersHeight;
    if ([representedObject referencedMessage]) {
        height += referencedMessageView.frame.size.height;
    }
    return height;
}

-(NSString *)reactionIdentifierForReaction:(NSDictionary *)reaction {
    NSDictionary *emoji = [reaction objectForKey:@"emoji"];
    NSString *name = [emoji objectForKey:@"name"];
    id emojiID = [emoji objectForKey:@"id"];
    if (!name || [name isKindOfClass:[NSNull class]]) {
        return nil;
    }
    if (emojiID && ![emojiID isKindOfClass:[NSNull class]]) {
        return [NSString stringWithFormat:@"%@:%@", name, emojiID];
    }
    return name;
}

-(NSDictionary *)reactionForIdentifier:(NSString *)identifier {
    NSEnumerator *enumerator = [[representedObject reactions] objectEnumerator];
    NSDictionary *reaction;
    while (reaction = [enumerator nextObject]) {
        if ([[self reactionIdentifierForReaction:reaction] isEqualToString:identifier]) {
            return reaction;
        }
    }
    return nil;
}

-(BOOL)isCustomEmojiAnimated:(id)emojiID {
    if (!emojiID || [emojiID isKindOfClass:[NSNull class]]) {
        return NO;
    }
    NSEnumerator *reactionEnumerator = [[representedObject reactions] objectEnumerator];
    NSDictionary *reaction;
    while (reaction = [reactionEnumerator nextObject]) {
        NSDictionary *emoji = [reaction objectForKey:@"emoji"];
        if ([[emoji objectForKey:@"id"] isEqual:emojiID]) {
            return [[emoji objectForKey:@"animated"] boolValue];
        }
    }
    NSEnumerator *emojiEnumerator = [[[[DLController sharedInstance] selectedServer] emojis] objectEnumerator];
    NSDictionary *emoji;
    while (emoji = [emojiEnumerator nextObject]) {
        if ([[emoji objectForKey:@"id"] isEqual:emojiID]) {
            return [[emoji objectForKey:@"animated"] boolValue];
        }
    }
    return NO;
}

-(BOOL)advanceAnimatedImage:(NSImage *)image {
    BOOL advanced = NO;
    NSEnumerator *representationEnumerator = [[image representations] objectEnumerator];
    NSImageRep *representation;
    while (representation = [representationEnumerator nextObject]) {
        if (![representation isKindOfClass:[NSBitmapImageRep class]]) {
            continue;
        }
        NSBitmapImageRep *bitmap = (NSBitmapImageRep *)representation;
        NSInteger frameCount = [[bitmap valueForProperty:NSImageFrameCount] integerValue];
        if (frameCount <= 1) {
            continue;
        }
        NSInteger currentFrame = [[bitmap valueForProperty:NSImageCurrentFrame] integerValue];
        [bitmap setProperty:NSImageCurrentFrame withValue:[NSNumber numberWithInteger:(currentFrame + 1) % frameCount]];
        advanced = YES;
    }
    return advanced;
}

-(BOOL)advanceAnimatedEmojiAttachments {
    BOOL advanced = NO;
    NSAttributedString *content = [chatTextView textStorage];
    NSUInteger location = 0;
    while (location < [content length]) {
        NSRange effectiveRange = NSMakeRange(location, 1);
        NSTextAttachment *attachment = [content attribute:NSAttachmentAttributeName atIndex:location effectiveRange:&effectiveRange];
        if (attachment && [[attachment attachmentCell] respondsToSelector:@selector(image)]) {
            NSImage *image = [(NSTextAttachmentCell *)[attachment attachmentCell] image];
            advanced = [self advanceAnimatedImage:image] || advanced;
        }
        NSUInteger nextLocation = NSMaxRange(effectiveRange);
        location = nextLocation > location ? nextLocation : location + 1;
    }
    return advanced;
}

-(BOOL)containsAnimatedEmojiAttachments {
    NSAttributedString *content = [chatTextView textStorage];
    NSUInteger location = 0;
    while (location < [content length]) {
        NSRange effectiveRange = NSMakeRange(location, 1);
        NSTextAttachment *attachment = [content attribute:NSAttachmentAttributeName atIndex:location effectiveRange:&effectiveRange];
        if (attachment && [[attachment attachmentCell] respondsToSelector:@selector(image)]) {
            NSImage *image = [(NSTextAttachmentCell *)[attachment attachmentCell] image];
            NSEnumerator *representationEnumerator = [[image representations] objectEnumerator];
            NSImageRep *representation;
            while (representation = [representationEnumerator nextObject]) {
                if ([representation isKindOfClass:[NSBitmapImageRep class]] &&
                    [[(NSBitmapImageRep *)representation valueForProperty:NSImageFrameCount] integerValue] > 1) {
                    return YES;
                }
            }
        }
        NSUInteger nextLocation = NSMaxRange(effectiveRange);
        location = nextLocation > location ? nextLocation : location + 1;
    }
    return NO;
}

-(void)animatedEmojiTimerDidFire:(NSTimer *)timer {
    if (![self.view window] || NSIsEmptyRect([chatTextView visibleRect])) {
        return;
    }
    BOOL advanced = [self advanceAnimatedEmojiAttachments];
    NSEnumerator *buttonEnumerator = [reactionButtons objectEnumerator];
    NSButton *button;
    while (button = [buttonEnumerator nextObject]) {
        if ([self advanceAnimatedImage:[button image]]) {
            [button setNeedsDisplay:YES];
            advanced = YES;
        }
    }
    if (advanced) {
        [chatTextView setNeedsDisplay:YES];
    }
}

-(void)refreshAnimatedEmojiTimer {
    [self stopAnimatedEmojiPlayback];
    if ([self containsAnimatedEmojiAttachments]) {
        animatedEmojiTimer = [[NSTimer scheduledTimerWithTimeInterval:0.08
            target:self selector:@selector(animatedEmojiTimerDidFire:) userInfo:nil repeats:YES] retain];
    }
}

-(void)stopAnimatedEmojiPlayback {
    [animatedEmojiTimer invalidate];
    [animatedEmojiTimer release];
    animatedEmojiTimer = nil;
}

-(void)updateJumboEmojiLayout {
    BOOL shouldUseJumbo = [DLTextParser isEmojiOnlyMessage:representedObject];
    CGFloat displayScale = [[DLPreferencesHandler sharedInstance] messageDisplayScale];
    NSRect frame = [chatTextView frame];
    if (shouldUseJumbo) {
        frame.size.height = ceil(60.0 * displayScale);
    } else if (jumboEmojiDisplay) {
        frame.size.height = ceil(18.0 * displayScale);
    }
    jumboEmojiDisplay = shouldUseJumbo;
    [chatTextView setFrame:frame];
}

-(void)updateReactionMenu {
    [reactionMenu removeAllItems];
    NSMutableArray *identifiers = [NSMutableArray arrayWithObjects:@"👍", @"❤️", @"😂", @"🎉", @"👀", nil];
    NSMutableDictionary *labels = [NSMutableDictionary dictionary];
    NSEnumerator *enumerator = [[representedObject reactions] objectEnumerator];
    NSDictionary *reaction;
    while (reaction = [enumerator nextObject]) {
        NSString *identifier = [self reactionIdentifierForReaction:reaction];
        if (!identifier) {
            continue;
        }
        NSDictionary *emoji = [reaction objectForKey:@"emoji"];
        NSString *label = ([emoji objectForKey:@"id"] && ![[emoji objectForKey:@"id"] isKindOfClass:[NSNull class]])
            ? [NSString stringWithFormat:@":%@:", [emoji objectForKey:@"name"]]
            : [emoji objectForKey:@"name"];
        [labels setObject:label forKey:identifier];
        if (![identifiers containsObject:identifier]) {
            [identifiers addObject:identifier];
        }
    }

    enumerator = [identifiers objectEnumerator];
    NSString *identifier;
    while (identifier = [enumerator nextObject]) {
        reaction = [self reactionForIdentifier:identifier];
        BOOL reactedByMe = [[reaction objectForKey:@"me"] boolValue];
        NSString *label = [labels objectForKey:identifier] ? [labels objectForKey:identifier] : identifier;
        NSString *title = [NSString stringWithFormat:@"%@ %@", reactedByMe ? @"Remove" : @"Add", label];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(toggleReaction:) keyEquivalent:@""];
        [item setTarget:self];
        [item setRepresentedObject:identifier];
        [item setState:reactedByMe ? NSOnState : NSOffState];
        NSDictionary *emoji = [reaction objectForKey:@"emoji"];
        id emojiID = [emoji objectForKey:@"id"];
        if (emojiID && ![emojiID isKindOfClass:[NSNull class]]) {
            NSString *emojiURL = DLCustomEmojiURL(emojiID, [[emoji objectForKey:@"animated"] boolValue]);
            NSData *cachedData = [[HTTPCache sharedInstance] cachedDataForURL:emojiURL];
            if (cachedData) {
                NSImage *image = [[[NSImage alloc] initWithData:cachedData] autorelease];
                [image setSize:NSMakeSize(16, 16)];
                [item setImage:image];
            }
        }
        [reactionMenu addItem:item];
        [item release];
    }
}

-(NSAttributedString *)attributedReactionSummary {
    CGFloat displayScale = [[DLPreferencesHandler sharedInstance] messageDisplayScale];
    NSMutableAttributedString *summary = [[[NSMutableAttributedString alloc] init] autorelease];
    NSEnumerator *enumerator = [[representedObject reactions] objectEnumerator];
    NSDictionary *reaction;
    while (reaction = [enumerator nextObject]) {
        if ([summary length] > 0) {
            [summary appendAttributedString:[[[NSAttributedString alloc] initWithString:@"   "] autorelease]];
        }
        NSDictionary *emoji = [reaction objectForKey:@"emoji"];
        NSString *name = [emoji objectForKey:@"name"];
        id emojiID = [emoji objectForKey:@"id"];
        BOOL appendedImage = NO;
        if (emojiID && ![emojiID isKindOfClass:[NSNull class]]) {
            NSString *emojiURL = DLCustomEmojiURL(emojiID, [[emoji objectForKey:@"animated"] boolValue]);
            NSData *cachedData = [[HTTPCache sharedInstance] cachedDataForURL:emojiURL];
            if (cachedData) {
                NSImage *image = [[[NSImage alloc] initWithData:cachedData] autorelease];
                [image setSize:NSMakeSize(16 * displayScale, 16 * displayScale)];
                NSTextAttachmentCell *cell = [[[NSTextAttachmentCell alloc] initImageCell:image] autorelease];
                NSTextAttachment *attachment = [[[NSTextAttachment alloc] init] autorelease];
                [attachment setAttachmentCell:cell];
                [summary appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
                appendedImage = YES;
            }
        }
        NSString *label = appendedImage ? @"" : ((emojiID && ![emojiID isKindOfClass:[NSNull class]]) ? [NSString stringWithFormat:@":%@:", name] : name);
        NSString *countText = [NSString stringWithFormat:@"%@%@%@", label, [label length] > 0 ? @" " : @"", [reaction objectForKey:@"count"]];
        [summary appendAttributedString:[[[NSAttributedString alloc] initWithString:countText] autorelease]];
    }
    if ([summary length] > 0) {
        [summary addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:12 * displayScale] range:NSMakeRange(0, [summary length])];
        [summary addAttribute:NSForegroundColorAttributeName value:[DLUtil nativeSecondaryTextColor] range:NSMakeRange(0, [summary length])];
    }
    return summary;
}

-(void)rebuildReactionButtons {
    CGFloat displayScale = [[DLPreferencesHandler sharedInstance] messageDisplayScale];
    CGFloat reactionHeight = [self reactionViewHeight];
    NSEnumerator *oldButtonEnumerator = [reactionButtons objectEnumerator];
    NSButton *oldButton;
    while (oldButton = [oldButtonEnumerator nextObject]) {
        [oldButton removeFromSuperview];
    }
    [reactionButtons removeAllObjects];

    CGFloat x = 72.0;
    CGFloat maximumX = NSWidth([insetView bounds]) - 12.0;
    NSEnumerator *enumerator = [[representedObject reactions] objectEnumerator];
    NSDictionary *reaction;
    while (reaction = [enumerator nextObject]) {
        NSString *identifier = [self reactionIdentifierForReaction:reaction];
        if (!identifier) {
            continue;
        }
        NSDictionary *emoji = [reaction objectForKey:@"emoji"];
        NSString *name = [emoji objectForKey:@"name"];
        id emojiID = [emoji objectForKey:@"id"];
        NSString *count = [NSString stringWithFormat:@"%@", [reaction objectForKey:@"count"]];
        NSImage *emojiImage = nil;
        NSString *title = nil;
        if (emojiID && ![emojiID isKindOfClass:[NSNull class]]) {
            NSString *emojiURL = DLCustomEmojiURL(emojiID, [[emoji objectForKey:@"animated"] boolValue]);
            NSData *cachedData = [[HTTPCache sharedInstance] cachedDataForURL:emojiURL];
            if (cachedData) {
                emojiImage = [[[NSImage alloc] initWithData:cachedData] autorelease];
                [emojiImage setSize:NSMakeSize(16 * displayScale, 16 * displayScale)];
                title = count;
            } else {
                title = [NSString stringWithFormat:@":%@: %@", name, count];
            }
        } else {
            title = [NSString stringWithFormat:@"%@ %@", name, count];
        }

        NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSFont systemFontOfSize:12 * displayScale] forKey:NSFontAttributeName];
        CGFloat width = ceil([title sizeWithAttributes:attributes].width) + (emojiImage ? 38.0 : 20.0);
        width = MAX(42.0, width);
        if (x + width > maximumX) {
            break;
        }
        NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(x, 1, width, reactionHeight - 1.0)];
        [button setAutoresizingMask:NSViewMaxYMargin];
        [button setBezelStyle:NSRecessedBezelStyle];
        [button setButtonType:NSPushOnPushOffButton];
        [button setFont:[NSFont systemFontOfSize:12 * displayScale]];
        [button setTitle:title];
        if (emojiImage) {
            [button setImage:emojiImage];
            [button setImagePosition:NSImageLeft];
        }
        BOOL reactedByMe = [[reaction objectForKey:@"me"] boolValue];
        [button setState:reactedByMe ? NSOnState : NSOffState];
        [button setToolTip:reactedByMe ? @"Remove reaction" : @"Add reaction"];
        [[button cell] setRepresentedObject:identifier];
        [button setTarget:self];
        [button setAction:@selector(quickReaction:)];
        [insetView addSubview:button];
        [reactionButtons addObject:button];
        [button release];
        x += width + 4.0;
    }
    [reactionTextField setHidden:YES];
}

-(void)toggleReaction:(NSMenuItem *)sender {
    NSString *identifier = [sender representedObject];
    NSDictionary *reaction = [self reactionForIdentifier:identifier];
    NSDictionary *emoji = [reaction objectForKey:@"emoji"];
    if (!emoji) {
        emoji = [NSDictionary dictionaryWithObject:identifier forKey:@"name"];
    }

    [self toggleReactionWithEmoji:emoji];
}

-(void)toggleReactionWithEmoji:(NSDictionary *)emoji {
    NSString *name = [emoji objectForKey:@"name"];
    id emojiID = [emoji objectForKey:@"id"];
    NSString *identifier = (emojiID && ![emojiID isKindOfClass:[NSNull class]]) ? [NSString stringWithFormat:@"%@:%@", name, emojiID] : name;
    NSDictionary *reaction = [self reactionForIdentifier:identifier];
    BOOL removing = [[reaction objectForKey:@"me"] boolValue];
    [representedObject applyReactionEmoji:emoji added:!removing byCurrentUser:YES];
    if (removing) {
        [[DLController sharedInstance] removeReactionWithEmoji:identifier fromMessage:representedObject];
    } else {
        [[DLController sharedInstance] addReactionWithEmoji:identifier toMessage:representedObject];
    }
    NSMutableArray *recent = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] objectForKey:@"recentReactionEmoji"] ? [[NSUserDefaults standardUserDefaults] objectForKey:@"recentReactionEmoji"] : [NSArray array]];
    [recent removeObject:identifier];
    [recent insertObject:identifier atIndex:0];
    while ([recent count] > 3) {
        [recent removeLastObject];
    }
    [[NSUserDefaults standardUserDefaults] setObject:recent forKey:@"recentReactionEmoji"];
    [self rebuildMessageActionBar];
}

-(void)quickReaction:(NSButton *)sender {
    NSString *identifier = [[sender cell] representedObject];
    NSRange separator = [identifier rangeOfString:@":" options:NSBackwardsSearch];
    NSDictionary *emoji;
    if (separator.location != NSNotFound) {
        emoji = [NSDictionary dictionaryWithObjectsAndKeys:[identifier substringToIndex:separator.location], @"name", [identifier substringFromIndex:separator.location + 1], @"id", nil];
    } else {
        emoji = [NSDictionary dictionaryWithObject:identifier forKey:@"name"];
    }
    [self toggleReactionWithEmoji:emoji];
    if ([sender superview] != messageActionBar) {
        [self populateMessageActionBar:[sender superview]];
        [[NSNotificationCenter defaultCenter] postNotificationName:DLMessageActionBarDidShowNotification object:self];
    }
}

-(void)showReactionPicker:(id)sender {
    [delegate chatView:self showReactionPickerRelativeToView:(NSView *)sender];
}

-(void)rebuildMessageActionBar {
    [self populateMessageActionBar:messageActionBar];
}

-(void)populateMessageActionBar:(NSView *)actionBar {
    if (!actionBar) {
        return;
    }
    NSArray *subviews = [[actionBar subviews] copy];
    NSEnumerator *subviewEnumerator = [subviews objectEnumerator];
    NSView *subview;
    while (subview = [subviewEnumerator nextObject]) {
        [subview removeFromSuperview];
    }
    [subviews release];
    NSMutableArray *recent = [NSMutableArray array];
    NSArray *savedRecent = [[NSUserDefaults standardUserDefaults] objectForKey:@"recentReactionEmoji"];
    if ([savedRecent isKindOfClass:[NSArray class]]) {
        [recent addObjectsFromArray:savedRecent];
    }
    NSArray *fallback = [NSArray arrayWithObjects:@"👍", @"❤️", @"😂", nil];
    NSEnumerator *fallbackEnumerator = [fallback objectEnumerator];
    NSString *fallbackIdentifier;
    while ([recent count] < 3 && (fallbackIdentifier = [fallbackEnumerator nextObject])) {
        if (![recent containsObject:fallbackIdentifier]) {
            [recent addObject:fallbackIdentifier];
        }
    }
    CGFloat x = 0;
    for (NSInteger index = 0; index < 3; index++) {
        NSString *identifier = [recent objectAtIndex:index];
        NSButton *button = [[DLMessageActionButton alloc] initWithFrame:NSMakeRect(x, 1, 34, 28)];
        [button setBordered:NO];
        [button setRefusesFirstResponder:YES];
        [button setFont:[NSFont systemFontOfSize:14]];
        [[button cell] setRepresentedObject:identifier];
        [button setTarget:self];
        [button setAction:@selector(quickReaction:)];
        NSRange separator = [identifier rangeOfString:@":" options:NSBackwardsSearch];
        if (separator.location == NSNotFound) {
            [button setTitle:identifier];
        } else {
            NSString *emojiID = [identifier substringFromIndex:separator.location + 1];
            NSString *emojiURL = DLCustomEmojiURL(emojiID, [self isCustomEmojiAnimated:emojiID]);
            NSData *data = [[HTTPCache sharedInstance] cachedDataForURL:emojiURL];
            if (data) {
                NSImage *image = [[[NSImage alloc] initWithData:data] autorelease];
                [image setSize:NSMakeSize(18, 18)];
                [button setImage:image];
                [button setImagePosition:NSImageOnly];
            } else {
                [button setTitle:@":"];
                if ([[HTTPCache sharedInstance] beginLoadingURL:emojiURL]) {
                    AsyncHTTPGetRequest *request = [[AsyncHTTPGetRequest alloc] init];
                    [request setDelegate:self];
                    [request setUrl:emojiURL];
                    [request setCached:YES];
                    [request start];
                }
            }
        }
        [actionBar addSubview:button];
        [button release];
        x += 34;
    }
    NSButton *pickerButton = [[DLMessageActionButton alloc] initWithFrame:NSMakeRect(102, 1, 34, 28)];
    [pickerButton setBordered:NO];
    [pickerButton setRefusesFirstResponder:YES];
    [pickerButton setTitle:@"+"];
    [pickerButton setToolTip:@"Add reaction"];
    [pickerButton setTarget:self];
    [pickerButton setAction:@selector(showReactionPicker:)];
    [actionBar addSubview:pickerButton];
    [pickerButton release];
    NSButton *replyButton = [[DLMessageActionButton alloc] initWithFrame:NSMakeRect(136, 1, 52, 28)];
    [replyButton setBordered:NO];
    [replyButton setRefusesFirstResponder:YES];
    [replyButton setTitle:@"Reply"];
    [replyButton setToolTip:@"Reply"];
    [replyButton setTarget:self];
    [replyButton setAction:@selector(addReply)];
    [actionBar addSubview:replyButton];
    [replyButton release];
}

-(NSTextField *)embedTextFieldWithFrame:(NSRect)frame text:(NSString *)text font:(NSFont *)font color:(NSColor *)color {
    NSTextField *field = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [field setBordered:NO];
    [field setDrawsBackground:NO];
    [field setEditable:NO];
    [field setSelectable:YES];
    [field setFont:font];
    [field setTextColor:color];
    [field setStringValue:text ? text : @""];
    [[field cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    return field;
}

-(NSString *)embedMediaURLFromDictionary:(NSDictionary *)media {
    id value = [media objectForKey:@"proxy_url"];
    if (!value || [value isKindOfClass:[NSNull class]]) {
        value = [media objectForKey:@"url"];
    }
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

-(void)startLoadingEmbedImageURL:(NSString *)imageURL {
    if (!imageURL || ![[HTTPCache sharedInstance] beginLoadingURL:imageURL]) {
        return;
    }
    AsyncHTTPGetRequest *request = [[AsyncHTTPGetRequest alloc] init];
    [request setDelegate:self];
    [request setUrl:imageURL];
    [request setCached:YES];
    [request start];
}

-(void)closeWebViewsInView:(NSView *)container {
    NSArray *subviews = [[container subviews] copy];
    NSEnumerator *enumerator = [subviews objectEnumerator];
    NSView *subview;
    while (subview = [enumerator nextObject]) {
        if ([subview isKindOfClass:[WebView class]]) {
            WebView *webView = (WebView *)subview;
            [webView setFrameLoadDelegate:nil];
            [webView setResourceLoadDelegate:nil];
            [webView setPolicyDelegate:nil];
            [webView setUIDelegate:nil];
            [[webView mainFrame] stopLoading];
            [webView close];
        } else {
            [self closeWebViewsInView:subview];
        }
    }
    [subviews release];
}

-(void)closeEmbedWebViews {
    NSEnumerator *enumerator = [embedViews objectEnumerator];
    NSView *embedView;
    while (embedView = [enumerator nextObject]) {
        [self closeWebViewsInView:embedView];
    }
}

-(void)rebuildStickerViews {
    NSEnumerator *oldViewEnumerator = [stickerViews objectEnumerator];
    NSView *oldView;
    while (oldView = [oldViewEnumerator nextObject]) {
        [oldView removeFromSuperview];
    }
    [stickerViews removeAllObjects];
    stickersHeight = 0.0;

    NSArray *items = [representedObject stickerItems];
    NSInteger count = MIN(3, (NSInteger)[items count]);
    if (count <= 0) {
        return;
    }

    CGFloat displayScale = [[DLPreferencesHandler sharedInstance] messageDisplayScale];
    CGFloat spacing = 6.0;
    CGFloat availableWidth = MAX(120.0, NSWidth([insetView bounds]) - 88.0);
    CGFloat stickerSide = MIN(160.0 * displayScale, floor((availableWidth - spacing * (count - 1)) / count));
    stickerSide = MAX(82.0, stickerSide);
    stickersHeight = stickerSide + 8.0;

    for (NSInteger index = 0; index < count; index++) {
        NSDictionary *sticker = [items objectAtIndex:index];
        NSString *name = [[sticker objectForKey:@"name"] isKindOfClass:[NSString class]] ? [sticker objectForKey:@"name"] : @"Sticker";
        NSInteger formatType = [[sticker objectForKey:@"format_type"] integerValue];
        NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(74.0 + index * (stickerSide + spacing), 0.0, stickerSide, stickerSide)];
        NSString *stickerURL = DLStickerURL(sticker);
        if (stickerURL) {
            NSImageView *imageView = [[NSImageView alloc] initWithFrame:[container bounds]];
            [imageView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
            [imageView setImageScaling:NSImageScaleProportionallyUpOrDown];
            [imageView setAnimates:(formatType == 2 || formatType == 4)];
            [imageView setToolTip:name];
            NSData *cachedData = [[HTTPCache sharedInstance] cachedDataForURL:stickerURL];
            if (cachedData) {
                [imageView setImage:[[[NSImage alloc] initWithData:cachedData] autorelease]];
            } else {
                [self startLoadingEmbedImageURL:stickerURL];
            }
            [container addSubview:imageView];
            [imageView release];
        } else {
            NSString *lowercaseName = [name lowercaseString];
            NSString *fallbackSymbol = @"✨";
            if ([lowercaseName rangeOfString:@"wave"].location != NSNotFound || [lowercaseName rangeOfString:@"hello"].location != NSNotFound) {
                fallbackSymbol = @"👋";
            } else if ([lowercaseName rangeOfString:@"happy"].location != NSNotFound || [lowercaseName rangeOfString:@"smile"].location != NSNotFound) {
                fallbackSymbol = @"😊";
            } else if ([lowercaseName rangeOfString:@"sad"].location != NSNotFound || [lowercaseName rangeOfString:@"cry"].location != NSNotFound) {
                fallbackSymbol = @"😢";
            } else if ([lowercaseName rangeOfString:@"laugh"].location != NSNotFound) {
                fallbackSymbol = @"😂";
            } else if ([lowercaseName rangeOfString:@"love"].location != NSNotFound || [lowercaseName rangeOfString:@"heart"].location != NSNotFound) {
                fallbackSymbol = @"❤️";
            }
            NSTextField *label = [self embedTextFieldWithFrame:[container bounds]
                text:fallbackSymbol
                font:[NSFont systemFontOfSize:64.0 * displayScale]
                color:[DLUtil nativePrimaryTextColor]];
            [label setAlignment:NSCenterTextAlignment];
            [label setToolTip:[NSString stringWithFormat:@"%@ (Lottie sticker)", name]];
            [container addSubview:label];
        }
        [insetView addSubview:container];
        [stickerViews addObject:container];
        [container release];
    }
}

-(void)rebuildEmbedViews {
    [self closeEmbedWebViews];
    NSEnumerator *oldViewEnumerator = [embedViews objectEnumerator];
    NSView *oldView;
    while (oldView = [oldViewEnumerator nextObject]) {
        [oldView removeFromSuperview];
    }
    [embedViews removeAllObjects];
    embedsHeight = 0.0;

    CGFloat displayScale = [[DLPreferencesHandler sharedInstance] messageDisplayScale];
    CGFloat cardWidth = MIN(410.0 * displayScale, MAX(240.0, NSWidth([insetView bounds]) - 88.0));
    NSInteger embedCount = 0;
    NSEnumerator *enumerator = [[representedObject embeds] objectEnumerator];
    NSDictionary *embed;
    while ((embed = [enumerator nextObject]) && embedCount < 4) {
        NSString *title = [[embed objectForKey:@"title"] isKindOfClass:[NSString class]] ? [embed objectForKey:@"title"] : nil;
        NSString *description = [[embed objectForKey:@"description"] isKindOfClass:[NSString class]] ? [embed objectForKey:@"description"] : nil;
        NSString *embedURL = [[embed objectForKey:@"url"] isKindOfClass:[NSString class]] ? [embed objectForKey:@"url"] : nil;
        NSDictionary *provider = [[embed objectForKey:@"provider"] isKindOfClass:[NSDictionary class]] ? [embed objectForKey:@"provider"] : nil;
        NSDictionary *author = [[embed objectForKey:@"author"] isKindOfClass:[NSDictionary class]] ? [embed objectForKey:@"author"] : nil;
        NSString *providerName = [[provider objectForKey:@"name"] isKindOfClass:[NSString class]] ? [provider objectForKey:@"name"] : nil;
        NSString *authorName = [[author objectForKey:@"name"] isKindOfClass:[NSString class]] ? [author objectForKey:@"name"] : nil;
        NSDictionary *video = [[embed objectForKey:@"video"] isKindOfClass:[NSDictionary class]] ? [embed objectForKey:@"video"] : nil;
        NSDictionary *image = [[embed objectForKey:@"image"] isKindOfClass:[NSDictionary class]] ? [embed objectForKey:@"image"] : nil;
        NSDictionary *thumbnail = [[embed objectForKey:@"thumbnail"] isKindOfClass:[NSDictionary class]] ? [embed objectForKey:@"thumbnail"] : nil;
        NSDictionary *media = video ? video : (image ? image : thumbnail);
        NSString *mediaURL = [self embedMediaURLFromDictionary:media];
        BOOL hasVideo = video && [mediaURL length] > 0;

        NSInteger descriptionLines = [description length] > 0 ? MIN(4, MAX(1, ((NSInteger)[description length] + 54) / 55)) : 0;
        CGFloat providerHeight = ([providerName length] || [authorName length]) ? 16.0 * displayScale : 0.0;
        CGFloat titleHeight = [title length] ? 19.0 * displayScale : 0.0;
        CGFloat descriptionHeight = descriptionLines * 17.0 * displayScale;
        CGFloat mediaHeight = 0.0;
        if ([mediaURL length]) {
            CGFloat mediaWidth = [[media objectForKey:@"width"] doubleValue];
            CGFloat originalHeight = [[media objectForKey:@"height"] doubleValue];
            if (mediaWidth > 0 && originalHeight > 0) {
                mediaHeight = (cardWidth - 18.0) * originalHeight / mediaWidth;
            } else {
                mediaHeight = hasVideo ? 205.0 * displayScale : 180.0 * displayScale;
            }
            mediaHeight = MIN(230.0 * displayScale, MAX(90.0 * displayScale, mediaHeight));
        }
        CGFloat cardHeight = 16.0 + providerHeight + titleHeight + descriptionHeight +
            (mediaHeight > 0 ? mediaHeight + 8.0 : 0.0);
        if (cardHeight <= 20.0) {
            continue;
        }

        NSBox *card = [[NSBox alloc] initWithFrame:NSMakeRect(74.0, 0.0, cardWidth, cardHeight)];
        [card setBoxType:NSBoxCustom];
        [card setBorderType:NSLineBorder];
        [card setBorderColor:[DLUtil nativeBorderColor]];
        [card setFillColor:[DLUtil nativeChromeColor]];
        [card setTitlePosition:NSNoTitle];
        NSView *cardContent = [card contentView];
        CGFloat y = 8.0;
        if (mediaHeight > 0) {
            NSRect mediaFrame = NSMakeRect(8.0, y, cardWidth - 18.0, mediaHeight);
            if (hasVideo) {
                WebView *videoView = [[[WebView alloc] initWithFrame:mediaFrame] autorelease];
                NSString *escapedURL = [[mediaURL stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"] stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
                BOOL directVideo = [[mediaURL lowercaseString] rangeOfString:@".mp4"].location != NSNotFound || [[mediaURL lowercaseString] rangeOfString:@".webm"].location != NSNotFound;
                NSString *mediaHTML = directVideo
                    ? [NSString stringWithFormat:@"<video src=\"%@\" controls preload='metadata' style='width:100%%;height:100%%'></video>", escapedURL]
                    : [NSString stringWithFormat:@"<iframe src=\"%@\" frameborder='0' allowfullscreen style='width:100%%;height:100%%'></iframe>", escapedURL];
                NSString *html = [NSString stringWithFormat:@"<html><body style='margin:0;background:#111;overflow:hidden'>%@</body></html>", mediaHTML];
                [[videoView mainFrame] loadHTMLString:html baseURL:nil];
                [cardContent addSubview:videoView];
            } else {
                NSImageView *imageView = [[[NSImageView alloc] initWithFrame:mediaFrame] autorelease];
                [imageView setImageScaling:NSImageScaleProportionallyUpOrDown];
                NSData *cachedData = [[HTTPCache sharedInstance] cachedDataForURL:mediaURL];
                if (cachedData) {
                    [imageView setImage:[[[NSImage alloc] initWithData:cachedData] autorelease]];
                } else {
                    [self startLoadingEmbedImageURL:mediaURL];
                }
                [cardContent addSubview:imageView];
            }
            y += mediaHeight + 8.0;
        }
        if (descriptionHeight > 0) {
            NSTextField *descriptionField = [self embedTextFieldWithFrame:NSMakeRect(9.0, y, cardWidth - 20.0, descriptionHeight)
                text:description font:[NSFont systemFontOfSize:12.0 * displayScale] color:[DLUtil nativePrimaryTextColor]];
            [[descriptionField cell] setLineBreakMode:NSLineBreakByWordWrapping];
            [cardContent addSubview:descriptionField];
            y += descriptionHeight;
        }
        if (titleHeight > 0) {
            NSTextField *titleField = [self embedTextFieldWithFrame:NSMakeRect(9.0, y, cardWidth - 20.0, titleHeight)
                text:title font:[NSFont boldSystemFontOfSize:13.0 * displayScale] color:[DLUtil nativeLinkColor]];
            if ([embedURL length]) {
                NSMutableAttributedString *linkedTitle = [[[NSMutableAttributedString alloc] initWithString:title] autorelease];
                [linkedTitle addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:13.0 * displayScale] range:NSMakeRange(0, [linkedTitle length])];
                [linkedTitle addAttribute:NSLinkAttributeName value:embedURL range:NSMakeRange(0, [linkedTitle length])];
                [titleField setAttributedStringValue:linkedTitle];
                [titleField setAllowsEditingTextAttributes:YES];
            }
            [cardContent addSubview:titleField];
            y += titleHeight;
        }
        if (providerHeight > 0) {
            NSString *byline = [authorName length] ? authorName : providerName;
            if ([providerName length] && [authorName length]) {
                byline = [NSString stringWithFormat:@"%@ — %@", authorName, providerName];
            }
            [cardContent addSubview:[self embedTextFieldWithFrame:NSMakeRect(9.0, y, cardWidth - 20.0, providerHeight)
                text:byline font:[NSFont boldSystemFontOfSize:11.0 * displayScale] color:[DLUtil nativeSecondaryTextColor]]];
        }
        [insetView addSubview:card];
        [embedViews addObject:card];
        [card release];
        embedsHeight += cardHeight + 8.0;
        embedCount++;
    }
}

-(void)layoutDynamicMessageViews {
    CGFloat attachmentsHeight = 0;
    NSUInteger attachmentIndex = 0;
    NSEnumerator *enumerator = [[representedObject attachments] objectEnumerator];
    DLAttachment *attachment;
    while (attachment = [enumerator nextObject]) {
        if (attachmentIndex >= [attachmentViews count]) {
            break;
        }
        AttachmentPreviewViewController *attachmentVC = [attachmentViews objectAtIndex:attachmentIndex];
        NSRect frame = [[attachmentVC attachmentView] frame];
        frame.origin.y = ((([self expectedHeight] - attachmentsHeight) - [self headerSpacing]) - chatTextView.frame.size.height) - frame.size.height;
        if ([representedObject referencedMessage]) {
            frame.origin.y -= referencedMessageView.frame.size.height;
        }
        frame.origin.x = chatTextView.frame.origin.x + chatTextView.textContainerInset.height;
        [[attachmentVC attachmentView] setFrame:frame];
        attachmentsHeight += [attachment scaledHeight] + ATTACHMENT_SPACING;
        attachmentIndex++;
    }

    BOOL hasReactions = [[[representedObject reactionSummary] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0;
    CGFloat stickerY = hasReactions ? [self reactionViewHeight] : 0.0;
    NSEnumerator *stickerEnumerator = [stickerViews objectEnumerator];
    NSView *stickerView;
    while (stickerView = [stickerEnumerator nextObject]) {
        NSRect stickerFrame = [stickerView frame];
        stickerFrame.origin.y = stickerY + 4.0;
        [stickerView setFrame:stickerFrame];
    }

    CGFloat embedY = stickerY + stickersHeight;
    NSEnumerator *embedEnumerator = [embedViews reverseObjectEnumerator];
    NSView *embedView;
    while (embedView = [embedEnumerator nextObject]) {
        NSRect embedFrame = [embedView frame];
        embedFrame.origin.y = embedY + 4.0;
        [embedView setFrame:embedFrame];
        embedY += embedFrame.size.height + 8.0;
    }

    if ([representedObject referencedMessage]) {
        NSRect referencedFrame = referencedMessageView.frame;
        referencedFrame.origin.y = NSHeight([insetView bounds]) - referencedFrame.size.height;
        referencedFrame.size.width = NSWidth([insetView bounds]) - 5;
        [referencedMessageView setFrame:referencedFrame];
    }
}

-(void)layoutForCurrentViewFrame {
    NSRect insetFrame = [insetView frame];
    insetFrame.origin.x = 0.0;
    insetFrame.origin.y = compactDisplay ? [self headerSpacing] : 6.0;
    insetFrame.size.width = NSWidth([view bounds]);
    insetFrame.size.height = MAX(0.0, NSHeight([view bounds]) - insetFrame.origin.y);
    [insetView setFrame:insetFrame];
    NSRect actionFrame = [messageActionBar frame];
    actionFrame.origin.x = MAX(4.0, NSWidth([insetView bounds]) - actionFrame.size.width - 8.0);
    actionFrame.origin.y = MAX(0.0, NSHeight([insetView bounds]) - actionFrame.size.height);
    [messageActionBar setFrame:actionFrame];
    [self layoutMessageHeaderFields];
    [self syncAvatarProfileButton];
    if (viewHasLoaded) {
        [self layoutDynamicMessageViews];
    }
}

-(void)loadCustomEmojiImages {
    NSString *customEmojiRegex = @"<a?:[A-Za-z0-9_]+:[0-9]+>";
    NSArray *matches = [[representedObject content] componentsMatchedByRegex:customEmojiRegex];
    NSMutableSet *requestedIDs = [NSMutableSet set];
    NSEnumerator *enumerator = [matches objectEnumerator];
    NSString *match;
    while (match = [enumerator nextObject]) {
        NSString *emojiID = [match stringByMatching:@"[0-9]+"];
        if (!emojiID || [requestedIDs containsObject:emojiID]) {
            continue;
        }
        [requestedIDs addObject:emojiID];
        BOOL animated = [match hasPrefix:@"<a:"];
        NSString *emojiURL = DLCustomEmojiURL(emojiID, animated);
        if (![[HTTPCache sharedInstance] beginLoadingURL:emojiURL]) {
            continue;
        }
        AsyncHTTPGetRequest *request = [[AsyncHTTPGetRequest alloc] init];
        [request setDelegate:self];
        [request setUrl:emojiURL];
        [request setCached:YES];
        [request start];
    }
    enumerator = [[representedObject reactions] objectEnumerator];
    NSDictionary *reaction;
    while (reaction = [enumerator nextObject]) {
        id emojiID = [[reaction objectForKey:@"emoji"] objectForKey:@"id"];
        if (!emojiID || [emojiID isKindOfClass:[NSNull class]] || [requestedIDs containsObject:emojiID]) {
            continue;
        }
        [requestedIDs addObject:emojiID];
        NSDictionary *emoji = [reaction objectForKey:@"emoji"];
        NSString *emojiURL = DLCustomEmojiURL(emojiID, [[emoji objectForKey:@"animated"] boolValue]);
        if (![[HTTPCache sharedInstance] beginLoadingURL:emojiURL]) {
            continue;
        }
        AsyncHTTPGetRequest *request = [[AsyncHTTPGetRequest alloc] init];
        [request setDelegate:self];
        [request setUrl:emojiURL];
        [request setCached:YES];
        [request start];
    }
}
-(DLMessage *)representedObject {
    return representedObject;
}
-(void)setDelegate:(id<ChatItemViewControllerDelegate>)inDelegate {
    delegate = inDelegate;
}
-(void)setRepresentedObject:(DLMessage *)obj {
    [representedObject release];
    [obj retain];
    representedObject = obj;
    [self updateViewFromRepresentedObject];
}

-(void)updateViewFromRepresentedObject {
    [representedObject setDelegate:self];
    [[representedObject author] setDelegate:self];
    
    NSAttributedString *as = [DLTextParser attributedContentStringForMessage:representedObject];
    if (as) {
        [[chatTextView textStorage] setAttributedString:as];
    }
    [self updateJumboEmojiLayout];

    NSString *reactionSummary = [representedObject reactionSummary];
    [reactionTextField setAttributedStringValue:[self attributedReactionSummary]];
    [reactionTextField setHidden:[reactionSummary length] == 0];
    [self rebuildReactionButtons];
    [self updateReactionMenu];
    [editedInfoLabel setHidden:[representedObject editedTimestamp] == nil];
    [self loadCustomEmojiImages];
    [self rebuildStickerViews];
    if ([embedViews count] == 0 && [[representedObject embeds] count] > 0) {
        [self rebuildEmbedViews];
    }

    if (viewHasLoaded) {
        [self layoutDynamicMessageViews];
        [self refreshAnimatedEmojiTimer];
        [self syncAvatarProfileButton];
        return;
    }

    [usernameTextField setStringValue:[[representedObject author] globalName]];
    [avatarImageView setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:[[representedObject author] avatarImageData]] autorelease] newSize:avatarImageView.frame.size cornerRadius:[ChatItemViewController AVATAR_RADIUS]]];
    [[representedObject author] loadAvatarData];
    
    NSCalendar *cal = [NSCalendar currentCalendar];
    
    NSDate *date = [NSDate date];
    NSDateComponents *comps = [cal components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit) fromDate:date];
    NSDate *today = [cal dateFromComponents:comps];
    NSDateComponents *components = [[NSDateComponents alloc] init];
    [components setDay:-1];
    NSDate *yesterday = [cal dateByAddingComponents:components toDate:today options:0];
    NSString *dateFormat = @"H:mm";
    NSString *dateUserString = @"";
    if ([[representedObject timestamp] isGreaterThan:today]) {
        dateUserString = @"";
    } else if ([[representedObject timestamp] isGreaterThan:yesterday]) {
        dateUserString = @"Yesterday";
    } else {
        dateUserString = @"";
        dateFormat = @"M/dd/yyyy H:mm";
    }
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setFormatterBehavior:NSDateFormatterBehavior10_4];
    [formatter setDateFormat:dateFormat];
    NSString *timestamp = [formatter stringFromDate:[representedObject timestamp]];
    NSString *displayTimestamp = [dateUserString length]
        ? [NSString stringWithFormat:@"%@ %@", dateUserString, timestamp]
        : timestamp;
    [timestampTextField setStringValue:displayTimestamp];
    [self layoutMessageHeaderFields];
    
    [components release];
    
    CGFloat attachmentsHeight = 0;
    NSMutableArray *views = [[NSMutableArray alloc] init];
    NSEnumerator *e = [[representedObject attachments] objectEnumerator];
    DLAttachment *attachment;
    while (attachment = [e nextObject]) {
        AttachmentPreviewViewController *attachmentVC = [[AttachmentPreviewViewController alloc] initWithNibNamed:@"AttachmentPreviewViewController" bundle:nil];
        [attachmentVC setRepresentedObject:attachment];
        NSRect frame = [attachmentVC attachmentView].frame;
        frame.origin.y = ((([self expectedHeight] - attachmentsHeight) - [self headerSpacing]) - chatTextView.frame.size.height) - frame.size.height;
        if ([representedObject referencedMessage]) {
            frame.origin.y -= referencedMessageView.frame.size.height;
        }
        frame.origin.x = chatTextView.frame.origin.x + chatTextView.textContainerInset.height;
        [[attachmentVC attachmentView] setFrame:frame];
        [views addObject:attachmentVC];
        [insetView addSubview:attachmentVC.attachmentView];
        attachmentsHeight += [attachment scaledHeight] + ATTACHMENT_SPACING;
        [attachmentVC release];
    }
    attachmentViews = views;
    
    CGFloat shift = 0;
    if ([representedObject referencedMessage] && !viewHasLoaded) {
        [[[representedObject referencedMessage] author] setDelegate:self];
        shift = referencedMessageView.frame.size.height;
        
        NSMutableAttributedString *attStr = [[NSMutableAttributedString alloc] initWithString:[[[[representedObject referencedMessage] author] globalName] stringByAppendingString:@" "]];
        [attStr addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:12 * [[DLPreferencesHandler sharedInstance] messageDisplayScale]] range:NSMakeRange(0, attStr.length)];
        [attStr appendAttributedString:[DLTextParser attributedContentStringForMessage:[representedObject referencedMessage]]];
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.lineBreakMode = NSLineBreakByTruncatingTail;
        [attStr addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, attStr.length)];
        [referencedMessageTextField setAttributedStringValue:attStr];
        
        [referencedMessageAvatarImageView setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:[[[representedObject referencedMessage] author] avatarImageData]] autorelease] newSize:referencedMessageAvatarImageView.frame.size cornerRadius:[ChatItemViewController REFERENCED_AVATAR_RADIUS]]];
        NSRect frame = usernameTextField.frame;
        frame.origin.y -= shift;
        [usernameTextField setFrame:frame];
        frame = timestampTextField.frame;
        frame.origin.y -= shift;
        [timestampTextField setFrame:frame];
        frame = avatarImageView.frame;
        frame.origin.y -= shift;
        [avatarImageView setFrame:frame];
        [self syncAvatarProfileButton];
        
        [insetView addSubview:referencedMessageView];
        
        [[[representedObject referencedMessage] author] loadAvatarData];
    }
    [self layoutDynamicMessageViews];
    
    BOOL mentionedMyUser = NO;
    e = [[representedObject mentionedUsers] objectEnumerator];
    DLUser *u;
    while (u = [e nextObject]) {
        if ([u isEqual:[[DLController sharedInstance] myUser]]) {
            mentionedMyUser = YES;
        }
    }
    
    if ([representedObject mentionedEveryone]) {
        mentionedMyUser = YES;
    }
    
    if (mentionedMyUser) {
        usesMentionBackground = YES;
        [insetView setBackgroundColor:[DLUtil nativeMentionColor]];
        [insetView setNeedsDisplay:YES];
    }
    
    [self syncAvatarProfileButton];
    viewHasLoaded = YES;
    [self refreshAnimatedEmojiTimer];
}

-(void)setSearchHighlighted:(BOOL)highlighted {
    searchHighlighted = highlighted;
    if (searchHighlighted) {
        [insetView setBackgroundColor:[DLUtil nativeTagColor]];
    } else if (usesMentionBackground) {
        [insetView setBackgroundColor:[DLUtil nativeMentionColor]];
    } else {
        [insetView setBackgroundColor:[NSColor clearColor]];
    }
    [insetView setNeedsDisplay:YES];
}

-(void)setCompactDisplay:(BOOL)compact {
    if ([representedObject referencedMessage]) {
        compact = NO;
    }
    compactDisplay = compact;
    NSRect insetFrame = [insetView frame];
    insetFrame.origin.y = compactDisplay ? [self headerSpacing] : 6.0;
    [insetView setFrame:insetFrame];
    [avatarImageView setHidden:compactDisplay];
    [avatarProfileButton setHidden:compactDisplay];
    [usernameTextField setHidden:compactDisplay];
    [timestampTextField setHidden:compactDisplay];
    if (viewHasLoaded) {
        [self layoutForCurrentViewFrame];
    } else {
        [self syncAvatarProfileButton];
    }
}

-(void)setGroupedMessageFollows:(BOOL)follows {
    if (groupedMessageFollows == follows) {
        return;
    }
    CGFloat groupShift = round(12.0 * [[DLPreferencesHandler sharedInstance] messageDisplayScale]);
    CGFloat shift = follows ? -groupShift : groupShift;
    NSRect frame = [usernameTextField frame];
    frame.origin.y += shift;
    [usernameTextField setFrame:frame];
    frame = [timestampTextField frame];
    frame.origin.y += shift;
    [timestampTextField setFrame:frame];
    groupedMessageFollows = follows;
    if (viewHasLoaded) {
        [self layoutForCurrentViewFrame];
    }
}

-(BOOL)isMessageActionBarVisible {
    return ![messageActionBar isHidden];
}

-(void)hideMessageActionBar {
    [messageActionBar setHidden:YES];
}

-(void)addReply {
    [delegate addReferencedMessage:representedObject];
}

-(void)setIsMyContent:(BOOL)mine {
    if (mine) {
        [contextMenu addItem:editItem];
        [contextMenu addItem:deleteItem];
    } else {
        [contextMenu removeItem:editItem];
        [contextMenu removeItem:deleteItem];
    }
}

-(void)beginEditingContent {
    if ([delegate chatViewShouldBeginEditing:self]) {
        isEditing = YES;
        [chatTextView setString:[representedObject content]];
        [chatTextView setEditable:YES];
        [chatTextView setDrawsBackground:YES];
        [editDismissInfoLabel setHidden:NO];
    }
}
-(void)showAuthorProfile:(id)sender {
    if ([delegate respondsToSelector:@selector(chatView:showProfileForUser:relativeToView:)]) {
        [delegate chatView:self showProfileForUser:[representedObject author] relativeToView:avatarImageView];
    }
}
-(void)endEditingContent {
    isEditing = NO;
    [chatTextView setEditable:NO];
    [chatTextView setDrawsBackground:NO];
    [editDismissInfoLabel setHidden:YES];
}
-(BOOL)isBeingEdited {
    return isEditing;
}
-(void)beginDeletingMessage {
    [delegate chatViewMessageShouldBeDeleted:self];
}
-(void)becomeWindowFirstResponderForEditing:(NSWindow *)window {
    [window makeFirstResponder:chatTextView];
}
-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopAnimatedEmojiPlayback];
    [insetView setDelegate:nil];
    [self closeEmbedWebViews];
    [attachmentViews release];
    [embedViews release];
    [stickerViews release];
    [reactionButtons release];
    [reactionTextField release];
    [messageActionBar release];
    [avatarProfileButton release];
    [reactionMenu release];
    [contextMenu release];
    [editItem release];
    [deleteItem release];
    [representedObject release];
    [self.view release];
    [super dealloc];
}

#pragma mark Delegated Functions

-(void)user:(DLUser *)u avatarDidUpdateWithData:(NSData *)data {
    if ([u isEqual:[representedObject author]]) {
        [avatarImageView setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:data] autorelease] newSize:avatarImageView.frame.size cornerRadius:[ChatItemViewController AVATAR_RADIUS]]];
    }
    if ([representedObject referencedMessage]) {
        if ([u isEqual:[[representedObject referencedMessage] author]]) {
            [referencedMessageAvatarImageView setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:data] autorelease] newSize:referencedMessageAvatarImageView.frame.size cornerRadius:[ChatItemViewController REFERENCED_AVATAR_RADIUS]]];
        }
    }
}

-(void)mouseWasDepressedWithEvent:(NSEvent *)event {
    if ((event.modifierFlags & NSControlKeyMask) == NSControlKeyMask) {
        [NSMenu popUpContextMenu:contextMenu withEvent:event forView:nil];
    }
}
-(void)mouseRightButtonWasDepressedWithEvent:(NSEvent *)event {
    [NSMenu popUpContextMenu:contextMenu withEvent:event forView:nil];
}
-(void)mouseEnteredView:(NSView *)hoveredView {
    if (hoveredView == insetView) {
        [[NSNotificationCenter defaultCenter] postNotificationName:DLMessageActionBarDidShowNotification object:self];
    }
}
-(void)mouseExitedView:(NSView *)hoveredView {
    if (hoveredView == insetView) {
        [[NSNotificationCenter defaultCenter] postNotificationName:DLMessageActionBarDidHideNotification object:self];
    }
}

-(NSMenu *)textViewContextMenu {
    return contextMenu;
}
-(void)escapeKeyWasPressed {
    [self endEditingContent];
    [[chatTextView textStorage] setAttributedString:[DLTextParser attributedContentStringForMessage:representedObject]];
    [delegate chatView:self didEndEditingWithCommit:NO];
}
-(void)messageContentWasUpdated {
    [self updateViewFromRepresentedObject];
    [delegate chatViewContentWasUpdated:self];
}
-(void)messageWasDeleted {
    [delegate chatViewMessageWasDeleted:self];
}

-(void)requestDidFinishLoading:(AsyncHTTPRequest *)request {
    if ([request result] != HTTPResultOK) {
        [[HTTPCache sharedInstance] endLoadingURL:[request url]];
    }
    [request release];
}

-(void)cachedEmojiDidUpdate:(NSNotification *)notification {
    NSString *updatedURL = [notification object];
    NSEnumerator *stickerEnumerator = [[representedObject stickerItems] objectEnumerator];
    NSDictionary *sticker;
    while (sticker = [stickerEnumerator nextObject]) {
        if ([DLStickerURL(sticker) isEqualToString:updatedURL]) {
            [self rebuildStickerViews];
            [self layoutDynamicMessageViews];
            [delegate chatViewContentWasUpdated:self];
            return;
        }
    }

    BOOL messageUsesEmoji = NO;
    NSEnumerator *reactionEnumerator = [[representedObject reactions] objectEnumerator];
    NSDictionary *reaction;
    while (reaction = [reactionEnumerator nextObject]) {
        NSDictionary *emoji = [reaction objectForKey:@"emoji"];
        id emojiID = [emoji objectForKey:@"id"];
        if (emojiID && ![emojiID isKindOfClass:[NSNull class]] &&
            [DLCustomEmojiURL(emojiID, [[emoji objectForKey:@"animated"] boolValue]) isEqualToString:updatedURL]) {
            messageUsesEmoji = YES;
            break;
        }
    }
    if (!messageUsesEmoji) {
        NSString *content = [representedObject content];
        NSArray *matches = [content componentsMatchedByRegex:@"<a?:[A-Za-z0-9_]+:[0-9]+>"];
        NSEnumerator *matchEnumerator = [matches objectEnumerator];
        NSString *match;
        while (match = [matchEnumerator nextObject]) {
            NSString *emojiID = [match stringByMatching:@"[0-9]+"];
            if ([DLCustomEmojiURL(emojiID, [match hasPrefix:@"<a:"]) isEqualToString:updatedURL]) {
                messageUsesEmoji = YES;
                break;
            }
        }
    }
    BOOL embedUsesImage = NO;
    NSEnumerator *embedEnumerator = [[representedObject embeds] objectEnumerator];
    NSDictionary *embed;
    while (embed = [embedEnumerator nextObject]) {
        NSArray *mediaKeys = [NSArray arrayWithObjects:@"image", @"thumbnail", nil];
        NSEnumerator *keyEnumerator = [mediaKeys objectEnumerator];
        NSString *mediaKey;
        while (mediaKey = [keyEnumerator nextObject]) {
            NSDictionary *media = [[embed objectForKey:mediaKey] isKindOfClass:[NSDictionary class]] ? [embed objectForKey:mediaKey] : nil;
            if ([[self embedMediaURLFromDictionary:media] isEqualToString:updatedURL]) {
                embedUsesImage = YES;
                break;
            }
        }
        if (embedUsesImage) {
            break;
        }
    }
    if (embedUsesImage) {
        [self rebuildEmbedViews];
        [self layoutDynamicMessageViews];
        [delegate chatViewContentWasUpdated:self];
        return;
    }
    if (!messageUsesEmoji) {
        return;
    }
    [[chatTextView textStorage] setAttributedString:[DLTextParser attributedContentStringForMessage:representedObject]];
    [reactionTextField setAttributedStringValue:[self attributedReactionSummary]];
    [self rebuildReactionButtons];
    [self updateReactionMenu];
    [self rebuildMessageActionBar];
    [self updateJumboEmojiLayout];
    [self refreshAnimatedEmojiTimer];
    [delegate chatViewContentWasUpdated:self];
}

#pragma mark TextView Delegated Functions

-(void)textDidChange:(NSNotification *)notification {
    [delegate chatViewUpdatedWithEnteredText:self];
}

- (BOOL)textView:(NSTextView *)aTextView doCommandBySelector:(SEL)aSelector
{
    if (aSelector == @selector(insertNewline:)) {
        NSEvent * event = [NSApp currentEvent];
        if ((event.modifierFlags & NSShiftKeyMask) != NSShiftKeyMask) {
            [self endEditingContent];
            [representedObject setContent:[chatTextView string]];
            [delegate chatView:self didEndEditingWithCommit:YES];
            return YES;
        }
    }
    return NO;
}

@end
