//
//  DLMainWindowController.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/27/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLMainWindowController.h"
#import "DLUtil.h"
#import "DLPreferencesHandler.h"

static NSString *DLStickerPickerURL(NSDictionary *sticker) {
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

@interface DLDarkSplitView : NSSplitView
@end

@implementation DLDarkSplitView
-(void)drawDividerInRect:(NSRect)rect {
    [[DLUtil nativeBorderColor] set];
    NSRectFill(rect);
}
@end

@interface DLDarkSearchFieldCell : NSSearchFieldCell
@end

@implementation DLDarkSearchFieldCell
-(void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    NSRect backgroundRect = NSInsetRect(cellFrame, 0.5, 0.5);
    [[DLUtil nativeInputColor] set];
    [[NSBezierPath bezierPathWithRoundedRect:backgroundRect xRadius:6.0 yRadius:6.0] fill];
    [[DLUtil nativeBorderColor] set];
    [[NSBezierPath bezierPathWithRoundedRect:backgroundRect xRadius:6.0 yRadius:6.0] stroke];
    [self drawInteriorWithFrame:NSInsetRect(cellFrame, 2.0, 1.0) inView:controlView];
}
@end

@interface DLMessageComposerBackgroundView : NSView
@end

@implementation DLMessageComposerBackgroundView
-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = NSInsetRect([self bounds], 0.5, 0.5);
    NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:7.0 yRadius:7.0];
    [[DLUtil nativeInputColor] set];
    [background fill];
    [[DLUtil nativeBorderColor] set];
    [background setLineWidth:1.0];
    [background stroke];
}
@end

@interface DLServerTableCell : NSCell {
    DLServer *representedServer;
    BOOL drawsSeparatorBefore;
}
-(void)setRepresentedServer:(DLServer *)server;
-(void)setDrawsSeparatorBefore:(BOOL)drawSeparator;
@end

@implementation DLServerTableCell

-(void)setRepresentedServer:(DLServer *)server {
    representedServer = server;
}

-(void)setDrawsSeparatorBefore:(BOOL)drawSeparator {
    drawsSeparatorBefore = drawSeparator;
}

-(void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (!representedServer) {
        return;
    }
    NSInteger row = [(NSTableView *)controlView rowAtPoint:NSMakePoint(NSMidX(cellFrame), NSMidY(cellFrame))];
    BOOL selected = (row >= 0 && [[(NSTableView *)controlView selectedRowIndexes] containsIndex:(NSUInteger)row]);

    if (drawsSeparatorBefore) {
        [[NSColor colorWithCalibratedWhite:0.38 alpha:1.0] set];
        NSRectFill(NSMakeRect(NSMinX(cellFrame) + 17.0, NSMaxY(cellFrame) - 1.0,
                              NSWidth(cellFrame) - 34.0, 1.0));
    }

    NSRect iconRect = NSMakeRect(NSMidX(cellFrame) - 22.0, NSMidY(cellFrame) - 22.0, 44.0, 44.0);
    NSImage *sourceImage = [[[NSImage alloc] initWithData:[representedServer iconImageData]] autorelease];
    if (sourceImage) {
        CGFloat cornerRadius = selected ? 14.0 : 22.0;
        NSImage *roundedImage = [DLUtil imageResize:sourceImage newSize:iconRect.size cornerRadius:cornerRadius];
        [roundedImage drawInRect:iconRect
                       fromRect:NSZeroRect
                      operation:NSCompositeSourceOver
                       fraction:1.0
                 respectFlipped:YES
                          hints:nil];
    }

    if (selected) {
        [[NSColor whiteColor] set];
        NSBezierPath *selectedPath = [NSBezierPath bezierPathWithRoundedRect:
                                      NSMakeRect(NSMinX(cellFrame), NSMidY(cellFrame) - 18.0, 4.0, 36.0)
                                                                           xRadius:2.0 yRadius:2.0];
        [selectedPath fill];
    } else if ([representedServer hasUnreadMessages]) {
        [[NSColor whiteColor] set];
        NSBezierPath *unreadPath = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMinX(cellFrame), NSMidY(cellFrame) - 5.0, 4.0, 10.0)
                                                                      xRadius:2.0 yRadius:2.0];
        [unreadPath fill];
    }

    NSInteger mentionCount = [representedServer mentionCount];
    if (mentionCount > 0) {
        NSString *badgeText = mentionCount > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)mentionCount];
        NSRect badgeRect = NSMakeRect(NSMaxX(iconRect) - 13.0, NSMinY(iconRect) - 1.0, 20.0, 16.0);
        [[NSColor colorWithCalibratedRed:0.82 green:0.08 blue:0.10 alpha:1.0] set];
        [[NSBezierPath bezierPathWithRoundedRect:badgeRect xRadius:8.0 yRadius:8.0] fill];

        NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSFont boldSystemFontOfSize:9.0], NSFontAttributeName,
                                    [NSColor whiteColor], NSForegroundColorAttributeName,
                                    nil];
        NSSize textSize = [badgeText sizeWithAttributes:attributes];
        NSPoint textPoint = NSMakePoint(NSMidX(badgeRect) - textSize.width / 2.0,
                                       NSMidY(badgeRect) - textSize.height / 2.0);
        [badgeText drawAtPoint:textPoint withAttributes:attributes];
    }
}

@end

@interface DLEmojiButton : NSButton
@end

@implementation DLEmojiButton

-(void)drawRect:(NSRect)dirtyRect {
    [NSGraphicsContext saveGraphicsState];
    if ([self isFlipped]) {
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:0.0 yBy:NSHeight([self bounds])];
        [transform scaleXBy:1.0 yBy:-1.0];
        [transform concat];
    }
    NSRect bounds = [self bounds];
    NSPoint center = NSMakePoint(NSMidX(bounds), NSMidY(bounds));
    NSColor *faceColor = [self isEnabled] ? [DLUtil nativePrimaryTextColor]
                                           : [DLUtil nativeSecondaryTextColor];
    [faceColor set];

    NSBezierPath *face = [NSBezierPath bezierPathWithOvalInRect:
                          NSMakeRect(center.x - 8.0, center.y - 8.0, 16.0, 16.0)];
    [face setLineWidth:1.8];
    [face stroke];

    CGFloat eyeY = center.y + 2.0;
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x - 4.5, eyeY, 2.0, 2.0)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x + 2.5, eyeY, 2.0, 2.0)] fill];

    NSBezierPath *smile = [NSBezierPath bezierPath];
    CGFloat mouthY = center.y - 2.0;
    CGFloat smileY = center.y - 5.0;
    [smile moveToPoint:NSMakePoint(center.x - 4.5, mouthY)];
    [smile curveToPoint:NSMakePoint(center.x + 4.5, mouthY)
           controlPoint1:NSMakePoint(center.x - 2.5, smileY)
           controlPoint2:NSMakePoint(center.x + 2.5, smileY)];
    [smile setLineWidth:2.0];
    [smile stroke];
    [NSGraphicsContext restoreGraphicsState];
}

@end

@interface DLStickerButton : NSButton
@end

@implementation DLStickerButton

-(void)drawRect:(NSRect)dirtyRect {
    [NSGraphicsContext saveGraphicsState];
    if ([self isFlipped]) {
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:0.0 yBy:NSHeight([self bounds])];
        [transform scaleXBy:1.0 yBy:-1.0];
        [transform concat];
    }
    NSColor *color = [self isEnabled] ? [DLUtil nativePrimaryTextColor]
                                      : [DLUtil nativeSecondaryTextColor];
    [color set];
    NSRect bounds = [self bounds];
    NSRect stickerRect = NSMakeRect(NSMidX(bounds) - 7.5, NSMidY(bounds) - 7.5, 15.0, 15.0);
    NSBezierPath *sticker = [NSBezierPath bezierPath];
    [sticker moveToPoint:NSMakePoint(NSMinX(stickerRect), NSMinY(stickerRect))];
    [sticker lineToPoint:NSMakePoint(NSMinX(stickerRect), NSMaxY(stickerRect))];
    [sticker lineToPoint:NSMakePoint(NSMaxX(stickerRect), NSMaxY(stickerRect))];
    [sticker lineToPoint:NSMakePoint(NSMaxX(stickerRect), NSMinY(stickerRect) + 5.0)];
    [sticker lineToPoint:NSMakePoint(NSMaxX(stickerRect) - 5.0, NSMinY(stickerRect))];
    [sticker closePath];
    [sticker setLineWidth:1.8];
    [sticker stroke];
    NSBezierPath *fold = [NSBezierPath bezierPath];
    [fold moveToPoint:NSMakePoint(NSMaxX(stickerRect) - 5.0, NSMinY(stickerRect))];
    [fold lineToPoint:NSMakePoint(NSMaxX(stickerRect) - 5.0, NSMinY(stickerRect) + 5.0)];
    [fold lineToPoint:NSMakePoint(NSMaxX(stickerRect), NSMinY(stickerRect) + 5.0)];
    [fold setLineWidth:1.5];
    [fold stroke];
    [NSGraphicsContext restoreGraphicsState];
}

@end

@interface DLConnectionIndicatorView : NSView {
    NSColor *indicatorColor;
}
-(void)setIndicatorColor:(NSColor *)color;
@end

@implementation DLConnectionIndicatorView

-(void)setIndicatorColor:(NSColor *)color {
    if (indicatorColor != color) {
        [indicatorColor release];
        indicatorColor = [color retain];
    }
    [self setNeedsDisplay:YES];
}

-(void)drawRect:(NSRect)dirtyRect {
    NSRect circleRect = NSMakeRect(NSMidX([self bounds]) - 6.0, NSMidY([self bounds]) - 6.0, 12.0, 12.0);
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.18] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(circleRect, -1.0, -1.0)] fill];
    [(indicatorColor ? indicatorColor : [NSColor grayColor]) set];
    [[NSBezierPath bezierPathWithOvalInRect:circleRect] fill];
}

-(void)dealloc {
    [indicatorColor release];
    [super dealloc];
}

@end

@interface DLProfileStatusBubbleView : NSView
@end

@implementation DLProfileStatusBubbleView
-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = NSInsetRect([self bounds], 1.0, 1.0);
    NSBezierPath *bubble = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:13.0 yRadius:13.0];
    [[DLUtil nativeInputColor] set];
    [bubble fill];
    [[NSColor colorWithCalibratedWhite:0.55 alpha:0.28] set];
    [bubble setLineWidth:1.0];
    [bubble stroke];
}
@end

@interface DLProfileRoleChipView : NSView {
    NSString *roleName;
    NSColor *roleColor;
}
-(id)initWithFrame:(NSRect)frame name:(NSString *)name color:(NSColor *)color;
@end

@implementation DLProfileRoleChipView
-(id)initWithFrame:(NSRect)frame name:(NSString *)name color:(NSColor *)color {
    self = [super initWithFrame:frame];
    roleName = [name copy];
    roleColor = [color retain];
    return self;
}
-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = NSInsetRect([self bounds], 0.5, 0.5);
    NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:8.0 yRadius:8.0];
    [[NSColor colorWithCalibratedWhite:0.5 alpha:0.10] set];
    [pill fill];
    [[NSColor colorWithCalibratedWhite:0.5 alpha:0.28] set];
    [pill setLineWidth:1.0];
    [pill stroke];
    [(roleColor ? roleColor : [NSColor grayColor]) set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(7.0, NSMidY(bounds) - 4.0, 8.0, 8.0)] fill];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont systemFontOfSize:10.0], NSFontAttributeName,
                                [DLUtil nativePrimaryTextColor], NSForegroundColorAttributeName, nil];
    [roleName drawAtPoint:NSMakePoint(19.0, NSMidY(bounds) - 6.0) withAttributes:attributes];
}
-(void)dealloc {
    [roleName release];
    [roleColor release];
    [super dealloc];
}
@end

@interface DLMemberButton : NSButton
@end

@implementation DLMemberButton
-(void)drawRect:(NSRect)dirtyRect {
    [NSGraphicsContext saveGraphicsState];
    if ([self isFlipped]) {
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:0.0 yBy:NSHeight([self bounds])];
        [transform scaleXBy:1.0 yBy:-1.0];
        [transform concat];
    }
    NSColor *color = [self isEnabled] ? [DLUtil nativePrimaryTextColor] : [DLUtil nativeSecondaryTextColor];
    [color set];
    NSRect bounds = [self bounds];
    CGFloat cx = NSMidX(bounds);
    CGFloat cy = NSMidY(bounds);
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(cx - 7.0, cy + 1.0, 6.0, 6.0)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(cx + 2.0, cy + 2.0, 5.0, 5.0)] fill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(cx - 9.0, cy - 7.0, 10.0, 7.0)
                                     xRadius:3.0 yRadius:3.0] fill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(cx + 1.0, cy - 6.0, 8.0, 6.0)
                                     xRadius:3.0 yRadius:3.0] fill];
    [NSGraphicsContext restoreGraphicsState];
}
@end

@interface DLPinsButton : NSButton
@end

@implementation DLPinsButton
-(void)drawRect:(NSRect)dirtyRect {
    [NSGraphicsContext saveGraphicsState];
    if ([self isFlipped]) {
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:0.0 yBy:NSHeight([self bounds])];
        [transform scaleXBy:1.0 yBy:-1.0];
        [transform concat];
    }
    NSColor *color = [self isEnabled] ? [DLUtil nativePrimaryTextColor] : [DLUtil nativeSecondaryTextColor];
    [color set];
    CGFloat cx = NSMidX([self bounds]);
    CGFloat cy = NSMidY([self bounds]);
    NSBezierPath *pin = [NSBezierPath bezierPath];
    [pin moveToPoint:NSMakePoint(cx - 5.0, cy + 6.0)];
    [pin lineToPoint:NSMakePoint(cx + 5.0, cy + 6.0)];
    [pin lineToPoint:NSMakePoint(cx + 3.0, cy + 1.0)];
    [pin lineToPoint:NSMakePoint(cx + 7.0, cy - 4.0)];
    [pin lineToPoint:NSMakePoint(cx - 7.0, cy - 4.0)];
    [pin lineToPoint:NSMakePoint(cx - 3.0, cy + 1.0)];
    [pin closePath];
    [pin fill];
    NSBezierPath *needle = [NSBezierPath bezierPath];
    [needle moveToPoint:NSMakePoint(cx, cy - 4.0)];
    [needle lineToPoint:NSMakePoint(cx, cy - 10.0)];
    [needle setLineWidth:1.5];
    [needle stroke];
    [NSGraphicsContext restoreGraphicsState];
}
@end

@interface DLMemberListCell : NSCell {
    DLServerMember *representedMember;
}
-(void)setRepresentedMember:(DLServerMember *)member;
@end

@implementation DLMemberListCell
-(void)setRepresentedMember:(DLServerMember *)member {
    representedMember = member;
}
-(void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    DLUser *user = [representedMember user];
    if (!user) return;
    NSRect avatarRect = NSMakeRect(NSMinX(cellFrame) + 9.0, NSMidY(cellFrame) - 14.0, 28.0, 28.0);
    NSImage *avatar = [[[NSImage alloc] initWithData:[user avatarImageData]] autorelease];
    if (avatar) {
        [NSGraphicsContext saveGraphicsState];
        [[NSBezierPath bezierPathWithOvalInRect:avatarRect] addClip];
        [avatar drawInRect:avatarRect fromRect:NSZeroRect operation:NSCompositeSourceOver
                  fraction:1.0 respectFlipped:YES hints:nil];
        [NSGraphicsContext restoreGraphicsState];
    }
    NSString *name = [user globalName] ? [user globalName] : [user username];
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [style setLineBreakMode:NSLineBreakByTruncatingTail];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont systemFontOfSize:11.0], NSFontAttributeName,
                                [DLUtil nativePrimaryTextColor], NSForegroundColorAttributeName,
                                style, NSParagraphStyleAttributeName, nil];
    [name drawInRect:NSMakeRect(NSMaxX(avatarRect) + 8.0, NSMidY(cellFrame) - 8.0,
                                NSWidth(cellFrame) - NSMaxX(avatarRect) - 16.0, 17.0)
        withAttributes:attributes];
}
@end

@interface DLSearchResultCell : NSCell {
    DLMessage *representedMessage;
}
-(void)setRepresentedMessage:(DLMessage *)message;
@end

@implementation DLSearchResultCell

-(void)setRepresentedMessage:(DLMessage *)message {
    representedMessage = message;
}

-(void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (!representedMessage) {
        return;
    }
    DLMessage *message = representedMessage;
    NSRect cardRect = NSInsetRect(cellFrame, 5.0, 4.0);
    NSColor *background = [self isHighlighted] ? [DLUtil nativeSelectionColor]
                                                : [DLUtil nativeChromeColor];
    [background set];
    [[NSBezierPath bezierPathWithRoundedRect:cardRect xRadius:6.0 yRadius:6.0] fill];

    NSString *author = [[message author] globalName] ? [[message author] globalName] : [[message author] username];
    NSString *contentText = [[message content] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if (!contentText) {
        contentText = @"";
    }
    NSMutableParagraphStyle *truncate = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [truncate setLineBreakMode:NSLineBreakByTruncatingTail];
    DLChannel *channel = [[DLController sharedInstance] loadedChannelWithID:[message channelID]];
    NSString *channelName = [channel name] ? [NSString stringWithFormat:@"#%@", [channel name]] : @"Unknown channel";
    static NSDateFormatter *searchResultDateFormatter = nil;
    if (!searchResultDateFormatter) {
        searchResultDateFormatter = [[NSDateFormatter alloc] init];
        [searchResultDateFormatter setDateFormat:@"yyyy/MM/dd HH:mm"];
    }
    NSString *dateText = [message timestamp] ? [searchResultDateFormatter stringFromDate:[message timestamp]] : @"";
    NSString *metadata = [NSString stringWithFormat:@"%@  •  %@", channelName, dateText];
    NSDictionary *authorAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSFont boldSystemFontOfSize:11.0], NSFontAttributeName,
                                      [DLUtil nativePrimaryTextColor], NSForegroundColorAttributeName,
                                      truncate, NSParagraphStyleAttributeName, nil];
    NSDictionary *metadataAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                         [NSFont systemFontOfSize:9.0], NSFontAttributeName,
                                         [DLUtil nativeSecondaryTextColor], NSForegroundColorAttributeName,
                                         truncate, NSParagraphStyleAttributeName, nil];
    NSDictionary *contentAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                       [NSFont systemFontOfSize:10.0], NSFontAttributeName,
                                       [DLUtil nativeSecondaryTextColor], NSForegroundColorAttributeName,
                                       truncate, NSParagraphStyleAttributeName, nil];
    CGFloat topY = [controlView isFlipped] ? NSMinY(cardRect) + 6.0 : NSMaxY(cardRect) - 22.0;
    CGFloat metadataY = [controlView isFlipped] ? topY + 17.0 : topY - 17.0;
    CGFloat contentY = [controlView isFlipped] ? topY + 34.0 : topY - 34.0;
    NSRect avatarRect = NSMakeRect(NSMinX(cardRect) + 8.0,
                                   [controlView isFlipped] ? NSMinY(cardRect) + 12.0 : NSMidY(cardRect) - 16.0,
                                   32.0, 32.0);
    NSData *avatarData = [[message author] avatarImageData];
    NSImage *avatar = avatarData ? [[[NSImage alloc] initWithData:avatarData] autorelease] : nil;
    if (avatar) {
        [NSGraphicsContext saveGraphicsState];
        [[NSBezierPath bezierPathWithOvalInRect:avatarRect] addClip];
        [avatar drawInRect:avatarRect
                  fromRect:NSZeroRect
                 operation:NSCompositeSourceOver
                  fraction:1.0
            respectFlipped:YES
                     hints:nil];
        [NSGraphicsContext restoreGraphicsState];
    }
    CGFloat textX = NSMinX(cardRect) + 48.0;
    CGFloat textWidth = NSWidth(cardRect) - 57.0;
    [author drawInRect:NSMakeRect(textX, topY, textWidth, 15.0)
       withAttributes:authorAttributes];
    [metadata drawInRect:NSMakeRect(textX, metadataY, textWidth, 13.0)
          withAttributes:metadataAttributes];
    [contentText drawInRect:NSMakeRect(textX, contentY, textWidth, 14.0)
            withAttributes:contentAttributes];
}

@end

@interface DLThreadListCell : NSCell {
    DLServerChannel *representedThread;
}
-(void)setRepresentedThread:(DLServerChannel *)thread;
@end

@implementation DLThreadListCell

-(void)setRepresentedThread:(DLServerChannel *)thread {
    representedThread = thread;
}

-(void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (!representedThread) {
        return;
    }
    BOOL archived = [representedThread archivedThread];
    NSRect cardRect = NSInsetRect(cellFrame, 6.0, 4.0);
    NSColor *background = archived ? [DLUtil nativeSidebarColor] : [DLUtil nativeChromeColor];
    if ([self isHighlighted]) {
        background = [DLUtil nativeSelectionColor];
    }
    [background set];
    [[NSBezierPath bezierPathWithRoundedRect:cardRect xRadius:7.0 yRadius:7.0] fill];
    [[DLUtil nativeBorderColor] set];
    [[NSBezierPath bezierPathWithRoundedRect:cardRect xRadius:7.0 yRadius:7.0] stroke];

    DLChannel *parent = [[DLController sharedInstance] loadedChannelWithID:[representedThread parentID]];
    NSString *title = [representedThread name] ? [representedThread name] : @"Untitled";
    NSString *detail = [NSString stringWithFormat:@"%@  •  # %@",
                        archived ? @"Archived" : @"Active thread",
                        [parent name] ? [parent name] : @"Unknown channel"];
    NSColor *titleColor = archived ? [DLUtil nativeSecondaryTextColor] : [DLUtil nativePrimaryTextColor];
    NSDictionary *titleAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                     [NSFont boldSystemFontOfSize:12.0], NSFontAttributeName,
                                     titleColor, NSForegroundColorAttributeName, nil];
    NSDictionary *detailAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSFont systemFontOfSize:10.0], NSFontAttributeName,
                                      [DLUtil nativeSecondaryTextColor], NSForegroundColorAttributeName, nil];
    CGFloat top = [controlView isFlipped] ? NSMinY(cardRect) + 8.0 : NSMaxY(cardRect) - 24.0;
    NSColor *dotColor = archived ? [NSColor grayColor]
                                 : [NSColor colorWithCalibratedRed:0.20 green:0.62 blue:0.26 alpha:1.0];
    [dotColor set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMinX(cardRect) + 10.0,
                                                        [controlView isFlipped] ? top + 4.0 : top + 3.0,
                                                        8.0, 8.0)] fill];
    [title drawInRect:NSMakeRect(NSMinX(cardRect) + 25.0, top,
                                  NSWidth(cardRect) - 35.0, 17.0)
        withAttributes:titleAttributes];
    CGFloat detailY = [controlView isFlipped] ? top + 22.0 : top - 20.0;
    [detail drawInRect:NSMakeRect(NSMinX(cardRect) + 25.0, detailY,
                                   NSWidth(cardRect) - 35.0, 15.0)
         withAttributes:detailAttributes];
}

@end

@interface DLChannelOutlineView : NSOutlineView {
    NSInteger hoveredRow;
    NSInteger pendingHoveredRow;
    NSTrackingArea *hoverTrackingArea;
}
-(NSInteger)hoveredRow;
@end

@implementation DLChannelOutlineView

-(id)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        hoveredRow = -1;
        pendingHoveredRow = -1;
    }
    return self;
}

-(NSInteger)hoveredRow {
    return hoveredRow;
}

-(void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [[self window] setAcceptsMouseMovedEvents:YES];
    [self updateTrackingAreas];
}

-(void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (hoverTrackingArea) {
        [self removeTrackingArea:hoverTrackingArea];
        [hoverTrackingArea release];
        hoverTrackingArea = nil;
    }
    if ([self window]) {
        NSTrackingAreaOptions options = NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
            NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect;
        hoverTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                         options:options
                                                           owner:self
                                                        userInfo:nil];
        [self addTrackingArea:hoverTrackingArea];
    }
}

-(void)setHoveredRow:(NSInteger)row {
    if (hoveredRow == row) {
        return;
    }
    NSInteger previousRow = hoveredRow;
    hoveredRow = row;
    if (previousRow >= 0 && previousRow < [self numberOfRows]) {
        [self setNeedsDisplayInRect:[self rectOfRow:previousRow]];
    }
    if (hoveredRow >= 0 && hoveredRow < [self numberOfRows]) {
        [self setNeedsDisplayInRect:[self rectOfRow:hoveredRow]];
    }
}

-(void)mouseMoved:(NSEvent *)event {
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSInteger row = [self rowAtPoint:point];
    if (row == hoveredRow) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyPendingHoveredRow) object:nil];
        pendingHoveredRow = -1;
        return;
    }
    if (row == pendingHoveredRow) {
        return;
    }
    pendingHoveredRow = row;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyPendingHoveredRow) object:nil];
    [self performSelector:@selector(applyPendingHoveredRow) withObject:nil afterDelay:0.06];
}

-(void)applyPendingHoveredRow {
    NSInteger row = pendingHoveredRow;
    pendingHoveredRow = -1;
    [self setHoveredRow:row];
}

-(void)mouseExited:(NSEvent *)event {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyPendingHoveredRow) object:nil];
    pendingHoveredRow = -1;
    [self setHoveredRow:-1];
}

-(void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyPendingHoveredRow) object:nil];
    if (hoverTrackingArea) {
        [self removeTrackingArea:hoverTrackingArea];
        [hoverTrackingArea release];
    }
    [super dealloc];
}

@end

@interface DLChannelTableCell : NSCell {
    DLChannel *representedChannel;
}
-(void)setRepresentedChannel:(DLChannel *)channel;
@end

@implementation DLChannelTableCell

-(void)setRepresentedChannel:(DLChannel *)channel {
    representedChannel = channel;
}

-(void)drawHashIconInRect:(NSRect)rect color:(NSColor *)color {
    [color set];
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat left = NSMinX(rect) + 4.5;
    CGFloat right = NSMinX(rect) + 10.5;
    CGFloat bottom = NSMinY(rect) + 3.0;
    CGFloat top = NSMaxY(rect) - 3.0;
    [path moveToPoint:NSMakePoint(left + 1.0, bottom)];
    [path lineToPoint:NSMakePoint(left - 1.0, top)];
    [path moveToPoint:NSMakePoint(right + 1.0, bottom)];
    [path lineToPoint:NSMakePoint(right - 1.0, top)];
    [path moveToPoint:NSMakePoint(NSMinX(rect) + 2.0, NSMidY(rect) - 3.0)];
    [path lineToPoint:NSMakePoint(NSMaxX(rect) - 2.0, NSMidY(rect) - 3.0)];
    [path moveToPoint:NSMakePoint(NSMinX(rect) + 1.0, NSMidY(rect) + 3.0)];
    [path lineToPoint:NSMakePoint(NSMaxX(rect) - 3.0, NSMidY(rect) + 3.0)];
    [path setLineWidth:1.6];
    [path stroke];
}

-(void)drawVoiceIconInRect:(NSRect)rect color:(NSColor *)color {
    [color set];
    CGFloat midY = NSMidY(rect);
    NSRect speakerBody = NSMakeRect(NSMinX(rect) + 2.0, midY - 2.5, 4.0, 5.0);
    NSRectFill(speakerBody);

    NSBezierPath *cone = [NSBezierPath bezierPath];
    [cone moveToPoint:NSMakePoint(NSMaxX(speakerBody), midY - 2.5)];
    [cone lineToPoint:NSMakePoint(NSMinX(rect) + 11.0, midY - 6.0)];
    [cone lineToPoint:NSMakePoint(NSMinX(rect) + 11.0, midY + 6.0)];
    [cone lineToPoint:NSMakePoint(NSMaxX(speakerBody), midY + 2.5)];
    [cone closePath];
    [cone fill];

    NSBezierPath *wave = [NSBezierPath bezierPath];
    [wave moveToPoint:NSMakePoint(NSMinX(rect) + 13.0, midY - 4.0)];
    [wave curveToPoint:NSMakePoint(NSMinX(rect) + 13.0, midY + 4.0)
          controlPoint1:NSMakePoint(NSMinX(rect) + 16.0, midY - 2.0)
          controlPoint2:NSMakePoint(NSMinX(rect) + 16.0, midY + 2.0)];
    [wave setLineWidth:1.4];
    [wave stroke];
}

-(void)drawThreadIconInRect:(NSRect)rect color:(NSColor *)color {
    [color set];
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat left = NSMinX(rect) + 4.0;
    CGFloat right = NSMaxX(rect) - 3.0;
    CGFloat lower = NSMinY(rect) + 5.0;
    CGFloat upper = NSMaxY(rect) - 5.0;
    [path moveToPoint:NSMakePoint(left, upper)];
    [path lineToPoint:NSMakePoint(right, upper)];
    [path lineToPoint:NSMakePoint(right, NSMidY(rect))];
    [path moveToPoint:NSMakePoint(left, lower)];
    [path lineToPoint:NSMakePoint(right - 4.0, lower)];
    [path lineToPoint:NSMakePoint(right - 4.0, NSMidY(rect))];
    [path setLineWidth:1.8];
    [path setLineCapStyle:NSRoundLineCapStyle];
    [path setLineJoinStyle:NSRoundLineJoinStyle];
    [path stroke];
}

