//
//  DLEmojiPickerController.m
//  Legacy Discord
//

#import "DLEmojiPickerController.h"
#import "DLCompatibilityPopover.h"
#import "DLController.h"
#import "DLServer.h"
#import "DLUtil.h"
#import "DLMainWindowChromeControls.h"
#import "NSView+BGColor.h"
#import "ChatItemViewController.h"
#import "NSScroller+BGColor.h"
#import "DLTwemojiRenderer.h"

@interface DLEmojiPickerController ()
-(void)showFromButton:(id)sender;
-(void)showRelativeToView:(NSView *)anchorView;
-(void)presentItems:(NSArray *)pickerItems relativeToView:(NSView *)anchorView;
-(void)reloadGrid:(id)sender;
-(void)scheduleReload:(id)sender;
-(void)cacheDidUpdate:(NSNotification *)notification;
-(void)popoverDidClose:(NSNotification *)notification;
-(void)selectEmojiItem:(NSDictionary *)emoji;
-(NSImage *)imageForPickerItem:(NSDictionary *)emoji;
-(NSArray *)standardEmojiItems;
-(NSArray *)sectionsForItems:(NSArray *)visible;
-(void)rebuildCategoryBar;
@end


// Draw only the visible native button cells. The full catalog can be scrolled
// without allocating thousands of buttons or decoding every PNG at once.
// Sections ({title, start}) add Discord-style headers between emoji runs.
static const CGFloat DLEmojiCell = 34.0;
static const CGFloat DLEmojiHeaderHeight = 26.0;
static const NSInteger DLEmojiColumns = 7;

@interface DLEmojiGridView : NSView_BGColor {
    NSArray *emojiItems;
    DLEmojiPickerController *picker;
    NSButtonCell *emojiCell;
    NSInteger focusedIndex;
    NSMutableData *itemRects;
    NSMutableArray *headerTitles;
    NSMutableArray *headerTops;
}
-(id)initWithItems:(NSArray *)inItems sections:(NSArray *)sections picker:(DLEmojiPickerController *)inPicker;
-(CGFloat)topOfSection:(NSUInteger)section;
@end

