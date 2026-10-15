//
//  DLMainWindowController.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/27/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLMainWindowController.h"
#if LEGACY_DISCORD_UI_DIAGNOSTICS
#import "DLUIDiagnostics.h"
#endif
#import "DLUtil.h"
#import "DLTwemojiRenderer.h"
#import "DLPreferencesHandler.h"
#import "DLMainWindowChromeControls.h"
#import "DLMessageReadStateController.h"
#import "DLServerNavigationController.h"
#import "DLChannelNavigationController.h"
#import "DLUserProfileController.h"
#import "DLThreadController.h"
#import "DLMessageSearchController.h"
#import "DLPinsController.h"
#import "DLMessageComposerController.h"
#import "DLDirectMessageController.h"
#import "DLMessagePresentationController.h"
#import "DLMainHeaderController.h"
#if LEGACY_DISCORD_LOCAL_DEV
#import "DLReplayFixtureProvider.h"
#endif

static void DLSetSplitHoldingPriorityIfSupported(NSSplitView *splitView, float priority, NSInteger index) {
    SEL selector = NSSelectorFromString(@"setHoldingPriority:forSubviewAtIndex:");
    if (![splitView respondsToSelector:selector]) return;
    typedef void (*DLSetHoldingPriorityFunction)(id, SEL, float, NSInteger);
    DLSetHoldingPriorityFunction function = (DLSetHoldingPriorityFunction)[splitView methodForSelector:selector];
    function(splitView, selector, priority, index);
}

@interface DLMainWindowController ()
-(void)installResizableMainSplitView;
-(void)moveView:(NSView *)view toPane:(NSView *)pane frame:(NSRect)frame autoresizingMask:(NSUInteger)mask;
-(IBAction)showThreadList:(id)sender;
-(void)hideThreadBrowser;
-(void)selectServer:(DLServer *)server;
-(void)loadChannelsForServer:(DLServer *)server;
-(void)setServerTitle:(NSString *)title;
-(void)refreshThreadOutlineForServer:(DLServer *)server;
-(void)selectChannel:(DLChannel *)channel;
-(void)messageDisplayScaleDidChange:(NSNotification *)notification;
-(void)appearanceThemeDidChange:(NSNotification *)notification;
-(void)applyCurrentTheme;
-(void)openUserSettings:(id)sender;
@end

@implementation DLMainWindowController

