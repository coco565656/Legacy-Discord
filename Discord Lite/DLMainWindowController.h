//
//  DLMainWindowController.h
//  Discord Lite
//
//  Created by Collin Mistr on 10/27/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "DLController.h"
#import "DLErrorHandler.h"
#import "ServerItemViewController.h"
#import "DynamicScrollView.h"
#import "ChatScrollView.h"
#import "ChannelItemViewController.h"
#import "ChatItemViewController.h"
#import "PaddedTextView.h"
#import "DirectMessageItemViewController.h"
#import "NSView+Border.h"
#import "DLAudioPlayer.h"
#import "HorizontalDynamicScrollView.h"
#import "PendingAttachmentViewController.h"
#import "TagSelectionViewController.h"
#import "DLMessageEditor.h"

typedef enum {
    DLDialogConfirmMessageDelete = 0
} DLDialog;

@protocol DLMainWindowDelegate <NSObject>
@optional
-(void)logoutWasSuccessful;
@end

@interface DLMainWindowController : NSWindowController <DLControllerDelegate, DLChannelDelegate, DLServerDelegate, ServerItemDelegate, ChannelItemDelegate, DLUserDelegate, DMChannelItemDelegate, PendingAttachmentItemDelegate, DLUserTypingDelegate, TagSelectionItemDelegate, DLMessageEditorDelegate, ChatItemViewControllerDelegate, ChatScrollViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSToolbarDelegate, NSSplitViewDelegate, AsyncHTTPRequestDelegate, NSPopoverDelegate> {
    
    BOOL isLoadingViews;
    BOOL isLoadingMessages;
    BOOL isLoadingNewerMessages;
    BOOL searchHistoryWindowActive;
    BOOL hasMoreNewerMessages;
    BOOL isTyping;
    BOOL madeMentionChange;
    
    IBOutlet NSView_BGColor *messageEntryContainerView;
    NSView *messageComposerBackgroundView;
    IBOutlet NSView_BGColor *channelViewHeader;
    IBOutlet NSView_BGColor *chatViewHeader;
    IBOutlet NSView_BGColor *userInfoView;
    
    NSInteger editingLocation;
    NSInteger tagIndex;
    
