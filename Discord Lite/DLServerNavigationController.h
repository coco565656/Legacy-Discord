//
//  DLServerNavigationController.h
//  Legacy Discord
//

#import <Cocoa/Cocoa.h>
#import "DLServer.h"

@class DynamicScrollView;
@class DLServerNavigationController;

@protocol DLServerNavigationControllerDelegate <NSObject>
-(void)serverNavigationController:(DLServerNavigationController *)controller didSelectServer:(DLServer *)server;
-(void)serverNavigationControllerDidFinishDisplayingItems:(DLServerNavigationController *)controller;
@end

@interface DLServerNavigationController : NSObject <NSTableViewDataSource, NSTableViewDelegate, DLServerDelegate> {
    DynamicScrollView *scrollView;
    NSTableView *tableView;
    NSArray *serverItems;
    BOOL updatingSelection;
    id<DLServerNavigationControllerDelegate> delegate;
}

-(id)initWithScrollView:(DynamicScrollView *)inScrollView;
-(void)setDelegate:(id<DLServerNavigationControllerDelegate>)inDelegate;
-(void)displayServerItems:(NSArray *)items;
-(void)displayServerItems:(NSArray *)items selectedServer:(DLServer *)selectedServer myServer:(DLServer *)myServer;
-(void)applyCurrentTheme;

@end