const CGFloat MY_USER_AVATAR_RADIUS = 18.0f;
#if LEGACY_DISCORD_UI_DIAGNOSTICS
-(NSString *)writeSanitizedUIDiagnostics {
    return [DLUIDiagnostics writeSanitizedSnapshotForWindow:self.window chatScrollView:chatScrollView];
}
#endif
#if LEGACY_DISCORD_LOCAL_DEV
-(void)showLocalReplayFixtureNamed:(NSString *)fixtureName windowSize:(NSSize)windowSize {
    NSString *name = fixtureName;
    BOOL profileNoteFixture = [name isEqualToString:@"profile-note"];
    if (![name isEqualToString:@"channel-basic"] &&
        ![name isEqualToString:@"channel-message-states"] &&
        ![name isEqualToString:@"channel-layout"] &&
        ![name isEqualToString:@"channel-layout-text"] &&
        ![name isEqualToString:@"channel-layout-unbroken"] &&
        ![name isEqualToString:@"channel-layout-states"] &&
        ![name isEqualToString:@"channel-layout-attachment"] &&
        ![name isEqualToString:@"channel-navigation"] &&
        ![name isEqualToString:@"composer-text"] &&
        ![name isEqualToString:@"composer-reply"] &&
        ![name isEqualToString:@"composer-attachment"] &&
        ![name isEqualToString:@"composer-emoji"] &&
        ![name isEqualToString:@"composer-emoji-picker"] &&
        ![name isEqualToString:@"composer-mention"] &&
        ![name isEqualToString:@"composer-typing"] &&
        ![name isEqualToString:@"composer-sticker"] &&
        !profileNoteFixture) {
        name = @"channel-basic";
    }
    [self.window setContentSize:windowSize];
    [self.window setMinSize:NSMakeSize(720.0, 520.0)];
    [self.window setTitle:[NSString stringWithFormat:@"Legacy Discord Dev — replay: %@", name]];
    [directMessageController hideFriendsHome];
    if ([name isEqualToString:@"channel-navigation"]) {
        NSArray *servers = [DLReplayFixtureProvider serversForNavigationFixture];
        DLServer *homeServer = [servers count] > 0 ? [servers objectAtIndex:0] : nil;
        DLServer *selectedServer = [servers count] > 1 ? [servers objectAtIndex:1] : homeServer;
        [serverNavigationController displayServerItems:servers
                                        selectedServer:selectedServer
                                              myServer:homeServer];
        NSArray *channels = [DLReplayFixtureProvider channelsForNavigationFixture];
        DLChannel *category = [channels count] > 0 ? [channels objectAtIndex:0] : nil;
        DLChannel *selectedChannel = [[category children] count] > 0 ? [[category children] objectAtIndex:0] : nil;
        [channelNavigationController displayChannelItems:channels
                                   showingDirectMessages:NO
                                          selectedChannel:selectedChannel];
        [DLTwemojiRenderer setText:[selectedServer name] forLabel:serverLabel];
    }
    [messageComposerController prepareForOfflineReplay];
    NSMutableArray *messages = [NSMutableArray array];
    NSEnumerator *enumerator = [[DLReplayFixtureProvider messagesForFixtureNamed:name] objectEnumerator];
    NSDictionary *messageDictionary;
    while (messageDictionary = [enumerator nextObject]) {
        DLMessage *message = [[[DLMessage alloc] initWithDict:messageDictionary] autorelease];
        [messages addObject:message];
    }
    [messagePresentationController displayReplayMessages:messages
                                              channelName:[DLReplayFixtureProvider channelNameForFixtureNamed:name]];
    if ([name hasPrefix:@"composer-"]) {
        [messageComposerController configureOfflineReplayStateNamed:name
                                                        replyMessage:[DLReplayFixtureProvider composerReplyMessage]
                                                      candidateUsers:[DLReplayFixtureProvider composerCandidateUsers]
                                                     attachmentPaths:[DLReplayFixtureProvider composerAttachmentPaths]
                                                        stickerItems:[DLReplayFixtureProvider composerStickerItems]];
    }
    if (profileNoteFixture) {
        [userProfileController showOfflineProfileNoteForUser:[DLReplayFixtureProvider profileNoteUser]
                                                       note:@"Follow up about the project plan.\nA second line tests wrapping in the note editor."];
    }
}

-(BOOL)captureLocalReplayPNGToPath:(NSString *)path {
    if (![messageComposerController offlineReplayStateIsValid]) return NO;
    NSString *fixtureName = [[[self.window title] componentsSeparatedByString:@"replay: "] lastObject];
    NSView *content = [messageComposerController offlinePickerContentViewForFixtureNamed:fixtureName];
    if (!content) content = [fixtureName isEqualToString:@"profile-note"]
        ? [userProfileController offlineProfileDetailView] : [self.window contentView];
    NSRect bounds = [content bounds];
    NSBitmapImageRep *image = [content bitmapImageRepForCachingDisplayInRect:bounds];
    if (!image) return NO;
    [content cacheDisplayInRect:bounds toBitmapImageRep:image];
    return [[image representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]] writeToFile:path atomically:YES];
}
#endif

