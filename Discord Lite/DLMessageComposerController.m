//
//  DLMessageComposerController.m
//  Legacy Discord
//

#import "DLMessageComposerController.h"
#import "DLLocalization.h"
#import "DLPreferencesHandler.h"
#import "DLMessageComposerControls.h"
#import "DLController.h"
#import "DLChannel.h"
#import "DLDirectMessageChannel.h"
#import "DLServer.h"
#import "DLServerMember.h"
#import "DLUser.h"
#import "DLMessage.h"
#import "DLAttachment.h"
#import "DLTextParser.h"
#import "DLTwemojiRenderer.h"
#import "DLUtil.h"
#import "PaddedTextView.h"
#import "ChatScrollView.h"
#import "ChatItemViewController.h"
#import "DynamicScrollView.h"
#import "HorizontalDynamicScrollView.h"
#import "NSView+BGColor.h"

static const NSTimeInterval DLComposerTypingSendInterval = 8.0;

@interface DLMessageComposerController ()
-(void)showPendingAttachmentView;
-(void)hidePendingAttachmentView;
-(void)showReplyView;
-(void)hideReplyView;
-(void)displayReferencedMessage:(DLMessage *)message;
-(NSString *)serializedContent;
-(void)showTagSelectionViewWithContent:(NSArray *)content;
-(void)hideTagSelectionView;
-(void)updateTextViewSizing;
-(void)updateEditorAfterTextChange;
-(void)updateTypingStatus;
-(void)updateTypingString;
-(BOOL)isEditingTag;
-(void)updatePendingAttachmentsWithFilePaths:(NSArray *)paths;
@end

// Settings > Chat > "Automatically convert emoticons": standalone :) and
// friends become emoji when sent, as in the official client. Messages with
// code are left alone.
static NSString *DLConvertEmoticons(NSString *text) {
    if (![text length] || [text rangeOfString:@"`"].location != NSNotFound) return text;
    static NSDictionary *emoticons = nil;
    if (!emoticons) {
        emoticons = [[NSDictionary alloc] initWithObjectsAndKeys:
            @"🙂", @":)", @"🙂", @":-)", @"🙁", @":(", @"🙁", @":-(",
            @"😃", @":D", @"😃", @":-D", @"😉", @";)", @"😉", @";-)",
            @"😛", @":P", @"😛", @":p", @"😛", @":-P", @"😮", @":O",
            @"😮", @":o", @"😐", @":|", @"😢", @":'(", @"❤️", @"<3",
            @"💔", @"</3", @"😎", @"B)", @"😠", @">:(", @"😕", @":/", nil];
    }
    NSMutableString *result = [NSMutableString stringWithCapacity:[text length]];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSUInteger length = [text length];
    NSUInteger location = 0;
    while (location < length) {
        NSRange space = [text rangeOfCharacterFromSet:whitespace options:0 range:NSMakeRange(location, length - location)];
        NSUInteger end = (space.location == NSNotFound) ? length : space.location;
        if (end > location) {
            NSString *token = [text substringWithRange:NSMakeRange(location, end - location)];
            NSString *emoji = [emoticons objectForKey:token];
            [result appendString:(emoji ? emoji : token)];
        }
        if (space.location == NSNotFound) break;
        [result appendString:[text substringWithRange:space]];
        location = NSMaxRange(space);
    }
    return result;
}

@implementation DLMessageComposerController

-(void)setDelegate:(id<DLMessageComposerControllerDelegate>)inDelegate {
    delegate = inDelegate;
}

-(id)initWithWindow:(NSWindow *)window
       containerView:(NSView_BGColor *)inContainerView
            textView:(PaddedTextView *)inTextView
      textScrollView:(NSScrollView *)inTextScrollView
      chatScrollView:(ChatScrollView *)inChatScrollView
pendingAttachmentsScrollView:(HorizontalDynamicScrollView *)inPendingAttachmentsScrollView
  tagSelectionScrollView:(DynamicScrollView *)inTagSelectionScrollView
           replyView:(NSView *)inReplyView
      replyTextField:(NSTextField *)inReplyTextField
typingStatusTextField:(NSTextField *)inTypingStatusTextField
        attachButton:(NSButton *)inAttachButton
        textScroller:(NSScroller_BGColor *)inTextScroller