-(void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (!representedChannel) {
        return;
    }

    BOOL isCategory = ([representedChannel type] == ChannelTypeHeader);
    NSInteger row = [(NSOutlineView *)controlView rowAtPoint:NSMakePoint(NSMidX(cellFrame), NSMidY(cellFrame))];
    BOOL selected = (row >= 0 && [[(NSOutlineView *)controlView selectedRowIndexes] containsIndex:(NSUInteger)row]);
    BOOL hovered = ([controlView isKindOfClass:[DLChannelOutlineView class]] &&
                    row == [(DLChannelOutlineView *)controlView hoveredRow]);
    NSRect contentRect = cellFrame;

    if (!isCategory && selected) {
        NSRect selectionRect = NSInsetRect(cellFrame, 2.0, 2.0);
        [[DLUtil nativeSelectionColor] set];
        [[NSBezierPath bezierPathWithRoundedRect:selectionRect xRadius:5.0 yRadius:5.0] fill];
    } else if (!isCategory && hovered) {
        NSRect hoverRect = NSInsetRect(cellFrame, 2.0, 2.0);
        [[[DLUtil nativeSelectionColor] colorWithAlphaComponent:0.55] set];
        [[NSBezierPath bezierPathWithRoundedRect:hoverRect xRadius:5.0 yRadius:5.0] fill];
    }

    NSString *name = [representedChannel name] ? [representedChannel name] : @"Untitled";
    NSFont *font = isCategory ? [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]]
                              : ([representedChannel hasUnreadMessages]
                                 ? [NSFont boldSystemFontOfSize:[NSFont systemFontSize]]
                                 : [NSFont systemFontOfSize:[NSFont systemFontSize]]);
    BOOL emphasized = selected || hovered || [representedChannel hasUnreadMessages];
    NSColor *textColor = isCategory ? [DLUtil nativeSecondaryTextColor]
                                    : (emphasized ? [DLUtil nativePrimaryTextColor]
                                                  : [DLUtil nativeSecondaryTextColor]);
    NSMutableParagraphStyle *paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [paragraphStyle setLineBreakMode:NSLineBreakByTruncatingTail];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                font, NSFontAttributeName,
                                textColor, NSForegroundColorAttributeName,
                                paragraphStyle, NSParagraphStyleAttributeName,
                                nil];

    if (isCategory) {
        NSString *categoryName = [name uppercaseString];
        NSSize textSize = [categoryName sizeWithAttributes:attributes];
        NSRect textRect = NSMakeRect(NSMinX(contentRect) + 3.0,
                                     NSMidY(contentRect) - textSize.height / 2.0,
                                     NSWidth(contentRect) - 8.0,
                                     textSize.height);
        [categoryName drawInRect:textRect withAttributes:attributes];
        return;
    }

    if ([representedChannel hasUnreadMessages] && !selected) {
        [[DLUtil nativePrimaryTextColor] set];
        NSRect unreadRect = NSMakeRect(NSMinX(contentRect), NSMidY(contentRect) - 4.0, 3.0, 8.0);
        [[NSBezierPath bezierPathWithRoundedRect:unreadRect xRadius:1.5 yRadius:1.5] fill];
    }

    NSColor *iconColor = emphasized ? [DLUtil nativePrimaryTextColor]
                                    : [DLUtil nativeSecondaryTextColor];
    BOOL isDirectMessage = ([representedChannel type] == ChannelTypeDM ||
                            [representedChannel type] == ChannelTypeGroup);
    NSRect iconRect = isDirectMessage
        ? NSMakeRect(NSMinX(contentRect) + 7.0, NSMidY(contentRect) - 16.0, 32.0, 32.0)
        : NSMakeRect(NSMinX(contentRect) + 7.0, NSMidY(contentRect) - 9.0, 18.0, 18.0);
    if (isDirectMessage) {
        NSImage *avatar = [[[NSImage alloc] initWithData:[representedChannel imageData]] autorelease];
        if (avatar) {
            [NSGraphicsContext saveGraphicsState];
            [[NSBezierPath bezierPathWithOvalInRect:iconRect] addClip];
            [avatar drawInRect:iconRect fromRect:NSZeroRect operation:NSCompositeSourceOver
                      fraction:1.0 respectFlipped:YES hints:nil];
            [NSGraphicsContext restoreGraphicsState];
        }
    } else if ([representedChannel type] == ChannelTypeVoice || [representedChannel type] == ChannelTypeStageVoice) {
        [self drawVoiceIconInRect:iconRect color:iconColor];
    } else if ([representedChannel isThread]) {
        [self drawThreadIconInRect:iconRect color:iconColor];
    } else {
        [self drawHashIconInRect:iconRect color:iconColor];
    }

    CGFloat rightInset = 8.0;
    NSInteger mentionCount = [representedChannel mentionCount];
    if (mentionCount > 0) {
        NSString *badgeText = mentionCount > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)mentionCount];
        NSDictionary *badgeAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                         [NSFont boldSystemFontOfSize:9.0], NSFontAttributeName,
                                         [NSColor whiteColor], NSForegroundColorAttributeName,
                                         nil];
        NSSize badgeTextSize = [badgeText sizeWithAttributes:badgeAttributes];
        CGFloat badgeWidth = MAX(18.0, badgeTextSize.width + 8.0);
        NSRect badgeRect = NSMakeRect(NSMaxX(contentRect) - badgeWidth - 5.0,
                                     NSMidY(contentRect) - 8.0,
                                     badgeWidth,
                                     16.0);
        [[NSColor colorWithCalibratedRed:0.80 green:0.10 blue:0.12 alpha:1.0] set];
        [[NSBezierPath bezierPathWithRoundedRect:badgeRect xRadius:8.0 yRadius:8.0] fill];
        [badgeText drawAtPoint:NSMakePoint(NSMidX(badgeRect) - badgeTextSize.width / 2.0,
                                          NSMidY(badgeRect) - badgeTextSize.height / 2.0)
                   withAttributes:badgeAttributes];
        rightInset += badgeWidth + 4.0;
    }

    NSSize textSize = [name sizeWithAttributes:attributes];
    CGFloat textOriginX = isDirectMessage ? NSMinX(contentRect) + 47.0 : NSMinX(contentRect) + 30.0;
    NSRect textRect = NSMakeRect(textOriginX,
                                 NSMidY(contentRect) - textSize.height / 2.0,
                                 MAX(0.0, NSMaxX(contentRect) - textOriginX - rightInset),
                                 textSize.height);
    [name drawInRect:textRect withAttributes:attributes];
}

@end

@interface DLMainWindowController ()
-(void)installResizableMainSplitView;
-(void)moveView:(NSView *)view toPane:(NSView *)pane frame:(NSRect)frame autoresizingMask:(NSUInteger)mask;
-(void)installNativeToolbar;
-(void)installSearchResultsPane;
-(void)installThreadBrowser;
-(void)installMemberListPane;
-(void)installFriendsHome;
-(void)installMessageStateBanners;
-(BOOL)isViewingLatestMessages;
-(void)refreshMessageBannerVisibility;
-(void)resetUnreadMessageState;
-(void)recordUnreadMessage:(DLMessage *)message;
-(IBAction)jumpToLatestMessages:(id)sender;
-(IBAction)markLatestMessagesRead:(id)sender;
-(void)mainWindowDidBecomeKey:(NSNotification *)notification;
-(IBAction)toggleMemberList:(id)sender;
-(void)setMemberListVisible:(BOOL)visible;
-(void)refreshMemberList;
-(void)memberListBoundsDidChange:(NSNotification *)notification;
-(void)requestNextMemberPageIfNeeded;
-(void)showProfileForUser:(DLUser *)user relativeToRect:(NSRect)rect ofView:(NSView *)view;
-(void)showExpandedProfile:(id)sender;
-(NSString *)profileAvatarCacheKeyForUser:(DLUser *)user size:(CGFloat)size;
-(NSImage *)cachedProfileAvatarForUser:(DLUser *)user size:(CGFloat)size;
-(void)requestProfileAvatarForUser:(DLUser *)user size:(CGFloat)size radius:(CGFloat)radius;
-(void)loadProfileAvatarInBackground:(NSDictionary *)context;
-(void)profileAvatarDidFinishLoading:(NSDictionary *)result;
-(NSString *)profileDataCacheKeyForUser:(DLUser *)user server:(DLServer *)server;
-(void)requestProfileDataForUser:(DLUser *)user server:(DLServer *)server;
-(void)updateVisibleProfileData;
-(void)profileBannerCacheDidUpdate:(NSNotification *)notification;
-(void)applyCachedProfileBanner;
-(void)loadProfileBannerInBackground:(NSDictionary *)context;
-(void)profileBannerDidFinishLoading:(NSDictionary *)result;
-(NSColor *)profileAccentColorFromData:(NSDictionary *)profile;
-(NSString *)profileJoinedDateFromData:(NSDictionary *)profile;
-(NSString *)profileConnectionsTextFromData:(NSDictionary *)profile;
-(NSString *)profileActivitiesTextFromData:(NSDictionary *)profile;
-(NSString *)profileCustomStatusFromData:(NSDictionary *)profile;
-(void)reloadRoleChipsInView:(NSView *)container roleIDs:(NSArray *)roleIDs maxWidth:(CGFloat)maxWidth;
-(IBAction)showMyProfile:(id)sender;
-(NSTextField *)profileLabelWithFrame:(NSRect)frame text:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
-(IBAction)showThreadList:(id)sender;
-(IBAction)closeThreadList:(id)sender;
-(IBAction)closeThreadDetail:(id)sender;
-(void)openThreadDetail:(DLChannel *)thread;
-(void)hideThreadBrowser;
-(void)setSearchResultsPaneVisible:(BOOL)visible;
-(void)updateSearchResultsForQuery:(NSString *)query;
-(void)jumpToSearchResultAtRow:(NSInteger)row;
-(void)animatedScrollToChatView:(ChatItemViewController *)item;
-(void)reloadSearchResultsTable;
-(void)loadVisibleSearchResultAvatars;
-(void)performMessageSearchAtOffset:(NSInteger)offset;
-(IBAction)showPreviousSearchPage:(id)sender;
-(IBAction)showNextSearchPage:(id)sender;
-(DLUser *)searchUserMatchingName:(NSString *)name inMembers:(NSArray *)members;
-(void)showNoSearchUserNamed:(NSString *)name;
-(IBAction)closeMessageSearchResults:(id)sender;
-(IBAction)togglePinnedMessages:(id)sender;
-(void)updateConnectionStatusField;
-(void)clearMessageSearchHighlight;
-(void)installNativeServerTableView;
-(void)displayServerItems:(NSArray *)items;
-(void)selectServer:(DLServer *)server;
-(void)loadChannelsForServer:(DLServer *)server;
-(void)refreshThreadOutlineForServer:(DLServer *)server;
-(void)scheduleThreadOutlineRefreshForServer:(DLServer *)server;
-(void)refreshArchivedThreadListForContext:(NSDictionary *)context;
-(void)installNativeChannelOutlineView;
-(void)displayChannelOutlineItems:(NSArray *)items;
-(void)selectChannel:(DLChannel *)channel;
-(void)scheduleEmojiPickerReload:(id)sender;
-(void)messageDisplayScaleDidChange:(NSNotification *)notification;
-(void)appearanceThemeDidChange:(NSNotification *)notification;
-(void)applyCurrentTheme;
-(void)showFriendsHomeWithChannels:(NSArray *)channels;
-(void)refreshFriendsHomeAvatars;
-(void)hideFriendsHome;
-(IBAction)openFriendDirectMessage:(id)sender;
-(void)updateResponsiveDMLayout;
-(void)openUserSettings:(id)sender;
-(NSArray *)standardEmojiPickerItems;
@end

@implementation DLMainWindowController

const NSTimeInterval TYPING_SEND_INTERVAL = 8.0;
const CGFloat MY_USER_AVATAR_RADIUS = 18.0f;
- (void)windowDidLoad {
    [super windowDidLoad];

    [self.window setTitle:@"Legacy Discord"];
    [self.window setBackgroundColor:[DLUtil nativeContentColor]];
    [self installNativeToolbar];
    [self installResizableMainSplitView];
    [self installMessageStateBanners];
    [self installSearchResultsPane];
    [self installThreadBrowser];
    [self installMemberListPane];
    [self installFriendsHome];

    [serversScrollView setDrawsBackground:YES];
    [serversScrollView setBackgroundColor:[DLUtil nativeServerRailColor]];
    [serversScrollView setFocusRingType:NSFocusRingTypeNone];
    [[serversScrollView contentView] setBackgroundColor:[DLUtil nativeServerRailColor]];
    [self installNativeServerTableView];
    [channelsScrollView setDrawsBackground:YES];
    [channelsScrollView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [channelsScrollView setFocusRingType:NSFocusRingTypeNone];
    [[channelsScrollView contentView] setBackgroundColor:[DLUtil nativeSidebarColor]];
    [self installNativeChannelOutlineView];
    [chatScrollView setDrawsBackground:YES];
    [chatScrollView setBackgroundColor:[DLUtil nativeContentColor]];
    [[chatScrollView contentView] setBackgroundColor:[DLUtil nativeContentColor]];

    [channelViewHeader setGradientStartColor:[DLUtil nativeHeaderTopColor]
                                    endColor:[DLUtil nativeHeaderBottomColor]];
    [channelViewHeader setBottomBorderColor:[DLUtil nativeBorderColor]];
    [chatViewHeader setGradientStartColor:[DLUtil nativeHeaderTopColor]
                                 endColor:[DLUtil nativeHeaderBottomColor]];
    [chatViewHeader setBottomBorderColor:[DLUtil nativeBorderColor]];
    [serverLabel setTextColor:[DLUtil nativePrimaryTextColor]];
    [chatHeaderLabel setTextColor:[DLUtil nativePrimaryTextColor]];
    [serverLabel setFont:[NSFont boldSystemFontOfSize:13.0]];
    [chatHeaderLabel setFont:[NSFont boldSystemFontOfSize:14.0]];

    [userInfoView setBackgroundColor:[DLUtil nativeChromeColor]];
    [userInfoView setBottomBorderColor:[DLUtil nativeBorderColor]];
    [myUsernameTextField setTextColor:[DLUtil nativePrimaryTextColor]];
    [myDiscTextField setTextColor:[DLUtil nativeSecondaryTextColor]];

    [messageEntryContainerView setBackgroundColor:[DLUtil nativeChromeColor]];
    [messageEntryTextView setBackgroundColor:[NSColor clearColor]];
    [messageEntryTextView setDrawsBackground:NO];
    [messageEntryTextView setTextColor:[DLUtil nativePrimaryTextColor]];
    [messageEntryTextView setInsertionPointColor:[DLUtil nativePrimaryTextColor]];
    [messageEntryScrollView setBorderType:NSNoBorder];
    [messageEntryScrollView setDrawsBackground:NO];
    [messageEntryScrollView setBackgroundColor:[NSColor clearColor]];
    [[messageEntryScrollView contentView] setDrawsBackground:NO];
    NSRect entryFrame = [messageEntryScrollView frame];
    entryFrame.origin.x += 6.0;
    entryFrame.size.width -= 62.0;
    [messageEntryScrollView setFrame:entryFrame];
    NSRect composerFrame = NSMakeRect(MAX(4.0, NSMinX(entryFrame) - 10.0),
                                      MAX(4.0, NSMinY(entryFrame) - 8.0),
                                      NSWidth([messageEntryContainerView bounds]) - MAX(4.0, NSMinX(entryFrame) - 10.0) - 7.0,
                                      NSHeight(entryFrame) + 16.0);
    messageComposerBackgroundView = [[DLMessageComposerBackgroundView alloc] initWithFrame:composerFrame];
    [messageComposerBackgroundView setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [messageEntryContainerView addSubview:messageComposerBackgroundView positioned:NSWindowBelow relativeTo:messageEntryScrollView];
    stickerButton = [[DLStickerButton alloc] initWithFrame:NSMakeRect(NSWidth([messageEntryContainerView bounds]) - 63, 15, 28, 26)];
    [stickerButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
    [stickerButton setBordered:NO];
    [stickerButton setButtonType:NSMomentaryPushInButton];
    [stickerButton setTitle:@""];
    [stickerButton setToolTip:@"Send sticker"];
    [stickerButton setTarget:self];
    [stickerButton setAction:@selector(showStickerMenu:)];
    [stickerButton setEnabled:NO];
    [messageEntryContainerView addSubview:stickerButton];
    emojiButton = [[DLEmojiButton alloc] initWithFrame:NSMakeRect(NSWidth([messageEntryContainerView bounds]) - 35, 15, 28, 26)];
    [emojiButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
    [emojiButton setBordered:NO];
    [emojiButton setButtonType:NSMomentaryPushInButton];
    [emojiButton setTitle:@""];
    [emojiButton setToolTip:@"Insert emoji"];
    [emojiButton setTarget:self];
    [emojiButton setAction:@selector(showEmojiMenu:)];
    [emojiButton setEnabled:NO];
    [messageEntryContainerView addSubview:emojiButton];
    [typingStatusTextField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [replyToTextField setTextColor:[DLUtil nativePrimaryTextColor]];
    
    [messageEntryTextView setSelectedTextAttributes:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[DLUtil nativeSelectedTextColor], [DLTextParser DEFAULT_TEXT_HIGHLIGHT_COLOR], nil] forKeys:[NSArray arrayWithObjects:NSForegroundColorAttributeName, NSBackgroundColorAttributeName, nil]]];
    
    [serverViewScroller setBackgroundColor:[serversScrollView backgroundColor]];
    [serverViewScroller setNeedsDisplay:YES];
    
    [channelViewScroller setBackgroundColor:[channelsScrollView backgroundColor]];
    [channelViewScroller setNeedsDisplay:YES];
    
    [chatViewScroller setBackgroundColor:[chatScrollView backgroundColor]];
    [chatViewScroller setNeedsDisplay:YES];
    
    [messageEntryViewScroller setBackgroundColor:[messageEntryTextView backgroundColor]];
    [messageEntryViewScroller setNeedsDisplay:YES];
    
    [tagSelectionViewScroller setBackgroundColor:[tagSelectionScrollView backgroundColor]];
    [tagSelectionViewScroller setNeedsDisplay:YES];
    
    [pendingAttachmentViewScroller setBackgroundColor:[pendingAttachmentsScrollView backgroundColor]];
    [pendingAttachmentViewScroller setNeedsDisplay:YES];
    
    lastMessage = nil;
    firstMessage = nil;
    editingLocation = NSNotFound;
    tagIndex = NSNotFound;
    messageEditor = [[DLMessageEditor alloc] init];
    [messageEditor setDelegate:self];
    isLoadingMessages = NO;
    isLoadingNewerMessages = NO;
    searchHistoryWindowActive = NO;
    hasMoreNewerMessages = NO;
    isLoadingViews = NO;
    isTyping = NO;
    madeMentionChange = NO;
    profileAvatarCache = [[NSCache alloc] init];
    [profileAvatarCache setCountLimit:80];
    profileAvatarRequests = [[NSMutableSet alloc] init];
    profileBannerImageCache = [[NSCache alloc] init];
    [profileBannerImageCache setCountLimit:20];
    profileBannerImageRequests = [[NSMutableSet alloc] init];
    profileDataCache = [[NSMutableDictionary alloc] init];
    profileDataRequests = [[NSMutableSet alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileBannerCacheDidUpdate:)
                                                 name:HTTPCacheDataDidUpdateNotification object:nil];
    [[DLController sharedInstance] setDelegate:self];
    [chatScrollView.contentView setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chatScrollViewBoundsDidChange:) name:NSViewBoundsDidChangeNotification object:chatScrollView.contentView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messageDisplayScaleDidChange:) name:DLMessageDisplayScaleDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appearanceThemeDidChange:) name:DLAppearanceThemeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mainWindowDidBecomeKey:) name:NSWindowDidBecomeKeyNotification object:self.window];
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    [myUserAvatarImage setImage:[DLUtil imageResize:[[[NSImage alloc] initWithContentsOfFile:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"discord_placeholder.png"]] autorelease] newSize:myUserAvatarImage.frame.size cornerRadius:MY_USER_AVATAR_RADIUS]];
    myProfileButton = [[NSButton alloc] initWithFrame:[myUserAvatarImage frame]];
    [myProfileButton setBordered:NO];
    [myProfileButton setRefusesFirstResponder:YES];
    [myProfileButton setTitle:@""];
    [myProfileButton setToolTip:@"View your profile"];
    [myProfileButton setTarget:self];
    [myProfileButton setAction:@selector(showMyProfile:)];
    [userInfoView addSubview:myProfileButton];
    [messageEntryTextView setDelegate:self];
    [chatScrollView setDelegate:self];
    currentMessageScrollHeight = messageEntryScrollView.frame.size.height;
    typingUsers = [[NSMutableArray alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTextViewSizing) name:NSWindowDidResizeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mainWindowDidResize:) name:NSWindowDidResizeNotification object:self.window];
}

-(void)moveView:(NSView *)view toPane:(NSView *)pane frame:(NSRect)frame autoresizingMask:(NSUInteger)mask {
    [view retain];
    [view removeFromSuperview];
    [view setFrame:frame];
    [view setAutoresizingMask:mask];
    [pane addSubview:view];
    [view release];
}

