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

@protocol DLThreadControllerDelegate <NSObject>
-(void)threadController:(DLThreadController *)controller selectChannel:(DLChannel *)channel;
-(void)threadController:(DLThreadController *)controller restoreBaseChannel:(DLChannel *)channel;
@end

@interface DLThreadController : NSObject <NSTableViewDataSource, NSTableViewDelegate> {
    id<DLThreadControllerDelegate> delegate;
    NSView *hostView;
    ChatScrollView *chatScrollView;
    NSView *composerView;
    NSView_BGColor *listPane;
    NSScrollView *listScrollView;
    NSTableView *listTableView;
    NSArray *items;
    NSTextField *emptyField;
    NSView_BGColor *detailPane;
    NSTextField *detailTitleField;
    DLChannel *baseChannel;
    BOOL visible;
    BOOL detailVisible;
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
