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
@end


// Draw only the visible native button cells. The full catalog can be scrolled
// without allocating thousands of buttons or decoding every PNG at once.
@interface DLEmojiGridView : NSView_BGColor {
    NSArray *emojiItems;
    DLEmojiPickerController *picker;
    NSButtonCell *emojiCell;
    NSInteger focusedIndex;
}
-(id)initWithItems:(NSArray *)inItems picker:(DLEmojiPickerController *)inPicker;
@end

@implementation DLEmojiGridView
-(id)initWithItems:(NSArray *)inItems picker:(DLEmojiPickerController *)inPicker {
    NSInteger rows = MAX(1, ((NSInteger)[inItems count] + 6) / 7);
    self = [super initWithFrame:NSMakeRect(0, 0, 260, rows * 34 + 8)];
    if (self) {
        emojiItems = [inItems copy];
        picker = inPicker;
        focusedIndex = -1;
        [self setBackgroundColor:[DLUtil nativeContentColor]];
        emojiCell = [[NSButtonCell alloc] initTextCell:@""];
        [emojiCell setBezelStyle:NSShadowlessSquareBezelStyle];
        [emojiCell setButtonType:NSMomentaryPushInButton];
        [self addToolTipRect:[self bounds] owner:self userData:NULL];
    }
    return self;
}
-(BOOL)isFlipped { return YES; }
-(BOOL)acceptsFirstResponder { return YES; }
-(NSRect)rectForIndex:(NSUInteger)index {
    return NSMakeRect(6 + (index % 7) * 34, 4 + (index / 7) * 34, 30, 30);
}
-(NSInteger)indexAtPoint:(NSPoint)point {
    if (point.x < 6.0 || point.y < 4.0) return -1;
    NSInteger column = (NSInteger)((point.x - 6.0) / 34.0);
    NSInteger row = (NSInteger)((point.y - 4.0) / 34.0);
    NSInteger index = row * 7 + column;
    if (column >= 7 || index >= (NSInteger)[emojiItems count] ||
        !NSPointInRect(point, [self rectForIndex:index])) return -1;
    return index;
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
    NSUInteger first = MAX(0, (NSInteger)(NSMinY(dirtyRect) / 34.0)) * 7;
    NSUInteger end = MIN([emojiItems count], ((NSUInteger)(NSMaxY(dirtyRect) / 34.0) + 1) * 7);
    for (NSUInteger index = first; index < end; index++) {
        [self configureCellForIndex:index];
        [emojiCell drawWithFrame:[self rectForIndex:index] inView:self];
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
        NSView_BGColor *pickerView = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0, 0, 300, 330)];
        [pickerView setBackgroundColor:[DLUtil nativeContentColor]];
        searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(10, 296, 280, 24)];
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
        scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 10, 280, 278)];
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
        [popover setContentSize:NSMakeSize(300, 330)];
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

    DLEmojiGridView *grid = [[DLEmojiGridView alloc] initWithItems:visible picker:self];
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
    [super dealloc];
}

@end