-(void)installResizableMainSplitView {
    NSView *contentView = [self.window contentView];
    NSRect contentBounds = [contentView bounds];
    CGFloat serverRailWidth = NSWidth([serversScrollView frame]);
    CGFloat paneHeight = NSHeight(contentBounds);
    CGFloat splitWidth = NSWidth(contentBounds) - serverRailWidth;
    CGFloat initialChannelWidth = NSWidth([channelsScrollView frame]);
    CGFloat dividerWidth = 1.0;

    mainSplitView = [[DLDarkSplitView alloc] initWithFrame:NSMakeRect(serverRailWidth, 0.0, splitWidth, paneHeight)];
    [mainSplitView setVertical:YES];
    [mainSplitView setDividerStyle:NSSplitViewDividerStyleThin];
    [mainSplitView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [mainSplitView setDelegate:self];

    channelPaneView = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, initialChannelWidth, paneHeight)];
    chatPaneView = [[NSView alloc] initWithFrame:NSMakeRect(initialChannelWidth + dividerWidth,
                                                            0.0,
                                                            splitWidth - initialChannelWidth - dividerWidth,
                                                            paneHeight)];
    [mainSplitView addSubview:channelPaneView];
    [mainSplitView addSubview:chatPaneView];
    [mainSplitView setHoldingPriority:251.0 forSubviewAtIndex:0];
    [mainSplitView setHoldingPriority:250.0 forSubviewAtIndex:1];
    [contentView addSubview:mainSplitView];

    [self moveView:channelViewHeader
             toPane:channelPaneView
              frame:NSMakeRect(0.0, paneHeight - 42.0, initialChannelWidth, 42.0)
   autoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [self moveView:channelsScrollView
             toPane:channelPaneView
              frame:NSMakeRect(0.0, 56.0, initialChannelWidth, paneHeight - 98.0)
   autoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [self moveView:userInfoView
             toPane:channelPaneView
              frame:NSMakeRect(0.0, 0.0, initialChannelWidth, 56.0)
   autoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];

    CGFloat initialChatWidth = NSWidth([chatPaneView bounds]);
    [self moveView:chatViewHeader
             toPane:chatPaneView
              frame:NSMakeRect(0.0, paneHeight - 42.0, initialChatWidth, 42.0)
   autoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [self moveView:chatScrollView
             toPane:chatPaneView
              frame:NSMakeRect(0.0, 56.0, initialChatWidth, paneHeight - 98.0)
   autoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [self moveView:messageEntryContainerView
             toPane:chatPaneView
              frame:NSMakeRect(0.0, 0.0, initialChatWidth, 56.0)
   autoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];

    [serverLabel setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [myUsernameTextField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [myDiscTextField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];

    NSEnumerator *userInfoSubviews = [[userInfoView subviews] objectEnumerator];
    NSView *subview;
    while (subview = [userInfoSubviews nextObject]) {
        if ([subview isKindOfClass:[NSButton class]] && [(NSButton *)subview action] == @selector(showSettingsMenu:)) {
            [subview setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
        }
    }

    NSString *autosaveName = @"LegacyDiscordMainSplit";
    NSString *autosaveKey = [NSString stringWithFormat:@"NSSplitView Subview Frames %@", autosaveName];
    BOOL hasSavedPosition = ([[NSUserDefaults standardUserDefaults] objectForKey:autosaveKey] != nil);
    [mainSplitView setAutosaveName:autosaveName];
    if (!hasSavedPosition) {
        [mainSplitView setPosition:initialChannelWidth ofDividerAtIndex:0];
    }
}

-(void)installFriendsHome {
    NSRect bounds = [chatPaneView bounds];
    friendsHomeView = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0, 0.0, NSWidth(bounds), NSHeight(bounds) - 42.0)];
    [friendsHomeView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [friendsHomeView setBackgroundColor:[DLUtil nativeContentColor]];

    NSTextField *title = [[[NSTextField alloc] initWithFrame:NSMakeRect(24.0, NSHeight([friendsHomeView bounds]) - 43.0, 300.0, 25.0)] autorelease];
    [title setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
    [title setBezeled:NO];
    [title setDrawsBackground:NO];
    [title setEditable:NO];
    [title setSelectable:NO];
    [title setFont:[NSFont boldSystemFontOfSize:18.0]];
    [title setTextColor:[DLUtil nativePrimaryTextColor]];
    [title setStringValue:@"Friends"];
    [friendsHomeView addSubview:title];

    NSTextField *subtitle = [[[NSTextField alloc] initWithFrame:NSMakeRect(25.0, NSHeight([friendsHomeView bounds]) - 65.0, 420.0, 18.0)] autorelease];
    [subtitle setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
    [subtitle setBezeled:NO];
    [subtitle setDrawsBackground:NO];
    [subtitle setEditable:NO];
    [subtitle setSelectable:NO];
    [subtitle setFont:[NSFont systemFontOfSize:11.0]];
    [subtitle setTextColor:[DLUtil nativeSecondaryTextColor]];
    [subtitle setStringValue:@"Recent conversations"];
    [friendsHomeView addSubview:subtitle];

    friendsHomeScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(16.0, 16.0, NSWidth(bounds) - 32.0, NSHeight(bounds) - 92.0)];
    [friendsHomeScrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [friendsHomeScrollView setBorderType:NSNoBorder];
    [friendsHomeScrollView setHasVerticalScroller:YES];
    [friendsHomeScrollView setDrawsBackground:YES];
    [friendsHomeScrollView setBackgroundColor:[DLUtil nativeContentColor]];
    [friendsHomeView addSubview:friendsHomeScrollView];
    [chatPaneView addSubview:friendsHomeView];
    [friendsHomeView setHidden:YES];
}

-(void)showFriendsHomeWithChannels:(NSArray *)channels {
    NSArray *newChannels = [channels retain];
    [friendsHomeChannels release];
    friendsHomeChannels = newChannels;
    NSRect visibleBounds = [[friendsHomeScrollView contentView] bounds];
    CGFloat rowHeight = 58.0;
    CGFloat documentHeight = MAX(NSHeight(visibleBounds), [channels count] * rowHeight + 8.0);
    NSView_BGColor *document = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0, 0.0, NSWidth(visibleBounds), documentHeight)] autorelease];
    [document setAutoresizingMask:NSViewWidthSizable];
    [document setBackgroundColor:[DLUtil nativeContentColor]];
    NSInteger row = 0;
    for (DLDirectMessageChannel *channel in channels) {
        CGFloat y = documentHeight - (row + 1) * rowHeight;
        NSButton *rowButton = [[[NSButton alloc] initWithFrame:NSMakeRect(0.0, y, NSWidth(visibleBounds), rowHeight - 2.0)] autorelease];
        [rowButton setAutoresizingMask:NSViewWidthSizable];
        [rowButton setBordered:NO];
        [rowButton setTitle:@""];
        [rowButton setTag:row];
        [rowButton setTarget:self];
        [rowButton setAction:@selector(openFriendDirectMessage:)];
        [rowButton setToolTip:[NSString stringWithFormat:@"Open %@", [channel name]]];
        [document addSubview:rowButton];

        NSImageView *avatar = [[[NSImageView alloc] initWithFrame:NSMakeRect(12.0, y + 9.0, 38.0, 38.0)] autorelease];
        NSImage *avatarImage = [[[NSImage alloc] initWithData:[channel imageData]] autorelease];
        if (avatarImage) [avatar setImage:[DLUtil imageResize:avatarImage newSize:NSMakeSize(38.0, 38.0) cornerRadius:19.0]];
        [document addSubview:avatar];

        NSTextField *name = [[[NSTextField alloc] initWithFrame:NSMakeRect(62.0, y + 20.0, MAX(100.0, NSWidth(visibleBounds) - 120.0), 20.0)] autorelease];
        [name setAutoresizingMask:NSViewWidthSizable];
        [name setBezeled:NO];
        [name setDrawsBackground:NO];
        [name setEditable:NO];
        [name setSelectable:NO];
        [name setFont:[NSFont boldSystemFontOfSize:13.0]];
        [name setTextColor:[DLUtil nativePrimaryTextColor]];
        [name setStringValue:[channel name] ? [channel name] : @"Direct Message"];
        [document addSubview:name];

        NSBox *separator = [[[NSBox alloc] initWithFrame:NSMakeRect(62.0, y, MAX(0.0, NSWidth(visibleBounds) - 74.0), 1.0)] autorelease];
        [separator setAutoresizingMask:NSViewWidthSizable];
        [separator setBoxType:NSBoxSeparator];
        [document addSubview:separator];
        row++;
    }
    if ([channels count] == 0) {
        NSTextField *empty = [[[NSTextField alloc] initWithFrame:NSMakeRect(20.0, NSMidY([document bounds]) - 20.0, NSWidth(visibleBounds) - 40.0, 40.0)] autorelease];
        [empty setBezeled:NO]; [empty setDrawsBackground:NO]; [empty setEditable:NO];
        [empty setAlignment:NSCenterTextAlignment]; [empty setTextColor:[DLUtil nativeSecondaryTextColor]];
        [empty setStringValue:@"No recent direct messages"];
        [document addSubview:empty];
    }
    [friendsHomeScrollView setDocumentView:document];
    [chatHeaderLabel setStringValue:@"Friends"];
    [chatHeaderImage setImage:nil];
    [chatScrollView setHidden:YES];
    [messageEntryContainerView setHidden:YES];
    [friendsHomeView setHidden:NO];
    [self updateResponsiveDMLayout];
}

-(void)hideFriendsHome {
    [friendsHomeView setHidden:YES];
    [chatScrollView setHidden:NO];
    [messageEntryContainerView setHidden:NO];
}

-(void)refreshFriendsHomeAvatars {
    if (![friendsHomeView isHidden] && friendsHomeChannels) {
        [self showFriendsHomeWithChannels:friendsHomeChannels];
    }
}

-(IBAction)openFriendDirectMessage:(id)sender {
    NSInteger row = [(NSButton *)sender tag];
    if (row >= 0 && row < (NSInteger)[friendsHomeChannels count]) {
        DLChannel *channel = [friendsHomeChannels objectAtIndex:row];
        NSInteger outlineRow = [channelOutlineView rowForItem:channel];
        if (outlineRow >= 0) {
            updatingChannelOutlineSelection = YES;
            [channelOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:outlineRow] byExtendingSelection:NO];
            updatingChannelOutlineSelection = NO;
        }
        [self selectChannel:channel];
    }
}

-(void)mainWindowDidResize:(NSNotification *)notification {
    [self updateResponsiveDMLayout];
}

-(void)updateResponsiveDMLayout {
    BOOL showingDM = [[[DLController sharedInstance] selectedServer] isEqual:[[DLController sharedInstance] myServerItem]];
    if (!showingDM || !mainSplitView) return;
    CGFloat width = NSWidth([[self.window contentView] bounds]);
    if (!compactDMLayout && width < 680.0) {
        expandedChannelPaneWidth = NSWidth([channelPaneView frame]);
        compactDMLayout = YES;
        [mainSplitView setPosition:0.0 ofDividerAtIndex:0];
    } else if (compactDMLayout && width > 740.0) {
        compactDMLayout = NO;
        CGFloat restoredWidth = expandedChannelPaneWidth >= 180.0 ? expandedChannelPaneWidth : 220.0;
        [mainSplitView setPosition:MIN(restoredWidth, 300.0) ofDividerAtIndex:0];
    }
}

-(void)installMessageStateBanners {
    NSRect bounds = [chatScrollView bounds];
    unreadMessageBanner = [[NSView_BGColor alloc] initWithFrame:
                           NSMakeRect(0.0, 0.0, NSWidth(bounds), 28.0)];
    [unreadMessageBanner setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [unreadMessageBanner setBackgroundColor:[NSColor colorWithCalibratedRed:0.345 green:0.396 blue:0.949 alpha:0.98]];
    [unreadMessageBanner setBottomBorderColor:[DLUtil nativeBorderColor]];

    unreadMessageBannerLabel = [[NSTextField alloc] initWithFrame:
                                NSMakeRect(10.0, 5.0, MAX(80.0, NSWidth(bounds) - 112.0), 18.0)];
    [unreadMessageBannerLabel setAutoresizingMask:NSViewWidthSizable];
    [unreadMessageBannerLabel setBezeled:NO];
    [unreadMessageBannerLabel setDrawsBackground:NO];
    [unreadMessageBannerLabel setEditable:NO];
    [unreadMessageBannerLabel setSelectable:NO];
    [unreadMessageBannerLabel setFont:[NSFont boldSystemFontOfSize:10.0]];
    [unreadMessageBannerLabel setTextColor:[NSColor whiteColor]];
    [unreadMessageBanner addSubview:unreadMessageBannerLabel];

    markMessagesReadButton = [[NSButton alloc] initWithFrame:
                              NSMakeRect(MAX(0.0, NSWidth(bounds) - 98.0), 3.0, 92.0, 22.0)];
    [markMessagesReadButton setAutoresizingMask:NSViewMinXMargin];
    [markMessagesReadButton setBezelStyle:NSRoundedBezelStyle];
    [markMessagesReadButton setFont:[NSFont boldSystemFontOfSize:10.0]];
    [markMessagesReadButton setTitle:@"既読にする"];
    [markMessagesReadButton setTarget:self];
    [markMessagesReadButton setAction:@selector(markLatestMessagesRead:)];
    [unreadMessageBanner addSubview:markMessagesReadButton];
    [chatScrollView addSubview:unreadMessageBanner positioned:NSWindowAbove relativeTo:nil];

    CGFloat historyWidth = MIN(310.0, MAX(210.0, NSWidth(bounds) - 24.0));
    historyMessageBanner = [[NSView_BGColor alloc] initWithFrame:
                            NSMakeRect(floor((NSWidth(bounds) - historyWidth) / 2.0),
                                       MAX(0.0, NSHeight(bounds) - 37.0),
                                       historyWidth, 30.0)];
    [historyMessageBanner setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin];
    [historyMessageBanner setBackgroundColor:[NSColor colorWithCalibratedWhite:0.17 alpha:0.94]];
    historyMessageBannerLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10.0, 6.0, 132.0, 18.0)];
    [historyMessageBannerLabel setBezeled:NO];
    [historyMessageBannerLabel setDrawsBackground:NO];
    [historyMessageBannerLabel setEditable:NO];
    [historyMessageBannerLabel setSelectable:NO];
    [historyMessageBannerLabel setFont:[NSFont systemFontOfSize:10.0]];
    [historyMessageBannerLabel setTextColor:[NSColor whiteColor]];
    [historyMessageBannerLabel setStringValue:@"古いメッセージを表示中"];
    [historyMessageBanner addSubview:historyMessageBannerLabel];

    jumpToLatestButton = [[NSButton alloc] initWithFrame:NSMakeRect(historyWidth - 151.0, 4.0, 143.0, 22.0)];
    [jumpToLatestButton setAutoresizingMask:NSViewMinXMargin];
    [jumpToLatestButton setBezelStyle:NSRoundedBezelStyle];
    [jumpToLatestButton setFont:[NSFont boldSystemFontOfSize:10.0]];
    [jumpToLatestButton setTitle:@"最新メッセージへ"];
    [jumpToLatestButton setTarget:self];
    [jumpToLatestButton setAction:@selector(jumpToLatestMessages:)];
    [historyMessageBanner addSubview:jumpToLatestButton];
    [chatScrollView addSubview:historyMessageBanner positioned:NSWindowAbove relativeTo:nil];

    [unreadMessageBanner setHidden:YES];
    [historyMessageBanner setHidden:YES];
}

-(BOOL)isViewingLatestMessages {
    return NSMinY([[chatScrollView contentView] bounds]) <= 8.0;
}

-(void)refreshMessageBannerVisibility {
    BOOL hasPending = pendingNewMessageCount > 0;
    [unreadMessageBanner setHidden:!hasPending];
    [historyMessageBanner setHidden:(!hasPending || [self isViewingLatestMessages])];
    if (hasPending) {
        [chatScrollView addSubview:unreadMessageBanner positioned:NSWindowAbove relativeTo:nil];
        [chatScrollView addSubview:historyMessageBanner positioned:NSWindowAbove relativeTo:nil];
    }
}

-(void)resetUnreadMessageState {
    pendingNewMessageCount = 0;
    [pendingNewMessageStartDate release];
    pendingNewMessageStartDate = nil;
    [firstUnreadMessageID release];
    firstUnreadMessageID = nil;
    [chatScrollView clearUnreadSeparator];
    [unreadMessageBanner setHidden:YES];
    [historyMessageBanner setHidden:YES];
}

-(void)recordUnreadMessage:(DLMessage *)message {
    if (!message) return;
    if (pendingNewMessageCount == 0) {
        pendingNewMessageStartDate = [[message timestamp] retain];
        firstUnreadMessageID = [[[message messageID] description] copy];
        [chatScrollView setUnreadStartMessageID:firstUnreadMessageID];
    }
    pendingNewMessageCount++;
    NSString *timeText = pendingNewMessageStartDate
        ? [NSDateFormatter localizedStringFromDate:pendingNewMessageStartDate
                                         dateStyle:NSDateFormatterNoStyle
                                         timeStyle:NSDateFormatterShortStyle]
        : @"--:--";
    [unreadMessageBannerLabel setStringValue:
     [NSString stringWithFormat:@"%@から %ld件+の新着メッセージ",
      timeText, (long)pendingNewMessageCount]];
    [self refreshMessageBannerVisibility];
}

-(IBAction)markLatestMessagesRead:(id)sender {
    if (firstMessage) {
        [[DLController sharedInstance] acknowledgeMessage:firstMessage];
    }
    [[[DLController sharedInstance] selectedChannel] setHasUnreadMessages:NO];
    [self resetUnreadMessageState];
}

-(IBAction)jumpToLatestMessages:(id)sender {
    NSPoint point = [[chatScrollView contentView] bounds].origin;
    point.y = 0.0;
    [[chatScrollView contentView] scrollToPoint:point];
    [chatScrollView reflectScrolledClipView:[chatScrollView contentView]];
    [self markLatestMessagesRead:nil];
}

-(void)mainWindowDidBecomeKey:(NSNotification *)notification {
    if (pendingNewMessageCount > 0 && [self isViewingLatestMessages]) {
        [self markLatestMessagesRead:nil];
    } else {
        [self refreshMessageBannerVisibility];
    }
}

-(void)installSearchResultsPane {
    CGFloat paneWidth = 280.0;
    NSRect chatBounds = [chatPaneView bounds];
    searchResultsPane = [[NSView_BGColor alloc] initWithFrame:
                         NSMakeRect(NSWidth(chatBounds) - paneWidth, 0.0, paneWidth, NSHeight(chatBounds) - 42.0)];
    [searchResultsPane setAutoresizingMask:NSViewMinXMargin | NSViewHeightSizable];
    [searchResultsPane setBackgroundColor:[DLUtil nativeSidebarColor]];
    [searchResultsPane setBottomBorderColor:[DLUtil nativeBorderColor]];

    searchResultsTitleField = [[NSTextField alloc] initWithFrame:NSMakeRect(12.0, NSHeight([searchResultsPane bounds]) - 31.0, 180.0, 19.0)];
    [searchResultsTitleField setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
    [searchResultsTitleField setBezeled:NO];
    [searchResultsTitleField setDrawsBackground:NO];
    [searchResultsTitleField setEditable:NO];
    [searchResultsTitleField setSelectable:NO];
    [searchResultsTitleField setFont:[NSFont boldSystemFontOfSize:13.0]];
    [searchResultsTitleField setTextColor:[DLUtil nativePrimaryTextColor]];
    [searchResultsTitleField setStringValue:@"Search Results"];
    [searchResultsPane addSubview:searchResultsTitleField];

    NSButton *closeButton = [[[NSButton alloc] initWithFrame:NSMakeRect(paneWidth - 33.0, NSHeight([searchResultsPane bounds]) - 34.0, 24.0, 24.0)] autorelease];
    [closeButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [closeButton setBordered:NO];
    [closeButton setFont:[NSFont systemFontOfSize:17.0]];
    [closeButton setTitle:@"×"];
    [closeButton setToolTip:@"Close search results"];
    [closeButton setTarget:self];
    [closeButton setAction:@selector(closeMessageSearchResults:)];
    [searchResultsPane addSubview:closeButton];

    searchResultsCountField = [[NSTextField alloc] initWithFrame:NSMakeRect(12.0, NSHeight([searchResultsPane bounds]) - 51.0, paneWidth - 24.0, 16.0)];
    [searchResultsCountField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [searchResultsCountField setBezeled:NO];
    [searchResultsCountField setDrawsBackground:NO];
    [searchResultsCountField setEditable:NO];
    [searchResultsCountField setSelectable:NO];
    [searchResultsCountField setFont:[NSFont systemFontOfSize:10.0]];
    [searchResultsCountField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [searchResultsPane addSubview:searchResultsCountField];

    searchEmptyStateField = [[NSTextField alloc] initWithFrame:
                             NSMakeRect(20.0, NSMidY([searchResultsPane bounds]) - 36.0,
                                        paneWidth - 40.0, 72.0)];
    [searchEmptyStateField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin];
    [searchEmptyStateField setBezeled:NO];
    [searchEmptyStateField setDrawsBackground:NO];
    [searchEmptyStateField setEditable:NO];
    [searchEmptyStateField setSelectable:NO];
    [searchEmptyStateField setAlignment:NSCenterTextAlignment];
    [searchEmptyStateField setFont:[NSFont boldSystemFontOfSize:16.0]];
    [searchEmptyStateField setTextColor:[DLUtil nativePrimaryTextColor]];
    [[searchEmptyStateField cell] setWraps:YES];
    [[searchEmptyStateField cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [searchEmptyStateField setHidden:YES];
    [searchResultsPane addSubview:searchEmptyStateField];

    searchResultsScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 30.0, paneWidth, NSHeight([searchResultsPane bounds]) - 86.0)];
    [searchResultsScrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [searchResultsScrollView setBorderType:NSNoBorder];
    [searchResultsScrollView setHasVerticalScroller:YES];
    [searchResultsScrollView setDrawsBackground:YES];
    [searchResultsScrollView setBackgroundColor:[DLUtil nativeSidebarColor]];

    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"searchResult"] autorelease];
    [column setWidth:paneWidth];
    [column setResizingMask:NSTableColumnAutoresizingMask];
    [column setDataCell:[[[DLSearchResultCell alloc] init] autorelease]];
    searchResultsTableView = [[NSTableView alloc] initWithFrame:[[searchResultsScrollView contentView] bounds]];
    [searchResultsTableView addTableColumn:column];
    [searchResultsTableView setHeaderView:nil];
    [searchResultsTableView setDataSource:self];
    [searchResultsTableView setDelegate:self];
    [searchResultsTableView setRowHeight:72.0];
    [searchResultsTableView setIntercellSpacing:NSMakeSize(0.0, 0.0)];
    [searchResultsTableView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [searchResultsTableView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];
    [searchResultsScrollView setDocumentView:searchResultsTableView];
    [searchResultsPane addSubview:searchResultsScrollView];
    [searchEmptyStateField removeFromSuperviewWithoutNeedingDisplay];
    [searchResultsPane addSubview:searchEmptyStateField];

    searchPreviousButton = [[NSButton alloc] initWithFrame:NSMakeRect(8.0, 4.0, 70.0, 24.0)];
    [searchPreviousButton setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
    [searchPreviousButton setBezelStyle:NSRoundRectBezelStyle];
    [searchPreviousButton setFont:[NSFont systemFontOfSize:10.0]];
    [searchPreviousButton setTitle:@"‹ Previous"];
    [searchPreviousButton setTarget:self];
    [searchPreviousButton setAction:@selector(showPreviousSearchPage:)];
    [searchPreviousButton setEnabled:NO];
    [searchResultsPane addSubview:searchPreviousButton];

    searchPageField = [[NSTextField alloc] initWithFrame:NSMakeRect(82.0, 7.0, paneWidth - 164.0, 17.0)];
    [searchPageField setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [searchPageField setBezeled:NO];
    [searchPageField setDrawsBackground:NO];
    [searchPageField setEditable:NO];
    [searchPageField setSelectable:NO];
    [searchPageField setAlignment:NSCenterTextAlignment];
    [searchPageField setFont:[NSFont systemFontOfSize:10.0]];
    [searchPageField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [searchResultsPane addSubview:searchPageField];

    searchNextButton = [[NSButton alloc] initWithFrame:NSMakeRect(paneWidth - 78.0, 4.0, 70.0, 24.0)];
    [searchNextButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
    [searchNextButton setBezelStyle:NSRoundRectBezelStyle];
    [searchNextButton setFont:[NSFont systemFontOfSize:10.0]];
    [searchNextButton setTitle:@"Next ›"];
    [searchNextButton setTarget:self];
    [searchNextButton setAction:@selector(showNextSearchPage:)];
    [searchNextButton setEnabled:NO];
    [searchResultsPane addSubview:searchNextButton];

    [chatPaneView addSubview:searchResultsPane];
    [searchResultsPane setHidden:YES];
    searchResultsPaneVisible = NO;
    pinsPaneActive = NO;
    messageSearchResults = [[NSArray alloc] init];
    messageSearchOffset = 0;
    messageSearchTotal = 0;
}

-(void)installThreadBrowser {
    NSRect bounds = [chatPaneView bounds];
    threadListPane = [[NSView_BGColor alloc] initWithFrame:
                      NSMakeRect(0.0, 0.0, NSWidth(bounds), NSHeight(bounds) - 42.0)];
    [threadListPane setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [threadListPane setBackgroundColor:[DLUtil nativeContentColor]];

    NSTextField *title = [[[NSTextField alloc] initWithFrame:
                           NSMakeRect(16.0, NSHeight([threadListPane bounds]) - 34.0,
                                      NSWidth([threadListPane bounds]) - 60.0, 22.0)] autorelease];
    [title setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [title setBezeled:NO];
    [title setDrawsBackground:NO];
    [title setEditable:NO];
    [title setSelectable:NO];
    [title setFont:[NSFont boldSystemFontOfSize:15.0]];
    [title setTextColor:[DLUtil nativePrimaryTextColor]];
    [title setStringValue:@"Active Threads"];
    [threadListPane addSubview:title];

    NSButton *closeListButton = [[[NSButton alloc] initWithFrame:
                                  NSMakeRect(NSWidth([threadListPane bounds]) - 35.0,
                                             NSHeight([threadListPane bounds]) - 36.0, 26.0, 26.0)] autorelease];
    [closeListButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [closeListButton setBordered:NO];
    [closeListButton setFont:[NSFont systemFontOfSize:17.0]];
    [closeListButton setTitle:@"×"];
    [closeListButton setToolTip:@"Close thread list"];
    [closeListButton setTarget:self];
    [closeListButton setAction:@selector(closeThreadList:)];
    [threadListPane addSubview:closeListButton];

    threadListScrollView = [[NSScrollView alloc] initWithFrame:
                            NSMakeRect(10.0, 10.0, NSWidth(bounds) - 20.0, NSHeight(bounds) - 92.0)];
    [threadListScrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [threadListScrollView setBorderType:NSNoBorder];
    [threadListScrollView setHasVerticalScroller:YES];
    [threadListScrollView setDrawsBackground:YES];
    [threadListScrollView setBackgroundColor:[DLUtil nativeContentColor]];
    NSTableColumn *threadColumn = [[[NSTableColumn alloc] initWithIdentifier:@"thread"] autorelease];
    [threadColumn setWidth:NSWidth([threadListScrollView bounds])];
    [threadColumn setResizingMask:NSTableColumnAutoresizingMask];
    [threadColumn setDataCell:[[[DLThreadListCell alloc] init] autorelease]];
    threadListTableView = [[NSTableView alloc] initWithFrame:[[threadListScrollView contentView] bounds]];
    [threadListTableView addTableColumn:threadColumn];
    [threadListTableView setHeaderView:nil];
    [threadListTableView setDataSource:self];
    [threadListTableView setDelegate:self];
    [threadListTableView setRowHeight:64.0];
    [threadListTableView setIntercellSpacing:NSMakeSize(0.0, 1.0)];
    [threadListTableView setBackgroundColor:[DLUtil nativeContentColor]];
    [threadListTableView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];
    [threadListScrollView setDocumentView:threadListTableView];
    [threadListPane addSubview:threadListScrollView];

    threadListEmptyField = [[NSTextField alloc] initWithFrame:
                            NSMakeRect(20.0, NSMidY([threadListPane bounds]) - 30.0,
                                       NSWidth(bounds) - 40.0, 60.0)];
    [threadListEmptyField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin];
    [threadListEmptyField setBezeled:NO];
    [threadListEmptyField setDrawsBackground:NO];
    [threadListEmptyField setEditable:NO];
    [threadListEmptyField setSelectable:NO];
    [threadListEmptyField setAlignment:NSCenterTextAlignment];
    [threadListEmptyField setFont:[NSFont boldSystemFontOfSize:15.0]];
    [threadListEmptyField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [threadListEmptyField setStringValue:@"No active threads in this channel"];
    [threadListPane addSubview:threadListEmptyField];

    CGFloat detailWidth = MAX(300.0, NSWidth(bounds) * 0.58);
    threadDetailPane = [[NSView_BGColor alloc] initWithFrame:
                        NSMakeRect(NSWidth(bounds) - detailWidth, 0.0, detailWidth, NSHeight(bounds) - 42.0)];
    [threadDetailPane setAutoresizingMask:NSViewMinXMargin | NSViewHeightSizable];
    [threadDetailPane setBackgroundColor:[DLUtil nativeContentColor]];
    [threadDetailPane setLeftBorderColor:[DLUtil nativeBorderColor]];
    threadDetailTitleField = [[NSTextField alloc] initWithFrame:
                              NSMakeRect(12.0, NSHeight([threadDetailPane bounds]) - 32.0,
                                         detailWidth - 52.0, 20.0)];
    [threadDetailTitleField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [threadDetailTitleField setBezeled:NO];
    [threadDetailTitleField setDrawsBackground:NO];
    [threadDetailTitleField setEditable:NO];
    [threadDetailTitleField setSelectable:NO];
    [threadDetailTitleField setFont:[NSFont boldSystemFontOfSize:13.0]];
    [threadDetailTitleField setTextColor:[DLUtil nativePrimaryTextColor]];
    [threadDetailPane addSubview:threadDetailTitleField];
    NSButton *closeDetailButton = [[[NSButton alloc] initWithFrame:
                                    NSMakeRect(detailWidth - 35.0,
                                               NSHeight([threadDetailPane bounds]) - 36.0, 26.0, 26.0)] autorelease];
    [closeDetailButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [closeDetailButton setBordered:NO];
    [closeDetailButton setFont:[NSFont systemFontOfSize:17.0]];
    [closeDetailButton setTitle:@"×"];
    [closeDetailButton setToolTip:@"Close thread"];
    [closeDetailButton setTarget:self];
    [closeDetailButton setAction:@selector(closeThreadDetail:)];
    [threadDetailPane addSubview:closeDetailButton];

    [chatPaneView addSubview:threadListPane];
    [chatPaneView addSubview:threadDetailPane];
    [threadListPane setHidden:YES];
    [threadDetailPane setHidden:YES];
    threadListItems = [[NSArray alloc] init];
    threadListVisible = NO;
    threadDetailVisible = NO;
}

-(void)installMemberListPane {
    CGFloat paneWidth = 220.0;
    NSRect bounds = [chatPaneView bounds];
    memberListPane = [[NSView_BGColor alloc] initWithFrame:
                      NSMakeRect(NSWidth(bounds) - paneWidth, 0.0, paneWidth, NSHeight(bounds) - 42.0)];
    [memberListPane setAutoresizingMask:NSViewMinXMargin | NSViewHeightSizable];
    [memberListPane setBackgroundColor:[DLUtil nativeSidebarColor]];
    [memberListPane setLeftBorderColor:[DLUtil nativeBorderColor]];

    NSTextField *title = [[[NSTextField alloc] initWithFrame:
                           NSMakeRect(12.0, NSHeight([memberListPane bounds]) - 30.0,
                                      paneWidth - 24.0, 18.0)] autorelease];
    [title setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [title setBezeled:NO];
    [title setDrawsBackground:NO];
    [title setEditable:NO];
    [title setSelectable:NO];
    [title setFont:[NSFont boldSystemFontOfSize:10.0]];
    [title setTextColor:[DLUtil nativeSecondaryTextColor]];
    [title setStringValue:@"MEMBERS"];
    [memberListPane addSubview:title];

    memberListScrollView = [[NSScrollView alloc] initWithFrame:
                            NSMakeRect(0.0, 0.0, paneWidth, NSHeight(bounds) - 76.0)];
    [memberListScrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [memberListScrollView setBorderType:NSNoBorder];
    [memberListScrollView setHasVerticalScroller:YES];
    [memberListScrollView setDrawsBackground:YES];
    [memberListScrollView setBackgroundColor:[DLUtil nativeSidebarColor]];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"member"] autorelease];
    [column setWidth:paneWidth];
    [column setResizingMask:NSTableColumnAutoresizingMask];
    [column setDataCell:[[[DLMemberListCell alloc] init] autorelease]];
    memberListTableView = [[NSTableView alloc] initWithFrame:[[memberListScrollView contentView] bounds]];
    [memberListTableView addTableColumn:column];
    [memberListTableView setHeaderView:nil];
    [memberListTableView setDataSource:self];
    [memberListTableView setDelegate:self];
    [memberListTableView setRowHeight:40.0];
    [memberListTableView setIntercellSpacing:NSMakeSize(0.0, 0.0)];
    [memberListTableView setAllowsEmptySelection:YES];
    [memberListTableView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];
    [memberListTableView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [memberListScrollView setDocumentView:memberListTableView];
    [[memberListScrollView contentView] setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(memberListBoundsDidChange:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:[memberListScrollView contentView]];
    [memberListPane addSubview:memberListScrollView];
    [chatPaneView addSubview:memberListPane];
    [memberListPane setHidden:YES];
    memberListItems = [[NSArray alloc] init];
    memberAvatarRequests = [[NSMutableSet alloc] init];
    memberListVisible = NO;
    memberRequestedUpperBound = 99;
    memberRequestInFlight = NO;
}

-(void)refreshMemberList {
    DLServer *server = [[DLController sharedInstance] selectedServer];
    NSArray *items = server ? [[server members] sortedArrayUsingSelector:@selector(compareDisplayName:)] : [NSArray array];
    [memberListItems release];
    memberListItems = [items retain];
    [memberListTableView reloadData];
    NSInteger loadCount = MIN((NSInteger)[memberListItems count], 20);
    for (NSInteger index = 0; index < loadCount; index++) {
        DLUser *user = [[memberListItems objectAtIndex:index] user];
        NSString *userID = [[user userID] description];
        if (userID && ![memberAvatarRequests containsObject:userID]) {
            [memberAvatarRequests addObject:userID];
            [user setDelegate:self];
            [user loadAvatarData];
        }
    }
}

-(void)setMemberListVisible:(BOOL)visible {
    if (visible == memberListVisible) return;
    CGFloat paneWidth = NSWidth([memberListPane frame]);
    NSRect chatFrame = [chatScrollView frame];
    NSRect entryFrame = [messageEntryContainerView frame];
    if (visible) {
        if (threadListVisible) return;
        if (searchResultsPaneVisible) [self closeMessageSearchResults:nil];
        [self refreshMemberList];
        DLServer *server = [[DLController sharedInstance] selectedServer];
        DLChannel *channel = [[DLController sharedInstance] selectedChannel];
        memberRequestedUpperBound = 99;
        memberRequestInFlight = NO;
        if (server && channel && ![server isEqual:[[DLController sharedInstance] myServerItem]]) {
            memberRequestInFlight = YES;
            [[DLController sharedInstance] requestMembersForChannel:channel inServer:server from:0 to:99];
        }
        chatFrame.size.width = MAX(180.0, chatFrame.size.width - paneWidth);
        entryFrame.size.width = MAX(180.0, entryFrame.size.width - paneWidth);
        [memberListPane setHidden:NO];
    } else {
        chatFrame.size.width += paneWidth;
        entryFrame.size.width += paneWidth;
        [memberListPane setHidden:YES];
    }
    memberListVisible = visible;
    [chatScrollView setFrame:chatFrame];
    [messageEntryContainerView setFrame:entryFrame];
    [chatScrollView screenResize];
    [membersButton setState:(visible ? NSOnState : NSOffState)];
}

-(void)memberListBoundsDidChange:(NSNotification *)notification {
    if (!memberListVisible) return;
    NSClipView *clipView = [notification object];
    CGFloat visibleBottom = NSMaxY([clipView bounds]);
    CGFloat documentHeight = NSHeight([memberListTableView bounds]);
    if (documentHeight - visibleBottom < 120.0) {
        [self requestNextMemberPageIfNeeded];
    }
}

-(void)requestNextMemberPageIfNeeded {
    if (memberRequestInFlight || memberRequestedUpperBound >= 499) return;
    DLServer *server = [[DLController sharedInstance] selectedServer];
    DLChannel *channel = [[DLController sharedInstance] selectedChannel];
    if (!server || !channel || [server isEqual:[[DLController sharedInstance] myServerItem]]) return;
    NSInteger start = memberRequestedUpperBound + 1;
    NSInteger end = MIN(start + 99, 499);
    memberRequestedUpperBound = end;
    memberRequestInFlight = YES;
    [[DLController sharedInstance] requestMembersForChannel:channel inServer:server from:start to:end];
}

-(IBAction)toggleMemberList:(id)sender {
    DLServer *server = [[DLController sharedInstance] selectedServer];
    if (!server || [server isEqual:[[DLController sharedInstance] myServerItem]]) {
        NSBeep();
        return;
    }
    [self setMemberListVisible:!memberListVisible];
}

-(NSTextField *)profileLabelWithFrame:(NSRect)frame text:(NSString *)text font:(NSFont *)font color:(NSColor *)color {
    NSTextField *field = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [field setBezeled:NO];
    [field setDrawsBackground:NO];
    [field setEditable:NO];
    [field setSelectable:YES];
    [field setFont:font];
    [field setTextColor:color];
    [field setStringValue:text ? text : @""];
    return field;
}

-(NSString *)profileAvatarCacheKeyForUser:(DLUser *)user size:(CGFloat)size {
    NSString *userID = [[user userID] description];
    NSString *avatarID = [user avatarID];
    if (!avatarID || [avatarID isKindOfClass:[NSNull class]]) {
        avatarID = @"default";
    }
    NSData *avatarData = [user avatarImageData];
    return [NSString stringWithFormat:@"%@-%@-%lu-%lu-%.0f",
            userID ? userID : @"unknown", avatarID,
            (unsigned long)[avatarData length], (unsigned long)[avatarData hash], size];
}

-(NSImage *)cachedProfileAvatarForUser:(DLUser *)user size:(CGFloat)size {
    return [profileAvatarCache objectForKey:[self profileAvatarCacheKeyForUser:user size:size]];
}

-(void)requestProfileAvatarForUser:(DLUser *)user size:(CGFloat)size radius:(CGFloat)radius {
    if (!user) return;
    NSString *cacheKey = [self profileAvatarCacheKeyForUser:user size:size];
    if ([profileAvatarCache objectForKey:cacheKey] || [profileAvatarRequests containsObject:cacheKey]) {
        return;
    }
    NSData *avatarData = [user avatarImageData];
    if (!avatarData) return;
    [profileAvatarRequests addObject:cacheKey];
    NSDictionary *context = [NSDictionary dictionaryWithObjectsAndKeys:
                             cacheKey, @"key",
                             avatarData, @"data",
                             [NSNumber numberWithDouble:size], @"size",
                             [NSNumber numberWithDouble:radius], @"radius", nil];
    [self performSelectorInBackground:@selector(loadProfileAvatarInBackground:) withObject:context];
}

-(void)loadProfileAvatarInBackground:(NSDictionary *)context {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *cacheKey = [context objectForKey:@"key"];
    CGFloat size = [[context objectForKey:@"size"] doubleValue];
    CGFloat radius = [[context objectForKey:@"radius"] doubleValue];
    NSImage *source = [[[NSImage alloc] initWithData:[context objectForKey:@"data"]] autorelease];
    NSImage *resized = source ? [DLUtil imageResize:source
                                           newSize:NSMakeSize(size, size)
                                      cornerRadius:radius] : nil;
    NSData *renderedData = resized ? [resized TIFFRepresentation] : nil;
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   cacheKey, @"key",
                                   [NSNumber numberWithDouble:size], @"size", nil];
    if (renderedData) {
        [result setObject:renderedData forKey:@"data"];
    }
    [self performSelectorOnMainThread:@selector(profileAvatarDidFinishLoading:)
                           withObject:result waitUntilDone:NO];
    [pool drain];
}

-(void)profileAvatarDidFinishLoading:(NSDictionary *)result {
    NSString *cacheKey = [result objectForKey:@"key"];
    [profileAvatarRequests removeObject:cacheKey];
    NSData *data = [result objectForKey:@"data"];
    if (!data) return;
    NSImage *image = [[[NSImage alloc] initWithData:data] autorelease];
    if (!image) return;
    [profileAvatarCache setObject:image forKey:cacheKey];
    if (!profileUser || ![cacheKey hasPrefix:[NSString stringWithFormat:@"%@-", [[profileUser userID] description]]]) {
        return;
    }
    CGFloat size = [[result objectForKey:@"size"] doubleValue];
    if (size == 72.0 && profileAvatarButton) {
        [profileAvatarButton setImage:image];
    } else if (size == 128.0 && profileDetailAvatarView) {
        [profileDetailAvatarView setImage:image];
    }
}

-(NSString *)profileDataCacheKeyForUser:(DLUser *)user server:(DLServer *)server {
    NSString *serverID = server && [server serverID] ? [server serverID] : @"@me";
    return [NSString stringWithFormat:@"%@-%@", [[user userID] description], serverID];
}

-(void)requestProfileDataForUser:(DLUser *)user server:(DLServer *)server {
    if (!user) return;
    NSString *key = [self profileDataCacheKeyForUser:user server:server];
    if ([profileDataCache objectForKey:key]) {
        [self updateVisibleProfileData];
        return;
    }
    if (![profileDataRequests containsObject:key]) {
        [profileDataRequests addObject:key];
        [[DLController sharedInstance] loadProfileForUser:user inServer:server];
    }
}

-(NSColor *)profileAccentColorFromData:(NSDictionary *)profile {
    NSDictionary *userProfile = [[profile objectForKey:@"user_profile"] isKindOfClass:[NSDictionary class]]
        ? [profile objectForKey:@"user_profile"] : nil;
    NSDictionary *userData = [[profile objectForKey:@"user"] isKindOfClass:[NSDictionary class]]
        ? [profile objectForKey:@"user"] : nil;
    NSNumber *accent = [userProfile objectForKey:@"accent_color"];
    if (![accent isKindOfClass:[NSNumber class]]) accent = [userData objectForKey:@"accent_color"];
    if (![accent isKindOfClass:[NSNumber class]]) {
        return [NSColor colorWithCalibratedRed:0.36 green:0.48 blue:0.72 alpha:1.0];
    }
    unsigned long value = [accent unsignedLongValue];
    return [NSColor colorWithCalibratedRed:((value >> 16) & 0xff) / 255.0
                                     green:((value >> 8) & 0xff) / 255.0
                                      blue:(value & 0xff) / 255.0 alpha:1.0];
}

-(NSString *)profileJoinedDateFromData:(NSDictionary *)profile {
    NSDictionary *member = [[profile objectForKey:@"guild_member"] isKindOfClass:[NSDictionary class]]
        ? [profile objectForKey:@"guild_member"] : nil;
    NSString *timestamp = [member objectForKey:@"joined_at"];
    if (![timestamp isKindOfClass:[NSString class]] || [timestamp length] < 10) return nil;
    return [[timestamp substringToIndex:10] stringByReplacingOccurrencesOfString:@"-" withString:@"/"];
}

-(NSString *)profileConnectionsTextFromData:(NSDictionary *)profile {
    NSArray *connections = [[profile objectForKey:@"connected_accounts"] isKindOfClass:[NSArray class]]
        ? [profile objectForKey:@"connected_accounts"] : nil;
    if ([connections count] == 0) return @"No visible connections";
    NSMutableArray *lines = [NSMutableArray array];
    NSInteger limit = MIN((NSInteger)[connections count], 5);
    for (NSInteger i = 0; i < limit; i++) {
        NSDictionary *connection = [connections objectAtIndex:i];
        if (![connection isKindOfClass:[NSDictionary class]]) continue;
        NSString *type = [connection objectForKey:@"type"];
        NSString *name = [connection objectForKey:@"name"];
        if ([type isKindOfClass:[NSString class]] && [name isKindOfClass:[NSString class]]) {
            [lines addObject:[NSString stringWithFormat:@"%@: %@", [type capitalizedString], name]];
        }
    }
    return [lines count] ? [lines componentsJoinedByString:@"\n"] : @"No visible connections";
}

-(NSString *)profileActivitiesTextFromData:(NSDictionary *)profile {
    NSArray *activities = [[profile objectForKey:@"activities"] isKindOfClass:[NSArray class]]
        ? [profile objectForKey:@"activities"] : nil;
    NSDictionary *member = [[profile objectForKey:@"guild_member"] isKindOfClass:[NSDictionary class]]
        ? [profile objectForKey:@"guild_member"] : nil;
    NSDictionary *presence = [[member objectForKey:@"presence"] isKindOfClass:[NSDictionary class]]
        ? [member objectForKey:@"presence"] : nil;
    if (!presence && [[profileMember presence] isKindOfClass:[NSDictionary class]]) {
        presence = [profileMember presence];
    }
    if (!activities) activities = [[presence objectForKey:@"activities"] isKindOfClass:[NSArray class]]
        ? [presence objectForKey:@"activities"] : nil;
    NSMutableArray *lines = [NSMutableArray array];
    NSEnumerator *enumerator = [activities objectEnumerator];
    NSDictionary *activity;
    while (activity = [enumerator nextObject]) {
        if (![activity isKindOfClass:[NSDictionary class]]) continue;
        if ([[activity objectForKey:@"type"] integerValue] == 4) continue;
        NSString *name = [activity objectForKey:@"name"];
        NSString *details = [activity objectForKey:@"details"];
        if (![details isKindOfClass:[NSString class]]) details = [activity objectForKey:@"state"];
        if ([name isKindOfClass:[NSString class]]) {
            [lines addObject:([details isKindOfClass:[NSString class]] && [details length] > 0)
             ? [NSString stringWithFormat:@"%@ — %@", name, details] : name];
        }
        if ([lines count] >= 3) break;
    }
    return [lines count] ? [lines componentsJoinedByString:@"\n"] : nil;
}

-(NSString *)profileCustomStatusFromData:(NSDictionary *)profile {
    NSArray *activities = [[profile objectForKey:@"activities"] isKindOfClass:[NSArray class]]
        ? [profile objectForKey:@"activities"] : nil;
    NSDictionary *member = [[profile objectForKey:@"guild_member"] isKindOfClass:[NSDictionary class]]
        ? [profile objectForKey:@"guild_member"] : nil;
    NSDictionary *presence = [[member objectForKey:@"presence"] isKindOfClass:[NSDictionary class]]
        ? [member objectForKey:@"presence"] : nil;
    if (!presence && [[profileMember presence] isKindOfClass:[NSDictionary class]]) presence = [profileMember presence];
    if (!activities && [[presence objectForKey:@"activities"] isKindOfClass:[NSArray class]]) {
        activities = [presence objectForKey:@"activities"];
    }
    NSEnumerator *enumerator = [activities objectEnumerator];
    NSDictionary *activity;
    while (activity = [enumerator nextObject]) {
        if (![activity isKindOfClass:[NSDictionary class]] || [[activity objectForKey:@"type"] integerValue] != 4) continue;
        NSString *status = [activity objectForKey:@"state"];
        if ([status isKindOfClass:[NSString class]] && [status length] > 0) return status;
    }
    return nil;
}

-(void)reloadRoleChipsInView:(NSView *)container roleIDs:(NSArray *)roleIDs maxWidth:(CGFloat)maxWidth {
    if (!container) return;
    NSArray *existing = [[container subviews] copy];
    NSEnumerator *oldEnumerator = [existing objectEnumerator];
    NSView *oldView;
    while (oldView = [oldEnumerator nextObject]) [oldView removeFromSuperview];
    [existing release];
    CGFloat x = 0.0;
    CGFloat y = NSHeight([container bounds]) - 23.0;
    NSInteger shown = 0;
    NSEnumerator *enumerator = [roleIDs objectEnumerator];
    NSString *roleID;
    while (roleID = [enumerator nextObject]) {
        if ([[roleID description] isEqualToString:[[profileServer serverID] description]]) continue;
        NSDictionary *role = [profileServer roleWithID:[roleID description]];
        NSString *name = [role objectForKey:@"name"];
        if (![name isKindOfClass:[NSString class]] || [name length] == 0) name = @"Role";
        NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSFont systemFontOfSize:10.0]
                                                                 forKey:NSFontAttributeName];
        CGFloat width = MIN(maxWidth, MAX(54.0, [name sizeWithAttributes:attributes].width + 29.0));
        if (x > 0.0 && x + width > maxWidth) {
            x = 0.0;
            y -= 27.0;
        }
        if (y < 0.0) break;
        NSNumber *colorValue = [role objectForKey:@"color"];
        unsigned long color = [colorValue isKindOfClass:[NSNumber class]] ? [colorValue unsignedLongValue] : 0;
        NSColor *dotColor = color == 0 ? [DLUtil nativeSecondaryTextColor]
            : [NSColor colorWithCalibratedRed:((color >> 16) & 0xff) / 255.0
                                        green:((color >> 8) & 0xff) / 255.0
                                         blue:(color & 0xff) / 255.0 alpha:1.0];
        DLProfileRoleChipView *chip = [[DLProfileRoleChipView alloc]
                                      initWithFrame:NSMakeRect(x, y, width, 22.0)
                                      name:name color:dotColor];
        [container addSubview:chip];
        [chip release];
        x += width + 5.0;
        shown++;
    }
    if (shown == 0) {
        NSTextField *empty = [self profileLabelWithFrame:NSMakeRect(0.0, MAX(0.0, y), maxWidth, 20.0)
                                                    text:@"No visible roles"
                                                    font:[NSFont systemFontOfSize:10.0]
                                                   color:[DLUtil nativeSecondaryTextColor]];
        [container addSubview:empty];
    }
}

-(void)applyCachedProfileBanner {
    if (!profileBannerURL) return;
    NSImage *cachedImage = [profileBannerImageCache objectForKey:profileBannerURL];
    if (cachedImage) {
        [profileBannerImageView setImage:cachedImage];
        [profileDetailBannerImageView setImage:cachedImage];
        return;
    }
    NSData *data = [[HTTPCache sharedInstance] cachedDataForURL:profileBannerURL];
    if (!data || [profileBannerImageRequests containsObject:profileBannerURL]) return;
    [profileBannerImageRequests addObject:profileBannerURL];
    NSDictionary *context = [NSDictionary dictionaryWithObjectsAndKeys:
                             profileBannerURL, @"url", data, @"data", nil];
    [self performSelectorInBackground:@selector(loadProfileBannerInBackground:) withObject:context];
}

-(void)loadProfileBannerInBackground:(NSDictionary *)context {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSImage *source = [[[NSImage alloc] initWithData:[context objectForKey:@"data"]] autorelease];
    NSImage *rendered = source ? [DLUtil imageResize:source newSize:NSMakeSize(380.0, 160.0) cornerRadius:0.0] : nil;
    NSData *renderedData = rendered ? [rendered TIFFRepresentation] : nil;
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:[context objectForKey:@"url"] forKey:@"url"];
    if (renderedData) [result setObject:renderedData forKey:@"data"];
    [self performSelectorOnMainThread:@selector(profileBannerDidFinishLoading:)
                           withObject:result waitUntilDone:NO];
    [pool drain];
}

-(void)profileBannerDidFinishLoading:(NSDictionary *)result {
    NSString *url = [result objectForKey:@"url"];
    [profileBannerImageRequests removeObject:url];
    NSData *data = [result objectForKey:@"data"];
    if (!data) return;
    NSImage *image = [[[NSImage alloc] initWithData:data] autorelease];
    if (!image) return;
    [profileBannerImageCache setObject:image forKey:url];
    if ([url isEqualToString:profileBannerURL]) {
        [profileBannerImageView setImage:image];
        [profileDetailBannerImageView setImage:image];
    }
}

-(void)profileBannerCacheDidUpdate:(NSNotification *)notification {
    if (profileBannerURL && [[notification object] isEqualToString:profileBannerURL]) {
        [self applyCachedProfileBanner];
    }
}

-(void)updateVisibleProfileData {
    if (!profileUser) return;
    NSDictionary *profile = [profileDataCache objectForKey:
                             [self profileDataCacheKeyForUser:profileUser server:profileServer]];
    if (![profile isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *userProfile = [[profile objectForKey:@"user_profile"] isKindOfClass:[NSDictionary class]]
        ? [profile objectForKey:@"user_profile"] : nil;
    NSDictionary *userData = [[profile objectForKey:@"user"] isKindOfClass:[NSDictionary class]]
        ? [profile objectForKey:@"user"] : nil;
    NSDictionary *guildMember = [[profile objectForKey:@"guild_member"] isKindOfClass:[NSDictionary class]]
        ? [profile objectForKey:@"guild_member"] : nil;
    NSString *bio = [userProfile objectForKey:@"bio"];
    if (![bio isKindOfClass:[NSString class]] || [bio length] == 0) bio = @"";
    NSString *pronouns = [userProfile objectForKey:@"pronouns"];
    NSString *joined = [self profileJoinedDateFromData:profile];
    NSArray *roles = [[guildMember objectForKey:@"roles"] isKindOfClass:[NSArray class]]
        ? [guildMember objectForKey:@"roles"] : [profileMember roles];
    NSArray *mutualGuilds = [[profile objectForKey:@"mutual_guilds"] isKindOfClass:[NSArray class]]
        ? [profile objectForKey:@"mutual_guilds"] : nil;

    NSMutableArray *metadata = [NSMutableArray array];
    if (joined) [metadata addObject:[NSString stringWithFormat:@"Joined %@", joined]];
    if ([pronouns isKindOfClass:[NSString class]] && [pronouns length] > 0) {
        [metadata addObject:[NSString stringWithFormat:@"Pronouns: %@", pronouns]];
    }
    if ([mutualGuilds count] > 0) {
        [metadata addObject:[NSString stringWithFormat:@"%ld mutual server%@", (long)[mutualGuilds count], [mutualGuilds count] == 1 ? @"" : @"s"]];
    }
    [profileBioField setStringValue:bio];
    [profileMetadataField setStringValue:[metadata count] ? [metadata componentsJoinedByString:@"  •  "] : @"Profile loaded"];
    [profileDetailBioField setStringValue:bio];
    [profileDetailMetadataField setStringValue:[metadata count] ? [metadata componentsJoinedByString:@"  •  "] : @""];
    [self reloadRoleChipsInView:profileRoleContainer roleIDs:roles maxWidth:NSWidth([profileRoleContainer bounds])];
    [self reloadRoleChipsInView:profileDetailRoleContainer roleIDs:roles maxWidth:NSWidth([profileDetailRoleContainer bounds])];
    NSString *customStatus = [self profileCustomStatusFromData:profile];
    [profileStatusField setStringValue:customStatus ? customStatus : @""];
    [profileStatusBubble setHidden:customStatus == nil];
    [profileDetailStatusField setStringValue:customStatus ? customStatus : @""];
    [profileDetailStatusBubble setHidden:customStatus == nil];
    NSString *activities = [self profileActivitiesTextFromData:profile];
    NSString *connections = [self profileConnectionsTextFromData:profile];
    [profileDetailConnectionsField setStringValue:activities
     ? [NSString stringWithFormat:@"ACTIVE NOW\n%@\n\nCONNECTIONS\n%@", activities, connections]
     : [NSString stringWithFormat:@"CONNECTIONS\n%@", connections]];

    NSColor *accent = [self profileAccentColorFromData:profile];
    [profileBannerView setBackgroundColor:accent];
    [profileDetailBannerView setBackgroundColor:accent];
    NSString *bannerHash = [userProfile objectForKey:@"banner"];
    if (![bannerHash isKindOfClass:[NSString class]]) bannerHash = [userData objectForKey:@"banner"];
    [profileBannerURL release];
    profileBannerURL = nil;
    [profileBannerImageView setImage:nil];
    [profileDetailBannerImageView setImage:nil];
    if ([bannerHash isKindOfClass:[NSString class]] && [bannerHash length] > 0) {
        profileBannerURL = [[NSString stringWithFormat:
                            @"https://cdn.discordapp.com/banners/%@/%@.png?size=600",
                            [profileUser userID], bannerHash] retain];
        if ([[HTTPCache sharedInstance] cachedDataForURL:profileBannerURL]) {
            [self applyCachedProfileBanner];
        } else if ([[HTTPCache sharedInstance] beginLoadingURL:profileBannerURL]) {
            AsyncHTTPGetRequest *request = [[AsyncHTTPGetRequest alloc] init];
            [request setDelegate:self];
            [request setUrl:profileBannerURL];
            [request setCached:YES];
            [request start];
        }
    }
}

-(void)showProfileForUser:(DLUser *)user relativeToRect:(NSRect)rect ofView:(NSView *)view {
    if (!user || !view) return;
    [profilePopover close];
    [profilePopover release];
    profilePopover = [[NSPopover alloc] init];
    [profilePopover setBehavior:NSPopoverBehaviorTransient];
    [profilePopover setDelegate:self];
    [profilePopoverController release];
    profilePopoverController = [[NSViewController alloc] init];
    [profileUser release];
    profileUser = [user retain];
    [profileServer release];
    profileServer = [[[DLController sharedInstance] selectedServer] retain];
    [profileMember release];
    DLServer *server = profileServer;
    profileMember = [[server memberWithUserID:[user userID]] retain];

    [profileBannerView release]; profileBannerView = nil;
    [profileBannerImageView release]; profileBannerImageView = nil;
    [profileBioField release]; profileBioField = nil;
    [profileMetadataField release]; profileMetadataField = nil;
    [profileRoleContainer release]; profileRoleContainer = nil;
    [profileStatusBubble release]; profileStatusBubble = nil;
    [profileStatusField release]; profileStatusField = nil;

    NSView_BGColor *card = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0, 0.0, 340.0, 410.0)] autorelease];
    [card setBackgroundColor:[DLUtil nativeContentColor]];
    NSView_BGColor *banner = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0, 305.0, 340.0, 105.0)] autorelease];
    [banner setBackgroundColor:[NSColor colorWithCalibratedRed:0.36 green:0.48 blue:0.72 alpha:1.0]];
    [card addSubview:banner];
    profileBannerView = [banner retain];
    NSImageView *bannerImage = [[[NSImageView alloc] initWithFrame:[banner bounds]] autorelease];
    [bannerImage setImageScaling:NSImageScaleAxesIndependently];
    [bannerImage setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [banner addSubview:bannerImage];
    profileBannerImageView = [bannerImage retain];

    NSButton *avatarButton = [[[NSButton alloc] initWithFrame:NSMakeRect(20.0, 263.0, 76.0, 76.0)] autorelease];
    [avatarButton setBordered:NO];
    [avatarButton setRefusesFirstResponder:YES];
    [avatarButton setTitle:@""];
    NSImage *avatar = [self cachedProfileAvatarForUser:user size:72.0];
    if (!avatar) {
        avatar = [[[NSImage alloc] initWithContentsOfFile:
                   [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"discord_placeholder.png"]] autorelease];
        [avatar setSize:NSMakeSize(72.0, 72.0)];
    }
    [avatarButton setImage:avatar];
    [avatarButton setImagePosition:NSImageOnly];
    [avatarButton setToolTip:@"Open full profile"];
    [avatarButton setTarget:self];
    [avatarButton setAction:@selector(showExpandedProfile:)];
    [card addSubview:avatarButton];
    [profileAvatarButton release];
    profileAvatarButton = [avatarButton retain];
    DLProfileStatusBubbleView *statusBubble = [[[DLProfileStatusBubbleView alloc]
                                               initWithFrame:NSMakeRect(108.0, 270.0, 212.0, 54.0)] autorelease];
    [statusBubble setHidden:YES];
    NSTextField *statusField = [self profileLabelWithFrame:NSMakeRect(14.0, 7.0, 184.0, 40.0)
                                                       text:@"" font:[NSFont systemFontOfSize:11.0]
                                                      color:[NSColor colorWithCalibratedWhite:0.18 alpha:1.0]];
    [[statusField cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [statusBubble addSubview:statusField];
    [card addSubview:statusBubble];
    profileStatusBubble = [statusBubble retain];
    profileStatusField = [statusField retain];

    NSString *displayName = [user globalName] ? [user globalName] : [user username];
    [card addSubview:[self profileLabelWithFrame:NSMakeRect(20.0, 236.0, 300.0, 25.0)
                                               text:displayName
                                               font:[NSFont boldSystemFontOfSize:18.0]
                                              color:[DLUtil nativePrimaryTextColor]]];
    [card addSubview:[self profileLabelWithFrame:NSMakeRect(20.0, 213.0, 300.0, 20.0)
                                               text:[user username]
                                               font:[NSFont systemFontOfSize:12.0]
                                              color:[DLUtil nativeSecondaryTextColor]]];
    NSTextField *bioField = [self profileLabelWithFrame:NSMakeRect(20.0, 164.0, 300.0, 42.0)
                                                   text:@"Loading profile details…"
                                                   font:[NSFont systemFontOfSize:11.0]
                                                  color:[DLUtil nativePrimaryTextColor]];
    [[bioField cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [[bioField cell] setWraps:YES];
    [[bioField cell] setScrollable:NO];
    [[bioField cell] setUsesSingleLineMode:NO];
    [card addSubview:bioField];
    profileBioField = [bioField retain];
    NSTextField *metadataField = [self profileLabelWithFrame:NSMakeRect(20.0, 136.0, 300.0, 20.0)
                                                        text:@"Loading membership details…"
                                                        font:[NSFont systemFontOfSize:10.0]
                                                       color:[DLUtil nativeSecondaryTextColor]];
    [card addSubview:metadataField];
    profileMetadataField = [metadataField retain];
    [card addSubview:[self profileLabelWithFrame:NSMakeRect(20.0, 106.0, 300.0, 20.0)
                                               text:@"ROLES"
                                               font:[NSFont boldSystemFontOfSize:10.0]
                                              color:[DLUtil nativeSecondaryTextColor]]];
    NSView *roleContainer = [[[NSView alloc] initWithFrame:NSMakeRect(20.0, 14.0, 300.0, 88.0)] autorelease];
    [card addSubview:roleContainer];
    profileRoleContainer = [roleContainer retain];
    [self reloadRoleChipsInView:roleContainer roleIDs:[profileMember roles] maxWidth:300.0];
    [profilePopoverController setView:card];
    [profilePopover setContentViewController:profilePopoverController];
    [profilePopover setContentSize:NSMakeSize(340.0, 410.0)];
    NSRectEdge edge = (view == memberListTableView) ? NSMinXEdge : NSMaxXEdge;
    [profilePopover showRelativeToRect:rect ofView:view preferredEdge:edge];
    [self requestProfileAvatarForUser:user size:72.0 radius:36.0];
    [self requestProfileDataForUser:user server:server];
}

-(IBAction)showMyProfile:(id)sender {
    [self showProfileForUser:[[DLController sharedInstance] myUser]
              relativeToRect:[myProfileButton bounds]
                      ofView:myProfileButton];
}

-(void)showExpandedProfile:(id)sender {
    if (!profileUser) return;
    [profilePopover close];
    if (profileDetailPanel) {
        [self.window removeChildWindow:profileDetailPanel];
        [profileDetailPanel close];
        [profileDetailPanel release];
    }
    profileDetailPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 760.0, 520.0)
                                                    styleMask:NSTitledWindowMask | NSClosableWindowMask
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    [profileDetailPanel setTitle:@"User Profile"];
    NSView_BGColor *content = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0, 0.0, 760.0, 520.0)] autorelease];
    [content setBackgroundColor:[DLUtil nativeContentColor]];
    NSView_BGColor *summary = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0, 0.0, 380.0, 520.0)] autorelease];
    [summary setBackgroundColor:[DLUtil nativeSidebarColor]];
    [summary setLeftBorderColor:[DLUtil nativeBorderColor]];
    [content addSubview:summary];
    [profileDetailBannerView release]; profileDetailBannerView = nil;
    [profileDetailBannerImageView release]; profileDetailBannerImageView = nil;
    [profileDetailBioField release]; profileDetailBioField = nil;
    [profileDetailMetadataField release]; profileDetailMetadataField = nil;
    [profileDetailConnectionsField release]; profileDetailConnectionsField = nil;
    [profileDetailRoleContainer release]; profileDetailRoleContainer = nil;
    [profileDetailStatusBubble release]; profileDetailStatusBubble = nil;
    [profileDetailStatusField release]; profileDetailStatusField = nil;
    NSView_BGColor *detailBanner = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0, 360.0, 380.0, 160.0)] autorelease];
    [detailBanner setBackgroundColor:[NSColor colorWithCalibratedRed:0.36 green:0.48 blue:0.72 alpha:1.0]];
    [summary addSubview:detailBanner];
    profileDetailBannerView = [detailBanner retain];
    NSImageView *detailBannerImage = [[[NSImageView alloc] initWithFrame:[detailBanner bounds]] autorelease];
    [detailBannerImage setImageScaling:NSImageScaleAxesIndependently];
    [detailBannerImage setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [detailBanner addSubview:detailBannerImage];
    profileDetailBannerImageView = [detailBannerImage retain];
    NSImageView *avatarView = [[[NSImageView alloc] initWithFrame:NSMakeRect(32.0, 315.0, 128.0, 128.0)] autorelease];
    NSImage *avatar = [self cachedProfileAvatarForUser:profileUser size:128.0];
    if (!avatar) {
        avatar = [[[NSImage alloc] initWithContentsOfFile:
                   [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"discord_placeholder.png"]] autorelease];
        [avatar setSize:NSMakeSize(128.0, 128.0)];
    }
    [avatarView setImage:avatar];
    [summary addSubview:avatarView];
    [profileDetailAvatarView release];
    profileDetailAvatarView = [avatarView retain];
    DLProfileStatusBubbleView *detailStatusBubble = [[[DLProfileStatusBubbleView alloc]
                                                     initWithFrame:NSMakeRect(172.0, 332.0, 184.0, 58.0)] autorelease];
    [detailStatusBubble setHidden:YES];
    NSTextField *detailStatusField = [self profileLabelWithFrame:NSMakeRect(14.0, 8.0, 156.0, 42.0)
                                                             text:@"" font:[NSFont systemFontOfSize:11.0]
                                                            color:[NSColor colorWithCalibratedWhite:0.18 alpha:1.0]];
    [[detailStatusField cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [detailStatusBubble addSubview:detailStatusField];
    [summary addSubview:detailStatusBubble];
    profileDetailStatusBubble = [detailStatusBubble retain];
    profileDetailStatusField = [detailStatusField retain];
    NSString *displayName = [profileUser globalName] ? [profileUser globalName] : [profileUser username];
    [summary addSubview:[self profileLabelWithFrame:NSMakeRect(32.0, 282.0, 316.0, 28.0)
                                                  text:displayName font:[NSFont boldSystemFontOfSize:20.0]
                                                 color:[DLUtil nativePrimaryTextColor]]];
    [summary addSubview:[self profileLabelWithFrame:NSMakeRect(32.0, 257.0, 316.0, 20.0)
                                                  text:[profileUser username] font:[NSFont systemFontOfSize:12.0]
                                                 color:[DLUtil nativeSecondaryTextColor]]];
    NSTextField *detailBio = [self profileLabelWithFrame:NSMakeRect(32.0, 204.0, 316.0, 45.0)
                                                     text:@"Loading profile details…"
                                                     font:[NSFont systemFontOfSize:12.0]
                                                    color:[DLUtil nativePrimaryTextColor]];
    [[detailBio cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [[detailBio cell] setWraps:YES];
    [[detailBio cell] setScrollable:NO];
    [[detailBio cell] setUsesSingleLineMode:NO];
    [summary addSubview:detailBio];
    profileDetailBioField = [detailBio retain];
    NSTextField *detailMetadata = [self profileLabelWithFrame:NSMakeRect(32.0, 175.0, 316.0, 22.0)
                                                          text:@"Loading membership details…"
                                                          font:[NSFont systemFontOfSize:10.0]
                                                         color:[DLUtil nativeSecondaryTextColor]];
    [summary addSubview:detailMetadata];
    profileDetailMetadataField = [detailMetadata retain];
    [summary addSubview:[self profileLabelWithFrame:NSMakeRect(32.0, 140.0, 316.0, 20.0)
                                                  text:@"ROLES" font:[NSFont boldSystemFontOfSize:10.0]
                                                 color:[DLUtil nativeSecondaryTextColor]]];
    NSView *detailRoleContainer = [[[NSView alloc] initWithFrame:NSMakeRect(32.0, 24.0, 316.0, 110.0)] autorelease];
    [summary addSubview:detailRoleContainer];
    profileDetailRoleContainer = [detailRoleContainer retain];
    [self reloadRoleChipsInView:detailRoleContainer roleIDs:[profileMember roles] maxWidth:316.0];

    [content addSubview:[self profileLabelWithFrame:NSMakeRect(410.0, 460.0, 320.0, 30.0)
                                                 text:@"PROFILE DETAILS" font:[NSFont boldSystemFontOfSize:14.0]
                                                color:[DLUtil nativePrimaryTextColor]]];
    NSTextField *detailConnections = [self profileLabelWithFrame:NSMakeRect(410.0, 70.0, 320.0, 380.0)
                                                             text:@"Loading activity and connections…"
                                                             font:[NSFont systemFontOfSize:11.0]
                                                            color:[DLUtil nativePrimaryTextColor]];
    [[detailConnections cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [content addSubview:detailConnections];
    profileDetailConnectionsField = [detailConnections retain];
    [profileDetailPanel setContentView:content];
    NSRect parentFrame = [self.window frame];
    NSRect panelFrame = [profileDetailPanel frame];
    panelFrame.origin.x = NSMidX(parentFrame) - NSWidth(panelFrame) / 2.0;
    panelFrame.origin.y = NSMidY(parentFrame) - NSHeight(panelFrame) / 2.0;
    [profileDetailPanel setFrame:panelFrame display:NO];
    [self.window addChildWindow:profileDetailPanel ordered:NSWindowAbove];
    [profileDetailPanel makeKeyAndOrderFront:self];
    [self requestProfileAvatarForUser:profileUser size:128.0 radius:64.0];
    [self requestProfileDataForUser:profileUser server:profileServer];
}

-(void)setSearchResultsPaneVisible:(BOOL)visible {
    if (searchResultsPaneVisible == visible) {
        return;
    }
    searchResultsPaneVisible = visible;
    if (visible && memberListVisible) {
        [self setMemberListVisible:NO];
    }
    CGFloat widthChange = NSWidth([searchResultsPane frame]);
    NSRect chatFrame = [chatScrollView frame];
    NSRect entryFrame = [messageEntryContainerView frame];
    if (visible) {
        chatFrame.size.width = MAX(180.0, chatFrame.size.width - widthChange);
        entryFrame.size.width = MAX(180.0, entryFrame.size.width - widthChange);
        [searchResultsPane setHidden:NO];
    } else {
        chatFrame.size.width += widthChange;
        entryFrame.size.width += widthChange;
        [searchResultsPane setHidden:YES];
    }
    [chatScrollView setFrame:chatFrame];
    [messageEntryContainerView setFrame:entryFrame];
    [chatScrollView screenResize];
}

-(IBAction)closeMessageSearchResults:(id)sender {
    [messageSearchField setStringValue:@""];
    [messageSearchResults release];
    messageSearchResults = [[NSArray alloc] init];
    [searchResultsTableView reloadData];
    messageSearchOffset = 0;
    messageSearchTotal = 0;
    [searchPreviousButton setEnabled:NO];
    [searchNextButton setEnabled:NO];
    [searchPageField setStringValue:@""];
    [searchEmptyStateField setHidden:YES];
    [pendingSearchAuthorName release];
    pendingSearchAuthorName = nil;
    pinsPaneActive = NO;
    [pinsButton setState:NSOffState];
    [searchResultsTitleField setStringValue:@"Search Results"];
    [self clearMessageSearchHighlight];
    [self setSearchResultsPaneVisible:NO];
}

-(IBAction)togglePinnedMessages:(id)sender {
    if (pinsPaneActive) {
        [self closeMessageSearchResults:nil];
        return;
    }
    DLChannel *channel = [[DLController sharedInstance] selectedChannel];
    if (!channel || threadListVisible) {
        [pinsButton setState:NSOffState];
        NSBeep();
        return;
    }
    pinsPaneActive = YES;
    [pinsButton setState:NSOnState];
    [searchResultsTitleField setStringValue:@"Pinned Messages"];
    [messageSearchResults release];
    messageSearchResults = [[NSArray alloc] init];
    [searchResultsTableView reloadData];
    [searchResultsCountField setStringValue:@"Loading pinned messages…"];
    [searchEmptyStateField setHidden:YES];
    [searchPreviousButton setEnabled:NO];
    [searchNextButton setEnabled:NO];
    [searchPageField setStringValue:@""];
    [self setSearchResultsPaneVisible:YES];
    [[DLController sharedInstance] loadPinsForChannel:channel];
}

-(IBAction)showThreadList:(id)sender {
    DLChannel *selected = [[DLController sharedInstance] selectedChannel];
    DLServer *server = [[DLController sharedInstance] selectedServer];
    if (!selected || !server || [server isEqual:[[DLController sharedInstance] myServerItem]]) {
        NSBeep();
        return;
    }
    DLChannel *parentChannel = selected;
    if ([selected isThread]) {
        parentChannel = [[DLController sharedInstance] loadedChannelWithID:[(DLServerChannel *)selected parentID]];
    }
    if (!parentChannel) {
        NSBeep();
        return;
    }
    if (searchResultsPaneVisible) {
        [self closeMessageSearchResults:nil];
    }
    if (memberListVisible) {
        [self setMemberListVisible:NO];
    }
    [threadListBaseChannel release];
    threadListBaseChannel = [parentChannel retain];
    [threadListItems release];
    threadListItems = [[[DLController sharedInstance] activeThreadsForServer:server
                                                               parentChannel:parentChannel] retain];
    [[DLController sharedInstance] loadArchivedThreadsForChannel:parentChannel];
    [threadListTableView reloadData];
    [threadListTableView deselectAll:self];
    [threadListEmptyField setHidden:([threadListItems count] != 0)];
    [chatScrollView setHidden:YES];
    [messageEntryContainerView setHidden:YES];
    [threadDetailPane setHidden:YES];
    [threadListPane setHidden:NO];
    threadListVisible = YES;
    threadDetailVisible = NO;
}

-(void)openThreadDetail:(DLChannel *)thread {
    if (!thread || !threadListVisible) {
        return;
    }
    isLoadingMessages = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:chatScrollView selector:@selector(screenResize) object:nil];
    [chatScrollView setHidden:YES];
    [chatScrollView setContent:[NSArray array]];
    NSRect bounds = [chatPaneView bounds];
    CGFloat detailWidth = MIN(NSWidth(bounds) - 180.0, MAX(300.0, NSWidth(bounds) * 0.58));
    NSRect detailFrame = NSMakeRect(NSWidth(bounds) - detailWidth, 0.0,
                                    detailWidth, NSHeight(bounds) - 42.0);
    [threadDetailPane setFrame:detailFrame];
    [threadDetailTitleField setStringValue:[NSString stringWithFormat:@"↳ %@", [thread name]]];
    [threadDetailPane setHidden:NO];

    [chatScrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [messageEntryContainerView setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [chatScrollView setFrame:NSMakeRect(0.0, 56.0, detailWidth,
                                        MAX(80.0, NSHeight(bounds) - 140.0))];
    [messageEntryContainerView setFrame:NSMakeRect(0.0, 0.0, detailWidth, 56.0)];
    [chatScrollView retain];
    if ([chatScrollView superview] != threadDetailPane) {
        [chatScrollView removeFromSuperviewWithoutNeedingDisplay];
        [threadDetailPane addSubview:chatScrollView];
    }
    [chatScrollView release];
    [messageEntryContainerView retain];
    if ([messageEntryContainerView superview] != threadDetailPane) {
        [messageEntryContainerView removeFromSuperviewWithoutNeedingDisplay];
        [threadDetailPane addSubview:messageEntryContainerView];
    }
    [messageEntryContainerView release];
    [chatScrollView setHidden:NO];
    [messageEntryContainerView setHidden:NO];
    threadDetailVisible = YES;
    [self selectChannel:thread];
}

-(IBAction)closeThreadDetail:(id)sender {
    if (!threadListVisible) {
        return;
    }
    [chatScrollView setHidden:YES];
    [messageEntryContainerView setHidden:YES];
    [threadDetailPane setHidden:YES];
    threadDetailVisible = NO;
    if (threadListBaseChannel) {
        [[DLController sharedInstance] setSelectedChannel:threadListBaseChannel];
        [chatHeaderLabel setStringValue:[threadListBaseChannel name]];
    }
    [threadListTableView deselectAll:self];
}

-(void)hideThreadBrowser {
    if (!threadListVisible) {
        return;
    }
    NSRect bounds = [chatPaneView bounds];
    [threadListPane setHidden:YES];
    [threadDetailPane setHidden:YES];
    [chatScrollView retain];
    if ([chatScrollView superview] != chatPaneView) {
        [chatScrollView removeFromSuperviewWithoutNeedingDisplay];
        [chatPaneView addSubview:chatScrollView];
    }
    [chatScrollView release];
    [messageEntryContainerView retain];
    if ([messageEntryContainerView superview] != chatPaneView) {
        [messageEntryContainerView removeFromSuperviewWithoutNeedingDisplay];
        [chatPaneView addSubview:messageEntryContainerView];
    }
    [messageEntryContainerView release];
    [chatScrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [messageEntryContainerView setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [chatScrollView setFrame:NSMakeRect(0.0, 56.0, NSWidth(bounds), NSHeight(bounds) - 98.0)];
    [messageEntryContainerView setFrame:NSMakeRect(0.0, 0.0, NSWidth(bounds), 56.0)];
    [chatScrollView setHidden:NO];
    [messageEntryContainerView setHidden:NO];
    threadListVisible = NO;
    threadDetailVisible = NO;
    [chatScrollView screenResize];
}

-(IBAction)closeThreadList:(id)sender {
    DLChannel *baseChannel = [threadListBaseChannel retain];
    [self hideThreadBrowser];
    if (baseChannel) {
        [self selectChannel:baseChannel];
    }
    [baseChannel release];
}

-(CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex {
    return compactDMLayout ? 0.0 : 180.0;
}

-(CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex {
    return MIN(360.0, NSWidth([splitView bounds]) - 320.0);
}

-(void)splitViewDidResizeSubviews:(NSNotification *)notification {
    if ([notification object] != mainSplitView) {
        return;
    }
    [chatScrollView refreshVisibleMessageHeaderLayouts];
    [NSObject cancelPreviousPerformRequestsWithTarget:chatScrollView selector:@selector(screenResize) object:nil];
    [chatScrollView performSelector:@selector(screenResize) withObject:nil afterDelay:0.05];
}

-(void)messageDisplayScaleDidChange:(NSNotification *)notification {
    if ([[DLController sharedInstance] selectedChannel]) {
        [self reloadSelectedChannel:nil];
    }
}

-(void)appearanceThemeDidChange:(NSNotification *)notification {
    [self applyCurrentTheme];
}

-(void)applyCurrentTheme {
    [self.window setBackgroundColor:[DLUtil nativeContentColor]];
    [serversScrollView setBackgroundColor:[DLUtil nativeServerRailColor]];
    [[serversScrollView contentView] setBackgroundColor:[DLUtil nativeServerRailColor]];
    [serverTableView setBackgroundColor:[DLUtil nativeServerRailColor]];
    [channelsScrollView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [[channelsScrollView contentView] setBackgroundColor:[DLUtil nativeSidebarColor]];
    [channelOutlineView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [chatScrollView setBackgroundColor:[DLUtil nativeContentColor]];
    [[chatScrollView contentView] setBackgroundColor:[DLUtil nativeContentColor]];
    [channelViewHeader setGradientStartColor:[DLUtil nativeHeaderTopColor] endColor:[DLUtil nativeHeaderBottomColor]];
    [chatViewHeader setGradientStartColor:[DLUtil nativeHeaderTopColor] endColor:[DLUtil nativeHeaderBottomColor]];
    [channelViewHeader setBottomBorderColor:[DLUtil nativeBorderColor]];
    [chatViewHeader setBottomBorderColor:[DLUtil nativeBorderColor]];
    [userInfoView setBackgroundColor:[DLUtil nativeChromeColor]];
    [messageEntryContainerView setBackgroundColor:[DLUtil nativeChromeColor]];
    [friendsHomeView setBackgroundColor:[DLUtil nativeContentColor]];
    [friendsHomeScrollView setBackgroundColor:[DLUtil nativeContentColor]];
    [[friendsHomeScrollView documentView] setNeedsDisplay:YES];
    [serverTableView reloadData];
    [channelOutlineView reloadData];
    [chatScrollView setNeedsDisplay:YES];
    [[self.window contentView] setNeedsDisplay:YES];
}

-(void)installNativeToolbar {
    currentConnectionState = DLWSConnectionStateConnecting;
    lastMessageSearchIndex = -1;
    [self.window setToolbar:nil];

    NSRect channelHeaderBounds = [channelViewHeader bounds];
    connectionStatusField = [[DLConnectionIndicatorView alloc] initWithFrame:
                             NSMakeRect(NSWidth(channelHeaderBounds) - 29.0, 10.0, 20.0, 22.0)];
    [connectionStatusField setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [channelViewHeader addSubview:connectionStatusField];
    NSRect serverLabelFrame = [serverLabel frame];
    serverLabelFrame.size.width = MAX(40.0, NSWidth(channelHeaderBounds) - serverLabelFrame.origin.x - 38.0);
    [serverLabel setFrame:serverLabelFrame];

    NSRect chatHeaderBounds = [chatViewHeader bounds];
    CGFloat reloadWidth = 26.0;
    CGFloat searchWidth = MIN(190.0, MAX(130.0, NSWidth(chatHeaderBounds) * 0.42));
    reloadButton = [[NSButton alloc] initWithFrame:
                    NSMakeRect(NSWidth(chatHeaderBounds) - reloadWidth - 8.0, 8.0, reloadWidth, 26.0)];
    [reloadButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [reloadButton setBordered:NO];
    [reloadButton setImage:[NSImage imageNamed:NSImageNameRefreshTemplate]];
    [reloadButton setImagePosition:NSImageOnly];
    [reloadButton setToolTip:@"Reload the selected channel"];
    [reloadButton setTarget:self];
    [reloadButton setAction:@selector(reloadSelectedChannel:)];
    [chatViewHeader addSubview:reloadButton];

    messageSearchField = [[NSSearchField alloc] initWithFrame:
                          NSMakeRect(NSMinX([reloadButton frame]) - searchWidth - 6.0, 9.0, searchWidth, 24.0)];
    DLDarkSearchFieldCell *searchCell = [[DLDarkSearchFieldCell alloc] initTextCell:@""];
    [searchCell setTextColor:[DLUtil nativePrimaryTextColor]];
    [searchCell setBackgroundColor:[NSColor clearColor]];
    [searchCell setDrawsBackground:NO];
    [searchCell setBezeled:NO];
    [messageSearchField setCell:searchCell];
    [searchCell release];
    [messageSearchField setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [messageSearchField setBackgroundColor:[DLUtil nativeInputColor]];
    [messageSearchField setTextColor:[DLUtil nativePrimaryTextColor]];
    [messageSearchField setFocusRingType:NSFocusRingTypeNone];
    [[messageSearchField cell] setPlaceholderString:@"Search messages"];
    [[messageSearchField cell] setSendsWholeSearchString:YES];
    [[messageSearchField cell] setSendsSearchStringImmediately:NO];
    [messageSearchField setTarget:self];
    [messageSearchField setAction:@selector(searchLoadedMessages:)];
    [chatViewHeader addSubview:messageSearchField];

    membersButton = [[DLMemberButton alloc] initWithFrame:
                     NSMakeRect(NSMinX([messageSearchField frame]) - 32.0, 8.0, 26.0, 26.0)];
    [membersButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [membersButton setBordered:NO];
    [membersButton setRefusesFirstResponder:YES];
    [membersButton setButtonType:NSPushOnPushOffButton];
    [membersButton setTitle:@""];
    [membersButton setToolTip:@"Show member list"];
    [membersButton setTarget:self];
    [membersButton setAction:@selector(toggleMemberList:)];
    [membersButton setEnabled:NO];
    [chatViewHeader addSubview:membersButton];

    pinsButton = [[DLPinsButton alloc] initWithFrame:
                  NSMakeRect(NSMinX([membersButton frame]) - 30.0, 8.0, 26.0, 26.0)];
    [pinsButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [pinsButton setBordered:NO];
    [pinsButton setRefusesFirstResponder:YES];
    [pinsButton setButtonType:NSPushOnPushOffButton];
    [pinsButton setTitle:@""];
    [pinsButton setToolTip:@"Show pinned messages"];
    [pinsButton setTarget:self];
    [pinsButton setAction:@selector(togglePinnedMessages:)];
    [pinsButton setEnabled:NO];
    [chatViewHeader addSubview:pinsButton];

    NSRect channelLabelFrame = [chatHeaderLabel frame];
    channelLabelFrame.size.width = MAX(45.0, NSMinX([pinsButton frame]) - channelLabelFrame.origin.x - 8.0);
    [chatHeaderLabel setFrame:channelLabelFrame];
    [self updateConnectionStatusField];
}

-(void)updateConnectionStatusField {
    NSString *statusDescription = @"Disconnected";
    NSColor *statusColor = [NSColor colorWithCalibratedRed:0.65 green:0.12 blue:0.12 alpha:1.0];
    if (currentConnectionState == DLWSConnectionStateConnecting) {
        statusDescription = @"Connecting…";
        statusColor = [NSColor colorWithCalibratedRed:0.72 green:0.46 blue:0.08 alpha:1.0];
    } else if (currentConnectionState == DLWSConnectionStateConnected) {
        statusDescription = @"Connected";
        statusColor = [NSColor colorWithCalibratedRed:0.18 green:0.55 blue:0.20 alpha:1.0];
    } else if (currentConnectionState == DLWSConnectionStateReconnecting) {
        statusDescription = @"Reconnecting…";
        statusColor = [NSColor colorWithCalibratedRed:0.72 green:0.46 blue:0.08 alpha:1.0];
    }
    [(DLConnectionIndicatorView *)connectionStatusField setIndicatorColor:statusColor];
    [connectionStatusField setToolTip:statusDescription];
}

-(void)connectionStateDidChange:(DLWSConnectionState)state {
    currentConnectionState = state;
    [self updateConnectionStatusField];
}

-(IBAction)reloadSelectedChannel:(id)sender {
    DLChannel *channel = [[DLController sharedInstance] selectedChannel];
    if (!channel) {
        NSBeep();
        return;
    }
    [self clearMessageSearchHighlight];
    if (searchResultsPaneVisible) {
        [self closeMessageSearchResults:nil];
    }
    [reloadButton setEnabled:NO];
    lastMessageSearchIndex = -1;
    lastMessage = nil;
    firstMessage = nil;
    searchHistoryWindowActive = NO;
    hasMoreNewerMessages = NO;
    isLoadingNewerMessages = NO;
    [[DLController sharedInstance] loadMessagesForChannel:channel beforeMessage:nil quantity:25];
}

-(void)clearMessageSearchHighlight {
    [highlightedSearchResult setSearchHighlighted:NO];
    highlightedSearchResult = nil;
}

-(IBAction)searchLoadedMessages:(id)sender {
    pinsPaneActive = NO;
    [pinsButton setState:NSOffState];
    [searchResultsTitleField setStringValue:@"Search Results"];
    NSString *query = [[messageSearchField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([query length] == 0) {
        [lastMessageSearchQuery release];
        lastMessageSearchQuery = nil;
        lastMessageSearchIndex = -1;
        [self clearMessageSearchHighlight];
        [messageSearchField setToolTip:nil];
        [messageSearchResults release];
        messageSearchResults = [[NSArray alloc] init];
        [searchResultsTableView reloadData];
        messageSearchOffset = 0;
        messageSearchTotal = 0;
        [searchPreviousButton setEnabled:NO];
        [searchNextButton setEnabled:NO];
        [searchPageField setStringValue:@""];
        [searchEmptyStateField setHidden:YES];
        [self setSearchResultsPaneVisible:NO];
        return;
    }

    if (![query isEqualToString:lastMessageSearchQuery]) {
        [lastMessageSearchQuery release];
        lastMessageSearchQuery = [query copy];
        lastMessageSearchIndex = -1;
        [pendingSearchAuthorName release];
        pendingSearchAuthorName = nil;
    }
    if ([query hasPrefix:@"@"]) {
        // Username lookup is retained for compatibility with the original client.
        // Discord's history endpoint requires an author ID rather than a display name.
        [self updateSearchResultsForQuery:query];
        messageSearchOffset = 0;
        messageSearchTotal = [messageSearchResults count];
        [searchPreviousButton setEnabled:NO];
        [searchNextButton setEnabled:NO];
        [searchPageField setStringValue:@""];
    } else {
        [self performMessageSearchAtOffset:0];
    }
}

-(void)performMessageSearchAtOffset:(NSInteger)offset {
    NSString *query = lastMessageSearchQuery;
    DLChannel *channel = [[DLController sharedInstance] selectedChannel];
    if (!query || [query length] == 0 || !channel) {
        return;
    }
    NSString *authorID = nil;
    if ([query hasPrefix:@"from:"]) {
        NSRange separator = [query rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
        NSUInteger end = separator.location == NSNotFound ? [query length] : separator.location;
        NSString *authorName = end > 5 ? [query substringWithRange:NSMakeRange(5, end - 5)] : @"";
        if ([authorName length] == 0) {
            [self showNoSearchUserNamed:authorName];
            return;
        }
        NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        if ([authorName rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
            authorID = authorName;
        } else {
            DLServer *server = [[DLController sharedInstance] selectedServer];
            DLUser *matchedUser = nil;
            if ([server isEqual:[[DLController sharedInstance] myServerItem]]) {
                NSArray *recipientMatches = [channel recipientsWithUsernameContainingString:authorName];
                NSMutableArray *users = [NSMutableArray arrayWithArray:recipientMatches ? recipientMatches : [NSArray array]];
                if ([[[[DLController sharedInstance] myUser] globalName] rangeOfString:authorName options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    [users addObject:[[DLController sharedInstance] myUser]];
                }
                NSMutableArray *wrappedMembers = [NSMutableArray array];
                NSEnumerator *userEnumerator = [users objectEnumerator];
                DLUser *user;
                while (user = [userEnumerator nextObject]) {
                    DLServerMember *member = [[[DLServerMember alloc] init] autorelease];
                    [member setUser:user];
                    [wrappedMembers addObject:member];
                }
                matchedUser = [self searchUserMatchingName:authorName inMembers:wrappedMembers];
            } else {
                matchedUser = [self searchUserMatchingName:authorName inMembers:[server members]];
            }
            if (matchedUser) {
                authorID = [matchedUser userID];
            } else if (![server isEqual:[[DLController sharedInstance] myServerItem]]) {
                [pendingSearchAuthorName release];
                pendingSearchAuthorName = [authorName copy];
                pendingSearchAuthorOffset = offset;
                [searchEmptyStateField setHidden:YES];
                [searchResultsCountField setStringValue:[NSString stringWithFormat:@"Finding %@…", authorName]];
                [searchPreviousButton setEnabled:NO];
                [searchNextButton setEnabled:NO];
                [self setSearchResultsPaneVisible:YES];
                [[DLController sharedInstance] queryServer:server forMembersContainingUsername:authorName];
                return;
            } else {
                [self showNoSearchUserNamed:authorName];
                return;
            }
        }
    }

    [self clearMessageSearchHighlight];
    [messageSearchResults release];
    messageSearchResults = [[NSArray alloc] init];
    [searchResultsTableView reloadData];
    [searchEmptyStateField setHidden:YES];
    [searchResultsCountField setFont:[NSFont systemFontOfSize:10.0]];
    [searchResultsCountField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [searchResultsCountField setStringValue:@"Searching message history…"];
    [searchPreviousButton setEnabled:NO];
    [searchNextButton setEnabled:NO];
    [searchPageField setStringValue:@""];
    [messageSearchField setToolTip:nil];
    [self setSearchResultsPaneVisible:YES];
    [[DLController sharedInstance] searchMessagesForChannel:channel
                                                     query:query
                                                  authorID:authorID
                                                    offset:MAX(0, offset)];
}

-(DLUser *)searchUserMatchingName:(NSString *)name inMembers:(NSArray *)members {
    DLUser *partialMatch = nil;
    NSEnumerator *enumerator = [members objectEnumerator];
    DLServerMember *member;
    while (member = [enumerator nextObject]) {
        DLUser *user = [member user];
        NSString *username = [user username] ? [user username] : @"";
        NSString *displayName = [user globalName] ? [user globalName] : username;
        if ([username caseInsensitiveCompare:name] == NSOrderedSame ||
            [displayName caseInsensitiveCompare:name] == NSOrderedSame) {
            return user;
        }
        if (!partialMatch &&
            ([username rangeOfString:name options:NSCaseInsensitiveSearch].location != NSNotFound ||
             [displayName rangeOfString:name options:NSCaseInsensitiveSearch].location != NSNotFound)) {
            partialMatch = user;
        }
    }
    return partialMatch;
}

-(void)showNoSearchUserNamed:(NSString *)name {
    [messageSearchResults release];
    messageSearchResults = [[NSArray alloc] init];
    [searchResultsTableView reloadData];
    [searchResultsCountField setFont:[NSFont systemFontOfSize:10.0]];
    [searchResultsCountField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [searchResultsCountField setStringValue:@"No results"];
    [searchEmptyStateField setStringValue:[name length] > 0 ?
     [NSString stringWithFormat:@"No user named %@", name] : @"Enter a user after from:"];
    [searchEmptyStateField setHidden:NO];
    [searchPreviousButton setEnabled:NO];
    [searchNextButton setEnabled:NO];
    [searchPageField setStringValue:@""];
    [self setSearchResultsPaneVisible:YES];
}

-(IBAction)showPreviousSearchPage:(id)sender {
    if (messageSearchOffset >= 25) {
        [self performMessageSearchAtOffset:messageSearchOffset - 25];
    }
}

-(IBAction)showNextSearchPage:(id)sender {
    if (messageSearchOffset + 25 < messageSearchTotal) {
        [self performMessageSearchAtOffset:messageSearchOffset + 25];
    }
}

-(void)updateSearchResultsForQuery:(NSString *)query {
    [self clearMessageSearchHighlight];
    [searchEmptyStateField setHidden:YES];
    [searchResultsCountField setFont:[NSFont systemFontOfSize:10.0]];
    [searchResultsCountField setTextColor:[DLUtil nativeSecondaryTextColor]];

    NSString *authorQuery = nil;
    NSString *contentQuery = query;
    if ([query hasPrefix:@"@"]) {
        NSRange separatorRange = [query rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
        if (separatorRange.location == NSNotFound) {
            authorQuery = [query substringFromIndex:1];
            contentQuery = @"";
        } else {
            authorQuery = [query substringWithRange:NSMakeRange(1, separatorRange.location - 1)];
            contentQuery = [[query substringFromIndex:separatorRange.location + 1]
                            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
    }

    NSMutableArray *results = [NSMutableArray array];
    NSEnumerator *enumerator = [[chatScrollView content] objectEnumerator];
    ChatItemViewController *item;
    while (item = [enumerator nextObject]) {
        DLMessage *message = [item representedObject];
        NSString *authorName = [[message author] globalName] ? [[message author] globalName] : @"";
        NSString *username = [[message author] username] ? [[message author] username] : @"";
        NSString *messageContent = [message content] ? [message content] : @"";
        BOOL contentMatches = [contentQuery length] == 0 || [messageContent rangeOfString:contentQuery options:NSCaseInsensitiveSearch].location != NSNotFound;
        NSString *nameQuery = authorQuery ? authorQuery : query;
        BOOL authorMatches = ([authorName rangeOfString:nameQuery options:NSCaseInsensitiveSearch].location != NSNotFound ||
                              [username rangeOfString:nameQuery options:NSCaseInsensitiveSearch].location != NSNotFound);
        BOOL matches = authorQuery ? ([authorQuery length] > 0 && authorMatches && contentMatches)
                                   : (contentMatches || authorMatches);
        if (matches) {
            [results addObject:[item representedObject]];
        }
    }
    [messageSearchResults release];
    messageSearchResults = [[NSArray alloc] initWithArray:results];
    [searchResultsCountField setStringValue:[NSString stringWithFormat:@"%ld result%@ in loaded messages",
                                             (long)[messageSearchResults count],
                                             [messageSearchResults count] == 1 ? @"" : @"s"]];
    [searchResultsTableView reloadData];
    [searchResultsTableView deselectAll:self];
    if ([messageSearchResults count] == 0) {
        [searchEmptyStateField setStringValue:@"No matching messages"];
        [searchEmptyStateField setHidden:NO];
    }
    [messageSearchField setToolTip:[messageSearchResults count] == 0 ? @"No matching loaded messages" : nil];
    [self setSearchResultsPaneVisible:YES];
}

-(void)jumpToSearchResultAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)[messageSearchResults count]) {
        return;
    }
    DLMessage *selectedMessage = [messageSearchResults objectAtIndex:row];
    NSString *selectedMessageID = [[selectedMessage messageID] description];
    NSEnumerator *enumerator = [[chatScrollView content] objectEnumerator];
    ChatItemViewController *item;
    while (item = [enumerator nextObject]) {
        if ([[[[item representedObject] messageID] description] isEqualToString:selectedMessageID]) {
            [self clearMessageSearchHighlight];
            highlightedSearchResult = item;
            [highlightedSearchResult setSearchHighlighted:YES];
            [self animatedScrollToChatView:highlightedSearchResult];
            return;
        }
    }

    DLChannel *targetChannel = [[DLController sharedInstance] loadedChannelWithID:[selectedMessage channelID]];
    if (!targetChannel) {
        [messageSearchField setToolTip:@"The result channel is unavailable"];
        NSBeep();
        return;
    }
    [messageSearchField setToolTip:@"Loading selected message…"];
    [[DLController sharedInstance] loadMessagesAroundMessage:selectedMessage
                                                   inChannel:targetChannel];
}

-(void)animatedScrollToChatView:(ChatItemViewController *)item {
    if (!item) {
        return;
    }
    NSClipView *clipView = [chatScrollView contentView];
    NSRect visibleBounds = [clipView bounds];
    NSRect itemFrame = [[item view] frame];
    CGFloat targetY = NSMidY(itemFrame) - NSHeight(visibleBounds) / 2.0;
    CGFloat maximumY = MAX(0.0, NSHeight([[chatScrollView documentView] frame]) - NSHeight(visibleBounds));
    targetY = MIN(maximumY, MAX(0.0, targetY));
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:0.22];
    [[[chatScrollView contentView] animator] setBoundsOrigin:NSMakePoint(visibleBounds.origin.x, targetY)];
    [NSAnimationContext endGrouping];
    [chatScrollView reflectScrolledClipView:clipView];
}

-(void)reloadSearchResultsTable {
    [searchResultsTableView reloadData];
}

-(void)loadVisibleSearchResultAvatars {
    NSInteger limit = MIN((NSInteger)[messageSearchResults count], 10);
    for (NSInteger index = 0; index < limit; index++) {
        DLMessage *message = [messageSearchResults objectAtIndex:index];
        [[message author] loadAvatarData];
    }
    [self performSelector:@selector(reloadSearchResultsTable) withObject:nil afterDelay:0.8];
    [self performSelector:@selector(reloadSearchResultsTable) withObject:nil afterDelay:2.0];
}

-(void)installNativeServerTableView {
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"server"] autorelease];
    [column setWidth:NSWidth([[serversScrollView contentView] bounds])];
    [column setResizingMask:NSTableColumnAutoresizingMask];
    [column setDataCell:[[[DLServerTableCell alloc] init] autorelease]];

    serverTableView = [[NSTableView alloc] initWithFrame:[[serversScrollView contentView] bounds]];
    [serverTableView addTableColumn:column];
    [serverTableView setHeaderView:nil];
    [serverTableView setDataSource:self];
    [serverTableView setDelegate:self];
    [serverTableView setRowHeight:58.0];
    [serverTableView setIntercellSpacing:NSMakeSize(0.0, 0.0)];
    [serverTableView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleNone];
    [serverTableView setAllowsMultipleSelection:NO];
    [serverTableView setAllowsEmptySelection:YES];
    [serverTableView setBackgroundColor:[DLUtil nativeServerRailColor]];
    [serverTableView setFocusRingType:NSFocusRingTypeNone];
    [serverTableView setGridStyleMask:NSTableViewGridNone];
    [serversScrollView setDocumentView:serverTableView];
}

-(void)displayServerItems:(NSArray *)items {
    NSEnumerator *oldEnumerator = [serverItems objectEnumerator];
    DLServer *oldServer;
    while (oldServer = [oldEnumerator nextObject]) {
        [oldServer setDelegate:nil];
    }

    [serverItems release];
    serverItems = [items retain];
    NSEnumerator *enumerator = [serverItems objectEnumerator];
    DLServer *server;
    while (server = [enumerator nextObject]) {
        [server setDelegate:self];
    }
    [serverTableView reloadData];

    DLServer *selectedServer = [[DLController sharedInstance] selectedServer];
    NSInteger selectedRow = selectedServer ? [serverItems indexOfObject:selectedServer] : NSNotFound;
    updatingServerTableSelection = YES;
    if (selectedRow != NSNotFound) {
        [serverTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow] byExtendingSelection:NO];
        [serverTableView scrollRowToVisible:selectedRow];
    } else {
        selectedRow = [serverItems indexOfObject:[[DLController sharedInstance] myServerItem]];
        if (selectedRow != NSNotFound) {
            [serverTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow] byExtendingSelection:NO];
        } else {
            [serverTableView deselectAll:self];
        }
    }
    updatingServerTableSelection = NO;
    isLoadingViews = NO;
    if (!selectedServer && selectedRow != NSNotFound) {
        [self selectServer:[serverItems objectAtIndex:selectedRow]];
    }
}

-(void)installNativeChannelOutlineView {
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"channel"] autorelease];
    [column setWidth:NSWidth([[channelsScrollView contentView] bounds])];
    [column setResizingMask:NSTableColumnAutoresizingMask];
    [column setDataCell:[[[DLChannelTableCell alloc] init] autorelease]];

    channelOutlineView = [[DLChannelOutlineView alloc] initWithFrame:[[channelsScrollView contentView] bounds]];
    [channelOutlineView addTableColumn:column];
    [channelOutlineView setOutlineTableColumn:column];
    [channelOutlineView setHeaderView:nil];
    [channelOutlineView setDataSource:self];
    [channelOutlineView setDelegate:self];
    [channelOutlineView setRowHeight:28.0];
    [channelOutlineView setIntercellSpacing:NSMakeSize(0.0, 1.0)];
    [channelOutlineView setIndentationPerLevel:14.0];
    [channelOutlineView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleNone];
    [channelOutlineView setAllowsMultipleSelection:NO];
    [channelOutlineView setAllowsEmptySelection:YES];
    [channelOutlineView setFocusRingType:NSFocusRingTypeNone];
    [channelOutlineView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [channelOutlineView setAutoresizesOutlineColumn:YES];
    [channelsScrollView setDocumentView:channelOutlineView];
}

-(void)displayChannelOutlineItems:(NSArray *)items {
    [channelOutlineItems release];
    channelOutlineItems = [items retain];
    BOOL showingDirectMessages = [[[DLController sharedInstance] selectedServer]
                                  isEqual:[[DLController sharedInstance] myServerItem]];
    [channelOutlineView setRowHeight:(showingDirectMessages ? 42.0 : 28.0)];
    [channelOutlineView setIndentationPerLevel:(showingDirectMessages ? 0.0 : 14.0)];
    [channelOutlineView reloadData];

    NSEnumerator *enumerator = [channelOutlineItems objectEnumerator];
    DLChannel *item;
    while (item = [enumerator nextObject]) {
        [item setDelegate:self];
        if ([[item children] count] > 0) {
            [channelOutlineView expandItem:item];
        }
        NSEnumerator *childEnumerator = [[item children] objectEnumerator];
        DLChannel *child;
        while (child = [childEnumerator nextObject]) {
            [child setDelegate:self];
            if ([[child children] count] > 0) {
                [channelOutlineView expandItem:child];
            }
            NSEnumerator *threadEnumerator = [[child children] objectEnumerator];
            DLChannel *thread;
            while (thread = [threadEnumerator nextObject]) {
                [thread setDelegate:self];
            }
        }
    }

    DLChannel *selectedChannel = [[DLController sharedInstance] selectedChannel];
    NSInteger selectedRow = selectedChannel ? [channelOutlineView rowForItem:selectedChannel] : -1;
    updatingChannelOutlineSelection = YES;
    if (selectedRow >= 0) {
        [channelOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow] byExtendingSelection:NO];
    } else {
        [channelOutlineView deselectAll:self];
    }
    updatingChannelOutlineSelection = NO;
    isLoadingViews = NO;
    if (showingDirectMessages && !selectedChannel) {
        [self showFriendsHomeWithChannels:items];
    }
}

-(void)setDelegate:(id<DLMainWindowDelegate>)inDelegate {
    delegate = inDelegate;
}

#pragma mark Native Server Table

-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == searchResultsTableView) {
        return [messageSearchResults count];
    }
    if (tableView == threadListTableView) {
        return [threadListItems count];
    }
    if (tableView == memberListTableView) {
        return [memberListItems count];
    }
    return [serverItems count];
}

-(id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == searchResultsTableView) {
        return [[messageSearchResults objectAtIndex:row] content];
    }
    if (tableView == threadListTableView) {
        DLServerChannel *thread = [threadListItems objectAtIndex:row];
        DLChannel *parent = [[DLController sharedInstance] loadedChannelWithID:[thread parentID]];
        return [NSString stringWithFormat:@"↳ %@    # %@",
                [thread name] ? [thread name] : @"Untitled",
                [parent name] ? [parent name] : @"Unknown channel"];
    }
    if (tableView == memberListTableView) {
        DLUser *user = [[memberListItems objectAtIndex:row] user];
        return [user globalName] ? [user globalName] : [user username];
    }
    return [[serverItems objectAtIndex:row] name];
}

-(void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == searchResultsTableView) {
        if ([cell isKindOfClass:[DLSearchResultCell class]]) {
            [(DLSearchResultCell *)cell setRepresentedMessage:[messageSearchResults objectAtIndex:row]];
        }
        return;
    }
    if (tableView == threadListTableView) {
        if ([cell isKindOfClass:[DLThreadListCell class]]) {
            [(DLThreadListCell *)cell setRepresentedThread:[threadListItems objectAtIndex:row]];
        }
        return;
    }
    if (tableView == memberListTableView) {
        if ([cell isKindOfClass:[DLMemberListCell class]]) {
            [(DLMemberListCell *)cell setRepresentedMember:[memberListItems objectAtIndex:row]];
        }
        return;
    }
    if ([cell isKindOfClass:[DLServerTableCell class]]) {
        [(DLServerTableCell *)cell setRepresentedServer:[serverItems objectAtIndex:row]];
        [(DLServerTableCell *)cell setDrawsSeparatorBefore:(row == 1)];
    }
}

-(NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation {
    if (tableView == searchResultsTableView) {
        if (row >= 0 && row < (NSInteger)[messageSearchResults count]) {
            return [[messageSearchResults objectAtIndex:row] content];
        }
        return nil;
    }
    if (tableView == threadListTableView) {
        if (row >= 0 && row < (NSInteger)[threadListItems count]) {
            return [[threadListItems objectAtIndex:row] name];
        }
        return nil;
    }
    if (tableView == memberListTableView) {
        if (row >= 0 && row < (NSInteger)[memberListItems count]) {
            DLUser *user = [[memberListItems objectAtIndex:row] user];
            return [user globalName] ? [user globalName] : [user username];
        }
        return nil;
    }
    if (row >= 0 && row < (NSInteger)[serverItems count]) {
        return [[serverItems objectAtIndex:row] name];
    }
    return nil;
}

-(void)tableViewSelectionDidChange:(NSNotification *)notification {
    if ([notification object] == searchResultsTableView) {
        [self jumpToSearchResultAtRow:[searchResultsTableView selectedRow]];
        return;
    }
    if ([notification object] == threadListTableView) {
        NSInteger row = [threadListTableView selectedRow];
        if (row >= 0 && row < (NSInteger)[threadListItems count]) {
            [self openThreadDetail:[threadListItems objectAtIndex:row]];
        }
        return;
    }
    if ([notification object] == memberListTableView) {
        NSInteger row = [memberListTableView selectedRow];
        if (row >= 0 && row < (NSInteger)[memberListItems count]) {
            DLUser *user = [[memberListItems objectAtIndex:row] user];
            [self showProfileForUser:user relativeToRect:[memberListTableView rectOfRow:row]
                              ofView:memberListTableView];
        }
        return;
    }
    if (updatingServerTableSelection || [notification object] != serverTableView) {
        return;
    }
    NSInteger row = [serverTableView selectedRow];
    if (row >= 0 && row < (NSInteger)[serverItems count]) {
        [self selectServer:[serverItems objectAtIndex:row]];
    }
}

-(void)selectServer:(DLServer *)server {
    if (![server isEqual:[[DLController sharedInstance] myServerItem]] && compactDMLayout) {
        compactDMLayout = NO;
        CGFloat restoredWidth = expandedChannelPaneWidth >= 180.0 ? expandedChannelPaneWidth : 220.0;
        [mainSplitView setPosition:MIN(restoredWidth, 300.0) ofDividerAtIndex:0];
    }
    [self.window setTitle:([server isEqual:[[DLController sharedInstance] myServerItem]] ? @"Direct Messages" : ([server name] ? [server name] : @"Legacy Discord"))];
    if (memberListVisible) {
        [self setMemberListVisible:NO];
    }
    [self hideThreadBrowser];
    [membersButton setEnabled:![server isEqual:[[DLController sharedInstance] myServerItem]]];
    [pinsButton setEnabled:NO];
    [attachButton setEnabled:NO];
    [emojiButton setEnabled:NO];
    [stickerButton setEnabled:NO];
    [messageEntryTextView setEditable:NO];
    [chatScrollView unregisterDraggedTypes];
    [self resetUI];
    [[DLController sharedInstance] setSelectedChannel:nil];
    [chatScrollView setContent:[NSArray array]];
    [self hideFriendsHome];

    if ([server isEqual:[[DLController sharedInstance] myServerItem]]) {
        [NSThread detachNewThreadSelector:@selector(loadDirectMessageChannels) toTarget:self withObject:nil];
    } else {
        [[DLController sharedInstance] loadActiveThreadsForServer:server];
        [NSThread detachNewThreadSelector:@selector(loadChannelsForServer:) toTarget:self withObject:server];
    }
}

-(void)refreshServerTable {
    [serverTableView reloadData];
}

-(void)iconDidUpdateWithData:(NSData *)data {
    [self performSelectorOnMainThread:@selector(refreshServerTable) withObject:nil waitUntilDone:NO];
}

-(void)mentionCountDidUpdate {
    [self performSelectorOnMainThread:@selector(refreshServerTable) withObject:nil waitUntilDone:NO];
}

-(void)unreadStatusDidUpdate {
    [self performSelectorOnMainThread:@selector(refreshServerTable) withObject:nil waitUntilDone:NO];
}

#pragma mark Native Channel Outline

-(NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (!item) {
        return [channelOutlineItems count];
    }
    return [[(DLChannel *)item children] count];
}

-(id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (!item) {
        return [channelOutlineItems objectAtIndex:index];
    }
    return [[(DLChannel *)item children] objectAtIndex:index];
}

-(BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    DLChannel *channel = (DLChannel *)item;
    return [[channel children] count] > 0;
}

-(id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    DLChannel *channel = (DLChannel *)item;
    NSString *name = [channel name] ? [channel name] : @"Untitled";
    if ([channel type] == ChannelTypeHeader) {
        return [name uppercaseString];
    }

    NSString *kindPrefix = @"";
    if ([channel isThread]) {
        kindPrefix = @"↳ ";
    } else if ([channel type] == ChannelTypeStandard || [channel type] == ChannelTypeAnnouncements ||
               [channel type] == ChannelTypeForum || [channel type] == ChannelTypeMedia) {
        kindPrefix = @"# ";
    } else if ([channel type] == ChannelTypeVoice || [channel type] == ChannelTypeStageVoice) {
        kindPrefix = @"◖ ";
    }
    NSString *unreadPrefix = [channel hasUnreadMessages] ? @"● " : @"";
    NSString *mentionSuffix = [channel mentionCount] > 0 ? [NSString stringWithFormat:@"  (%ld)", (long)[channel mentionCount]] : @"";
    return [NSString stringWithFormat:@"%@%@%@%@", unreadPrefix, kindPrefix, name, mentionSuffix];
}

-(BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item {
    // Group rows in Mountain Lion draw a clipped "Hide" / "Show" control at
    // the right edge. Regular expandable rows retain the native disclosure
    // triangle while the delegate below supplies the category styling.
    return NO;
}

-(BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
    return [(DLChannel *)item type] != ChannelTypeHeader;
}

-(void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    if ([cell isKindOfClass:[DLChannelTableCell class]]) {
        [(DLChannelTableCell *)cell setRepresentedChannel:(DLChannel *)item];
    }
    [cell setLineBreakMode:NSLineBreakByTruncatingTail];
}

-(void)outlineViewSelectionDidChange:(NSNotification *)notification {
    if (updatingChannelOutlineSelection) {
        return;
    }
    NSInteger row = [channelOutlineView selectedRow];
    if (row < 0) {
        return;
    }
    DLChannel *channel = [channelOutlineView itemAtRow:row];
    if ([channel type] != ChannelTypeHeader) {
        [self hideThreadBrowser];
        [self selectChannel:channel];
    }
}

-(void)selectChannel:(DLChannel *)channel {
    [self hideFriendsHome];
    if (searchResultsPaneVisible) {
        [self closeMessageSearchResults:nil];
    }
    [self clearMessageSearchHighlight];
    [pinsButton setEnabled:(channel != nil && [channel type] != ChannelTypeForum && [channel type] != ChannelTypeMedia)];
    lastMessageSearchIndex = -1;
    lastMessage = nil;
    firstMessage = nil;
    [self resetUnreadMessageState];
    searchHistoryWindowActive = NO;
    hasMoreNewerMessages = NO;
    isLoadingNewerMessages = NO;
    if ([channel type] == ChannelTypeForum || [channel type] == ChannelTypeMedia) {
        [[DLController sharedInstance] setSelectedChannel:channel];
        [chatHeaderLabel setStringValue:[channel name]];
        [attachButton setEnabled:NO];
        [emojiButton setEnabled:NO];
        [stickerButton setEnabled:NO];
        [messageEntryTextView setEditable:NO];
        [self resetUI];
        [self showThreadList:nil];
        return;
    }
    [attachButton setEnabled:YES];
    [emojiButton setEnabled:YES];
    BOOL isDirectMessage = [channel type] == ChannelTypeDM || [channel type] == ChannelTypeGroup;
    [stickerButton setEnabled:(!isDirectMessage && [[[[DLController sharedInstance] selectedServer] stickers] count] > 0)];
    [messageEntryTextView setEditable:YES];
    [chatScrollView registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, nil]];
    [self resetUI];
    [chatHeaderLabel setStringValue:[channel name] ? [channel name] : @"Direct Message"];
    NSData *headerImageData = ([channel type] == ChannelTypeDM || [channel type] == ChannelTypeGroup)
        ? [channel imageData] : [channel subImageData];
    [chatHeaderImage setImage:[[[NSImage alloc] initWithData:headerImageData] autorelease]];
    isLoadingMessages = YES;
    [[DLController sharedInstance] loadMessagesForChannel:channel beforeMessage:nil
                                                 quantity:([channel isThread] ? 15 : 25)];
}

-(void)refreshChannelOutlineItem:(DLChannel *)channel {
    if ([channelOutlineView rowForItem:channel] >= 0) {
        [channelOutlineView reloadItem:channel];
    }
}

-(void)mentionsUpdatedForChannel:(DLChannel *)channel {
    [self performSelectorOnMainThread:@selector(refreshChannelOutlineItem:) withObject:channel waitUntilDone:NO];
}

-(void)unreadStatusUpdatedForChannel:(DLChannel *)channel {
    [self performSelectorOnMainThread:@selector(refreshChannelOutlineItem:) withObject:channel waitUntilDone:NO];
}

-(void)channel:(DLChannel *)channel imageDidUpdateWithData:(NSData *)data {
    [self performSelectorOnMainThread:@selector(refreshChannelOutlineItem:) withObject:channel waitUntilDone:NO];
    if (![friendsHomeView isHidden] && [friendsHomeChannels containsObject:channel]) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshFriendsHomeAvatars) object:nil];
        [self performSelectorOnMainThread:@selector(refreshFriendsHomeAvatars) withObject:nil waitUntilDone:NO];
    }
    if ([channel isEqual:[[DLController sharedInstance] selectedChannel]]) {
        NSImage *headerAvatar = [[[NSImage alloc] initWithData:data] autorelease];
        if (headerAvatar) {
            [chatHeaderImage performSelectorOnMainThread:@selector(setImage:)
                                              withObject:headerAvatar waitUntilDone:NO];
        }
    }
}

-(void)resetUI {
    isTyping = NO;
    [typingTimer invalidate];
    typingTimer = nil;
    [typingUsers removeAllObjects];
    [self updateTypingString];
    [self hidePendingAttachmentView];
    [self hideReplyToView];
    [messageEditor clear];
    [messageEntryTextView setString:@""];
    [self textDidChange:nil];
}

-(void)loadMainContent {
    DLUser *u = [[DLController sharedInstance] myUser];
    [u setDelegate:self];
    [myUserAvatarImage setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:[u avatarImageData]] autorelease] newSize:myUserAvatarImage.frame.size cornerRadius:MY_USER_AVATAR_RADIUS]];
    [myUsernameTextField setStringValue:[u globalName]];
    [myDiscTextField setStringValue:[u username]];
    [u loadAvatarData];
}

-(void)populateUserServers {
    NSAutoreleasePool *autoreleasepool = [[NSAutoreleasePool alloc] init];
    if (!isLoadingViews) {
        isLoadingViews = YES;
        NSMutableArray *items = [[NSMutableArray alloc] init];
        [items addObject:[[DLController sharedInstance] myServerItem]];
        
        NSEnumerator *e = [[[DLController sharedInstance] userServers] objectEnumerator];
        DLServer *item;
        while (item = [e nextObject]) {
            if (![item isEqual:[[DLController sharedInstance] myServerItem]]) {
                [items addObject:item];
            }
        }
        [self performSelectorOnMainThread:@selector(displayServerItems:) withObject:items waitUntilDone:YES];
        [items release];
    }
    
    [autoreleasepool release];
}

-(void)loadChannelsForServer:(DLServer *)server {
    NSAutoreleasePool *autoreleasepool = [[NSAutoreleasePool alloc] init];
    if (!isLoadingViews) {
        isLoadingViews = YES;
        
        NSArray *channels = [[DLController sharedInstance] channelsForServer:server];
        NSEnumerator *e = [channels objectEnumerator];
        DLServerChannel *channelItem;
        while (channelItem = [e nextObject]) {
            [channelItem setDelegate:self];
            NSEnumerator *ee = [[channelItem children] objectEnumerator];
            DLServerChannel *child;
            while (child = [ee nextObject]) {
                [child setDelegate:self];
            }
        }
        [serverLabel performSelectorOnMainThread:@selector(setStringValue:) withObject:[server name] waitUntilDone:NO];
        [self performSelectorOnMainThread:@selector(displayChannelOutlineItems:) withObject:channels waitUntilDone:NO];
    }
    
    [autoreleasepool release];
}

-(void)refreshThreadOutlineForServer:(DLServer *)server {
    if (!server || ![server isEqual:[[DLController sharedInstance] selectedServer]]) {
        return;
    }
    NSArray *channels = [[DLController sharedInstance] channelsForServer:server];
    [self displayChannelOutlineItems:channels];
    if (threadListVisible && threadListBaseChannel) {
        [threadListItems release];
        threadListItems = [[[DLController sharedInstance] activeThreadsForServer:server
                                                                   parentChannel:threadListBaseChannel] retain];
        [threadListTableView reloadData];
        [threadListEmptyField setHidden:([threadListItems count] != 0)];
    }
}

-(void)threadsDidUpdateForServer:(DLServer *)server {
    [self performSelectorOnMainThread:@selector(scheduleThreadOutlineRefreshForServer:)
                           withObject:server
                        waitUntilDone:NO];
}

-(void)scheduleThreadOutlineRefreshForServer:(DLServer *)server {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(refreshThreadOutlineForServer:)
                                               object:nil];
    [self performSelector:@selector(refreshThreadOutlineForServer:)
               withObject:server
               afterDelay:0.08];
}

-(void)refreshArchivedThreadListForContext:(NSDictionary *)context {
    DLServer *server = [context objectForKey:@"server"];
    DLChannel *channel = [context objectForKey:@"channel"];
    if (!threadListVisible || !threadListBaseChannel ||
        ![threadListBaseChannel isEqual:channel] ||
        ![server isEqual:[[DLController sharedInstance] selectedServer]]) {
        return;
    }
    [threadListItems release];
    threadListItems = [[[DLController sharedInstance] activeThreadsForServer:server
                                                               parentChannel:threadListBaseChannel] retain];
    [threadListTableView reloadData];
    [threadListEmptyField setHidden:([threadListItems count] != 0)];
}

-(void)archivedThreadsDidUpdateForServer:(DLServer *)server channel:(DLChannel *)channel {
    if (!server || !channel) {
        return;
    }
    NSDictionary *context = [NSDictionary dictionaryWithObjectsAndKeys:
                             server, @"server", channel, @"channel", nil];
    [self performSelectorOnMainThread:@selector(refreshArchivedThreadListForContext:)
                           withObject:context
                        waitUntilDone:NO];
}

-(void)loadDirectMessageChannels {
    NSAutoreleasePool *autoreleasepool = [[NSAutoreleasePool alloc] init];
    if (!isLoadingViews) {
        isLoadingViews = YES;
        
        NSArray *channels = [[DLController sharedInstance] directMessageChannels];
        NSEnumerator *e = [channels objectEnumerator];
        DLDirectMessageChannel *item;
        while (item = [e nextObject]) {
            [item setDelegate:self];
        }
        [serverLabel performSelectorOnMainThread:@selector(setStringValue:) withObject:@"Direct Messages" waitUntilDone:NO];
        [self performSelectorOnMainThread:@selector(displayChannelOutlineItems:) withObject:channels waitUntilDone:NO];
        e = [channels objectEnumerator];
        while (item = [e nextObject]) {
            [item performSelectorOnMainThread:@selector(loadAvatarImageData) withObject:nil waitUntilDone:NO];
        }
    }
    
    [autoreleasepool release];
}

-(void)showPendingAttachmentView {
    if (![pendingAttachmentsScrollView superview]) {
        
        //CGPoint originalScrollOrigin = [chatScrollView frame].origin;
        
        NSRect attachmentsViewFrame = pendingAttachmentsScrollView.frame;
        attachmentsViewFrame.origin.y = messageEntryContainerView.frame.size.height;
        attachmentsViewFrame.size.width = messageEntryContainerView.frame.size.width;
        [pendingAttachmentsScrollView setFrame:attachmentsViewFrame];
        
        NSRect chatViewFrame = chatScrollView.frame;
        chatViewFrame.size.height -= attachmentsViewFrame.size.height;
        chatViewFrame.origin.y += attachmentsViewFrame.size.height;
        [chatScrollView setFrame:chatViewFrame];
        
        NSRect containerFrame = messageEntryContainerView.frame;
        containerFrame.size.height += attachmentsViewFrame.size.height;
        [messageEntryContainerView setFrame:containerFrame];
        
        [messageEntryContainerView addSubview:pendingAttachmentsScrollView];
        [messageEntryContainerView setNeedsDisplay:YES];
        [chatScrollView setNeedsDisplay:YES];
        
        if ([replyToView superview]) {
            NSRect replyToViewFrame = replyToView.frame;
            replyToViewFrame.origin.y -= attachmentsViewFrame.size.height;
            [replyToView setFrame:replyToViewFrame];
            [replyToView setNeedsDisplay:YES];
        }
        
        //[chatScrollView.documentView scrollPoint:NSMakePoint(0, [[chatScrollView contentView] bounds].origin.y + originalScrollOrigin.y)];
    }
}

-(void)hidePendingAttachmentView {
    if ([pendingAttachmentsScrollView superview]) {
        [pendingAttachmentsScrollView setContent:[[NSArray alloc] init]];
        NSRect attachmentsViewFrame = pendingAttachmentsScrollView.frame;
        
        NSRect chatViewFrame = chatScrollView.frame;
        chatViewFrame.size.height += attachmentsViewFrame.size.height;
        chatViewFrame.origin.y -= attachmentsViewFrame.size.height;
        [chatScrollView setFrame:chatViewFrame];
        
        NSRect containerFrame = messageEntryContainerView.frame;
        containerFrame.size.height -= attachmentsViewFrame.size.height;
        [messageEntryContainerView setFrame:containerFrame];
        
        [pendingAttachmentsScrollView removeFromSuperview];
        [messageEntryContainerView setNeedsDisplay:YES];
        [chatScrollView setNeedsDisplay:YES];
        
        if ([replyToView superview]) {
            NSRect replyToViewFrame = replyToView.frame;
            replyToViewFrame.origin.y += attachmentsViewFrame.size.height;
            [replyToView setFrame:replyToViewFrame];
            [replyToView setNeedsDisplay:YES];
        }
    }
}

-(void)showReplyToView {
    if (![replyToView superview]) {
        NSRect replyToViewFrame = replyToView.frame;
        replyToViewFrame.origin.y = messageEntryScrollView.frame.size.height + 35;
        replyToViewFrame.size.width = messageEntryContainerView.frame.size.width;
        [replyToView setFrame:replyToViewFrame];
        
        NSRect chatViewFrame = chatScrollView.frame;
        chatViewFrame.size.height -= replyToViewFrame.size.height;
        chatViewFrame.origin.y += replyToViewFrame.size.height;
        [chatScrollView setFrame:chatViewFrame];
        
        NSRect containerFrame = messageEntryContainerView.frame;
        containerFrame.size.height += replyToViewFrame.size.height;
        [messageEntryContainerView setFrame:containerFrame];
        
        [messageEntryContainerView addSubview:replyToView];
        [messageEntryContainerView setNeedsDisplay:YES];
        [chatScrollView setNeedsDisplay:YES];
    }
}

-(void)hideReplyToView {
    if ([replyToView superview]) {
        NSRect replyToViewFrame = replyToView.frame;
        
        NSRect chatViewFrame = chatScrollView.frame;
        chatViewFrame.size.height += replyToViewFrame.size.height;
        chatViewFrame.origin.y -= replyToViewFrame.size.height;
        [chatScrollView setFrame:chatViewFrame];
        
        NSRect containerFrame = messageEntryContainerView.frame;
        containerFrame.size.height -= replyToViewFrame.size.height;
        [messageEntryContainerView setFrame:containerFrame];
        
        [replyToView removeFromSuperview];
        [messageEntryContainerView setNeedsDisplay:YES];
        [chatScrollView setNeedsDisplay:YES];
    }
}

-(void)logOutUser {
    [[DLController sharedInstance] logOutUser];
}

- (IBAction)showFileOpenDialog:(id)sender {
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];
    [openDlg setCanChooseFiles:YES];
    [openDlg setAllowsMultipleSelection:YES];
    [openDlg setCanChooseDirectories:NO];
    if ([openDlg runModalForDirectory:nil file:nil] == NSOKButton) {
        
        [self updatePendingAttachmentsWithFilePaths:[openDlg filenames]];
    }
}

- (IBAction)showSettingsMenu:(id)sender {
    NSMenu *contextMenu = [[NSMenu alloc] init];
    NSMenuItem *settingsItem = [contextMenu addItemWithTitle:@"User Settings…" action:@selector(openUserSettings:) keyEquivalent:@""];
    [settingsItem setTarget:self];
    [contextMenu addItem:[NSMenuItem separatorItem]];
    [contextMenu addItemWithTitle:@"Log Out" action:@selector(logOutUser) keyEquivalent:@""];
    [NSMenu popUpContextMenu:contextMenu withEvent:[NSApp currentEvent] forView:(NSButton *)sender];
    [contextMenu release];
}

-(void)openUserSettings:(id)sender {
    [NSApp sendAction:@selector(showPreferencesWindow:) to:nil from:self];
}

-(void)showEmojiMenu:(id)sender {
    if (sender == emojiButton) {
        [reactionPickerChatView release];
        reactionPickerChatView = nil;
    }
    [emojiPickerItems release];
    NSMutableArray *pickerItems = [NSMutableArray array];
    if ([[[DLController sharedInstance] selectedServer] emojis]) {
        NSArray *customEmoji = [[[[DLController sharedInstance] selectedServer] emojis] sortedArrayUsingDescriptors:
            [NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(caseInsensitiveCompare:)]]];
        [pickerItems addObjectsFromArray:customEmoji];
    }
    [pickerItems addObjectsFromArray:[self standardEmojiPickerItems]];
    emojiPickerItems = [pickerItems copy];
    if (!emojiPopover) {
        emojiPopover = [[NSPopover alloc] init];
        [emojiPopover setBehavior:NSPopoverBehaviorTransient];
        [emojiPopover setDelegate:self];
        emojiPopoverController = [[NSViewController alloc] init];
        NSView_BGColor *pickerView = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0, 0, 300, 330)];
        [pickerView setBackgroundColor:[DLUtil nativeContentColor]];
        emojiPickerSearchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(10, 296, 280, 24)];
        DLDarkSearchFieldCell *emojiSearchCell = [[DLDarkSearchFieldCell alloc] initTextCell:@""];
        [emojiSearchCell setTextColor:[DLUtil nativePrimaryTextColor]];
        [emojiSearchCell setDrawsBackground:NO];
        [emojiSearchCell setBezeled:NO];
        [emojiPickerSearchField setCell:emojiSearchCell];
        [emojiSearchCell release];
        [[emojiPickerSearchField cell] setPlaceholderString:@"Search emoji"];
        [emojiPickerSearchField setBackgroundColor:[DLUtil nativeInputColor]];
        [emojiPickerSearchField setTextColor:[DLUtil nativePrimaryTextColor]];
        [emojiPickerSearchField setFocusRingType:NSFocusRingTypeNone];
        [emojiPickerSearchField setTarget:self];
        [emojiPickerSearchField setAction:@selector(reloadEmojiPickerGrid:)];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scheduleEmojiPickerReload:) name:NSControlTextDidChangeNotification object:emojiPickerSearchField];
        [pickerView addSubview:emojiPickerSearchField];
        emojiPickerScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 10, 280, 278)];
        [emojiPickerScrollView setHasVerticalScroller:YES];
        [emojiPickerScrollView setBorderType:NSNoBorder];
        [emojiPickerScrollView setDrawsBackground:YES];
        [emojiPickerScrollView setBackgroundColor:[DLUtil nativeContentColor]];
        [pickerView addSubview:emojiPickerScrollView];
        [emojiPopoverController setView:pickerView];
        [pickerView release];
        [emojiPopover setContentViewController:emojiPopoverController];
        [emojiPopover setContentSize:NSMakeSize(300, 330)];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(emojiCacheDidUpdate:) name:HTTPCacheDataDidUpdateNotification object:nil];
    }
    [emojiPickerSearchField setStringValue:@""];
    [self reloadEmojiPickerGrid:nil];
    NSView *anchorView = (NSView *)sender;
    if (![anchorView window]) {
        anchorView = emojiButton;
    }
    if (![anchorView window]) {
        return;
    }
    [emojiPopover showRelativeToRect:[anchorView bounds] ofView:anchorView preferredEdge:NSMaxYEdge];
}

-(void)showStickerMenu:(id)sender {
    [stickerPickerItems release];
    NSArray *serverStickers = [[[DLController sharedInstance] selectedServer] stickers];
    stickerPickerItems = [serverStickers copy];
    if (!stickerPopover) {
        stickerPopover = [[NSPopover alloc] init];
        [stickerPopover setBehavior:NSPopoverBehaviorTransient];
        [stickerPopover setDelegate:self];
        stickerPopoverController = [[NSViewController alloc] init];
        NSView_BGColor *pickerView = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0, 0, 300, 330)];
        [pickerView setBackgroundColor:[DLUtil nativeContentColor]];
        stickerPickerSearchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(10, 296, 280, 24)];
        DLDarkSearchFieldCell *stickerSearchCell = [[DLDarkSearchFieldCell alloc] initTextCell:@""];
        [stickerSearchCell setTextColor:[DLUtil nativePrimaryTextColor]];
        [stickerSearchCell setDrawsBackground:NO];
        [stickerSearchCell setBezeled:NO];
        [stickerPickerSearchField setCell:stickerSearchCell];
        [stickerSearchCell release];
        [[stickerPickerSearchField cell] setPlaceholderString:@"Search stickers"];
        [stickerPickerSearchField setBackgroundColor:[DLUtil nativeInputColor]];
        [stickerPickerSearchField setTextColor:[DLUtil nativePrimaryTextColor]];
        [stickerPickerSearchField setFocusRingType:NSFocusRingTypeNone];
        [stickerPickerSearchField setTarget:self];
        [stickerPickerSearchField setAction:@selector(reloadStickerPickerGrid:)];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scheduleStickerPickerReload:) name:NSControlTextDidChangeNotification object:stickerPickerSearchField];
        [pickerView addSubview:stickerPickerSearchField];
        stickerPickerScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 10, 280, 278)];
        [stickerPickerScrollView setHasVerticalScroller:YES];
        [stickerPickerScrollView setBorderType:NSNoBorder];
        [stickerPickerScrollView setDrawsBackground:YES];
        [stickerPickerScrollView setBackgroundColor:[DLUtil nativeContentColor]];
        [pickerView addSubview:stickerPickerScrollView];
        [stickerPopoverController setView:pickerView];
        [pickerView release];
        [stickerPopover setContentViewController:stickerPopoverController];
        [stickerPopover setContentSize:NSMakeSize(300, 330)];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stickerCacheDidUpdate:) name:HTTPCacheDataDidUpdateNotification object:nil];
    }
    [stickerPickerSearchField setStringValue:@""];
    [self reloadStickerPickerGrid:nil];
    if ([stickerButton window]) {
        [stickerPopover showRelativeToRect:[stickerButton bounds] ofView:stickerButton preferredEdge:NSMaxYEdge];
    }
}

