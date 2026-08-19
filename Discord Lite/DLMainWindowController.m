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

    if (drawsSeparatorBefore) {
        [[NSColor colorWithCalibratedWhite:0.38 alpha:1.0] set];
        NSRectFill(NSMakeRect(NSMinX(cellFrame) + 17.0, NSMaxY(cellFrame) - 1.0,
                              NSWidth(cellFrame) - 34.0, 1.0));
    }

    NSRect iconRect = NSMakeRect(NSMidX(cellFrame) - 22.0, NSMidY(cellFrame) - 22.0, 44.0, 44.0);
    NSImage *sourceImage = [[[NSImage alloc] initWithData:[representedServer iconImageData]] autorelease];
    if (sourceImage) {
        NSImage *roundedImage = [DLUtil imageResize:sourceImage newSize:iconRect.size cornerRadius:22.0];
        [roundedImage drawInRect:iconRect
                       fromRect:NSZeroRect
                      operation:NSCompositeSourceOver
                       fraction:1.0
                 respectFlipped:YES
                          hints:nil];
    }

    if ([representedServer hasUnreadMessages] && ![self isHighlighted]) {
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

@interface DLMainWindowController ()
-(void)installNativeToolbar;
-(void)updateConnectionStatusField;
-(void)clearMessageSearchHighlight;
-(void)installNativeServerTableView;
-(void)displayServerItems:(NSArray *)items;
-(void)selectServer:(DLServer *)server;
-(void)loadChannelsForServer:(DLServer *)server;
-(void)installNativeChannelOutlineView;
-(void)displayChannelOutlineItems:(NSArray *)items;
-(void)selectChannel:(DLChannel *)channel;
-(NSImage *)emojiPickerButtonImage;
-(void)scheduleEmojiPickerReload:(id)sender;
-(void)messageDisplayScaleDidChange:(NSNotification *)notification;
-(NSArray *)standardEmojiPickerItems;
@end

@implementation DLMainWindowController

const NSTimeInterval TYPING_SEND_INTERVAL = 8.0;
const CGFloat MY_USER_AVATAR_RADIUS = 18.0f;
static NSString *DLToolbarConnectionItemIdentifier = @"DLToolbarConnection";
static NSString *DLToolbarSearchItemIdentifier = @"DLToolbarSearch";
static NSString *DLToolbarReloadItemIdentifier = @"DLToolbarReload";

- (void)windowDidLoad {
    [super windowDidLoad];

    [self.window setTitle:@"Legacy Discord"];
    [self.window setBackgroundColor:[NSColor windowBackgroundColor]];
    [self installNativeToolbar];

    [serversScrollView setDrawsBackground:YES];
    [serversScrollView setBackgroundColor:[DLUtil nativeServerRailColor]];
    [[serversScrollView contentView] setBackgroundColor:[DLUtil nativeServerRailColor]];
    [self installNativeServerTableView];
    [channelsScrollView setDrawsBackground:YES];
    [channelsScrollView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [[channelsScrollView contentView] setBackgroundColor:[DLUtil nativeSidebarColor]];
    [self installNativeChannelOutlineView];
    [chatScrollView setDrawsBackground:YES];
    [chatScrollView setBackgroundColor:[DLUtil nativeContentColor]];
    [[chatScrollView contentView] setBackgroundColor:[DLUtil nativeContentColor]];

    [channelViewHeader setGradientStartColor:[DLUtil nativeHeaderTopColor]
                                    endColor:[DLUtil nativeHeaderBottomColor]];
    [channelViewHeader setBottomBorderColor:[NSColor gridColor]];
    [chatViewHeader setGradientStartColor:[DLUtil nativeHeaderTopColor]
                                 endColor:[DLUtil nativeHeaderBottomColor]];
    [chatViewHeader setBottomBorderColor:[NSColor gridColor]];
    [serverLabel setTextColor:[DLUtil nativePrimaryTextColor]];
    [chatHeaderLabel setTextColor:[DLUtil nativePrimaryTextColor]];

    [userInfoView setBackgroundColor:[DLUtil nativeChromeColor]];
    [userInfoView setBottomBorderColor:[NSColor gridColor]];
    [myUsernameTextField setTextColor:[DLUtil nativePrimaryTextColor]];
    [myDiscTextField setTextColor:[DLUtil nativeSecondaryTextColor]];

    [messageEntryContainerView setBackgroundColor:[DLUtil nativeChromeColor]];
    [messageEntryTextView setBackgroundColor:[DLUtil nativeContentColor]];
    [messageEntryTextView setTextColor:[DLUtil nativePrimaryTextColor]];
    [messageEntryTextView setInsertionPointColor:[DLUtil nativePrimaryTextColor]];
    [messageEntryScrollView setBorderType:NSBezelBorder];
    [messageEntryScrollView setDrawsBackground:YES];
    [messageEntryScrollView setBackgroundColor:[DLUtil nativeContentColor]];
    NSRect entryFrame = [messageEntryScrollView frame];
    entryFrame.size.width -= 28;
    [messageEntryScrollView setFrame:entryFrame];
    emojiButton = [[NSButton alloc] initWithFrame:NSMakeRect(NSWidth([messageEntryContainerView bounds]) - 35, 15, 28, 26)];
    [emojiButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
    [emojiButton setBezelStyle:NSRoundedBezelStyle];
    [emojiButton setButtonType:NSMomentaryPushInButton];
    [emojiButton setTitle:@""];
    [emojiButton setImage:[self emojiPickerButtonImage]];
    [emojiButton setImagePosition:NSImageOnly];
    [emojiButton setToolTip:@"Insert custom emoji"];
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
    editingLocation = NSNotFound;
    tagIndex = NSNotFound;
    messageEditor = [[DLMessageEditor alloc] init];
    [messageEditor setDelegate:self];
    isLoadingMessages = NO;
    isLoadingViews = NO;
    isTyping = NO;
    madeMentionChange = NO;
    [[DLController sharedInstance] setDelegate:self];
    [chatScrollView.contentView setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chatScrollViewBoundsDidChange:) name:NSViewBoundsDidChangeNotification object:chatScrollView.contentView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messageDisplayScaleDidChange:) name:DLMessageDisplayScaleDidChangeNotification object:nil];
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    [myUserAvatarImage setImage:[DLUtil imageResize:[[[NSImage alloc] initWithContentsOfFile:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"discord_placeholder.png"]] autorelease] newSize:myUserAvatarImage.frame.size cornerRadius:MY_USER_AVATAR_RADIUS]];
    [messageEntryTextView setDelegate:self];
    [chatScrollView setDelegate:self];
    currentMessageScrollHeight = messageEntryScrollView.frame.size.height;
    typingUsers = [[NSMutableArray alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTextViewSizing) name:NSWindowDidResizeNotification object:nil];
}

