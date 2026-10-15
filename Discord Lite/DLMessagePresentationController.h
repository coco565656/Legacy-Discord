//
//  DLMessagePresentationController.h
//  Legacy Discord
//

#import <Cocoa/Cocoa.h>
#import "ChatItemViewController.h"
#import "DLMessageReadStateController.h"

@class DLMessagePresentationController;
@class ChatScrollView;
@class DLMessage;
@class DLChannel;
@class DLServer;
@class DLMessageSearchController;
@class DLPinsController;
@class DLChannelNavigationController;
@class DLMessageComposerController;
@class DLUserProfileController;

@protocol DLMessagePresentationControllerDelegate <NSObject>
-(void)messagePresentationControllerNeedsDirectMessageRefresh:(DLMessagePresentationController *)controller;
@end

@interface DLMessagePresentationController : NSObject <ChatItemViewControllerDelegate, DLMessageReadStateControllerDelegate> {
    id<DLMessagePresentationControllerDelegate> delegate;
    NSWindow *hostWindow;
    ChatScrollView *chatScrollView;
    NSTextField *chatHeaderLabel;
    NSImageView *chatHeaderImage;
    NSButton *reloadButton;
    DLMessageReadStateController *readStateController;
    DLMessageSearchController *searchController;
    DLPinsController *pinsController;
    DLChannelNavigationController *channelNavigationController;
    DLMessageComposerController *composerController;
    DLUserProfileController *userProfileController;
    DLMessage *lastMessage;
    DLMessage *firstMessage;
    DLMessage *messagePendingDeletion;
    BOOL isLoadingMessages;
    BOOL isLoadingNewerMessages;
    BOOL searchHistoryWindowActive;
    BOOL hasMoreNewerMessages;
#if LEGACY_DISCORD_LOCAL_DEV
    BOOL localReplayActive;
#endif
}

-(id)initWithWindow:(NSWindow *)window
      chatScrollView:(ChatScrollView *)chatScrollView
     chatHeaderLabel:(NSTextField *)chatHeaderLabel
     chatHeaderImage:(NSImageView *)chatHeaderImage
        reloadButton:(NSButton *)reloadButton
 readStateController:(DLMessageReadStateController *)readStateController
    searchController:(DLMessageSearchController *)searchController
      pinsController:(DLPinsController *)pinsController
channelNavigationController:(DLChannelNavigationController *)channelNavigationController
  composerController:(DLMessageComposerController *)composerController
userProfileController:(DLUserProfileController *)userProfileController;
-(void)setDelegate:(id<DLMessagePresentationControllerDelegate>)delegate;
-(void)prepareForServerChange;
-(void)prepareForChannelChange;
-(void)loadInitialMessagesForChannel:(DLChannel *)channel;
-(void)reloadSelectedChannel;
-(void)messages:(NSArray *)messages receivedForChannel:(DLChannel *)channel;
-(void)newerMessages:(NSArray *)messages receivedForChannel:(DLChannel *)channel;
-(void)newMessage:(DLMessage *)message receivedForChannel:(DLChannel *)channel inServer:(DLServer *)server;
-(void)messages:(NSArray *)messages receivedAroundSearchResult:(NSString *)messageID forChannel:(DLChannel *)channel;
#if LEGACY_DISCORD_LOCAL_DEV
-(void)displayReplayMessages:(NSArray *)messages channelName:(NSString *)channelName;
#endif

@end