-(void)reloadStickerPickerGrid:(id)sender {
    NSView_BGColor *grid = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0, 0, 260, 1)];
    [grid setBackgroundColor:[DLUtil nativeContentColor]];
    NSString *query = [[[stickerPickerSearchField stringValue] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *visible = [NSMutableArray array];
    NSEnumerator *enumerator = [stickerPickerItems objectEnumerator];
    NSDictionary *sticker;
    while (sticker = [enumerator nextObject]) {
        if ([sticker objectForKey:@"available"] && ![[sticker objectForKey:@"available"] boolValue]) {
            continue;
        }
        NSString *name = [[sticker objectForKey:@"name"] isKindOfClass:[NSString class]] ? [sticker objectForKey:@"name"] : @"Sticker";
        NSString *description = [[sticker objectForKey:@"description"] isKindOfClass:[NSString class]] ? [sticker objectForKey:@"description"] : @"";
        NSString *tags = [[sticker objectForKey:@"tags"] isKindOfClass:[NSString class]] ? [sticker objectForKey:@"tags"] : @"";
        NSString *searchText = [[NSString stringWithFormat:@"%@ %@ %@", name, description, tags] lowercaseString];
        if ([query length] > 0 && [searchText rangeOfString:query].location == NSNotFound) {
            continue;
        }
        [visible addObject:sticker];
    }

    NSInteger columns = 3;
    CGFloat cellWidth = 84.0;
    CGFloat cellHeight = 94.0;
    NSInteger rows = MAX(1, ((NSInteger)[visible count] + columns - 1) / columns);
    [grid setFrameSize:NSMakeSize(260, rows * cellHeight + 8.0)];
    for (NSInteger index = 0; index < (NSInteger)[visible count]; index++) {
        sticker = [visible objectAtIndex:index];
        NSInteger column = index % columns;
        NSInteger row = index / columns;
        NSRect cellFrame = NSMakeRect(4.0 + column * cellWidth,
                                      NSHeight([grid bounds]) - (row + 1) * cellHeight,
                                      80.0, 90.0);
        NSView *cellView = [[NSView alloc] initWithFrame:cellFrame];
        NSString *name = [[sticker objectForKey:@"name"] isKindOfClass:[NSString class]] ? [sticker objectForKey:@"name"] : @"Sticker";
        NSString *stickerURL = DLStickerPickerURL(sticker);
        NSData *data = stickerURL ? [[HTTPCache sharedInstance] cachedDataForURL:stickerURL] : nil;

        NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 90)];
        [button setBordered:NO];
        [button setTitle:@""];
        [button setToolTip:name];
        [button setTarget:self];
        [button setAction:@selector(sendSticker:)];
        [[button cell] setRepresentedObject:sticker];

        if (data) {
            NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(8, 17, 64, 68)];
            [imageView setImageScaling:NSImageScaleProportionallyUpOrDown];
            [imageView setAnimates:([[sticker objectForKey:@"format_type"] integerValue] == 2 || [[sticker objectForKey:@"format_type"] integerValue] == 4)];
            [imageView setImage:[[[NSImage alloc] initWithData:data] autorelease]];
            [cellView addSubview:imageView];
            [imageView release];
            [button setTransparent:YES];
        } else if (stickerURL) {
            [button setEnabled:NO];
            [button setTitle:@"…"];
            if ([[HTTPCache sharedInstance] beginLoadingURL:stickerURL]) {
                AsyncHTTPGetRequest *request = [[AsyncHTTPGetRequest alloc] init];
                [request setDelegate:self];
                [request setUrl:stickerURL];
                [request setCached:YES];
                [request start];
            }
        } else {
            [button setTitle:@"✨"];
            [button setFont:[NSFont systemFontOfSize:30.0]];
        }
        NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(2, 1, 76, 16)];
        [nameField setBordered:NO];
        [nameField setDrawsBackground:NO];
        [nameField setEditable:NO];
        [nameField setSelectable:NO];
        [nameField setAlignment:NSCenterTextAlignment];
        [nameField setFont:[NSFont systemFontOfSize:10.0]];
        [nameField setTextColor:[DLUtil nativeSecondaryTextColor]];
        [[nameField cell] setLineBreakMode:NSLineBreakByTruncatingTail];
        [nameField setStringValue:name];
        [cellView addSubview:nameField];
        [nameField release];
        [cellView addSubview:button];
        [button release];
        [grid addSubview:cellView];
        [cellView release];
    }
    if ([visible count] == 0) {
        NSTextField *emptyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, NSHeight([grid bounds]) / 2.0 - 10.0, 235, 20)];
        [emptyLabel setBordered:NO];
        [emptyLabel setDrawsBackground:NO];
        [emptyLabel setEditable:NO];
        [emptyLabel setAlignment:NSCenterTextAlignment];
        [emptyLabel setTextColor:[DLUtil nativeSecondaryTextColor]];
        [emptyLabel setStringValue:([stickerPickerItems count] ? @"No matching stickers" : @"No stickers available")];
        [grid addSubview:emptyLabel];
        [emptyLabel release];
    }
    [stickerPickerScrollView setDocumentView:grid];
    [grid release];
}