tagSelectionScroller:(NSScroller_BGColor *)inTagSelectionScroller
pendingAttachmentScroller:(NSScroller_BGColor *)inPendingAttachmentScroller {
    self = [super init];
    if (self) {
        hostWindow = window;
        containerView = [inContainerView retain];
        textView = [inTextView retain];
        textScrollView = [inTextScrollView retain];
        chatScrollView = [inChatScrollView retain];
        pendingAttachmentsScrollView = [inPendingAttachmentsScrollView retain];
        tagSelectionScrollView = [inTagSelectionScrollView retain];
        replyView = [inReplyView retain];
        replyTextField = [inReplyTextField retain];
        typingStatusTextField = [inTypingStatusTextField retain];
        attachButton = [inAttachButton retain];
        textScroller = [inTextScroller retain];
        tagSelectionScroller = [inTagSelectionScroller retain];
        pendingAttachmentScroller = [inPendingAttachmentScroller retain];

        [containerView setBackgroundColor:[DLUtil nativeChromeColor]];
        [textView setBackgroundColor:[NSColor clearColor]];
        [textView setDrawsBackground:NO];
        [textView setTextColor:[DLUtil nativePrimaryTextColor]];
        [textView setInsertionPointColor:[DLUtil nativePrimaryTextColor]];
        [textScrollView setBorderType:NSNoBorder];
        [textScrollView setDrawsBackground:NO];
        [textScrollView setBackgroundColor:[NSColor clearColor]];
        [[textScrollView contentView] setDrawsBackground:NO];

        NSRect entryFrame = [textScrollView frame];
        entryFrame.origin.x += 6.0;
        entryFrame.size.width -= 62.0;
        [textScrollView setFrame:entryFrame];
        // Like Discord, the attach "+" sits inside the rounded input field.
        CGFloat backgroundLeft = MAX(4.0, NSMinX(entryFrame) - 10.0);
        if (attachButton && [attachButton superview] == containerView) {
            backgroundLeft = MAX(4.0, MIN(backgroundLeft, NSMinX([attachButton frame]) - 8.0));
        }
        NSRect backgroundFrame = NSMakeRect(backgroundLeft,
                                             MAX(4.0, NSMinY(entryFrame) - 8.0),
                                             NSWidth([containerView bounds]) - backgroundLeft - 7.0,
                                             NSHeight(entryFrame) + 16.0);
        backgroundView = [[DLMessageComposerBackgroundView alloc] initWithFrame:backgroundFrame];
        [backgroundView setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
        [containerView addSubview:backgroundView positioned:NSWindowBelow relativeTo:textScrollView];
        if (attachButton && [attachButton superview] == containerView) {
            [attachButton retain];
            [attachButton removeFromSuperview];
            [containerView addSubview:attachButton positioned:NSWindowAbove relativeTo:backgroundView];
            [attachButton release];
        }

        NSButton *stickerButton = [[DLStickerButton alloc] initWithFrame:NSMakeRect(NSWidth([containerView bounds]) - 63, 15, 28, 26)];
        [stickerButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
        [stickerButton setBordered:NO];
        [stickerButton setButtonType:NSMomentaryPushInButton];
        [stickerButton setTitle:@""];
        [stickerButton setToolTip:DLLocalizedString(@"Send sticker")];
        [stickerButton setEnabled:NO];
        [containerView addSubview:stickerButton];
        stickerPickerController = [[DLStickerPickerController alloc] initWithButton:stickerButton];
        [stickerPickerController setDelegate:self];
        [stickerButton release];

        NSButton *emojiButton = [[DLEmojiButton alloc] initWithFrame:NSMakeRect(NSWidth([containerView bounds]) - 35, 15, 28, 26)];
        [emojiButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
        [emojiButton setBordered:NO];
        [emojiButton setButtonType:NSMomentaryPushInButton];
        [emojiButton setTitle:@""];
        [emojiButton setToolTip:DLLocalizedString(@"Insert emoji")];
        [emojiButton setEnabled:NO];
        [containerView addSubview:emojiButton];
        emojiPickerController = [[DLEmojiPickerController alloc] initWithButton:emojiButton];
        [emojiPickerController setDelegate:self];
        [emojiButton release];

        [typingStatusTextField setTextColor:[DLUtil nativeSecondaryTextColor]];
        [replyTextField setTextColor:[DLUtil nativePrimaryTextColor]];
        [textView setSelectedTextAttributes:[NSDictionary dictionaryWithObjects:
            [NSArray arrayWithObjects:[DLUtil nativeSelectedTextColor], [DLTextParser DEFAULT_TEXT_HIGHLIGHT_COLOR], nil]
            forKeys:[NSArray arrayWithObjects:NSForegroundColorAttributeName, NSBackgroundColorAttributeName, nil]]];

        [textScroller setBackgroundColor:[textView backgroundColor]];
        [textScroller setNeedsDisplay:YES];
        [tagSelectionScroller setBackgroundColor:[tagSelectionScrollView backgroundColor]];
        [tagSelectionScroller setNeedsDisplay:YES];
        [pendingAttachmentScroller setBackgroundColor:[pendingAttachmentsScrollView backgroundColor]];
        [pendingAttachmentScroller setNeedsDisplay:YES];

        editingLocation = NSNotFound;
        tagIndex = NSNotFound;
        currentTextScrollHeight = [textScrollView frame].size.height;
        typingUsers = [[NSMutableArray alloc] init];
        messageEditor = [[DLMessageEditor alloc] init];
        [messageEditor setDelegate:self];
        [textView setDelegate:self];
        [chatScrollView setDelegate:self];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTextViewSizing) name:NSWindowDidResizeNotification object:nil];
    }
    return self;
}

-(void)prepareForOfflineReplay {
    offlineReplay = YES;
    offlineReplayStateValid = YES;
    [textView setString:@""];
    [textView setEditable:NO];
    [textView setSelectable:NO];
    [textView setToolTip:@"Offline replay: message input is disabled"];
    [textView setPlaceholderString:@"Message #replay"];
    [attachButton setEnabled:NO];
    [emojiPickerController setEnabled:NO];
    [stickerPickerController setEnabled:NO];
}

-(NSString *)placeholderForChannel:(DLChannel *)channel {
    NSString *name = [channel name];
    if (![name length]) return nil;
    BOOL isDirectMessage = [channel type] == ChannelTypeDM || [channel type] == ChannelTypeGroup;
    return [NSString stringWithFormat:(isDirectMessage ? DLLocalizedString(@"Message @%@") : DLLocalizedString(@"Message #%@")), name];
}

-(void)setEnabledForChannel:(DLChannel *)channel {
    offlineReplay = NO;
    BOOL enabled = channel && [channel type] != ChannelTypeForum && [channel type] != ChannelTypeMedia;
    [attachButton setEnabled:enabled];
    [emojiPickerController setEnabled:enabled];
    [textView setEditable:enabled];
    [textView setPlaceholderString:[self placeholderForChannel:(enabled ? channel : nil)]];
    if (!enabled) {
        [stickerPickerController setEnabled:NO];
        return;
    }
    BOOL isDirectMessage = [channel type] == ChannelTypeDM || [channel type] == ChannelTypeGroup;
    BOOL hasStickers = [[[[DLController sharedInstance] selectedServer] stickers] count] > 0;
    [stickerPickerController setEnabled:(!isDirectMessage && hasStickers)];
}

-(void)reset {
    isTyping = NO;
    [typingTimer invalidate];
    typingTimer = nil;
    [typingUsers removeAllObjects];
    [self updateTypingString];
    [self hidePendingAttachmentView];
    [self hideReplyView];
    [messageEditor clear];
    [textView setString:@""];
    [self updateEditorAfterTextChange];
}

-(void)applyCurrentTheme {
    [containerView setBackgroundColor:[DLUtil nativeChromeColor]];
    [textView setTextColor:[DLUtil nativePrimaryTextColor]];
    [textView setInsertionPointColor:[DLUtil nativePrimaryTextColor]];
    [typingStatusTextField setTextColor:[DLUtil nativeSecondaryTextColor]];
    [replyTextField setTextColor:[DLUtil nativePrimaryTextColor]];
    [textScroller setBackgroundColor:[textView backgroundColor]];
    [tagSelectionScroller setBackgroundColor:[tagSelectionScrollView backgroundColor]];
    [pendingAttachmentScroller setBackgroundColor:[pendingAttachmentsScrollView backgroundColor]];
    [backgroundView setNeedsDisplay:YES];
    [containerView setNeedsDisplay:YES];
}

-(void)showFileOpenDialog {
    NSOpenPanel *openDialog = [NSOpenPanel openPanel];
    [openDialog setCanChooseFiles:YES];
    [openDialog setAllowsMultipleSelection:YES];
    [openDialog setCanChooseDirectories:NO];
    if ([openDialog runModalForDirectory:nil file:nil] == NSOKButton) {
        [self updatePendingAttachmentsWithFilePaths:[openDialog filenames]];
    }
}

-(void)showPendingAttachmentView {
    if (![pendingAttachmentsScrollView superview]) {
        NSRect attachmentsViewFrame = [pendingAttachmentsScrollView frame];
        attachmentsViewFrame.origin.y = [containerView frame].size.height;
        attachmentsViewFrame.size.width = [containerView frame].size.width;
        [pendingAttachmentsScrollView setFrame:attachmentsViewFrame];
        NSRect chatViewFrame = [chatScrollView frame];
        chatViewFrame.size.height -= attachmentsViewFrame.size.height;
        chatViewFrame.origin.y += attachmentsViewFrame.size.height;
        [chatScrollView setFrame:chatViewFrame];
        NSRect containerFrame = [containerView frame];
        containerFrame.size.height += attachmentsViewFrame.size.height;
        [containerView setFrame:containerFrame];
        [containerView addSubview:pendingAttachmentsScrollView];
        [containerView setNeedsDisplay:YES];
        [chatScrollView setNeedsDisplay:YES];
        if ([replyView superview]) {
            NSRect replyFrame = [replyView frame];
            replyFrame.origin.y -= attachmentsViewFrame.size.height;
            [replyView setFrame:replyFrame];
            [replyView setNeedsDisplay:YES];
        }
    }
}

-(void)hidePendingAttachmentView {
    if ([pendingAttachmentsScrollView superview]) {
        [pendingAttachmentsScrollView setContent:[NSArray array]];
        NSRect attachmentsViewFrame = [pendingAttachmentsScrollView frame];
        NSRect chatViewFrame = [chatScrollView frame];
        chatViewFrame.size.height += attachmentsViewFrame.size.height;
        chatViewFrame.origin.y -= attachmentsViewFrame.size.height;
        [chatScrollView setFrame:chatViewFrame];
        NSRect containerFrame = [containerView frame];
        containerFrame.size.height -= attachmentsViewFrame.size.height;
        [containerView setFrame:containerFrame];
        [pendingAttachmentsScrollView removeFromSuperview];
        [containerView setNeedsDisplay:YES];
        [chatScrollView setNeedsDisplay:YES];
        if ([replyView superview]) {
            NSRect replyFrame = [replyView frame];
            replyFrame.origin.y += attachmentsViewFrame.size.height;
            [replyView setFrame:replyFrame];
            [replyView setNeedsDisplay:YES];
        }
    }
}

-(void)showReplyView {
    if (![replyView superview]) {
        NSRect replyFrame = [replyView frame];
        replyFrame.origin.y = [textScrollView frame].size.height + 35;
        replyFrame.size.width = [containerView frame].size.width;
        [replyView setFrame:replyFrame];
        NSRect chatViewFrame = [chatScrollView frame];
        chatViewFrame.size.height -= replyFrame.size.height;
        chatViewFrame.origin.y += replyFrame.size.height;
        [chatScrollView setFrame:chatViewFrame];
        NSRect containerFrame = [containerView frame];
        containerFrame.size.height += replyFrame.size.height;
        [containerView setFrame:containerFrame];
        [containerView addSubview:replyView];
        [containerView setNeedsDisplay:YES];
        [chatScrollView setNeedsDisplay:YES];
    }
}

-(void)hideReplyView {
    if ([replyView superview]) {
        NSRect replyFrame = [replyView frame];
        NSRect chatViewFrame = [chatScrollView frame];
        chatViewFrame.size.height += replyFrame.size.height;
        chatViewFrame.origin.y -= replyFrame.size.height;
        [chatScrollView setFrame:chatViewFrame];
        NSRect containerFrame = [containerView frame];
        containerFrame.size.height -= replyFrame.size.height;
        [containerView setFrame:containerFrame];
        [replyView removeFromSuperview];
        [containerView setNeedsDisplay:YES];
        [chatScrollView setNeedsDisplay:YES];
    }
}

-(NSString *)serializedContent {
    NSAttributedString *content = [textView textStorage];
    NSMutableString *serialized = [NSMutableString string];
    NSUInteger location = 0;
    while (location < [content length]) {
        NSRange effectiveRange;
        NSDictionary *attributes = [content attributesAtIndex:location effectiveRange:&effectiveRange];
        NSString *customEmoji = [attributes objectForKey:@kCustomEmojiAttribute];
        NSString *unicodeEmoji = [attributes objectForKey:@kUnicodeEmojiAttribute];
        NSString *mentionUserID = [attributes objectForKey:@kMentionUserIDAttribute];
        if (customEmoji) {
            [serialized appendString:customEmoji];
        } else if (unicodeEmoji) {
            [serialized appendString:unicodeEmoji];
        } else if (mentionUserID) {
            [serialized appendFormat:@"<@%@>", mentionUserID];
        } else {
            [serialized appendString:[[content string] substringWithRange:effectiveRange]];
        }
        location = NSMaxRange(effectiveRange);
    }
    return serialized;
}

-(void)showTagSelectionViewWithContent:(NSArray *)content {
    NSInteger limit = 10;
    NSInteger startIndex = 0;
    if ([content count] > limit) {
        startIndex = [content count] - limit;
    }
    if ([content count] > 0) {
        NSView *windowContentView = [hostWindow contentView];
        NSRect containerRect = [containerView convertRect:[containerView bounds]
                                                    toView:windowContentView];
        NSRect frame = [tagSelectionScrollView frame];
        frame.size.width = containerRect.size.width;
        frame.origin.y = NSMaxY(containerRect);
        frame.origin.x = NSMinX(containerRect);
        [tagSelectionScrollView setFrame:frame];
        if (![tagSelectionScrollView superview]) {
            [[hostWindow contentView] addSubview:tagSelectionScrollView];
        }
        NSMutableArray *views = [[NSMutableArray alloc] init];
        for (NSInteger index = startIndex; index < (NSInteger)[content count]; index++) {
            TagSelectionViewController *view = [[TagSelectionViewController alloc] initWithNibNamed:@"TagSelectionViewController" bundle:nil];
            if (index == (NSInteger)[content count] - 1) {
                [view setSelected:YES];
            }
            [view setRepresentedObject:[content objectAtIndex:index]];
            [view setDelegate:self];
            [views addObject:view];
            [view release];
        }
        [tagSelectionScrollView setContent:views];
        [views release];
        CGFloat newHeight = [[tagSelectionScrollView documentView] frame].size.height + 2;
        if (newHeight > 300) {
            newHeight = 300;
        }
        frame = [tagSelectionScrollView frame];
        frame.size.height = newHeight;
        [tagSelectionScrollView setFrame:frame];
    } else {
        [tagSelectionScrollView removeFromSuperview];
    }
    [chatScrollView setNeedsDisplay:YES];
    [tagSelectionScrollView setNeedsDisplay:YES];
}

-(void)hideTagSelectionView {
    if ([tagSelectionScrollView superview]) {
        [tagSelectionScrollView removeFromSuperview];
        [chatScrollView setNeedsDisplay:YES];
        [tagSelectionScrollView setNeedsDisplay:YES];
    }
}

-(void)updateTextViewSizing {
    [[textView layoutManager] glyphRangeForTextContainer:[textView textContainer]];
    NSRect textFrame = [[textView layoutManager] usedRectForTextContainer:[textView textContainer]];
    if (textFrame.size.height <= 126) {
        NSRect scrollViewFrame = [textScrollView frame];
        scrollViewFrame.size.height = textFrame.size.height + 8;
        [textScrollView setFrame:scrollViewFrame];
        NSRect backgroundFrame = [backgroundView frame];
        backgroundFrame.size.height = scrollViewFrame.size.height + 16.0;
        [backgroundView setFrame:backgroundFrame];
        CGFloat change = scrollViewFrame.size.height - currentTextScrollHeight;
        if (change) {
            NSRect containerFrame = [containerView frame];
            containerFrame.size.height += change;
            [containerView setFrame:containerFrame];
            NSRect chatViewFrame = [chatScrollView frame];
            chatViewFrame.size.height -= change;
            chatViewFrame.origin.y += change;
            [chatScrollView setFrame:chatViewFrame];
            [chatScrollView setNeedsDisplay:YES];
            [containerView setNeedsDisplay:YES];
        }
        currentTextScrollHeight = scrollViewFrame.size.height;
    }
}

-(void)updateTypingStatus {
    if (isTyping) {
        isTyping = NO;
        [typingTimer invalidate];
        typingTimer = nil;
    }
}

-(BOOL)isEditingTag {
    if (editingLocation == NSNotFound || editingLocation > (NSInteger)[[textView string] length]) {
        return NO;
    }
    NSString *textBeforeSelection = [[textView string] substringToIndex:editingLocation];
    tagIndex = [textBeforeSelection rangeOfString:@"@" options:NSBackwardsSearch].location;
    return (tagIndex != NSNotFound) && ([[textBeforeSelection substringFromIndex:tagIndex] rangeOfString:@" "].location == NSNotFound);
}

-(void)removeReferencedMessage {
    [messageEditor removeReferencedMessage];
    [self hideReplyView];
}

-(void)addReferencedMessage:(DLMessage *)message {
    if (![[[DLController sharedInstance] selectedServer] isEqual:[[DLController sharedInstance] myServerItem]]) {
        [message setServerID:[[[DLController sharedInstance] selectedServer] serverID]];
    }
    [self displayReferencedMessage:message];
}

-(void)displayReferencedMessage:(DLMessage *)message {
    [messageEditor setReferencedMessage:message];
    NSString *authorName = [[message author] globalName];
    NSString *baseString = [NSString stringWithFormat:DLLocalizedString(@"Replying to %@"), authorName];
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:baseString];
    [attributedString addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:13] range:[baseString rangeOfString:authorName]];
    [replyTextField setAttributedStringValue:attributedString];
    [attributedString release];
    [self showReplyView];
}

