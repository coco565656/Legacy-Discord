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
#import "DLMainWindowChromeControls.h"
#import "DLTwemojiRenderer.h"

static const CGFloat DLForumCardMargin = 16.0;
static const CGFloat DLForumTagRowHeight = 24.0;

// "5m ago", "3h ago", "2d ago", then the short date, like the post cards.
static NSString *DLRelativeActivityString(NSDate *date) {
    if (!date) return @"";
    NSTimeInterval age = -[date timeIntervalSinceNow];
    if (age < 60.0) return @"just now";
    if (age < 3600.0) return [NSString stringWithFormat:@"%ldm ago", (long)(age / 60.0)];
    if (age < 86400.0) return [NSString stringWithFormat:@"%ldh ago", (long)(age / 3600.0)];
    if (age < 30.0 * 86400.0) return [NSString stringWithFormat:@"%ldd ago", (long)(age / 86400.0)];
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setDateStyle:NSDateFormatterShortStyle];
    [formatter setTimeStyle:NSDateFormatterNoStyle];
    return [formatter stringFromDate:date];
}

// Names of the forum tags applied to a post, in the forum's tag order.
static NSArray *DLAppliedTagNames(DLServerChannel *thread) {
    DLServerChannel *forum = (DLServerChannel *)[[DLController sharedInstance] loadedChannelWithID:[thread parentID]];
    if (![forum respondsToSelector:@selector(availableTags)]) return [NSArray array];
    NSArray *applied = [thread appliedTagIDs];
    NSMutableArray *names = [NSMutableArray array];
    NSEnumerator *enumerator = [[forum availableTags] objectEnumerator];
    NSDictionary *tag;
    while (tag = [enumerator nextObject]) {
        if (![tag isKindOfClass:[NSDictionary class]]) continue;
        if (![applied containsObject:[[tag objectForKey:@"id"] description]]) continue;
        NSString *tagName = [tag objectForKey:@"name"];
        NSString *emoji = [tag objectForKey:@"emoji_name"];
        if (![tagName isKindOfClass:[NSString class]]) continue;
        if ([emoji isKindOfClass:[NSString class]] && [emoji length]) {
            tagName = [NSString stringWithFormat:@"%@ %@", emoji, tagName];
        }
        [names addObject:tagName];
    }
    return names;
}

@interface DLForumPostCell : NSCell {
    DLServerChannel *representedThread;
    BOOL forumPost;
    BOOL hovered;
}
-(void)setRepresentedThread:(DLServerChannel *)thread forumPost:(BOOL)isForumPost hovered:(BOOL)isHovered;
@end

@implementation DLForumPostCell

-(void)setRepresentedThread:(DLServerChannel *)thread forumPost:(BOOL)isForumPost hovered:(BOOL)isHovered {
    representedThread = thread;
    forumPost = isForumPost;
    hovered = isHovered;
}

-(NSAttributedString *)lineWithString:(NSString *)string font:(NSFont *)font color:(NSColor *)color {
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [style setLineBreakMode:NSLineBreakByTruncatingTail];
    NSMutableAttributedString *line = [[[NSMutableAttributedString alloc] initWithString:(string ? string : @"")
        attributes:[NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, color,
                    NSForegroundColorAttributeName, style, NSParagraphStyleAttributeName, nil]] autorelease];
    [DLTwemojiRenderer replaceEmojiInAttributedString:line size:[font pointSize]
                                   excludingAttribute:nil recordingAttribute:nil cursorLocation:NULL];
    return line;
}

