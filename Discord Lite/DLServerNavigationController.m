//
//  DLServerNavigationController.m
//  Legacy Discord
//

#import "DLServerMenuController.h"
#import "DLDarkMenu.h"
#import "DLServerNavigationController.h"
#import "DLController.h"
#import "DLUtil.h"
#import "DLMainWindowChromeControls.h"
#import "DLPreferencesHandler.h"
#import "DynamicScrollView.h"

@interface DLServerTableCell : NSCell {
    DLServer *representedServer;
    BOOL drawsSeparatorBefore;
}
-(void)setRepresentedServer:(DLServer *)server;
-(void)setDrawsSeparatorBefore:(BOOL)drawSeparator;
@end

@implementation DLServerTableCell

-(void)setRepresentedServer:(DLServer *)server {
    representedServer = server;
}

-(void)setDrawsSeparatorBefore:(BOOL)drawSeparator {
    drawsSeparatorBefore = drawSeparator;
}

-(void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (!representedServer) return;
    NSInteger row = [(NSTableView *)controlView rowAtPoint:NSMakePoint(NSMidX(cellFrame), NSMidY(cellFrame))];
    BOOL selected = (row >= 0 && [[(NSTableView *)controlView selectedRowIndexes] containsIndex:(NSUInteger)row]);
    BOOL hovered = (row >= 0 && [controlView isKindOfClass:[DLContextTableView class]] &&
                    row == [(DLContextTableView *)controlView hoveredRow]);

    if (drawsSeparatorBefore) {
        [[NSColor colorWithCalibratedWhite:0.38 alpha:1.0] set];
        NSRectFill(NSMakeRect(NSMinX(cellFrame) + 17.0, NSMaxY(cellFrame) - 1.0,
                              NSWidth(cellFrame) - 34.0, 1.0));
    }

    NSRect iconRect = NSMakeRect(NSMidX(cellFrame) - 22.0, NSMidY(cellFrame) - 22.0, 44.0, 44.0);
    NSImage *sourceImage = [[[NSImage alloc] initWithData:[representedServer iconImageData]] autorelease];
    if (sourceImage) {
        // Circle at rest, rounded square when selected or hovered.
        CGFloat cornerRadius = (selected || hovered) ? 14.0 : 22.0;
        NSImage *roundedImage = [DLUtil imageResize:sourceImage newSize:iconRect.size cornerRadius:cornerRadius];
        [roundedImage drawInRect:iconRect
                       fromRect:NSZeroRect
                      operation:NSCompositeSourceOver
                       fraction:1.0
                 respectFlipped:YES
                          hints:nil];
    }

    if (selected) {
        [[NSColor whiteColor] set];
        NSBezierPath *selectedPath = [NSBezierPath bezierPathWithRoundedRect:
                                      NSMakeRect(NSMinX([controlView visibleRect]) - 4.0, NSMidY(cellFrame) - 20.0, 8.0, 40.0)
                                                                           xRadius:4.0 yRadius:4.0];
        [selectedPath fill];
    } else if (hovered) {
        [[NSColor whiteColor] set];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMinX([controlView visibleRect]) - 4.0, NSMidY(cellFrame) - 10.0, 8.0, 20.0)
                                         xRadius:4.0 yRadius:4.0] fill];
    } else if ([representedServer hasUnreadMessages] && ![[DLController existingInstance] isServerMuted:representedServer]) {
        [[NSColor whiteColor] set];
        NSBezierPath *unreadPath = [NSBezierPath bezierPathWithRoundedRect:
                                    NSMakeRect(NSMinX([controlView visibleRect]) - 4.0, NSMidY(cellFrame) - 4.0, 8.0, 8.0)
                                                                         xRadius:4.0 yRadius:4.0];
        [unreadPath fill];
    }

    NSInteger mentionCount = [representedServer mentionCount];
    if (mentionCount > 0) {
        NSString *badgeText = mentionCount > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)mentionCount];
        // Discord puts the mention badge at the icon's bottom-right corner,
        // cut out of the icon by a ring of the rail color.
        NSDictionary *measureAttributes = [NSDictionary dictionaryWithObject:[NSFont boldSystemFontOfSize:9.0] forKey:NSFontAttributeName];
        CGFloat badgeWidth = MAX(16.0, ceil([badgeText sizeWithAttributes:measureAttributes].width) + 8.0);
        BOOL flipped = [controlView isFlipped];
        NSRect badgeRect = NSMakeRect(NSMaxX(iconRect) - badgeWidth + 3.0,
                                      flipped ? NSMaxY(iconRect) - 13.0 : NSMinY(iconRect) - 3.0, badgeWidth, 16.0);
        [[DLUtil nativeServerRailColor] set];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(badgeRect, -3.0, -3.0) xRadius:11.0 yRadius:11.0] fill];
        [[NSColor colorWithCalibratedRed:0.949 green:0.247 blue:0.263 alpha:1.0] set];
        [[NSBezierPath bezierPathWithRoundedRect:badgeRect xRadius:8.0 yRadius:8.0] fill];

        NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSFont boldSystemFontOfSize:9.0], NSFontAttributeName,
                                    [NSColor whiteColor], NSForegroundColorAttributeName, nil];
        NSSize textSize = [badgeText sizeWithAttributes:attributes];
        NSPoint textPoint = NSMakePoint(NSMidX(badgeRect) - textSize.width / 2.0,
                                       NSMidY(badgeRect) - textSize.height / 2.0);
        [badgeText drawAtPoint:textPoint withAttributes:attributes];
    }
}