#if LEGACY_DISCORD_LOCAL_DEV
-(void)configureOfflineReplayStateNamed:(NSString *)stateName
                           replyMessage:(DLMessage *)replyMessage
                         candidateUsers:(NSArray *)candidateUsers
                        attachmentPaths:(NSArray *)attachmentPaths
                           stickerItems:(NSArray *)stickerItems {
    offlineReplayStateValid = YES;
    [textView setSelectable:YES];
    if ([stateName isEqualToString:@"composer-text"]) {
        [textView setString:@"A synthetic draft uses the production editor.\nThe second line verifies dynamic composer height."];
        [messageEditor setContent:[textView string]];
        [self updateTextViewSizing];
        offlineReplayStateValid = ([[textView string] rangeOfString:@"\n"].location != NSNotFound);
    } else if ([stateName isEqualToString:@"composer-reply"]) {
        [textView setString:@"A synthetic reply is ready to send."];
        [messageEditor setContent:[textView string]];
        [self updateTextViewSizing];
        if (replyMessage) [self displayReferencedMessage:replyMessage];
        offlineReplayStateValid = (replyMessage != nil && [replyView superview] != nil);
    } else if ([stateName isEqualToString:@"composer-attachment"]) {
        [textView setString:@"A bundled image is attached without network access."];
        [messageEditor setContent:[textView string]];
        [self updateTextViewSizing];
        if ([attachmentPaths count] > 0) [self updatePendingAttachmentsWithFilePaths:attachmentPaths];
        offlineReplayStateValid = ([[pendingAttachmentsScrollView content] count] > 0 &&
                                   [pendingAttachmentsScrollView superview] != nil);
    } else if ([stateName isEqualToString:@"composer-emoji"]) {
        [textView setEditable:YES];
        [textView setString:@"Emoji inserted through the production picker callback: "];
        [textView setSelectedRange:NSMakeRange([[textView string] length], 0)];
        [self focusInput];
        [self emojiPickerController:emojiPickerController
                     didSelectEmoji:[NSDictionary dictionaryWithObjectsAndKeys:
                                     @"✨", @"name", nil]];
        [textView setEditable:NO];
        offlineReplayStateValid = ([[textView string] rangeOfString:@"￼"].location != NSNotFound &&
                                   [[self serializedContent] rangeOfString:@"✨"].location != NSNotFound);
    } else if ([stateName isEqualToString:@"composer-mention"]) {
        [textView setString:@"@"];
        [messageEditor setContent:[textView string]];
        [self updateTextViewSizing];
        [self showTagSelectionViewWithContent:candidateUsers];
        offlineReplayStateValid = ([tagSelectionScrollView superview] != nil &&
                                   [[tagSelectionScrollView content] count] == [candidateUsers count]);
    } else if ([stateName isEqualToString:@"composer-typing"]) {
        [textView setString:@"Typing state is simulated with a synthetic user."];
        [messageEditor setContent:[textView string]];
        [self updateTextViewSizing];
        if ([candidateUsers count] > 0) [self userDidStartTyping:[candidateUsers objectAtIndex:0]];
        offlineReplayStateValid = (![typingStatusTextField isHidden] &&
                                   [[typingStatusTextField stringValue] length] > 0);
    } else if ([stateName isEqualToString:@"composer-sticker"]) {
        [stickerPickerController setEnabled:YES];
        [stickerPickerController showOfflineReplayItems:stickerItems];
        offlineReplayStateValid = [stickerPickerController offlineReplayIsShown];
    } else if ([stateName isEqualToString:@"composer-emoji-picker"]) {
        [emojiPickerController setEnabled:YES];
        [emojiPickerController showOfflineReplayPicker];
        offlineReplayStateValid = [emojiPickerController offlineReplayIsShown];
    }
    if (!offlineReplayStateValid) NSLog(@"Composer offline replay state failed validation: %@", stateName);
}

