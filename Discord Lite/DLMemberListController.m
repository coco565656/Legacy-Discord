//
//  DLMemberListController.m
//  Legacy Discord
//

#import "DLMemberListController.h"
#import "ChatScrollView.h"
#import "DLController.h"
#import "DLServer.h"
#import "DLServerChannel.h"
#import "DLServerMember.h"
#import "DLUtil.h"
#import "NSView+BGColor.h"
#import "NSView+Border.h"
#import "NSScroller+BGColor.h"
#import "DLTwemojiRenderer.h"

@interface DLMemberListCell : NSCell {
    DLServerMember *representedMember;
    DLServer *representedServer;
}
-(void)setRepresentedMember:(DLServerMember *)member;
-(void)setRepresentedServer:(DLServer *)server;
@end

@implementation DLMemberListCell

-(void)setRepresentedMember:(DLServerMember *)member {
    representedMember = member;
}

-(void)setRepresentedServer:(DLServer *)server {
    representedServer = server;
}

-(void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    // The table uses NSTableViewSelectionHighlightStyleNone: the Aqua
    // highlight turns light gray whenever the table is not key, which made
    // white member names unreadable. Draw the same rounded selection as the
    // channel list instead.
    NSInteger row = [(NSTableView *)controlView rowAtPoint:NSMakePoint(NSMidX(cellFrame), NSMidY(cellFrame))];
    if (row >= 0 && [[(NSTableView *)controlView selectedRowIndexes] containsIndex:(NSUInteger)row]) {
        NSRect selectionRect = NSInsetRect(NSIntersectionRect(cellFrame, [controlView visibleRect]), 6.0, 2.0);
        [[DLUtil nativeSelectionColor] set];
        [[NSBezierPath bezierPathWithRoundedRect:selectionRect xRadius:5.0 yRadius:5.0] fill];
    }
    cellFrame = NSIntersectionRect(cellFrame, [controlView visibleRect]);
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
    NSColor *nameColor = [DLUtil roleColorForRoleIDs:[representedMember roles] inServer:representedServer];
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [style setLineBreakMode:NSLineBreakByTruncatingTail];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont systemFontOfSize:11.0], NSFontAttributeName,
                                (nameColor ? nameColor : [DLUtil nativePrimaryTextColor]), NSForegroundColorAttributeName,
                                style, NSParagraphStyleAttributeName, nil];
    NSMutableAttributedString *displayName = [[[NSMutableAttributedString alloc]
        initWithString:(name ? name : @"") attributes:attributes] autorelease];
    [DLTwemojiRenderer replaceEmojiInAttributedString:displayName size:11.0
                                   excludingAttribute:nil recordingAttribute:nil cursorLocation:NULL];
    [displayName drawInRect:NSMakeRect(NSMaxX(avatarRect) + 8.0, NSMidY(cellFrame) - 8.0,
                                NSWidth(cellFrame) - NSMaxX(avatarRect) - 16.0, 17.0)
        ];
}

@end

@interface DLMemberListController ()
-(void)installPane;
-(void)boundsDidChange:(NSNotification *)notification;
-(void)requestNextPageIfNeeded;
-(void)layoutPanes;
-(void)hostFrameDidChange:(NSNotification *)notification;
@end

@implementation DLMemberListController

-(id)initWithHostView:(NSView *)inHostView
       chatScrollView:(ChatScrollView *)inChatScrollView
         composerView:(NSView *)inComposerView
         toggleButton:(NSButton *)inToggleButton {
    self = [super init];
    if (self) {
        hostView = [inHostView retain];
        chatScrollView = [inChatScrollView retain];
        composerView = [inComposerView retain];
        toggleButton = [inToggleButton retain];
        items = [[NSArray alloc] init];
        avatarRequests = [[NSMutableSet alloc] init];
        requestedUpperBound = 99;
        [self installPane];
        [hostView setPostsFrameChangedNotifications:YES];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(hostFrameDidChange:)
                                                     name:NSViewFrameDidChangeNotification object:hostView];
    }
    return self;
}

-(void)setDelegate:(id<DLMemberListControllerDelegate>)inDelegate {
    delegate = inDelegate;
}

-(BOOL)isVisible {
    return visible;
}

