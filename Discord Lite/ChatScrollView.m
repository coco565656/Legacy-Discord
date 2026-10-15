//
//  ChatScrollView.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/2/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "ChatScrollView.h"
#import "DLUtil.h"
#import "HTTPCache.h"
#if LEGACY_DISCORD_UI_DIAGNOSTICS
#import "DLUIDiagnostics.h"
#endif

extern NSString * const DLMessageActionBarDidShowNotification;
extern NSString * const DLMessageActionBarDidHideNotification;

@class ChatScrollView;

@interface DLSharedMessageActionBar : NSView {
    ChatScrollView *owner;
    NSTrackingArea *trackingArea;
}
-(void)setOwner:(ChatScrollView *)inOwner;
@end

@interface ChatScrollView (MessageActionBarPrivate)
-(void)messageActionBarMouseEntered;
-(void)messageActionBarMouseExited;
-(void)hideSharedMessageActionBar;
-(void)showSharedMessageActionBarForItem:(ChatItemViewController *)item;
@end

@implementation DLSharedMessageActionBar

-(void)setOwner:(ChatScrollView *)inOwner {
    owner = inOwner;
}

-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = NSInsetRect([self bounds], 0.5, 0.5);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:7.0 yRadius:7.0];
    [[DLUtil nativeChromeColor] set];
    [path fill];
    [[DLUtil nativeBorderColor] set];
    [path setLineWidth:1.0];
    [path stroke];
}

-(void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (trackingArea) {
        [self removeTrackingArea:trackingArea];
        [trackingArea release];
        trackingArea = nil;
    }
    if ([self window]) {
        NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited |
            NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect;
        trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                   options:options
                                                     owner:self
                                                  userInfo:nil];
        [self addTrackingArea:trackingArea];
    }
}

-(void)mouseEntered:(NSEvent *)event {
    [owner messageActionBarMouseEntered];
}

-(void)mouseExited:(NSEvent *)event {
    [owner messageActionBarMouseExited];
}

-(void)dealloc {
    if (trackingArea) {
        [self removeTrackingArea:trackingArea];
        [trackingArea release];
    }
    [super dealloc];
}

@end

@interface DLUnreadSeparatorView : NSView
@end

@implementation DLUnreadSeparatorView

-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    NSColor *red = [NSColor colorWithCalibratedRed:0.88 green:0.20 blue:0.22 alpha:1.0];
    [red set];
    NSRectFill(NSMakeRect(0.0, floor(NSMidY(bounds)), NSWidth(bounds) - 38.0, 1.0));
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont boldSystemFontOfSize:9.0], NSFontAttributeName,
                                red, NSForegroundColorAttributeName, nil];
    [@"NEW" drawAtPoint:NSMakePoint(MAX(2.0, NSWidth(bounds) - 34.0),
                                    floor(NSMidY(bounds) - 6.0))
          withAttributes:attributes];
}

@end

@implementation ChatScrollView

const NSTimeInterval MESSAGE_GROUP_INTERVAL = 7.0 * 60.0;

-(void)updateUnreadSeparatorPosition {
    BOOL foundUnreadStart = NO;
    if (unreadStartMessageID) {
        NSEnumerator *enumerator = [content objectEnumerator];
        ChatItemViewController *item;
        while (item = [enumerator nextObject]) {
            NSString *messageID = [[item representedObject] messageID];
            if ([[messageID description] isEqualToString:unreadStartMessageID]) {
                CGFloat separatorY = NSMaxY([[item view] frame]) - 9.0;
                [unreadSeparatorView setFrame:NSMakeRect(0.0, separatorY,
                                                          NSWidth([self.documentView bounds]), 18.0)];
                [unreadSeparatorView setHidden:NO];
                [self.documentView addSubview:unreadSeparatorView positioned:NSWindowAbove relativeTo:nil];
                foundUnreadStart = YES;
                break;
            }
        }
    }
    if (!foundUnreadStart) {
        [unreadSeparatorView setHidden:YES];
    }
}

-(BOOL)date:(NSDate *)date isSameDayAsDate:(NSDate *)otherDate {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSUInteger units = NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit;
    NSDateComponents *components = [calendar components:units fromDate:date];
    NSDateComponents *otherComponents = [calendar components:units fromDate:otherDate];
    return [components year] == [otherComponents year] &&
           [components month] == [otherComponents month] &&
           [components day] == [otherComponents day];
}

