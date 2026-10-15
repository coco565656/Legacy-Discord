//
//  DLDirectMessageController.h
//  Legacy Discord
//

#import <Cocoa/Cocoa.h>

@class DLDirectMessageController;
@class DLChannel;
@class DLChannelNavigationController;
@class ChatScrollView;

@protocol DLDirectMessageControllerDelegate <NSObject>
-(void)directMessageController:(DLDirectMessageController *)controller didSelectChannel:(DLChannel *)channel;
@end

@interface DLDirectMessageController : NSObject {
    id<DLDirectMessageControllerDelegate> delegate;
    NSView *hostView;
    ChatScrollView *chatScrollView;
    NSView *composerView;
    NSTextField *chatHeaderLabel;
    NSImageView *chatHeaderImage;
    NSTextField *navigationTitleLabel;
    NSSplitView *mainSplitView;
    NSView *channelPaneView;
    DLChannelNavigationController *channelNavigationController;
    NSView *friendsHomeView;
    NSScrollView *friendsHomeScrollView;
    NSTextField *friendsTitleField;
    NSTextField *friendsSubtitleField;
    NSArray *friendsHomeChannels;
    NSInteger friendsTab;
    NSMutableArray *friendsTabButtons;
    NSMutableArray *friendRowItems;
    NSMutableDictionary *friendUsers;
    BOOL compactLayout;
    CGFloat expandedChannelPaneWidth;
}

-(id)initWithHostView:(NSView *)hostView
       chatScrollView:(ChatScrollView *)chatScrollView
         composerView:(NSView *)composerView
      chatHeaderLabel:(NSTextField *)chatHeaderLabel
      chatHeaderImage:(NSImageView *)chatHeaderImage
 navigationTitleLabel:(NSTextField *)navigationTitleLabel
        mainSplitView:(NSSplitView *)mainSplitView
      channelPaneView:(NSView *)channelPaneView
channelNavigationController:(DLChannelNavigationController *)channelNavigationController;
-(void)setDelegate:(id<DLDirectMessageControllerDelegate>)delegate;
-(void)displayDirectMessageChannels:(NSArray *)channels;
-(void)showFriendsHomeWithChannels:(NSArray *)channels;
-(void)hideFriendsHome;
// Rebuilds the Friends list after relationships or presences changed.
-(void)relationshipsDidUpdate;
-(void)channelImageDidUpdate:(DLChannel *)channel;
-(void)updateResponsiveLayoutForWindowWidth:(CGFloat)width showingDirectMessages:(BOOL)showingDirectMessages;
-(void)restoreExpandedLayout;
-(CGFloat)minimumSplitCoordinate;
-(void)applyCurrentTheme;

@end
