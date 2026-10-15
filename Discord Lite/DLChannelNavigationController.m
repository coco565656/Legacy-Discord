//
//  DLChannelNavigationController.m
//  Legacy Discord
//

#import "DLChannelNavigationController.h"
#import "DLController.h"
#import "DLUtil.h"
#import "DLTwemojiRenderer.h"
#import "DynamicScrollView.h"
#if LEGACY_DISCORD_UI_DIAGNOSTICS
#import "DLUIDiagnostics.h"
#endif

@interface DLChannelOutlineView : NSOutlineView {
    NSInteger hoveredRow;
    NSInteger pendingHoveredRow;
    NSTrackingArea *hoverTrackingArea;
}
-(NSInteger)hoveredRow;
@end

@implementation DLChannelOutlineView

-(id)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        hoveredRow = -1;
        pendingHoveredRow = -1;
    }
    return self;
}

-(NSInteger)hoveredRow {
    return hoveredRow;
}

-(void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [[self window] setAcceptsMouseMovedEvents:YES];
    [self updateTrackingAreas];
}

-(void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (hoverTrackingArea) {
        [self removeTrackingArea:hoverTrackingArea];
        [hoverTrackingArea release];
        hoverTrackingArea = nil;
    }
    if ([self window]) {
        NSTrackingAreaOptions options = NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
            NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect;
        hoverTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                         options:options
                                                           owner:self
                                                        userInfo:nil];
        [self addTrackingArea:hoverTrackingArea];
    }
}

-(void)setHoveredRow:(NSInteger)row {
    if (hoveredRow == row) return;
    NSInteger previousRow = hoveredRow;
    hoveredRow = row;
    if (previousRow >= 0 && previousRow < [self numberOfRows]) {
        [self setNeedsDisplayInRect:[self rectOfRow:previousRow]];
    }
    if (hoveredRow >= 0 && hoveredRow < [self numberOfRows]) {
        [self setNeedsDisplayInRect:[self rectOfRow:hoveredRow]];
    }
}

-(void)mouseMoved:(NSEvent *)event {
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSInteger row = [self rowAtPoint:point];
    if (row == hoveredRow) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyPendingHoveredRow) object:nil];
        pendingHoveredRow = -1;
        return;
    }
    if (row == pendingHoveredRow) return;
    pendingHoveredRow = row;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyPendingHoveredRow) object:nil];
    [self performSelector:@selector(applyPendingHoveredRow) withObject:nil afterDelay:0.06];
}

-(void)applyPendingHoveredRow {
    NSInteger row = pendingHoveredRow;
    pendingHoveredRow = -1;
    [self setHoveredRow:row];
}

-(void)mouseExited:(NSEvent *)event {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyPendingHoveredRow) object:nil];
    pendingHoveredRow = -1;
    [self setHoveredRow:-1];
}

-(void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyPendingHoveredRow) object:nil];
    if (hoverTrackingArea) {
        [self removeTrackingArea:hoverTrackingArea];
        [hoverTrackingArea release];
    }
    [super dealloc];
}

@end

@interface DLChannelTableCell : NSCell {
    DLChannel *representedChannel;
}
-(void)setRepresentedChannel:(DLChannel *)channel;
@end

@implementation DLChannelTableCell

-(void)setRepresentedChannel:(DLChannel *)channel {
    representedChannel = channel;
}

-(void)drawHashIconInRect:(NSRect)rect color:(NSColor *)color {
    [color set];
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat left = NSMinX(rect) + 4.5;
    CGFloat right = NSMinX(rect) + 10.5;
    CGFloat bottom = NSMinY(rect) + 3.0;
    CGFloat top = NSMaxY(rect) - 3.0;
    [path moveToPoint:NSMakePoint(left + 1.0, bottom)];
    [path lineToPoint:NSMakePoint(left - 1.0, top)];
    [path moveToPoint:NSMakePoint(right + 1.0, bottom)];
    [path lineToPoint:NSMakePoint(right - 1.0, top)];
    [path moveToPoint:NSMakePoint(NSMinX(rect) + 2.0, NSMidY(rect) - 3.0)];
    [path lineToPoint:NSMakePoint(NSMaxX(rect) - 2.0, NSMidY(rect) - 3.0)];
    [path moveToPoint:NSMakePoint(NSMinX(rect) + 1.0, NSMidY(rect) + 3.0)];
    [path lineToPoint:NSMakePoint(NSMaxX(rect) - 3.0, NSMidY(rect) + 3.0)];
    [path setLineWidth:1.6];
    [path stroke];
}

