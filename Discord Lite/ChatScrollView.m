//
//  ChatScrollView.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/2/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "ChatScrollView.h"

extern NSString * const DLMessageActionBarDidShowNotification;
extern NSString * const DLMessageActionBarDidHideNotification;

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
    NSRect frame = [self.contentView frame];
    frame.size.height = 100;
    [self.documentView setFrame: frame];
    unreadSeparatorView = [[DLUnreadSeparatorView alloc] initWithFrame:NSMakeRect(0.0, 0.0, NSWidth(frame), 18.0)];
    [unreadSeparatorView setAutoresizingMask:NSViewWidthSizable];
    [unreadSeparatorView setHidden:YES];
    [self.documentView addSubview:unreadSeparatorView];
}
-(void)messageActionBarDidShow:(NSNotification *)notification {
    ChatItemViewController *item = [notification object];
    if (![content containsObject:item]) {
        return;
    }
    if (visibleActionBarItem && visibleActionBarItem != item) {
        [visibleActionBarItem hideMessageActionBar];
    }
    visibleActionBarItem = item;
}
-(void)messageActionBarDidHide:(NSNotification *)notification {
    if (visibleActionBarItem == [notification object]) {
        visibleActionBarItem = nil;
    }
}
-(void)setDelegate:(id<ChatScrollViewDelegate>)inDelegate {
    delegate = inDelegate;
}
-(NSArray *)content {
    return content;
}
-(void)screenResize {
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
        currentHeight += [item expectedHeight];
    }
    [self updateUnreadSeparatorPosition];
    [self.documentView setNeedsDisplay:YES];
}
-(void)setContent:(NSArray *)inContent {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(screenResize) object:nil];
    visibleActionBarItem = nil;
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
        CGFloat expectedHeight = [item expectedHeight];
        NSRect itemFrame = item.view.frame;
        height += expectedHeight;
        itemFrame.size.height = expectedHeight;
        itemFrame.size.width = [self.documentView frame].size.width;
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
}
-(void)appendContent:(NSArray *)inContent {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(screenResize) object:nil];
    [content addObjectsFromArray:inContent];
    [self updateMessageGroups];
    CGFloat height = [self.documentView frame].size.height;
    NSEnumerator *e = [inContent objectEnumerator];
    ChatItemViewController *item;
    while (item = [e nextObject]) {
        CGFloat expectedHeight = [item expectedHeight];
        NSRect itemFrame = item.view.frame;
        height += expectedHeight;
        itemFrame.size.height = expectedHeight;
        itemFrame.size.width = [self.documentView frame].size.width;
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
}
-(void)prependViewController:(ChatItemViewController *)vc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(screenResize) object:nil];
    [content insertObject:vc atIndex:0];
    [self updateMessageGroups];
    CGFloat expectedHeight = [vc expectedHeight];
    NSRect itemFrame = vc.view.frame;
    itemFrame.size.height = expectedHeight;
    itemFrame.size.width = [self.contentView frame].size.width;
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
        visibleActionBarItem = nil;
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [unreadStartMessageID release];
    [unreadSeparatorView release];
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
