//
//  DLMemberListController.m
//  Legacy Discord
//

#import "DLMemberListController.h"
#import "DLLocalization.h"
#import "ChatScrollView.h"
#import "DLController.h"
#import "DLDarkMenu.h"
#import "DLServerMenuController.h"
#import "DLServer.h"
#import "DLServerChannel.h"
#import "DLServerMember.h"
#import "DLUtil.h"
#import "DLMainWindowChromeControls.h"
#import "DLPreferencesHandler.h"
#import "NSView+BGColor.h"
#import "NSView+Border.h"
#import "NSScroller+BGColor.h"
#import "DLTwemojiRenderer.h"

static const CGFloat DLMemberRowHeight = 44.0;
static const CGFloat DLMemberGroupRowHeight = 30.0;

@interface DLMemberListCell : NSCell {
    DLServerMember *representedMember;
    DLServer *representedServer;
    NSString *groupTitle;
}
-(void)setRepresentedMember:(DLServerMember *)member;
-(void)setRepresentedServer:(DLServer *)server;
// Non-nil for a group header row ("ROLE — 3").
-(void)setGroupTitle:(NSString *)title;
@end

@implementation DLMemberListCell

-(void)setRepresentedMember:(DLServerMember *)member {
    representedMember = member;
}

-(void)setRepresentedServer:(DLServer *)server {
    representedServer = server;
}

-(void)setGroupTitle:(NSString *)title {
    groupTitle = title;
}