// Speech bubble used for the message count, drawn so it needs no emoji font.
-(void)drawBubbleInRect:(NSRect)rect color:(NSColor *)color flipped:(BOOL)flipped {
    NSRect body = NSMakeRect(NSMinX(rect), flipped ? NSMinY(rect) : NSMinY(rect) + 3.0, NSWidth(rect), NSHeight(rect) - 3.0);
    NSBezierPath *bubble = [NSBezierPath bezierPathWithRoundedRect:body xRadius:3.0 yRadius:3.0];
    CGFloat tailY = flipped ? NSMaxY(body) : NSMinY(body);
    CGFloat tipY = flipped ? NSMaxY(rect) : NSMinY(rect);
    [bubble moveToPoint:NSMakePoint(NSMinX(body) + 3.0, tailY)];
    [bubble lineToPoint:NSMakePoint(NSMinX(body) + 2.0, tipY)];
    [bubble lineToPoint:NSMakePoint(NSMinX(body) + 7.0, tailY)];
    [color setStroke];
    [bubble setLineWidth:1.3];
    [bubble stroke];
}

-(void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (!representedThread) return;
    BOOL flipped = [controlView isFlipped];
    NSRect card = NSInsetRect(cellFrame, DLForumCardMargin, 4.0);
    NSColor *background = [DLUtil nativeSidebarColor];
    if (hovered) background = [background blendedColorWithFraction:0.06 ofColor:[NSColor whiteColor]];
    [background set];
    [[NSBezierPath bezierPathWithRoundedRect:card xRadius:8.0 yRadius:8.0] fill];

    CGFloat x = NSMinX(card) + 16.0;
    CGFloat width = NSWidth(card) - 32.0;
    // Lay out from the top of the card in either coordinate system.
    CGFloat cursor = 12.0;
    #define DLCardRect(offset, height) NSMakeRect(x, flipped ? NSMinY(card) + (offset) : NSMaxY(card) - (offset) - (height), width, (height))

    NSArray *tags = forumPost ? DLAppliedTagNames(representedThread) : [NSArray array];
    if ([tags count]) {
        CGFloat tagX = x;
        NSEnumerator *enumerator = [tags objectEnumerator];
        NSString *tag;
        while ((tag = [enumerator nextObject]) && tagX < NSMaxX(card) - 40.0) {
            NSAttributedString *label = [self lineWithString:tag font:[NSFont boldSystemFontOfSize:11.0]
                                                       color:[DLUtil nativePrimaryTextColor]];
            CGFloat pillWidth = MIN(ceil([label size].width) + 16.0, NSMaxX(card) - 16.0 - tagX);
            NSRect pill = DLCardRect(cursor, 18.0);
            pill.origin.x = tagX;
            pill.size.width = pillWidth;
            [[DLUtil nativeInputColor] set];
            [[NSBezierPath bezierPathWithRoundedRect:pill xRadius:9.0 yRadius:9.0] fill];
            [label drawInRect:NSInsetRect(pill, 8.0, 2.0)];
            tagX += pillWidth + 6.0;
        }
        cursor += DLForumTagRowHeight;
    }

    NSString *title = [representedThread name] ? [representedThread name] : @"Untitled";
    NSColor *titleColor = [representedThread archivedThread] ? [DLUtil nativeSecondaryTextColor] : [DLUtil nativePrimaryTextColor];
    [[self lineWithString:title font:[NSFont boldSystemFontOfSize:15.0] color:titleColor]
        drawInRect:DLCardRect(cursor, 20.0)];
    cursor += 24.0;

    // "author: opening message" like the official card; plain status for
    // text-channel threads, whose starter lives in the parent channel.
    NSMutableAttributedString *snippet = [[[NSMutableAttributedString alloc] init] autorelease];
    NSDictionary *summary = [representedThread starterSummary];
    if (forumPost && summary) {
        NSString *author = [summary objectForKey:@"author"];
        if ([author length]) {
            [snippet appendAttributedString:[self lineWithString:[author stringByAppendingString:@": "]
                                                            font:[NSFont boldSystemFontOfSize:13.0]
                                                           color:[DLUtil nativePrimaryTextColor]]];
        }
        [snippet appendAttributedString:[self lineWithString:[summary objectForKey:@"text"]
                                                        font:[NSFont systemFontOfSize:13.0]
                                                       color:[DLUtil nativeSecondaryTextColor]]];
    } else if (!forumPost) {
        [snippet appendAttributedString:[self lineWithString:([representedThread archivedThread] ? @"Archived thread" : @"Active thread")
                                                        font:[NSFont systemFontOfSize:13.0]
                                                       color:[DLUtil nativeSecondaryTextColor]]];
    }
    NSMutableParagraphStyle *truncating = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [truncating setLineBreakMode:NSLineBreakByTruncatingTail];
    [snippet addAttribute:NSParagraphStyleAttributeName value:truncating range:NSMakeRange(0, [snippet length])];
    [snippet drawInRect:DLCardRect(cursor, 18.0)];
    cursor += 24.0;

    NSColor *metaColor = [DLUtil nativeSecondaryTextColor];
    NSRect bubbleRect = DLCardRect(cursor + 2.0, 12.0);
    bubbleRect.size.width = 13.0;
    [self drawBubbleInRect:bubbleRect color:metaColor flipped:flipped];
    NSString *meta = [NSString stringWithFormat:@"%ld", (long)MAX(0, [representedThread messageCount])];
    NSString *activity = DLRelativeActivityString([representedThread lastActivityDate]);
    if ([activity length]) meta = [meta stringByAppendingFormat:@"   •   %@", activity];
    if ([representedThread archivedThread]) meta = [meta stringByAppendingString:@"   •   Archived"];
    NSRect metaRect = DLCardRect(cursor, 16.0);
    metaRect.origin.x += 20.0;
    metaRect.size.width -= 20.0;
    [[self lineWithString:meta font:[NSFont systemFontOfSize:12.0] color:metaColor] drawInRect:metaRect];
    #undef DLCardRect
}