-(BOOL)offlineReplayStateIsValid {
    return offlineReplayStateValid;
}

-(NSView *)offlinePickerContentViewForFixtureNamed:(NSString *)fixtureName {
    if ([fixtureName isEqualToString:@"composer-sticker"]) return [stickerPickerController offlineReplayContentView];
    if ([fixtureName isEqualToString:@"composer-emoji-picker"]) return [emojiPickerController offlineReplayContentView];
    return nil;
}
#endif

-(void)pendingAttachmentItemWasRemoved:(PendingAttachmentViewController *)item {
    [pendingAttachmentsScrollView removeContent:item];
    if ([[pendingAttachmentsScrollView content] count] < 1) {
        [self hidePendingAttachmentView];
    }
}

// Discord's upload limit without Nitro, and the most files per message.
static const unsigned long long DLMaxUploadBytes = 10ULL * 1024 * 1024;
static const NSUInteger DLMaxAttachmentsPerMessage = 10;

-(void)updatePendingAttachmentsWithFilePaths:(NSArray *)paths {
    NSMutableArray *tooLarge = [NSMutableArray array];
    NSUInteger existing = [[pendingAttachmentsScrollView content] count];
    NSEnumerator *enumerator = [paths objectEnumerator];
    NSString *filePath;
    while (filePath = [enumerator nextObject]) {
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:NULL];
        if (![[attributes fileType] isEqualToString:NSFileTypeRegular]) continue;
        if ([attributes fileSize] > DLMaxUploadBytes) {
            [tooLarge addObject:[filePath lastPathComponent]];
            continue;
        }
        if (existing >= DLMaxAttachmentsPerMessage) {
            NSBeep();
            break;
        }
        existing++;
        [self showPendingAttachmentView];
        NSData *fileData = [NSData dataWithContentsOfFile:filePath];
        DLAttachment *attachment = [[DLAttachment alloc] init];
        [attachment setFilename:[filePath lastPathComponent]];
        [attachment setMimeType:[DLUtil mimeTypeForExtension:[filePath pathExtension]]];
        [attachment setAttachmentData:fileData];
        PendingAttachmentViewController *view = [[PendingAttachmentViewController alloc] initWithNibNamed:@"PendingAttachmentViewController" bundle:nil];
        [view setRepresentedObject:attachment];
        [view setDelegate:self];
        [pendingAttachmentsScrollView appendContent:view];
        [view release];
        [attachment release];
    }
    if ([tooLarge count]) {
        // The official client's wording for oversized uploads.
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:DLLocalizedString(@"Your files are too powerful")];
        [alert setInformativeText:[NSString stringWithFormat:DLLocalizedString(@"The max file size is 10 MB.\n\n%@"),
                                   [tooLarge componentsJoinedByString:@"\n"]]];
        [alert addButtonWithTitle:DLLocalizedString(@"OK")];
        [alert beginSheetModalForWindow:hostWindow modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
    }
}

