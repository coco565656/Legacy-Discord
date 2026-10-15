//
//  DLChannelNavigationController.h
//  Legacy Discord
//

#import <Cocoa/Cocoa.h>
#import "DLChannel.h"

@class DynamicScrollView;
@class DLChannelNavigationController;

@protocol DLChannelNavigationControllerDelegate <NSObject>
-(void)channelNavigationController:(DLChannelNavigationController *)controller didSelectChannel:(DLChannel *)channel;
-(void)channelNavigationController:(DLChannelNavigationController *)controller
          didFinishDisplayingItems:(NSArray *)items
             showingDirectMessages:(BOOL)showingDirectMessages
                    selectedChannel:(DLChannel *)selectedChannel;
-(void)channelNavigationController:(DLChannelNavigationController *)controller
       imageDidUpdateWithData:(NSData *)data
                   forChannel:(DLChannel *)channel;
@end

@interface DLChannelNavigationController : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate, DLChannelDelegate> {
    DynamicScrollView *scrollView;
    NSOutlineView *outlineView;
    NSArray *channelItems;
    BOOL updatingSelection;
    id<DLChannelNavigationControllerDelegate> delegate;
}

-(id)initWithScrollView:(DynamicScrollView *)inScrollView;
-(void)setDelegate:(id<DLChannelNavigationControllerDelegate>)inDelegate;
-(void)displayChannelItems:(NSArray *)items;
-(void)displayChannelItems:(NSArray *)items
     showingDirectMessages:(BOOL)showingDirectMessages
            selectedChannel:(DLChannel *)selectedChannel;
-(void)selectChannelWithoutNotifying:(DLChannel *)channel;
-(void)applyCurrentTheme;

@end