    IBOutlet NSScroller_BGColor *serverViewScroller;
    IBOutlet NSScroller_BGColor *channelViewScroller;
    IBOutlet NSScroller_BGColor *chatViewScroller;
    IBOutlet NSScroller_BGColor *messageEntryViewScroller;
    IBOutlet NSScroller_BGColor *tagSelectionViewScroller;
    IBOutlet NSScroller_BGColor *pendingAttachmentViewScroller;
    
    
    IBOutlet DynamicScrollView *serversScrollView;
    NSTableView *serverTableView;
    NSArray *serverItems;
    BOOL updatingServerTableSelection;
    NSToolbar *mainToolbar;
    NSSplitView *mainSplitView;
    NSView *channelPaneView;
    NSView *chatPaneView;
    NSView_BGColor *friendsHomeView;
    NSScrollView *friendsHomeScrollView;
    NSArray *friendsHomeChannels;
    BOOL compactDMLayout;
    CGFloat expandedChannelPaneWidth;
    NSSearchField *messageSearchField;
    NSView *connectionStatusField;
    NSButton *reloadButton;
    NSButton *threadsButton;
    NSButton *membersButton;
    NSButton *pinsButton;
    NSView_BGColor *memberListPane;
    NSScrollView *memberListScrollView;
    NSTableView *memberListTableView;
    NSArray *memberListItems;
    NSMutableSet *memberAvatarRequests;
    BOOL memberListVisible;
    NSInteger memberRequestedUpperBound;
    BOOL memberRequestInFlight;
    NSPopover *profilePopover;
    NSViewController *profilePopoverController;
    DLUser *profileUser;
    DLServer *profileServer;
    DLServerMember *profileMember;
    NSPanel *profileDetailPanel;
    NSButton *profileAvatarButton;
    NSImageView *profileDetailAvatarView;
    NSCache *profileAvatarCache;
    NSMutableSet *profileAvatarRequests;
    NSCache *profileBannerImageCache;
    NSMutableSet *profileBannerImageRequests;
    NSMutableDictionary *profileDataCache;
    NSMutableSet *profileDataRequests;
    NSView_BGColor *profileBannerView;
    NSImageView *profileBannerImageView;
    NSTextField *profileBioField;
    NSTextField *profileMetadataField;
    NSView *profileRoleContainer;
    NSView *profileStatusBubble;
    NSTextField *profileStatusField;
    NSView_BGColor *profileDetailBannerView;
    NSImageView *profileDetailBannerImageView;
    NSTextField *profileDetailBioField;
    NSTextField *profileDetailMetadataField;
    NSTextField *profileDetailConnectionsField;
    NSView *profileDetailRoleContainer;
    NSView *profileDetailStatusBubble;
    NSTextField *profileDetailStatusField;
    NSString *profileBannerURL;
    NSButton *myProfileButton;
    NSView_BGColor *historyMessageBanner;
    NSTextField *historyMessageBannerLabel;
    NSButton *jumpToLatestButton;
    NSView_BGColor *unreadMessageBanner;
    NSTextField *unreadMessageBannerLabel;
    NSButton *markMessagesReadButton;
    NSInteger pendingNewMessageCount;
    NSDate *pendingNewMessageStartDate;
    NSString *firstUnreadMessageID;
    NSView_BGColor *threadListPane;
    NSScrollView *threadListScrollView;
    NSTableView *threadListTableView;
    NSArray *threadListItems;
    NSTextField *threadListEmptyField;
    NSView_BGColor *threadDetailPane;
    NSTextField *threadDetailTitleField;
    DLChannel *threadListBaseChannel;
    BOOL threadListVisible;
    BOOL threadDetailVisible;
    NSView_BGColor *searchResultsPane;
    NSTextField *searchResultsTitleField;
    NSScrollView *searchResultsScrollView;
    NSTableView *searchResultsTableView;
    NSTextField *searchResultsCountField;
    NSTextField *searchEmptyStateField;
    NSButton *searchPreviousButton;
    NSButton *searchNextButton;
    NSTextField *searchPageField;
    NSArray *messageSearchResults;
    BOOL searchResultsPaneVisible;
    BOOL pinsPaneActive;
    NSInteger messageSearchOffset;
    NSInteger messageSearchTotal;
    NSString *pendingSearchAuthorName;
    NSInteger pendingSearchAuthorOffset;
    DLWSConnectionState currentConnectionState;
    NSString *lastMessageSearchQuery;
    NSInteger lastMessageSearchIndex;
    ChatItemViewController *highlightedSearchResult;
    IBOutlet DynamicScrollView *channelsScrollView;
    NSOutlineView *channelOutlineView;
    NSArray *channelOutlineItems;
    BOOL updatingChannelOutlineSelection;
    IBOutlet DynamicScrollView *tagSelectionScrollView;
    IBOutlet PaddedTextView *messageEntryTextView;
    IBOutlet NSScrollView *messageEntryScrollView;
    IBOutlet ChatScrollView *chatScrollView;
    IBOutlet NSImageView *myUserAvatarImage;
    IBOutlet NSTextField *myUsernameTextField;
    IBOutlet NSTextField *myDiscTextField;
    IBOutlet NSButton *attachButton;
    NSButton *emojiButton;
    NSButton *stickerButton;
    NSPopover *emojiPopover;
    NSViewController *emojiPopoverController;
    NSSearchField *emojiPickerSearchField;
    NSScrollView *emojiPickerScrollView;
    NSArray *emojiPickerItems;
    NSPopover *stickerPopover;
    NSViewController *stickerPopoverController;
    NSSearchField *stickerPickerSearchField;
    NSScrollView *stickerPickerScrollView;
    NSArray *stickerPickerItems;
    ChatItemViewController *reactionPickerChatView;
    
    
    IBOutlet NSTextField *serverLabel;
    IBOutlet NSImageView *chatHeaderImage;
    IBOutlet NSTextField *chatHeaderLabel;
    IBOutlet HorizontalDynamicScrollView *pendingAttachmentsScrollView;
    IBOutlet NSTextField *typingStatusTextField;
    
    IBOutlet NSView *replyToView;
    IBOutlet NSTextField *replyToTextField;
    
    
    DLMessage *lastMessage;
    DLMessage *firstMessage;
    DLMessage *messagePendingDeletion;
    DLMessageEditor *messageEditor;
    NSMutableArray *typingUsers;
    
    CGFloat currentMessageScrollHeight;
    
    NSTimer *typingTimer;
    id<DLMainWindowDelegate> delegate;
}
- (IBAction)showFileOpenDialog:(id)sender;
- (IBAction)showSettingsMenu:(id)sender;
- (IBAction)removeReferencedMessage:(id)sender;
-(void)showEmojiMenu:(id)sender;
-(void)insertCustomEmoji:(id)sender;
-(void)showStickerMenu:(id)sender;
-(void)sendSticker:(id)sender;

-(void)setDelegate:(id<DLMainWindowDelegate>)inDelegate;
@end