-(void)editorContentDidUpdateWithAttributedString:(NSAttributedString *)attributedString {
    NSMutableAttributedString *merged = [[attributedString mutableCopy] autorelease];
    NSAttributedString *current = [textView textStorage];
    NSUInteger searchLocation = 0;
    for (NSUInteger index = 0; index < [current length]; index++) {
        id customEmoji = [current attribute:@kCustomEmojiAttribute atIndex:index effectiveRange:nil];
        id unicodeEmoji = [current attribute:@kUnicodeEmojiAttribute atIndex:index effectiveRange:nil];
        if (!customEmoji && !unicodeEmoji) {
            continue;
        }
        NSRange placeholderRange = [[merged string] rangeOfString:@"￼" options:0 range:NSMakeRange(searchLocation, [merged length] - searchLocation)];
        if (placeholderRange.location == NSNotFound) {
            break;
        }
        [merged replaceCharactersInRange:placeholderRange withAttributedString:[current attributedSubstringFromRange:NSMakeRange(index, 1)]];
        searchLocation = placeholderRange.location + 1;
    }
    NSInteger lengthChange = [merged length] - [[textView string] length];
    NSUInteger temporaryLocation = editingLocation + lengthChange;
    [[textView textStorage] beginEditing];
    [[textView textStorage] setAttributedString:merged];
    [[textView textStorage] endEditing];
    [textView setSelectedRange:NSMakeRange(temporaryLocation, 0)];
    [self updateTextViewSizing];
}

