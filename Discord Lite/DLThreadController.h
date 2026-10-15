//
//  DLThreadController.h
//  Legacy Discord
//

#import <Cocoa/Cocoa.h>

@class DLThreadController;
@class DLServer;
@class DLChannel;
@class ChatScrollView;
@class NSView_BGColor;
@class DLContextTableView;

@protocol DLThreadControllerDelegate <NSObject>
-(void)threadController:(DLThreadController *)controller selectChannel:(DLChannel *)channel;
-(void)threadController:(DLThreadController *)controller restoreBaseChannel:(DLChannel *)channel;
@end

// The official forum post list (a forum or media channel's main view) and the
// thread list of a text channel. Both show Discord-style cards; opening one
// shows the post or thread in the regular full-width chat.
@interface DLThreadController : NSObject <NSTableViewDataSource, NSTableViewDelegate> {
    id<DLThreadControllerDelegate> delegate;
    NSView *hostView;
    ChatScrollView *chatScrollView;
    NSView *composerView;
    NSView_BGColor *listPane;
    NSScrollView *listScrollView;
    DLContextTableView *listTableView;
    NSSearchField *searchField;
    NSButton *closeButton;
    NSTextField *titleField;
    NSArray *allItems;
    NSArray *items;
    NSTextField *emptyField;
    DLChannel *baseChannel;
    BOOL visible;
}

-(id)initWithHostView:(NSView *)hostView
       chatScrollView:(ChatScrollView *)chatScrollView
         composerView:(NSView *)composerView;
-(void)setDelegate:(id<DLThreadControllerDelegate>)delegate;
-(BOOL)isVisible;
-(void)showThreadList;
-(void)hideThreadBrowser;
-(void)refreshForServer:(DLServer *)server;
-(void)threadsDidUpdateForServer:(DLServer *)server;
-(void)archivedThreadsDidUpdateForServer:(DLServer *)server channel:(DLChannel *)channel;
-(void)applyCurrentTheme;

@end