@implementation DLEmojiGridView
-(id)initWithItems:(NSArray *)inItems sections:(NSArray *)sections picker:(DLEmojiPickerController *)inPicker {
    self = [super initWithFrame:NSMakeRect(0, 0, 6 + DLEmojiColumns * DLEmojiCell + 4, 100)];
    if (self) {
        emojiItems = [inItems copy];
        picker = inPicker;
        focusedIndex = -1;
        itemRects = [[NSMutableData alloc] initWithLength:sizeof(NSRect) * MAX((NSUInteger)1, [emojiItems count])];
        headerTitles = [[NSMutableArray alloc] init];
        headerTops = [[NSMutableArray alloc] init];
        NSRect *rects = (NSRect *)[itemRects mutableBytes];
        CGFloat y = 4.0;
        NSUInteger sectionIndex = 0;
        NSInteger column = 0;
        for (NSUInteger index = 0; index < [emojiItems count]; index++) {
            if (sectionIndex < [sections count] &&
                [[[sections objectAtIndex:sectionIndex] objectForKey:@"start"] unsignedIntegerValue] == index) {
                if (column != 0) { y += DLEmojiCell; column = 0; }
                [headerTitles addObject:[[sections objectAtIndex:sectionIndex] objectForKey:@"title"]];
                [headerTops addObject:[NSNumber numberWithDouble:y]];
                y += DLEmojiHeaderHeight;
                sectionIndex++;
            }
            rects[index] = NSMakeRect(6 + column * DLEmojiCell, y, 30, 30);
            column++;
            if (column == DLEmojiColumns) { column = 0; y += DLEmojiCell; }
        }
        if (column != 0) y += DLEmojiCell;
        [self setFrameSize:NSMakeSize(NSWidth([self frame]), y + 4.0)];
        [self setBackgroundColor:[DLUtil nativeContentColor]];
        emojiCell = [[NSButtonCell alloc] initTextCell:@""];
        [emojiCell setBezelStyle:NSShadowlessSquareBezelStyle];
        [emojiCell setButtonType:NSMomentaryPushInButton];
        // No Aqua square around each emoji, like the official picker.
        [emojiCell setBordered:NO];
        [self addToolTipRect:[self bounds] owner:self userData:NULL];
    }
    return self;
}
-(BOOL)isFlipped { return YES; }
-(BOOL)acceptsFirstResponder { return YES; }
-(CGFloat)topOfSection:(NSUInteger)section {
    return section < [headerTops count] ? [[headerTops objectAtIndex:section] doubleValue] : 0.0;
}
-(NSRect)rectForIndex:(NSUInteger)index {
    return ((NSRect *)[itemRects mutableBytes])[index];
}
-(NSInteger)indexAtPoint:(NSPoint)point {
    for (NSUInteger index = 0; index < [emojiItems count]; index++) {
        if (NSPointInRect(point, [self rectForIndex:index])) return (NSInteger)index;
    }
    return -1;
}
-(void)configureCellForIndex:(NSUInteger)index {
    NSImage *image = [picker imageForPickerItem:[emojiItems objectAtIndex:index]];
    [emojiCell setImage:image];
    [emojiCell setTitle:image ? @"" : @"…"];
    [emojiCell setImagePosition:image ? NSImageOnly : NSNoImage];
    [emojiCell setEnabled:image != nil];
    [emojiCell setHighlighted:NO];
    [emojiCell setShowsFirstResponder:(index == focusedIndex && [[self window] firstResponder] == self)];
}
-(void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSDictionary *headerAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSFont boldSystemFontOfSize:10.0], NSFontAttributeName,
                                      [DLUtil nativeSecondaryTextColor], NSForegroundColorAttributeName, nil];
    for (NSUInteger header = 0; header < [headerTitles count]; header++) {
        CGFloat top = [[headerTops objectAtIndex:header] doubleValue];
        NSRect headerRect = NSMakeRect(8.0, top + 7.0, NSWidth([self bounds]) - 16.0, 14.0);
        if (NSIntersectsRect(headerRect, dirtyRect)) {
            [[headerTitles objectAtIndex:header] drawInRect:headerRect withAttributes:headerAttributes];
        }
    }
    for (NSUInteger index = 0; index < [emojiItems count]; index++) {
        NSRect rect = [self rectForIndex:index];
        if (NSMinY(rect) > NSMaxY(dirtyRect)) break;
        if (!NSIntersectsRect(rect, dirtyRect)) continue;
        [self configureCellForIndex:index];
        [emojiCell drawWithFrame:rect inView:self];
    }
}
-(void)mouseDown:(NSEvent *)event {
    NSInteger index = [self indexAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
    if (index < 0) return;
    focusedIndex = index;
    [[self window] makeFirstResponder:self];
    [self configureCellForIndex:index];
    if ([emojiCell isEnabled] && [emojiCell trackMouse:event inRect:[self rectForIndex:index]
                                               ofView:self untilMouseUp:YES]) {
        [picker selectEmojiItem:[emojiItems objectAtIndex:index]];
    }
    [self setNeedsDisplay:YES];
}
-(void)keyDown:(NSEvent *)event {
    NSString *characters = [event charactersIgnoringModifiers];
    if (![characters length] || ![emojiItems count]) { [super keyDown:event]; return; }
    unichar key = [characters characterAtIndex:0];
    NSInteger index = MAX(0, focusedIndex);
    if (key == NSLeftArrowFunctionKey) index--;
    else if (key == NSRightArrowFunctionKey) index++;
    else if (key == NSUpArrowFunctionKey) index -= 7;
    else if (key == NSDownArrowFunctionKey) index += 7;
    else if (key == '\r' || key == ' ') {
        NSDictionary *item = [emojiItems objectAtIndex:index];
        if ([picker imageForPickerItem:item]) [picker selectEmojiItem:item];
        return;
    } else { [super keyDown:event]; return; }
    focusedIndex = MIN((NSInteger)[emojiItems count] - 1, MAX(0, index));
    [self scrollRectToVisible:[self rectForIndex:focusedIndex]];
    [self setNeedsDisplay:YES];
}
-(NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data {
    NSInteger index = [self indexAtPoint:point];
    if (index < 0) return nil;
    NSDictionary *emoji = [emojiItems objectAtIndex:index];
    return [emoji objectForKey:@"id"] ? [NSString stringWithFormat:@":%@:", [emoji objectForKey:@"name"]]
        : [DLTwemojiRenderer displayNameForEmoji:[emoji objectForKey:@"name"]];
}
-(void)dealloc {
    [emojiCell release];
    [emojiItems release];
    [itemRects release];
    [headerTitles release];
    [headerTops release];
    [super dealloc];
}
@end

@implementation DLEmojiPickerController

-(id)initWithButton:(NSButton *)inButton {
    self = [super init];
    if (self) {
        pickerImageCache = [[NSCache alloc] init];
        [pickerImageCache setCountLimit:128];
        button = [inButton retain];
        [button setTarget:self];
        [button setAction:@selector(showFromButton:)];
    }
    return self;
}

-(void)setDelegate:(id<DLEmojiPickerControllerDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)setEnabled:(BOOL)enabled {
    [button setEnabled:enabled];
}

-(void)showFromButton:(id)sender {
    [reactionChatView release];
    reactionChatView = nil;
    [self showRelativeToView:button];
}

#if LEGACY_DISCORD_LOCAL_DEV
-(void)showOfflineReplayPicker {
    [reactionChatView release];
    reactionChatView = nil;
    [self presentItems:[self standardEmojiItems] relativeToView:button];
}

-(BOOL)offlineReplayIsShown {
    return [popover isShown];
}

-(NSView *)offlineReplayContentView {
    return [popoverController view];
}
#endif

-(void)showReactionPickerForChatView:(ChatItemViewController *)chatView relativeToView:(NSView *)anchorView {
    [reactionChatView release];
    reactionChatView = [chatView retain];
    [self showRelativeToView:anchorView];
}

-(void)showRelativeToView:(NSView *)anchorView {
    NSMutableArray *pickerItems = [NSMutableArray array];
    if ([[[DLController sharedInstance] selectedServer] emojis]) {
        NSArray *customEmoji = [[[[DLController sharedInstance] selectedServer] emojis] sortedArrayUsingDescriptors:
            [NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(caseInsensitiveCompare:)]]];
        [pickerItems addObjectsFromArray:customEmoji];
    }
    [pickerItems addObjectsFromArray:[self standardEmojiItems]];
    [self presentItems:pickerItems relativeToView:anchorView];
}

-(void)presentItems:(NSArray *)pickerItems relativeToView:(NSView *)anchorView {
    [items release];
    items = [pickerItems copy];

    if (!popover) {
        popover = [[DLCompatibilityPopover alloc] init];
        [popover setBehavior:DLCompatibilityPopoverBehaviorTransient];
        [popover setDelegate:self];
        popoverController = [[NSViewController alloc] init];
        // Discord layout: category icons in a column on the left, search and
        // the sectioned grid on the right.
        NSView_BGColor *pickerView = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0, 0, 340, 360)];
        [pickerView setBackgroundColor:[DLUtil nativeContentColor]];
        NSView_BGColor *bar = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(0, 0, 44, 360)] autorelease];
        [bar setBackgroundColor:[DLUtil nativeServerRailColor]];
        [pickerView addSubview:bar];
        categoryBar = [bar retain];
        searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(52, 326, 278, 24)];
        DLDarkSearchFieldCell *searchCell = [[DLDarkSearchFieldCell alloc] initTextCell:@""];
        [searchCell setTextColor:[DLUtil nativePrimaryTextColor]];
        [searchCell setDrawsBackground:NO];
        [searchCell setBezeled:NO];
        [searchField setCell:searchCell];
        [searchField setEditable:YES];
        [searchField setSelectable:YES];
        [searchCell release];
        [[searchField cell] setPlaceholderString:@"Search emoji"];
        [searchField setBackgroundColor:[DLUtil nativeInputColor]];
        [searchField setTextColor:[DLUtil nativePrimaryTextColor]];
        [searchField setFocusRingType:NSFocusRingTypeNone];
        [searchField setTarget:self];
        [searchField setAction:@selector(reloadGrid:)];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scheduleReload:) name:NSControlTextDidChangeNotification object:searchField];
        [pickerView addSubview:searchField];
        scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(52, 8, 282, 310)];
        [scrollView setHasVerticalScroller:YES];
        [scrollView setBorderType:NSNoBorder];
        [scrollView setDrawsBackground:YES];
        [scrollView setBackgroundColor:[DLUtil nativeContentColor]];
        NSScroller_BGColor *emojiScroller = [[NSScroller_BGColor alloc] initWithFrame:NSZeroRect];
        [emojiScroller setBackgroundColor:[DLUtil nativeContentColor]];
        [scrollView setVerticalScroller:emojiScroller];
        [emojiScroller release];
        [pickerView addSubview:scrollView];
        [popoverController setView:pickerView];
        [pickerView release];
        [popover setContentViewController:popoverController];
        [popover setContentSize:NSMakeSize(340, 360)];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cacheDidUpdate:) name:HTTPCacheDataDidUpdateNotification object:nil];
    }

    [searchField setStringValue:@""];
    [self reloadGrid:nil];
    if (![anchorView window]) {
        anchorView = button;
    }
    if ([anchorView window]) {
        [popover showRelativeToRect:[anchorView bounds] ofView:anchorView preferredEdge:NSMaxYEdge];
    }
}