-(void)tagSelectionItemWasSelected:(TagSelectionViewController *)item {
    NSEnumerator *enumerator = [[tagSelectionScrollView content] objectEnumerator];
    TagSelectionViewController *otherItem;
    while (otherItem = [enumerator nextObject]) {
        if (item != otherItem) {
            [otherItem setSelected:NO];
        }
    }
    [messageEditor addMentionedUser:[item representedObject] byReplacingStringInRange:NSMakeRange(tagIndex, editingLocation - tagIndex)];
    [self hideTagSelectionView];
}

-(void)membersDidUpdate:(NSArray *)members {
    if ([self isEditingTag]) {
        NSMutableArray *users = [[NSMutableArray alloc] init];
        NSEnumerator *enumerator = [members objectEnumerator];
        DLServerMember *member;
        while (member = [enumerator nextObject]) {
            [users addObject:[member user]];
        }
        [self showTagSelectionViewWithContent:users];
        [users release];
    }
}

-(void)updateTypingString {
    if ([typingUsers count] > 0) {
        NSString *typingString = @"";
        [typingStatusTextField setHidden:NO];
        if ([DLLocalization isJapanese] && [typingUsers count] < 4) {
            NSMutableArray *names = [NSMutableArray array];
            NSEnumerator *typingEnumerator = [typingUsers objectEnumerator];
            DLUser *typingUser;
            while (typingUser = [typingEnumerator nextObject]) [names addObject:([typingUser globalName] ? [typingUser globalName] : [typingUser username])];
            typingString = [[names componentsJoinedByString:@"、"] stringByAppendingString:@"が入力中..."];
        } else if ([typingUsers count] == 1) {
            typingString = [NSString stringWithFormat:@"%@ is Typing...", [[typingUsers objectAtIndex:0] globalName]];
        } else if ([typingUsers count] < 4) {
            for (NSInteger index = 0; index < (NSInteger)[typingUsers count]; index++) {
                if (index < (NSInteger)[typingUsers count] - 1) {
                    typingString = [typingString stringByAppendingString:[NSString stringWithFormat:@"%@", [[typingUsers objectAtIndex:index] globalName]]];
                    typingString = [typingString stringByAppendingString:(index < (NSInteger)[typingUsers count] - 2 ? @", " : @" ")];
                } else {
                    typingString = [typingString stringByAppendingString:[NSString stringWithFormat:@"and %@ are Typing...", [[typingUsers objectAtIndex:index] globalName]]];
                }
            }
        } else {
            typingString = DLLocalizedString(@"Several People are Typing...");
        }
        [typingStatusTextField setStringValue:typingString];
    } else {
        [typingStatusTextField setHidden:YES];
    }
}

-(void)userDidStartTyping:(DLUser *)user {
    [user setTypingDelegate:self];
    if (![typingUsers containsObject:user]) {
        [typingUsers addObject:user];
    }
    [self updateTypingString];
}

-(void)userDidStopTyping:(DLUser *)user {
    [typingUsers removeObject:user];
    [self updateTypingString];
}

-(void)emojiPickerController:(DLEmojiPickerController *)controller didSelectEmoji:(NSDictionary *)emoji {
    NSString *emojiID = [emoji objectForKey:@"id"];
    if (!emojiID) {
        NSString *unicode = [emoji objectForKey:@"name"];
        NSImage *image = [DLTwemojiRenderer imageForEmoji:unicode size:18.0];
        if (!image) return;
        NSTextAttachmentCell *cell = [[[NSTextAttachmentCell alloc] initImageCell:image] autorelease];
        NSTextAttachment *attachment = [[[NSTextAttachment alloc] init] autorelease];
        [attachment setAttachmentCell:cell];
        NSMutableAttributedString *emojiString = [[[NSMutableAttributedString alloc]
            initWithAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]] autorelease];
        [emojiString addAttribute:@kUnicodeEmojiAttribute value:unicode range:NSMakeRange(0, [emojiString length])];
        NSRange selectedRange = [textView selectedRange];
        [[textView textStorage] replaceCharactersInRange:selectedRange withAttributedString:emojiString];
        [textView setSelectedRange:NSMakeRange(selectedRange.location + 1, 0)];
        [self updateEditorAfterTextChange];
        [self focusInput];
        return;
    }
    NSString *emojiURL = [NSString stringWithFormat:@"https://cdn.discordapp.com/emojis/%@.%@?size=32&quality=lossless", emojiID, [[emoji objectForKey:@"animated"] boolValue] ? @"gif" : @"png"];
    NSData *data = [[HTTPCache sharedInstance] cachedDataForURL:emojiURL];
    if (!data) {
        return;
    }
    NSImage *image = [[[NSImage alloc] initWithData:data] autorelease];
    [image setSize:NSMakeSize(18, 18)];
    NSTextAttachmentCell *cell = [[[NSTextAttachmentCell alloc] initImageCell:image] autorelease];
    NSTextAttachment *attachment = [[[NSTextAttachment alloc] init] autorelease];
    [attachment setAttachmentCell:cell];
    NSMutableAttributedString *emojiString = [[[NSMutableAttributedString alloc] initWithAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]] autorelease];
    NSString *prefix = [[emoji objectForKey:@"animated"] boolValue] ? @"<a:" : @"<:";
    NSString *markup = [NSString stringWithFormat:@"%@%@:%@>", prefix, [emoji objectForKey:@"name"], emojiID];
    [emojiString addAttribute:@kCustomEmojiAttribute value:markup range:NSMakeRange(0, [emojiString length])];
    NSRange selectedRange = [textView selectedRange];
    [[textView textStorage] replaceCharactersInRange:selectedRange withAttributedString:emojiString];
    [textView setSelectedRange:NSMakeRange(selectedRange.location + 1, 0)];
    [self updateEditorAfterTextChange];
    [self focusInput];
}

