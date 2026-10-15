//
//  DLThreadController.m
//  Legacy Discord
//

#import "DLThreadController.h"
#import "DLController.h"
#import "DLServerChannel.h"
#import "ChatScrollView.h"
#import "NSView+BGColor.h"
#import "DLUtil.h"
#import "NSScroller+BGColor.h"

@interface DLThreadListCell : NSCell {
    DLServerChannel *representedThread;
}
-(void)setRepresentedThread:(DLServerChannel *)thread;
@end

@implementation DLThreadListCell

-(void)setRepresentedThread:(DLServerChannel *)thread {
    representedThread = thread;
}

-(void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (!representedThread) {
        return;
    }
    BOOL archived = [representedThread archivedThread];
    NSRect cardRect = NSInsetRect(cellFrame, 6.0, 4.0);
    NSColor *background = archived ? [DLUtil nativeSidebarColor] : [DLUtil nativeChromeColor];
    if ([self isHighlighted]) {
        background = [DLUtil nativeSelectionColor];
    }
    [background set];
    [[NSBezierPath bezierPathWithRoundedRect:cardRect xRadius:7.0 yRadius:7.0] fill];
    [[DLUtil nativeBorderColor] set];
    [[NSBezierPath bezierPathWithRoundedRect:cardRect xRadius:7.0 yRadius:7.0] stroke];

    DLChannel *parent = [[DLController sharedInstance] loadedChannelWithID:[representedThread parentID]];
    NSString *title = [representedThread name] ? [representedThread name] : @"Untitled";
    NSString *detail = [NSString stringWithFormat:@"%@  •  # %@",
                        archived ? @"Archived" : @"Active thread",
                        [parent name] ? [parent name] : @"Unknown channel"];
    NSColor *titleColor = archived ? [DLUtil nativeSecondaryTextColor] : [DLUtil nativePrimaryTextColor];
    NSDictionary *titleAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                     [NSFont boldSystemFontOfSize:12.0], NSFontAttributeName,
                                     titleColor, NSForegroundColorAttributeName, nil];
    NSDictionary *detailAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSFont systemFontOfSize:10.0], NSFontAttributeName,
                                      [DLUtil nativeSecondaryTextColor], NSForegroundColorAttributeName, nil];
    CGFloat top = [controlView isFlipped] ? NSMinY(cardRect) + 8.0 : NSMaxY(cardRect) - 24.0;
    NSColor *dotColor = archived ? [NSColor grayColor]
                                 : [NSColor colorWithCalibratedRed:0.20 green:0.62 blue:0.26 alpha:1.0];
    [dotColor set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMinX(cardRect) + 10.0,
                                                        [controlView isFlipped] ? top + 4.0 : top + 3.0,
                                                        8.0, 8.0)] fill];
    [title drawInRect:NSMakeRect(NSMinX(cardRect) + 25.0, top,
                                  NSWidth(cardRect) - 35.0, 17.0)
        withAttributes:titleAttributes];
    CGFloat detailY = [controlView isFlipped] ? top + 22.0 : top - 20.0;
    [detail drawInRect:NSMakeRect(NSMinX(cardRect) + 25.0, detailY,
                                   NSWidth(cardRect) - 35.0, 15.0)
         withAttributes:detailAttributes];
}

@end

@interface DLThreadController ()
-(void)installViews;
@end

@implementation DLThreadController

-(id)initWithHostView:(NSView *)inHostView
       chatScrollView:(ChatScrollView *)inChatScrollView
         composerView:(NSView *)inComposerView {
    self = [super init];
    if (self) {
        hostView = [inHostView retain];
        chatScrollView = [inChatScrollView retain];
        composerView = [inComposerView retain];
        [self installViews];
    }
    return self;
}
-(void)setDelegate:(id<DLThreadControllerDelegate>)inDelegate { delegate = inDelegate; }
-(BOOL)isVisible { return visible; }

