//
//  DLMessageSearchController.m
//  Legacy Discord
//

#import "DLMessageSearchController.h"
#import "DLLocalization.h"
#import "DLTwemojiRenderer.h"
#import "DLMainWindowChromeControls.h"
#import "DLController.h"
#import "DLMessage.h"
#import "DLServerMember.h"
#import "ChatScrollView.h"
#import "ChatItemViewController.h"
#import "NSView+BGColor.h"
#import "DLUtil.h"
#import "DLThemes.h"
#import "NSScroller+BGColor.h"

@interface DLSearchResultCell : NSCell {
    DLMessage *representedMessage;
    NSString *highlightTerm;
    BOOL hovered;
}
-(void)setRepresentedMessage:(DLMessage *)message highlight:(NSString *)term hovered:(BOOL)isHovered;
@end

@implementation DLSearchResultCell

-(void)setRepresentedMessage:(DLMessage *)message highlight:(NSString *)term hovered:(BOOL)isHovered {
    representedMessage = message;
    highlightTerm = term;
    hovered = isHovered;
}

// Official result card: avatar, role-coloured name and time on the first line,
// up to three lines of message text with the search words highlighted.
-(void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (!representedMessage) {
        return;
    }
    DLMessage *message = representedMessage;
    BOOL flipped = [controlView isFlipped];
    // Stay inside the visible part (the legacy scroller takes width).
    NSRect visibleFrame = NSIntersectionRect(cellFrame, [controlView visibleRect]);
    visibleFrame.origin.y = NSMinY(cellFrame);
    visibleFrame.size.height = NSHeight(cellFrame);
    NSRect cardRect = NSInsetRect(visibleFrame, 8.0, 4.0);
    NSColor *background = [DLUtil nativeContentColor];
    if (hovered) background = [DLThemes isGradientThemeActive] ? [DLUtil nativeHoverColor] : [background blendedColorWithFraction:0.05 ofColor:[NSColor whiteColor]];
    [background set];
    [[NSBezierPath bezierPathWithRoundedRect:cardRect xRadius:8.0 yRadius:8.0] fill];

    DLChannel *channel = [[DLController sharedInstance] loadedChannelWithID:[message channelID]];
    DLServer *server = [[DLController sharedInstance] loadedServerWithID:[channel serverID]];
    NSArray *roles = [message memberRoles];
    if (!roles) roles = [[server memberWithUserID:[[message author] userID]] roles];
    NSColor *nameColor = [DLUtil roleColorForRoleIDs:roles inServer:server];
    if (!nameColor) nameColor = [DLUtil nativePrimaryTextColor];

    NSMutableParagraphStyle *truncate = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [truncate setLineBreakMode:NSLineBreakByTruncatingTail];
    NSMutableParagraphStyle *wrapping = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [wrapping setLineBreakMode:NSLineBreakByWordWrapping];

    NSRect avatarRect = NSMakeRect(NSMinX(cardRect) + 12.0, flipped ? NSMinY(cardRect) + 12.0 : NSMaxY(cardRect) - 44.0, 32.0, 32.0);
    NSData *avatarData = [[message author] avatarImageData];
    NSImage *avatar = avatarData ? [[[NSImage alloc] initWithData:avatarData] autorelease] : nil;
    if (avatar) {
        [NSGraphicsContext saveGraphicsState];
        [[NSBezierPath bezierPathWithOvalInRect:avatarRect] addClip];
        [avatar drawInRect:avatarRect fromRect:NSZeroRect operation:NSCompositeSourceOver
                  fraction:1.0 respectFlipped:YES hints:nil];
        [NSGraphicsContext restoreGraphicsState];
    }

    CGFloat textX = NSMaxX(avatarRect) + 12.0;
    CGFloat textWidth = NSMaxX(cardRect) - 12.0 - textX;
    NSString *author = [[message author] globalName] ? [[message author] globalName] : [[message author] username];
    NSMutableAttributedString *header = [[[NSMutableAttributedString alloc] initWithString:(author ? author : @"")
        attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont boldSystemFontOfSize:13.0], NSFontAttributeName,
                    nameColor, NSForegroundColorAttributeName, truncate, NSParagraphStyleAttributeName, nil]] autorelease];
    [header appendAttributedString:[[[NSAttributedString alloc] initWithString:
        [@"  " stringByAppendingString:[DLUtil discordTimestampStringForDate:[message timestamp]]]
        attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:11.0], NSFontAttributeName,
                    [DLUtil nativeSecondaryTextColor], NSForegroundColorAttributeName, truncate, NSParagraphStyleAttributeName, nil]] autorelease]];
    [DLTwemojiRenderer replaceEmojiInAttributedString:header size:13.0 excludingAttribute:nil recordingAttribute:nil cursorLocation:NULL];
    CGFloat headerY = flipped ? NSMinY(cardRect) + 10.0 : NSMaxY(cardRect) - 28.0;
    [header drawInRect:NSMakeRect(textX, headerY, textWidth, 18.0)];

    NSString *contentText = [message content] ? [message content] : @"";
    if (![contentText length] && [[message attachments] count]) contentText = DLLocalizedString(@"Sent an attachment");
    NSMutableAttributedString *body = [[[NSMutableAttributedString alloc] initWithString:contentText
        attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:13.0], NSFontAttributeName,
                    [DLUtil nativePrimaryTextColor], NSForegroundColorAttributeName, wrapping, NSParagraphStyleAttributeName, nil]] autorelease];
    // Highlight each search word (from:/in: filters excluded).
    NSEnumerator *words = [[highlightTerm componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] objectEnumerator];
    NSString *word;
    while (word = [words nextObject]) {
        if ([word length] < 1 || [word rangeOfString:@":"].location != NSNotFound) continue;
        NSRange searchRange = NSMakeRange(0, [contentText length]);
        while (searchRange.length > 0) {
            NSRange found = [contentText rangeOfString:word options:NSCaseInsensitiveSearch range:searchRange];
            if (found.location == NSNotFound) break;
            [body addAttribute:NSBackgroundColorAttributeName
                         value:[NSColor colorWithCalibratedRed:0.98 green:0.66 blue:0.10 alpha:0.35] range:found];
            [body addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:13.0] range:found];
            searchRange = NSMakeRange(NSMaxRange(found), [contentText length] - NSMaxRange(found));
        }
    }
    [DLTwemojiRenderer replaceEmojiInAttributedString:body size:13.0 excludingAttribute:nil recordingAttribute:nil cursorLocation:NULL];
    CGFloat bodyHeight = NSHeight(cardRect) - 40.0;
    CGFloat bodyY = flipped ? NSMinY(cardRect) + 30.0 : NSMinY(cardRect) + 8.0;
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(NSMakeRect(textX, bodyY, textWidth, bodyHeight));
    // In a flipped view the rect's origin is its top; otherwise draw from the
    // top of the area downwards by placing the origin at its top edge.
    if (flipped) {
        [body drawWithRect:NSMakeRect(textX, bodyY, textWidth, bodyHeight) options:NSStringDrawingUsesLineFragmentOrigin];
    } else {
        [body drawInRect:NSMakeRect(textX, bodyY, textWidth, bodyHeight)];
    }
    [NSGraphicsContext restoreGraphicsState];
}

