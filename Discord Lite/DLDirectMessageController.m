//
//  DLDirectMessageController.m
//  Legacy Discord
//

#import "DLDirectMessageController.h"
#import "DLLocalization.h"
#import "DLChannelNavigationController.h"
#import "DLDirectMessageChannel.h"
#import "ChatScrollView.h"
#import "NSView+BGColor.h"
#import "NSScroller+BGColor.h"
#import "DLUtil.h"
#import "DLTwemojiRenderer.h"
#import "DLController.h"
#import "DLMainWindowChromeControls.h"

enum {
    DLFriendsTabOnline = 0,
    DLFriendsTabAll,
    DLFriendsTabPending,
    DLFriendsTabBlocked
};

// Text tab in the Friends header, highlighted like the official tabs.
@interface DLFriendsTabButton : NSButton {
    BOOL selected;
}
-(void)setSelected:(BOOL)flag;
@end

@implementation DLFriendsTabButton
-(void)setSelected:(BOOL)flag {
    selected = flag;
    [self setNeedsDisplay:YES];
}
-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    if (selected || [[self cell] isHighlighted]) {
        [[DLUtil nativeSelectionColor] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 0.0, 2.0) xRadius:4.0 yRadius:4.0] fill];
    }
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont systemFontOfSize:13.0], NSFontAttributeName,
                                (selected ? [DLUtil nativePrimaryTextColor] : [DLUtil nativeSecondaryTextColor]), NSForegroundColorAttributeName, nil];
    NSSize size = [[self title] sizeWithAttributes:attributes];
    [[self title] drawAtPoint:NSMakePoint(floor(NSMidX(bounds) - size.width / 2.0), floor(NSMidY(bounds) - size.height / 2.0))
               withAttributes:attributes];
}
@end

@interface DLDirectMessageController () <DLUserDelegate>
-(void)installFriendsHome;
-(void)refreshFriendsHomeAvatars;
-(void)friendsHomeFrameDidChange:(NSNotification *)notification;
-(IBAction)openFriendDirectMessage:(id)sender;
-(void)rebuildFriendsList;
-(void)rebuildRecentConversations;
@end

@implementation DLDirectMessageController

-(id)initWithHostView:(NSView *)inHostView
       chatScrollView:(ChatScrollView *)inChatScrollView
         composerView:(NSView *)inComposerView
      chatHeaderLabel:(NSTextField *)inChatHeaderLabel
      chatHeaderImage:(NSImageView *)inChatHeaderImage
 navigationTitleLabel:(NSTextField *)inNavigationTitleLabel
        mainSplitView:(NSSplitView *)inMainSplitView
      channelPaneView:(NSView *)inChannelPaneView
channelNavigationController:(DLChannelNavigationController *)inChannelNavigationController {
    self = [super init];
    if (self) {
        hostView = [inHostView retain];
        chatScrollView = [inChatScrollView retain];
        composerView = [inComposerView retain];
        chatHeaderLabel = [inChatHeaderLabel retain];
        chatHeaderImage = [inChatHeaderImage retain];
        navigationTitleLabel = [inNavigationTitleLabel retain];
        mainSplitView = [inMainSplitView retain];
        channelPaneView = [inChannelPaneView retain];
        channelNavigationController = [inChannelNavigationController retain];
        [self installFriendsHome];
    }
    return self;
}

