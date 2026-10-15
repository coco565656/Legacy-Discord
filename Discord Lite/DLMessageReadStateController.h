//
//  DLMessageReadStateController.h
//  Legacy Discord
//

#import <Cocoa/Cocoa.h>

@class ChatScrollView;
@class DLMessage;
@class DLMessageReadStateController;

@protocol DLMessageReadStateControllerDelegate <NSObject>
-(DLMessage *)latestMessageForMessageReadStateController:(DLMessageReadStateController *)controller;
@end

@interface DLMessageReadStateController : NSObject {
    ChatScrollView *chatScrollView;
    NSWindow *window;
    id<DLMessageReadStateControllerDelegate> delegate;

    NSView *historyMessageBanner;
    NSTextField *historyMessageBannerLabel;
    NSButton *jumpToLatestButton;
    NSView *unreadMessageBanner;
    NSTextField *unreadMessageBannerLabel;
    NSButton *markMessagesReadButton;

    NSInteger pendingNewMessageCount;
    NSDate *pendingNewMessageStartDate;
    NSString *firstUnreadMessageID;
}

-(id)initWithChatScrollView:(ChatScrollView *)scrollView window:(NSWindow *)inWindow;
-(void)setDelegate:(id<DLMessageReadStateControllerDelegate>)inDelegate;
-(BOOL)isViewingLatestMessages;
-(BOOL)hasPendingMessages;
-(void)recordUnreadMessage:(DLMessage *)message;
-(void)resetUnreadMessageState;

@end