@end

@interface DLMessageSearchController ()
-(void)installViews;
-(void)setVisible:(BOOL)shouldShow;
-(void)clearMessageSearchHighlight;
-(void)performMessageSearchAtOffset:(NSInteger)requestedOffset;
-(DLUser *)searchUserMatchingName:(NSString *)name inMembers:(NSArray *)members;
-(void)showNoSearchUserNamed:(NSString *)name;
-(void)updateSearchResultsForQuery:(NSString *)query;
-(void)jumpToSearchResultAtRow:(NSInteger)row;
-(void)animatedScrollToChatView:(ChatItemViewController *)item;
-(void)reloadSearchResultsTable;
-(void)loadVisibleSearchResultAvatars;
@end

@implementation DLMessageSearchController
-(id)initWithHostView:(NSView *)inHostView chatScrollView:(ChatScrollView *)inChatScrollView
         composerView:(NSView *)inComposerView searchField:(NSSearchField *)inSearchField {
    self = [super init];
    if (self) {
        hostView = [inHostView retain];
        chatScrollView = [inChatScrollView retain];
        composerView = [inComposerView retain];
        searchField = [inSearchField retain];
        [searchField setTarget:self];
        [searchField setAction:@selector(searchLoadedMessages:)];
        if (hostView) [self installViews];
    }
    return self;
}
-(void)setDelegate:(id<DLMessageSearchControllerDelegate>)inDelegate { delegate = inDelegate; }
-(void)attachToHostView:(NSView *)inHostView {
    if (hostView || !inHostView) return;
    hostView = [inHostView retain];
    [self installViews];
}
-(BOOL)isVisible { return visible; }
-(void)resetForChannelChange {
    [self close];
    lastResultIndex = -1;
}
-(void)clearHighlight { [self clearMessageSearchHighlight]; }
-(void)installViews {
    CGFloat paneWidth = 280.0;
    NSRect chatBounds = [hostView bounds];
    resultsPane = [[NSView_BGColor alloc] initWithFrame:
                         NSMakeRect(NSWidth(chatBounds) - paneWidth, 0.0, paneWidth, NSHeight(chatBounds) - 42.0)];
    [resultsPane setAutoresizingMask:NSViewMinXMargin | NSViewHeightSizable];
    [resultsPane setBackgroundColor:[DLUtil nativeSidebarColor]];
    [resultsPane setBottomBorderColor:[DLUtil nativeBorderColor]];

    titleField = [[NSTextField alloc] initWithFrame:NSMakeRect(12.0, NSHeight([resultsPane bounds]) - 31.0, 180.0, 19.0)];
    [titleField setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
    [titleField setBezeled:NO];
    [titleField setDrawsBackground:NO];
    [titleField setEditable:NO];
    [titleField setSelectable:NO];
    [titleField setFont:[NSFont boldSystemFontOfSize:13.0]];
    [titleField setTextColor:[DLUtil nativePrimaryTextColor]];
    [titleField setStringValue:DLLocalizedString(@"Search Results")];
    [resultsPane addSubview:titleField];

    NSButton *closeButton = [[[NSButton alloc] initWithFrame:NSMakeRect(paneWidth - 33.0, NSHeight([resultsPane bounds]) - 34.0, 24.0, 24.0)] autorelease];
    [closeButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [closeButton setBordered:NO];
    [closeButton setFont:[NSFont systemFontOfSize:17.0]];
    [closeButton setTitle:@"×"];
    [closeButton setToolTip:DLLocalizedString(@"Close search results")];
    [closeButton setTarget:self];
    [closeButton setAction:@selector(closeMessageSearchResults:)];
    [resultsPane addSubview:closeButton];

    countField = [[NSTextField alloc] initWithFrame:NSMakeRect(12.0, NSHeight([resultsPane bounds]) - 51.0, paneWidth - 24.0, 16.0)];
    [countField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [countField setBezeled:NO];
    [countField setDrawsBackground:NO];
    [countField setEditable:NO];
    [countField setSelectable:NO];
    [countField setFont:[NSFont systemFontOfSize:10.0]];
    [countField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [resultsPane addSubview:countField];

    emptyStateField = [[NSTextField alloc] initWithFrame:
                             NSMakeRect(20.0, NSMidY([resultsPane bounds]) - 36.0,
                                        paneWidth - 40.0, 72.0)];
    [emptyStateField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin];
    [emptyStateField setBezeled:NO];
    [emptyStateField setDrawsBackground:NO];
    [emptyStateField setEditable:NO];
    [emptyStateField setSelectable:NO];
    [emptyStateField setAlignment:NSCenterTextAlignment];
    [emptyStateField setFont:[NSFont boldSystemFontOfSize:16.0]];
    [emptyStateField setTextColor:[DLUtil nativePrimaryTextColor]];
    [[emptyStateField cell] setWraps:YES];
    [[emptyStateField cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [emptyStateField setHidden:YES];
    [resultsPane addSubview:emptyStateField];

    resultsScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 30.0, paneWidth, NSHeight([resultsPane bounds]) - 86.0)];
    [resultsScrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [resultsScrollView setBorderType:NSNoBorder];
    [resultsScrollView setHasVerticalScroller:YES];
    [resultsScrollView setDrawsBackground:YES];
    [resultsScrollView setBackgroundColor:[DLUtil nativeSidebarColor]];
    NSScroller_BGColor *resultsScrollViewScroller = [[[NSScroller_BGColor alloc] initWithFrame:NSZeroRect] autorelease];
    [resultsScrollViewScroller setBackgroundColor:[DLUtil nativeSidebarColor]];
    [resultsScrollView setVerticalScroller:resultsScrollViewScroller];

    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"searchResult"] autorelease];
    [column setWidth:paneWidth];
    [column setResizingMask:NSTableColumnAutoresizingMask];
    [column setDataCell:[[[DLSearchResultCell alloc] init] autorelease]];
    resultsTableView = [[DLContextTableView alloc] initWithFrame:[[resultsScrollView contentView] bounds]];
    [resultsTableView setFocusRingType:NSFocusRingTypeNone];
    [resultsScrollView setFocusRingType:NSFocusRingTypeNone];
    [resultsTableView addTableColumn:column];
    [resultsTableView setHeaderView:nil];
    [resultsTableView setDataSource:self];
    [resultsTableView setDelegate:self];
    [resultsTableView setRowHeight:96.0];
    [resultsTableView setTarget:self];
    [resultsTableView setAction:@selector(openClickedResult:)];
    [resultsTableView setIntercellSpacing:NSMakeSize(0.0, 0.0)];
    [resultsTableView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleNone];
    [resultsTableView setGridStyleMask:NSTableViewGridNone];
    // Set after the highlight style, which resets the background on 10.6.
    [resultsTableView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [resultsTableView setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
    [resultsScrollView setDocumentView:resultsTableView];
    [resultsPane addSubview:resultsScrollView];
    [emptyStateField removeFromSuperviewWithoutNeedingDisplay];
    [resultsPane addSubview:emptyStateField];

    previousButton = [[DLSecondaryButton alloc] initWithFrame:NSMakeRect(8.0, 4.0, 70.0, 24.0)];
    [previousButton setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
    [previousButton setTitle:DLLocalizedString(@"Back")];
    [previousButton setTarget:self];
    [previousButton setAction:@selector(showPreviousSearchPage:)];
    [previousButton setEnabled:NO];
    [resultsPane addSubview:previousButton];

    pageField = [[NSTextField alloc] initWithFrame:NSMakeRect(82.0, 7.0, paneWidth - 164.0, 17.0)];
    [pageField setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [pageField setBezeled:NO];
    [pageField setDrawsBackground:NO];
    [pageField setEditable:NO];
    [pageField setSelectable:NO];
    [pageField setAlignment:NSCenterTextAlignment];
    [pageField setFont:[NSFont systemFontOfSize:10.0]];
    [pageField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [resultsPane addSubview:pageField];

    nextButton = [[DLSecondaryButton alloc] initWithFrame:NSMakeRect(paneWidth - 78.0, 4.0, 70.0, 24.0)];
    [nextButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
    [nextButton setTitle:DLLocalizedString(@"Next")];
    [nextButton setTarget:self];
    [nextButton setAction:@selector(showNextSearchPage:)];
    [nextButton setEnabled:NO];
    [resultsPane addSubview:nextButton];

    [hostView addSubview:resultsPane];
    [resultsPane setHidden:YES];
    visible = NO;
    results = [[NSArray alloc] init];
    offset = 0;
    total = 0;
}

-(void)setVisible:(BOOL)shouldShow {
    if (visible == shouldShow) {
        return;
    }
    visible = shouldShow;
    if (shouldShow) [delegate messageSearchControllerWillShow:self];
    CGFloat widthChange = NSWidth([resultsPane frame]);
    NSRect chatFrame = [chatScrollView frame];
    NSRect entryFrame = [composerView frame];
    if (shouldShow) {
        chatFrame.size.width = MAX(180.0, chatFrame.size.width - widthChange);
        entryFrame.size.width = MAX(180.0, entryFrame.size.width - widthChange);
        [resultsPane setHidden:NO];
    } else {
        chatFrame.size.width += widthChange;
        entryFrame.size.width += widthChange;
        [resultsPane setHidden:YES];
    }
    [chatScrollView setFrame:chatFrame];
    [composerView setFrame:entryFrame];
    [chatScrollView screenResize];
}

-(void)close {
    [searchField setStringValue:@""];
    [results release];
    results = [[NSArray alloc] init];
    [resultsTableView reloadData];
    offset = 0;
    total = 0;
    [previousButton setEnabled:NO];
    [nextButton setEnabled:NO];
    [pageField setStringValue:@""];
    [emptyStateField setHidden:YES];
    [pendingAuthorName release];
    pendingAuthorName = nil;
    [titleField setStringValue:DLLocalizedString(@"Search Results")];
    [self clearMessageSearchHighlight];
    [self setVisible:NO];
    [delegate messageSearchControllerDidClose:self];
}

-(void)clearMessageSearchHighlight {
    [highlightedResult setSearchHighlighted:NO];
    highlightedResult = nil;
}

-(IBAction)searchLoadedMessages:(id)sender {
    [titleField setStringValue:DLLocalizedString(@"Search Results")];
    NSString *query = [[searchField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([query length] == 0) {
        [lastQuery release];
        lastQuery = nil;
        lastResultIndex = -1;
        [self clearMessageSearchHighlight];
        [searchField setToolTip:nil];
        [results release];
        results = [[NSArray alloc] init];
        [resultsTableView reloadData];
        offset = 0;
        total = 0;
        [previousButton setEnabled:NO];
        [nextButton setEnabled:NO];
        [pageField setStringValue:@""];
        [emptyStateField setHidden:YES];
        [self setVisible:NO];
        return;
    }

    if (![query isEqualToString:lastQuery]) {
        [lastQuery release];
        lastQuery = [query copy];
        lastResultIndex = -1;
        [pendingAuthorName release];
        pendingAuthorName = nil;
    }
    if ([query hasPrefix:@"@"]) {
        // Username lookup is retained for compatibility with the original client.
        // Discord's history endpoint requires an author ID rather than a display name.
        [self updateSearchResultsForQuery:query];
        offset = 0;
        total = [results count];
        [previousButton setEnabled:NO];
        [nextButton setEnabled:NO];
        [pageField setStringValue:@""];
    } else {
        [self performMessageSearchAtOffset:0];
    }
}

-(void)performMessageSearchAtOffset:(NSInteger)requestedOffset {
    NSString *query = lastQuery;
    DLChannel *channel = [[DLController sharedInstance] selectedChannel];
    if (!query || [query length] == 0 || !channel) {
        return;
    }
    NSString *authorID = nil;
    if ([query hasPrefix:@"from:"]) {
        NSRange separator = [query rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
        NSUInteger end = separator.location == NSNotFound ? [query length] : separator.location;
        NSString *authorName = end > 5 ? [query substringWithRange:NSMakeRange(5, end - 5)] : @"";
        if ([authorName length] == 0) {
            [self showNoSearchUserNamed:authorName];
            return;
        }
        NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        if ([authorName rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
            authorID = authorName;
        } else {
            DLServer *server = [[DLController sharedInstance] selectedServer];
            DLUser *matchedUser = nil;
            if ([server isEqual:[[DLController sharedInstance] myServerItem]]) {
                NSArray *recipientMatches = [channel recipientsWithUsernameContainingString:authorName];
                NSMutableArray *users = [NSMutableArray arrayWithArray:recipientMatches ? recipientMatches : [NSArray array]];
                if ([[[[DLController sharedInstance] myUser] globalName] rangeOfString:authorName options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    [users addObject:[[DLController sharedInstance] myUser]];
                }
                NSMutableArray *wrappedMembers = [NSMutableArray array];
                NSEnumerator *userEnumerator = [users objectEnumerator];
                DLUser *user;
                while (user = [userEnumerator nextObject]) {
                    DLServerMember *member = [[[DLServerMember alloc] init] autorelease];
                    [member setUser:user];
                    [wrappedMembers addObject:member];
                }
                matchedUser = [self searchUserMatchingName:authorName inMembers:wrappedMembers];
            } else {
                matchedUser = [self searchUserMatchingName:authorName inMembers:[server members]];
            }
            if (matchedUser) {
                authorID = [matchedUser userID];
            } else if (![server isEqual:[[DLController sharedInstance] myServerItem]]) {
                [pendingAuthorName release];
                pendingAuthorName = [authorName copy];
                pendingAuthorOffset = requestedOffset;
                [emptyStateField setHidden:YES];
                [countField setStringValue:[NSString stringWithFormat:DLLocalizedString(@"Finding %@…"), authorName]];
                [previousButton setEnabled:NO];
                [nextButton setEnabled:NO];
                [self setVisible:YES];
                [[DLController sharedInstance] queryServer:server forMembersContainingUsername:authorName];
                return;
            } else {
                [self showNoSearchUserNamed:authorName];
                return;
            }
        }
    }

    [self clearMessageSearchHighlight];
    [results release];
    results = [[NSArray alloc] init];
    [resultsTableView reloadData];
    [emptyStateField setHidden:YES];
    [countField setFont:[NSFont systemFontOfSize:10.0]];
    [countField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [countField setStringValue:DLLocalizedString(@"Searching message history…")];
    [previousButton setEnabled:NO];
    [nextButton setEnabled:NO];
    [pageField setStringValue:@""];
    [searchField setToolTip:nil];
    [self setVisible:YES];
    [[DLController sharedInstance] searchMessagesForChannel:channel
                                                     query:query
                                                  authorID:authorID
                                                    offset:MAX(0, requestedOffset)];
}

-(DLUser *)searchUserMatchingName:(NSString *)name inMembers:(NSArray *)members {
    DLUser *partialMatch = nil;
    NSEnumerator *enumerator = [members objectEnumerator];
    DLServerMember *member;
    while (member = [enumerator nextObject]) {
        DLUser *user = [member user];
        NSString *username = [user username] ? [user username] : @"";
        NSString *displayName = [user globalName] ? [user globalName] : username;
        if ([username caseInsensitiveCompare:name] == NSOrderedSame ||
            [displayName caseInsensitiveCompare:name] == NSOrderedSame) {
            return user;
        }
        if (!partialMatch &&
            ([username rangeOfString:name options:NSCaseInsensitiveSearch].location != NSNotFound ||
             [displayName rangeOfString:name options:NSCaseInsensitiveSearch].location != NSNotFound)) {
            partialMatch = user;
        }
    }
    return partialMatch;
}

-(void)showNoSearchUserNamed:(NSString *)name {
    [results release];
    results = [[NSArray alloc] init];
    [resultsTableView reloadData];
    [countField setFont:[NSFont systemFontOfSize:10.0]];
    [countField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [countField setStringValue:DLLocalizedString(@"No results")];
    [emptyStateField setStringValue:[name length] > 0 ?
     [NSString stringWithFormat:DLLocalizedString(@"No user named %@"), name] : DLLocalizedString(@"Enter a user after from:")];
    [emptyStateField setHidden:NO];
    [previousButton setEnabled:NO];
    [nextButton setEnabled:NO];
    [pageField setStringValue:@""];
    [self setVisible:YES];
}

-(IBAction)showPreviousSearchPage:(id)sender {
    if (offset >= 25) {
        [self performMessageSearchAtOffset:offset - 25];
    }
}

-(IBAction)showNextSearchPage:(id)sender {
    if (offset + 25 < total) {
        [self performMessageSearchAtOffset:offset + 25];
    }
}

-(void)updateSearchResultsForQuery:(NSString *)query {
    [self clearMessageSearchHighlight];
    [emptyStateField setHidden:YES];
    [countField setFont:[NSFont systemFontOfSize:10.0]];
    [countField setTextColor:[DLUtil nativeSecondaryTextColor]];

    NSString *authorQuery = nil;
    NSString *contentQuery = query;
    if ([query hasPrefix:@"@"]) {
        NSRange separatorRange = [query rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
        if (separatorRange.location == NSNotFound) {
            authorQuery = [query substringFromIndex:1];
            contentQuery = @"";
        } else {
            authorQuery = [query substringWithRange:NSMakeRange(1, separatorRange.location - 1)];
            contentQuery = [[query substringFromIndex:separatorRange.location + 1]
                            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
    }

    NSMutableArray *matchingResults = [NSMutableArray array];
    NSEnumerator *enumerator = [[chatScrollView content] objectEnumerator];
    ChatItemViewController *item;
    while (item = [enumerator nextObject]) {
        DLMessage *message = [item representedObject];
        NSString *authorName = [[message author] globalName] ? [[message author] globalName] : @"";
        NSString *username = [[message author] username] ? [[message author] username] : @"";
        NSString *messageContent = [message content] ? [message content] : @"";
        BOOL contentMatches = [contentQuery length] == 0 || [messageContent rangeOfString:contentQuery options:NSCaseInsensitiveSearch].location != NSNotFound;
        NSString *nameQuery = authorQuery ? authorQuery : query;
        BOOL authorMatches = ([authorName rangeOfString:nameQuery options:NSCaseInsensitiveSearch].location != NSNotFound ||
                              [username rangeOfString:nameQuery options:NSCaseInsensitiveSearch].location != NSNotFound);
        BOOL matches = authorQuery ? ([authorQuery length] > 0 && authorMatches && contentMatches)
                                   : (contentMatches || authorMatches);
        if (matches) {
            [matchingResults addObject:[item representedObject]];
        }
    }
    [results release];
    results = [[NSArray alloc] initWithArray:matchingResults];
    [countField setStringValue:[NSString stringWithFormat:DLLocalizedString(@"%ld result%@ in loaded messages"),
                                             (long)[results count],
                                             DLPluralSuffix([results count])]];
    [resultsTableView reloadData];
    [resultsTableView deselectAll:self];
    if ([results count] == 0) {
        [emptyStateField setStringValue:DLLocalizedString(@"We searched far and wide. Unfortunately, no results were found.")];
        [emptyStateField setHidden:NO];
    }
    [searchField setToolTip:[results count] == 0 ? DLLocalizedString(@"No matching loaded messages") : nil];
    [self setVisible:YES];
}

-(void)jumpToSearchResultAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)[results count]) {
        return;
    }
    DLMessage *selectedMessage = [results objectAtIndex:row];
    NSString *selectedMessageID = [[selectedMessage messageID] description];
    NSEnumerator *enumerator = [[chatScrollView content] objectEnumerator];
    ChatItemViewController *item;
    while (item = [enumerator nextObject]) {
        if ([[[[item representedObject] messageID] description] isEqualToString:selectedMessageID]) {
            [self clearMessageSearchHighlight];
            highlightedResult = item;
            [highlightedResult setSearchHighlighted:YES];
            [self animatedScrollToChatView:highlightedResult];
            return;
        }
    }

    DLChannel *targetChannel = [[DLController sharedInstance] loadedChannelWithID:[selectedMessage channelID]];
    if (!targetChannel) {
        [searchField setToolTip:DLLocalizedString(@"The result channel is unavailable")];
        NSBeep();
        return;
    }
    [searchField setToolTip:DLLocalizedString(@"Loading selected message…")];
    [[DLController sharedInstance] loadMessagesAroundMessage:selectedMessage
                                                   inChannel:targetChannel];
}

-(void)animatedScrollToChatView:(ChatItemViewController *)item {
    if (!item) {
        return;
    }
    NSClipView *clipView = [chatScrollView contentView];
    NSRect visibleBounds = [clipView bounds];
    NSRect itemFrame = [[item view] frame];
    CGFloat targetY = NSMidY(itemFrame) - NSHeight(visibleBounds) / 2.0;
    CGFloat maximumY = MAX(0.0, NSHeight([[chatScrollView documentView] frame]) - NSHeight(visibleBounds));
    targetY = MIN(maximumY, MAX(0.0, targetY));
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:0.22];
    [[[chatScrollView contentView] animator] setBoundsOrigin:NSMakePoint(visibleBounds.origin.x, targetY)];
    [NSAnimationContext endGrouping];
    [chatScrollView reflectScrolledClipView:clipView];
}

-(void)reloadSearchResultsTable {
    [resultsTableView reloadData];
}

-(void)loadVisibleSearchResultAvatars {
    NSInteger limit = MIN((NSInteger)[results count], 10);
    for (NSInteger index = 0; index < limit; index++) {
        DLMessage *message = [results objectAtIndex:index];
        [[message author] loadAvatarData];
    }
    [self performSelector:@selector(reloadSearchResultsTable) withObject:nil afterDelay:0.8];
    [self performSelector:@selector(reloadSearchResultsTable) withObject:nil afterDelay:2.0];
}

-(void)messageSearchResults:(NSArray *)messages totalResults:(NSInteger)inTotal offset:(NSInteger)inOffset forChannel:(DLChannel *)channel query:(NSString *)query {
    if (![[[DLController sharedInstance] selectedChannel] isEqual:channel] ||
        ![query isEqualToString:lastQuery]) {
        return;
    }
    [results release];
    results = [[NSArray alloc] initWithArray:messages];
    offset = inOffset;
    total = inTotal;
    [countField setFont:[NSFont systemFontOfSize:10.0]];
    [countField setTextColor:[DLUtil nativeSecondaryTextColor]];
    // Official header: "128 Results"; the count line names the channel.
    [titleField setStringValue:[NSString stringWithFormat:DLLocalizedString(@"%ld Result%@"), (long)total, DLPluralSuffix(total)]];
    [countField setStringValue:[channel name] ? [NSString stringWithFormat:DLLocalizedString(@"in #%@"), [channel name]] : @""];
    [resultsTableView reloadData];
    [resultsTableView deselectAll:self];
    [emptyStateField setStringValue:DLLocalizedString(@"No matching messages")];
    [emptyStateField setHidden:([messages count] != 0)];
    NSInteger pageCount = MAX(1, (total + 24) / 25);
    NSInteger currentPage = MIN(pageCount, offset / 25 + 1);
    [pageField setStringValue:[NSString stringWithFormat:@"%ld / %ld", (long)currentPage, (long)pageCount]];
    [previousButton setEnabled:(offset > 0)];
    [nextButton setEnabled:(offset + (NSInteger)[messages count] < total)];
    // Page controls only when there is more than one page, like the official panel.
    BOOL paged = pageCount > 1;
    [previousButton setHidden:!paged];
    [nextButton setHidden:!paged];
    [pageField setHidden:!paged];
    [searchField setToolTip:[messages count] == 0 ? DLLocalizedString(@"No matching messages") : nil];
    [self setVisible:YES];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadVisibleSearchResultAvatars) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadSearchResultsTable) object:nil];
    [self performSelector:@selector(loadVisibleSearchResultAvatars) withObject:nil afterDelay:0.35];
}



-(void)members:(NSArray *)members didUpdateForServer:(DLServer *)server {
    if (!pendingAuthorName || ![server isEqual:[[DLController sharedInstance] selectedServer]]) return;
    NSInteger requestedOffset = pendingAuthorOffset;
    DLUser *matchedUser = [self searchUserMatchingName:pendingAuthorName inMembers:members];
    NSString *unmatchedName = [pendingAuthorName copy];
    [pendingAuthorName release];
    pendingAuthorName = nil;
    if (matchedUser) [self performMessageSearchAtOffset:requestedOffset];
    else [self showNoSearchUserNamed:unmatchedName];
    [unmatchedName release];
}
-(void)didDisplayMessagesAroundID:(NSString *)messageID {
    [self clearMessageSearchHighlight];
    NSEnumerator *enumerator = [[chatScrollView content] objectEnumerator];
    ChatItemViewController *item;
    while (item = [enumerator nextObject]) {
        if ([[[[item representedObject] messageID] description] isEqualToString:messageID]) {
            highlightedResult = item;
            [highlightedResult setSearchHighlighted:YES];
            [self performSelector:@selector(animatedScrollToChatView:) withObject:item afterDelay:0.01];
            break;
        }
    }
    [searchField setToolTip:nil];
}
-(void)showPinnedMessagesLoading {
    [titleField setStringValue:DLLocalizedString(@"Pinned Messages")];
    [results release]; results = [[NSArray alloc] init];
    [resultsTableView reloadData];
    [countField setStringValue:DLLocalizedString(@"Loading pinned messages…")];
    [emptyStateField setHidden:YES];
    [previousButton setHidden:YES]; [nextButton setHidden:YES]; [pageField setHidden:YES];
    [self setVisible:YES];
}
-(void)showPinnedMessages:(NSArray *)messages {
    [results release]; results = [[NSArray alloc] initWithArray:messages];
    [resultsTableView reloadData]; [resultsTableView deselectAll:self];
    [countField setStringValue:[NSString stringWithFormat:DLLocalizedString(@"%ld pinned message%@"), (long)[messages count],
                                DLPluralSuffix([messages count])]];
    [emptyStateField setStringValue:DLLocalizedString(@"This channel doesn't have any pinned messages... yet.")];
    [emptyStateField setHidden:([messages count] != 0)];
    [self loadVisibleSearchResultAvatars];
}
-(void)showPinnedMessagesError { [countField setStringValue:DLLocalizedString(@"Unable to load pinned messages")]; }
-(void)applyCurrentTheme {
    [(NSView_BGColor *)resultsPane setBackgroundColor:[DLUtil nativeSidebarColor]];
    [(NSView_BGColor *)resultsPane setBottomBorderColor:[DLUtil nativeBorderColor]];
    [titleField setTextColor:[DLUtil nativePrimaryTextColor]];
    [countField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [emptyStateField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [resultsScrollView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [(NSScroller_BGColor *)[resultsScrollView verticalScroller] setBackgroundColor:[DLUtil nativeSidebarColor]];
    [resultsTableView setBackgroundColor:[DLUtil nativeSidebarColor]];
    [resultsTableView reloadData];
}
-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return [results count]; }
-(id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row { return [[results objectAtIndex:row] content]; }
-(void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if ([cell isKindOfClass:[DLSearchResultCell class]]) {
        BOOL pins = [[titleField stringValue] isEqualToString:@"Pinned Messages"];
        [(DLSearchResultCell *)cell setRepresentedMessage:[results objectAtIndex:row]
                                                highlight:(pins ? nil : lastQuery)
                                                  hovered:(row == [(DLContextTableView *)resultsTableView hoveredRow])];
    }
}
-(NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)column row:(NSInteger)row mouseLocation:(NSPoint)point {
    return nil;
}
// Clicking a card jumps to the message, like the official Jump action.
-(void)openClickedResult:(id)sender {
    NSInteger row = [resultsTableView clickedRow];
    if (row >= 0) [self jumpToSearchResultAtRow:row];
}
-(void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self clearMessageSearchHighlight];
    [resultsTableView setDelegate:nil]; [resultsTableView setDataSource:nil];
    [lastQuery release]; [pendingAuthorName release]; [results release];
    [titleField release]; [countField release]; [emptyStateField release];
    [previousButton release]; [nextButton release]; [pageField release];
    [resultsTableView release]; [resultsScrollView release]; [resultsPane release];
    [searchField release]; [composerView release]; [chatScrollView release]; [hostView release];
    [super dealloc];
}
@end