-(void)reloadGrid:(id)sender {
    NSString *query = [[[searchField stringValue] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    query = [query stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":"]];
    NSMutableArray *visible = [NSMutableArray array];
    NSEnumerator *enumerator = [items objectEnumerator];
    NSDictionary *emoji;
    while (emoji = [enumerator nextObject]) {
        NSString *name = [emoji objectForKey:@"name"];
        NSString *searchText = [emoji objectForKey:@"search"];
        BOOL nameMatches = name && [[name lowercaseString] rangeOfString:query].location != NSNotFound;
        BOOL aliasMatches = searchText && [[searchText lowercaseString] rangeOfString:query].location != NSNotFound;
        if (!name || ([query length] > 0 && !nameMatches && !aliasMatches)) {
            continue;
        }
        if ([emoji objectForKey:@"available"] && ![[emoji objectForKey:@"available"] boolValue]) {
            continue;
        }
        [visible addObject:emoji];
    }

    NSArray *sections = [query length] == 0 ? [self sectionsForItems:visible] : [NSArray array];
    [visibleSections release];
    visibleSections = [sections retain];
    [self rebuildCategoryBar];
    DLEmojiGridView *grid = [[DLEmojiGridView alloc] initWithItems:visible sections:sections picker:self];
    if ([visible count] == 0) {
        NSTextField *emptyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 8, 235, 18)];
        [emptyLabel setBordered:NO];
        [emptyLabel setDrawsBackground:NO];
        [emptyLabel setEditable:NO];
        [emptyLabel setAlignment:NSCenterTextAlignment];
        [emptyLabel setTextColor:[DLUtil nativeSecondaryTextColor]];
        [emptyLabel setStringValue:@"No matching emoji"];
        [grid addSubview:emptyLabel];
        [emptyLabel release];
    }
    [scrollView setDocumentView:grid];
    [grid scrollPoint:NSZeroPoint];
    [grid release];
}