-(void)sendSticker:(id)sender {
    NSDictionary *sticker = [[sender cell] representedObject];
    id stickerID = [sticker objectForKey:@"id"];
    DLChannel *channel = [[DLController sharedInstance] selectedChannel];
    if (!stickerID || [stickerID isKindOfClass:[NSNull class]] || !channel) {
        return;
    }
    DLMessage *message = [[DLMessage alloc] init];
    [message setContent:@""];
    [message setOutgoingStickerIDs:[NSArray arrayWithObject:[stickerID description]]];
    [[DLController sharedInstance] sendMessage:message toChannel:channel];
    [message release];
    [stickerPopover close];
    [self.window makeFirstResponder:messageEntryTextView];
}

-(void)reloadEmojiPickerGrid:(id)sender {
    NSView_BGColor *grid = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0, 0, 260, 1)];
    [grid setBackgroundColor:[DLUtil nativeContentColor]];
    NSString *query = [[[emojiPickerSearchField stringValue] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    query = [query stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":"]];
    NSArray *sorted = emojiPickerItems;
    NSMutableArray *visible = [NSMutableArray array];
    NSEnumerator *enumerator = [sorted objectEnumerator];
    NSDictionary *emoji;
    while (emoji = [enumerator nextObject]) {
        NSString *name = [emoji objectForKey:@"name"];
        NSString *searchText = [emoji objectForKey:@"search"];
        BOOL nameMatches = name && [[name lowercaseString] rangeOfString:query].location != NSNotFound;
        BOOL aliasMatches = searchText && [[searchText lowercaseString] rangeOfString:query].location != NSNotFound;
        if (!name || ([query length] > 0 && !nameMatches && !aliasMatches)) {
            continue;
        }
        if ([emoji objectForKey:@"available"] && ![[emoji objectForKey:@"available"] boolValue]) {
            continue;
        }
        [visible addObject:emoji];
        if ([visible count] >= 160) {
            break;
        }
    }
    NSInteger columns = 7;
    NSInteger buttonSize = 34;
    NSInteger rows = MAX(1, ((NSInteger)[visible count] + columns - 1) / columns);
    [grid setFrameSize:NSMakeSize(260, rows * buttonSize + 8)];
    for (NSInteger index = 0; index < (NSInteger)[visible count]; index++) {
        emoji = [visible objectAtIndex:index];
        NSInteger column = index % columns;
        NSInteger row = index / columns;
        NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(6 + column * buttonSize, NSHeight([grid bounds]) - (row + 1) * buttonSize, 30, 30)];
        [button setBezelStyle:NSShadowlessSquareBezelStyle];
        [button setTitle:@""];
        [button setToolTip:[NSString stringWithFormat:@":%@:", [emoji objectForKey:@"name"]]];
        [button setTarget:self];
        [button setAction:@selector(insertCustomEmoji:)];
        [[button cell] setRepresentedObject:emoji];
        NSString *emojiID = [emoji objectForKey:@"id"];
        if (!emojiID) {
            [button setTitle:[emoji objectForKey:@"name"]];
            [button setFont:[NSFont systemFontOfSize:16]];
            [grid addSubview:button];
            [button release];
            continue;
        }
        NSString *emojiURL = [NSString stringWithFormat:@"https://cdn.discordapp.com/emojis/%@.%@?size=32&quality=lossless", emojiID, [[emoji objectForKey:@"animated"] boolValue] ? @"gif" : @"png"];
        NSData *data = [[HTTPCache sharedInstance] cachedDataForURL:emojiURL];
        if (data) {
            NSImage *image = [[[NSImage alloc] initWithData:data] autorelease];
            [image setSize:NSMakeSize(24, 24)];
            [button setImage:image];
            [button setImagePosition:NSImageOnly];
        } else {
            [button setEnabled:NO];
            [button setTitle:@"…"];
            if ([[HTTPCache sharedInstance] beginLoadingURL:emojiURL]) {
                AsyncHTTPGetRequest *request = [[AsyncHTTPGetRequest alloc] init];
                [request setDelegate:self];
                [request setUrl:emojiURL];
                [request setCached:YES];
                [request start];
            }
        }
        [grid addSubview:button];
        [button release];
    }
    if ([visible count] == 0) {
        NSTextField *emptyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 8, 235, 18)];
        [emptyLabel setBordered:NO];
        [emptyLabel setDrawsBackground:NO];
        [emptyLabel setEditable:NO];
        [emptyLabel setAlignment:NSCenterTextAlignment];
        [emptyLabel setTextColor:[DLUtil nativeSecondaryTextColor]];
        [emptyLabel setStringValue:@"No matching emoji"];
        [grid addSubview:emptyLabel];
        [emptyLabel release];
    }
    [emojiPickerScrollView setDocumentView:grid];
    [grid release];
}

