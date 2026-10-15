//
//  DLStickerPickerController.m
//  Legacy Discord
//

#import "DLStickerPickerController.h"
#import "DLCompatibilityPopover.h"
#import "DLController.h"
#import "DLServer.h"
#import "DLUtil.h"
#import "DLMainWindowChromeControls.h"
#import "NSView+BGColor.h"
#import "NSScroller+BGColor.h"

static NSString *DLStickerPickerURL(NSDictionary *sticker) {
    id stickerID = [sticker objectForKey:@"id"];
    NSInteger formatType = [[sticker objectForKey:@"format_type"] integerValue];
    if (!stickerID || [stickerID isKindOfClass:[NSNull class]] || formatType == 3) {
        return nil;
    }
    if (formatType == 4) {
        return [NSString stringWithFormat:@"https://media.discordapp.net/stickers/%@.gif", stickerID];
    }
    return [NSString stringWithFormat:@"https://cdn.discordapp.com/stickers/%@.png", stickerID];
}

@interface DLStickerPickerController ()
-(void)showFromButton:(id)sender;
-(void)reloadGrid:(id)sender;
-(void)scheduleReload:(id)sender;
-(void)cacheDidUpdate:(NSNotification *)notification;
-(void)popoverDidClose:(NSNotification *)notification;
-(void)selectSticker:(id)sender;
-(void)showItems:(NSArray *)stickerItems;
@end

@implementation DLStickerPickerController

-(id)initWithButton:(NSButton *)inButton {
    self = [super init];
    if (self) {
        button = [inButton retain];
        [button setTarget:self];
        [button setAction:@selector(showFromButton:)];
    }
    return self;
}

-(void)setDelegate:(id<DLStickerPickerControllerDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)setEnabled:(BOOL)enabled {
    [button setEnabled:enabled];
}

-(void)showFromButton:(id)sender {
    [self showItems:[[[DLController sharedInstance] selectedServer] stickers]];
}

-(void)showItems:(NSArray *)stickerItems {
    [items release];
    items = [stickerItems copy];
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
        [[searchField cell] setPlaceholderString:@"Search stickers"];
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
        NSScroller_BGColor *stickerScroller = [[NSScroller_BGColor alloc] initWithFrame:NSZeroRect];
        [stickerScroller setBackgroundColor:[DLUtil nativeContentColor]];
        [scrollView setVerticalScroller:stickerScroller];
        [stickerScroller release];
        [pickerView addSubview:scrollView];
        [popoverController setView:pickerView];
        [pickerView release];
        [popover setContentViewController:popoverController];
        [popover setContentSize:NSMakeSize(300, 330)];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cacheDidUpdate:) name:HTTPCacheDataDidUpdateNotification object:nil];
    }
    [searchField setStringValue:@""];
    [self reloadGrid:nil];
    if ([button window]) {
        [popover showRelativeToRect:[button bounds] ofView:button preferredEdge:NSMaxYEdge];
    }
}

#if LEGACY_DISCORD_LOCAL_DEV
-(void)showOfflineReplayItems:(NSArray *)stickerItems {
    [self showItems:stickerItems];
}

-(BOOL)offlineReplayIsShown {
    return [popover isShown];
}

-(NSView *)offlineReplayContentView {
    return [popoverController view];
}
#endif

