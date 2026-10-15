//
//  DLServerNavigationController.m
//  Legacy Discord
//

#import "DLServerNavigationController.h"
#import "DLController.h"
#import "DLUtil.h"
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

    if (drawsSeparatorBefore) {
        [[NSColor colorWithCalibratedWhite:0.38 alpha:1.0] set];
        NSRectFill(NSMakeRect(NSMinX(cellFrame) + 17.0, NSMaxY(cellFrame) - 1.0,
                              NSWidth(cellFrame) - 34.0, 1.0));
    }

    NSRect iconRect = NSMakeRect(NSMidX(cellFrame) - 22.0, NSMidY(cellFrame) - 22.0, 44.0, 44.0);
    NSImage *sourceImage = [[[NSImage alloc] initWithData:[representedServer iconImageData]] autorelease];
    if (sourceImage) {
        CGFloat cornerRadius = selected ? 14.0 : 22.0;
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
    } else if ([representedServer hasUnreadMessages]) {
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

    tableView = [[NSTableView alloc] initWithFrame:[[scrollView contentView] bounds]];
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
    [scrollView setDocumentView:tableView];
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

-(NSString *)tableView:(NSTableView *)inTableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation {
    if (row >= 0 && row < (NSInteger)[serverItems count]) {
        return [[serverItems objectAtIndex:row] name];
    }
    return nil;
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