-(BOOL)message:(DLMessage *)message canFollowMessageInGroup:(DLMessage *)olderMessage {
    if (!message || !olderMessage || [message referencedMessage] || [olderMessage referencedMessage]) {
        return NO;
    }
    if (![[message author] isEqual:[olderMessage author]]) {
        return NO;
    }
    NSTimeInterval interval = [[message timestamp] timeIntervalSinceDate:[olderMessage timestamp]];
    if (interval < 0 || interval > MESSAGE_GROUP_INTERVAL) {
        return NO;
    }
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSUInteger units = NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit;
    NSDateComponents *messageDate = [calendar components:units fromDate:[message timestamp]];
    NSDateComponents *olderDate = [calendar components:units fromDate:[olderMessage timestamp]];
    return [messageDate year] == [olderDate year] &&
           [messageDate month] == [olderDate month] &&
           [messageDate day] == [olderDate day];
}

-(void)updateMessageGroups {
    NSInteger count = [content count];
    for (NSInteger index = 0; index < count; index++) {
        ChatItemViewController *item = [content objectAtIndex:index];
        BOOL compact = NO;
        if (index + 1 < count) {
            ChatItemViewController *olderItem = [content objectAtIndex:index + 1];
            compact = [self message:[item representedObject] canFollowMessageInGroup:[olderItem representedObject]];
        }
        [item setCompactDisplay:compact];
        BOOL groupedFollower = NO;
        if (index > 0) {
            ChatItemViewController *newerItem = [content objectAtIndex:index - 1];
            groupedFollower = [self message:[newerItem representedObject] canFollowMessageInGroup:[item representedObject]];
        }
        [item setGroupedMessageFollows:groupedFollower];
        NSDate *dividerDate = nil;
        if (index + 1 < count) {
            NSDate *date = [(DLMessage *)[item representedObject] timestamp];
            ChatItemViewController *olderItem = [content objectAtIndex:index + 1];
            NSDate *olderDate = [(DLMessage *)[olderItem representedObject] timestamp];
            if (date && olderDate && ![self date:date isSameDayAsDate:olderDate]) dividerDate = date;
        }
        [item setDateDividerDate:dividerDate];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    // Drawing code here.
}
-(void)awakeFromNib {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(screenResize) name:NSWindowDidResizeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messageActionBarDidShow:) name:DLMessageActionBarDidShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messageActionBarDidHide:) name:DLMessageActionBarDidHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messageActionBarCacheDidUpdate:) name:HTTPCacheDataDidUpdateNotification object:nil];
    [[self contentView] setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contentViewBoundsDidChange:) name:NSViewBoundsDidChangeNotification object:[self contentView]];
    NSRect frame = [self.contentView frame];
    frame.size.height = 100;
    [self.documentView setFrame: frame];
    unreadSeparatorView = [[DLUnreadSeparatorView alloc] initWithFrame:NSMakeRect(0.0, 0.0, NSWidth(frame), 18.0)];
    [unreadSeparatorView setAutoresizingMask:NSViewWidthSizable];
    [unreadSeparatorView setHidden:YES];
    [self.documentView addSubview:unreadSeparatorView];
    sharedMessageActionBar = [[DLSharedMessageActionBar alloc] initWithFrame:NSMakeRect(0.0, 0.0, 188.0, 30.0)];
    [(DLSharedMessageActionBar *)sharedMessageActionBar setOwner:self];
    [sharedMessageActionBar setHidden:YES];
    [[self contentView] addSubview:sharedMessageActionBar];
    [[self window] setAcceptsMouseMovedEvents:YES];
    [self updateTrackingAreas];
}
-(void)messageActionBarDidShow:(NSNotification *)notification {
    ChatItemViewController *item = [notification object];
    [self showSharedMessageActionBarForItem:item];
}
-(void)showSharedMessageActionBarForItem:(ChatItemViewController *)item {
    if (![content containsObject:item]) {
        return;
    }
    if (visibleActionBarItem == item && ![sharedMessageActionBar isHidden]) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideSharedMessageActionBar) object:nil];
        return;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideSharedMessageActionBar) object:nil];
    visibleActionBarItem = item;
    [item populateMessageActionBar:sharedMessageActionBar];
    NSRect visibleBounds = [[self contentView] bounds];
    NSRect itemRect = [[self contentView] convertRect:[[item view] bounds] fromView:[item view]];
    NSRect actionFrame = [sharedMessageActionBar frame];
    actionFrame.origin.x = MAX(NSMinX(visibleBounds) + 4.0,
                               NSMaxX(visibleBounds) - NSWidth(actionFrame) - 4.0);
    actionFrame.origin.y = NSMaxY(itemRect) - NSHeight(actionFrame) - 1.0;
    actionFrame.origin.y = MAX(NSMinY(visibleBounds) + 4.0,
                               MIN(actionFrame.origin.y,
                                   NSMaxY(visibleBounds) - NSHeight(actionFrame) - 4.0));
    [sharedMessageActionBar setFrame:actionFrame];
    [sharedMessageActionBar setHidden:NO];
    [[self contentView] addSubview:sharedMessageActionBar positioned:NSWindowAbove relativeTo:nil];
}
-(void)messageActionBarDidHide:(NSNotification *)notification {
    if (visibleActionBarItem == [notification object]) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideSharedMessageActionBar) object:nil];
        [self performSelector:@selector(hideSharedMessageActionBar) withObject:nil afterDelay:0.10];
    }
}
-(void)messageActionBarMouseEntered {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideSharedMessageActionBar) object:nil];
}
-(void)messageActionBarMouseExited {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideSharedMessageActionBar) object:nil];
    [self performSelector:@selector(hideSharedMessageActionBar) withObject:nil afterDelay:0.08];
}
-(void)messageActionBarCacheDidUpdate:(NSNotification *)notification {
    if (visibleActionBarItem && ![sharedMessageActionBar isHidden]) {
        [visibleActionBarItem refreshMessageActionBar:sharedMessageActionBar];
    }
}
-(void)contentViewBoundsDidChange:(NSNotification *)notification {
    [self hideSharedMessageActionBar];
}
-(void)hideSharedMessageActionBar {
    [sharedMessageActionBar setHidden:YES];
    visibleActionBarItem = nil;
}
-(void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [[self window] setAcceptsMouseMovedEvents:YES];
    [self updateTrackingAreas];
}
-(void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (messageHoverTrackingArea) {
        [[self contentView] removeTrackingArea:messageHoverTrackingArea];
        [messageHoverTrackingArea release];
        messageHoverTrackingArea = nil;
    }
    if ([self window] && [self contentView]) {
        NSTrackingAreaOptions options = NSTrackingMouseMoved |
            NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect;
        messageHoverTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                               options:options
                                                                 owner:self
                                                              userInfo:nil];
        [[self contentView] addTrackingArea:messageHoverTrackingArea];
    }
}
-(void)mouseMoved:(NSEvent *)event {
    NSPoint clipPoint = [[self contentView] convertPoint:[event locationInWindow] fromView:nil];
    if (![sharedMessageActionBar isHidden] && NSPointInRect(clipPoint, [sharedMessageActionBar frame])) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideSharedMessageActionBar) object:nil];
        return;
    }

    NSPoint documentPoint = [[self documentView] convertPoint:[event locationInWindow] fromView:nil];
    NSEnumerator *enumerator = [content objectEnumerator];
    ChatItemViewController *item;
    while (item = [enumerator nextObject]) {
        if (NSPointInRect(documentPoint, [[item view] frame])) {
            [self showSharedMessageActionBarForItem:item];
            return;
        }
    }
    [self hideSharedMessageActionBar];
}
-(void)setDelegate:(id<ChatScrollViewDelegate>)inDelegate {
    delegate = inDelegate;
}
-(NSArray *)content {
    return content;
}
-(void)screenResize {
    [self hideSharedMessageActionBar];
    [self updateMessageGroups];
    CGFloat currentHeight = 0;
    NSEnumerator *e = [content objectEnumerator];
    ChatItemViewController *item;
    while (item = [e nextObject]) {
        currentHeight += [item expectedHeight];
    }
    NSRect frame = [self.documentView frame];
    frame.size.height = currentHeight;
    [self.documentView setFrame: frame];
    currentHeight = 0;
    e = [content objectEnumerator];
    while (item = [e nextObject]) {
        NSRect itemFrame = item.view.frame;
        itemFrame.size.height = [item expectedHeight];
        itemFrame.origin.y = currentHeight;
        item.view.frame = itemFrame;
        [item layoutForCurrentViewFrame];
        [item.view setNeedsDisplay:YES];
#if LEGACY_DISCORD_UI_DIAGNOSTICS
        [DLUIDiagnostics recordEvent:@"message-row-layout-pass" details:[NSDictionary dictionaryWithObjectsAndKeys:
                                          [NSNumber numberWithDouble:[item expectedHeight]], @"expected_height",
                                          [NSNumber numberWithDouble:NSHeight([item.view frame])], @"actual_height", nil]];
#endif
        currentHeight += [item expectedHeight];
    }
    [self updateUnreadSeparatorPosition];
    [self.documentView setNeedsDisplay:YES];
#if LEGACY_DISCORD_UI_DIAGNOSTICS
    [DLUIDiagnostics recordEvent:@"message-layout" details:[NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSNumber numberWithUnsignedInteger:[content count]], @"message_count",
                                      [NSNumber numberWithDouble:NSWidth([self.documentView bounds])], @"width",
                                      [NSNumber numberWithDouble:NSHeight([self.documentView bounds])], @"height", nil]];