-(void)setDelegate:(id<DLDirectMessageControllerDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)installFriendsHome {
    NSRect bounds = [hostView bounds];
    NSView_BGColor *homeView = [[NSView_BGColor alloc] initWithFrame:
                               NSMakeRect(0.0, 0.0, NSWidth(bounds), NSHeight(bounds) - 42.0)];
    friendsHomeView = homeView;
    [friendsHomeView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [friendsHomeView setPostsFrameChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(friendsHomeFrameDidChange:)
                                                 name:NSViewFrameDidChangeNotification object:friendsHomeView];
    [homeView setBackgroundColor:[DLUtil nativeContentColor]];

    friendsTitleField = [[NSTextField alloc] initWithFrame:
                         NSMakeRect(24.0, NSHeight([friendsHomeView bounds]) - 43.0,
                                    NSWidth([friendsHomeView bounds]) - 48.0, 25.0)];
    [friendsTitleField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [friendsTitleField setBezeled:NO];
    [friendsTitleField setDrawsBackground:NO];
    [friendsTitleField setEditable:NO];
    [friendsTitleField setSelectable:NO];
    [friendsTitleField setFont:[NSFont boldSystemFontOfSize:18.0]];
    [friendsTitleField setTextColor:[DLUtil nativePrimaryTextColor]];
    [friendsTitleField setStringValue:DLLocalizedString(@"Friends")];
    [friendsHomeView addSubview:friendsTitleField];

    friendsSubtitleField = [[NSTextField alloc] initWithFrame:
                            NSMakeRect(25.0, NSHeight([friendsHomeView bounds]) - 65.0,
                                       NSWidth([friendsHomeView bounds]) - 50.0, 18.0)];
    [friendsSubtitleField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [friendsSubtitleField setBezeled:NO];
    [friendsSubtitleField setDrawsBackground:NO];
    [friendsSubtitleField setEditable:NO];
    [friendsSubtitleField setSelectable:NO];
    [friendsSubtitleField setFont:[NSFont systemFontOfSize:11.0]];
    [friendsSubtitleField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [friendsSubtitleField setStringValue:DLLocalizedString(@"Recent conversations")];
    [friendsHomeView addSubview:friendsSubtitleField];
    // The official Friends page has tabs instead of a title.
    [friendsTitleField setHidden:YES];
    [friendsSubtitleField setHidden:YES];
    friendsTabButtons = [[NSMutableArray alloc] init];
    NSArray *tabTitles = [NSArray arrayWithObjects:DLLocalizedString(@"Online"), DLLocalizedString(@"All"), DLLocalizedString(@"Pending"), DLLocalizedString(@"Blocked"), nil];
    CGFloat tabX = 20.0;
    for (NSUInteger index = 0; index < [tabTitles count]; index++) {
        NSString *tabTitle = [tabTitles objectAtIndex:index];
        CGFloat width = ceil([tabTitle sizeWithAttributes:[NSDictionary dictionaryWithObject:[NSFont systemFontOfSize:13.0] forKey:NSFontAttributeName]].width) + 20.0;
        DLFriendsTabButton *tab = [[[DLFriendsTabButton alloc] initWithFrame:NSMakeRect(tabX, NSHeight([friendsHomeView bounds]) - 48.0, width, 30.0)] autorelease];
        [tab setAutoresizingMask:NSViewMinYMargin];
        [tab setBordered:NO];
        [tab setButtonType:NSMomentaryChangeButton];
        [tab setTitle:tabTitle];
        [tab setTag:index];
        [tab setTarget:self];
        [tab setAction:@selector(selectFriendsTab:)];
        [friendsHomeView addSubview:tab];
        [friendsTabButtons addObject:tab];
        tabX += width + 8.0;
    }
    friendsTab = DLFriendsTabOnline;
    friendUsers = [[NSMutableDictionary alloc] init];
    friendRowItems = [[NSMutableArray alloc] init];

    friendsHomeScrollView = [[NSScrollView alloc] initWithFrame:
                             NSMakeRect(16.0, 16.0, NSWidth([friendsHomeView bounds]) - 32.0,
                                        NSHeight([friendsHomeView bounds]) - 92.0)];
    [friendsHomeScrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [friendsHomeScrollView setBorderType:NSNoBorder];
    [friendsHomeScrollView setHasVerticalScroller:YES];
    [friendsHomeScrollView setAutohidesScrollers:YES];
    [friendsHomeScrollView setDrawsBackground:YES];
    [friendsHomeScrollView setBackgroundColor:[DLUtil nativeContentColor]];
    [[friendsHomeScrollView contentView] setBackgroundColor:[DLUtil nativeContentColor]];
    NSScroller_BGColor *friendsScroller = [[NSScroller_BGColor alloc] initWithFrame:NSZeroRect];
    [friendsScroller setBackgroundColor:[DLUtil nativeContentColor]];
    [friendsHomeScrollView setVerticalScroller:friendsScroller];
    [friendsScroller release];
    [friendsHomeView addSubview:friendsHomeScrollView];
    [hostView addSubview:friendsHomeView];
    [friendsHomeView setHidden:YES];
}

-(void)displayDirectMessageChannels:(NSArray *)channels {
    [navigationTitleLabel performSelectorOnMainThread:@selector(setStringValue:)
                                           withObject:DLLocalizedString(@"Direct Messages")
                                        waitUntilDone:NO];
    [channelNavigationController performSelectorOnMainThread:@selector(displayChannelItems:)
                                                  withObject:channels
                                               waitUntilDone:NO];
    NSEnumerator *enumerator = [channels objectEnumerator];
    DLDirectMessageChannel *channel;
    while (channel = [enumerator nextObject]) {
        [channel performSelectorOnMainThread:@selector(loadAvatarImageData)
                                  withObject:nil
                               waitUntilDone:NO];
    }
}

-(void)showFriendsHomeWithChannels:(NSArray *)channels {
    NSArray *newChannels = [channels retain];
    [friendsHomeChannels release];
    friendsHomeChannels = newChannels;
    [self rebuildFriendsList];
    // No conversation is open on the Friends page.
    [channelNavigationController selectChannelWithoutNotifying:nil];
    [DLTwemojiRenderer setText:DLLocalizedString(@"Friends") forLabel:chatHeaderLabel];
    [chatHeaderImage setImage:nil];
    [chatScrollView setHidden:YES];
    [composerView setHidden:YES];
    [friendsHomeView setHidden:NO];
    [self updateResponsiveLayoutForWindowWidth:NSWidth([[[hostView window] contentView] bounds])
                         showingDirectMessages:YES];
}

-(void)selectFriendsTab:(NSButton *)sender {
    friendsTab = [sender tag];
    [self rebuildFriendsList];
}

-(void)relationshipsDidUpdate {
    if (friendsHomeView && ![friendsHomeView isHidden]) [self rebuildFriendsList];
}

-(void)user:(DLUser *)user avatarDidUpdateWithData:(NSData *)data {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(rebuildFriendsList) object:nil];
    [self performSelector:@selector(rebuildFriendsList) withObject:nil afterDelay:0.3];
}

-(DLUser *)friendUserForRelationship:(NSDictionary *)relationship {
    NSDictionary *userData = [relationship objectForKey:@"user"];
    NSString *userID = [[relationship objectForKey:@"id"] description];
    if (![userData isKindOfClass:[NSDictionary class]] || !userID) return nil;
    DLUser *user = [friendUsers objectForKey:userID];
    if (!user) {
        user = [[[DLUser alloc] initWithDict:userData] autorelease];
        [friendUsers setObject:user forKey:userID];
        [user setDelegate:self];
        [user loadAvatarData];
    }
    return user;
}

static NSString *DLStatusDescription(NSString *status) {
    if ([status isEqualToString:@"online"]) return DLLocalizedString(@"Online");
    if ([status isEqualToString:@"idle"]) return DLLocalizedString(@"Idle");
    if ([status isEqualToString:@"dnd"]) return DLLocalizedString(@"Do Not Disturb");
    return DLLocalizedString(@"Offline");
}

-(NSTextField *)friendsLabelWithFrame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color {
    NSTextField *field = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [field setAutoresizingMask:NSViewWidthSizable];
    [field setBezeled:NO];
    [field setDrawsBackground:NO];
    [field setEditable:NO];
    [field setSelectable:NO];
    [field setFont:font];
    [field setTextColor:color];
    [[field cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    return field;
}

// Friends page like the official client: Online / All / Pending / Blocked,
// a "TAB — N" header and one row per person with a status line.
-(void)rebuildFriendsList {
    for (NSUInteger index = 0; index < [friendsTabButtons count]; index++) {
        [(DLFriendsTabButton *)[friendsTabButtons objectAtIndex:index] setSelected:((NSInteger)index == friendsTab)];
    }
    DLController *controller = [DLController existingInstance];
    NSArray *relationships = [controller relationships];
    if ([relationships count] == 0) {
        [self rebuildRecentConversations];
        return;
    }
    [friendRowItems removeAllObjects];
    NSEnumerator *enumerator = [relationships objectEnumerator];
    NSDictionary *relationship;
    while (relationship = [enumerator nextObject]) {
        if (![relationship isKindOfClass:[NSDictionary class]]) continue;
        int type = [[relationship objectForKey:@"type"] intValue];
        NSString *status = [controller presenceStatusForUserID:[[relationship objectForKey:@"id"] description]];
        BOOL include = NO;
        if (friendsTab == DLFriendsTabOnline) include = (type == 1 && ![status isEqualToString:@"offline"]);
        else if (friendsTab == DLFriendsTabAll) include = (type == 1);
        else if (friendsTab == DLFriendsTabPending) include = (type == 3 || type == 4);
        else include = (type == 2);
        if (include) [friendRowItems addObject:relationship];
    }

    NSArray *tabNames = [NSArray arrayWithObjects:DLLocalizedString(@"ONLINE"), DLLocalizedString(@"ALL FRIENDS"), DLLocalizedString(@"PENDING"), DLLocalizedString(@"BLOCKED"), nil];
    NSRect visibleBounds = [[friendsHomeScrollView contentView] bounds];
    CGFloat rowHeight = 62.0;
    CGFloat headerHeight = 36.0;
    CGFloat documentHeight = MAX(NSHeight(visibleBounds), headerHeight + [friendRowItems count] * rowHeight + 8.0);
    NSView_BGColor *document = [[[NSView_BGColor alloc] initWithFrame:
                                NSMakeRect(0.0, 0.0, NSWidth(visibleBounds), documentHeight)] autorelease];
    [document setAutoresizingMask:NSViewWidthSizable];
    [document setBackgroundColor:[DLUtil nativeContentColor]];
    NSTextField *header = [self friendsLabelWithFrame:NSMakeRect(12.0, documentHeight - 28.0, NSWidth(visibleBounds) - 24.0, 16.0)
                                                 font:[NSFont boldSystemFontOfSize:10.0]
                                                color:[DLUtil nativeSecondaryTextColor]];
    [header setStringValue:[NSString stringWithFormat:@"%@ — %lu", [tabNames objectAtIndex:friendsTab], (unsigned long)[friendRowItems count]]];
    [document addSubview:header];

    NSInteger row = 0;
    for (NSDictionary *item in friendRowItems) {
        DLUser *user = [self friendUserForRelationship:item];
        NSString *userID = [[item objectForKey:@"id"] description];
        int type = [[item objectForKey:@"type"] intValue];
        NSString *status = [controller presenceStatusForUserID:userID];
        CGFloat y = documentHeight - headerHeight - (row + 1) * rowHeight;

        NSButton *rowButton = [[[NSButton alloc] initWithFrame:NSMakeRect(0.0, y, NSWidth(visibleBounds), rowHeight - 1.0)] autorelease];
        [rowButton setAutoresizingMask:NSViewWidthSizable];
        [rowButton setBordered:NO];
        [rowButton setTitle:@""];
        [rowButton setTag:row];
        [rowButton setTarget:self];
        [rowButton setAction:@selector(openFriendRow:)];
        [document addSubview:rowButton];

        NSRect avatarRect = NSMakeRect(12.0, y + 13.0, 36.0, 36.0);
        NSImageView *avatar = [[[NSImageView alloc] initWithFrame:avatarRect] autorelease];
        NSImage *avatarImage = [[[NSImage alloc] initWithData:[user avatarImageData]] autorelease];
        if (avatarImage) [avatar setImage:[DLUtil imageResize:avatarImage newSize:avatarRect.size cornerRadius:18.0]];
        [document addSubview:avatar];
        if (type == 1 && ![status isEqualToString:@"offline"]) {
            DLStatusDotView *dot = [[[DLStatusDotView alloc] initWithFrame:NSMakeRect(NSMaxX(avatarRect) - 12.0, NSMinY(avatarRect) - 2.0, 14.0, 14.0)] autorelease];
            [dot setDotColor:[DLUtil statusColorForPresenceStatus:status] ringColor:[DLUtil nativeContentColor]];
            [document addSubview:dot];
        }

        NSTextField *nameField = [self friendsLabelWithFrame:NSMakeRect(60.0, y + 32.0, MAX(100.0, NSWidth(visibleBounds) - 120.0), 18.0)
                                                        font:[NSFont boldSystemFontOfSize:13.0]
                                                       color:[DLUtil nativePrimaryTextColor]];
        [DLTwemojiRenderer setText:([user globalName] ? [user globalName] : @"") forLabel:nameField];
        [document addSubview:nameField];
        NSString *subtitle = type == 3 ? DLLocalizedString(@"Incoming Friend Request")
                           : (type == 4 ? DLLocalizedString(@"Outgoing Friend Request")
                           : (type == 2 ? DLLocalizedString(@"Blocked") : DLStatusDescription(status)));
        NSTextField *statusField = [self friendsLabelWithFrame:NSMakeRect(60.0, y + 14.0, MAX(100.0, NSWidth(visibleBounds) - 120.0), 16.0)
                                                          font:[NSFont systemFontOfSize:11.0]
                                                         color:[DLUtil nativeSecondaryTextColor]];
        [statusField setStringValue:subtitle];
        [document addSubview:statusField];

        NSView_BGColor *separator = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(12.0, y + rowHeight - 1.0, MAX(0.0, NSWidth(visibleBounds) - 24.0), 1.0)] autorelease];
        [separator setAutoresizingMask:NSViewWidthSizable];
        [separator setBackgroundColor:[DLUtil nativeSelectionColor]];
        [document addSubview:separator];
        row++;
    }
    if ([friendRowItems count] == 0) {
        NSTextField *emptyField = [self friendsLabelWithFrame:NSMakeRect(20.0, NSMidY([document bounds]) - 10.0, NSWidth(visibleBounds) - 40.0, 20.0)
                                                         font:[NSFont systemFontOfSize:12.0]
                                                        color:[DLUtil nativeSecondaryTextColor]];
        [emptyField setAlignment:NSCenterTextAlignment];
        NSArray *emptyTexts = [NSArray arrayWithObjects:DLLocalizedString(@"No one's around to play with Wumpus."), DLLocalizedString(@"Wumpus is waiting on friends."),
                               DLLocalizedString(@"There are no pending friend requests."), DLLocalizedString(@"You can't unblock the Wumpus."), nil];
        [emptyField setStringValue:[emptyTexts objectAtIndex:friendsTab]];
        [document addSubview:emptyField];
    }
    [friendsHomeScrollView setDocumentView:document];
}

// Opens the existing one-to-one DM with the person, if there is one.
-(void)openFriendRow:(NSButton *)sender {
    NSInteger row = [sender tag];
    if (row < 0 || row >= (NSInteger)[friendRowItems count]) return;
    NSString *userID = [[[friendRowItems objectAtIndex:row] objectForKey:@"id"] description];
    NSEnumerator *enumerator = [friendsHomeChannels objectEnumerator];
    DLDirectMessageChannel *channel;
    while (channel = [enumerator nextObject]) {
        if (![channel isKindOfClass:[DLDirectMessageChannel class]] || [channel isGroupMessage]) continue;
        if ([channel recipientWithUserID:userID]) {
            [channelNavigationController selectChannelWithoutNotifying:channel];
            if ([delegate respondsToSelector:@selector(directMessageController:didSelectChannel:)]) {
                [delegate directMessageController:self didSelectChannel:channel];
            }
            return;
        }
    }
    NSBeep();
}

// Used until READY relationships arrive: recent DM conversations.
-(void)rebuildRecentConversations {
    NSArray *channels = friendsHomeChannels;
    NSRect visibleBounds = [[friendsHomeScrollView contentView] bounds];
    CGFloat rowHeight = 58.0;
    CGFloat documentHeight = MAX(NSHeight(visibleBounds), [channels count] * rowHeight + 8.0);
    NSView_BGColor *document = [[[NSView_BGColor alloc] initWithFrame:
                                NSMakeRect(0.0, 0.0, NSWidth(visibleBounds), documentHeight)] autorelease];
    [document setAutoresizingMask:NSViewWidthSizable];
    [document setBackgroundColor:[DLUtil nativeContentColor]];
    NSInteger row = 0;
    for (DLDirectMessageChannel *channel in channels) {
        CGFloat y = documentHeight - (row + 1) * rowHeight;
        NSButton *rowButton = [[[NSButton alloc] initWithFrame:
                                NSMakeRect(0.0, y, NSWidth(visibleBounds), rowHeight - 2.0)] autorelease];
        [rowButton setAutoresizingMask:NSViewWidthSizable];
        [rowButton setBordered:NO];
        [rowButton setTitle:@""];
        [rowButton setTag:row];
        [rowButton setTarget:self];
        [rowButton setAction:@selector(openFriendDirectMessage:)];
        [rowButton setToolTip:[NSString stringWithFormat:DLLocalizedString(@"Open %@"), [channel name]]];
        [document addSubview:rowButton];

        NSImageView *avatar = [[[NSImageView alloc] initWithFrame:NSMakeRect(12.0, y + 9.0, 38.0, 38.0)] autorelease];
        NSImage *avatarImage = [[[NSImage alloc] initWithData:[channel imageData]] autorelease];
        if (avatarImage) {
            [avatar setImage:[DLUtil imageResize:avatarImage newSize:NSMakeSize(38.0, 38.0) cornerRadius:19.0]];
        }
        [document addSubview:avatar];

        NSTextField *nameField = [[[NSTextField alloc] initWithFrame:
                                   NSMakeRect(62.0, y + 20.0, MAX(100.0, NSWidth(visibleBounds) - 120.0), 20.0)] autorelease];
        [nameField setAutoresizingMask:NSViewWidthSizable];
        [nameField setBezeled:NO];
        [nameField setDrawsBackground:NO];
        [nameField setEditable:NO];
        [nameField setSelectable:NO];
        [nameField setFont:[NSFont boldSystemFontOfSize:13.0]];
        [[nameField cell] setLineBreakMode:NSLineBreakByTruncatingTail];
        [nameField setTextColor:[DLUtil nativePrimaryTextColor]];
        [DLTwemojiRenderer setText:[channel name] ? [channel name] : DLLocalizedString(@"Direct Message") forLabel:nameField];
        [document addSubview:nameField];

        NSBox *separator = [[[NSBox alloc] initWithFrame:
                             NSMakeRect(62.0, y, MAX(0.0, NSWidth(visibleBounds) - 74.0), 1.0)] autorelease];
        [separator setAutoresizingMask:NSViewWidthSizable];
        [separator setBoxType:NSBoxSeparator];
        [document addSubview:separator];
        row++;
    }
    if ([channels count] == 0) {
        NSTextField *emptyField = [[[NSTextField alloc] initWithFrame:
                                    NSMakeRect(20.0, NSMidY([document bounds]) - 20.0,
                                               NSWidth(visibleBounds) - 40.0, 40.0)] autorelease];
        [emptyField setBezeled:NO];
        [emptyField setDrawsBackground:NO];
        [emptyField setEditable:NO];
        [emptyField setAlignment:NSCenterTextAlignment];
        [emptyField setTextColor:[DLUtil nativeSecondaryTextColor]];
        [emptyField setStringValue:DLLocalizedString(@"No recent direct messages")];
        [document addSubview:emptyField];
    }
    [friendsHomeScrollView setDocumentView:document];
}

-(void)hideFriendsHome {
    [friendsHomeView setHidden:YES];
    [chatScrollView setHidden:NO];
    [composerView setHidden:NO];
}

-(void)refreshFriendsHomeAvatars {
    if (![friendsHomeView isHidden] && friendsHomeChannels) {
        [self showFriendsHomeWithChannels:friendsHomeChannels];
    }
}

-(void)friendsHomeFrameDidChange:(NSNotification *)notification {
    if ([friendsHomeView isHidden] || !friendsHomeChannels) return;
    // Wait for the scroll view's autoresizing pass before reading its viewport.
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshFriendsHomeAvatars) object:nil];
    [self performSelector:@selector(refreshFriendsHomeAvatars) withObject:nil afterDelay:0.0];
}

-(void)channelImageDidUpdate:(DLChannel *)channel {
    if (![friendsHomeView isHidden] && [friendsHomeChannels containsObject:channel]) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(refreshFriendsHomeAvatars)
                                                   object:nil];
        [self refreshFriendsHomeAvatars];
    }
}