-(void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (groupTitle) {
        NSMutableParagraphStyle *headerStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
        [headerStyle setLineBreakMode:NSLineBreakByTruncatingTail];
        NSDictionary *headerAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                          [NSFont boldSystemFontOfSize:10.0], NSFontAttributeName,
                                          [DLUtil nativeSecondaryTextColor], NSForegroundColorAttributeName,
                                          headerStyle, NSParagraphStyleAttributeName, nil];
        NSMutableAttributedString *header = [[[NSMutableAttributedString alloc] initWithString:groupTitle attributes:headerAttributes] autorelease];
        [DLTwemojiRenderer replaceEmojiInAttributedString:header size:10.0
                                       excludingAttribute:nil recordingAttribute:nil cursorLocation:NULL];
        // Headers sit near the bottom of their row, just above the first member.
        CGFloat headerY = [controlView isFlipped] ? NSMaxY(cellFrame) - 20.0 : NSMinY(cellFrame) + 6.0;
        [header drawInRect:NSMakeRect(NSMinX(cellFrame) + 16.0, headerY, NSWidth(cellFrame) - 28.0, 14.0)];
        return;
    }
    // The table uses NSTableViewSelectionHighlightStyleNone: the Aqua
    // highlight turns light gray whenever the table is not key, which made
    // white member names unreadable. Draw the same rounded selection as the
    // channel list instead.
    NSInteger row = [(NSTableView *)controlView rowAtPoint:NSMakePoint(NSMidX(cellFrame), NSMidY(cellFrame))];
    BOOL selectedRow = row >= 0 && [[(NSTableView *)controlView selectedRowIndexes] containsIndex:(NSUInteger)row];
    BOOL hoveredMemberRow = row >= 0 && [controlView isKindOfClass:[DLContextTableView class]] &&
                            row == [(DLContextTableView *)controlView hoveredRow];
    if (selectedRow || hoveredMemberRow) {
        NSRect selectionRect = NSInsetRect(NSIntersectionRect(cellFrame, [controlView visibleRect]), 6.0, 2.0);
        [(selectedRow ? [DLUtil nativeSelectionColor] : [DLUtil nativeHoverColor]) set];
        [[NSBezierPath bezierPathWithRoundedRect:selectionRect xRadius:5.0 yRadius:5.0] fill];
    }
    cellFrame = NSIntersectionRect(cellFrame, [controlView visibleRect]);
    DLUser *user = [representedMember user];
    if (!user) return;
    NSString *status = [representedMember presenceStatus];
    BOOL offline = [status isEqualToString:@"offline"];
    // Offline members are dimmed like the official list.
    CGFloat alpha = offline ? 0.35 : 1.0;
    NSRect avatarRect = NSMakeRect(NSMinX(cellFrame) + 12.0, NSMidY(cellFrame) - 16.0, 32.0, 32.0);
    NSImage *avatar = [[[NSImage alloc] initWithData:[user avatarImageData]] autorelease];
    if (avatar) {
        [NSGraphicsContext saveGraphicsState];
        [[NSBezierPath bezierPathWithOvalInRect:avatarRect] addClip];
        [avatar drawInRect:avatarRect fromRect:NSZeroRect operation:NSCompositeSourceOver
                  fraction:alpha respectFlipped:YES hints:nil];
        [NSGraphicsContext restoreGraphicsState];
    }
    if (!offline) {
        BOOL flipped = [controlView isFlipped];
        NSRect dotRect = NSMakeRect(NSMaxX(avatarRect) - 11.0, (flipped ? NSMaxY(avatarRect) - 11.0 : NSMinY(avatarRect) - 1.0), 12.0, 12.0);
        [[DLUtil nativeSidebarColor] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:dotRect] fill];
        [[DLUtil statusColorForPresenceStatus:status] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(dotRect, 2.0, 2.0)] fill];
    }
    NSString *name = [user globalName] ? [user globalName] : [user username];
    NSColor *nameColor = [DLUtil roleColorForRoleIDs:[representedMember roles] inServer:representedServer];
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [style setLineBreakMode:NSLineBreakByTruncatingTail];
    NSColor *textColor = nameColor ? nameColor : [DLUtil nativePrimaryTextColor];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont systemFontOfSize:13.0], NSFontAttributeName,
                                [textColor colorWithAlphaComponent:alpha], NSForegroundColorAttributeName,
                                style, NSParagraphStyleAttributeName, nil];
    NSMutableAttributedString *displayName = [[[NSMutableAttributedString alloc]
        initWithString:(name ? name : @"") attributes:attributes] autorelease];
    [DLTwemojiRenderer replaceEmojiInAttributedString:displayName size:13.0
                                   excludingAttribute:nil recordingAttribute:nil cursorLocation:NULL];
    CGFloat textX = NSMaxX(avatarRect) + 12.0;
    CGFloat textWidth = NSWidth(cellFrame) - NSMaxX(avatarRect) - 20.0;
    NSString *customStatus = offline ? nil : [representedMember customStatusText];
    if (![customStatus length]) {
        [displayName drawInRect:NSMakeRect(textX, NSMidY(cellFrame) - 9.0, textWidth, 18.0)];
        return;
    }
    // Name above, custom status below.
    BOOL flipped = [controlView isFlipped];
    [displayName drawInRect:NSMakeRect(textX, NSMidY(cellFrame) + (flipped ? -17.0 : 0.0), textWidth, 18.0)];
    NSDictionary *statusAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSFont systemFontOfSize:11.0], NSFontAttributeName,
                                      [DLUtil nativeSecondaryTextColor], NSForegroundColorAttributeName,
                                      style, NSParagraphStyleAttributeName, nil];
    NSMutableAttributedString *statusText = [[[NSMutableAttributedString alloc] initWithString:customStatus attributes:statusAttributes] autorelease];
    [DLTwemojiRenderer replaceEmojiInAttributedString:statusText size:11.0
                                   excludingAttribute:nil recordingAttribute:nil cursorLocation:NULL];
    [statusText drawInRect:NSMakeRect(textX, NSMidY(cellFrame) + (flipped ? 1.0 : -16.0), textWidth, 15.0)];
}

@end