@end

// Tag pill in the New Post draft; blurple when selected.
@interface DLTagToggleButton : NSButton
@end

@implementation DLTagToggleButton
-(void)drawRect:(NSRect)dirtyRect {
    NSRect pill = NSInsetRect([self bounds], 0.5, 1.5);
    BOOL on = [self state] == NSOnState;
    NSColor *fill = on ? [NSColor colorWithCalibratedRed:0.345 green:0.396 blue:0.949 alpha:1.0] : [DLUtil nativeInputColor];
    [fill set];
    [[NSBezierPath bezierPathWithRoundedRect:pill xRadius:NSHeight(pill) / 2.0 yRadius:NSHeight(pill) / 2.0] fill];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont boldSystemFontOfSize:11.0], NSFontAttributeName,
                                (on ? [NSColor whiteColor] : [DLUtil nativePrimaryTextColor]), NSForegroundColorAttributeName, nil];
    NSString *title = [self title] ? [self title] : @"";
    NSSize size = [title sizeWithAttributes:attributes];
    [title drawAtPoint:NSMakePoint(floor(NSMidX(pill) - size.width / 2.0), floor(NSMidY(pill) - size.height / 2.0))
        withAttributes:attributes];
}
@end

static NSTextField *DLDraftField(NSString *placeholder, CGFloat fontSize, BOOL multiline) {
    NSTextField *field = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
    [field setBezeled:NO];
    [field setBordered:NO];
    [field setDrawsBackground:YES];
    [field setBackgroundColor:[DLUtil nativeInputColor]];
    [field setTextColor:[DLUtil nativePrimaryTextColor]];
    [field setFont:[NSFont systemFontOfSize:fontSize]];
    [field setFocusRingType:NSFocusRingTypeNone];
    [[field cell] setPlaceholderString:placeholder];
    [[field cell] setWraps:multiline];
    [[field cell] setScrollable:!multiline];
    return field;
}

@interface DLThreadController ()
-(void)installViews;
-(BOOL)isForumMode;
-(void)reloadItems;
-(void)applySearchFilter;
-(void)layoutListArea;
-(void)setComposing:(BOOL)shouldCompose;
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
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(threadStarterDidLoad:)
                                                     name:DLThreadStarterDidLoadNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(forumPostCreationDidFinish:)
                                                     name:DLForumPostCreationDidFinishNotification object:nil];
    }
    return self;
}
-(void)setDelegate:(id<DLThreadControllerDelegate>)inDelegate { delegate = inDelegate; }
-(BOOL)isVisible { return visible; }