- (void)windowDidLoad {
    [super windowDidLoad];

    [self.window setTitle:@"Legacy Discord"];
    [self.window setBackgroundColor:[DLUtil nativeContentColor]];
    [self.window setToolbar:nil];
    mainHeaderController = [[DLMainHeaderController alloc] initWithChannelHeaderView:channelViewHeader
                                                                      chatHeaderView:chatViewHeader
                                                                         serverLabel:serverLabel
                                                                     chatHeaderLabel:chatHeaderLabel
                                                                      chatScrollView:chatScrollView
                                                                        composerView:messageEntryContainerView];
    [mainHeaderController setDelegate:self];
    messageSearchController = [mainHeaderController messageSearchController];
    pinsController = [mainHeaderController pinsController];
    [messageSearchController setDelegate:self];
    [pinsController setDelegate:self];
    [self installResizableMainSplitView];
    [messageSearchController attachToHostView:chatPaneView];
    messageReadStateController = [[DLMessageReadStateController alloc] initWithChatScrollView:chatScrollView
                                                                                       window:self.window];
    threadController = [[DLThreadController alloc] initWithHostView:chatPaneView
                                                     chatScrollView:chatScrollView
                                                       composerView:messageEntryContainerView];
    [threadController setDelegate:self];
    memberListController = [[DLMemberListController alloc] initWithHostView:chatPaneView
                                                             chatScrollView:chatScrollView
                                                               composerView:messageEntryContainerView
                                                               toggleButton:[mainHeaderController memberToggleButton]];
    [memberListController setDelegate:self];
    [serversScrollView setDrawsBackground:YES];
    [serversScrollView setBackgroundColor:[DLUtil nativeServerRailColor]];
    [serversScrollView setAutohidesScrollers:YES];
    [serversScrollView setFocusRingType:NSFocusRingTypeNone];
    [[serversScrollView contentView] setBackgroundColor:[DLUtil nativeServerRailColor]];
    [serverViewScroller setBackgroundColor:[DLUtil nativeServerRailColor]];
    serverNavigationController = [[DLServerNavigationController alloc] initWithScrollView:serversScrollView];
    [serverNavigationController setDelegate:self];
    [channelsScrollView setDrawsBackground:YES];
    [channelsScrollView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [channelsScrollView setAutohidesScrollers:YES];
    [channelsScrollView setFocusRingType:NSFocusRingTypeNone];
    [[channelsScrollView contentView] setBackgroundColor:[DLUtil nativeSidebarColor]];
    [channelViewScroller setBackgroundColor:[DLUtil nativeSidebarColor]];
    channelNavigationController = [[DLChannelNavigationController alloc] initWithScrollView:channelsScrollView];
    [channelNavigationController setDelegate:self];
    directMessageController = [[DLDirectMessageController alloc] initWithHostView:chatPaneView
                                                                   chatScrollView:chatScrollView
                                                                     composerView:messageEntryContainerView
                                                                  chatHeaderLabel:chatHeaderLabel
                                                                  chatHeaderImage:chatHeaderImage
                                                             navigationTitleLabel:serverLabel
                                                                    mainSplitView:mainSplitView
                                                                  channelPaneView:channelPaneView
                                                    channelNavigationController:channelNavigationController];
    [directMessageController setDelegate:self];
    [chatScrollView setDrawsBackground:YES];
    [chatScrollView setBackgroundColor:[DLUtil nativeContentColor]];
    [chatScrollView setAutohidesScrollers:YES];
    [[chatScrollView contentView] setBackgroundColor:[DLUtil nativeContentColor]];
    [chatViewScroller setBackgroundColor:[DLUtil nativeContentColor]];

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

    messageComposerController = [[DLMessageComposerController alloc] initWithWindow:self.window
                                                                      containerView:messageEntryContainerView
                                                                           textView:messageEntryTextView
                                                                     textScrollView:messageEntryScrollView
                                                                     chatScrollView:chatScrollView
                                                       pendingAttachmentsScrollView:pendingAttachmentsScrollView
                                                             tagSelectionScrollView:tagSelectionScrollView
                                                                          replyView:replyToView
                                                                     replyTextField:replyToTextField
                                                               typingStatusTextField:typingStatusTextField
                                                                       attachButton:attachButton
                                                                       textScroller:messageEntryViewScroller
                                                                tagSelectionScroller:tagSelectionViewScroller
                                                           pendingAttachmentScroller:pendingAttachmentViewScroller];
    [messageComposerController setDelegate:self];
    
    isLoadingViews = NO;
#if !LEGACY_DISCORD_LOCAL_DEV
    [[DLController sharedInstance] setDelegate:self];
#endif
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messageDisplayScaleDidChange:) name:DLMessageDisplayScaleDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appearanceThemeDidChange:) name:DLAppearanceThemeDidChangeNotification object:nil];
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    [myUserAvatarImage setImage:[DLUtil imageResize:[[[NSImage alloc] initWithContentsOfFile:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"discord_placeholder.png"]] autorelease] newSize:myUserAvatarImage.frame.size cornerRadius:MY_USER_AVATAR_RADIUS]];
    userProfileController = [[DLUserProfileController alloc] initWithHostWindow:self.window
                                                                   userInfoView:userInfoView
                                                                     avatarView:myUserAvatarImage];
    messagePresentationController = [[DLMessagePresentationController alloc] initWithWindow:self.window
                                                                              chatScrollView:chatScrollView
                                                                             chatHeaderLabel:chatHeaderLabel
                                                                             chatHeaderImage:chatHeaderImage
                                                                                reloadButton:[mainHeaderController reloadButton]
                                                                         readStateController:messageReadStateController
                                                                            searchController:messageSearchController
                                                                              pinsController:pinsController
                                                                channelNavigationController:channelNavigationController
                                                                          composerController:messageComposerController
                                                                       userProfileController:userProfileController];
    [messagePresentationController setDelegate:self];
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
    DLSetSplitHoldingPriorityIfSupported(mainSplitView, 251.0, 0);
    DLSetSplitHoldingPriorityIfSupported(mainSplitView, 250.0, 1);
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
    [self splitView:mainSplitView resizeSubviewsWithOldSize:[mainSplitView bounds].size];
}