-(void)installPane {
    CGFloat paneWidth = 220.0;
    NSRect bounds = [hostView bounds];
    pane = [[NSView_BGColor alloc] initWithFrame:
            NSMakeRect(NSWidth(bounds) - paneWidth, 0.0, paneWidth, NSHeight(bounds) - 42.0)];
    [pane setAutoresizingMask:NSViewMinXMargin | NSViewHeightSizable];
    [pane setBackgroundColor:[DLUtil nativeSidebarColor]];
    [pane setLeftBorderColor:[DLUtil nativeBorderColor]];

    titleField = [[NSTextField alloc] initWithFrame:
                  NSMakeRect(12.0, NSHeight([pane bounds]) - 30.0, paneWidth - 24.0, 18.0)];
    [titleField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [titleField setBezeled:NO];
    [titleField setDrawsBackground:NO];
    [titleField setEditable:NO];
    [titleField setSelectable:NO];
    [titleField setFont:[NSFont boldSystemFontOfSize:10.0]];
    [titleField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [titleField setStringValue:@"MEMBERS"];
    [pane addSubview:titleField];

    scrollView = [[NSScrollView alloc] initWithFrame:
                  NSMakeRect(0.0, 0.0, paneWidth, NSHeight(bounds) - 76.0)];
    [scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [scrollView setBorderType:NSNoBorder];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setAutohidesScrollers:YES];
    [scrollView setDrawsBackground:YES];
    [scrollView setBackgroundColor:[DLUtil nativeSidebarColor]];
    NSScroller_BGColor *memberScroller = [[[NSScroller_BGColor alloc] initWithFrame:NSZeroRect] autorelease];
    [memberScroller setBackgroundColor:[DLUtil nativeSidebarColor]];
    [scrollView setVerticalScroller:memberScroller];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"member"] autorelease];
    [column setWidth:paneWidth];
    [column setResizingMask:NSTableColumnAutoresizingMask];
    [column setDataCell:[[[DLMemberListCell alloc] init] autorelease]];
    tableView = [[NSTableView alloc] initWithFrame:[[scrollView contentView] bounds]];
    [tableView setFocusRingType:NSFocusRingTypeNone];
    [scrollView setFocusRingType:NSFocusRingTypeNone];
    [tableView addTableColumn:column];
    [tableView setHeaderView:nil];
    [tableView setDataSource:self];
    [tableView setDelegate:self];
    [tableView setRowHeight:40.0];
    [tableView setIntercellSpacing:NSMakeSize(0.0, 0.0)];
    [tableView setAllowsEmptySelection:YES];
    [tableView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleNone];
    [tableView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [scrollView setDocumentView:tableView];
    [[scrollView contentView] setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(boundsDidChange:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:[scrollView contentView]];
    [pane addSubview:scrollView];
    [hostView addSubview:pane];
    [pane setHidden:YES];
}

-(void)refreshForServer:(DLServer *)server {
    [displayedServer release];
    displayedServer = [server retain];
    NSArray *newItems = server ? [[server members] sortedArrayUsingSelector:@selector(compareDisplayName:)] : [NSArray array];
    [items release];
    items = [newItems retain];
    [tableView reloadData];
    NSInteger loadCount = MIN((NSInteger)[items count], 20);
    for (NSInteger index = 0; index < loadCount; index++) {
        DLServerMember *member = [items objectAtIndex:index];
        DLUser *user = [member user];
        NSString *userID = [[user userID] description];
        if (userID && ![avatarRequests containsObject:userID]) {
            [avatarRequests addObject:userID];
            [user setDelegate:self];
            [user loadAvatarData];
        }
    }
}

-(void)setVisible:(BOOL)shouldShow server:(DLServer *)server channel:(DLChannel *)channel {
    if (shouldShow == visible) return;
    if (shouldShow) {
        [displayedChannel release];
        displayedChannel = [channel retain];
        [self refreshForServer:server];
        requestedUpperBound = 99;
        requestInFlight = NO;
        if (server && channel && ![server isEqual:[[DLController sharedInstance] myServerItem]]) {
            requestInFlight = YES;
            [[DLController sharedInstance] requestMembersForChannel:channel inServer:server from:0 to:99];
        }
        [pane setHidden:NO];
    } else {
        [pane setHidden:YES];
        [displayedChannel release];
        displayedChannel = nil;
    }
    visible = shouldShow;
    [self layoutPanes];
    [toggleButton setState:(shouldShow ? NSOnState : NSOffState)];
}

-(void)layoutPanes {
    CGFloat hostWidth = NSWidth([hostView bounds]);
    CGFloat paneWidth = visible ? MIN(220.0, MAX(0.0, hostWidth - 180.0)) : 0.0;
    NSRect paneFrame = [pane frame];
    paneFrame.origin.x = hostWidth - paneWidth;
    paneFrame.size.width = paneWidth;
    [pane setFrame:paneFrame];
    NSRect chatFrame = [chatScrollView frame];
    NSRect entryFrame = [composerView frame];
    chatFrame.size.width = hostWidth - paneWidth;
    entryFrame.size.width = hostWidth - paneWidth;
    [chatScrollView setFrame:chatFrame];
    [composerView setFrame:entryFrame];
    [chatScrollView screenResize];
}

-(void)hostFrameDidChange:(NSNotification *)notification {
    if (visible) [self layoutPanes];
}

-(void)boundsDidChange:(NSNotification *)notification {
    if (!visible) return;
    NSClipView *clipView = [notification object];
    if (NSHeight([tableView bounds]) - NSMaxY([clipView bounds]) < 120.0) {
        [self requestNextPageIfNeeded];
    }
}

-(void)requestNextPageIfNeeded {
    if (requestInFlight || requestedUpperBound >= 499 || !displayedServer || !displayedChannel) return;
    if ([displayedServer isEqual:[[DLController sharedInstance] myServerItem]]) return;
    NSInteger start = requestedUpperBound + 1;
    NSInteger end = MIN(start + 99, 499);
    requestedUpperBound = end;
    requestInFlight = YES;
    [[DLController sharedInstance] requestMembersForChannel:displayedChannel
                                                  inServer:displayedServer from:start to:end];
}

-(void)members:(NSArray *)members didUpdateForServer:(DLServer *)server {
    requestInFlight = NO;
    NSEnumerator *enumerator = [members objectEnumerator];
    DLServerMember *member;
    while (member = [enumerator nextObject]) {
        NSString *userID = [[[member user] userID] description];
        if (userID) {
            if ([server memberWithUserID:userID]) [server replaceMember:member];
            else [server addMember:member];
        }
    }
    if (visible && [server isEqual:displayedServer]) [self refreshForServer:server];
}

-(NSInteger)numberOfRowsInTableView:(NSTableView *)inTableView {
    return [items count];
}

-(id)tableView:(NSTableView *)inTableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    DLServerMember *member = [items objectAtIndex:row];
    DLUser *user = [member user];
    return [user globalName] ? [user globalName] : [user username];
}

-(void)tableView:(NSTableView *)inTableView willDisplayCell:(id)cell
  forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if ([cell isKindOfClass:[DLMemberListCell class]]) {
        [(DLMemberListCell *)cell setRepresentedMember:[items objectAtIndex:row]];
        [(DLMemberListCell *)cell setRepresentedServer:displayedServer];
    }
}