-(void)messageDisplayScaleDidChange:(NSNotification *)notification {
    if ([[DLController sharedInstance] selectedChannel]) {
        [self reloadSelectedChannel:nil];
    }
}

-(NSImage *)emojiPickerButtonImage {
    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(18, 18)] autorelease];
    [image lockFocus];
    [[NSColor colorWithCalibratedWhite:0.12 alpha:1.0] set];

    NSBezierPath *face = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(1.5, 1.5, 15.0, 15.0)];
    [face setLineWidth:1.4];
    [face stroke];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5.0, 10.0, 1.8, 1.8)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(11.2, 10.0, 1.8, 1.8)] fill];

    NSBezierPath *smile = [NSBezierPath bezierPath];
    [smile moveToPoint:NSMakePoint(5.0, 7.0)];
    [smile curveToPoint:NSMakePoint(13.0, 7.0)
           controlPoint1:NSMakePoint(7.0, 4.3)
           controlPoint2:NSMakePoint(11.0, 4.3)];
    [smile setLineWidth:1.4];
    [smile stroke];
    [image unlockFocus];
    return image;
}

-(void)installNativeToolbar {
    currentConnectionState = DLWSConnectionStateConnecting;
    lastMessageSearchIndex = -1;
    mainToolbar = [[NSToolbar alloc] initWithIdentifier:@"LegacyDiscordMainToolbar"];
    [mainToolbar setDelegate:self];
    [mainToolbar setAllowsUserCustomization:NO];
    [mainToolbar setAutosavesConfiguration:NO];
    [mainToolbar setDisplayMode:NSToolbarDisplayModeIconAndLabel];
    [self.window setToolbar:mainToolbar];
}