-(void)mainWindowDidResize:(NSNotification *)notification {
#if LEGACY_DISCORD_UI_DIAGNOSTICS
    [DLUIDiagnostics recordEvent:@"window-resized" details:[NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSNumber numberWithDouble:NSWidth([[self.window contentView] bounds])], @"width",
                                      [NSNumber numberWithDouble:NSHeight([[self.window contentView] bounds])], @"height", nil]];
#endif
#if LEGACY_DISCORD_LOCAL_DEV
    return;
#endif
    BOOL showingDM = [[[DLController sharedInstance] selectedServer] isEqual:[[DLController sharedInstance] myServerItem]];
    [directMessageController updateResponsiveLayoutForWindowWidth:NSWidth([[self.window contentView] bounds])
                                            showingDirectMessages:showingDM];
}

-(void)mainHeaderControllerDidRequestMemberListToggle:(DLMainHeaderController *)controller {
    DLServer *server = [[DLController sharedInstance] selectedServer];
    if (!server || [server isEqual:[[DLController sharedInstance] myServerItem]]) {
        NSBeep();
        return;
    }
    if (![memberListController isVisible] && [threadController isVisible]) return;
    if (![memberListController isVisible] && [messageSearchController isVisible]) {
        [messageSearchController close];
    }
    [memberListController setVisible:![memberListController isVisible]
                              server:server
                             channel:[[DLController sharedInstance] selectedChannel]];
}

-(IBAction)showThreadList:(id)sender {
    if ([messageSearchController isVisible]) [messageSearchController close];
    if ([memberListController isVisible]) [memberListController setVisible:NO server:nil channel:nil];
    [threadController showThreadList];
}

-(void)hideThreadBrowser {
    [threadController hideThreadBrowser];
}

-(void)threadController:(DLThreadController *)controller selectChannel:(DLChannel *)channel {
    [self selectChannel:channel];
}

-(void)threadController:(DLThreadController *)controller restoreBaseChannel:(DLChannel *)channel {
    [[DLController sharedInstance] setSelectedChannel:channel];
    [DLTwemojiRenderer setText:[channel name] forLabel:chatHeaderLabel];
}

-(void)messageSearchControllerWillShow:(DLMessageSearchController *)controller {
    [pinsController deactivate];
    if ([memberListController isVisible]) [memberListController setVisible:NO server:nil channel:nil];
}

-(void)messageSearchControllerDidClose:(DLMessageSearchController *)controller {
    [pinsController deactivate];
}

-(BOOL)pinsControllerMayOpen:(DLPinsController *)controller {
    return ![threadController isVisible];
}

-(void)messageComposerController:(DLMessageComposerController *)controller sendPreparedMessage:(DLMessage *)message toChannel:(DLChannel *)channel {
    [[DLController sharedInstance] sendMessage:message toChannel:channel];
}