-(IBAction)openFriendDirectMessage:(id)sender {
    NSInteger row = [(NSButton *)sender tag];
    if (row >= 0 && row < (NSInteger)[friendsHomeChannels count]) {
        DLChannel *channel = [friendsHomeChannels objectAtIndex:row];
        [channelNavigationController selectChannelWithoutNotifying:channel];
        if ([delegate respondsToSelector:@selector(directMessageController:didSelectChannel:)]) {
            [delegate directMessageController:self didSelectChannel:channel];
        }
    }
}

-(void)updateResponsiveLayoutForWindowWidth:(CGFloat)width showingDirectMessages:(BOOL)showingDirectMessages {
#if LEGACY_DISCORD_LOCAL_DEV
    return;
#endif
    if (!showingDirectMessages || !mainSplitView) {
        return;
    }
    if (!compactLayout && width < 680.0) {
        expandedChannelPaneWidth = NSWidth([channelPaneView frame]);
        compactLayout = YES;
        [mainSplitView setPosition:0.0 ofDividerAtIndex:0];
    } else if (compactLayout && width > 740.0) {
        [self restoreExpandedLayout];
    }
}

-(void)restoreExpandedLayout {
    if (!compactLayout) {
        return;
    }
    compactLayout = NO;
    CGFloat restoredWidth = expandedChannelPaneWidth >= 180.0 ? expandedChannelPaneWidth : 240.0;
    [mainSplitView setPosition:MIN(restoredWidth, 300.0) ofDividerAtIndex:0];
}

