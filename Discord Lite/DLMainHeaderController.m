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
    [reloadButton setFrame:NSMakeRect(width - 34.0, 8.0, 26.0, 26.0)];
    [messageSearchField setFrame:NSMakeRect(width - 40.0 - searchWidth, 9.0, searchWidth, 24.0)];
    [membersButton setFrame:NSMakeRect(NSMinX([messageSearchField frame]) - 32.0, 8.0, 26.0, 26.0)];
    [pinsButton setFrame:NSMakeRect(NSMinX([membersButton frame]) - 30.0, 8.0, 26.0, 26.0)];
    labelFrame.size.width = MAX(0.0, NSMinX([pinsButton frame]) - labelFrame.origin.x - 8.0);
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

-(void)setReloadEnabled:(BOOL)enabled {
    [reloadButton setEnabled:enabled];
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
}

-(void)applyCurrentTheme {
    for (NSTextField *label in [NSArray arrayWithObjects:serverLabel, chatHeaderLabel, nil]) {
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
    [messageSearchField release];
    [membersButton release];
    [reloadButton release];
    [connectionStatusField release];
    [composerView release];
    [chatScrollView release];
    [chatHeaderLabel release];
    [serverLabel release];
    [chatHeaderView release];
    [channelHeaderView release];
    [super dealloc];
}

@end
