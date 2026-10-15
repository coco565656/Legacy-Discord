//
//  DLDirectMessageController.m
//  Legacy Discord
//

#import "DLDirectMessageController.h"
#import "DLChannelNavigationController.h"
#import "DLDirectMessageChannel.h"
#import "ChatScrollView.h"
#import "NSView+BGColor.h"
#import "NSScroller+BGColor.h"
#import "DLUtil.h"
#import "DLTwemojiRenderer.h"

@interface DLDirectMessageController ()
-(void)installFriendsHome;
-(void)refreshFriendsHomeAvatars;
-(void)friendsHomeFrameDidChange:(NSNotification *)notification;
-(IBAction)openFriendDirectMessage:(id)sender;
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
    [friendsTitleField setStringValue:@"Friends"];
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
    [friendsSubtitleField setStringValue:@"Recent conversations"];
    [friendsHomeView addSubview:friendsSubtitleField];

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
                                           withObject:@"Direct Messages"
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
        [rowButton setToolTip:[NSString stringWithFormat:@"Open %@", [channel name]]];
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
        [DLTwemojiRenderer setText:[channel name] ? [channel name] : @"Direct Message" forLabel:nameField];
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
        [emptyField setStringValue:@"No recent direct messages"];
        [document addSubview:emptyField];
    }
    [friendsHomeScrollView setDocumentView:document];
    [DLTwemojiRenderer setText:@"Friends" forLabel:chatHeaderLabel];
    [chatHeaderImage setImage:nil];
    [chatScrollView setHidden:YES];
    [composerView setHidden:YES];
    [friendsHomeView setHidden:NO];
    [self updateResponsiveLayoutForWindowWidth:NSWidth([[[hostView window] contentView] bounds])
                         showingDirectMessages:YES];
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
    [super dealloc];
}

@end
