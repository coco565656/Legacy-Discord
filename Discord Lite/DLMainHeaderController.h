//
//  DLMainHeaderController.h
//  Legacy Discord
//

#import <Cocoa/Cocoa.h>
#import "DLWSController.h"

@class DLMainHeaderController;
@class DLMessageSearchController;
@class DLPinsController;
@class ChatScrollView;

@protocol DLMainHeaderControllerDelegate <NSObject>
-(void)mainHeaderControllerDidRequestReload:(DLMainHeaderController *)controller;
-(void)mainHeaderControllerDidRequestMemberListToggle:(DLMainHeaderController *)controller;
@end

@interface DLMainHeaderController : NSObject {
    id<DLMainHeaderControllerDelegate> delegate;
    NSView *channelHeaderView;
    NSView *chatHeaderView;
    NSTextField *serverLabel;
    NSTextField *chatHeaderLabel;
    NSView *composerView;
    ChatScrollView *chatScrollView;
    NSView *connectionStatusField;
    NSButton *reloadButton;
    NSButton *membersButton;
    NSSearchField *messageSearchField;
    NSButton *pinsButton;
    DLMessageSearchController *messageSearchController;
    DLPinsController *pinsController;
    DLWSConnectionState connectionState;
}

-(id)initWithChannelHeaderView:(NSView *)channelHeaderView
                chatHeaderView:(NSView *)chatHeaderView
                   serverLabel:(NSTextField *)serverLabel
               chatHeaderLabel:(NSTextField *)chatHeaderLabel
                chatScrollView:(ChatScrollView *)chatScrollView
                  composerView:(NSView *)composerView;
-(void)setDelegate:(id<DLMainHeaderControllerDelegate>)delegate;
-(DLMessageSearchController *)messageSearchController;
-(DLPinsController *)pinsController;
-(NSButton *)memberToggleButton;
-(NSButton *)reloadButton;
-(void)setMembersEnabled:(BOOL)enabled;
-(void)setReloadEnabled:(BOOL)enabled;
-(void)setConnectionState:(DLWSConnectionState)state;
// Channel name with its topic after a divider, like the official header.
-(void)setChannelTitle:(NSString *)title topic:(NSString *)topic;
-(void)applyCurrentTheme;

@end