#endif
}
-(void)refreshVisibleMessageHeaderLayouts {
    NSRect visibleRect = [[self documentView] convertRect:[[self contentView] bounds]
                                                 fromView:[self contentView]];
    NSEnumerator *enumerator = [content objectEnumerator];
    ChatItemViewController *item;
    while (item = [enumerator nextObject]) {
        if (NSIntersectsRect(visibleRect, [[item view] frame])) {
            [item refreshMessageHeaderLayout];
        }
    }
}
-(void)setContent:(NSArray *)inContent {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(screenResize) object:nil];
    [self hideSharedMessageActionBar];
    NSEnumerator *e = [content objectEnumerator];
    ChatItemViewController *item;
    while (item = [e nextObject]) {
        [item stopAnimatedEmojiPlayback];
        [item.view removeFromSuperview];
    }
    [content release];
    content = [[NSMutableArray alloc] initWithArray:inContent];
    [self updateMessageGroups];
    CGFloat height = 0;
    e = [content reverseObjectEnumerator];
    while (item = [e nextObject]) {
        // Give the row its real width first so its text wraps as it will be
        // shown; measuring at the nib's width under-counted wrapped lines.
        NSRect itemFrame = item.view.frame;
        itemFrame.size.width = [self.documentView frame].size.width;
        item.view.frame = itemFrame;
        [item layoutForCurrentViewFrame];
        CGFloat expectedHeight = [item expectedHeight];
        height += expectedHeight;
        itemFrame.size.height = expectedHeight;
        itemFrame.origin.y = [self.documentView frame].size.height - height;
        item.view.frame = itemFrame;
        [item layoutForCurrentViewFrame];
        [self.documentView addSubview:item.view];
        [item.view setNeedsDisplay:YES];
    }
    NSRect frame = [self.documentView frame];
    frame.origin.x = self.frame.origin.x;
    frame.origin.y = self.frame.origin.y;
    frame.size.height = height;
    [self.documentView setFrame: frame];
    [self.documentView setNeedsDisplay:YES];
