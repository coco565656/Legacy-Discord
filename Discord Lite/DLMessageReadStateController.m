//
//  DLMessageReadStateController.m
//  Legacy Discord
//

#import "DLMessageReadStateController.h"
#import "ChatScrollView.h"
#import "DLChannel.h"
#import "DLController.h"
#import "DLMessage.h"
#import "DLUtil.h"
#import "NSView+BGColor.h"

@interface DLMessageReadStateController ()
-(void)installMessageStateBanners;
-(void)refreshMessageBannerVisibility;
-(void)markLatestMessagesRead:(id)sender;
-(void)jumpToLatestMessages:(id)sender;
-(void)mainWindowDidBecomeKey:(NSNotification *)notification;
-(void)chatScrollViewBoundsDidChange:(NSNotification *)notification;
@end

@implementation DLMessageReadStateController

-(id)initWithChatScrollView:(ChatScrollView *)scrollView window:(NSWindow *)inWindow {
    self = [super init];
    if (self) {
        chatScrollView = [scrollView retain];
        window = inWindow;
        pendingNewMessageCount = 0;
        [self installMessageStateBanners];

        [[chatScrollView contentView] setPostsBoundsChangedNotifications:YES];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(chatScrollViewBoundsDidChange:)
                                                     name:NSViewBoundsDidChangeNotification
                                                   object:[chatScrollView contentView]];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(mainWindowDidBecomeKey:)
                                                     name:NSWindowDidBecomeKeyNotification
                                                   object:window];
    }
    return self;
}

-(void)setDelegate:(id<DLMessageReadStateControllerDelegate>)inDelegate {
    delegate = inDelegate;
}

// Borderless text button used in the Discord-style banners.
static NSButton *DLBannerTextButton(NSString *title, NSColor *color, NSRect frame, id target, SEL action) {
    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];
    [button setBordered:NO];
    [button setButtonType:NSMomentaryChangeButton];
    [button setAlignment:NSRightTextAlignment];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont boldSystemFontOfSize:11.0], NSFontAttributeName,
                                color, NSForegroundColorAttributeName, nil];
    [button setAttributedTitle:[[[NSAttributedString alloc] initWithString:title attributes:attributes] autorelease]];
    [button setTarget:target];
    [button setAction:action];
    return button;
}

static NSTextField *DLBannerLabel(NSRect frame, NSColor *color, BOOL bold) {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setFont:(bold ? [NSFont boldSystemFontOfSize:11.0] : [NSFont systemFontOfSize:11.0])];
    [label setTextColor:color];
    [[label cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    return label;
}

// Matches the official client: a blurple "new messages" bar across the top of
// the chat with Mark As Read, and a dark "viewing older messages" bar at the
// bottom, just above the composer, with Jump To Present.
-(void)installMessageStateBanners {
    NSRect bounds = [chatScrollView bounds];
    CGFloat width = MAX(120.0, NSWidth(bounds) - [NSScroller scrollerWidth]);

    unreadMessageBanner = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0, NSHeight(bounds) - 26.0, width, 26.0)];
    [unreadMessageBanner setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [(NSView_BGColor *)unreadMessageBanner setBackgroundColor:
     [NSColor colorWithCalibratedRed:0.345 green:0.396 blue:0.949 alpha:1.0]];
    unreadMessageBannerLabel = DLBannerLabel(NSMakeRect(12.0, 4.0, MAX(40.0, width - 130.0), 17.0), [NSColor whiteColor], YES);
    [unreadMessageBannerLabel setAutoresizingMask:NSViewWidthSizable];
    [unreadMessageBanner addSubview:unreadMessageBannerLabel];
    markMessagesReadButton = [DLBannerTextButton(@"Mark As Read", [NSColor whiteColor],
                                                 NSMakeRect(width - 112.0, 3.0, 100.0, 20.0),
                                                 self, @selector(markLatestMessagesRead:)) retain];
    [markMessagesReadButton setAutoresizingMask:NSViewMinXMargin];
    [unreadMessageBanner addSubview:markMessagesReadButton];
    [chatScrollView addSubview:unreadMessageBanner positioned:NSWindowAbove relativeTo:nil];

    historyMessageBanner = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0, 0.0, width, 30.0)];
    [historyMessageBanner setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [(NSView_BGColor *)historyMessageBanner setBackgroundColor:[DLUtil nativeSidebarColor]];
    historyMessageBannerLabel = DLBannerLabel(NSMakeRect(12.0, 6.0, MAX(40.0, width - 150.0), 17.0), [DLUtil nativeSecondaryTextColor], NO);
    [historyMessageBannerLabel setAutoresizingMask:NSViewWidthSizable];
    [historyMessageBannerLabel setStringValue:@"You're Viewing Older Messages"];
    [historyMessageBanner addSubview:historyMessageBannerLabel];
    jumpToLatestButton = [DLBannerTextButton(@"Jump To Present", [DLUtil nativePrimaryTextColor],
                                             NSMakeRect(width - 132.0, 5.0, 120.0, 20.0),
                                             self, @selector(jumpToLatestMessages:)) retain];
    [jumpToLatestButton setAutoresizingMask:NSViewMinXMargin];
    [historyMessageBanner addSubview:jumpToLatestButton];
    [chatScrollView addSubview:historyMessageBanner positioned:NSWindowAbove relativeTo:nil];

    [unreadMessageBanner setHidden:YES];
    [historyMessageBanner setHidden:YES];
}