-(NSArray *)standardEmojiPickerItems {
    NSArray *definitions = [NSArray arrayWithObjects:
        @"😀\tgrinning face smile 笑顔", @"😃\thappy smile 笑顔", @"😄\tsmile happy joy 笑顔",
        @"😁\tgrin happy にこにこ", @"😆\tlaugh closed eyes 笑い", @"😅\tsweat smile 苦笑い",
        @"😂\ttears joy laugh 笑い", @"😊\tblush smile 笑顔", @"😇\tangel halo 天使",
        @"😉\twink ウインク", @"😌\trelieved calm 安心", @"😍\theart eyes love ハート",
        @"😘\tkiss heart キス", @"😋\tdelicious yum おいしい", @"😜\twink tongue 舌",
        @"😎\tsunglasses cool サングラス", @"😏\tsmirk にやり", @"😒\tunamused 不満",
        @"😔\tpensive sad 悲しい", @"😞\tdisappointed sad 落ち込む", @"😢\tcry sad 泣く",
        @"😭\tloud cry tears 大泣き", @"😤\ttriumph steam ふん", @"😠\tangry 怒り",
        @"😡\trage angry 激怒", @"😱\tscream fear 叫び", @"😳\tflushed surprised 驚き",
        @"😲\tastonished surprise 驚き", @"😵\tdizzy 目が回る", @"😷\tmask sick マスク",
        @"👍\tthumb thumbs up like good いいね", @"👎\tthumb thumbs down bad よくない", @"👌\tokay hand ok オーケー",
        @"✌️\tvictory peace ピース", @"👊\tfist bump punch こぶし", @"✊\traised fist こぶし",
        @"👋\twave hello goodbye 手", @"👏\tclap applause 拍手", @"🙌\traise hands hooray 万歳",
        @"🙏\tpray thanks please お願い", @"💪\tmuscle strong 筋肉", @"👀\teyes look watch 目",
        @"❤️\theart love red ハート", @"💔\tbroken heart 失恋", @"💕\ttwo hearts love ハート",
        @"💖\tsparkling heart ハート", @"💙\tblue heart 青", @"💚\tgreen heart 緑",
        @"💛\tyellow heart 黄色", @"💜\tpurple heart 紫", @"💯\thundred perfect 100 満点",
        @"💥\tboom collision 爆発", @"💦\tsweat drops 汗", @"💤\tsleep zzz 眠る",
        @"🔥\tfire flame 火", @"✨\tsparkles shine キラキラ", @"⭐\tstar favorite 星",
        @"🎉\tparty popper celebrate お祝い", @"🎂\tbirthday cake 誕生日", @"🎁\tgift present プレゼント",
        @"✅\tcheck done yes 完了", @"❌\tcross no wrong バツ", @"⚠️\twarning caution 注意",
        @"❓\tquestion はてな", @"❗\texclamation important びっくり", @"💡\tbulb idea 電球",
        @"🐶\tdog puppy 犬", @"🐱\tcat kitty 猫", @"🐭\tmouse ネズミ",
        @"🐰\trabbit bunny ウサギ", @"🐻\tbear クマ", @"🐼\tpanda パンダ",
        @"🐸\tfrog カエル", @"🐵\tmonkey サル", @"🐧\tpenguin ペンギン",
        @"🍎\tapple red fruit りんご", @"🍊\torange fruit オレンジ", @"🍋\tlemon fruit レモン",
        @"🍌\tbanana fruit バナナ", @"🍉\twatermelon fruit スイカ", @"🍓\tstrawberry fruit いちご",
        @"🍔\tburger food ハンバーガー", @"🍕\tpizza food ピザ", @"🍟\tfries food ポテト",
        @"🍣\tsushi food 寿司", @"🍜\tnoodle ramen ラーメン", @"☕\tcoffee drink コーヒー",
        @"🍺\tbeer drink ビール", @"🌍\tearth world globe 地球", @"☀️\tsun sunny weather 太陽",
        @"☁️\tcloud weather 雲", @"☔\train umbrella weather 雨", @"⛄\tsnowman snow 雪",
        @"🌙\tmoon night 月", @"🌈\trainbow 虹", @"🎵\tmusic note 音楽",
        @"🎮\tgame controller ゲーム", @"📷\tcamera photo カメラ", @"💻\tcomputer laptop パソコン",
        @"📱\tphone mobile 携帯", @"✉️\tmail envelope メール", @"🔔\tbell notification 通知", nil];
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:[definitions count]];
    NSEnumerator *enumerator = [definitions objectEnumerator];
    NSString *definition;
    while (definition = [enumerator nextObject]) {
        NSArray *parts = [definition componentsSeparatedByString:@"\t"];
        if ([parts count] == 2) {
            [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                [parts objectAtIndex:0], @"name", [parts objectAtIndex:1], @"search", nil]];
        }
    }
    return items;
}