#if LEGACY_DISCORD_UI_DIAGNOSTICS
    [DLUIDiagnostics recordEvent:@"message-set-content" details:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInteger:[content count]] forKey:@"message_count"]];
#endif
}
-(void)appendContent:(NSArray *)inContent {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(screenResize) object:nil];
    [content addObjectsFromArray:inContent];
    [self updateMessageGroups];
    CGFloat height = [self.documentView frame].size.height;
    NSEnumerator *e = [inContent objectEnumerator];
    ChatItemViewController *item;
    while (item = [e nextObject]) {
        // Give the row its real width first so its text wraps as it will be
        // shown; measuring at the nib's width under-counted wrapped lines.
        NSRect itemFrame = item.view.frame;
        itemFrame.size.width = [self.documentView frame].size.width;
        item.view.frame = itemFrame;
        [item layoutForCurrentViewFrame];
        CGFloat expectedHeight = [item expectedHeight];
        height += expectedHeight;
        itemFrame.size.height = expectedHeight;
        itemFrame.origin.y = [self.documentView frame].size.height - height;
        item.view.frame = itemFrame;
        [item layoutForCurrentViewFrame];
        [self.documentView addSubview:item.view];
        [item.view setNeedsDisplay:YES];
    }
    
    NSRect frame = [self.documentView frame];
    frame.origin.x = self.frame.origin.x;
    frame.origin.y = self.frame.origin.y;
    frame.size.height = height;
    [self.documentView setFrame: frame];
    [self.documentView setNeedsDisplay:YES];
    [self screenResize];
