//
//  DLPinsController.h
//  Legacy Discord
//

#import <Cocoa/Cocoa.h>

@class DLPinsController;
@class DLMessageSearchController;
@class DLChannel;

@protocol DLPinsControllerDelegate <NSObject>
-(BOOL)pinsControllerMayOpen:(DLPinsController *)controller;
@end

@interface DLPinsController : NSObject {
    id<DLPinsControllerDelegate> delegate;
    NSButton *button;
    DLMessageSearchController *searchController;
    BOOL active;
}
-(id)initWithButton:(NSButton *)button searchController:(DLMessageSearchController *)searchController;
-(void)setDelegate:(id<DLPinsControllerDelegate>)delegate;
-(void)setEnabled:(BOOL)enabled;
-(void)close;
-(void)deactivate;
-(void)channelPins:(NSArray *)messages didLoadForChannel:(DLChannel *)channel;
-(void)requestDidFail;
@end