-(void)scheduleEmojiPickerReload:(id)sender {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadEmojiPickerGrid:) object:nil];
    [self performSelector:@selector(reloadEmojiPickerGrid:) withObject:nil afterDelay:0.15];
}

-(void)scheduleStickerPickerReload:(id)sender {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadStickerPickerGrid:) object:nil];
    [self performSelector:@selector(reloadStickerPickerGrid:) withObject:nil afterDelay:0.15];
}

-(void)emojiCacheDidUpdate:(NSNotification *)notification {
    if ([emojiPopover isShown]) {
        [self scheduleEmojiPickerReload:nil];
    }
}

-(void)stickerCacheDidUpdate:(NSNotification *)notification {
    if ([stickerPopover isShown]) {
        [self scheduleStickerPickerReload:nil];
    }
}

-(void)popoverDidClose:(NSNotification *)notification {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadEmojiPickerGrid:) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadStickerPickerGrid:) object:nil];
    [reactionPickerChatView release];
    reactionPickerChatView = nil;
    if ([notification object] != emojiPopover &&
        [self.window isKeyWindow] && [messageEntryTextView isEditable]) {
        [self.window makeFirstResponder:messageEntryTextView];
    }
}

-(void)insertCustomEmoji:(id)sender {
    NSDictionary *emoji = [[sender cell] representedObject];
    NSString *emojiID = [emoji objectForKey:@"id"];
    if (reactionPickerChatView) {
        [reactionPickerChatView toggleReactionWithEmoji:emoji];
        [reactionPickerChatView release];
        reactionPickerChatView = nil;
        [emojiPopover close];
        return;
    }
    if (!emojiID) {
        [messageEntryTextView insertText:[emoji objectForKey:@"name"]];
        [emojiPopover close];
        return;
    }
    NSString *emojiURL = [NSString stringWithFormat:@"https://cdn.discordapp.com/emojis/%@.%@?size=32&quality=lossless", emojiID, [[emoji objectForKey:@"animated"] boolValue] ? @"gif" : @"png"];
    NSData *data = [[HTTPCache sharedInstance] cachedDataForURL:emojiURL];
    if (!data) {
        return;
    }
    NSImage *image = [[[NSImage alloc] initWithData:data] autorelease];
    [image setSize:NSMakeSize(18, 18)];
    NSTextAttachmentCell *cell = [[[NSTextAttachmentCell alloc] initImageCell:image] autorelease];
    NSTextAttachment *attachment = [[[NSTextAttachment alloc] init] autorelease];
    [attachment setAttachmentCell:cell];
    NSMutableAttributedString *emojiString = [[[NSMutableAttributedString alloc] initWithAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]] autorelease];
    NSString *prefix = [[emoji objectForKey:@"animated"] boolValue] ? @"<a:" : @"<:";
    NSString *markup = [NSString stringWithFormat:@"%@%@:%@>", prefix, [emoji objectForKey:@"name"], emojiID];
    [emojiString addAttribute:@kCustomEmojiAttribute value:markup range:NSMakeRange(0, [emojiString length])];
    NSRange selectedRange = [messageEntryTextView selectedRange];
    [[messageEntryTextView textStorage] replaceCharactersInRange:selectedRange withAttributedString:emojiString];
    [messageEntryTextView setSelectedRange:NSMakeRange(selectedRange.location + 1, 0)];
    [self textDidChange:nil];
    [emojiPopover close];
    [self.window makeFirstResponder:messageEntryTextView];
}

-(NSString *)serializedComposerContent {
    NSAttributedString *content = [messageEntryTextView textStorage];
    NSMutableString *serialized = [NSMutableString string];
    NSUInteger location = 0;
    while (location < [content length]) {
        NSRange effectiveRange;
        NSDictionary *attributes = [content attributesAtIndex:location effectiveRange:&effectiveRange];
        NSString *customEmoji = [attributes objectForKey:@kCustomEmojiAttribute];
        NSString *mentionUserID = [attributes objectForKey:@kMentionUserIDAttribute];
        if (customEmoji) {
            [serialized appendString:customEmoji];
        } else if (mentionUserID) {
            [serialized appendFormat:@"<@%@>", mentionUserID];
        } else {
            [serialized appendString:[[content string] substringWithRange:effectiveRange]];
        }
        location = NSMaxRange(effectiveRange);
    }
    return serialized;
}

-(NSString *)contentByExpandingCustomEmojiAliases:(NSString *)content {
    NSMutableString *expanded = [[content mutableCopy] autorelease];
    NSEnumerator *enumerator = [[[[DLController sharedInstance] selectedServer] emojis] objectEnumerator];
    NSDictionary *emoji;
    while (emoji = [enumerator nextObject]) {
        NSString *name = [emoji objectForKey:@"name"];
        NSString *emojiID = [emoji objectForKey:@"id"];
        if (!name || !emojiID) {
            continue;
        }
        NSString *alias = [NSString stringWithFormat:@":%@:", name];
        NSString *prefix = [[emoji objectForKey:@"animated"] boolValue] ? @"<a:" : @"<:";
        NSString *markup = [NSString stringWithFormat:@"%@%@:%@>", prefix, name, emojiID];
        [expanded replaceOccurrencesOfString:alias withString:markup options:0 range:NSMakeRange(0, [expanded length])];
    }
    return expanded;
}

-(void)showTagSelectionViewWithContent:(NSArray *)content {
    
    NSInteger limit = 10;
    NSInteger startIndex = 0;
    
    if (content.count > limit) {
        startIndex = content.count - limit;
    }
    
    if (content.count > 0) {
        NSRect frame = [tagSelectionScrollView frame];
        frame.size.width = [messageEntryContainerView frame].size.width;
        frame.origin.y = [messageEntryContainerView frame].size.height;
        frame.origin.x = [messageEntryContainerView frame].origin.x;
        [tagSelectionScrollView setFrame:frame];
        
        if (![tagSelectionScrollView superview]) {
            [self.window.contentView addSubview:tagSelectionScrollView];
        }
        
        NSMutableArray *views = [[NSMutableArray alloc] init];
        for (NSInteger i=startIndex; i<content.count; i++) {
            TagSelectionViewController *view = [[TagSelectionViewController alloc] initWithNibNamed:@"TagSelectionViewController" bundle:nil];
            if (i == content.count - 1) {
                [view setSelected:YES];
            }
            [view setRepresentedObject:[content objectAtIndex:i]];
            [view setDelegate:self];
            [views addObject: view];
            [view release];
        }
        [tagSelectionScrollView setContent:views];
        [views release];
        
        CGFloat newHeight = [[tagSelectionScrollView documentView] frame].size.height + 2;
        if (newHeight > 300) {
            newHeight = 300;
        }
        
        frame = [tagSelectionScrollView frame];
        frame.size.height = newHeight;
        [tagSelectionScrollView setFrame:frame];
        
    } else {
        [tagSelectionScrollView removeFromSuperview];
    }
    [chatScrollView setNeedsDisplay:YES];
    [tagSelectionScrollView setNeedsDisplay:YES];
}

-(void)hideTagSelectionView {
    if ([tagSelectionScrollView superview]) {
        [tagSelectionScrollView removeFromSuperview];
        [chatScrollView setNeedsDisplay:YES];
        [tagSelectionScrollView setNeedsDisplay:YES];
    }
}

-(void)updateTextViewSizing {
    [messageEntryTextView.layoutManager glyphRangeForTextContainer:messageEntryTextView.textContainer];
    NSRect textFrame = [messageEntryTextView.layoutManager usedRectForTextContainer:messageEntryTextView.textContainer];
    if (textFrame.size.height <= 126) {
        NSRect scrollViewFrame = messageEntryScrollView.frame;
        scrollViewFrame.size.height = textFrame.size.height + 8;
        [messageEntryScrollView setFrame:scrollViewFrame];
        NSRect composerFrame = [messageComposerBackgroundView frame];
        composerFrame.size.height = scrollViewFrame.size.height + 16.0;
        [messageComposerBackgroundView setFrame:composerFrame];
        
        CGFloat change = scrollViewFrame.size.height - currentMessageScrollHeight;
        
        if (change) {
            
            NSRect containerFrame = messageEntryContainerView.frame;
            containerFrame.size.height += change;
            [messageEntryContainerView setFrame:containerFrame];
            
            NSRect chatViewFrame = chatScrollView.frame;
            chatViewFrame.size.height -= change;
            chatViewFrame.origin.y += change;
            [chatScrollView setFrame:chatViewFrame];
            
            [chatScrollView setNeedsDisplay:YES];
            [messageEntryContainerView setNeedsDisplay:YES];
        }
        currentMessageScrollHeight = scrollViewFrame.size.height;
    }
}

-(void)updateTypingStatus {
    if (isTyping) {
        isTyping = NO;
        [typingTimer invalidate];
        typingTimer = nil;
    }
}

- (IBAction)removeReferencedMessage:(id)sender {
    [messageEditor removeReferencedMessage];
    [self hideReplyToView];
}

-(BOOL)isEditingTag {
    if (editingLocation == NSNotFound || editingLocation > [[messageEntryTextView string] length]) {
        return NO;
    }
    NSString *textPreSelection = [[messageEntryTextView string] substringToIndex:editingLocation];
    tagIndex = [textPreSelection rangeOfString:@"@" options:NSBackwardsSearch].location;
    return (tagIndex != NSNotFound) && ([[textPreSelection substringFromIndex:tagIndex] rangeOfString:@" "].location == NSNotFound);
}

- (void)alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    if (contextInfo == DLDialogConfirmMessageDelete) {
        if (returnCode == NSAlertSecondButtonReturn) {
            [[DLController sharedInstance] deleteMessage:messagePendingDeletion];
        }
        messagePendingDeletion = nil;
    }
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self clearMessageSearchHighlight];
    [lastMessageSearchQuery release];
    [pendingSearchAuthorName release];
    [messageSearchField release];
    [connectionStatusField release];
    [reloadButton release];
    [threadsButton release];
    [membersButton release];
    [pinsButton release];
    [myProfileButton release];
    [pendingNewMessageStartDate release];
    [firstUnreadMessageID release];
    [historyMessageBannerLabel release];
    [jumpToLatestButton release];
    [historyMessageBanner release];
    [unreadMessageBannerLabel release];
    [markMessagesReadButton release];
    [unreadMessageBanner release];
    [profilePopover close];
    [profilePopover release];
    [profilePopoverController release];
    [profileUser release];
    [profileServer release];
    [profileMember release];
    [profileAvatarButton release];
    [profileDetailAvatarView release];
    [profileAvatarRequests release];
    [profileAvatarCache release];
    [profileBannerImageRequests release];
    [profileBannerImageCache release];
    [profileDataRequests release];
    [profileDataCache release];
    [profileBannerView release];
    [profileBannerImageView release];
    [profileBioField release];
    [profileMetadataField release];
    [profileRoleContainer release];
    [profileStatusBubble release];
    [profileStatusField release];
    [profileDetailBannerView release];
    [profileDetailBannerImageView release];
    [profileDetailBioField release];
    [profileDetailMetadataField release];
    [profileDetailConnectionsField release];
    [profileDetailRoleContainer release];
    [profileDetailStatusBubble release];
    [profileDetailStatusField release];
    [profileBannerURL release];
    if (profileDetailPanel) {
        [self.window removeChildWindow:profileDetailPanel];
        [profileDetailPanel close];
        [profileDetailPanel release];
    }
    [memberAvatarRequests release];
    [memberListItems release];
    [memberListTableView setDelegate:nil];
    [memberListTableView setDataSource:nil];
    [memberListTableView release];
    [memberListScrollView release];
    [memberListPane release];
    [threadListBaseChannel release];
    [threadListItems release];
    [threadListEmptyField release];
    [threadDetailTitleField release];
    [threadListTableView setDelegate:nil];
    [threadListTableView setDataSource:nil];
    [threadListTableView release];
    [threadListScrollView release];
    [threadDetailPane release];
    [threadListPane release];
    [messageSearchResults release];
    [searchResultsTitleField release];
    [searchResultsCountField release];
    [searchEmptyStateField release];
    [searchPreviousButton release];
    [searchNextButton release];
    [searchPageField release];
    [searchResultsTableView setDelegate:nil];
    [searchResultsTableView setDataSource:nil];
    [searchResultsTableView release];
    [searchResultsScrollView release];
    [searchResultsPane release];
    [emojiButton release];
    [stickerButton release];
    [messageComposerBackgroundView release];
    [emojiPickerItems release];
    [emojiPickerSearchField release];
    [emojiPickerScrollView release];
    [emojiPopoverController release];
    [reactionPickerChatView release];
    [emojiPopover release];
    [stickerPickerItems release];
    [stickerPickerSearchField release];
    [stickerPickerScrollView release];
    [stickerPopoverController release];
    [stickerPopover release];
    [friendsHomeChannels release];
    [friendsHomeScrollView release];
    [friendsHomeView release];
    [mainToolbar setDelegate:nil];
    [mainToolbar release];
    NSEnumerator *channelEnumerator = [channelOutlineItems objectEnumerator];
    DLChannel *channel;
    while (channel = [channelEnumerator nextObject]) {
        [channel setDelegate:nil];
        NSEnumerator *childEnumerator = [[channel children] objectEnumerator];
        DLChannel *child;
        while (child = [childEnumerator nextObject]) {
            [child setDelegate:nil];
        }
    }
    [channelOutlineItems release];
    [channelOutlineView setDelegate:nil];
    [channelOutlineView setDataSource:nil];
    [channelOutlineView release];
    NSEnumerator *serverEnumerator = [serverItems objectEnumerator];
    DLServer *server;
    while (server = [serverEnumerator nextObject]) {
        [server setDelegate:nil];
    }
    [serverItems release];
    [serverTableView setDelegate:nil];
    [serverTableView setDataSource:nil];
    [serverTableView release];
    [mainSplitView setDelegate:nil];
    [channelPaneView release];
    [chatPaneView release];
    [mainSplitView release];
    [super dealloc];
}

#pragma mark Delegated Functions

-(void)pendingAttachmentItemWasRemoved:(PendingAttachmentViewController *)item {
    [pendingAttachmentsScrollView removeContent:item];
    if ([pendingAttachmentsScrollView content].count < 1) {
        [self hidePendingAttachmentView];
    }
    
}

-(void)updatePendingAttachmentsWithFilePaths:(NSArray *)paths {
    [self showPendingAttachmentView];
    NSEnumerator *e = [paths objectEnumerator];
    NSString *filepath;
    while (filepath = [e nextObject]) {
        NSData *fileData = [NSData dataWithContentsOfFile:filepath];
        DLAttachment *a = [[DLAttachment alloc] init];
        [a setFilename:[filepath lastPathComponent]];
        [a setMimeType:[DLUtil mimeTypeForExtension:[filepath pathExtension]]];
        [a setAttachmentData:fileData];
        PendingAttachmentViewController *view = [[PendingAttachmentViewController alloc] initWithNibNamed:@"PendingAttachmentViewController" bundle:nil];
        [view setRepresentedObject:a];
        [view setDelegate:self];
        [pendingAttachmentsScrollView appendContent:view];
        [view release];
        [a release];
    }
}

-(void)editorContentDidUpdateWithAttributedString:(NSAttributedString *)as {
    NSMutableAttributedString *merged = [[as mutableCopy] autorelease];
    NSAttributedString *current = [messageEntryTextView textStorage];
    NSUInteger searchLocation = 0;
    for (NSUInteger index = 0; index < [current length]; index++) {
        id customEmoji = [current attribute:@kCustomEmojiAttribute atIndex:index effectiveRange:nil];
        if (!customEmoji) {
            continue;
        }
        NSRange placeholderRange = [[merged string] rangeOfString:@"￼" options:0 range:NSMakeRange(searchLocation, [merged length] - searchLocation)];
        if (placeholderRange.location == NSNotFound) {
            break;
        }
        [merged replaceCharactersInRange:placeholderRange withAttributedString:[current attributedSubstringFromRange:NSMakeRange(index, 1)]];
        searchLocation = placeholderRange.location + 1;
    }
    NSInteger lenChange = [merged length] - [messageEntryTextView string].length;
    NSUInteger tempLoc = editingLocation + lenChange;
    [[messageEntryTextView textStorage] beginEditing];
    [[messageEntryTextView textStorage] setAttributedString:merged];
    [[messageEntryTextView textStorage] endEditing];
    [messageEntryTextView setSelectedRange:NSMakeRange(tempLoc, 0)];
    [self updateTextViewSizing];
}