-(void)drawVoiceIconInRect:(NSRect)rect color:(NSColor *)color {
    [color set];
    CGFloat midY = NSMidY(rect);
    NSRect speakerBody = NSMakeRect(NSMinX(rect) + 2.0, midY - 2.5, 4.0, 5.0);
    NSRectFill(speakerBody);
    NSBezierPath *cone = [NSBezierPath bezierPath];
    [cone moveToPoint:NSMakePoint(NSMaxX(speakerBody), midY - 2.5)];
    [cone lineToPoint:NSMakePoint(NSMinX(rect) + 11.0, midY - 6.0)];
    [cone lineToPoint:NSMakePoint(NSMinX(rect) + 11.0, midY + 6.0)];
    [cone lineToPoint:NSMakePoint(NSMaxX(speakerBody), midY + 2.5)];
    [cone closePath];
    [cone fill];
    NSBezierPath *wave = [NSBezierPath bezierPath];
    [wave moveToPoint:NSMakePoint(NSMinX(rect) + 13.0, midY - 4.0)];
    [wave curveToPoint:NSMakePoint(NSMinX(rect) + 13.0, midY + 4.0)
          controlPoint1:NSMakePoint(NSMinX(rect) + 16.0, midY - 2.0)
          controlPoint2:NSMakePoint(NSMinX(rect) + 16.0, midY + 2.0)];
    [wave setLineWidth:1.4];
    [wave stroke];
}

-(void)drawThreadIconInRect:(NSRect)rect color:(NSColor *)color {
    [color set];
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat left = NSMinX(rect) + 4.0;
    CGFloat right = NSMaxX(rect) - 3.0;
    CGFloat lower = NSMinY(rect) + 5.0;
    CGFloat upper = NSMaxY(rect) - 5.0;
    [path moveToPoint:NSMakePoint(left, upper)];
    [path lineToPoint:NSMakePoint(right, upper)];
    [path lineToPoint:NSMakePoint(right, NSMidY(rect))];
    [path moveToPoint:NSMakePoint(left, lower)];
    [path lineToPoint:NSMakePoint(right - 4.0, lower)];
    [path lineToPoint:NSMakePoint(right - 4.0, NSMidY(rect))];
    [path setLineWidth:1.8];
    [path setLineCapStyle:NSRoundLineCapStyle];
    [path setLineJoinStyle:NSRoundLineJoinStyle];
    [path stroke];
}