-(void)reloadGrid:(id)sender {
    NSView_BGColor *grid = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0, 0, 260, 1)];
    [grid setBackgroundColor:[DLUtil nativeContentColor]];
    NSString *query = [[[searchField stringValue] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *visible = [NSMutableArray array];
    NSEnumerator *enumerator = [items objectEnumerator];
    NSDictionary *sticker;
    while (sticker = [enumerator nextObject]) {
        if ([sticker objectForKey:@"available"] && ![[sticker objectForKey:@"available"] boolValue]) {
            continue;
        }
        NSString *name = [[sticker objectForKey:@"name"] isKindOfClass:[NSString class]] ? [sticker objectForKey:@"name"] : @"Sticker";
        NSString *description = [[sticker objectForKey:@"description"] isKindOfClass:[NSString class]] ? [sticker objectForKey:@"description"] : @"";
        NSString *tags = [[sticker objectForKey:@"tags"] isKindOfClass:[NSString class]] ? [sticker objectForKey:@"tags"] : @"";
        NSString *searchText = [[NSString stringWithFormat:@"%@ %@ %@", name, description, tags] lowercaseString];
        if ([query length] > 0 && [searchText rangeOfString:query].location == NSNotFound) {
            continue;
        }
        [visible addObject:sticker];
    }

    NSInteger columns = 3;
    CGFloat cellWidth = 84.0;
    CGFloat cellHeight = 94.0;
    NSInteger rows = MAX(1, ((NSInteger)[visible count] + columns - 1) / columns);
    [grid setFrameSize:NSMakeSize(260, rows * cellHeight + 8.0)];
    for (NSInteger index = 0; index < (NSInteger)[visible count]; index++) {
        sticker = [visible objectAtIndex:index];
        NSInteger column = index % columns;
        NSInteger row = index / columns;
        NSRect cellFrame = NSMakeRect(4.0 + column * cellWidth,
                                      NSHeight([grid bounds]) - (row + 1) * cellHeight,
                                      80.0, 90.0);
        NSView *cellView = [[NSView alloc] initWithFrame:cellFrame];
        NSString *name = [[sticker objectForKey:@"name"] isKindOfClass:[NSString class]] ? [sticker objectForKey:@"name"] : @"Sticker";
        NSString *stickerURL = DLStickerPickerURL(sticker);
        NSData *data = stickerURL ? [[HTTPCache sharedInstance] cachedDataForURL:stickerURL] : nil;
        NSButton *stickerButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 90)];
        [stickerButton setBordered:NO];
        [stickerButton setTitle:@""];
        [stickerButton setToolTip:name];
        [stickerButton setTarget:self];
        [stickerButton setAction:@selector(selectSticker:)];
        [[stickerButton cell] setRepresentedObject:sticker];
        if (data) {
            NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(8, 17, 64, 68)];
            [imageView setImageScaling:NSImageScaleProportionallyUpOrDown];
            [imageView setAnimates:([[sticker objectForKey:@"format_type"] integerValue] == 2 || [[sticker objectForKey:@"format_type"] integerValue] == 4)];
            [imageView setImage:[[[NSImage alloc] initWithData:data] autorelease]];
            [cellView addSubview:imageView];
            [imageView release];
            [stickerButton setTransparent:YES];
        } else if (stickerURL) {
            [stickerButton setEnabled:NO];
            [stickerButton setTitle:@"…"];
            if ([[HTTPCache sharedInstance] beginLoadingURL:stickerURL]) {
                AsyncHTTPGetRequest *request = [[AsyncHTTPGetRequest alloc] init];
                [request setDelegate:self];
                [request setUrl:stickerURL];
                [request setCached:YES];
                [request start];
            }
        } else {
            NSTextField *placeholder = [[NSTextField alloc] initWithFrame:NSMakeRect(5.0, 31.0, 70.0, 24.0)];
            [placeholder setBordered:NO];
            [placeholder setDrawsBackground:NO];
            [placeholder setEditable:NO];
            [placeholder setSelectable:NO];
            [placeholder setAlignment:NSCenterTextAlignment];
            [placeholder setFont:[NSFont boldSystemFontOfSize:11.0]];
            [placeholder setTextColor:[DLUtil nativeSecondaryTextColor]];
            [placeholder setStringValue:@"STICKER"];
            [cellView addSubview:placeholder];
            [placeholder release];
            [stickerButton setTransparent:YES];
        }
        NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(2, 1, 76, 16)];
        [nameField setBordered:NO];
        [nameField setDrawsBackground:NO];
        [nameField setEditable:NO];
        [nameField setSelectable:NO];
        [nameField setAlignment:NSCenterTextAlignment];
        [nameField setFont:[NSFont systemFontOfSize:10.0]];
        [nameField setTextColor:[DLUtil nativeSecondaryTextColor]];
        [[nameField cell] setLineBreakMode:NSLineBreakByTruncatingTail];
        [nameField setStringValue:name];
        [cellView addSubview:nameField];
        [nameField release];
        [cellView addSubview:stickerButton];
        [stickerButton release];
        [grid addSubview:cellView];
        [cellView release];
    }
    if ([visible count] == 0) {
        NSTextField *emptyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, NSHeight([grid bounds]) / 2.0 - 10.0, 235, 20)];
        [emptyLabel setBordered:NO];
        [emptyLabel setDrawsBackground:NO];
        [emptyLabel setEditable:NO];
        [emptyLabel setAlignment:NSCenterTextAlignment];
        [emptyLabel setTextColor:[DLUtil nativeSecondaryTextColor]];
        [emptyLabel setStringValue:([items count] ? @"No matching stickers" : @"No stickers available")];
        [grid addSubview:emptyLabel];
        [emptyLabel release];
    }
    [scrollView setDocumentView:grid];
    [grid release];
}

-(void)selectSticker:(id)sender {
    NSDictionary *sticker = [[sender cell] representedObject];
    if ([delegate respondsToSelector:@selector(stickerPickerController:didSelectSticker:)]) {
        [delegate stickerPickerController:self didSelectSticker:sticker];
    }
    [popover close];
}

-(void)scheduleReload:(id)sender {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadGrid:) object:nil];
    [self performSelector:@selector(reloadGrid:) withObject:nil afterDelay:0.15];
}

-(void)cacheDidUpdate:(NSNotification *)notification {
    if ([popover isShown]) {
        [self scheduleReload:nil];
    }
}

-(void)popoverDidClose:(NSNotification *)notification {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadGrid:) object:nil];
    if ([delegate respondsToSelector:@selector(stickerPickerControllerDidClose:)]) {
        [delegate stickerPickerControllerDidClose:self];
    }
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
    [items release];
    [searchField release];
    [scrollView release];
    [popoverController release];
    [popover release];
    [button setTarget:nil];
    [button release];
    [super dealloc];
}

@end
