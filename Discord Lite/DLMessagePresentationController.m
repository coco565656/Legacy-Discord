//
//  DLMessagePresentationController.m
//  Legacy Discord
//

#import "DLMessagePresentationController.h"
#import "DLLocalization.h"
#import "DLDialog.h"
#import "ChatScrollView.h"
#import "DLController.h"
#import "DLChannel.h"
#import "DLDirectMessageChannel.h"
#import "DLServer.h"
#import "DLUser.h"
#import "DLMessage.h"
#import "DLMessageSearchController.h"
#import "DLPinsController.h"
#import "DLChannelNavigationController.h"
#import "DLMessageComposerController.h"
#import "DLUserProfileController.h"
#import "DLAudioPlayer.h"
#import "DLPreferencesHandler.h"
#import "DLTwemojiRenderer.h"


@interface DLMessagePresentationController ()
-(ChatItemViewController *)chatItemViewForMessage:(DLMessage *)message isMyContent:(BOOL)isMyContent;
-(void)chatScrollViewBoundsDidChange:(NSNotification *)notification;
@end

// Notification Center banner for a mention or DM (OS X 10.8+; the class
// does not exist on 10.6/10.7, so it is looked up at run time).
static void DLPostDesktopNotification(DLMessage *message, DLChannel *channel, DLServer *server, BOOL isDirect) {
    Class notificationClass = NSClassFromString(@"NSUserNotification");
    Class centerClass = NSClassFromString(@"NSUserNotificationCenter");
    if (!notificationClass || !centerClass) return;
    DLUser *author = [message author];
    NSString *name = [author globalName] ? [author globalName] : [author username];
    NSString *title = name ? name : @"Legacy Discord";
    if (!isDirect && [channel name]) {
        title = [NSString stringWithFormat:@"%@ (#%@, %@)", title, [channel name], [server name] ? [server name] : @""];
    }
    NSString *body = [[message content] length] ? [message content]
                   : ([[message attachments] count] ? DLLocalizedString(@"Uploaded a file") : DLLocalizedString(@"Sent a message"));
    id notification = [[[notificationClass alloc] init] autorelease];
    [notification performSelector:NSSelectorFromString(@"setTitle:") withObject:title];
    [notification performSelector:NSSelectorFromString(@"setInformativeText:") withObject:body];
    id center = [centerClass performSelector:NSSelectorFromString(@"defaultUserNotificationCenter")];
    [center performSelector:NSSelectorFromString(@"deliverNotification:") withObject:notification];
}

@implementation DLMessagePresentationController

-(id)initWithWindow:(NSWindow *)inWindow
      chatScrollView:(ChatScrollView *)inChatScrollView
     chatHeaderLabel:(NSTextField *)inChatHeaderLabel
     chatHeaderImage:(NSImageView *)inChatHeaderImage
        reloadButton:(NSButton *)inReloadButton
 readStateController:(DLMessageReadStateController *)inReadStateController
    searchController:(DLMessageSearchController *)inSearchController
      pinsController:(DLPinsController *)inPinsController
channelNavigationController:(DLChannelNavigationController *)inChannelNavigationController
  composerController:(DLMessageComposerController *)inComposerController
userProfileController:(DLUserProfileController *)inUserProfileController {
    self = [super init];
    if (self) {
        hostWindow = inWindow;
        chatScrollView = [inChatScrollView retain];
        chatHeaderLabel = [inChatHeaderLabel retain];
        chatHeaderImage = [inChatHeaderImage retain];
        reloadButton = [inReloadButton retain];
        readStateController = [inReadStateController retain];
        searchController = [inSearchController retain];
        pinsController = [inPinsController retain];
        channelNavigationController = [inChannelNavigationController retain];
        composerController = [inComposerController retain];
        userProfileController = [inUserProfileController retain];
        [readStateController setDelegate:self];
        [[chatScrollView contentView] setPostsBoundsChangedNotifications:YES];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(chatScrollViewBoundsDidChange:)
                                                     name:NSViewBoundsDidChangeNotification
                                                   object:[chatScrollView contentView]];
    }
    return self;
}

-(void)setDelegate:(id<DLMessagePresentationControllerDelegate>)inDelegate {
    delegate = inDelegate;
}