@interface DLMemberListController ()
-(void)installPane;
-(void)boundsDidChange:(NSNotification *)notification;
-(void)requestNextPageIfNeeded;
-(void)layoutPanes;
-(void)hostFrameDidChange:(NSNotification *)notification;
-(NSArray *)groupedItemsForServer:(DLServer *)server;
-(DLServerMember *)memberAtRow:(NSInteger)row;
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
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chatDisplayPreferencesDidChange:)
                                                 name:DLChatDisplayPreferencesDidChangeNotification object:nil];
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
    CGFloat paneWidth = 240.0;
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
    [titleField setStringValue:DLLocalizedString(@"MEMBERS")];
    // Group headers ("ONLINE — 12") replace the single pane title.
    [titleField setHidden:YES];
    [pane addSubview:titleField];

    scrollView = [[NSScrollView alloc] initWithFrame:
                  NSMakeRect(0.0, 0.0, paneWidth, NSHeight(bounds) - 50.0)];
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
    tableView = [[DLContextTableView alloc] initWithFrame:[[scrollView contentView] bounds]];
    [tableView setFocusRingType:NSFocusRingTypeNone];
    [scrollView setFocusRingType:NSFocusRingTypeNone];
    [tableView addTableColumn:column];
    [tableView setHeaderView:nil];
    [tableView setDataSource:self];
    [tableView setDelegate:self];
    [tableView setRowHeight:DLMemberRowHeight];
    [tableView setIntercellSpacing:NSMakeSize(0.0, 0.0)];
    [tableView setAllowsEmptySelection:YES];
    [tableView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleNone];
    [tableView setBackgroundColor:[DLUtil nativeSidebarColor]];
    NSMenu *memberMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    [memberMenu setDelegate:(id)self];
    [tableView setMenu:memberMenu];
    [tableView setTarget:self];
    [tableView setAction:@selector(memberRowClicked:)];
    [scrollView setDocumentView:tableView];
    [[scrollView contentView] setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(boundsDidChange:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:[scrollView contentView]];
    [pane addSubview:scrollView];
    [hostView addSubview:pane];
    [pane setHidden:YES];
}

// Groups members like the official list: online members under their highest
// hoisted ("display separately") role, then the remaining online members,
// then offline members. Header rows are NSStrings, member rows DLServerMember.
-(NSArray *)groupedItemsForServer:(DLServer *)server {
    if (!server) return [NSArray array];
    NSArray *hoistedRoles = [[server roles] filteredArrayUsingPredicate:
                             [NSPredicate predicateWithFormat:@"hoist == YES"]];
    hoistedRoles = [hoistedRoles sortedArrayUsingDescriptors:[NSArray arrayWithObject:
                    [[[NSSortDescriptor alloc] initWithKey:@"position" ascending:NO] autorelease]]];
    NSMutableDictionary *roleGroups = [NSMutableDictionary dictionary];
    NSMutableArray *online = [NSMutableArray array];
    NSMutableArray *offline = [NSMutableArray array];
    NSEnumerator *memberEnumerator = [[server members] objectEnumerator];
    DLServerMember *member;
    while (member = [memberEnumerator nextObject]) {
        if ([[member presenceStatus] isEqualToString:@"offline"]) {
            [offline addObject:member];
            continue;
        }
        NSString *groupRoleID = nil;
        NSEnumerator *roleEnumerator = [hoistedRoles objectEnumerator];
        NSDictionary *role;
        while ((role = [roleEnumerator nextObject]) && !groupRoleID) {
            NSString *roleID = [[role objectForKey:@"id"] description];
            NSEnumerator *memberRoles = [[member roles] objectEnumerator];
            id memberRoleID;
            while (memberRoleID = [memberRoles nextObject]) {
                if ([[memberRoleID description] isEqualToString:roleID]) { groupRoleID = roleID; break; }
            }
        }
        if (groupRoleID) {
            NSMutableArray *group = [roleGroups objectForKey:groupRoleID];
            if (!group) { group = [NSMutableArray array]; [roleGroups setObject:group forKey:groupRoleID]; }
            [group addObject:member];
        } else {
            [online addObject:member];
        }
    }
    NSMutableArray *result = [NSMutableArray array];
    NSEnumerator *roleEnumerator = [hoistedRoles objectEnumerator];
    NSDictionary *role;
    while (role = [roleEnumerator nextObject]) {
        NSArray *group = [roleGroups objectForKey:[[role objectForKey:@"id"] description]];
        if (![group count]) continue;
        [result addObject:[NSString stringWithFormat:@"%@ — %lu", [[role objectForKey:@"name"] uppercaseString], (unsigned long)[group count]]];
        [result addObjectsFromArray:[group sortedArrayUsingSelector:@selector(compareDisplayName:)]];
    }
    if ([online count]) {
        [result addObject:[NSString stringWithFormat:DLLocalizedString(@"ONLINE — %lu"), (unsigned long)[online count]]];
        [result addObjectsFromArray:[online sortedArrayUsingSelector:@selector(compareDisplayName:)]];
    }
    if ([offline count]) {
        [result addObject:[NSString stringWithFormat:DLLocalizedString(@"OFFLINE — %lu"), (unsigned long)[offline count]]];
        [result addObjectsFromArray:[offline sortedArrayUsingSelector:@selector(compareDisplayName:)]];
    }
    return result;
}