// Section boundaries follow Unicode's emoji order, which the bundled catalog
// keeps: each category starts at a known first emoji. Server emoji come first.
-(NSArray *)sectionsForItems:(NSArray *)visible {
    NSArray *starts = [NSArray arrayWithObjects:@"\U0001F600", @"\U0001F435", @"\U0001F347", @"\U0001F30D",
                       @"\U0001F383", @"\U0001F453", @"\U0001F3E7", @"\U0001F3C1", nil];
    NSArray *titles = [NSArray arrayWithObjects:@"PEOPLE", @"NATURE", @"FOOD", @"TRAVEL",
                       @"ACTIVITIES", @"OBJECTS", @"SYMBOLS", @"FLAGS", nil];
    NSMutableArray *sections = [NSMutableArray array];
    NSString *serverName = [[[DLController existingInstance] selectedServer] name];
    for (NSUInteger index = 0; index < [visible count]; index++) {
        NSDictionary *item = [visible objectAtIndex:index];
        if ([item objectForKey:@"id"]) {
            if ([sections count] == 0) {
                [sections addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                    ([serverName length] ? [serverName uppercaseString] : @"SERVER EMOJI"), @"title",
                    [NSNumber numberWithUnsignedInteger:index], @"start", item, @"icon", nil]];
            }
            continue;
        }
        NSUInteger startIndex = [starts indexOfObject:[item objectForKey:@"name"]];
        if (startIndex != NSNotFound) {
            [sections addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                [titles objectAtIndex:startIndex], @"title",
                [NSNumber numberWithUnsignedInteger:index], @"start", item, @"icon", nil]];
        }
    }
    return sections;
}