-(ChatItemViewController *)chatItemViewForMessage:(DLMessage *)message isMyContent:(BOOL)isMyContent {
    ChatItemViewController *view = [[[ChatItemViewController alloc] initWithNibNamed:@"ChatItemViewController" bundle:nil] autorelease];
    [view setDelegate:self];
    [view setRepresentedObject:message];
    if (isMyContent) {
        [view setIsMyContent:YES];
    }
    return view;
}

-(void)prepareForServerChange {
    lastMessage = nil;
    firstMessage = nil;
    isLoadingMessages = NO;
    isLoadingNewerMessages = NO;
    searchHistoryWindowActive = NO;
    hasMoreNewerMessages = NO;
    [chatScrollView setContent:[NSArray array]];
    [DLTwemojiRenderer setText:DLLocalizedString(@"Select a channel") forLabel:chatHeaderLabel];
    [chatHeaderImage setImage:nil];
}

-(void)prepareForChannelChange {
    lastMessage = nil;
    firstMessage = nil;
    isLoadingMessages = NO;
    isLoadingNewerMessages = NO;
    searchHistoryWindowActive = NO;
    hasMoreNewerMessages = NO;
    [readStateController resetUnreadMessageState];
}

-(void)loadInitialMessagesForChannel:(DLChannel *)channel {
    if (!channel) {
        return;
    }
    isLoadingMessages = YES;
    [[DLController sharedInstance] loadMessagesForChannel:channel
                                           beforeMessage:nil
                                                quantity:([channel isThread] ? 15 : 25)];
}

-(void)reloadSelectedChannel {
    DLChannel *channel = [[DLController sharedInstance] selectedChannel];
    if (!channel) {
        NSBeep();
        return;
    }
    [searchController resetForChannelChange];
    [pinsController deactivate];
    [reloadButton setEnabled:NO];
    [self prepareForChannelChange];
    isLoadingMessages = YES;
    [[DLController sharedInstance] loadMessagesForChannel:channel beforeMessage:nil quantity:25];
}

-(DLMessage *)latestMessageForMessageReadStateController:(DLMessageReadStateController *)controller {
    return firstMessage;
}

-(void)chatScrollViewBoundsDidChange:(NSNotification *)notification {
#if LEGACY_DISCORD_LOCAL_DEV
    return;
#else
    NSClipView *scrolledClipView = [notification object];
    if (searchHistoryWindowActive && hasMoreNewerMessages && !isLoadingNewerMessages &&
        [scrolledClipView bounds].origin.y <= 1.0 && firstMessage) {
        isLoadingNewerMessages = YES;
        [[DLController sharedInstance] loadMessagesForChannel:[[DLController sharedInstance] selectedChannel]
                                                afterMessage:firstMessage
                                                    quantity:25];
    }
    if ([[chatScrollView documentView] bounds].size.height <=
        [scrolledClipView bounds].size.height + [scrolledClipView bounds].origin.y) {
        if (!isLoadingMessages) {
            isLoadingMessages = YES;
            if ([[DLController sharedInstance] selectedChannel]) {
                [[DLController sharedInstance] loadMessagesForChannel:[[DLController sharedInstance] selectedChannel]
                                                        beforeMessage:lastMessage
                                                             quantity:25];
            }
        }
    }
#endif
}

#if LEGACY_DISCORD_LOCAL_DEV
-(void)displayReplayMessages:(NSArray *)messages channelName:(NSString *)channelName {
    localReplayActive = YES;
    lastMessage = nil;
    firstMessage = nil;
    [DLTwemojiRenderer setText:channelName forLabel:chatHeaderLabel];
    [chatHeaderImage setImage:nil];
    NSMutableArray *views = [NSMutableArray arrayWithCapacity:[messages count]];
    NSEnumerator *enumerator = [messages objectEnumerator];
    DLMessage *message;
    while (message = [enumerator nextObject]) {
        [views addObject:[self chatItemViewForMessage:message isMyContent:NO]];
        if (!firstMessage) {
            firstMessage = message;
        }
        lastMessage = message;
    }
    [chatScrollView setContent:views];
    [chatScrollView screenResize];
    [[chatScrollView contentView] scrollToPoint:NSMakePoint(0.0, 0.0)];
    [chatScrollView reflectScrolledClipView:[chatScrollView contentView]];
}
#endif