-(void)chatScrollViewBoundsDidChange:(NSNotification *)note {
    NSClipView *scrolledClipView = [note object];
    [self refreshMessageBannerVisibility];
    if (pendingNewMessageCount > 0 && [self.window isKeyWindow] && [self isViewingLatestMessages]) {
        [self markLatestMessagesRead:nil];
    }
    if (searchHistoryWindowActive && hasMoreNewerMessages && !isLoadingNewerMessages &&
        [scrolledClipView bounds].origin.y <= 1.0 && firstMessage) {
        isLoadingNewerMessages = YES;
        [[DLController sharedInstance] loadMessagesForChannel:[[DLController sharedInstance] selectedChannel]
                                                afterMessage:firstMessage
                                                    quantity:25];
    }
    if ([chatScrollView.documentView bounds].size.height <= [scrolledClipView bounds].size.height + [scrolledClipView bounds].origin.y) {
        if (!isLoadingMessages) {
            isLoadingMessages = YES;
            if ([[DLController sharedInstance] selectedChannel]) {
                [[DLController sharedInstance] loadMessagesForChannel:[[DLController sharedInstance] selectedChannel] beforeMessage:lastMessage quantity:25];
            }
        }
    }
}

-(void)initialDataWasReceived {
    [NSThread detachNewThreadSelector:@selector(populateUserServers) toTarget:self withObject:nil];
    [self loadMainContent];
}

-(void)requestDidFailWithError:(DLError *)e {
    [messageSearchField setToolTip:nil];
    if (pinsPaneActive) {
        [searchResultsCountField setStringValue:@"Unable to load pinned messages"];
    }
    [DLErrorHandler displayError:e onWindow:self.window];
}

-(void)channelPins:(NSArray *)messages didLoadForChannel:(DLChannel *)channel {
    if (!pinsPaneActive || ![[[DLController sharedInstance] selectedChannel] isEqual:channel]) return;
    [messageSearchResults release];
    messageSearchResults = [[NSArray alloc] initWithArray:messages];
    [searchResultsTableView reloadData];
    [searchResultsTableView deselectAll:self];
    [searchResultsCountField setStringValue:[NSString stringWithFormat:@"%ld pinned message%@",
                                              (long)[messages count], [messages count] == 1 ? @"" : @"s"]];
    [searchEmptyStateField setStringValue:@"No pinned messages"];
    [searchEmptyStateField setHidden:([messages count] != 0)];
    [self loadVisibleSearchResultAvatars];
}

-(void)messageSearchResults:(NSArray *)messages totalResults:(NSInteger)total offset:(NSInteger)offset forChannel:(DLChannel *)channel query:(NSString *)query {
    if (![[[DLController sharedInstance] selectedChannel] isEqual:channel] ||
        ![query isEqualToString:lastMessageSearchQuery]) {
        return;
    }
    [messageSearchResults release];
    messageSearchResults = [[NSArray alloc] initWithArray:messages];
    messageSearchOffset = offset;
    messageSearchTotal = total;
    [searchResultsCountField setFont:[NSFont systemFontOfSize:10.0]];
    [searchResultsCountField setTextColor:[DLUtil nativeSecondaryTextColor]];
    NSString *countText = nil;
    if (total > (NSInteger)[messages count]) {
        countText = [NSString stringWithFormat:@"Showing %ld of %ld results",
                     (long)[messages count], (long)total];
    } else {
        countText = [NSString stringWithFormat:@"%ld result%@",
                     (long)[messages count], [messages count] == 1 ? @"" : @"s"];
    }
    [searchResultsCountField setStringValue:countText];
    [searchResultsTableView reloadData];
    [searchResultsTableView deselectAll:self];
    [searchEmptyStateField setStringValue:@"No matching messages"];
    [searchEmptyStateField setHidden:([messages count] != 0)];
    NSInteger pageCount = MAX(1, (total + 24) / 25);
    NSInteger currentPage = MIN(pageCount, offset / 25 + 1);
    [searchPageField setStringValue:[NSString stringWithFormat:@"%ld / %ld", (long)currentPage, (long)pageCount]];
    [searchPreviousButton setEnabled:(offset > 0)];
    [searchNextButton setEnabled:(offset + (NSInteger)[messages count] < total)];
    [messageSearchField setToolTip:[messages count] == 0 ? @"No matching messages" : nil];
    [self setSearchResultsPaneVisible:YES];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadVisibleSearchResultAvatars) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadSearchResultsTable) object:nil];
    [self performSelector:@selector(loadVisibleSearchResultAvatars) withObject:nil afterDelay:0.35];
}

-(void)messages:(NSArray *)messages receivedAroundSearchResult:(NSString *)messageID forChannel:(DLChannel *)channel {
    if (![[[DLController sharedInstance] selectedChannel] isEqual:channel]) {
        return;
    }

    NSMutableArray *views = [NSMutableArray arrayWithCapacity:[messages count]];
    ChatItemViewController *targetView = nil;
    lastMessage = nil;
    firstMessage = nil;
    NSEnumerator *enumerator = [messages objectEnumerator];
    DLMessage *message;
    while (message = [enumerator nextObject]) {
        if (![message serverID] && [channel serverID]) {
            [message setServerID:[channel serverID]];
        }
        ChatItemViewController *view = [[[ChatItemViewController alloc] initWithNibNamed:@"ChatItemViewController" bundle:nil] autorelease];
        [view setDelegate:self];
        [view setRepresentedObject:message];
        if ([[message author] isEqual:[[DLController sharedInstance] myUser]]) {
            [view setIsMyContent:YES];
        }
        [views addObject:view];
        if (!firstMessage) {
            firstMessage = message;
        }
        lastMessage = message;
        if ([[[message messageID] description] isEqualToString:messageID]) {
            targetView = view;
        }
    }

    [self clearMessageSearchHighlight];
    [chatScrollView setContent:views];
    [chatScrollView screenResize];
    [chatHeaderLabel setStringValue:[channel name]];
    [chatHeaderImage setImage:[[[NSImage alloc] initWithData:[channel subImageData]] autorelease]];
    NSInteger channelRow = [channelOutlineView rowForItem:channel];
    if (channelRow >= 0) {
        updatingChannelOutlineSelection = YES;
        [channelOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:channelRow] byExtendingSelection:NO];
        updatingChannelOutlineSelection = NO;
    }
    if (targetView) {
        highlightedSearchResult = targetView;
        [highlightedSearchResult setSearchHighlighted:YES];
        [self performSelector:@selector(animatedScrollToChatView:) withObject:targetView afterDelay:0.01];
    }
    [messageSearchField setToolTip:nil];
    searchHistoryWindowActive = YES;
    hasMoreNewerMessages = YES;
    isLoadingNewerMessages = NO;
    isLoadingMessages = NO;
}

-(void)user:(DLUser *)u avatarDidUpdateWithData:(NSData *)data {
    if ([u isEqual:[[DLController sharedInstance] myUser]]) {
        [myUserAvatarImage setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:data] autorelease] newSize:myUserAvatarImage.frame.size cornerRadius:MY_USER_AVATAR_RADIUS]];
    } else if (memberListVisible) {
        [memberListTableView reloadData];
    }
    if (profileUser && [u isEqual:profileUser]) {
        [self requestProfileAvatarForUser:u size:72.0 radius:36.0];
        if (profileDetailPanel) {
            [self requestProfileAvatarForUser:u size:128.0 radius:64.0];
        }
    }
}

-(void)serverItemWasSelected:(ServerItemViewController *)item {
    [self selectServer:[item representedObject]];
}

-(void)serverItemHoverActiveWithDetailView:(NSView *)detail atPoint:(CGPoint)p {
    NSRect r = [serversScrollView documentVisibleRect];
    
    [detail setFrame:NSMakeRect(p.x, p.y - r.origin.y, detail.frame.size.width, detail.frame.size.height)];
    [self.window.contentView addSubview:detail];
}

-(void)channelItemWasSelected:(ChannelItemViewController *)item {
    [self selectChannel:[item representedObject]];
}
-(void)dmChannelItemWasSelected:(DirectMessageItemViewController *)item {
    [self selectChannel:[item representedObject]];
}

-(void)tagSelectionItemWasSelected:(TagSelectionViewController *)item {
    NSEnumerator *e = [[tagSelectionScrollView content] objectEnumerator];
    TagSelectionViewController *itm;
    while (itm = [e nextObject]) {
        if (item != itm) {
            [itm setSelected:NO];
        }
    }
    [messageEditor addMentionedUser:[item representedObject] byReplacingStringInRange:NSMakeRange(tagIndex, editingLocation - tagIndex)];
    [self hideTagSelectionView];
}

-(void)messages:(NSArray *)messages receivedForChannel:(DLChannel *)c {
    BOOL newChannel = YES;
    NSMutableArray *views = [[NSMutableArray alloc] init];
    NSMutableDictionary *existingViewsByMessageID = [NSMutableDictionary dictionary];
    NSEnumerator *existingEnumerator = [[chatScrollView content] objectEnumerator];
    ChatItemViewController *existingView;
    while (existingView = [existingEnumerator nextObject]) {
        NSString *messageID = [[[existingView representedObject] messageID] description];
        if (messageID) {
            [existingViewsByMessageID setObject:existingView forKey:messageID];
        }
    }
    NSEnumerator *e = [messages objectEnumerator];
    DLMessage *item;
    if (lastMessage) {
        newChannel = NO;
    }
    while (item = [e nextObject]) {
        if (![[[DLController sharedInstance] selectedServer] isEqual:[[DLController sharedInstance] myServerItem]]) {
            [item setServerID:[[[DLController sharedInstance] selectedServer] serverID]];
        }
        NSString *messageID = [[item messageID] description];
        ChatItemViewController *view = messageID ? [existingViewsByMessageID objectForKey:messageID] : nil;
        BOOL createdView = (view == nil);
        if (createdView) {
            view = [[ChatItemViewController alloc] initWithNibNamed:@"ChatItemViewController" bundle:nil];
            [view setDelegate:self];
        }
        [view setRepresentedObject:item];
        if ([[item author] isEqual:[[DLController sharedInstance] myUser]]) {
            [view setIsMyContent:YES];
        }
        [views addObject:view];
        if (newChannel && !firstMessage) {
            firstMessage = item;
        }
        lastMessage = item;
        if (createdView) {
            [view release];
        }
    }
    if (newChannel) {
        searchHistoryWindowActive = NO;
        hasMoreNewerMessages = NO;
        isLoadingNewerMessages = NO;
        [chatHeaderLabel setStringValue:[c name]];
        [chatHeaderImage setImage:[[[NSImage alloc] initWithData:[c subImageData]] autorelease]];
        [chatScrollView setContent:views];
        [[chatScrollView contentView] scrollToPoint: NSMakePoint(chatScrollView.frame.origin.x, chatScrollView.frame.origin.y)];
        [chatScrollView reflectScrolledClipView: [chatScrollView contentView]];
        if ([c hasUnreadMessages] || [c mentionCount] > 0) {
            [[DLController sharedInstance] acknowledgeMessage:[c lastMessage]];
        }
    } else {
        [chatScrollView appendContent:views];
    }
    [views release];
    [reloadButton setEnabled:YES];
    isLoadingMessages = NO;
}

-(void)newerMessages:(NSArray *)messages receivedForChannel:(DLChannel *)channel {
    if (!searchHistoryWindowActive || ![[[DLController sharedInstance] selectedChannel] isEqual:channel]) {
        isLoadingNewerMessages = NO;
        return;
    }
    if ([messages count] == 0) {
        hasMoreNewerMessages = NO;
        isLoadingNewerMessages = NO;
        return;
    }

    NSMutableSet *existingIDs = [NSMutableSet set];
    NSEnumerator *existingEnumerator = [[chatScrollView content] objectEnumerator];
    ChatItemViewController *existingView;
    while (existingView = [existingEnumerator nextObject]) {
        NSString *existingID = [[[[existingView representedObject] messageID] description] copy];
        if (existingID) {
            [existingIDs addObject:existingID];
            [existingID release];
        }
    }
    NSMutableArray *views = [NSMutableArray array];
    NSEnumerator *messageEnumerator = [messages objectEnumerator];
    DLMessage *message;
    while (message = [messageEnumerator nextObject]) {
        if ([existingIDs containsObject:[[message messageID] description]]) {
            continue;
        }
        ChatItemViewController *view = [[[ChatItemViewController alloc] initWithNibNamed:@"ChatItemViewController" bundle:nil] autorelease];
        [view setDelegate:self];
        [view setRepresentedObject:message];
        if ([[message author] isEqual:[[DLController sharedInstance] myUser]]) {
            [view setIsMyContent:YES];
        }
        [views addObject:view];
    }
    if ([messages count] > 0) {
        firstMessage = [messages objectAtIndex:0];
    }
    [chatScrollView prependContent:views preservingVisiblePosition:YES];
    isLoadingNewerMessages = NO;
}


-(void)newMessage:(DLMessage *)m receivedForChannel:(DLChannel *)c inServer:(DLServer *)s {
    if (![s isEqual:[[DLController sharedInstance] myServerItem]]) {
        [m setServerID:[s serverID]];
    }
    
    if ([c isEqual:[[DLController sharedInstance] selectedChannel]]) {
        BOOL isMyMessage = [[m author] isEqual:[[DLController sharedInstance] myUser]];
        BOOL wasViewingLatest = [self isViewingLatestMessages];
        BOOL shouldPreservePosition = !isMyMessage && !wasViewingLatest;
        BOOL shouldRecordUnread = !isMyMessage &&
            (![self.window isKeyWindow] || !wasViewingLatest);
        ChatItemViewController *view = [[[ChatItemViewController alloc] initWithNibNamed:@"ChatItemViewController" bundle:nil] autorelease];
        [view setRepresentedObject:m];
        [view setDelegate:self];
        if (isMyMessage) {
            [view setIsMyContent:YES];
        }
        [chatScrollView prependContent:[NSArray arrayWithObject:view]
             preservingVisiblePosition:shouldPreservePosition];
        firstMessage = m;
        [[m author] setTyping:NO];
        [self userDidStopTyping:[m author]];
        if (isMyMessage || (wasViewingLatest && [self.window isKeyWindow])) {
            NSPoint latestPoint = [[chatScrollView contentView] bounds].origin;
            latestPoint.y = 0.0;
            [[chatScrollView contentView] scrollToPoint:latestPoint];
            [chatScrollView reflectScrolledClipView:[chatScrollView contentView]];
            [[DLController sharedInstance] acknowledgeMessage:m];
            if (isMyMessage && pendingNewMessageCount > 0) {
                [self resetUnreadMessageState];
            }
        } else if (shouldRecordUnread) {
            [c setHasUnreadMessages:YES];
            if (s && ![s isEqual:[[DLController sharedInstance] myServerItem]]) {
                [s setHasUnreadMessages:YES];
            }
            [self recordUnreadMessage:m];
        }
    }
    
    BOOL mentioned = NO;
    NSEnumerator *e = [[m mentionedUsers] objectEnumerator];
    DLUser *user;
    if (![[m author] isEqual:[[DLController sharedInstance] myUser]]) {
        while (user = [e nextObject]) {
            if ([user isEqual:[[DLController sharedInstance] myUser]]) {
                mentioned = YES;
            }
        }
        if ([m mentionedEveryone]) {
            mentioned = YES;
        }
        
        if (mentioned || [c isKindOfClass:[DLDirectMessageChannel class]]) {
            if ([[[DLController sharedInstance] selectedChannel] isEqual:c]) {
                if (![self.window isKeyWindow]) {
                    [c notifyOfNewMention];
                    [s notifyOfNewMention];
                    [[DLAudioPlayer sharedInstance] playAudioWithID:AudioIDNotificationNewMention];
                }
            } else {
                [c notifyOfNewMention];
                [s notifyOfNewMention];
                [[DLAudioPlayer sharedInstance] playAudioWithID:AudioIDNotificationNewMention];
            }
        }
    }
    
    if (![c isEqual:[[DLController sharedInstance] selectedChannel]]) {
        [c setHasUnreadMessages:YES];
        if (![s isEqual:[[DLController sharedInstance] myServerItem]]) {
            [s setHasUnreadMessages:YES];
        }
    }
    
    if ([s isEqual:[[DLController sharedInstance] myServerItem]] && [[[DLController sharedInstance] selectedServer] isEqual:[[DLController sharedInstance] myServerItem]]) {
        [NSThread detachNewThreadSelector:@selector(loadDirectMessageChannels) toTarget:self withObject:nil];
    }
}

-(void)didLogoutSuccessfully {
    [delegate logoutWasSuccessful];
}

-(void)updateTypingString {
    if (typingUsers.count > 0) {
        NSString *typingString = @"";
        [typingStatusTextField setHidden:NO];
        if (typingUsers.count == 1) {
            typingString = [NSString stringWithFormat:@"%@ is Typing...", [[typingUsers objectAtIndex:0] globalName]];
        } else if (typingUsers.count < 4) {
            for (int i = 0; i<typingUsers.count; i++) {
                if (i < typingUsers.count - 1) {
                    typingString = [typingString stringByAppendingString:[NSString stringWithFormat:@"%@", [[typingUsers objectAtIndex:i] globalName]]];
                    if (i < typingUsers.count - 2) {
                        typingString = [typingString stringByAppendingString:@", "];
                    } else {
                        typingString = [typingString stringByAppendingString:@" "];
                    }
                } else {
                    typingString = [typingString stringByAppendingString:[NSString stringWithFormat:@"and %@ are Typing...", [[typingUsers objectAtIndex:i] globalName]]];
                }
            }
        } else {
            typingString = @"Several People are Typing...";
        }
        [typingStatusTextField setStringValue:typingString];
    } else {
        [typingStatusTextField setHidden:YES];
    }
}

-(void)userDidStartTypingInSelectedChannel:(DLUser *)u {
    [u setTypingDelegate:self];
    if (![typingUsers containsObject:u]) {
        [typingUsers addObject:u];
    }
    [self updateTypingString];
}

-(void)userDidStopTyping:(DLUser *)u {
    [typingUsers removeObject:u];
    [self updateTypingString];
}

-(void)members:(NSArray *)members didUpdateForServer:(DLServer *)s {
    memberRequestInFlight = NO;
    NSEnumerator *receivedMemberEnumerator = [members objectEnumerator];
    DLServerMember *receivedMember;
    while (receivedMember = [receivedMemberEnumerator nextObject]) {
        NSString *userID = [[[receivedMember user] userID] description];
        if (userID) {
            if ([s memberWithUserID:userID]) [s replaceMember:receivedMember];
            else [s addMember:receivedMember];
            if (profileUser && [userID isEqualToString:[[profileUser userID] description]] &&
                profileServer && [profileServer isEqual:s]) {
                [profileMember release];
                profileMember = [receivedMember retain];
                [self updateVisibleProfileData];
            }
        }
    }
    if (memberListVisible && [s isEqual:[[DLController sharedInstance] selectedServer]]) {
        [self refreshMemberList];
    }
    if (pendingSearchAuthorName && [s isEqual:[[DLController sharedInstance] selectedServer]]) {
        NSInteger requestedOffset = pendingSearchAuthorOffset;
        DLUser *matchedUser = [self searchUserMatchingName:pendingSearchAuthorName inMembers:members];
        NSString *unmatchedName = [pendingSearchAuthorName copy];
        [pendingSearchAuthorName release];
        pendingSearchAuthorName = nil;
        if (matchedUser) {
            [self performMessageSearchAtOffset:requestedOffset];
        } else {
            [self showNoSearchUserNamed:unmatchedName];
        }
        [unmatchedName release];
    }
    if ([self isEditingTag]) {
        NSMutableArray *users = [[NSMutableArray alloc] init];
        NSEnumerator *e = [members objectEnumerator];
        DLServerMember *m;
        while (m = [e nextObject]) {
            [users addObject:[m user]];
        }
        [self showTagSelectionViewWithContent:users];
    }
}

-(void)chatView:(ChatItemViewController *)chatView showProfileForUser:(DLUser *)user relativeToView:(NSView *)anchorView {
    NSRect anchorRect = [anchorView convertRect:[anchorView bounds] toView:chatScrollView];
    [self showProfileForUser:user relativeToRect:anchorRect ofView:chatScrollView];
}

-(void)addReferencedMessage:(DLMessage *)m {
    if (![[[DLController sharedInstance] selectedServer] isEqual:[[DLController sharedInstance] myServerItem]]) {
        [m setServerID:[[[DLController sharedInstance] selectedServer] serverID]];
    }
    [messageEditor setReferencedMessage:m];
    NSString *baseString = [NSString stringWithFormat:@"Replying to %@", [[m author] globalName]];
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:baseString];
    [as addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:13] range:[baseString rangeOfString:[[m author] globalName]]];
    [replyToTextField setAttributedStringValue:as];
    [self showReplyToView];
}
-(BOOL)chatViewShouldBeginEditing:(ChatItemViewController *)chatView {
    [chatScrollView endAllChatContentEditing];
    [chatView becomeWindowFirstResponderForEditing:self.window];
    return YES;
}
-(void)chatViewUpdatedWithEnteredText:(ChatItemViewController *)chatView {
    [chatScrollView screenResize];
}

-(void)chatViewContentWasUpdated:(ChatItemViewController *)chatView {
    [chatScrollView performSelector:@selector(screenResize) withObject:nil afterDelay:0.5];
}

-(void)chatView:(ChatItemViewController *)chatView showReactionPickerRelativeToView:(NSView *)anchorView {
    [reactionPickerChatView release];
    reactionPickerChatView = [chatView retain];
    [self showEmojiMenu:anchorView];
}

-(void)chatView:(ChatItemViewController *)chatView didEndEditingWithCommit:(BOOL)didCommit {
    if (didCommit) {
        [[DLController sharedInstance] submitEditedMessage:[chatView representedObject]];
    } else {
        [chatScrollView performSelector:@selector(screenResize) withObject:nil afterDelay:0.5];
    }
    [self.window makeFirstResponder:messageEntryTextView];
}

-(void)chatViewMessageShouldBeDeleted:(ChatItemViewController *)chatView {
    messagePendingDeletion = [chatView representedObject];
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Delete Message"];
    [alert setInformativeText:@"Are you sure you want to delete the selected message?"];
    [alert addButtonWithTitle:@"No"];
    [alert addButtonWithTitle:@"Yes"];
    [alert beginSheetModalForWindow:self.window modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:DLDialogConfirmMessageDelete];
}

-(void)chatViewMessageWasDeleted:(ChatItemViewController *)chatView {
    if (highlightedSearchResult == chatView) {
        [self clearMessageSearchHighlight];
        lastMessageSearchIndex = -1;
    }
    [chatScrollView removeViewController:chatView];
}

#pragma mark Text View Delegated Functions

- (BOOL)textView:(NSTextView *)aTextView doCommandBySelector:(SEL)aSelector
{
    if (aSelector == @selector(insertNewline:)) {
        NSEvent * event = [NSApp currentEvent];
        if ((event.modifierFlags & NSShiftKeyMask) != NSShiftKeyMask) {
            if ([tagSelectionScrollView superview]) {
                DLUser *selectedUser = nil;
                NSEnumerator *e = [[tagSelectionScrollView content] objectEnumerator];
                TagSelectionViewController *vc;
                while (vc = [e nextObject]) {
                    if ([vc isSelected]) {
                        selectedUser = [vc representedObject];
                        [messageEditor addMentionedUser:selectedUser byReplacingStringInRange:NSMakeRange(tagIndex, editingLocation - tagIndex)];
                    }
                }
                [self hideTagSelectionView];
            } else {
                
                NSEnumerator *e = [[pendingAttachmentsScrollView content] objectEnumerator];
                PendingAttachmentViewController *vc;
                while (vc = [e nextObject]) {
                    [messageEditor addAttachment:[vc representedObject]];
                }
                DLMessage *toSend = [messageEditor finalizedMessage];
                [toSend setContent:[self serializedComposerContent]];
                [[DLController sharedInstance] sendMessage:toSend toChannel:[[DLController sharedInstance] selectedChannel]];
                [toSend release];
                [messageEditor clear];
                [messageEntryTextView setString:@""];
                [self textDidChange:nil];
                [self hidePendingAttachmentView];
                [self hideReplyToView];
            }
            
            return YES;
        }
    }
    if(aSelector == @selector(moveUp:)){
        if ([tagSelectionScrollView superview]) {
            NSInteger selectedIndex = [tagSelectionScrollView content].count;
            for (NSInteger i=[tagSelectionScrollView content].count - 1; i >= 0; i--) {
                if ([[[tagSelectionScrollView content] objectAtIndex:i] isSelected]) {
                    selectedIndex = i;
                }
                [[[tagSelectionScrollView content] objectAtIndex:i] setSelected:NO];
            }
            if (selectedIndex == 0) {
                selectedIndex = [tagSelectionScrollView content].count;
            }
            TagSelectionViewController *item = [[tagSelectionScrollView content] objectAtIndex:selectedIndex - 1];
            [item setSelected:YES];
        } else {
            [chatScrollView endAllChatContentEditing];
            NSEnumerator *e = [[chatScrollView content] reverseObjectEnumerator];
            ChatItemViewController *item;
            while (item = [e nextObject]) {
                if ([[[item representedObject] author] isEqual:[[DLController sharedInstance] myUser]]) {
                    [item beginEditingContent];
                    [item becomeWindowFirstResponderForEditing:self.window];
                }
            }
        }
        return YES;
    }
    if(aSelector == @selector(moveDown:)){
        NSInteger selectedIndex = -1;
        for (NSInteger i = 0; i < [tagSelectionScrollView content].count; i++) {
            if ([[[tagSelectionScrollView content] objectAtIndex:i] isSelected]) {
                selectedIndex = i;
            }
            [[[tagSelectionScrollView content] objectAtIndex:i] setSelected:NO];
        }
        if (selectedIndex == [tagSelectionScrollView content].count - 1) {
            selectedIndex = -1;
        }
        TagSelectionViewController *item = [[tagSelectionScrollView content] objectAtIndex:selectedIndex + 1];
        [item setSelected:YES];
        return YES;
    }
    return NO;
}
-(void)textViewDidChangeSelection:(NSNotification *)notification {
    editingLocation = [[[messageEntryTextView selectedRanges] objectAtIndex:0] rangeValue].location;
    
    [messageEntryTextView setTypingAttributes:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[DLTextParser DEFAULT_TEXT_COLOR], [messageEntryTextView backgroundColor], nil] forKeys:[NSArray arrayWithObjects:NSForegroundColorAttributeName, NSBackgroundColorAttributeName, nil]]];
    
    if ([self isEditingTag]) {
        NSString *textPreSelection = [[messageEntryTextView string] substringToIndex:editingLocation];
        tagIndex = [textPreSelection rangeOfString:@"@" options:NSBackwardsSearch].location;
        NSString *enteredUsername = [textPreSelection substringFromIndex:tagIndex];
        if ([[[DLController sharedInstance] selectedServer] isEqual:[[DLController sharedInstance] myServerItem]]) {
            if ([enteredUsername isEqualToString:@"@"]) {
                [self showTagSelectionViewWithContent:[(DLDirectMessageChannel *)[[DLController sharedInstance] selectedChannel] recipients]];
            } else {
                [self showTagSelectionViewWithContent:[[[DLController sharedInstance] selectedChannel] recipientsWithUsernameContainingString:[enteredUsername substringFromIndex:1]]];
            }
        } else {
            if ([enteredUsername isEqualToString:@"@"]) {
                NSMutableArray *users = [[NSMutableArray alloc] init];
                NSEnumerator *e = [[[[DLController sharedInstance] selectedServer] members] objectEnumerator];
                DLServerMember *m;
                while (m = [e nextObject]) {
                    if (![[m user] isEqual:[[DLController sharedInstance] myUser]]) {
                        [users addObject:[m user]];
                    }
                }
                [self showTagSelectionViewWithContent:users];
            } else {
                [[DLController sharedInstance] queryServer:[[DLController sharedInstance] selectedServer] forMembersContainingUsername:[enteredUsername substringFromIndex:1]];
            }
        }
    } else {
        [self hideTagSelectionView];
    }
}

- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(NSString *)replacementString {
    if ((NSInteger)affectedCharRange.location <= (NSInteger)([messageEntryTextView string].length - 1)) {
        NSDictionary *attributes = [[messageEntryTextView textStorage] attributesAtIndex:affectedCharRange.location effectiveRange:nil];
        if ([[attributes objectForKey:@kTagAttribute] boolValue]) {
            if ([[messageEntryTextView string] characterAtIndex:affectedCharRange.location] == '@') {
                if ([replacementString isEqualToString:@""]) {
                    madeMentionChange = YES;
                }
            } else {
                madeMentionChange = YES;
            }
        }
    }
    return YES;
}

-(void)textDidChange:(NSNotification *)notification {
    [messageEditor setContent:[messageEntryTextView string]];
    if (madeMentionChange) {
        [messageEditor removeMentionedUserAtStringIndex:tagIndex];
        madeMentionChange = NO;
    }
    
    [self updateTextViewSizing];
    
    if (!isTyping && (![[messageEntryTextView string] isEqualToString:@""])) {
        [[DLController sharedInstance] informTypingInChannel:[[DLController sharedInstance] selectedChannel]];
        isTyping = YES;
        typingTimer = [NSTimer scheduledTimerWithTimeInterval:TYPING_SEND_INTERVAL target:self selector:@selector(updateTypingStatus) userInfo:nil repeats:NO];
    }
}

-(void)userProfile:(NSDictionary *)profile didLoadForUser:(DLUser *)user inServer:(DLServer *)server {
    NSString *key = [self profileDataCacheKeyForUser:user server:server];
    [profileDataRequests removeObject:key];
    if (profile) {
        [profileDataCache setObject:profile forKey:key];
    }
    if (profileUser && [[profileUser userID] isEqualToString:[user userID]] &&
        [[self profileDataCacheKeyForUser:profileUser server:profileServer] isEqualToString:key]) {
        if (profile) {
            [self updateVisibleProfileData];
        } else {
            [profileBioField setStringValue:@""];
            [profileMetadataField setStringValue:@""];
            [profileDetailBioField setStringValue:@""];
            [profileDetailMetadataField setStringValue:@""];
            NSString *status = [self profileCustomStatusFromData:[NSDictionary dictionary]];
            [profileStatusField setStringValue:status ? status : @""];
            [profileStatusBubble setHidden:status == nil];
            [profileDetailStatusField setStringValue:status ? status : @""];
            [profileDetailStatusBubble setHidden:status == nil];
        }
    }
}

-(void)requestDidFinishLoading:(AsyncHTTPRequest *)request {
    if ([request result] != HTTPResultOK) {
        [[HTTPCache sharedInstance] endLoadingURL:[request url]];
    }
    [request release];
}

@end
