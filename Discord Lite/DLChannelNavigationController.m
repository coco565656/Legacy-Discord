//
//  DLChannelNavigationController.m
//  Legacy Discord
//

#import "DLChannelNavigationController.h"
#import "DLController.h"
#import "DLVoiceManager.h"
#import "DLUtil.h"
#import "DLPreferencesHandler.h"
#import "DLTwemojiRenderer.h"
#import "DynamicScrollView.h"
#if LEGACY_DISCORD_UI_DIAGNOSTICS
#import "DLUIDiagnostics.h"
#endif

@interface DLChannelOutlineView : NSOutlineView {
    NSInteger hoveredRow;
    NSInteger pendingHoveredRow;
    NSTrackingArea *hoverTrackingArea;
    NSInteger menuRow;
}
-(NSInteger)hoveredRow;
-(NSInteger)menuRow;
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

-(NSInteger)menuRow {
    return menuRow;
}

// Not calling super avoids AppKit's blue outline around the right-clicked row.
-(NSMenu *)menuForEvent:(NSEvent *)event {
    menuRow = [self rowAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
    return menuRow >= 0 ? [self menu] : nil;
}

// A click on a category row expands or collapses it. Done here rather than in
// shouldSelectItem:, which AppKit may ask more than once per click.
-(void)mouseDown:(NSEvent *)event {
    NSInteger row = [self rowAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
    id item = row >= 0 ? [self itemAtRow:row] : nil;
    if ([item isKindOfClass:[DLChannel class]] && [(DLChannel *)item type] == ChannelTypeHeader) {
        if ([self isItemExpanded:item]) [self collapseItem:item];
        else [self expandItem:item];
        return;
    }
    [super mouseDown:event];
}

// No AppKit disclosure triangles: category rows draw Discord's chevron and
// toggle on click instead.
-(NSRect)frameOfOutlineCellAtRow:(NSInteger)row {
    return NSZeroRect;
}

// Channels sit flush with their category like the official list; only
// threads (level 2+) keep an indent.
-(NSRect)frameOfCellAtColumn:(NSInteger)column row:(NSInteger)row {
    NSRect columnRect = [self rectOfColumn:column];
    NSRect rowRect = [self rectOfRow:row];
    NSInteger level = [self levelForRow:row];
    CGFloat indent = level >= 2 ? (level - 1) * [self indentationPerLevel] : 0.0;
    return NSMakeRect(NSMinX(columnRect) + indent, NSMinY(rowRect),
                      MAX(0.0, NSWidth(columnRect) - indent), NSHeight(rowRect));
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

// Official forum icon: two overlapping speech bubbles.
-(void)drawForumIconInRect:(NSRect)rect color:(NSColor *)color flipped:(BOOL)flipped {
    [color set];
    CGFloat side = MIN(NSWidth(rect), NSHeight(rect));
    NSRect icon = NSMakeRect(NSMidX(rect) - side / 2.0, NSMidY(rect) - side / 2.0, side, side);
    CGFloat unit = side / 18.0;
    NSRect back = NSMakeRect(NSMinX(icon) + 2.0 * unit, NSMinY(icon) + (flipped ? 3.0 : 7.0) * unit, 10.0 * unit, 8.0 * unit);
    NSRect front = NSMakeRect(NSMinX(icon) + 6.0 * unit, NSMinY(icon) + (flipped ? 7.0 : 3.0) * unit, 10.0 * unit, 8.0 * unit);
    NSBezierPath *backPath = [NSBezierPath bezierPathWithRoundedRect:back xRadius:2.5 * unit yRadius:2.5 * unit];
    [backPath setLineWidth:1.6];
    [backPath stroke];
    [[DLUtil nativeSidebarColor] set];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(front, -1.2, -1.2) xRadius:3.0 * unit yRadius:3.0 * unit] fill];
    [color set];
    [[NSBezierPath bezierPathWithRoundedRect:front xRadius:2.5 * unit yRadius:2.5 * unit] fill];
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
    // Rows keep an 8-point margin on both sides of the list like Discord.
    if (!isCategory) contentRect = NSInsetRect(contentRect, 8.0, 0.0);

    if (!isCategory && selected) {
        NSRect selectionRect = NSInsetRect(contentRect, 0.0, 2.0);
        [[DLUtil nativeSelectionColor] set];
        [[NSBezierPath bezierPathWithRoundedRect:selectionRect xRadius:5.0 yRadius:5.0] fill];
    } else if (!isCategory && hovered) {
        NSRect hoverRect = NSInsetRect(contentRect, 0.0, 2.0);
        [[[DLUtil nativeSelectionColor] colorWithAlphaComponent:0.55] set];
        [[NSBezierPath bezierPathWithRoundedRect:hoverRect xRadius:5.0 yRadius:5.0] fill];
    }

    NSString *name = [representedChannel name] ? [representedChannel name] : @"Untitled";
    // Muted channels (or channels in a muted server) show no unread state;
    // a channel or category muted itself is also dimmed, like Discord.
    DLController *controller = [DLController existingInstance];
    BOOL muted = [controller isChannelMuted:representedChannel];
    BOOL dimmed = [controller isChannelMutedItself:representedChannel] ||
        (!isCategory && [representedChannel isKindOfClass:[DLServerChannel class]] &&
         [[(DLServerChannel *)representedChannel parentID] isKindOfClass:[NSString class]] &&
         [controller isChannelMutedItself:[controller loadedChannelWithID:[(DLServerChannel *)representedChannel parentID]]]);
    BOOL unread = [representedChannel hasUnreadMessages] && !muted;
    NSFont *font = isCategory ? [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]]
                              : (unread
                                 ? [NSFont boldSystemFontOfSize:[NSFont systemFontSize]]
                                 : [NSFont systemFontOfSize:[NSFont systemFontSize]]);
    BOOL emphasized = selected || hovered || unread;
    NSColor *textColor = isCategory ? [DLUtil nativeSecondaryTextColor]
                                    : (emphasized ? [DLUtil nativePrimaryTextColor]
                                                  : [DLUtil nativeSecondaryTextColor]);
    if (dimmed && !selected) textColor = [textColor colorWithAlphaComponent:0.45];
    NSMutableParagraphStyle *paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [paragraphStyle setLineBreakMode:NSLineBreakByTruncatingTail];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                font, NSFontAttributeName, textColor, NSForegroundColorAttributeName,
                                paragraphStyle, NSParagraphStyleAttributeName, nil];

    if (isCategory) {
        // Chevron: down when expanded, right when collapsed.
        BOOL expanded = [(NSOutlineView *)controlView isItemExpanded:representedChannel];
        BOOL flipped = [controlView isFlipped];
        CGFloat cx = NSMinX(contentRect) + 9.0;
        CGFloat cy = NSMidY(contentRect);
        NSBezierPath *chevron = [NSBezierPath bezierPath];
        if (expanded) {
            CGFloat dy = flipped ? 2.0 : -2.0;
            [chevron moveToPoint:NSMakePoint(cx - 3.5, cy - dy)];
            [chevron lineToPoint:NSMakePoint(cx, cy + dy)];
            [chevron lineToPoint:NSMakePoint(cx + 3.5, cy - dy)];
        } else {
            [chevron moveToPoint:NSMakePoint(cx - 1.5, cy - 3.5)];
            [chevron lineToPoint:NSMakePoint(cx + 2.0, cy)];
            [chevron lineToPoint:NSMakePoint(cx - 1.5, cy + 3.5)];
        }
        [chevron setLineWidth:1.5];
        [chevron setLineCapStyle:NSRoundLineCapStyle];
        [chevron setLineJoinStyle:NSRoundLineJoinStyle];
        [(dimmed ? [[DLUtil nativeSecondaryTextColor] colorWithAlphaComponent:0.45] : [DLUtil nativeSecondaryTextColor]) setStroke];
        [chevron stroke];
        contentRect.origin.x += 14.0;
        contentRect.size.width -= 14.0;
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

    if (unread && !selected) {
        [[DLUtil nativePrimaryTextColor] set];
        // Discord's unread pill hangs off the left edge of the channel list.
        NSRect unreadRect = NSMakeRect(NSMinX([controlView visibleRect]) - 4.0, NSMidY(contentRect) - 4.0, 8.0, 8.0);
        [[NSBezierPath bezierPathWithRoundedRect:unreadRect xRadius:4.0 yRadius:4.0] fill];
    }

    NSColor *iconColor = emphasized ? [DLUtil nativePrimaryTextColor] : [DLUtil nativeSecondaryTextColor];
    if (dimmed && !selected) iconColor = [iconColor colorWithAlphaComponent:0.45];
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
    } else if ([representedChannel type] == ChannelTypeForum || [representedChannel type] == ChannelTypeMedia) {
        [self drawForumIconInRect:iconRect color:iconColor flipped:[controlView isFlipped]];
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
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationSettingsDidChange:)
                                                     name:DLNotificationSettingsDidChangeNotification object:nil];
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
    // Right-click menu, rebuilt for the clicked row in menuNeedsUpdate:.
    NSMenu *channelMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    [channelMenu setDelegate:(id)self];
    [outlineView setMenu:channelMenu];
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

