//
//  DLMemberListController.h
//  Legacy Discord
//

#import <Cocoa/Cocoa.h>
#import "DLUser.h"

@class DLMemberListController;
@class DLServer;
@class DLChannel;
@class ChatScrollView;
@class NSView_BGColor;

@protocol DLMemberListControllerDelegate <NSObject>
-(void)memberListController:(DLMemberListController *)controller
              didSelectUser:(DLUser *)user
             relativeToRect:(NSRect)rect
                     ofView:(NSView *)view;
@optional
-(void)memberListController:(DLMemberListController *)controller avatarDidUpdateForUser:(DLUser *)user;
@end

@interface DLMemberListController : NSObject <NSTableViewDataSource, NSTableViewDelegate, DLUserDelegate> {
    id<DLMemberListControllerDelegate> delegate;
    NSView *hostView;
    ChatScrollView *chatScrollView;
    NSView *composerView;
    NSButton *toggleButton;
    NSView_BGColor *pane;
    NSScrollView *scrollView;
    NSTableView *tableView;
    NSTextField *titleField;
    NSArray *items;
    NSMutableSet *avatarRequests;
    DLServer *displayedServer;
    DLChannel *displayedChannel;
    BOOL visible;
    NSInteger requestedUpperBound;
    BOOL requestInFlight;
}

-(id)initWithHostView:(NSView *)inHostView
       chatScrollView:(ChatScrollView *)inChatScrollView
         composerView:(NSView *)inComposerView
         toggleButton:(NSButton *)inToggleButton;
-(void)setDelegate:(id<DLMemberListControllerDelegate>)inDelegate;
-(BOOL)isVisible;
-(void)setVisible:(BOOL)shouldShow server:(DLServer *)server channel:(DLChannel *)channel;
-(void)refreshForServer:(DLServer *)server;
-(void)members:(NSArray *)members didUpdateForServer:(DLServer *)server;
-(void)applyCurrentTheme;

@end