-(NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return [NSArray arrayWithObjects:DLToolbarConnectionItemIdentifier,
            DLToolbarSearchItemIdentifier, DLToolbarReloadItemIdentifier,
            NSToolbarFlexibleSpaceItemIdentifier, NSToolbarSpaceItemIdentifier,
            NSToolbarSeparatorItemIdentifier, nil];
}

-(NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return [NSArray arrayWithObjects:DLToolbarConnectionItemIdentifier,
            NSToolbarFlexibleSpaceItemIdentifier, DLToolbarSearchItemIdentifier,
            DLToolbarReloadItemIdentifier, nil];
}

-(NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];
    if ([itemIdentifier isEqualToString:DLToolbarConnectionItemIdentifier]) {
        connectionStatusField = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 125.0, 22.0)];
        [connectionStatusField setBezeled:NO];
        [connectionStatusField setDrawsBackground:NO];
        [connectionStatusField setEditable:NO];
        [connectionStatusField setSelectable:NO];
        [connectionStatusField setAlignment:NSLeftTextAlignment];
        [item setLabel:@"Connection"];
        [item setPaletteLabel:@"Connection Status"];
        [item setView:connectionStatusField];
        [item setMinSize:NSMakeSize(110.0, 22.0)];
        [item setMaxSize:NSMakeSize(150.0, 22.0)];
        [self updateConnectionStatusField];
    } else if ([itemIdentifier isEqualToString:DLToolbarSearchItemIdentifier]) {
        messageSearchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 210.0, 24.0)];
        [[messageSearchField cell] setPlaceholderString:@"Search loaded messages"];
        [[messageSearchField cell] setSendsWholeSearchString:YES];
        [[messageSearchField cell] setSendsSearchStringImmediately:NO];
        [messageSearchField setTarget:self];
        [messageSearchField setAction:@selector(searchLoadedMessages:)];
        [item setLabel:@"Search"];
        [item setPaletteLabel:@"Message Search"];
        [item setView:messageSearchField];
        [item setMinSize:NSMakeSize(150.0, 24.0)];
        [item setMaxSize:NSMakeSize(260.0, 24.0)];
    } else if ([itemIdentifier isEqualToString:DLToolbarReloadItemIdentifier]) {
        [item setLabel:@"Reload"];
        [item setPaletteLabel:@"Reload Channel"];
        [item setToolTip:@"Reload the selected channel"];
        [item setImage:[NSImage imageNamed:NSImageNameRefreshTemplate]];
        [item setTarget:self];
        [item setAction:@selector(reloadSelectedChannel:)];
    } else {
        return nil;
    }
    return item;
}

-(void)updateConnectionStatusField {
    NSString *statusText = @"● Disconnected";
    NSColor *statusColor = [NSColor colorWithCalibratedRed:0.65 green:0.12 blue:0.12 alpha:1.0];
    if (currentConnectionState == DLWSConnectionStateConnecting) {
        statusText = @"● Connecting…";
        statusColor = [NSColor colorWithCalibratedRed:0.72 green:0.46 blue:0.08 alpha:1.0];
    } else if (currentConnectionState == DLWSConnectionStateConnected) {
        statusText = @"● Connected";
        statusColor = [NSColor colorWithCalibratedRed:0.18 green:0.55 blue:0.20 alpha:1.0];
    } else if (currentConnectionState == DLWSConnectionStateReconnecting) {
        statusText = @"● Reconnecting…";
        statusColor = [NSColor colorWithCalibratedRed:0.72 green:0.46 blue:0.08 alpha:1.0];
    }
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont systemFontOfSize:[NSFont smallSystemFontSize]], NSFontAttributeName,
                                statusColor, NSForegroundColorAttributeName, nil];
    NSAttributedString *value = [[[NSAttributedString alloc] initWithString:statusText attributes:attributes] autorelease];
    [connectionStatusField setAttributedStringValue:value];
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
    lastMessageSearchIndex = -1;
    lastMessage = nil;
    [[DLController sharedInstance] loadMessagesForChannel:channel beforeMessage:nil quantity:25];
}