-(void)outlineView:(NSOutlineView *)inOutlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    if ([cell isKindOfClass:[DLChannelTableCell class]]) {
        [(DLChannelTableCell *)cell setRepresentedChannel:(DLChannel *)item];
    }
    [cell setLineBreakMode:NSLineBreakByTruncatingTail];
}

#pragma mark Context menu

-(NSMenuItem *)channelMenuItem:(NSString *)title action:(SEL)action channel:(DLChannel *)channel {
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""] autorelease];
    [item setTarget:self];
    [item setRepresentedObject:channel];
    return item;
}

-(BOOL)channelOrChildrenHaveUnread:(DLChannel *)channel {
    if ([channel hasUnreadMessages] || [channel mentionCount] > 0) return YES;
    NSEnumerator *enumerator = [[channel children] objectEnumerator];
    DLChannel *child;
    while (child = [enumerator nextObject]) {
        if ([self channelOrChildrenHaveUnread:child]) return YES;
    }
    return NO;
}

// Menus follow the official client's order for text channels, categories and
// direct messages, limited to actions this client performs.
-(void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    NSInteger row = [(DLChannelOutlineView *)outlineView menuRow];
    DLChannel *channel = row >= 0 ? [outlineView itemAtRow:row] : nil;
    if (!channel) return;
    BOOL isCategory = [channel type] == ChannelTypeHeader;
    NSMenuItem *markRead = [self channelMenuItem:@"Mark As Read" action:@selector(markChannelAsRead:) channel:channel];
    [markRead setEnabled:[self channelOrChildrenHaveUnread:channel]];
    [menu addItem:markRead];
    [menu addItem:[NSMenuItem separatorItem]];
    if (isCategory) {
        BOOL expanded = [outlineView isItemExpanded:channel];
        [menu addItem:[self channelMenuItem:(expanded ? @"Collapse Category" : @"Expand Category")
                                     action:@selector(toggleCategory:) channel:channel]];
        [menu addItem:[self channelMenuItem:@"Collapse All Categories" action:@selector(collapseAllCategories:) channel:channel]];
    } else {
        [menu addItem:[self channelMenuItem:@"Copy Link" action:@selector(copyChannelLink:) channel:channel]];
    }
    BOOL isVoice = [channel type] == ChannelTypeVoice || [channel type] == ChannelTypeStageVoice;
    if (isVoice && [DLVoiceManager isAvailable]) {
        DLVoiceManager *voice = [DLVoiceManager sharedManager];
        BOOL here = [voice state] != DLVoiceStateIdle && [[voice channel] isEqual:channel];
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:[self channelMenuItem:(here ? @"Disconnect" : @"Join Voice")
                                     action:(here ? @selector(leaveVoice:) : @selector(joinVoice:)) channel:channel]];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    [self addMuteItemForChannel:channel toMenu:menu];
    if ([[DLPreferencesHandler sharedInstance] developerMode]) {
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:[self channelMenuItem:(isCategory ? @"Copy Category ID" : @"Copy Channel ID")
                                     action:@selector(copyChannelID:) channel:channel]];
    }
}

