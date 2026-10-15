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
#import "DynamicScrollView.h"
#import "ChatScrollView.h"
#import "PaddedTextView.h"
#import "NSView+Border.h"
#import "DLAudioPlayer.h"
#import "HorizontalDynamicScrollView.h"
#import "DLCompatibilityPopover.h"
#import "DLMessageReadStateController.h"
#import "DLServerNavigationController.h"
#import "DLChannelNavigationController.h"
#import "DLMemberListController.h"
#import "DLUserProfileController.h"
#import "DLThreadController.h"
#import "DLMessageSearchController.h"
#import "DLPinsController.h"
#import "DLMessageComposerController.h"
#import "DLDirectMessageController.h"
#import "DLMessagePresentationController.h"
#import "DLMainHeaderController.h"

@protocol DLMainWindowDelegate <NSObject>
@optional
-(void)logoutWasSuccessful;
@end

@interface DLMainWindowController : NSWindowController <DLControllerDelegate, DLUserDelegate, DLServerNavigationControllerDelegate, DLChannelNavigationControllerDelegate, DLMemberListControllerDelegate, DLThreadControllerDelegate, DLMessageSearchControllerDelegate, DLPinsControllerDelegate, DLMessageComposerControllerDelegate, DLDirectMessageControllerDelegate, DLMessagePresentationControllerDelegate, DLMainHeaderControllerDelegate, NSSplitViewDelegate> {
    
    BOOL isLoadingViews;

    IBOutlet NSView_BGColor *messageEntryContainerView;
    IBOutlet NSView_BGColor *channelViewHeader;
    IBOutlet NSView_BGColor *chatViewHeader;
    IBOutlet NSView_BGColor *userInfoView;
    
    IBOutlet NSScroller_BGColor *serverViewScroller;
    IBOutlet NSScroller_BGColor *channelViewScroller;
    IBOutlet NSScroller_BGColor *chatViewScroller;
    IBOutlet NSScroller_BGColor *messageEntryViewScroller;
    IBOutlet NSScroller_BGColor *tagSelectionViewScroller;
    IBOutlet NSScroller_BGColor *pendingAttachmentViewScroller;
    
    
    IBOutlet DynamicScrollView *serversScrollView;
    DLServerNavigationController *serverNavigationController;
    DLMainHeaderController *mainHeaderController;
    NSSplitView *mainSplitView;
    NSView *channelPaneView;
    NSView *chatPaneView;
    DLDirectMessageController *directMessageController;
    DLMessageSearchController *messageSearchController;
    DLPinsController *pinsController;
    DLMemberListController *memberListController;
    DLUserProfileController *userProfileController;
    DLMessageReadStateController *messageReadStateController;
    DLThreadController *threadController;
    IBOutlet DynamicScrollView *channelsScrollView;
    DLChannelNavigationController *channelNavigationController;
    IBOutlet DynamicScrollView *tagSelectionScrollView;
    IBOutlet PaddedTextView *messageEntryTextView;
    IBOutlet NSScrollView *messageEntryScrollView;
    IBOutlet ChatScrollView *chatScrollView;
    IBOutlet NSImageView *myUserAvatarImage;
    IBOutlet NSTextField *myUsernameTextField;
    IBOutlet NSTextField *myDiscTextField;
    IBOutlet NSButton *attachButton;
    DLMessageComposerController *messageComposerController;
    DLMessagePresentationController *messagePresentationController;
    
    
    IBOutlet NSTextField *serverLabel;
    IBOutlet NSImageView *chatHeaderImage;
    IBOutlet NSTextField *chatHeaderLabel;
    IBOutlet HorizontalDynamicScrollView *pendingAttachmentsScrollView;
    IBOutlet NSTextField *typingStatusTextField;
    
    IBOutlet NSView *replyToView;
    IBOutlet NSTextField *replyToTextField;
    
    
    id<DLMainWindowDelegate> delegate;
}
- (IBAction)showFileOpenDialog:(id)sender;
- (IBAction)showSettingsMenu:(id)sender;
- (IBAction)removeReferencedMessage:(id)sender;
-(void)setDelegate:(id<DLMainWindowDelegate>)inDelegate;
#if LEGACY_DISCORD_UI_DIAGNOSTICS
-(NSString *)writeSanitizedUIDiagnostics;
#endif
#if LEGACY_DISCORD_LOCAL_DEV
-(void)showLocalReplayFixtureNamed:(NSString *)fixtureName windowSize:(NSSize)windowSize;
-(BOOL)captureLocalReplayPNGToPath:(NSString *)path;
#endif
@end