-(void)clearMessageSearchHighlight {
    [highlightedSearchResult setSearchHighlighted:NO];
    highlightedSearchResult = nil;
}

-(IBAction)searchLoadedMessages:(id)sender {
    NSString *query = [[messageSearchField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([query length] == 0) {
        [lastMessageSearchQuery release];
        lastMessageSearchQuery = nil;
        lastMessageSearchIndex = -1;
        [self clearMessageSearchHighlight];
        [messageSearchField setToolTip:nil];
        return;
    }

    if (![query isEqualToString:lastMessageSearchQuery]) {
        [lastMessageSearchQuery release];
        lastMessageSearchQuery = [query copy];
        lastMessageSearchIndex = -1;
    }
    [self clearMessageSearchHighlight];

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

    NSArray *items = [chatScrollView content];
    NSInteger count = [items count];
    for (NSInteger offset = 1; offset <= count; offset++) {
        NSInteger index = (lastMessageSearchIndex + offset + count) % count;
        ChatItemViewController *item = [items objectAtIndex:index];
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
            lastMessageSearchIndex = index;
            highlightedSearchResult = item;
            [item setSearchHighlighted:YES];
            [[chatScrollView documentView] scrollRectToVisible:[[item view] frame]];
            [messageSearchField setToolTip:nil];
            return;
        }
    }
    [messageSearchField setToolTip:@"No matching loaded messages"];
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
    [serverTableView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];
    [serverTableView setAllowsMultipleSelection:NO];
    [serverTableView setAllowsEmptySelection:YES];
    [serverTableView setBackgroundColor:[DLUtil nativeServerRailColor]];
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
        [serverTableView deselectAll:self];
    }
    updatingServerTableSelection = NO;
    isLoadingViews = NO;
}