// "Mute Channel" opens the official duration submenu; a muted channel offers
// "Unmute Channel" instead.
-(void)addMuteItemForChannel:(DLChannel *)channel toMenu:(NSMenu *)menu {
    BOOL isCategory = [channel type] == ChannelTypeHeader;
    BOOL isDirect = [channel isKindOfClass:[DLDirectMessageChannel class]] ||
                    [channel type] == ChannelTypeDM || [channel type] == ChannelTypeGroup;
    NSString *noun = isCategory ? @"Category" : (isDirect ? @"Conversation" : @"Channel");
    if ([[DLController sharedInstance] isChannelMutedItself:channel]) {
        NSMenuItem *unmute = [self channelMenuItem:[@"Unmute " stringByAppendingString:noun]
                                            action:@selector(unmuteChannel:) channel:channel];
        [menu addItem:unmute];
        return;
    }
    NSMenuItem *mute = [[[NSMenuItem alloc] initWithTitle:[@"Mute " stringByAppendingString:noun]
                                                   action:NULL keyEquivalent:@""] autorelease];
    NSMenu *durations = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    NSArray *titles = [NSArray arrayWithObjects:@"For 15 Minutes", @"For 1 Hour", @"For 3 Hours",
                       @"For 8 Hours", @"For 24 Hours", @"Until I turn it back on", nil];
    NSInteger seconds[] = { 15 * 60, 60 * 60, 3 * 60 * 60, 8 * 60 * 60, 24 * 60 * 60, 0 };
    NSUInteger index;
    for (index = 0; index < [titles count]; index++) {
        NSMenuItem *item = [self channelMenuItem:[titles objectAtIndex:index]
                                          action:@selector(muteChannel:) channel:channel];
        [item setTag:seconds[index]];
        [durations addItem:item];
    }
    [mute setSubmenu:durations];
    [menu addItem:mute];
}