-(void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (!representedChannel) return;
    BOOL isCategory = ([representedChannel type] == ChannelTypeHeader);
    NSInteger row = [(NSOutlineView *)controlView rowAtPoint:NSMakePoint(NSMidX(cellFrame), NSMidY(cellFrame))];
    BOOL selected = (row >= 0 && [[(NSOutlineView *)controlView selectedRowIndexes] containsIndex:(NSUInteger)row]);
    BOOL hovered = ([controlView isKindOfClass:[DLChannelOutlineView class]] &&
                    row == [(DLChannelOutlineView *)controlView hoveredRow]);
    // Traditional Snow Leopard scroll bars reserve space inside the scroll
    // view.  NSTableView can still hand the cell the wider document frame, so
    // keep right-aligned content inside the portion that is actually visible.
    NSRect contentRect = NSIntersectionRect(cellFrame, [controlView visibleRect]);

    if (!isCategory && selected) {
        NSRect selectionRect = NSInsetRect(cellFrame, 2.0, 2.0);
        [[DLUtil nativeSelectionColor] set];
        [[NSBezierPath bezierPathWithRoundedRect:selectionRect xRadius:5.0 yRadius:5.0] fill];
    } else if (!isCategory && hovered) {
        NSRect hoverRect = NSInsetRect(cellFrame, 2.0, 2.0);
        [[[DLUtil nativeSelectionColor] colorWithAlphaComponent:0.55] set];
        [[NSBezierPath bezierPathWithRoundedRect:hoverRect xRadius:5.0 yRadius:5.0] fill];
    }

    NSString *name = [representedChannel name] ? [representedChannel name] : @"Untitled";
    NSFont *font = isCategory ? [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]]
                              : ([representedChannel hasUnreadMessages]
                                 ? [NSFont boldSystemFontOfSize:[NSFont systemFontSize]]
                                 : [NSFont systemFontOfSize:[NSFont systemFontSize]]);
    BOOL emphasized = selected || hovered || [representedChannel hasUnreadMessages];
    NSColor *textColor = isCategory ? [DLUtil nativeSecondaryTextColor]
                                    : (emphasized ? [DLUtil nativePrimaryTextColor]
                                                  : [DLUtil nativeSecondaryTextColor]);
    NSMutableParagraphStyle *paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [paragraphStyle setLineBreakMode:NSLineBreakByTruncatingTail];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                font, NSFontAttributeName, textColor, NSForegroundColorAttributeName,
                                paragraphStyle, NSParagraphStyleAttributeName, nil];

    if (isCategory) {
        NSString *categoryName = [name uppercaseString];
        NSMutableAttributedString *categoryText = [[[NSMutableAttributedString alloc]
            initWithString:categoryName attributes:attributes] autorelease];
        [DLTwemojiRenderer replaceEmojiInAttributedString:categoryText size:11.0
                                       excludingAttribute:nil recordingAttribute:nil cursorLocation:NULL];
        NSSize textSize = [categoryText size];
        [categoryText drawInRect:NSMakeRect(NSMinX(contentRect) + 3.0,
                                            NSMidY(contentRect) - textSize.height / 2.0,
                                            NSWidth(contentRect) - 8.0, textSize.height)
                        ];
        return;
    }

    if ([representedChannel hasUnreadMessages] && !selected) {
        [[DLUtil nativePrimaryTextColor] set];
        NSRect unreadRect = NSMakeRect(NSMinX(contentRect), NSMidY(contentRect) - 4.0, 3.0, 8.0);
        [[NSBezierPath bezierPathWithRoundedRect:unreadRect xRadius:1.5 yRadius:1.5] fill];
    }

    NSColor *iconColor = emphasized ? [DLUtil nativePrimaryTextColor] : [DLUtil nativeSecondaryTextColor];
    BOOL isDirectMessage = ([representedChannel type] == ChannelTypeDM ||
                            [representedChannel type] == ChannelTypeGroup);
    NSRect iconRect = isDirectMessage
        ? NSMakeRect(NSMinX(contentRect) + 7.0, NSMidY(contentRect) - 16.0, 32.0, 32.0)
        : NSMakeRect(NSMinX(contentRect) + 7.0, NSMidY(contentRect) - 9.0, 18.0, 18.0);
    if (isDirectMessage) {
        NSImage *avatar = [[[NSImage alloc] initWithData:[representedChannel imageData]] autorelease];
        if (avatar) {
            [NSGraphicsContext saveGraphicsState];
            [[NSBezierPath bezierPathWithOvalInRect:iconRect] addClip];
            [avatar drawInRect:iconRect fromRect:NSZeroRect operation:NSCompositeSourceOver
                      fraction:1.0 respectFlipped:YES hints:nil];
            [NSGraphicsContext restoreGraphicsState];
        }
    } else if ([representedChannel type] == ChannelTypeVoice || [representedChannel type] == ChannelTypeStageVoice) {
        [self drawVoiceIconInRect:iconRect color:iconColor];
    } else if ([representedChannel isThread]) {
        [self drawThreadIconInRect:iconRect color:iconColor];
    } else {
        [self drawHashIconInRect:iconRect color:iconColor];
    }

    CGFloat rightInset = 8.0;
    NSInteger mentionCount = [representedChannel mentionCount];
    if (mentionCount > 0) {
        NSString *badgeText = mentionCount > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)mentionCount];
        NSDictionary *badgeAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                         [NSFont boldSystemFontOfSize:9.0], NSFontAttributeName,
                                         [NSColor whiteColor], NSForegroundColorAttributeName, nil];
        NSSize badgeTextSize = [badgeText sizeWithAttributes:badgeAttributes];
        CGFloat badgeWidth = MAX(18.0, badgeTextSize.width + 8.0);
        NSRect badgeRect = NSMakeRect(NSMaxX(contentRect) - badgeWidth - 5.0,
                                     NSMidY(contentRect) - 8.0, badgeWidth, 16.0);
        [[NSColor colorWithCalibratedRed:0.80 green:0.10 blue:0.12 alpha:1.0] set];
        [[NSBezierPath bezierPathWithRoundedRect:badgeRect xRadius:8.0 yRadius:8.0] fill];
        [badgeText drawAtPoint:NSMakePoint(NSMidX(badgeRect) - badgeTextSize.width / 2.0,
                                          NSMidY(badgeRect) - badgeTextSize.height / 2.0)
                   withAttributes:badgeAttributes];
        rightInset += badgeWidth + 4.0;
    }

    NSMutableAttributedString *channelText = [[[NSMutableAttributedString alloc]
        initWithString:name attributes:attributes] autorelease];
    [DLTwemojiRenderer replaceEmojiInAttributedString:channelText size:14.0
                                   excludingAttribute:nil recordingAttribute:nil cursorLocation:NULL];
    NSSize textSize = [channelText size];
    CGFloat textOriginX = isDirectMessage ? NSMinX(contentRect) + 47.0 : NSMinX(contentRect) + 30.0;
    [channelText drawInRect:NSMakeRect(textOriginX,
                                NSMidY(contentRect) - textSize.height / 2.0,
                                MAX(0.0, NSMaxX(contentRect) - textOriginX - rightInset),
                                textSize.height)];
}