-(void)messageComposerController:(DLMessageComposerController *)controller informTypingInChannel:(DLChannel *)channel {
    [[DLController sharedInstance] informTypingInChannel:channel];
}

-(void)messageComposerController:(DLMessageComposerController *)controller queryServer:(DLServer *)server forMembersContainingUsername:(NSString *)username {
    [[DLController sharedInstance] queryServer:server forMembersContainingUsername:username];
}
-(CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex {
    return directMessageController ? [directMessageController minimumSplitCoordinate] : 180.0;
}

-(CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex {
    return MIN(360.0, NSWidth([splitView bounds]) - 320.0 - [splitView dividerThickness]);
}

-(void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize {
    if (splitView != mainSplitView) return;
    NSRect bounds = [splitView bounds];
    CGFloat divider = [splitView dividerThickness];
    CGFloat minimum = directMessageController ? [directMessageController minimumSplitCoordinate] : 180.0;
    CGFloat maximum = MAX(minimum, MIN(360.0, NSWidth(bounds) - 320.0 - divider));
    CGFloat channelWidth = MIN(maximum, MAX(minimum, NSWidth([channelPaneView frame])));
    [channelPaneView setFrame:NSMakeRect(0.0, 0.0, channelWidth, NSHeight(bounds))];
    [chatPaneView setFrame:NSMakeRect(channelWidth + divider, 0.0,
                                    MAX(0.0, NSWidth(bounds) - channelWidth - divider), NSHeight(bounds))];
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
#if LEGACY_DISCORD_UI_DIAGNOSTICS
    [DLUIDiagnostics recordEvent:@"display-scale-changed" details:[NSDictionary dictionaryWithObject:[NSNumber numberWithDouble:[[DLPreferencesHandler sharedInstance] messageDisplayScale]] forKey:@"display_scale"]];
#endif
#if LEGACY_DISCORD_LOCAL_DEV
    [chatScrollView screenResize];
    return;
#endif
    if ([[DLController sharedInstance] selectedChannel]) {
        [messagePresentationController reloadSelectedChannel];
    }
}

-(void)appearanceThemeDidChange:(NSNotification *)notification {
#if LEGACY_DISCORD_UI_DIAGNOSTICS
    [DLUIDiagnostics recordEvent:@"theme-changed" details:[NSDictionary dictionaryWithObject:[[DLPreferencesHandler sharedInstance] appearanceTheme] forKey:@"theme"]];
#endif
    [self applyCurrentTheme];
}

-(void)applyCurrentTheme {
    [self.window setBackgroundColor:[DLUtil nativeContentColor]];
    [serversScrollView setBackgroundColor:[DLUtil nativeServerRailColor]];
    [[serversScrollView contentView] setBackgroundColor:[DLUtil nativeServerRailColor]];
    [serverViewScroller setBackgroundColor:[DLUtil nativeServerRailColor]];
    [serverViewScroller setNeedsDisplay:YES];
    [serverNavigationController applyCurrentTheme];
    [channelsScrollView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [[channelsScrollView contentView] setBackgroundColor:[DLUtil nativeSidebarColor]];
    [channelViewScroller setBackgroundColor:[DLUtil nativeSidebarColor]];
    [channelViewScroller setNeedsDisplay:YES];
    [channelNavigationController applyCurrentTheme];
    [memberListController applyCurrentTheme];
    [userProfileController applyCurrentTheme];
    [threadController applyCurrentTheme];
    [messageSearchController applyCurrentTheme];
    [chatScrollView setBackgroundColor:[DLUtil nativeContentColor]];
    [[chatScrollView contentView] setBackgroundColor:[DLUtil nativeContentColor]];
    [chatViewScroller setBackgroundColor:[DLUtil nativeContentColor]];
    [chatViewScroller setNeedsDisplay:YES];
    [channelViewHeader setGradientStartColor:[DLUtil nativeHeaderTopColor] endColor:[DLUtil nativeHeaderBottomColor]];
    [chatViewHeader setGradientStartColor:[DLUtil nativeHeaderTopColor] endColor:[DLUtil nativeHeaderBottomColor]];
    [channelViewHeader setBottomBorderColor:[DLUtil nativeBorderColor]];
    [chatViewHeader setBottomBorderColor:[DLUtil nativeBorderColor]];
    [userInfoView setBackgroundColor:[DLUtil nativeChromeColor]];
    [mainHeaderController applyCurrentTheme];
    [messageComposerController applyCurrentTheme];
    [directMessageController applyCurrentTheme];
    [chatScrollView setNeedsDisplay:YES];
    [[self.window contentView] setNeedsDisplay:YES];
}

-(void)connectionStateDidChange:(DLWSConnectionState)state {
    [mainHeaderController setConnectionState:state];
}

-(void)mainHeaderControllerDidRequestReload:(DLMainHeaderController *)controller {
    [messagePresentationController reloadSelectedChannel];
}

-(void)setDelegate:(id<DLMainWindowDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)serverNavigationController:(DLServerNavigationController *)controller didSelectServer:(DLServer *)server {
    [self selectServer:server];
}

-(void)serverNavigationControllerDidFinishDisplayingItems:(DLServerNavigationController *)controller {
    isLoadingViews = NO;
}

-(void)channelNavigationController:(DLChannelNavigationController *)controller didSelectChannel:(DLChannel *)channel {
    [self hideThreadBrowser];
    [self selectChannel:channel];
}

-(void)channelNavigationController:(DLChannelNavigationController *)controller
          didFinishDisplayingItems:(NSArray *)items
             showingDirectMessages:(BOOL)showingDirectMessages
                    selectedChannel:(DLChannel *)selectedChannel {
    isLoadingViews = NO;
    if (showingDirectMessages && !selectedChannel) {
        [directMessageController showFriendsHomeWithChannels:items];
    }
}

-(void)channelNavigationController:(DLChannelNavigationController *)controller
       imageDidUpdateWithData:(NSData *)data
                   forChannel:(DLChannel *)channel {
    [directMessageController channelImageDidUpdate:channel];
    if ([channel isEqual:[[DLController sharedInstance] selectedChannel]]) {
        NSImage *headerAvatar = [[[NSImage alloc] initWithData:data] autorelease];
        if (headerAvatar) [chatHeaderImage setImage:headerAvatar];
    }
}

-(void)memberListController:(DLMemberListController *)controller
              didSelectUser:(DLUser *)user
             relativeToRect:(NSRect)rect
                     ofView:(NSView *)view {
    [userProfileController showProfileForUser:user relativeToRect:rect ofView:view];
}

-(void)memberListController:(DLMemberListController *)controller avatarDidUpdateForUser:(DLUser *)user {
    [userProfileController avatarDidUpdateForUser:user data:[user avatarImageData]];
}

-(void)directMessageController:(DLDirectMessageController *)controller didSelectChannel:(DLChannel *)channel {
    [self selectChannel:channel];
}

#pragma mark Native Server Table

-(void)selectServer:(DLServer *)server {
    if (![server isEqual:[[DLController sharedInstance] myServerItem]]) {
        [directMessageController restoreExpandedLayout];
    }
    [self.window setTitle:([server isEqual:[[DLController sharedInstance] myServerItem]] ? @"Direct Messages" : ([server name] ? [server name] : @"Legacy Discord"))];
    if ([memberListController isVisible]) {
        [memberListController setVisible:NO server:nil channel:nil];
    }
    [self hideThreadBrowser];
    [mainHeaderController setMembersEnabled:![server isEqual:[[DLController sharedInstance] myServerItem]]];
    [pinsController setEnabled:NO];
    [messageComposerController setEnabledForChannel:nil];
    [chatScrollView unregisterDraggedTypes];
    [messageComposerController reset];
    [[DLController sharedInstance] setSelectedChannel:nil];
    [messagePresentationController prepareForServerChange];
    [directMessageController hideFriendsHome];

    if ([server isEqual:[[DLController sharedInstance] myServerItem]]) {
        [NSThread detachNewThreadSelector:@selector(loadDirectMessageChannels) toTarget:self withObject:nil];
    } else {
        [[DLController sharedInstance] loadActiveThreadsForServer:server];
        [NSThread detachNewThreadSelector:@selector(loadChannelsForServer:) toTarget:self withObject:server];
    }
}

-(void)selectChannel:(DLChannel *)channel {
    [directMessageController hideFriendsHome];
    [messageSearchController resetForChannelChange];
    [pinsController deactivate];
    [pinsController setEnabled:(channel != nil && [channel type] != ChannelTypeForum && [channel type] != ChannelTypeMedia)];
    [messagePresentationController prepareForChannelChange];
    if ([channel type] == ChannelTypeForum || [channel type] == ChannelTypeMedia) {
        [[DLController sharedInstance] setSelectedChannel:channel];
        [DLTwemojiRenderer setText:[channel name] forLabel:chatHeaderLabel];
        [messageComposerController setEnabledForChannel:nil];
        [messageComposerController reset];
        [self showThreadList:nil];
        return;
    }
    [messageComposerController setEnabledForChannel:channel];
    [chatScrollView registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, nil]];
    [messageComposerController reset];
    [DLTwemojiRenderer setText:[channel name] ? [channel name] : @"Direct Message" forLabel:chatHeaderLabel];
    NSData *headerImageData = ([channel type] == ChannelTypeDM || [channel type] == ChannelTypeGroup)
        ? [channel imageData] : [channel subImageData];
    [chatHeaderImage setImage:[[[NSImage alloc] initWithData:headerImageData] autorelease]];
    [messagePresentationController loadInitialMessagesForChannel:channel];
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
        [serverNavigationController performSelectorOnMainThread:@selector(displayServerItems:)
                                                      withObject:items
                                                   waitUntilDone:YES];
        [items release];
    }

    [autoreleasepool release];
}

-(void)setServerTitle:(NSString *)title {
    [DLTwemojiRenderer setText:title forLabel:serverLabel];
}

-(void)loadChannelsForServer:(DLServer *)server {
    NSAutoreleasePool *autoreleasepool = [[NSAutoreleasePool alloc] init];
    if (!isLoadingViews) {
        isLoadingViews = YES;

        NSArray *channels = [[DLController sharedInstance] channelsForServer:server];
        [self performSelectorOnMainThread:@selector(setServerTitle:) withObject:[server name] waitUntilDone:NO];
        [channelNavigationController performSelectorOnMainThread:@selector(displayChannelItems:)
                                                       withObject:channels waitUntilDone:NO];
    }

    [autoreleasepool release];
}

-(void)refreshThreadOutlineForServer:(DLServer *)server {
    if (!server || ![server isEqual:[[DLController sharedInstance] selectedServer]]) return;
    [channelNavigationController displayChannelItems:[[DLController sharedInstance] channelsForServer:server]];
    [threadController refreshForServer:server];
}

-(void)threadsDidUpdateForServer:(DLServer *)server {
    [threadController threadsDidUpdateForServer:server];
}

-(void)archivedThreadsDidUpdateForServer:(DLServer *)server channel:(DLChannel *)channel {
    [threadController archivedThreadsDidUpdateForServer:server channel:channel];
}
-(void)loadDirectMessageChannels {
    NSAutoreleasePool *autoreleasepool = [[NSAutoreleasePool alloc] init];
    if (!isLoadingViews) {
        isLoadingViews = YES;

        NSArray *channels = [[DLController sharedInstance] directMessageChannels];
        [directMessageController displayDirectMessageChannels:channels];
    }

    [autoreleasepool release];
}

-(void)logOutUser {
    [[DLController sharedInstance] logOutUser];
}

- (IBAction)showFileOpenDialog:(id)sender {
    [messageComposerController showFileOpenDialog];
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

- (IBAction)removeReferencedMessage:(id)sender {
    [messageComposerController removeReferencedMessage];
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [messagePresentationController setDelegate:nil];
    [messagePresentationController release];
    [messageSearchController setDelegate:nil];
    [pinsController setDelegate:nil];
    [mainHeaderController setDelegate:nil];
    [messageReadStateController setDelegate:nil];
    [messageReadStateController release];
    [userProfileController release];
    [memberListController setDelegate:nil];
    [memberListController release];
    [threadController setDelegate:nil];
    [threadController release];
    [messageComposerController setDelegate:nil];
    [messageComposerController release];
    [directMessageController setDelegate:nil];
    [directMessageController release];
    [mainHeaderController release];
    [channelNavigationController setDelegate:nil];
    [channelNavigationController release];
    [serverNavigationController setDelegate:nil];
    [serverNavigationController release];
    [mainSplitView setDelegate:nil];
    [channelPaneView release];
    [chatPaneView release];
    [mainSplitView release];
    [super dealloc];
}

#pragma mark Delegated Functions

-(void)initialDataWasReceived {
    [NSThread detachNewThreadSelector:@selector(populateUserServers) toTarget:self withObject:nil];
    [self loadMainContent];
}

-(void)requestDidFailWithError:(DLError *)error {
    [pinsController requestDidFail];
    [DLErrorHandler displayError:error onWindow:self.window];
}

-(void)channelPins:(NSArray *)messages didLoadForChannel:(DLChannel *)channel {
    [pinsController channelPins:messages didLoadForChannel:channel];
}

-(void)messageSearchResults:(NSArray *)messages totalResults:(NSInteger)total offset:(NSInteger)offset
                 forChannel:(DLChannel *)channel query:(NSString *)query {
    [messageSearchController messageSearchResults:messages totalResults:total offset:offset
                                        forChannel:channel query:query];
}

-(void)messages:(NSArray *)messages receivedAroundSearchResult:(NSString *)messageID forChannel:(DLChannel *)channel {
    [messagePresentationController messages:messages
                   receivedAroundSearchResult:messageID
                                   forChannel:channel];
}

-(void)user:(DLUser *)user avatarDidUpdateWithData:(NSData *)data {
    if ([user isEqual:[[DLController sharedInstance] myUser]]) {
        [myUserAvatarImage setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:data] autorelease]
                                                newSize:[myUserAvatarImage frame].size
                                           cornerRadius:MY_USER_AVATAR_RADIUS]];
    }
    [userProfileController avatarDidUpdateForUser:user data:data];
}