-(void)installNativeChannelOutlineView {
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"channel"] autorelease];
    [column setWidth:NSWidth([[channelsScrollView contentView] bounds])];
    [column setResizingMask:NSTableColumnAutoresizingMask];

    channelOutlineView = [[NSOutlineView alloc] initWithFrame:[[channelsScrollView contentView] bounds]];
    [channelOutlineView addTableColumn:column];
    [channelOutlineView setOutlineTableColumn:column];
    [channelOutlineView setHeaderView:nil];
    [channelOutlineView setDataSource:self];
    [channelOutlineView setDelegate:self];
    [channelOutlineView setRowHeight:24.0];
    [channelOutlineView setIndentationPerLevel:14.0];
    [channelOutlineView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
    [channelOutlineView setAllowsMultipleSelection:NO];
    [channelOutlineView setAllowsEmptySelection:YES];
    [channelOutlineView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [channelOutlineView setAutoresizesOutlineColumn:YES];
    [channelsScrollView setDocumentView:channelOutlineView];
}

-(void)displayChannelOutlineItems:(NSArray *)items {
    [channelOutlineItems release];
    channelOutlineItems = [items retain];
    [channelOutlineView reloadData];

    NSEnumerator *enumerator = [channelOutlineItems objectEnumerator];
    DLChannel *item;
    while (item = [enumerator nextObject]) {
        [item setDelegate:self];
        if ([item type] == ChannelTypeHeader) {
            [channelOutlineView expandItem:item];
        }
        NSEnumerator *childEnumerator = [[item children] objectEnumerator];
        DLChannel *child;
        while (child = [childEnumerator nextObject]) {
            [child setDelegate:self];
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
}

-(void)setDelegate:(id<DLMainWindowDelegate>)inDelegate {
    delegate = inDelegate;
}

#pragma mark Native Server Table

-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [serverItems count];
}

-(id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    return [[serverItems objectAtIndex:row] name];
}

-(void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([cell isKindOfClass:[DLServerTableCell class]]) {
        [(DLServerTableCell *)cell setRepresentedServer:[serverItems objectAtIndex:row]];
        [(DLServerTableCell *)cell setDrawsSeparatorBefore:(row == 1)];
    }
}

-(NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation {
    if (row >= 0 && row < (NSInteger)[serverItems count]) {
        return [[serverItems objectAtIndex:row] name];
    }
    return nil;
}

-(void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (updatingServerTableSelection || [notification object] != serverTableView) {
        return;
    }
    NSInteger row = [serverTableView selectedRow];
    if (row >= 0 && row < (NSInteger)[serverItems count]) {
        [self selectServer:[serverItems objectAtIndex:row]];
    }
}

-(void)selectServer:(DLServer *)server {
    [attachButton setEnabled:NO];
    [emojiButton setEnabled:NO];
    [messageEntryTextView setEditable:NO];
    [chatScrollView unregisterDraggedTypes];
    [self resetUI];
    [[DLController sharedInstance] setSelectedChannel:nil];
    [chatScrollView setContent:[NSArray array]];

    if ([server isEqual:[[DLController sharedInstance] myServerItem]]) {
        [NSThread detachNewThreadSelector:@selector(loadDirectMessageChannels) toTarget:self withObject:nil];
    } else {
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
    return ([channel type] == ChannelTypeHeader && [[channel children] count] > 0);
}

-(id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    DLChannel *channel = (DLChannel *)item;
    NSString *name = [channel name] ? [channel name] : @"Untitled";
    if ([channel type] == ChannelTypeHeader) {
        return [name uppercaseString];
    }

    NSString *kindPrefix = @"";
    if ([channel type] == ChannelTypeStandard || [channel type] == ChannelTypeAnnouncements) {
        kindPrefix = @"# ";
    } else if ([channel type] == ChannelTypeVoice) {
        kindPrefix = @"◖ ";
    }
    NSString *unreadPrefix = [channel hasUnreadMessages] ? @"● " : @"";
    NSString *mentionSuffix = [channel mentionCount] > 0 ? [NSString stringWithFormat:@"  (%ld)", (long)[channel mentionCount]] : @"";
    return [NSString stringWithFormat:@"%@%@%@%@", unreadPrefix, kindPrefix, name, mentionSuffix];
}

-(BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item {
    return [(DLChannel *)item type] == ChannelTypeHeader;
}

-(BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
    return [(DLChannel *)item type] != ChannelTypeHeader;
}

-(void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    if ([(DLChannel *)item type] == ChannelTypeHeader) {
        [cell setFont:[NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]]];
        [cell setTextColor:[DLUtil nativeSecondaryTextColor]];
    } else {
        [cell setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
        [cell setTextColor:[DLUtil nativePrimaryTextColor]];
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
        [self selectChannel:channel];
    }
}

-(void)selectChannel:(DLChannel *)channel {
    [self clearMessageSearchHighlight];
    lastMessageSearchIndex = -1;
    lastMessage = nil;
    [attachButton setEnabled:YES];
    [emojiButton setEnabled:YES];
    [messageEntryTextView setEditable:YES];
    [chatScrollView registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, nil]];
    [self resetUI];
    [[DLController sharedInstance] loadMessagesForChannel:channel beforeMessage:nil quantity:25];
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
    [contextMenu addItemWithTitle:@"Log Out" action:@selector(logOutUser) keyEquivalent:@""];
    [NSMenu popUpContextMenu:contextMenu withEvent:[NSApp currentEvent] forView:(NSButton *)sender];
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
        NSView *pickerView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 330)];
        emojiPickerSearchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(10, 296, 280, 24)];
        [[emojiPickerSearchField cell] setPlaceholderString:@"Search emoji"];
        [emojiPickerSearchField setTarget:self];
        [emojiPickerSearchField setAction:@selector(reloadEmojiPickerGrid:)];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scheduleEmojiPickerReload:) name:NSControlTextDidChangeNotification object:emojiPickerSearchField];
        [pickerView addSubview:emojiPickerSearchField];
        emojiPickerScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 10, 280, 278)];
        [emojiPickerScrollView setHasVerticalScroller:YES];
        [emojiPickerScrollView setBorderType:NSBezelBorder];
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

