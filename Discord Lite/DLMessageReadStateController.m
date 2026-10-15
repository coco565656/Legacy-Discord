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

-(void)installMessageStateBanners {
    NSRect bounds = [chatScrollView bounds];
    unreadMessageBanner = [[NSView_BGColor alloc] initWithFrame:
                           NSMakeRect(0.0, 0.0, NSWidth(bounds), 28.0)];
    [unreadMessageBanner setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [(NSView_BGColor *)unreadMessageBanner setBackgroundColor:
     [NSColor colorWithCalibratedRed:0.345 green:0.396 blue:0.949 alpha:0.98]];
    [(NSView_BGColor *)unreadMessageBanner setBottomBorderColor:[DLUtil nativeBorderColor]];

    unreadMessageBannerLabel = [[NSTextField alloc] initWithFrame:
                                NSMakeRect(10.0, 5.0, MAX(80.0, NSWidth(bounds) - 112.0), 18.0)];
    [unreadMessageBannerLabel setAutoresizingMask:NSViewWidthSizable];
    [unreadMessageBannerLabel setBezeled:NO];
    [unreadMessageBannerLabel setDrawsBackground:NO];
    [unreadMessageBannerLabel setEditable:NO];
    [unreadMessageBannerLabel setSelectable:NO];
    [unreadMessageBannerLabel setFont:[NSFont boldSystemFontOfSize:10.0]];
    [unreadMessageBannerLabel setTextColor:[NSColor whiteColor]];
    [unreadMessageBanner addSubview:unreadMessageBannerLabel];

    markMessagesReadButton = [[NSButton alloc] initWithFrame:
                              NSMakeRect(MAX(0.0, NSWidth(bounds) - 98.0), 3.0, 92.0, 22.0)];
    [markMessagesReadButton setAutoresizingMask:NSViewMinXMargin];
    [markMessagesReadButton setBezelStyle:NSRoundedBezelStyle];
    [markMessagesReadButton setFont:[NSFont boldSystemFontOfSize:10.0]];
    [markMessagesReadButton setTitle:@"既読にする"];
    [markMessagesReadButton setTarget:self];
    [markMessagesReadButton setAction:@selector(markLatestMessagesRead:)];
    [unreadMessageBanner addSubview:markMessagesReadButton];
    [chatScrollView addSubview:unreadMessageBanner positioned:NSWindowAbove relativeTo:nil];

    CGFloat historyWidth = MIN(310.0, MAX(210.0, NSWidth(bounds) - 24.0));
    historyMessageBanner = [[NSView_BGColor alloc] initWithFrame:
                            NSMakeRect(floor((NSWidth(bounds) - historyWidth) / 2.0),
                                       MAX(0.0, NSHeight(bounds) - 37.0),
                                       historyWidth, 30.0)];
    [historyMessageBanner setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin];
    [(NSView_BGColor *)historyMessageBanner setBackgroundColor:
     [NSColor colorWithCalibratedWhite:0.17 alpha:0.94]];
    historyMessageBannerLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10.0, 6.0, 132.0, 18.0)];
    [historyMessageBannerLabel setBezeled:NO];
    [historyMessageBannerLabel setDrawsBackground:NO];
    [historyMessageBannerLabel setEditable:NO];
    [historyMessageBannerLabel setSelectable:NO];
    [historyMessageBannerLabel setFont:[NSFont systemFontOfSize:10.0]];
    [historyMessageBannerLabel setTextColor:[NSColor whiteColor]];
    [historyMessageBannerLabel setStringValue:@"古いメッセージを表示中"];
    [historyMessageBanner addSubview:historyMessageBannerLabel];

    jumpToLatestButton = [[NSButton alloc] initWithFrame:NSMakeRect(historyWidth - 151.0, 4.0, 143.0, 22.0)];
    [jumpToLatestButton setAutoresizingMask:NSViewMinXMargin];
    [jumpToLatestButton setBezelStyle:NSRoundedBezelStyle];
    [jumpToLatestButton setFont:[NSFont boldSystemFontOfSize:10.0]];
    [jumpToLatestButton setTitle:@"最新メッセージへ"];
    [jumpToLatestButton setTarget:self];
    [jumpToLatestButton setAction:@selector(jumpToLatestMessages:)];
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
    [unreadMessageBanner setHidden:!hasPending];
    [historyMessageBanner setHidden:(!hasPending || [self isViewingLatestMessages])];
    if (hasPending) {
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
     [NSString stringWithFormat:@"%@から %ld件+の新着メッセージ",
      timeText, (long)pendingNewMessageCount]];
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