-(NSString *)tableView:(NSTableView *)inTableView toolTipForCell:(NSCell *)cell
                  rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)column
                   row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation {
    if (row < 0 || row >= (NSInteger)[items count]) return nil;
    DLServerMember *member = [items objectAtIndex:row];
    DLUser *user = [member user];
    return [user globalName] ? [user globalName] : [user username];
}

-(void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = [tableView selectedRow];
    if (row < 0 || row >= (NSInteger)[items count]) return;
    DLServerMember *member = [items objectAtIndex:row];
    DLUser *user = [member user];
    [delegate memberListController:self didSelectUser:user
                    relativeToRect:[tableView rectOfRow:row] ofView:tableView];
}

-(void)user:(DLUser *)user avatarDidUpdateWithData:(NSData *)data {
    if (visible) [tableView reloadData];
    if ([delegate respondsToSelector:@selector(memberListController:avatarDidUpdateForUser:)]) {
        [delegate memberListController:self avatarDidUpdateForUser:user];
    }
}

-(void)applyCurrentTheme {
    [(NSView_BGColor *)pane setBackgroundColor:[DLUtil nativeSidebarColor]];
    [(NSView_BGColor *)pane setLeftBorderColor:[DLUtil nativeBorderColor]];
    [titleField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [scrollView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [(NSScroller_BGColor *)[scrollView verticalScroller] setBackgroundColor:[DLUtil nativeSidebarColor]];
    [tableView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [tableView reloadData];
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [tableView setDelegate:nil];
    [tableView setDataSource:nil];
    delegate = nil;
    [displayedChannel release];
    [displayedServer release];
    [avatarRequests release];
    [items release];
    [titleField release];
    [tableView release];
    [scrollView release];
    [pane release];
    [toggleButton release];
    [composerView release];
    [chatScrollView release];
    [hostView release];
    [super dealloc];
}

@end