-(BOOL)isForumMode {
    return [baseChannel type] == ChannelTypeForum || [baseChannel type] == ChannelTypeMedia;
}

-(void)installViews {
    NSRect bounds = [hostView bounds];
    listPane = [[NSView_BGColor alloc] initWithFrame:
                NSMakeRect(0.0, 0.0, NSWidth(bounds), NSHeight(bounds) - 42.0)];
    [listPane setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [listPane setBackgroundColor:[DLUtil nativeContentColor]];
    NSRect paneBounds = [listPane bounds];

    // Text-channel thread list title; forum lists show only the search bar.
    titleField = [[NSTextField alloc] initWithFrame:
                  NSMakeRect(DLForumCardMargin, NSHeight(paneBounds) - 40.0, 120.0, 22.0)];
    [titleField setAutoresizingMask:NSViewMinYMargin];
    [titleField setBezeled:NO];
    [titleField setDrawsBackground:NO];
    [titleField setEditable:NO];
    [titleField setSelectable:NO];
    [titleField setFont:[NSFont boldSystemFontOfSize:15.0]];
    [titleField setTextColor:[DLUtil nativePrimaryTextColor]];
    [titleField setStringValue:@"Threads"];
    [listPane addSubview:titleField];

    searchField = [[NSSearchField alloc] initWithFrame:
                   NSMakeRect(DLForumCardMargin, NSHeight(paneBounds) - 42.0,
                              NSWidth(paneBounds) - DLForumCardMargin * 2.0 - 40.0, 28.0)];
    DLDarkSearchFieldCell *searchCell = [[DLDarkSearchFieldCell alloc] initTextCell:@""];
    [searchCell setTextColor:[DLUtil nativePrimaryTextColor]];
    [searchCell setBackgroundColor:[NSColor clearColor]];
    [searchCell setDrawsBackground:NO];
    [searchCell setBezeled:NO];
    [searchField setCell:searchCell];
    [searchCell release];
    [searchField setEditable:YES];
    [searchField setSelectable:YES];
    [searchField setFont:[NSFont systemFontOfSize:13.0]];
    [searchField setBackgroundColor:[DLUtil nativeInputColor]];
    [searchField setTextColor:[DLUtil nativePrimaryTextColor]];
    [searchField setFocusRingType:NSFocusRingTypeNone];
    [searchField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [searchField setDelegate:(id)self];
    [listPane addSubview:searchField];

    closeButton = [[NSButton alloc] initWithFrame:
                   NSMakeRect(NSWidth(paneBounds) - 36.0, NSHeight(paneBounds) - 41.0, 26.0, 26.0)];
    [closeButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [closeButton setBordered:NO];
    [closeButton setFont:[NSFont systemFontOfSize:17.0]];
    [closeButton setTitle:@"×"];
    [closeButton setToolTip:@"Close"];
    [closeButton setTarget:self];
    [closeButton setAction:@selector(closeThreadList:)];
    [listPane addSubview:closeButton];

    newPostButton = [[DLPrimaryButton alloc] initWithFrame:
                     NSMakeRect(NSWidth(paneBounds) - DLForumCardMargin - 96.0, NSHeight(paneBounds) - 42.0, 96.0, 28.0)];
    [newPostButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [newPostButton setTitle:@"New Post"];
    [newPostButton setTarget:self];
    [newPostButton setAction:@selector(beginNewPost:)];
    [listPane addSubview:newPostButton];

    // Draft card shown between the top bar and the post list.
    composeView = [[NSView_BGColor alloc] initWithFrame:NSZeroRect];
    [composeView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [composeView setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    postTitleField = [DLDraftField(@"Post title", 15.0, NO) retain];
    [postTitleField setFont:[NSFont boldSystemFontOfSize:15.0]];
    postMessageField = [DLDraftField(@"Enter a message (Option-Return for a new line)", 13.0, YES) retain];
    postStatusField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [postStatusField setBezeled:NO];
    [postStatusField setDrawsBackground:NO];
    [postStatusField setEditable:NO];
    [postStatusField setSelectable:NO];
    [postStatusField setFont:[NSFont systemFontOfSize:12.0]];
    [postStatusField setTextColor:[NSColor colorWithCalibratedRed:0.95 green:0.40 blue:0.40 alpha:1.0]];
    postSubmitButton = [[DLPrimaryButton alloc] initWithFrame:NSZeroRect];
    [postSubmitButton setTitle:@"Post"];
    [postSubmitButton setTarget:self];
    [postSubmitButton setAction:@selector(submitNewPost:)];
    postCancelButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    [postCancelButton setBordered:NO];
    [postCancelButton setAttributedTitle:[[[NSAttributedString alloc] initWithString:@"Cancel"
        attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:13.0], NSFontAttributeName,
                    [DLUtil nativePrimaryTextColor], NSForegroundColorAttributeName, nil]] autorelease]];
    [postCancelButton setTarget:self];
    [postCancelButton setAction:@selector(cancelNewPost:)];
    [composeView addSubview:postTitleField];
    [composeView addSubview:postMessageField];
    [composeView addSubview:postStatusField];
    [composeView addSubview:postSubmitButton];
    [composeView addSubview:postCancelButton];
    [composeView setHidden:YES];
    [listPane addSubview:composeView];
    postTagButtons = [[NSMutableArray alloc] init];

    listScrollView = [[NSScrollView alloc] initWithFrame:
                      NSMakeRect(0.0, 0.0, NSWidth(paneBounds), NSHeight(paneBounds) - 56.0)];
    [listScrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [listScrollView setBorderType:NSNoBorder];
    [listScrollView setHasVerticalScroller:YES];
    [listScrollView setDrawsBackground:YES];
    [listScrollView setBackgroundColor:[DLUtil nativeContentColor]];
    NSScroller_BGColor *scroller = [[[NSScroller_BGColor alloc] initWithFrame:NSZeroRect] autorelease];
    [scroller setBackgroundColor:[DLUtil nativeContentColor]];
    [listScrollView setVerticalScroller:scroller];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"post"] autorelease];
    [column setWidth:NSWidth([listScrollView bounds])];
    [column setResizingMask:NSTableColumnAutoresizingMask];
    [column setDataCell:[[[DLForumPostCell alloc] init] autorelease]];
    listTableView = [[DLContextTableView alloc] initWithFrame:[[listScrollView contentView] bounds]];
    [listTableView setFocusRingType:NSFocusRingTypeNone];
    [listTableView addTableColumn:column];
    [listTableView setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
    [listTableView setHeaderView:nil];
    [listTableView setDataSource:self];
    [listTableView setDelegate:self];
    [listTableView setIntercellSpacing:NSMakeSize(0.0, 0.0)];
    [listTableView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleNone];
    [listTableView setGridStyleMask:NSTableViewGridNone];
    [listTableView setBackgroundColor:[DLUtil nativeContentColor]];
    [listTableView setTarget:self];
    [listTableView setAction:@selector(openClickedPost:)];
    [listScrollView setDocumentView:listTableView];
    [listPane addSubview:listScrollView];

    emptyField = [[NSTextField alloc] initWithFrame:
                  NSMakeRect(20.0, NSMidY(paneBounds) - 30.0, NSWidth(paneBounds) - 40.0, 60.0)];
    [emptyField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin];
    [emptyField setBezeled:NO];
    [emptyField setDrawsBackground:NO];
    [emptyField setEditable:NO];
    [emptyField setSelectable:NO];
    [emptyField setAlignment:NSCenterTextAlignment];
    [emptyField setFont:[NSFont boldSystemFontOfSize:15.0]];
    [emptyField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [listPane addSubview:emptyField];

    [hostView addSubview:listPane];
    [listPane setHidden:YES];
    allItems = [[NSArray alloc] init];
    items = [[NSArray alloc] init];
    visible = NO;
}

// Forum mode: full-width search bar. Thread mode: title, search and close.
-(void)layoutTopBar {
    NSRect paneBounds = [listPane bounds];
    BOOL forum = [self isForumMode];
    [titleField setHidden:forum];
    [closeButton setHidden:forum];
    [newPostButton setHidden:!forum];
    [newPostButton setFrame:NSMakeRect(NSWidth(paneBounds) - DLForumCardMargin - 96.0, NSHeight(paneBounds) - 42.0, 96.0, 28.0)];
    CGFloat left = forum ? DLForumCardMargin : DLForumCardMargin + 90.0;
    CGFloat right = forum ? DLForumCardMargin + 106.0 : 46.0;
    [searchField setFrame:NSMakeRect(left, NSHeight(paneBounds) - 42.0,
                                     MAX(80.0, NSWidth(paneBounds) - left - right), 28.0)];
    [[searchField cell] setPlaceholderString:(forum ? @"Search posts" : @"Search threads")];
    [emptyField setStringValue:(forum ? @"There are no posts yet." : @"There are no threads here yet.")];
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
    [searchField setStringValue:@""];
    [self setComposing:NO];
    [self layoutTopBar];
    [self reloadItems];
    [[DLController sharedInstance] loadArchivedThreadsForChannel:parentChannel];
    [listTableView scrollRowToVisible:0];
    [chatScrollView setHidden:YES];
    [composerView setHidden:YES];
    [listPane setHidden:NO];
    visible = YES;
}

-(void)reloadItems {
    DLServer *server = [[DLController sharedInstance] selectedServer];
    NSArray *threads = (server && baseChannel)
        ? [[DLController sharedInstance] activeThreadsForServer:server parentChannel:baseChannel]
        : [NSArray array];
    [allItems release];
    allItems = [threads retain];
    [self applySearchFilter];
}

-(void)applySearchFilter {
    NSString *query = [[searchField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSArray *filtered = allItems;
    if ([query length]) {
        NSMutableArray *matches = [NSMutableArray array];
        NSEnumerator *enumerator = [allItems objectEnumerator];
        DLServerChannel *thread;
        while (thread = [enumerator nextObject]) {
            NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@", [thread name] ? [thread name] : @"",
                                  [[thread starterSummary] objectForKey:@"text"] ? [[thread starterSummary] objectForKey:@"text"] : @"",
                                  [DLAppliedTagNames(thread) componentsJoinedByString:@" "]];
            if ([haystack rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [matches addObject:thread];
            }
        }
        filtered = matches;
    }
    [items release];
    items = [filtered retain];
    [listTableView noteNumberOfRowsChanged];
    [listTableView reloadData];
    [emptyField setHidden:([items count] != 0)];
}

-(void)controlTextDidChange:(NSNotification *)notification {
    if ([notification object] == searchField) [self applySearchFilter];
}

-(void)openClickedPost:(id)sender {
    NSInteger row = [listTableView clickedRow];
    if (row < 0 || row >= (NSInteger)[items count]) return;
    DLChannel *thread = [[[items objectAtIndex:row] retain] autorelease];
    [self hideThreadBrowser];
    [delegate threadController:self selectChannel:thread];
}

-(void)hideThreadBrowser {
    if (!visible) {
        return;
    }
    [listPane setHidden:YES];
    [chatScrollView setHidden:NO];
    [composerView setHidden:NO];
    visible = NO;
    [chatScrollView screenResize];
}

-(IBAction)closeThreadList:(id)sender {
    DLChannel *channel = [baseChannel retain];
    [self hideThreadBrowser];
    if (channel) {
        [delegate threadController:self restoreBaseChannel:channel];
    }
    [channel release];
}

// The post list fills the pane below the top bar and, while drafting, below
// the draft card.
-(void)layoutListArea {
    NSRect paneBounds = [listPane bounds];
    CGFloat top = NSHeight(paneBounds) - 56.0;
    if (composing) {
        CGFloat width = NSWidth(paneBounds) - DLForumCardMargin * 2.0;
        CGFloat inner = width - 32.0;
        BOOL hasTags = [postTagButtons count] > 0;
        CGFloat height = 16.0 + 32.0 + 8.0 + 88.0 + (hasTags ? 34.0 : 0.0) + 44.0;
        [composeView setFrame:NSMakeRect(DLForumCardMargin, top - height, width, height)];
        CGFloat y = height - 16.0 - 32.0;
        [postTitleField setFrame:NSMakeRect(16.0, y, inner, 32.0)];
        y -= 8.0 + 88.0;
        [postMessageField setFrame:NSMakeRect(16.0, y, inner, 88.0)];
        if (hasTags) {
            y -= 34.0;
            CGFloat x = 16.0;
            NSEnumerator *enumerator = [postTagButtons objectEnumerator];
            NSButton *tagButton;
            while (tagButton = [enumerator nextObject]) {
                CGFloat tagWidth = ceil([[tagButton title] sizeWithAttributes:
                    [NSDictionary dictionaryWithObject:[NSFont boldSystemFontOfSize:11.0] forKey:NSFontAttributeName]].width) + 22.0;
                [tagButton setHidden:(x + tagWidth > inner + 16.0)];
                [tagButton setFrame:NSMakeRect(x, y + 4.0, tagWidth, 24.0)];
                x += tagWidth + 6.0;
            }
        }
        [postSubmitButton setFrame:NSMakeRect(width - 16.0 - 80.0, 10.0, 80.0, 28.0)];
        [postCancelButton setFrame:NSMakeRect(width - 16.0 - 80.0 - 76.0, 10.0, 70.0, 28.0)];
        [postStatusField setFrame:NSMakeRect(16.0, 14.0, MAX(40.0, width - 210.0), 18.0)];
        top -= height + 8.0;
    }
    [listScrollView setFrame:NSMakeRect(0.0, 0.0, NSWidth(paneBounds), MAX(40.0, top))];
}

-(void)setComposing:(BOOL)shouldCompose {
    composing = shouldCompose && [self isForumMode];
    [composeView setHidden:!composing];
    [newPostButton setEnabled:!composing];
    if (composing) {
        [postTagButtons makeObjectsPerformSelector:@selector(removeFromSuperview)];
        [postTagButtons removeAllObjects];
        NSEnumerator *enumerator = [[(DLServerChannel *)baseChannel availableTags] objectEnumerator];
        NSDictionary *tag;
        while (tag = [enumerator nextObject]) {
            if (![tag isKindOfClass:[NSDictionary class]] || ![[tag objectForKey:@"name"] isKindOfClass:[NSString class]]) continue;
            DLTagToggleButton *tagButton = [[[DLTagToggleButton alloc] initWithFrame:NSZeroRect] autorelease];
            [tagButton setButtonType:NSPushOnPushOffButton];
            [tagButton setBordered:NO];
            NSString *emoji = [tag objectForKey:@"emoji_name"];
            [tagButton setTitle:([emoji isKindOfClass:[NSString class]] && [emoji length])
                ? [NSString stringWithFormat:@"%@ %@", emoji, [tag objectForKey:@"name"]] : [tag objectForKey:@"name"]];
            [[tagButton cell] setRepresentedObject:[[tag objectForKey:@"id"] description]];
            [composeView addSubview:tagButton];
            [postTagButtons addObject:tagButton];
        }
        [postTitleField setStringValue:@""];
        [postMessageField setStringValue:@""];
        [postStatusField setStringValue:@""];
        [postSubmitButton setEnabled:YES];
        [[listPane window] makeFirstResponder:postTitleField];
    }
    [self layoutListArea];
}

-(IBAction)beginNewPost:(id)sender {
    [self setComposing:YES];
}

-(IBAction)cancelNewPost:(id)sender {
    [self setComposing:NO];
}

-(IBAction)submitNewPost:(id)sender {
    NSString *title = [[postTitleField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *message = [[postMessageField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *tagIDs = [NSMutableArray array];
    NSEnumerator *enumerator = [postTagButtons objectEnumerator];
    NSButton *tagButton;
    while (tagButton = [enumerator nextObject]) {
        if ([tagButton state] == NSOnState && [[tagButton cell] representedObject]) [tagIDs addObject:[[tagButton cell] representedObject]];
    }
    if (![title length] || ![message length]) {
        [postStatusField setStringValue:@"A post needs a title and a message."];
        return;
    }
    if ([(DLServerChannel *)baseChannel requiresTag] && ![tagIDs count]) {
        [postStatusField setStringValue:@"This forum requires at least one tag."];
        return;
    }
    [postStatusField setStringValue:@""];
    [postSubmitButton setEnabled:NO];
    [[DLController sharedInstance] createForumPostInChannel:(DLServerChannel *)baseChannel
                                                      title:title content:message tagIDs:tagIDs];
}

-(void)forumPostCreationDidFinish:(NSNotification *)notification {
    if (![[notification object] isEqual:baseChannel]) return;
    DLChannel *thread = [[notification userInfo] objectForKey:@"thread"];
    if (!thread) {
        [postSubmitButton setEnabled:YES];
        [postStatusField setStringValue:[[notification userInfo] objectForKey:@"error"]];
        return;
    }
    // Like the official client, the new post opens right away.
    [self setComposing:NO];
    [self hideThreadBrowser];
    [delegate threadController:self selectChannel:thread];
}

-(void)threadStarterDidLoad:(NSNotification *)notification {
    if (!visible) return;
    NSUInteger index = [items indexOfObjectIdenticalTo:[notification object]];
    if (index == NSNotFound) return;
    [listTableView setNeedsDisplayInRect:[listTableView rectOfRow:(NSInteger)index]];
}

-(void)refreshForServer:(DLServer *)server {
    if (!server || ![server isEqual:[[DLController sharedInstance] selectedServer]]) {
        return;
    }
    if (visible && baseChannel) [self reloadItems];
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
    [self reloadItems];
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
    [listScrollView setBackgroundColor:[DLUtil nativeContentColor]];
    [(NSScroller_BGColor *)[listScrollView verticalScroller] setBackgroundColor:[DLUtil nativeContentColor]];
    [listTableView setBackgroundColor:[DLUtil nativeContentColor]];
    [searchField setBackgroundColor:[DLUtil nativeInputColor]];
    [titleField setTextColor:[DLUtil nativePrimaryTextColor]];
    [emptyField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [listTableView reloadData];
}

-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [items count];
}

-(id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    return [[items objectAtIndex:row] name];
}

-(CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)[items count]) return 96.0;
    BOOL hasTags = [self isForumMode] && [DLAppliedTagNames([items objectAtIndex:row]) count] > 0;
    return 96.0 + (hasTags ? DLForumTagRowHeight : 0.0);
}

-(BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    return NO;
}

-(void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (![cell isKindOfClass:[DLForumPostCell class]] || row >= (NSInteger)[items count]) return;
    DLServerChannel *thread = [items objectAtIndex:row];
    BOOL forum = [self isForumMode];
    [(DLForumPostCell *)cell setRepresentedThread:thread forumPost:forum
                                          hovered:(row == [listTableView hoveredRow])];
    // Opening messages load lazily for the posts actually on screen.
    if (forum) [[DLController sharedInstance] loadStarterMessageForThread:thread];
}

-(NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)column row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation {
    return nil;
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self hideThreadBrowser];
    [listTableView setDelegate:nil];
    [listTableView setDataSource:nil];
    [searchField setDelegate:nil];
    [baseChannel release];
    [allItems release];
    [items release];
    [emptyField release];
    [titleField release];
    [closeButton release];
    [searchField release];
    [newPostButton release];
    [composeView release];
    [postTitleField release];
    [postMessageField release];
    [postTagButtons release];
    [postSubmitButton release];
    [postCancelButton release];
    [postStatusField release];
    [listTableView release];
    [listScrollView release];
    [listPane release];
    [composerView release];
    [chatScrollView release];
    [hostView release];
    [super dealloc];
}
@end
