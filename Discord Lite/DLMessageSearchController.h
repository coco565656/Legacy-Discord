//
//  DLMessageSearchController.h
//  Legacy Discord
//

#import <Cocoa/Cocoa.h>

@class DLMessageSearchController;
@class ChatScrollView;
@class DLChannel;
@class DLServer;
@class DLError;
@class NSView_BGColor;

@protocol DLMessageSearchControllerDelegate <NSObject>
-(void)messageSearchControllerWillShow:(DLMessageSearchController *)controller;
-(void)messageSearchControllerDidClose:(DLMessageSearchController *)controller;
@end

@interface DLMessageSearchController : NSObject <NSTableViewDataSource, NSTableViewDelegate> {
    id<DLMessageSearchControllerDelegate> delegate;
    NSView *hostView;
    ChatScrollView *chatScrollView;
    NSView *composerView;
    NSSearchField *searchField;
    NSView_BGColor *resultsPane;
    NSTextField *titleField;
    NSScrollView *resultsScrollView;
    NSTableView *resultsTableView;
    NSTextField *countField;
    NSTextField *emptyStateField;
    NSButton *previousButton;
    NSButton *nextButton;
    NSTextField *pageField;
    NSArray *results;
    BOOL visible;
    NSInteger offset;
    NSInteger total;
    NSString *pendingAuthorName;
    NSInteger pendingAuthorOffset;
    NSString *lastQuery;
    NSInteger lastResultIndex;
    id highlightedResult;
}

-(id)initWithHostView:(NSView *)hostView chatScrollView:(ChatScrollView *)chatScrollView
         composerView:(NSView *)composerView searchField:(NSSearchField *)searchField;
-(void)setDelegate:(id<DLMessageSearchControllerDelegate>)delegate;
-(void)attachToHostView:(NSView *)hostView;
-(BOOL)isVisible;
-(void)close;
-(void)resetForChannelChange;
-(void)clearHighlight;
-(void)messageSearchResults:(NSArray *)messages totalResults:(NSInteger)total offset:(NSInteger)offset
                 forChannel:(DLChannel *)channel query:(NSString *)query;
-(void)members:(NSArray *)members didUpdateForServer:(DLServer *)server;
-(void)didDisplayMessagesAroundID:(NSString *)messageID;
-(void)showPinnedMessagesLoading;
-(void)showPinnedMessages:(NSArray *)messages;
-(void)showPinnedMessagesError;
-(void)applyCurrentTheme;

@end
