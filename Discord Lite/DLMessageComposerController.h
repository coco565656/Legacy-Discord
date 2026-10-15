//
//  DLMessageComposerController.h
//  Legacy Discord
//

#import <Cocoa/Cocoa.h>
#import "PendingAttachmentViewController.h"
#import "TagSelectionViewController.h"
#import "DLMessageEditor.h"
#import "DLEmojiPickerController.h"
#import "DLStickerPickerController.h"
#import "DLUser.h"
#import "ChatScrollView.h"

@class DLMessageComposerController;
@class NSView_BGColor;
@class NSScroller_BGColor;
@class DynamicScrollView;
@class HorizontalDynamicScrollView;
@class PaddedTextView;
@class ChatScrollView;
@class ChatItemViewController;
@class DLMessage;
@class DLChannel;
@class DLServer;

@protocol DLMessageComposerControllerDelegate <NSObject>
-(void)messageComposerController:(DLMessageComposerController *)controller sendPreparedMessage:(DLMessage *)message toChannel:(DLChannel *)channel;
-(void)messageComposerController:(DLMessageComposerController *)controller informTypingInChannel:(DLChannel *)channel;
-(void)messageComposerController:(DLMessageComposerController *)controller queryServer:(DLServer *)server forMembersContainingUsername:(NSString *)username;
@end

@interface DLMessageComposerController : NSObject <PendingAttachmentItemDelegate, TagSelectionItemDelegate, DLMessageEditorDelegate, DLEmojiPickerControllerDelegate, DLStickerPickerControllerDelegate, DLUserTypingDelegate, NSTextViewDelegate, ChatScrollViewDelegate> {
    id<DLMessageComposerControllerDelegate> delegate;
    NSWindow *hostWindow;
    NSView_BGColor *containerView;
    PaddedTextView *textView;
    NSScrollView *textScrollView;
    ChatScrollView *chatScrollView;
    HorizontalDynamicScrollView *pendingAttachmentsScrollView;
    DynamicScrollView *tagSelectionScrollView;
    NSView *replyView;
    NSTextField *replyTextField;
    NSTextField *typingStatusTextField;
    NSButton *attachButton;
    NSScroller_BGColor *textScroller;
    NSScroller_BGColor *tagSelectionScroller;
    NSScroller_BGColor *pendingAttachmentScroller;
    NSView *backgroundView;
    DLEmojiPickerController *emojiPickerController;
    DLStickerPickerController *stickerPickerController;
    DLMessageEditor *messageEditor;
    NSMutableArray *typingUsers;
    NSTimer *typingTimer;
    NSInteger editingLocation;
    NSInteger tagIndex;
    CGFloat currentTextScrollHeight;
    BOOL isTyping;
    BOOL madeMentionChange;
    BOOL normalizingEmoji;
    BOOL offlineReplay;
    BOOL offlineReplayStateValid;
}

-(id)initWithWindow:(NSWindow *)window
       containerView:(NSView_BGColor *)containerView
            textView:(PaddedTextView *)textView
      textScrollView:(NSScrollView *)textScrollView
      chatScrollView:(ChatScrollView *)chatScrollView
pendingAttachmentsScrollView:(HorizontalDynamicScrollView *)pendingAttachmentsScrollView
  tagSelectionScrollView:(DynamicScrollView *)tagSelectionScrollView
           replyView:(NSView *)replyView
      replyTextField:(NSTextField *)replyTextField
typingStatusTextField:(NSTextField *)typingStatusTextField
        attachButton:(NSButton *)attachButton
        textScroller:(NSScroller_BGColor *)textScroller
tagSelectionScroller:(NSScroller_BGColor *)tagSelectionScroller
pendingAttachmentScroller:(NSScroller_BGColor *)pendingAttachmentScroller;

-(void)setDelegate:(id<DLMessageComposerControllerDelegate>)delegate;
-(void)prepareForOfflineReplay;
-(void)setEnabledForChannel:(DLChannel *)channel;
-(void)reset;
-(void)applyCurrentTheme;
-(void)showFileOpenDialog;
-(void)removeReferencedMessage;
-(void)addReferencedMessage:(DLMessage *)message;
-(void)membersDidUpdate:(NSArray *)members;
-(void)userDidStartTyping:(DLUser *)user;
-(void)userDidStopTyping:(DLUser *)user;
-(void)showReactionPickerForChatView:(ChatItemViewController *)chatView relativeToView:(NSView *)anchorView;
-(void)focusInput;
#if LEGACY_DISCORD_LOCAL_DEV
-(void)configureOfflineReplayStateNamed:(NSString *)stateName
                           replyMessage:(DLMessage *)replyMessage
                         candidateUsers:(NSArray *)candidateUsers
                        attachmentPaths:(NSArray *)attachmentPaths
                           stickerItems:(NSArray *)stickerItems;
-(BOOL)offlineReplayStateIsValid;
-(NSView *)offlinePickerContentViewForFixtureNamed:(NSString *)fixtureName;
#endif

@end