-(void)installViews {
    NSRect bounds = [hostView bounds];
    listPane = [[NSView_BGColor alloc] initWithFrame:
                      NSMakeRect(0.0, 0.0, NSWidth(bounds), NSHeight(bounds) - 42.0)];
    [listPane setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [listPane setBackgroundColor:[DLUtil nativeContentColor]];

    NSTextField *title = [[[NSTextField alloc] initWithFrame:
                           NSMakeRect(16.0, NSHeight([listPane bounds]) - 34.0,
                                      NSWidth([listPane bounds]) - 60.0, 22.0)] autorelease];
    [title setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [title setBezeled:NO];
    [title setDrawsBackground:NO];
    [title setEditable:NO];
    [title setSelectable:NO];
    [title setFont:[NSFont boldSystemFontOfSize:15.0]];
    [title setTextColor:[DLUtil nativePrimaryTextColor]];
    [title setStringValue:@"Active Threads"];
    [listPane addSubview:title];

    NSButton *closeListButton = [[[NSButton alloc] initWithFrame:
                                  NSMakeRect(NSWidth([listPane bounds]) - 35.0,
                                             NSHeight([listPane bounds]) - 36.0, 26.0, 26.0)] autorelease];
    [closeListButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [closeListButton setBordered:NO];
    [closeListButton setFont:[NSFont systemFontOfSize:17.0]];
    [closeListButton setTitle:@"×"];
    [closeListButton setToolTip:@"Close thread list"];
    [closeListButton setTarget:self];
    [closeListButton setAction:@selector(closeThreadList:)];
    [listPane addSubview:closeListButton];

    listScrollView = [[NSScrollView alloc] initWithFrame:
                            NSMakeRect(10.0, 10.0, NSWidth(bounds) - 20.0, NSHeight(bounds) - 92.0)];
    [listScrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [listScrollView setBorderType:NSNoBorder];
    [listScrollView setHasVerticalScroller:YES];
    [listScrollView setDrawsBackground:YES];
    [listScrollView setBackgroundColor:[DLUtil nativeContentColor]];
    NSScroller_BGColor *listScrollViewScroller = [[[NSScroller_BGColor alloc] initWithFrame:NSZeroRect] autorelease];
    [listScrollViewScroller setBackgroundColor:[DLUtil nativeContentColor]];
    [listScrollView setVerticalScroller:listScrollViewScroller];
    NSTableColumn *threadColumn = [[[NSTableColumn alloc] initWithIdentifier:@"thread"] autorelease];
    [threadColumn setWidth:NSWidth([listScrollView bounds])];
    [threadColumn setResizingMask:NSTableColumnAutoresizingMask];
    [threadColumn setDataCell:[[[DLThreadListCell alloc] init] autorelease]];
    listTableView = [[NSTableView alloc] initWithFrame:[[listScrollView contentView] bounds]];
    [listTableView addTableColumn:threadColumn];
    [listTableView setHeaderView:nil];
    [listTableView setDataSource:self];
    [listTableView setDelegate:self];
    [listTableView setRowHeight:64.0];
    [listTableView setIntercellSpacing:NSMakeSize(0.0, 1.0)];
    [listTableView setBackgroundColor:[DLUtil nativeContentColor]];
    [listTableView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];
    [listScrollView setDocumentView:listTableView];
    [listPane addSubview:listScrollView];

    emptyField = [[NSTextField alloc] initWithFrame:
                            NSMakeRect(20.0, NSMidY([listPane bounds]) - 30.0,
                                       NSWidth(bounds) - 40.0, 60.0)];
    [emptyField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin];
    [emptyField setBezeled:NO];
    [emptyField setDrawsBackground:NO];
    [emptyField setEditable:NO];
    [emptyField setSelectable:NO];
    [emptyField setAlignment:NSCenterTextAlignment];
    [emptyField setFont:[NSFont boldSystemFontOfSize:15.0]];
    [emptyField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [emptyField setStringValue:@"No active threads in this channel"];
    [listPane addSubview:emptyField];

    CGFloat detailWidth = MAX(300.0, NSWidth(bounds) * 0.58);
    detailPane = [[NSView_BGColor alloc] initWithFrame:
                        NSMakeRect(NSWidth(bounds) - detailWidth, 0.0, detailWidth, NSHeight(bounds) - 42.0)];
    [detailPane setAutoresizingMask:NSViewMinXMargin | NSViewHeightSizable];
    [detailPane setBackgroundColor:[DLUtil nativeContentColor]];
    [detailPane setLeftBorderColor:[DLUtil nativeBorderColor]];
    detailTitleField = [[NSTextField alloc] initWithFrame:
                              NSMakeRect(12.0, NSHeight([detailPane bounds]) - 32.0,
                                         detailWidth - 52.0, 20.0)];
    [detailTitleField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [detailTitleField setBezeled:NO];
    [detailTitleField setDrawsBackground:NO];
    [detailTitleField setEditable:NO];
    [detailTitleField setSelectable:NO];
    [detailTitleField setFont:[NSFont boldSystemFontOfSize:13.0]];
    [detailTitleField setTextColor:[DLUtil nativePrimaryTextColor]];
    [detailPane addSubview:detailTitleField];
    NSButton *closeDetailButton = [[[NSButton alloc] initWithFrame:
                                    NSMakeRect(detailWidth - 35.0,
                                               NSHeight([detailPane bounds]) - 36.0, 26.0, 26.0)] autorelease];
    [closeDetailButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [closeDetailButton setBordered:NO];
    [closeDetailButton setFont:[NSFont systemFontOfSize:17.0]];
    [closeDetailButton setTitle:@"×"];
    [closeDetailButton setToolTip:@"Close thread"];
    [closeDetailButton setTarget:self];
    [closeDetailButton setAction:@selector(closeThreadDetail:)];
    [detailPane addSubview:closeDetailButton];

    [hostView addSubview:listPane];
    [hostView addSubview:detailPane];
    [listPane setHidden:YES];
    [detailPane setHidden:YES];
    items = [[NSArray alloc] init];
    visible = NO;
    detailVisible = NO;
}

-(void)showThreadList {
    DLChannel *selected = [[DLController sharedInstance] selectedChannel];
    DLServer *server = [[DLController sharedInstance] selectedServer];
    if (!selected || !server || [server isEqual:[[DLController sharedInstance] myServerItem]]) {
        NSBeep();
        return;
    }
    DLChannel *parentChannel = selected;
    if ([selected isThread]) {
        parentChannel = [[DLController sharedInstance] loadedChannelWithID:[(DLServerChannel *)selected parentID]];
    }
    if (!parentChannel) {
        NSBeep();
        return;
    }
    [baseChannel release];
    baseChannel = [parentChannel retain];
    [items release];
    items = [[[DLController sharedInstance] activeThreadsForServer:server
                                                               parentChannel:parentChannel] retain];
    [[DLController sharedInstance] loadArchivedThreadsForChannel:parentChannel];
    [listTableView reloadData];
    [listTableView deselectAll:self];
    [emptyField setHidden:([items count] != 0)];
    [chatScrollView setHidden:YES];
    [composerView setHidden:YES];
    [detailPane setHidden:YES];
    [listPane setHidden:NO];
    visible = YES;
    detailVisible = NO;
}

-(void)openThreadDetail:(DLChannel *)thread {
    if (!thread || !visible) {
        return;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:chatScrollView selector:@selector(screenResize) object:nil];
    [chatScrollView setHidden:YES];
    [chatScrollView setContent:[NSArray array]];
    NSRect bounds = [hostView bounds];
    CGFloat detailWidth = MIN(NSWidth(bounds) - 180.0, MAX(300.0, NSWidth(bounds) * 0.58));
    NSRect detailFrame = NSMakeRect(NSWidth(bounds) - detailWidth, 0.0,
                                    detailWidth, NSHeight(bounds) - 42.0);
    [detailPane setFrame:detailFrame];
    [detailTitleField setStringValue:[NSString stringWithFormat:@"↳ %@", [thread name]]];
    [detailPane setHidden:NO];

    [chatScrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [composerView setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [chatScrollView setFrame:NSMakeRect(0.0, 56.0, detailWidth,
                                        MAX(80.0, NSHeight(bounds) - 140.0))];
    [composerView setFrame:NSMakeRect(0.0, 0.0, detailWidth, 56.0)];
    [chatScrollView retain];
    if ([chatScrollView superview] != detailPane) {
        [chatScrollView removeFromSuperviewWithoutNeedingDisplay];
        [detailPane addSubview:chatScrollView];
    }
    [chatScrollView release];
    [composerView retain];
    if ([composerView superview] != detailPane) {
        [composerView removeFromSuperviewWithoutNeedingDisplay];
        [detailPane addSubview:composerView];
    }
    [composerView release];
    [chatScrollView setHidden:NO];
    [composerView setHidden:NO];
    detailVisible = YES;
    [delegate threadController:self selectChannel:thread];
}

-(IBAction)closeThreadDetail:(id)sender {
    if (!visible) {
        return;
    }
    [chatScrollView setHidden:YES];
    [composerView setHidden:YES];
    [detailPane setHidden:YES];
    detailVisible = NO;
    if (baseChannel) {
        [delegate threadController:self restoreBaseChannel:baseChannel];
    }
    [listTableView deselectAll:self];
}

-(void)hideThreadBrowser {
    if (!visible) {
        return;
    }
    NSRect bounds = [hostView bounds];
    [listPane setHidden:YES];
    [detailPane setHidden:YES];
    [chatScrollView retain];
    if ([chatScrollView superview] != hostView) {
        [chatScrollView removeFromSuperviewWithoutNeedingDisplay];
        [hostView addSubview:chatScrollView];
    }
    [chatScrollView release];
    [composerView retain];
    if ([composerView superview] != hostView) {
        [composerView removeFromSuperviewWithoutNeedingDisplay];
        [hostView addSubview:composerView];
    }
    [composerView release];
    [chatScrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [composerView setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [chatScrollView setFrame:NSMakeRect(0.0, 56.0, NSWidth(bounds), NSHeight(bounds) - 98.0)];
    [composerView setFrame:NSMakeRect(0.0, 0.0, NSWidth(bounds), 56.0)];
    [chatScrollView setHidden:NO];
    [composerView setHidden:NO];
    visible = NO;
    detailVisible = NO;
    [chatScrollView screenResize];
}

-(IBAction)closeThreadList:(id)sender {
    DLChannel *channel = [baseChannel retain];
    [self hideThreadBrowser];
    if (channel) {
        [delegate threadController:self selectChannel:channel];
    }
    [channel release];
}

-(void)refreshForServer:(DLServer *)server {
    if (!server || ![server isEqual:[[DLController sharedInstance] selectedServer]]) {
        return;
    }
    if (visible && baseChannel) {
        [items release];
        items = [[[DLController sharedInstance] activeThreadsForServer:server
                                                                   parentChannel:baseChannel] retain];
        [listTableView reloadData];
        [emptyField setHidden:([items count] != 0)];
    }
}

-(void)threadsDidUpdateForServer:(DLServer *)server {
    [self performSelectorOnMainThread:@selector(scheduleThreadOutlineRefreshForServer:)
                           withObject:server
                        waitUntilDone:NO];
}

-(void)scheduleThreadOutlineRefreshForServer:(DLServer *)server {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(refreshForServer:)
                                               object:nil];
    [self performSelector:@selector(refreshForServer:)
               withObject:server
               afterDelay:0.08];
}

-(void)refreshArchivedThreadListForContext:(NSDictionary *)context {
    DLServer *server = [context objectForKey:@"server"];
    DLChannel *channel = [context objectForKey:@"channel"];
    if (!visible || !baseChannel ||
        ![baseChannel isEqual:channel] ||
        ![server isEqual:[[DLController sharedInstance] selectedServer]]) {
        return;
    }
    [items release];
    items = [[[DLController sharedInstance] activeThreadsForServer:server
                                                               parentChannel:baseChannel] retain];
    [listTableView reloadData];
    [emptyField setHidden:([items count] != 0)];
}

-(void)archivedThreadsDidUpdateForServer:(DLServer *)server channel:(DLChannel *)channel {
    if (!server || !channel) {
        return;
    }
    NSDictionary *context = [NSDictionary dictionaryWithObjectsAndKeys:
                             server, @"server", channel, @"channel", nil];
    [self performSelectorOnMainThread:@selector(refreshArchivedThreadListForContext:)
                           withObject:context
                        waitUntilDone:NO];
}



-(void)applyCurrentTheme {
    [(NSView_BGColor *)listPane setBackgroundColor:[DLUtil nativeContentColor]];
    [(NSView_BGColor *)detailPane setBackgroundColor:[DLUtil nativeContentColor]];
    [(NSView_BGColor *)detailPane setLeftBorderColor:[DLUtil nativeBorderColor]];
    [listScrollView setBackgroundColor:[DLUtil nativeContentColor]];
    [(NSScroller_BGColor *)[listScrollView verticalScroller] setBackgroundColor:[DLUtil nativeContentColor]];
    [listTableView setBackgroundColor:[DLUtil nativeContentColor]];
    [emptyField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [detailTitleField setTextColor:[DLUtil nativePrimaryTextColor]];
    [listTableView reloadData];
}
-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return [items count]; }
-(id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    DLServerChannel *thread = [items objectAtIndex:row];
    DLChannel *parent = [[DLController sharedInstance] loadedChannelWithID:[thread parentID]];
    return [NSString stringWithFormat:@"↳ %@    # %@", [thread name] ? [thread name] : @"Untitled",
            [parent name] ? [parent name] : @"Unknown channel"];
}
-(void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if ([cell isKindOfClass:[DLThreadListCell class]]) [(DLThreadListCell *)cell setRepresentedThread:[items objectAtIndex:row]];
}
-(NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)column row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation {
    return (row >= 0 && row < (NSInteger)[items count]) ? [[items objectAtIndex:row] name] : nil;
}
-(void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = [listTableView selectedRow];
    if (row >= 0 && row < (NSInteger)[items count]) [self openThreadDetail:[items objectAtIndex:row]];
}
-(void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self hideThreadBrowser];
    [listTableView setDelegate:nil];
    [listTableView setDataSource:nil];
    [baseChannel release];
    [items release];
    [emptyField release];
    [detailTitleField release];
    [listTableView release];
    [listScrollView release];
    [detailPane release];
    [listPane release];
    [composerView release];
    [chatScrollView release];
    [hostView release];
    [super dealloc];
}
@end