-(void)stickerPickerController:(DLStickerPickerController *)controller didSelectSticker:(NSDictionary *)sticker {
    id stickerID = [sticker objectForKey:@"id"];
    DLChannel *channel = [[DLController sharedInstance] selectedChannel];
    if (!stickerID || [stickerID isKindOfClass:[NSNull class]] || !channel) {
        return;
    }
    DLMessage *message = [[DLMessage alloc] init];
    [message setContent:@""];
    [message setOutgoingStickerIDs:[NSArray arrayWithObject:[stickerID description]]];
    if ([delegate respondsToSelector:@selector(messageComposerController:sendPreparedMessage:toChannel:)]) {
        [delegate messageComposerController:self sendPreparedMessage:message toChannel:channel];
    }
    [message release];
}

-(void)stickerPickerControllerDidClose:(DLStickerPickerController *)controller {
    if ([hostWindow isKeyWindow] && [textView isEditable]) {
        [self focusInput];
    }
}

-(void)showReactionPickerForChatView:(ChatItemViewController *)chatView relativeToView:(NSView *)anchorView {
    [emojiPickerController showReactionPickerForChatView:chatView relativeToView:anchorView];
}

-(void)focusInput {
    [hostWindow makeFirstResponder:textView];
}

- (BOOL)textView:(NSTextView *)inTextView doCommandBySelector:(SEL)selector {
    if (selector == @selector(insertNewline:)) {
        NSEvent *event = [NSApp currentEvent];
        if (([event modifierFlags] & NSShiftKeyMask) != NSShiftKeyMask) {
            if ([tagSelectionScrollView superview]) {
                NSEnumerator *enumerator = [[tagSelectionScrollView content] objectEnumerator];
                TagSelectionViewController *item;
                while (item = [enumerator nextObject]) {
                    if ([item isSelected]) {
                        [messageEditor addMentionedUser:[item representedObject] byReplacingStringInRange:NSMakeRange(tagIndex, editingLocation - tagIndex)];
                    }
                }
                [self hideTagSelectionView];
            } else {
                NSEnumerator *enumerator = [[pendingAttachmentsScrollView content] objectEnumerator];
                PendingAttachmentViewController *attachmentView;
                while (attachmentView = [enumerator nextObject]) {
                    [messageEditor addAttachment:[attachmentView representedObject]];
                }
                DLMessage *message = [messageEditor finalizedMessage];
                NSString *outgoing = [self serializedContent];
                if ([[DLPreferencesHandler sharedInstance] convertEmoticons]) outgoing = DLConvertEmoticons(outgoing);
                [message setContent:outgoing];
                if ([delegate respondsToSelector:@selector(messageComposerController:sendPreparedMessage:toChannel:)]) {
                    [delegate messageComposerController:self sendPreparedMessage:message toChannel:[[DLController sharedInstance] selectedChannel]];
                }
                [message release];
                [messageEditor clear];
                [textView setString:@""];
                [self updateEditorAfterTextChange];
                [self hidePendingAttachmentView];
                [self hideReplyView];
            }
            return YES;
        }
    }
    if (selector == @selector(moveUp:)) {
        if ([tagSelectionScrollView superview]) {
            NSInteger selectedIndex = [tagSelectionScrollView content].count;
            for (NSInteger index = [tagSelectionScrollView content].count - 1; index >= 0; index--) {
                if ([[[tagSelectionScrollView content] objectAtIndex:index] isSelected]) {
                    selectedIndex = index;
                }
                [[[tagSelectionScrollView content] objectAtIndex:index] setSelected:NO];
            }
            if (selectedIndex == 0) {
                selectedIndex = [tagSelectionScrollView content].count;
            }
            [[[tagSelectionScrollView content] objectAtIndex:selectedIndex - 1] setSelected:YES];
        } else {
            [chatScrollView endAllChatContentEditing];
            NSEnumerator *enumerator = [[chatScrollView content] reverseObjectEnumerator];
            ChatItemViewController *item;
            while (item = [enumerator nextObject]) {
                if ([[[item representedObject] author] isEqual:[[DLController sharedInstance] myUser]]) {
                    [item beginEditingContent];
                    [item becomeWindowFirstResponderForEditing:hostWindow];
                }
            }
        }
        return YES;
    }
    if (selector == @selector(moveDown:)) {
        NSInteger selectedIndex = -1;
        for (NSInteger index = 0; index < (NSInteger)[[tagSelectionScrollView content] count]; index++) {
            if ([[[tagSelectionScrollView content] objectAtIndex:index] isSelected]) {
                selectedIndex = index;
            }
            [[[tagSelectionScrollView content] objectAtIndex:index] setSelected:NO];
        }
        if (selectedIndex == (NSInteger)[[tagSelectionScrollView content] count] - 1) {
            selectedIndex = -1;
        }
        [[[tagSelectionScrollView content] objectAtIndex:selectedIndex + 1] setSelected:YES];
        return YES;
    }
    return NO;
}