-(void)rebuildCategoryBar {
    NSArray *old = [[[categoryBar subviews] copy] autorelease];
    for (NSView *view in old) [view removeFromSuperview];
    CGFloat y = NSHeight([categoryBar bounds]) - 40.0;
    for (NSUInteger index = 0; index < [visibleSections count]; index++) {
        NSDictionary *section = [visibleSections objectAtIndex:index];
        NSButton *categoryButton = [[[NSButton alloc] initWithFrame:NSMakeRect(6, y, 32, 32)] autorelease];
        [categoryButton setBordered:NO];
        [categoryButton setButtonType:NSMomentaryChangeButton];
        [categoryButton setImagePosition:NSImageOnly];
        NSImage *categoryImage = nil;
        if ([[section objectForKey:@"icon"] objectForKey:@"id"]) {
            // Server emoji use the server's icon, like the official picker.
            NSData *iconData = [[[DLController existingInstance] selectedServer] iconImageData];
            NSImage *serverIcon = iconData ? [[[NSImage alloc] initWithData:iconData] autorelease] : nil;
            if (serverIcon) categoryImage = [DLUtil imageResize:serverIcon newSize:NSMakeSize(24.0, 24.0) cornerRadius:8.0];
        }
        if (!categoryImage) categoryImage = [self imageForPickerItem:[section objectForKey:@"icon"]];
        [categoryButton setImage:categoryImage];
        [categoryButton setTitle:@""];
        [categoryButton setToolTip:[[section objectForKey:@"title"] capitalizedString]];
        [categoryButton setTag:index];
        [categoryButton setTarget:self];
        [categoryButton setAction:@selector(jumpToSection:)];
        [categoryBar addSubview:categoryButton];
        y -= 36.0;
    }
}

-(void)jumpToSection:(NSButton *)sender {
    DLEmojiGridView *grid = (DLEmojiGridView *)[scrollView documentView];
    if (![grid isKindOfClass:[DLEmojiGridView class]]) return;
    CGFloat top = [grid topOfSection:[sender tag]];
    CGFloat maximum = MAX(0.0, NSHeight([grid frame]) - NSHeight([[scrollView contentView] bounds]));
    [[scrollView contentView] scrollToPoint:NSMakePoint(0.0, MIN(top, maximum))];
    [scrollView reflectScrolledClipView:[scrollView contentView]];
}

-(NSImage *)imageForPickerItem:(NSDictionary *)emoji {
    NSString *emojiID = [emoji objectForKey:@"id"];
    if (!emojiID) return [DLTwemojiRenderer imageForEmoji:[emoji objectForKey:@"name"] size:24.0];
    NSString *url = [NSString stringWithFormat:@"https://cdn.discordapp.com/emojis/%@.%@?size=32&quality=lossless",
        emojiID, [[emoji objectForKey:@"animated"] boolValue] ? @"gif" : @"png"];
    NSImage *cachedImage = [pickerImageCache objectForKey:url];
    if (cachedImage) return cachedImage;
    NSData *data = [[HTTPCache sharedInstance] cachedDataForURL:url];
    if (data) {
        NSImage *image = [[[NSImage alloc] initWithData:data] autorelease];
        [image setSize:NSMakeSize(24, 24)];
        if (image) [pickerImageCache setObject:image forKey:url];
        return image;
    }
    if ([[HTTPCache sharedInstance] beginLoadingURL:url]) {
        AsyncHTTPGetRequest *request = [[AsyncHTTPGetRequest alloc] init];
        [request setDelegate:self];
        [request setUrl:url];
        [request setCached:YES];
        [request start];
    }
    return nil;
}

-(NSArray *)standardEmojiItems {
    return [DLTwemojiRenderer standardEmojiItems];
}

-(void)selectEmojiItem:(NSDictionary *)emoji {
    if (reactionChatView) {
        [reactionChatView toggleReactionWithEmoji:emoji];
        [reactionChatView release];
        reactionChatView = nil;
    } else if ([delegate respondsToSelector:@selector(emojiPickerController:didSelectEmoji:)]) {
        [delegate emojiPickerController:self didSelectEmoji:emoji];
    }
    [popover close];
}

-(void)scheduleReload:(id)sender {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadGrid:) object:nil];
    [self performSelector:@selector(reloadGrid:) withObject:nil afterDelay:0.15];
}

-(void)cacheDidUpdate:(NSNotification *)notification {
    if ([popover isShown]) {
        [[scrollView documentView] setNeedsDisplay:YES];
    }
}

-(void)popoverDidClose:(NSNotification *)notification {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadGrid:) object:nil];
    [reactionChatView release];
    reactionChatView = nil;
}

-(void)close {
    [popover close];
}

-(void)requestDidFinishLoading:(AsyncHTTPRequest *)request {
    if ([request result] != HTTPResultOK) {
        [[HTTPCache sharedInstance] endLoadingURL:[request url]];
    }
    [request release];
}

-(void)dealloc {
    delegate = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [reactionChatView release];
    [items release];
    [pickerImageCache release];
    [searchField release];
    [scrollView release];
    [popoverController release];
    [popover release];
    [button setTarget:nil];
    [button release];
    [categoryBar release];
    [visibleSections release];
    [super dealloc];
}

@end