@end

@interface DLServerNavigationController ()
-(void)installTableView;
-(void)refreshTable;
@end

@implementation DLServerNavigationController

-(id)initWithScrollView:(DynamicScrollView *)inScrollView {
    self = [super init];
    if (self) {
        scrollView = [inScrollView retain];
        [self installTableView];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationSettingsDidChange:)
                                                     name:DLNotificationSettingsDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(hoveredRowDidChange:)
                                                     name:DLContextTableViewHoveredRowDidChangeNotification object:tableView];
        [[scrollView contentView] setPostsBoundsChangedNotifications:YES];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(railScrolled:)
                                                     name:NSViewBoundsDidChangeNotification object:[scrollView contentView]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(railScrolled:)
                                                     name:DLDarkMenuDidCloseNotification object:nil];
    }
    return self;
}

-(void)setDelegate:(id<DLServerNavigationControllerDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)installTableView {
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"server"] autorelease];
    [column setWidth:NSWidth([[scrollView contentView] bounds])];
    [column setResizingMask:NSTableColumnAutoresizingMask];
    [column setDataCell:[[[DLServerTableCell alloc] init] autorelease]];

    tableView = [[DLContextTableView alloc] initWithFrame:[[scrollView contentView] bounds]];
    [tableView addTableColumn:column];
    [tableView setHeaderView:nil];
    [tableView setDataSource:self];
    [tableView setDelegate:self];
    [tableView setRowHeight:58.0];
    [tableView setIntercellSpacing:NSMakeSize(0.0, 0.0)];
    [tableView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleNone];
    [tableView setAllowsMultipleSelection:NO];
    [tableView setAllowsEmptySelection:YES];
    [tableView setBackgroundColor:[DLUtil nativeServerRailColor]];
    [tableView setFocusRingType:NSFocusRingTypeNone];
    [tableView setGridStyleMask:NSTableViewGridNone];
    // Right-click menu, rebuilt for the clicked server in menuNeedsUpdate:.
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    [menu setDelegate:(id)self];
    [tableView setMenu:menu];
    [scrollView setDocumentView:tableView];
}

-(DLServer *)clickedServer {
    NSInteger row = [(DLContextTableView *)tableView menuRow];
    return (row >= 0 && row < (NSInteger)[serverItems count]) ? [serverItems objectAtIndex:row] : nil;
}

// The official server menu, built by DLServerMenuController.
-(void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    [menu setAutoenablesItems:NO];
    NSMenu *serverMenu = [[DLServerMenuController sharedController] contextMenuForServer:[self clickedServer]];
    NSArray *items = [[[serverMenu itemArray] copy] autorelease];
    NSEnumerator *enumerator = [items objectEnumerator];
    NSMenuItem *item;
    while (item = [enumerator nextObject]) {
        [serverMenu removeItem:item];
        [menu addItem:item];
    }
}

-(void)notificationSettingsDidChange:(NSNotification *)notification {
    [tableView setNeedsDisplay:YES];
}

-(void)displayServerItems:(NSArray *)items {
    [self displayServerItems:items
              selectedServer:[[DLController sharedInstance] selectedServer]
                    myServer:[[DLController sharedInstance] myServerItem]];
}