-(DLServerMember *)memberAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)[items count]) return nil;
    id item = [items objectAtIndex:row];
    return [item isKindOfClass:[DLServerMember class]] ? item : nil;
}

-(void)refreshForServer:(DLServer *)server {
    [displayedServer release];
    displayedServer = [server retain];
    NSArray *newItems = [self groupedItemsForServer:server];
    [items release];
    items = [newItems retain];
    [tableView reloadData];
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

#if LEGACY_DISCORD_LOCAL_DEV
-(void)showOfflineReplayForServer:(DLServer *)server {
    [self refreshForServer:server];
    [pane setHidden:NO];
    visible = YES;
    [self layoutPanes];
    [toggleButton setState:NSOnState];
}
#endif

-(void)layoutPanes {
    CGFloat hostWidth = NSWidth([hostView bounds]);
    CGFloat paneWidth = visible ? MIN(240.0, MAX(0.0, hostWidth - 180.0)) : 0.0;
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

-(void)chatDisplayPreferencesDidChange:(NSNotification *)notification {
    [tableView reloadData];
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
    DLServerMember *member = [self memberAtRow:row];
    if (!member) return (row >= 0 && row < (NSInteger)[items count]) ? [items objectAtIndex:row] : nil;
    DLUser *user = [member user];
    return [user globalName] ? [user globalName] : [user username];
}

-(CGFloat)tableView:(NSTableView *)inTableView heightOfRow:(NSInteger)row {
    return [self memberAtRow:row] ? DLMemberRowHeight : DLMemberGroupRowHeight;
}

-(BOOL)tableView:(NSTableView *)inTableView shouldSelectRow:(NSInteger)row {
    return [self memberAtRow:row] != nil;
}

-(void)tableView:(NSTableView *)inTableView willDisplayCell:(id)cell
  forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (![cell isKindOfClass:[DLMemberListCell class]]) return;
    DLServerMember *member = [self memberAtRow:row];
    [(DLMemberListCell *)cell setRepresentedMember:member];
    [(DLMemberListCell *)cell setRepresentedServer:displayedServer];
    [(DLMemberListCell *)cell setGroupTitle:(member ? nil : [items objectAtIndex:row])];
    // Avatars load lazily as rows are drawn instead of for the first rows only.
    DLUser *user = [member user];
    NSString *userID = [[user userID] description];
    if (userID && ![avatarRequests containsObject:userID]) {
        [avatarRequests addObject:userID];
        [user setDelegate:self];
        [user loadAvatarData];
    }
}

-(NSString *)tableView:(NSTableView *)inTableView toolTipForCell:(NSCell *)cell
                  rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)column
                   row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation {
    DLServerMember *member = [self memberAtRow:row];
    if (!member) return nil;
    DLUser *user = [member user];
    NSString *name = [user globalName] ? [user globalName] : [user username];
    // Like the official client, only names cut off by the row get a tooltip.
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSFont systemFontOfSize:13.0]
                                                           forKey:NSFontAttributeName];
    CGFloat textWidth = NSWidth([inTableView frameOfCellAtColumn:0 row:row]) - 64.0;
    if ([name sizeWithAttributes:attributes].width <= textWidth) return nil;
    return name;
}