-(void)joinVoice:(NSMenuItem *)sender {
    [[DLVoiceManager sharedManager] joinChannel:[sender representedObject]];
}

-(void)leaveVoice:(NSMenuItem *)sender {
    [[DLVoiceManager sharedManager] disconnect];
}

-(void)muteChannel:(NSMenuItem *)sender {
    [[DLController sharedInstance] setMuted:YES duration:(NSTimeInterval)[sender tag] forChannel:[sender representedObject]];
}

-(void)unmuteChannel:(NSMenuItem *)sender {
    [[DLController sharedInstance] setMuted:NO duration:0 forChannel:[sender representedObject]];
}

-(void)markChannelAsRead:(NSMenuItem *)sender {
    DLChannel *channel = [sender representedObject];
    if ([channel type] == ChannelTypeHeader) {
        NSEnumerator *enumerator = [[channel children] objectEnumerator];
        DLChannel *child;
        while (child = [enumerator nextObject]) [[DLController sharedInstance] markChannelAsRead:child];
    } else {
        [[DLController sharedInstance] markChannelAsRead:channel];
    }
    [outlineView setNeedsDisplay:YES];
}

-(void)toggleCategory:(NSMenuItem *)sender {
    id item = [sender representedObject];
    if ([outlineView isItemExpanded:item]) [outlineView collapseItem:item];
    else [outlineView expandItem:item];
}

-(void)collapseAllCategories:(NSMenuItem *)sender {
    NSEnumerator *enumerator = [channelItems objectEnumerator];
    DLChannel *item;
    while (item = [enumerator nextObject]) {
        if ([item type] == ChannelTypeHeader) [outlineView collapseItem:item];
    }
}

-(void)copyChannelLink:(NSMenuItem *)sender {
    DLChannel *channel = [sender representedObject];
    BOOL isDirect = [channel type] == ChannelTypeDM || [channel type] == ChannelTypeGroup;
    NSString *guild = isDirect ? @"@me"
        : ([channel respondsToSelector:@selector(serverID)] ? [[(DLServerChannel *)channel serverID] description] : @"@me");
    [DLUtil copyStringToPasteboard:[NSString stringWithFormat:@"https://discord.com/channels/%@/%@", guild, [channel channelID]]];
}

-(void)copyChannelID:(NSMenuItem *)sender {
    [DLUtil copyStringToPasteboard:[[[sender representedObject] channelID] description]];
}

// Categories are toggled by DLChannelOutlineView's mouseDown and never selected.
-(BOOL)outlineView:(NSOutlineView *)inOutlineView shouldSelectItem:(id)item {
    return [(DLChannel *)item type] != ChannelTypeHeader;
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

-(void)notificationSettingsDidChange:(NSNotification *)notification {
    [outlineView setNeedsDisplay:YES];
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