-(void)messages:(NSArray *)messages receivedForChannel:(DLChannel *)channel {
    [messagePresentationController messages:messages receivedForChannel:channel];
}

-(void)newerMessages:(NSArray *)messages receivedForChannel:(DLChannel *)channel {
    [messagePresentationController newerMessages:messages receivedForChannel:channel];
}

-(void)newMessage:(DLMessage *)message receivedForChannel:(DLChannel *)channel inServer:(DLServer *)server {
    [messagePresentationController newMessage:message receivedForChannel:channel inServer:server];
}

-(void)messagePresentationControllerNeedsDirectMessageRefresh:(DLMessagePresentationController *)controller {
    [NSThread detachNewThreadSelector:@selector(loadDirectMessageChannels) toTarget:self withObject:nil];
}

-(void)didLogoutSuccessfully {
    [delegate logoutWasSuccessful];
}

-(void)userDidStartTypingInSelectedChannel:(DLUser *)user {
    [messageComposerController userDidStartTyping:user];
}

-(void)userDidStopTyping:(DLUser *)user {
    [messageComposerController userDidStopTyping:user];
}

-(void)members:(NSArray *)members didUpdateForServer:(DLServer *)server {
    [memberListController members:members didUpdateForServer:server];
    [userProfileController members:members didUpdateForServer:server];
    [messageSearchController members:members didUpdateForServer:server];
    [messageComposerController membersDidUpdate:members];
}

-(void)userProfile:(NSDictionary *)profile didLoadForUser:(DLUser *)user inServer:(DLServer *)server {
    [userProfileController userProfile:profile didLoadForUser:user inServer:server];
}

-(void)userNote:(NSString *)note didLoadForUser:(DLUser *)user error:(BOOL)error {
    [userProfileController userNote:note didLoadForUser:user error:error];
}

-(void)userNote:(NSString *)note didSaveForUser:(DLUser *)user error:(BOOL)error {
    [userProfileController userNote:note didSaveForUser:user error:error];
}

@end
