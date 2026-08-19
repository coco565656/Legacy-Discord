//
//  ChatItemViewController.h
//  Discord Lite
//
//  Created by Collin Mistr on 11/1/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "ViewController.h"
#import "DLMessage.h"
#import "AttachmentPreviewViewController.h"
#import "DLTextParser.h"
#import "NSTextView+Menu.h"
#import "DLController.h"

@class ChatItemViewController;

@protocol ChatItemViewControllerDelegate <NSObject>
@optional
-(void)addReferencedMessage:(DLMessage *)m;
-(BOOL)chatViewShouldBeginEditing:(ChatItemViewController *)chatView;
-(void)chatViewUpdatedWithEnteredText:(ChatItemViewController *)chatView;
-(void)chatViewContentWasUpdated:(ChatItemViewController *)chatView;
-(void)chatView:(ChatItemViewController *)chatView didEndEditingWithCommit:(BOOL)didCommit;
-(void)chatViewMessageShouldBeDeleted:(ChatItemViewController *)chatView;
-(void)chatViewMessageWasDeleted:(ChatItemViewController *)chatView;
-(void)chatView:(ChatItemViewController *)chatView showReactionPickerRelativeToView:(NSView *)anchorView;
@end

@interface ChatItemViewController : ViewController <DLUserDelegate, NSViewEventDelegate, NSTextViewMenuDelegate, DLMessageDelegate, AsyncHTTPRequestDelegate> {
    DLMessage *representedObject;
    id<ChatItemViewControllerDelegate> delegate;
    IBOutlet NSView_BGColor *insetView;
    IBOutlet NSTextView_Menu *chatTextView;
    CGFloat baseViewHeight;
    IBOutlet NSTextField *usernameTextField;
    IBOutlet NSImageView *avatarImageView;
    IBOutlet NSTextField *timestampTextField;
    NSArray *attachmentViews;
    NSMutableArray *embedViews;
    CGFloat embedsHeight;
    IBOutlet NSView *referencedMessageView;
    IBOutlet NSTextField *referencedMessageTextField;
    IBOutlet NSImageView *referencedMessageAvatarImageView;
    BOOL viewHasLoaded;
    NSMenu *contextMenu;
    NSMenu *reactionMenu;
    NSTextField *reactionTextField;
    NSMutableArray *reactionButtons;
    NSMenuItem *editItem;
    NSMenuItem *deleteItem;
    BOOL isEditing;
    BOOL usesMentionBackground;
    BOOL searchHighlighted;
    BOOL compactDisplay;
    BOOL groupedMessageFollows;
    NSView *messageActionBar;
    IBOutlet NSTextField *editDismissInfoLabel;
    IBOutlet NSTextField *editedInfoLabel;
}

-(DLMessage *)representedObject;
-(CGFloat)expectedHeight;

-(void)setDelegate:(id<ChatItemViewControllerDelegate>)inDelegate;
-(void)setRepresentedObject:(DLMessage *)obj;
-(void)setIsMyContent:(BOOL)mine;
-(void)setSearchHighlighted:(BOOL)highlighted;
-(void)setCompactDisplay:(BOOL)compact;
-(void)setGroupedMessageFollows:(BOOL)follows;
-(void)beginEditingContent;
-(void)endEditingContent;
-(BOOL)isBeingEdited;
-(void)becomeWindowFirstResponderForEditing:(NSWindow *)window;
-(void)toggleReactionWithEmoji:(NSDictionary *)emoji;

@end