-(void)reloadEmojiPickerGrid:(id)sender {
    NSView *grid = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 260, 1)];
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
        NSString *emojiURL = [NSString stringWithFormat:@"https://cdn.discordapp.com/emojis/%@.png?size=32&quality=lossless", emojiID];
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

-(void)emojiCacheDidUpdate:(NSNotification *)notification {
    if ([emojiPopover isShown]) {
        [self scheduleEmojiPickerReload:nil];
    }
}

-(void)popoverDidClose:(NSNotification *)notification {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadEmojiPickerGrid:) object:nil];
    [reactionPickerChatView release];
    reactionPickerChatView = nil;
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
    NSString *emojiURL = [NSString stringWithFormat:@"https://cdn.discordapp.com/emojis/%@.png?size=32&quality=lossless", emojiID];
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
    [self clearMessageSearchHighlight];
    [lastMessageSearchQuery release];
    [messageSearchField release];
    [connectionStatusField release];
    [emojiButton release];
    [emojiPickerItems release];
    [emojiPickerSearchField release];
    [emojiPickerScrollView release];
    [emojiPopoverController release];
    [reactionPickerChatView release];
    [emojiPopover release];
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
    [DLErrorHandler displayError:e onWindow:self.window];
}

-(void)user:(DLUser *)u avatarDidUpdateWithData:(NSData *)data {
    [myUserAvatarImage setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:data] autorelease] newSize:myUserAvatarImage.frame.size cornerRadius:MY_USER_AVATAR_RADIUS]];
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
    NSEnumerator *e = [messages objectEnumerator];
    DLMessage *item;
    if (lastMessage) {
        newChannel = NO;
    }
    while (item = [e nextObject]) {
        if (![[[DLController sharedInstance] selectedServer] isEqual:[[DLController sharedInstance] myServerItem]]) {
            [item setServerID:[[[DLController sharedInstance] selectedServer] serverID]];
        }
        ChatItemViewController *view = [[ChatItemViewController alloc] initWithNibNamed:@"ChatItemViewController" bundle:nil];
        [view setDelegate:self];
        [view setRepresentedObject:item];
        if ([[item author] isEqual:[[DLController sharedInstance] myUser]]) {
            [view setIsMyContent:YES];
        }
        [views addObject:view];
        lastMessage = item;
        [view release];
    }
    if (newChannel) {
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
    isLoadingMessages = NO;
}


-(void)newMessage:(DLMessage *)m receivedForChannel:(DLChannel *)c inServer:(DLServer *)s {
    if (![s isEqual:[[DLController sharedInstance] myServerItem]]) {
        [m setServerID:[s serverID]];
    }
    
    if ([c isEqual:[[DLController sharedInstance] selectedChannel]]) {
        ChatItemViewController *view = [[[ChatItemViewController alloc] initWithNibNamed:@"ChatItemViewController" bundle:nil] autorelease];
        [view setRepresentedObject:m];
        [view setDelegate:self];
        if ([[m author] isEqual:[[DLController sharedInstance] myUser]]) {
            [view setIsMyContent:YES];
        }
        [chatScrollView prependViewController:view];
        [[m author] setTyping:NO];
        [self userDidStopTyping:[m author]];
        if ([self.window isKeyWindow]) {
            [[DLController sharedInstance] acknowledgeMessage:m];
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

-(void)requestDidFinishLoading:(AsyncHTTPRequest *)request {
    if ([request result] != HTTPResultOK) {
        [[HTTPCache sharedInstance] endLoadingURL:[request url]];
    }
    [request release];
}

@end