// Every click opens the profile, also on the row that is already selected.
-(void)memberRowClicked:(id)sender {
    NSInteger row = [tableView clickedRow];
    if (row < 0) return;
    if ([tableView selectedRow] != row) {
        [tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        return;
    }
    [self tableViewSelectionDidChange:nil];
}

-(void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = [tableView selectedRow];
    DLServerMember *member = [self memberAtRow:row];
    if (!member) return;
    DLUser *user = [member user];
    [delegate memberListController:self didSelectUser:user
                    relativeToRect:[tableView rectOfRow:row] ofView:tableView];
}

#pragma mark Context menu

-(NSMenuItem *)memberMenuItem:(NSString *)title action:(SEL)action member:(DLServerMember *)member {
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""] autorelease];
    [item setTarget:self];
    [item setRepresentedObject:member];
    return item;
}

// Official user menu order, limited to actions this client performs.
-(void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    [menu setAutoenablesItems:NO];
    DLServerMember *member = [self memberAtRow:[(DLContextTableView *)tableView menuRow]];
    if (!member) return;
    DLController *controller = [DLController sharedInstance];
    BOOL isMe = [[[[member user] userID] description] isEqualToString:[[[controller myUser] userID] description]];
    [menu addItem:[self memberMenuItem:DLLocalizedString(@"Profile") action:@selector(showMemberProfile:) member:member]];
    if ([delegate respondsToSelector:@selector(memberListController:requestsMentionOfUser:)]) {
        [menu addItem:[self memberMenuItem:DLLocalizedString(@"Mention") action:@selector(mentionMember:) member:member]];
    }
    if (!isMe) [menu addItem:[self memberMenuItem:DLLocalizedString(@"Message") action:@selector(messageMember:) member:member]];
    if (isMe) {
        DLServer *server = [controller selectedServer];
        [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *nickname = [self memberMenuItem:DLLocalizedString(@"Edit Per-server Profile") action:@selector(editOwnServerProfile:) member:member];
        [nickname setEnabled:(server != nil)];
        [menu addItem:nickname];
    }
    if ([[DLPreferencesHandler sharedInstance] developerMode]) {
        [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *copyID = [self memberMenuItem:DLLocalizedString(@"Copy User ID") action:@selector(copyMemberID:) member:member];
        [DLDarkMenu setIconName:@"id" forItem:copyID];
        [menu addItem:copyID];
    }
}

-(void)messageMember:(NSMenuItem *)sender {
    [[DLController sharedInstance] openDirectMessageWithUser:[(DLServerMember *)[sender representedObject] user] draft:nil];
}

-(void)editOwnServerProfile:(NSMenuItem *)sender {
    [[DLServerMenuController sharedController] showServerProfileDialogForServer:[[DLController sharedInstance] selectedServer]];
}

-(void)showMemberProfile:(NSMenuItem *)sender {
    DLServerMember *member = [sender representedObject];
    NSInteger row = [items indexOfObjectIdenticalTo:member];
    if (row == NSNotFound) return;
    [delegate memberListController:self didSelectUser:[member user]
                    relativeToRect:[tableView rectOfRow:row] ofView:tableView];
}

-(void)mentionMember:(NSMenuItem *)sender {
    [delegate memberListController:self requestsMentionOfUser:[(DLServerMember *)[sender representedObject] user]];
}

-(void)copyMemberID:(NSMenuItem *)sender {
    [DLUtil copyStringToPasteboard:[[[(DLServerMember *)[sender representedObject] user] userID] description]];
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
