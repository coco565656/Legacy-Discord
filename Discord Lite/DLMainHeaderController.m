//
//  DLMainHeaderController.m
//  Legacy Discord
//

#import "DLMainHeaderController.h"
#import "DLMainWindowChromeControls.h"
#import "DLMessageSearchController.h"
#import "DLPinsController.h"
#import "ChatScrollView.h"
#import "DLUtil.h"
#import "DLTwemojiRenderer.h"
#import "DLDarkMenu.h"

// Clickable server header: hover tint and the chevron that turns into a
// close mark while the server menu is open, as in the official client.
@interface DLServerMenuButton : NSView {
    id target;
    SEL action;
    BOOL hovered;
    BOOL open;
    NSTrackingArea *trackingArea;
}
-(void)setTarget:(id)target action:(SEL)action;
-(void)setOpen:(BOOL)open;
@end

@implementation DLServerMenuButton
-(void)dealloc {
    if (trackingArea) [self removeTrackingArea:trackingArea];
    [trackingArea release];
    [super dealloc];
}
-(void)setTarget:(id)inTarget action:(SEL)inAction {
    target = inTarget;
    action = inAction;
}
-(void)setOpen:(BOOL)inOpen {
    open = inOpen;
    [self setNeedsDisplay:YES];
}
-(void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    if (hidden) hovered = NO;
}
-(void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (trackingArea) {
        [self removeTrackingArea:trackingArea];
        [trackingArea release];
    }
    trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect) owner:self userInfo:nil];
    [self addTrackingArea:trackingArea];
}
-(void)mouseEntered:(NSEvent *)event { hovered = YES; [self setNeedsDisplay:YES]; }
-(void)mouseExited:(NSEvent *)event { hovered = NO; [self setNeedsDisplay:YES]; }
-(BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
-(void)mouseDown:(NSEvent *)event {
    if (target && action) [target performSelector:action withObject:self];
}
-(void)drawRect:(NSRect)dirtyRect {
    if (hovered || open) {
        [[NSColor colorWithCalibratedWhite:1.0 alpha:0.04] setFill];
        NSRectFillUsingOperation([self bounds], NSCompositeSourceOver);
    }
    NSRect icon = NSMakeRect(NSWidth([self bounds]) - 30.0, floor(NSMidY([self bounds]) - 9.0), 18.0, 18.0);
    [DLDarkMenu drawIconNamed:(open ? @"close" : @"chevron-down") inRect:icon color:[DLUtil nativePrimaryTextColor]];
}
@end

@interface DLMainHeaderController ()
-(void)installHeaderControls;
-(void)updateConnectionStatusField;
-(void)layoutControls;
-(void)headerFrameDidChange:(NSNotification *)notification;
-(IBAction)reloadSelectedChannel:(id)sender;
-(IBAction)toggleMemberList:(id)sender;
@end

@implementation DLMainHeaderController

-(id)initWithChannelHeaderView:(NSView *)inChannelHeaderView
                chatHeaderView:(NSView *)inChatHeaderView
                   serverLabel:(NSTextField *)inServerLabel
               chatHeaderLabel:(NSTextField *)inChatHeaderLabel
                chatScrollView:(ChatScrollView *)inChatScrollView
                  composerView:(NSView *)inComposerView {
    self = [super init];
    if (self) {
        channelHeaderView = [inChannelHeaderView retain];
        chatHeaderView = [inChatHeaderView retain];
        serverLabel = [inServerLabel retain];
        chatHeaderLabel = [inChatHeaderLabel retain];
        chatScrollView = [inChatScrollView retain];
        composerView = [inComposerView retain];
        connectionState = DLWSConnectionStateConnecting;
        [self installHeaderControls];
        [chatHeaderView setPostsFrameChangedNotifications:YES];
        [channelHeaderView setPostsFrameChangedNotifications:YES];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(headerFrameDidChange:)
                                                     name:NSViewFrameDidChangeNotification object:chatHeaderView];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(headerFrameDidChange:)
                                                     name:NSViewFrameDidChangeNotification object:channelHeaderView];
        [self layoutControls];
    }
    return self;
}