-(CGFloat)minimumSplitCoordinate {
    return compactLayout ? 0.0 : 180.0;
}

-(void)applyCurrentTheme {
    [(NSView_BGColor *)friendsHomeView setBackgroundColor:[DLUtil nativeContentColor]];
    [friendsHomeScrollView setBackgroundColor:[DLUtil nativeContentColor]];
    [[friendsHomeScrollView contentView] setBackgroundColor:[DLUtil nativeContentColor]];
    [(NSScroller_BGColor *)[friendsHomeScrollView verticalScroller] setBackgroundColor:[DLUtil nativeContentColor]];
    [friendsTitleField setTextColor:[DLUtil nativePrimaryTextColor]];
    [friendsSubtitleField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [[friendsHomeScrollView documentView] setNeedsDisplay:YES];
}

-(void)dealloc {
    delegate = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [friendsHomeChannels release];
    [friendsSubtitleField release];
    [friendsTitleField release];
    [friendsHomeScrollView release];
    [friendsHomeView release];
    [channelNavigationController release];
    [channelPaneView release];
    [mainSplitView release];
    [navigationTitleLabel release];
    [chatHeaderImage release];
    [chatHeaderLabel release];
    [composerView release];
    [chatScrollView release];
    [hostView release];
    [friendsTabButtons release];
    [friendRowItems release];
    [friendUsers release];
    [super dealloc];
}

@end