-(void)messages:(NSArray *)messages receivedAroundSearchResult:(NSString *)messageID forChannel:(DLChannel *)channel {
    if (![[[DLController sharedInstance] selectedChannel] isEqual:channel]) {
        return;
    }
    NSMutableArray *views = [NSMutableArray arrayWithCapacity:[messages count]];
    lastMessage = nil;
    firstMessage = nil;
    NSEnumerator *enumerator = [messages objectEnumerator];
    DLMessage *message;
    while (message = [enumerator nextObject]) {
        if (![message serverID] && [channel serverID]) {
            [message setServerID:[channel serverID]];
        }
        [views addObject:[self chatItemViewForMessage:message
                                         isMyContent:[[message author] isEqual:[[DLController sharedInstance] myUser]]]];
        if (!firstMessage) {
            firstMessage = message;
        }
        lastMessage = message;
    }
    [searchController clearHighlight];
    [chatScrollView setContent:views];
    [chatScrollView screenResize];
    // The header title (topic, thread breadcrumb) is set when the channel is
    // selected; repainting the bare name here dropped both.
    [channelNavigationController selectChannelWithoutNotifying:channel];
    [searchController didDisplayMessagesAroundID:messageID];
    searchHistoryWindowActive = YES;
    hasMoreNewerMessages = YES;
    isLoadingNewerMessages = NO;
    isLoadingMessages = NO;
}

-(void)messages:(NSArray *)messages receivedForChannel:(DLChannel *)channel {
    BOOL newChannel = (lastMessage == nil);
    NSMutableArray *views = [[NSMutableArray alloc] init];
    NSMutableDictionary *existingViewsByMessageID = [NSMutableDictionary dictionary];
    NSEnumerator *existingEnumerator = [[chatScrollView content] objectEnumerator];
    ChatItemViewController *existingView;
    while (existingView = [existingEnumerator nextObject]) {
        NSString *messageID = [[[[existingView representedObject] messageID] description] copy];
        if (messageID) {
            [existingViewsByMessageID setObject:existingView forKey:messageID];
            [messageID release];
        }
    }
    NSEnumerator *enumerator = [messages objectEnumerator];
    DLMessage *message;
    while (message = [enumerator nextObject]) {
        if (![[[DLController sharedInstance] selectedServer] isEqual:[[DLController sharedInstance] myServerItem]]) {
            [message setServerID:[[[DLController sharedInstance] selectedServer] serverID]];
        }
        NSString *messageID = [[message messageID] description];
        ChatItemViewController *view = messageID ? [existingViewsByMessageID objectForKey:messageID] : nil;
        if (!view) {
            view = [self chatItemViewForMessage:message
                                   isMyContent:[[message author] isEqual:[[DLController sharedInstance] myUser]]];
        } else {
            [view setRepresentedObject:message];
            if ([[message author] isEqual:[[DLController sharedInstance] myUser]]) {
                [view setIsMyContent:YES];
            }
        }
        [views addObject:view];
        if (newChannel && !firstMessage) {
            firstMessage = message;
        }
        lastMessage = message;
    }
    if (newChannel) {
        searchHistoryWindowActive = NO;
        hasMoreNewerMessages = NO;
        isLoadingNewerMessages = NO;
        [chatScrollView setContent:views];
        [[chatScrollView contentView] scrollToPoint:NSMakePoint([chatScrollView frame].origin.x,
                                                                [chatScrollView frame].origin.y)];
        [chatScrollView reflectScrolledClipView:[chatScrollView contentView]];
        if ([channel hasUnreadMessages] || [channel mentionCount] > 0) {
            [[DLController sharedInstance] acknowledgeMessage:[channel lastMessage]];
        }
    } else {
        [chatScrollView appendContent:views];
    }
    [views release];
    [reloadButton setEnabled:YES];
    isLoadingMessages = NO;
}