-(void)setDelegate:(id<DLMainHeaderControllerDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)installHeaderControls {
    NSRect channelHeaderBounds = [channelHeaderView bounds];
    connectionStatusField = [[DLConnectionIndicatorView alloc] initWithFrame:
                             NSMakeRect(NSWidth(channelHeaderBounds) - 29.0, 10.0, 20.0, 22.0)];
    [connectionStatusField setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [channelHeaderView addSubview:connectionStatusField];
    serverMenuButton = [[DLServerMenuButton alloc] initWithFrame:channelHeaderBounds];
    [serverMenuButton setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [(DLServerMenuButton *)serverMenuButton setTarget:self action:@selector(serverMenuButtonClicked:)];
    [serverMenuButton setHidden:YES];
    [channelHeaderView addSubview:serverMenuButton positioned:NSWindowBelow relativeTo:connectionStatusField];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(darkMenuDidClose:)
                                                 name:DLDarkMenuDidCloseNotification object:nil];
    NSRect serverLabelFrame = [serverLabel frame];
    serverLabelFrame.size.width = MAX(40.0, NSWidth(channelHeaderBounds) - serverLabelFrame.origin.x - 38.0);
    [serverLabel setFrame:serverLabelFrame];

    NSRect chatHeaderBounds = [chatHeaderView bounds];
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
    [chatHeaderView addSubview:reloadButton];
    // The official client has no reload button; the object stays for the
    // presentation controller's enable/disable calls but is not shown.
    [reloadButton setHidden:YES];

    messageSearchField = [[NSSearchField alloc] initWithFrame:
                          NSMakeRect(NSMinX([reloadButton frame]) - searchWidth - 6.0, 9.0, searchWidth, 24.0)];
    DLDarkSearchFieldCell *searchCell = [[DLDarkSearchFieldCell alloc] initTextCell:@""];
    [searchCell setTextColor:[DLUtil nativePrimaryTextColor]];
    [searchCell setBackgroundColor:[NSColor clearColor]];
    [searchCell setDrawsBackground:NO];
    [searchCell setBezeled:NO];
    [messageSearchField setCell:searchCell];
    [messageSearchField setEditable:YES];
    [messageSearchField setSelectable:YES];
    [searchCell release];
    [messageSearchField setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [messageSearchField setBackgroundColor:[DLUtil nativeInputColor]];
    [messageSearchField setTextColor:[DLUtil nativePrimaryTextColor]];
    [messageSearchField setFocusRingType:NSFocusRingTypeNone];
    [[messageSearchField cell] setPlaceholderString:@"Search messages"];
    [[messageSearchField cell] setSendsWholeSearchString:YES];
    [[messageSearchField cell] setSendsSearchStringImmediately:NO];
    [chatHeaderView addSubview:messageSearchField];

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
    [chatHeaderView addSubview:membersButton];

    pinsButton = [[DLPinsButton alloc] initWithFrame:
                  NSMakeRect(NSMinX([membersButton frame]) - 30.0, 8.0, 26.0, 26.0)];
    [pinsButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [pinsButton setBordered:NO];
    [pinsButton setRefusesFirstResponder:YES];
    [pinsButton setButtonType:NSPushOnPushOffButton];
    [pinsButton setTitle:@""];
    [pinsButton setToolTip:@"Show pinned messages"];
    [pinsButton setEnabled:NO];
    [chatHeaderView addSubview:pinsButton];

    threadsButton = [[DLThreadsButton alloc] initWithFrame:
                     NSMakeRect(NSMinX([pinsButton frame]) - 30.0, 8.0, 26.0, 26.0)];
    [threadsButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [threadsButton setBordered:NO];
    [threadsButton setRefusesFirstResponder:YES];
    [threadsButton setTitle:@""];
    [threadsButton setToolTip:@"Threads"];
    [threadsButton setTarget:self];
    [threadsButton setAction:@selector(showThreadList:)];
    [threadsButton setHidden:YES];
    [chatHeaderView addSubview:threadsButton];

    NSRect channelLabelFrame = [chatHeaderLabel frame];
    channelLabelFrame.size.width = MAX(45.0, NSMinX([pinsButton frame]) - channelLabelFrame.origin.x - 8.0);
    [chatHeaderLabel setFrame:channelLabelFrame];
    messageSearchController = [[DLMessageSearchController alloc] initWithHostView:nil
                                                                   chatScrollView:chatScrollView
                                                                     composerView:composerView
                                                                      searchField:messageSearchField];
    pinsController = [[DLPinsController alloc] initWithButton:pinsButton
                                            searchController:messageSearchController];
    [self updateConnectionStatusField];
}

-(DLMessageSearchController *)messageSearchController {
    return messageSearchController;
}

-(void)layoutControls {
    CGFloat width = NSWidth([chatHeaderView bounds]);
    NSRect labelFrame = [chatHeaderLabel frame];
    CGFloat searchWidth = MIN(190.0, MAX(80.0, width - labelFrame.origin.x - 210.0));
    [messageSearchField setFrame:NSMakeRect(width - 10.0 - searchWidth, 9.0, searchWidth, 24.0)];
    [membersButton setFrame:NSMakeRect(NSMinX([messageSearchField frame]) - 32.0, 8.0, 26.0, 26.0)];
    [pinsButton setFrame:NSMakeRect(NSMinX([membersButton frame]) - 30.0, 8.0, 26.0, 26.0)];
    [threadsButton setFrame:NSMakeRect(NSMinX([pinsButton frame]) - 30.0, 8.0, 26.0, 26.0)];
    NSView *leftmost = [threadsButton isHidden] ? pinsButton : threadsButton;
    labelFrame.size.width = MAX(0.0, NSMinX([leftmost frame]) - labelFrame.origin.x - 8.0);
    [chatHeaderLabel setFrame:labelFrame];
    NSRect serverFrame = [serverLabel frame];
    serverFrame.size.width = MAX(0.0, NSWidth([channelHeaderView bounds]) - serverFrame.origin.x - 38.0);
    [serverLabel setFrame:serverFrame];
}

-(void)headerFrameDidChange:(NSNotification *)notification {
    [self layoutControls];
}

-(DLPinsController *)pinsController {
    return pinsController;
}

-(NSButton *)memberToggleButton {
    return membersButton;
}

-(NSButton *)reloadButton {
    return reloadButton;
}

-(void)setMembersEnabled:(BOOL)enabled {
    [membersButton setEnabled:enabled];
}

-(void)setChannelControlsHidden:(BOOL)hidden {
    [membersButton setHidden:hidden];
    [pinsButton setHidden:hidden];
    [messageSearchField setHidden:hidden];
    if (hidden) [self setThreadsButtonVisible:NO];
}

-(void)setThreadsButtonVisible:(BOOL)visible {
    [threadsButton setHidden:!visible];
    [self layoutControls];
}

-(IBAction)showThreadList:(id)sender {
    if ([delegate respondsToSelector:@selector(mainHeaderControllerDidRequestThreadList:)]) {
        [delegate mainHeaderControllerDidRequestThreadList:self];
    }
}

-(void)setServerMenuEnabled:(BOOL)enabled {
    [serverMenuButton setHidden:!enabled];
    [(DLServerMenuButton *)serverMenuButton setOpen:NO];
}

-(void)serverMenuButtonClicked:(id)sender {
    if (![delegate respondsToSelector:@selector(mainHeaderController:didRequestServerMenuFromView:)]) return;
    [(DLServerMenuButton *)serverMenuButton setOpen:YES];
    [delegate mainHeaderController:self didRequestServerMenuFromView:channelHeaderView];
    if (![DLDarkMenu isShown]) [(DLServerMenuButton *)serverMenuButton setOpen:NO];
}

-(void)darkMenuDidClose:(NSNotification *)notification {
    [(DLServerMenuButton *)serverMenuButton setOpen:NO];
}

-(void)setReloadEnabled:(BOOL)enabled {
    [reloadButton setEnabled:enabled];
}

-(void)setChannelTitle:(NSString *)title topic:(NSString *)topic {
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [style setLineBreakMode:NSLineBreakByTruncatingTail];
    NSMutableAttributedString *text = [[[NSMutableAttributedString alloc] initWithString:(title ? title : @"")
        attributes:[NSDictionary dictionaryWithObjectsAndKeys:
                    [NSFont boldSystemFontOfSize:14.0], NSFontAttributeName,
                    [DLUtil nativePrimaryTextColor], NSForegroundColorAttributeName,
                    style, NSParagraphStyleAttributeName, nil]] autorelease];
    NSString *singleLineTopic = [[topic componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
    if ([singleLineTopic length]) {
        // "name | topic" like the official channel header.
        [text appendAttributedString:[[[NSAttributedString alloc] initWithString:[@"  │  " stringByAppendingString:singleLineTopic]
            attributes:[NSDictionary dictionaryWithObjectsAndKeys:
                        [NSFont systemFontOfSize:12.0], NSFontAttributeName,
                        [DLUtil nativeSecondaryTextColor], NSForegroundColorAttributeName,
                        style, NSParagraphStyleAttributeName, nil]] autorelease]];
    }
    [DLTwemojiRenderer replaceEmojiInAttributedString:text size:14.0
                                   excludingAttribute:nil recordingAttribute:nil cursorLocation:NULL];
    [chatHeaderLabel setAttributedStringValue:text];
    [chatHeaderLabel setToolTip:([singleLineTopic length] ? singleLineTopic : nil)];
}

-(void)setConnectionState:(DLWSConnectionState)state {
    connectionState = state;
    [self updateConnectionStatusField];
}

-(void)updateConnectionStatusField {
    NSString *statusDescription = @"Disconnected";
    NSColor *statusColor = [NSColor colorWithCalibratedRed:0.65 green:0.12 blue:0.12 alpha:1.0];
    if (connectionState == DLWSConnectionStateConnecting) {
        statusDescription = @"Connecting…";
        statusColor = [NSColor colorWithCalibratedRed:0.72 green:0.46 blue:0.08 alpha:1.0];
    } else if (connectionState == DLWSConnectionStateConnected) {
        statusDescription = @"Connected";
        statusColor = [NSColor colorWithCalibratedRed:0.18 green:0.55 blue:0.20 alpha:1.0];
    } else if (connectionState == DLWSConnectionStateReconnecting) {
        statusDescription = @"Reconnecting…";
        statusColor = [NSColor colorWithCalibratedRed:0.72 green:0.46 blue:0.08 alpha:1.0];
    }
    [(DLConnectionIndicatorView *)connectionStatusField setIndicatorColor:statusColor];
    [connectionStatusField setToolTip:statusDescription];
    // Like the official client, connection state is only surfaced while the
    // Gateway is not connected.
    [connectionStatusField setHidden:(connectionState == DLWSConnectionStateConnected)];
}

-(void)applyCurrentTheme {
    for (NSTextField *label in [NSArray arrayWithObjects:serverLabel, nil]) {
        [label setTextColor:[DLUtil nativePrimaryTextColor]];
        NSMutableAttributedString *text = [[[label attributedStringValue] mutableCopy] autorelease];
        [text addAttribute:NSForegroundColorAttributeName value:[DLUtil nativePrimaryTextColor]
                     range:NSMakeRange(0, [text length])];
        [label setAttributedStringValue:text];
    }
    DLDarkSearchFieldCell *searchCell = (DLDarkSearchFieldCell *)[messageSearchField cell];
    [searchCell setTextColor:[DLUtil nativePrimaryTextColor]];
    [messageSearchField setBackgroundColor:[DLUtil nativeInputColor]];
    [messageSearchField setTextColor:[DLUtil nativePrimaryTextColor]];
    [messageSearchField setNeedsDisplay:YES];
    [connectionStatusField setNeedsDisplay:YES];
}

-(IBAction)reloadSelectedChannel:(id)sender {
    if ([delegate respondsToSelector:@selector(mainHeaderControllerDidRequestReload:)]) {
        [delegate mainHeaderControllerDidRequestReload:self];
    }
}

-(IBAction)toggleMemberList:(id)sender {
    if ([delegate respondsToSelector:@selector(mainHeaderControllerDidRequestMemberListToggle:)]) {
        [delegate mainHeaderControllerDidRequestMemberListToggle:self];
    }
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    delegate = nil;
    [pinsController setDelegate:nil];
    [messageSearchController setDelegate:nil];
    [pinsController release];
    [messageSearchController release];
    [pinsButton release];
    [threadsButton release];
    [messageSearchField release];
    [membersButton release];
    [reloadButton release];
    [connectionStatusField release];
    [serverMenuButton release];
    [composerView release];
    [chatScrollView release];
    [chatHeaderLabel release];
    [serverLabel release];
    [chatHeaderView release];
    [channelHeaderView release];
    [super dealloc];
}

@end