@end

@interface DLChannelNavigationController ()
-(void)installOutlineView;
-(void)refreshChannelItem:(DLChannel *)channel;
-(void)finishChannelImageUpdate:(NSDictionary *)context;
-(void)setModelDelegatesForItems:(NSArray *)items delegate:(id<DLChannelDelegate>)inDelegate;
@end

@implementation DLChannelNavigationController

-(id)initWithScrollView:(DynamicScrollView *)inScrollView {
    self = [super init];
    if (self) {
        scrollView = [inScrollView retain];
        [self installOutlineView];
    }
    return self;
}

-(void)setDelegate:(id<DLChannelNavigationControllerDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)installOutlineView {
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"channel"] autorelease];
    [column setWidth:NSWidth([[scrollView contentView] bounds])];
    [column setResizingMask:NSTableColumnAutoresizingMask];
    [column setDataCell:[[[DLChannelTableCell alloc] init] autorelease]];
    outlineView = [[DLChannelOutlineView alloc] initWithFrame:[[scrollView contentView] bounds]];
    [outlineView addTableColumn:column];
    [outlineView setOutlineTableColumn:column];
    [outlineView setHeaderView:nil];
    [outlineView setDataSource:self];
    [outlineView setDelegate:self];
    [outlineView setRowHeight:32.0];
    [outlineView setIntercellSpacing:NSMakeSize(0.0, 1.0)];
    [outlineView setIndentationPerLevel:14.0];
    [outlineView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleNone];
    [outlineView setAllowsMultipleSelection:NO];
    [outlineView setAllowsEmptySelection:YES];
    [outlineView setFocusRingType:NSFocusRingTypeNone];
    [outlineView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [outlineView setAutoresizesOutlineColumn:YES];
    [scrollView setDocumentView:outlineView];
}

-(void)setModelDelegatesForItems:(NSArray *)items delegate:(id<DLChannelDelegate>)inDelegate {
    NSEnumerator *enumerator = [items objectEnumerator];
    DLChannel *item;
    while (item = [enumerator nextObject]) {
        [item setDelegate:inDelegate];
        [self setModelDelegatesForItems:[item children] delegate:inDelegate];
    }
}

-(void)displayChannelItems:(NSArray *)items {
    BOOL showingDirectMessages = [[[DLController sharedInstance] selectedServer]
                                  isEqual:[[DLController sharedInstance] myServerItem]];
    [self displayChannelItems:items
        showingDirectMessages:showingDirectMessages
               selectedChannel:[[DLController sharedInstance] selectedChannel]];
}

-(void)displayChannelItems:(NSArray *)items
     showingDirectMessages:(BOOL)showingDirectMessages
            selectedChannel:(DLChannel *)selectedChannel {
    [channelItems release];
    channelItems = [items retain];
    [outlineView setRowHeight:(showingDirectMessages ? 42.0 : 32.0)];
    [outlineView setIndentationPerLevel:(showingDirectMessages ? 0.0 : 14.0)];
    [outlineView reloadData];

    [self setModelDelegatesForItems:channelItems delegate:self];
    NSEnumerator *enumerator = [channelItems objectEnumerator];
    DLChannel *item;
    while (item = [enumerator nextObject]) {
        if ([[item children] count] > 0) [outlineView expandItem:item];
        NSEnumerator *childEnumerator = [[item children] objectEnumerator];
        DLChannel *child;
        while (child = [childEnumerator nextObject]) {
            if ([[child children] count] > 0) [outlineView expandItem:child];
        }
    }

    [self selectChannelWithoutNotifying:selectedChannel];
    [delegate channelNavigationController:self
                 didFinishDisplayingItems:items
                    showingDirectMessages:showingDirectMessages
                           selectedChannel:selectedChannel];
}