#if LEGACY_DISCORD_UI_DIAGNOSTICS
    [DLUIDiagnostics recordEvent:@"message-append-content" details:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInteger:[inContent count]] forKey:@"added_count"]];
#endif
}
-(void)prependContent:(NSArray *)inContent preservingVisiblePosition:(BOOL)preservePosition {
    if ([inContent count] == 0) {
        return;
    }
    NSPoint oldOrigin = [[self contentView] bounds].origin;
    CGFloat insertedHeight = 0.0;
    NSEnumerator *enumerator = [inContent objectEnumerator];
    ChatItemViewController *item;
    while (item = [enumerator nextObject]) {
        insertedHeight += [item expectedHeight];
        [[self documentView] addSubview:[item view]];
    }
    NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [inContent count])];
    [content insertObjects:inContent atIndexes:indexes];
    [self screenResize];
    if (preservePosition) {
        CGFloat maximumY = MAX(0.0, NSHeight([[self documentView] frame]) - NSHeight([[self contentView] bounds]));
        oldOrigin.y = MIN(maximumY, oldOrigin.y + insertedHeight);
        [[self contentView] scrollToPoint:oldOrigin];
        [self reflectScrolledClipView:[self contentView]];
    }
#if LEGACY_DISCORD_UI_DIAGNOSTICS
    [DLUIDiagnostics recordEvent:@"message-prepend-content" details:[NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSNumber numberWithUnsignedInteger:[inContent count]], @"added_count",
                                      [NSNumber numberWithBool:preservePosition], @"preserved_scroll_position", nil]];
#endif
}
-(void)prependViewController:(ChatItemViewController *)vc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(screenResize) object:nil];
    [content insertObject:vc atIndex:0];
    [self updateMessageGroups];
    NSRect itemFrame = vc.view.frame;
    itemFrame.size.width = [self.contentView frame].size.width;
    vc.view.frame = itemFrame;
    [vc layoutForCurrentViewFrame];
    CGFloat expectedHeight = [vc expectedHeight];
    itemFrame.size.height = expectedHeight;
    itemFrame.origin.y = 0;
    vc.view.frame = itemFrame;
    [vc layoutForCurrentViewFrame];
    [vc.view setNeedsDisplay:YES];
    NSRect frame = [self.documentView frame];
    frame.size.height += expectedHeight;
    [self.documentView setFrame: frame];
    [self.documentView addSubview:vc.view];
    [self performSelector:@selector(screenResize) withObject:nil afterDelay:0.12];
}
-(void)removeViewController:(ChatItemViewController *)vc {
    if (visibleActionBarItem == vc) {
        [self hideSharedMessageActionBar];
    }
    [vc.view removeFromSuperview];
    [content removeObject:vc];
    [self updateMessageGroups];
    [self screenResize];
}
-(void)endAllChatContentEditing {
    NSEnumerator *e = [content objectEnumerator];
    ChatItemViewController *item;
    while (item = [e nextObject]) {
        [item endEditingContent];
    }
}
-(void)setUnreadStartMessageID:(NSString *)messageID {
    if (unreadStartMessageID != messageID) {
        [unreadStartMessageID release];
        unreadStartMessageID = [messageID copy];
    }
    [self updateUnreadSeparatorPosition];
}
-(void)clearUnreadSeparator {
    [unreadStartMessageID release];
    unreadStartMessageID = nil;
    [unreadSeparatorView setHidden:YES];
}
-(void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideSharedMessageActionBar) object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [unreadStartMessageID release];
    [unreadSeparatorView release];
    if (messageHoverTrackingArea) {
        [[self contentView] removeTrackingArea:messageHoverTrackingArea];
        [messageHoverTrackingArea release];
    }
    [(DLSharedMessageActionBar *)sharedMessageActionBar setOwner:nil];
    [sharedMessageActionBar release];
    [super dealloc];
}

#pragma mark File Dragging Functions

- (NSDragOperation)draggingEntered:(id < NSDraggingInfo >)sender {
    return NSDragOperationCopy;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pboard = [sender draggingPasteboard];
    NSArray *filenames = [pboard propertyListForType:NSFilenamesPboardType];
    if (filenames.count > 0) {
        [delegate updatePendingAttachmentsWithFilePaths:filenames];
        return YES;
    }
    return NO;
}

@end