-(void)displayServerItems:(NSArray *)items selectedServer:(DLServer *)selectedServer myServer:(DLServer *)myServer {
    NSEnumerator *oldEnumerator = [serverItems objectEnumerator];
    DLServer *oldServer;
    while (oldServer = [oldEnumerator nextObject]) {
        [oldServer setDelegate:nil];
    }

    [serverItems release];
    serverItems = [items retain];
    NSEnumerator *enumerator = [serverItems objectEnumerator];
    DLServer *server;
    while (server = [enumerator nextObject]) {
        [server setDelegate:self];
    }
    [tableView reloadData];

    NSInteger selectedRow = selectedServer ? [serverItems indexOfObject:selectedServer] : NSNotFound;
    updatingSelection = YES;
    if (selectedRow != NSNotFound) {
        [tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow] byExtendingSelection:NO];
        [tableView scrollRowToVisible:selectedRow];
    } else {
        selectedRow = [serverItems indexOfObject:myServer];
        if (selectedRow != NSNotFound) {
            [tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow] byExtendingSelection:NO];
        } else {
            [tableView deselectAll:self];
        }
    }
    updatingSelection = NO;
    [delegate serverNavigationControllerDidFinishDisplayingItems:self];
    if (!selectedServer && selectedRow != NSNotFound) {
        [delegate serverNavigationController:self didSelectServer:[serverItems objectAtIndex:selectedRow]];
    }
}

-(void)applyCurrentTheme {
    [tableView setBackgroundColor:[DLUtil nativeServerRailColor]];
    [tableView reloadData];
}

-(NSInteger)numberOfRowsInTableView:(NSTableView *)inTableView {
    return [serverItems count];
}

-(id)tableView:(NSTableView *)inTableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    return [[serverItems objectAtIndex:row] name];
}

-(void)tableView:(NSTableView *)inTableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([cell isKindOfClass:[DLServerTableCell class]]) {
        [(DLServerTableCell *)cell setRepresentedServer:[serverItems objectAtIndex:row]];
        [(DLServerTableCell *)cell setDrawsSeparatorBefore:(row == 1)];
    }
}

// Official server name bubble beside the hovered icon.
-(void)hoveredRowDidChange:(NSNotification *)notification {
    NSInteger row = [(DLContextTableView *)tableView hoveredRow];
    if (row < 0 || row >= (NSInteger)[serverItems count] || [DLDarkMenu isShown]) {
        [DLTooltip hide];
        return;
    }
    DLServer *server = [serverItems objectAtIndex:row];
    NSString *name = [server isEqual:[[DLController sharedInstance] myServerItem]] ? @"Direct Messages" : [server name];
    NSRect rowRect = [tableView rectOfRow:row];
    NSRect iconRect = NSMakeRect(NSMidX(rowRect) - 22.0, NSMidY(rowRect) - 22.0, 44.0, 44.0);
    [DLTooltip showText:name rightOfRect:iconRect inView:tableView];
}

-(void)railScrolled:(NSNotification *)notification {
    [DLTooltip hide];
}

-(void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (updatingSelection || [notification object] != tableView) return;
    NSInteger row = [tableView selectedRow];
    if (row >= 0 && row < (NSInteger)[serverItems count]) {
        [delegate serverNavigationController:self didSelectServer:[serverItems objectAtIndex:row]];
    }
}

-(void)refreshTable {
    [tableView reloadData];
}

-(void)iconDidUpdateWithData:(NSData *)data {
    [self performSelectorOnMainThread:@selector(refreshTable) withObject:nil waitUntilDone:NO];
}

-(void)mentionCountDidUpdate {
    [self performSelectorOnMainThread:@selector(refreshTable) withObject:nil waitUntilDone:NO];
}

-(void)unreadStatusDidUpdate {
    [self performSelectorOnMainThread:@selector(refreshTable) withObject:nil waitUntilDone:NO];
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    delegate = nil;
    NSEnumerator *enumerator = [serverItems objectEnumerator];
    DLServer *server;
    while (server = [enumerator nextObject]) {
        [server setDelegate:nil];
    }
    [serverItems release];
    [tableView setDelegate:nil];
    [tableView setDataSource:nil];
    [tableView release];
    [scrollView release];
    [super dealloc];
}

@end