-(void)textViewDidChangeSelection:(NSNotification *)notification {
    editingLocation = [[[textView selectedRanges] objectAtIndex:0] rangeValue].location;
    [textView setTypingAttributes:[NSDictionary dictionaryWithObjects:
        [NSArray arrayWithObjects:[DLTextParser DEFAULT_TEXT_COLOR], [textView backgroundColor], nil]
        forKeys:[NSArray arrayWithObjects:NSForegroundColorAttributeName, NSBackgroundColorAttributeName, nil]]];
    if (offlineReplay) return;
    if ([self isEditingTag]) {
        NSString *textBeforeSelection = [[textView string] substringToIndex:editingLocation];
        tagIndex = [textBeforeSelection rangeOfString:@"@" options:NSBackwardsSearch].location;
        NSString *enteredUsername = [textBeforeSelection substringFromIndex:tagIndex];
        if ([[[DLController sharedInstance] selectedServer] isEqual:[[DLController sharedInstance] myServerItem]]) {
            DLDirectMessageChannel *channel = (DLDirectMessageChannel *)[[DLController sharedInstance] selectedChannel];
            [self showTagSelectionViewWithContent:([enteredUsername isEqualToString:@"@"] ? [channel recipients] : [channel recipientsWithUsernameContainingString:[enteredUsername substringFromIndex:1]])];
        } else if ([enteredUsername isEqualToString:@"@"]) {
            NSMutableArray *users = [[NSMutableArray alloc] init];
            NSEnumerator *enumerator = [[[[DLController sharedInstance] selectedServer] members] objectEnumerator];
            DLServerMember *member;
            while (member = [enumerator nextObject]) {
                if (![[member user] isEqual:[[DLController sharedInstance] myUser]]) {
                    [users addObject:[member user]];
                }
            }
            [self showTagSelectionViewWithContent:users];
            [users release];
        } else {
            if ([delegate respondsToSelector:@selector(messageComposerController:queryServer:forMembersContainingUsername:)]) {
                [delegate messageComposerController:self
                                        queryServer:[[DLController sharedInstance] selectedServer]
                      forMembersContainingUsername:[enteredUsername substringFromIndex:1]];
            }
        }
    } else {
        [self hideTagSelectionView];
    }
}

- (BOOL)textView:(NSTextView *)inTextView shouldChangeTextInRange:(NSRange)affectedRange replacementString:(NSString *)replacementString {
    if ((NSInteger)affectedRange.location <= (NSInteger)([[textView string] length] - 1)) {
        NSDictionary *attributes = [[textView textStorage] attributesAtIndex:affectedRange.location effectiveRange:nil];
        if ([[attributes objectForKey:@kTagAttribute] boolValue]) {
            if ([[textView string] characterAtIndex:affectedRange.location] == '@') {
                if ([replacementString isEqualToString:@""]) {
                    madeMentionChange = YES;
                }
            } else {
                madeMentionChange = YES;
            }
        }
    }
    return YES;
}

-(void)textDidChange:(NSNotification *)notification {
    if (!normalizingEmoji && ![textView hasMarkedText]) {
        normalizingEmoji = YES;
        NSMutableAttributedString *converted = [[textView textStorage] mutableCopy];
        NSUInteger cursor = [textView selectedRange].location;
        NSUInteger replacements = [DLTwemojiRenderer replaceEmojiInAttributedString:converted
                                                                              size:18.0
                                                                excludingAttribute:nil
                                                               recordingAttribute:@kUnicodeEmojiAttribute
                                                                    cursorLocation:&cursor];
        if (replacements) {
            [[textView textStorage] setAttributedString:converted];
            [textView setSelectedRange:NSMakeRange(MIN(cursor, [converted length]), 0)];
        }
        [converted release];
        normalizingEmoji = NO;
    }
    [self updateEditorAfterTextChange];
}

-(void)setDraftText:(NSString *)text {
    if (![textView isEditable]) return;
    [textView setString:(text ? text : @"")];
    [self updateEditorAfterTextChange];
    [textView setSelectedRange:NSMakeRange([[textView string] length], 0)];
}

-(void)insertMentionForUser:(DLUser *)user {
    if (!user || ![textView isEditable]) return;
    NSString *current = [textView string];
    NSString *separator = ([current length] && ![current hasSuffix:@" "] && ![current hasSuffix:@"\n"]) ? @" " : @"";
    NSString *base = [current stringByAppendingString:separator];
    [messageEditor setContent:base];
    [messageEditor addMentionedUser:user byReplacingStringInRange:NSMakeRange([base length], 0)];
    [self focusInput];
    [textView setSelectedRange:NSMakeRange([[textView string] length], 0)];
}

-(void)updateEditorAfterTextChange {
    [messageEditor setContent:[textView string]];
    if (madeMentionChange) {
        [messageEditor removeMentionedUserAtStringIndex:tagIndex];
        madeMentionChange = NO;
    }
    [self updateTextViewSizing];
    if (!offlineReplay && !isTyping && ![[textView string] isEqualToString:@""]) {
        if ([delegate respondsToSelector:@selector(messageComposerController:informTypingInChannel:)]) {
            [delegate messageComposerController:self informTypingInChannel:[[DLController sharedInstance] selectedChannel]];
        }
        isTyping = YES;
        typingTimer = [NSTimer scheduledTimerWithTimeInterval:DLComposerTypingSendInterval target:self selector:@selector(updateTypingStatus) userInfo:nil repeats:NO];
    }
}

-(void)dealloc {
    delegate = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [typingTimer invalidate];
    [chatScrollView setDelegate:nil];
    [textView setDelegate:nil];
    [messageEditor setDelegate:nil];
    [emojiPickerController setDelegate:nil];
    [stickerPickerController setDelegate:nil];
    [emojiPickerController release];
    [stickerPickerController release];
    [messageEditor release];
    [typingUsers release];
    [backgroundView release];
    [pendingAttachmentScroller release];
    [tagSelectionScroller release];
    [textScroller release];
    [attachButton release];
    [typingStatusTextField release];
    [replyTextField release];
    [replyView release];
    [tagSelectionScrollView release];
    [pendingAttachmentsScrollView release];
    [chatScrollView release];
    [textScrollView release];
    [textView release];
    [containerView release];
    [super dealloc];
}

@end