-(void)selectChannelWithoutNotifying:(DLChannel *)channel {
    NSInteger row = channel ? [outlineView rowForItem:channel] : -1;
    updatingSelection = YES;
    if (row >= 0) {
        [outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    } else {
        [outlineView deselectAll:self];
    }
    updatingSelection = NO;
}

-(void)applyCurrentTheme {
    [outlineView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [outlineView reloadData];
}

-(NSInteger)outlineView:(NSOutlineView *)inOutlineView numberOfChildrenOfItem:(id)item {
    return item ? [[(DLChannel *)item children] count] : [channelItems count];
}

-(id)outlineView:(NSOutlineView *)inOutlineView child:(NSInteger)index ofItem:(id)item {
    return item ? [[(DLChannel *)item children] objectAtIndex:index] : [channelItems objectAtIndex:index];
}

-(BOOL)outlineView:(NSOutlineView *)inOutlineView isItemExpandable:(id)item {
    return [[(DLChannel *)item children] count] > 0;
}

-(id)outlineView:(NSOutlineView *)inOutlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    DLChannel *channel = (DLChannel *)item;
    NSString *name = [channel name] ? [channel name] : @"Untitled";
    if ([channel type] == ChannelTypeHeader) return [name uppercaseString];
    NSString *kindPrefix = @"";
    if ([channel isThread]) kindPrefix = @"↳ ";
    else if ([channel type] == ChannelTypeStandard || [channel type] == ChannelTypeAnnouncements ||
             [channel type] == ChannelTypeForum || [channel type] == ChannelTypeMedia) kindPrefix = @"# ";
    else if ([channel type] == ChannelTypeVoice || [channel type] == ChannelTypeStageVoice) kindPrefix = @"◖ ";
    NSString *unreadPrefix = [channel hasUnreadMessages] ? @"● " : @"";
    NSString *mentionSuffix = [channel mentionCount] > 0
        ? [NSString stringWithFormat:@"  (%ld)", (long)[channel mentionCount]] : @"";
    return [NSString stringWithFormat:@"%@%@%@%@", unreadPrefix, kindPrefix, name, mentionSuffix];
}

-(BOOL)outlineView:(NSOutlineView *)inOutlineView isGroupItem:(id)item {
    return NO;
}

-(BOOL)outlineView:(NSOutlineView *)inOutlineView shouldSelectItem:(id)item {
    return [(DLChannel *)item type] != ChannelTypeHeader;
}

-(void)outlineView:(NSOutlineView *)inOutlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    if ([cell isKindOfClass:[DLChannelTableCell class]]) {
        [(DLChannelTableCell *)cell setRepresentedChannel:(DLChannel *)item];
    }
    [cell setLineBreakMode:NSLineBreakByTruncatingTail];
}

-(void)outlineViewSelectionDidChange:(NSNotification *)notification {
    if (updatingSelection) return;
    NSInteger row = [outlineView selectedRow];
    if (row < 0) return;
    DLChannel *channel = [outlineView itemAtRow:row];
    if ([channel type] != ChannelTypeHeader) {
        [delegate channelNavigationController:self didSelectChannel:channel];
    }
}

-(void)refreshChannelItem:(DLChannel *)channel {
    NSInteger row = [outlineView rowForItem:channel];
    if (row < 0) return;
#if LEGACY_DISCORD_UI_DIAGNOSTICS
    [DLUIDiagnostics recordEvent:@"channel-outline-reload-item"
                         details:[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:row]
                                                             forKey:@"row"]];
#endif
    [outlineView reloadItem:channel];
}

-(void)mentionsUpdatedForChannel:(DLChannel *)channel {
    [self performSelectorOnMainThread:@selector(refreshChannelItem:) withObject:channel waitUntilDone:NO];
}

-(void)unreadStatusUpdatedForChannel:(DLChannel *)channel {
    [self performSelectorOnMainThread:@selector(refreshChannelItem:) withObject:channel waitUntilDone:NO];
}

-(void)channel:(DLChannel *)channel imageDidUpdateWithData:(NSData *)data {
    NSDictionary *context = [NSDictionary dictionaryWithObjectsAndKeys:
                             channel, @"channel", data ? data : [NSData data], @"data", nil];
    [self performSelectorOnMainThread:@selector(finishChannelImageUpdate:)
                           withObject:context waitUntilDone:NO];
}

-(void)finishChannelImageUpdate:(NSDictionary *)context {
    DLChannel *channel = [context objectForKey:@"channel"];
    NSData *data = [context objectForKey:@"data"];
    [self refreshChannelItem:channel];
    [delegate channelNavigationController:self imageDidUpdateWithData:data forChannel:channel];
}

-(void)dealloc {
    delegate = nil;
    [self setModelDelegatesForItems:channelItems delegate:nil];
    [channelItems release];
    [outlineView setDelegate:nil];
    [outlineView setDataSource:nil];
    [outlineView release];
    [scrollView release];
    [super dealloc];
}

@end