-(void)newerMessages:(NSArray *)messages receivedForChannel:(DLChannel *)channel {
    if (!searchHistoryWindowActive || ![[[DLController sharedInstance] selectedChannel] isEqual:channel]) {
        isLoadingNewerMessages = NO;
        return;
    }
    if ([messages count] == 0) {
        hasMoreNewerMessages = NO;
        isLoadingNewerMessages = NO;
        return;
    }
    NSMutableSet *existingIDs = [NSMutableSet set];
    NSEnumerator *existingEnumerator = [[chatScrollView content] objectEnumerator];
    ChatItemViewController *existingView;
    while (existingView = [existingEnumerator nextObject]) {
        NSString *existingID = [[[[existingView representedObject] messageID] description] copy];
        if (existingID) {
            [existingIDs addObject:existingID];
            [existingID release];
        }
    }
    NSMutableArray *views = [NSMutableArray array];
    NSEnumerator *messageEnumerator = [messages objectEnumerator];
    DLMessage *message;
    while (message = [messageEnumerator nextObject]) {
        if ([existingIDs containsObject:[[message messageID] description]]) {
            continue;
        }
        [views addObject:[self chatItemViewForMessage:message
                                         isMyContent:[[message author] isEqual:[[DLController sharedInstance] myUser]]]];
    }
    firstMessage = [messages objectAtIndex:0];
    [chatScrollView prependContent:views preservingVisiblePosition:YES];
    isLoadingNewerMessages = NO;
}

-(void)newMessage:(DLMessage *)message receivedForChannel:(DLChannel *)channel inServer:(DLServer *)server {
    if (![server isEqual:[[DLController sharedInstance] myServerItem]]) {
        [message setServerID:[server serverID]];
    }
    if ([channel isEqual:[[DLController sharedInstance] selectedChannel]]) {
        BOOL isMyMessage = [[message author] isEqual:[[DLController sharedInstance] myUser]];
        BOOL wasViewingLatest = [readStateController isViewingLatestMessages];
        BOOL shouldPreservePosition = !isMyMessage && !wasViewingLatest;
        BOOL shouldRecordUnread = !isMyMessage && (![hostWindow isKeyWindow] || !wasViewingLatest);
        ChatItemViewController *view = [self chatItemViewForMessage:message isMyContent:isMyMessage];
        [chatScrollView prependContent:[NSArray arrayWithObject:view]
             preservingVisiblePosition:shouldPreservePosition];
        firstMessage = message;
        [[message author] setTyping:NO];
        [composerController userDidStopTyping:[message author]];
        if (isMyMessage || (wasViewingLatest && [hostWindow isKeyWindow])) {
            NSPoint latestPoint = [[chatScrollView contentView] bounds].origin;
            latestPoint.y = 0.0;
            [[chatScrollView contentView] scrollToPoint:latestPoint];
            [chatScrollView reflectScrolledClipView:[chatScrollView contentView]];
            [[DLController sharedInstance] acknowledgeMessage:message];
            if (isMyMessage && [readStateController hasPendingMessages]) {
                [readStateController resetUnreadMessageState];
            }
        } else if (shouldRecordUnread) {
            [channel setHasUnreadMessages:YES];
            if (server && ![server isEqual:[[DLController sharedInstance] myServerItem]]) {
                [server setHasUnreadMessages:YES];
            }
            [readStateController recordUnreadMessage:message];
        }
    }

    DLController *controller = [DLController sharedInstance];
    BOOL mentioned = NO;
    NSEnumerator *enumerator = [[message mentionedUsers] objectEnumerator];
    DLUser *user;
    if (![[message author] isEqual:[controller myUser]]) {
        // Mentions inside a forwarded message do not ping, like Discord.
        while (![message isForwarded] && (user = [enumerator nextObject])) {
            if ([user isEqual:[controller myUser]]) {
                mentioned = YES;
            }
        }
        // @everyone/@here count unless the server suppresses them.
        if ([message mentionedEveryone] && ![message isForwarded] &&
            ![controller suppressesEveryoneInServerWithID:[server serverID]]) {
            mentioned = YES;
        }
        NSEnumerator *roleEnumerator = [[message mentionedRoleIDs] objectEnumerator];
        NSString *roleID;
        while (!mentioned && (roleID = [roleEnumerator nextObject])) {
            if ([[server myRoleIDs] containsObject:roleID]) mentioned = YES;
        }
        BOOL isDirect = [channel isKindOfClass:[DLDirectMessageChannel class]];
        // Muted conversations keep their badge but make no sound or bounce.
        BOOL muted = [controller isChannelMuted:channel];
        if (mentioned || isDirect) {
            BOOL viewing = [[controller selectedChannel] isEqual:channel] && [hostWindow isKeyWindow];
            if (!viewing) {
                [channel notifyOfNewMention];
                [server notifyOfNewMention];
                if (!muted) {
                    [[DLAudioPlayer sharedInstance] playAudioWithID:AudioIDNotificationNewMention];
                    if (![NSApp isActive] && [[DLPreferencesHandler sharedInstance] desktopNotifications]) {
                        DLPostDesktopNotification(message, channel, server, isDirect);
                    }
                    if (![NSApp isActive] && [[DLPreferencesHandler sharedInstance] bounceDockIcon]) {
                        [NSApp requestUserAttention:NSInformationalRequest];
                    }
                }
            }
        }
    }
    if (![channel isEqual:[[DLController sharedInstance] selectedChannel]]) {
        [channel setHasUnreadMessages:YES];
        if (![server isEqual:[[DLController sharedInstance] myServerItem]] &&
            ![[DLController sharedInstance] isChannelMuted:channel]) {
            [server setHasUnreadMessages:YES];
        }
    }
    if ([server isEqual:[[DLController sharedInstance] myServerItem]] &&
        [[[DLController sharedInstance] selectedServer] isEqual:[[DLController sharedInstance] myServerItem]]) {
        if ([delegate respondsToSelector:@selector(messagePresentationControllerNeedsDirectMessageRefresh:)]) {
            [delegate messagePresentationControllerNeedsDirectMessageRefresh:self];
        }
    }
}