-(BOOL)isViewingLatestMessages {
    return NSMinY([[chatScrollView contentView] bounds]) <= 8.0;
}

-(BOOL)hasPendingMessages {
    return pendingNewMessageCount > 0;
}

-(void)refreshMessageBannerVisibility {
    BOOL hasPending = [self hasPendingMessages];
    // Like the official client, the bottom bar appears once the reader is more
    // than a screen away from the newest messages, or has unread ones below.
    CGFloat scrolledUp = NSMinY([[chatScrollView contentView] bounds]);
    BOOL farFromPresent = scrolledUp > NSHeight([[chatScrollView contentView] bounds]);
    [unreadMessageBanner setHidden:!hasPending];
    [historyMessageBanner setHidden:([self isViewingLatestMessages] || !(hasPending || farFromPresent))];
    if (hasPending || farFromPresent) {
        [chatScrollView addSubview:unreadMessageBanner positioned:NSWindowAbove relativeTo:nil];
        [chatScrollView addSubview:historyMessageBanner positioned:NSWindowAbove relativeTo:nil];
    }
}

-(void)resetUnreadMessageState {
    pendingNewMessageCount = 0;
    [pendingNewMessageStartDate release];
    pendingNewMessageStartDate = nil;
    [firstUnreadMessageID release];
    firstUnreadMessageID = nil;
    [chatScrollView clearUnreadSeparator];
    [unreadMessageBanner setHidden:YES];
    [historyMessageBanner setHidden:YES];
}

-(void)recordUnreadMessage:(DLMessage *)message {
    if (!message) return;
    if (pendingNewMessageCount == 0) {
        pendingNewMessageStartDate = [[message timestamp] retain];
        firstUnreadMessageID = [[[message messageID] description] copy];
        [chatScrollView setUnreadStartMessageID:firstUnreadMessageID];
    }
    pendingNewMessageCount++;
    NSString *timeText = pendingNewMessageStartDate
        ? [NSDateFormatter localizedStringFromDate:pendingNewMessageStartDate
                                         dateStyle:NSDateFormatterNoStyle
                                         timeStyle:NSDateFormatterShortStyle]
        : @"--:--";
    [unreadMessageBannerLabel setStringValue:
     [NSString stringWithFormat:@"%ld new message%@ since %@",
      (long)pendingNewMessageCount, (pendingNewMessageCount == 1 ? @"" : @"s"), timeText]];
    [self refreshMessageBannerVisibility];
}

-(void)markLatestMessagesRead:(id)sender {
    DLMessage *message = [delegate latestMessageForMessageReadStateController:self];
    if (message) {
        [[DLController sharedInstance] acknowledgeMessage:message];
    }
    [[[DLController sharedInstance] selectedChannel] setHasUnreadMessages:NO];
    [self resetUnreadMessageState];
}

-(void)jumpToLatestMessages:(id)sender {
    NSPoint point = [[chatScrollView contentView] bounds].origin;
    point.y = 0.0;
    [[chatScrollView contentView] scrollToPoint:point];
    [chatScrollView reflectScrolledClipView:[chatScrollView contentView]];
    [self markLatestMessagesRead:nil];
}

-(void)mainWindowDidBecomeKey:(NSNotification *)notification {
    if ([self hasPendingMessages] && [self isViewingLatestMessages]) {
        [self markLatestMessagesRead:nil];
    } else {
        [self refreshMessageBannerVisibility];
    }
}

-(void)chatScrollViewBoundsDidChange:(NSNotification *)notification {
    [self refreshMessageBannerVisibility];
    if ([self hasPendingMessages] && [window isKeyWindow] && [self isViewingLatestMessages]) {
        [self markLatestMessagesRead:nil];
    }
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    delegate = nil;
    window = nil;
    [pendingNewMessageStartDate release];
    [firstUnreadMessageID release];
    [historyMessageBannerLabel release];
    [jumpToLatestButton release];
    [historyMessageBanner release];
    [unreadMessageBannerLabel release];
    [markMessagesReadButton release];
    [unreadMessageBanner release];
    [chatScrollView release];
    [super dealloc];
}

@end