-(void)chatView:(ChatItemViewController *)chatView showProfileForUser:(DLUser *)user relativeToView:(NSView *)anchorView {
    NSRect anchorRect = [anchorView convertRect:[anchorView bounds] toView:chatScrollView];
    [userProfileController showProfileForUser:user relativeToRect:anchorRect ofView:chatScrollView];
}

-(void)addReferencedMessage:(DLMessage *)message {
    [composerController addReferencedMessage:message];
}

-(BOOL)chatViewShouldBeginEditing:(ChatItemViewController *)chatView {
    [chatScrollView endAllChatContentEditing];
    [chatView becomeWindowFirstResponderForEditing:hostWindow];
    return YES;
}

-(void)chatViewUpdatedWithEnteredText:(ChatItemViewController *)chatView {
    [chatScrollView screenResize];
}

-(void)chatViewContentWasUpdated:(ChatItemViewController *)chatView {
    [chatScrollView performSelector:@selector(screenResize) withObject:nil afterDelay:0.5];
}

-(void)chatView:(ChatItemViewController *)chatView showReactionPickerRelativeToView:(NSView *)anchorView {
    [composerController showReactionPickerForChatView:chatView relativeToView:anchorView];
}

-(void)chatView:(ChatItemViewController *)chatView didEndEditingWithCommit:(BOOL)didCommit {
    if (didCommit) {
        [[DLController sharedInstance] submitEditedMessage:[chatView representedObject]];
    } else {
        [chatScrollView performSelector:@selector(screenResize) withObject:nil afterDelay:0.5];
    }
    [composerController focusInput];
}

-(void)chatViewMessageShouldBeDeleted:(ChatItemViewController *)chatView {
    DLMessage *message = [[[chatView representedObject] retain] autorelease];
    // Holding Shift skips the confirmation, as in the official client.
    if ([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask) {
        [[DLController sharedInstance] deleteMessage:message];
        return;
    }
    DLDialog *dialog = [DLDialog dialogWithTitle:DLLocalizedString(@"Delete Message")
                                         message:DLLocalizedString(@"Are you sure you want to delete this message?")];
    [dialog addButtonWithTitle:DLLocalizedString(@"Delete") style:DLDialogButtonStyleDanger];
    [dialog addButtonWithTitle:DLLocalizedString(@"Cancel") style:DLDialogButtonStyleLink];
    [dialog setHandler:^BOOL(DLDialog *shown, NSInteger buttonIndex) {
        if (buttonIndex == 0) [[DLController sharedInstance] deleteMessage:message];
        return YES;
    }];
    [dialog showInWindow:hostWindow];
}

-(void)chatViewMessageWasDeleted:(ChatItemViewController *)chatView {
    [searchController clearHighlight];
    [chatScrollView removeViewController:chatView];
}

-(void)dealloc {
    delegate = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [readStateController setDelegate:nil];
    [userProfileController release];
    [composerController release];
    [channelNavigationController release];
    [pinsController release];
    [searchController release];
    [readStateController release];
    [reloadButton release];
    [chatHeaderImage release];
    [chatHeaderLabel release];
    [chatScrollView release];
    [super dealloc];
}

@end
