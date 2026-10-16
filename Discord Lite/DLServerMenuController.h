//
//  DLServerMenuController.h
//  Legacy Discord
//
//  The official server menu: the dropdown under the server name and the
//  right-click menu of a server icon, with the dialogs behind them (invite,
//  notification settings, create channel or category, per-server profile,
//  server overview, leave server).
//

#import <Cocoa/Cocoa.h>

@class DLServer;

@interface DLServerMenuController : NSObject {
    NSWindow *window;
}

+(DLServerMenuController *)sharedController;
// Dialogs open over this window.
-(void)setWindow:(NSWindow *)window;

// Dropdown under the server header.
-(NSMenu *)headerMenuForServer:(DLServer *)server;
// Right-click menu of a server icon in the rail.
-(NSMenu *)contextMenuForServer:(DLServer *)server;

-(void)showInviteDialogForServer:(DLServer *)server;
-(void)showNotificationSettingsForServer:(DLServer *)server;
-(void)showCreateChannelDialogForServer:(DLServer *)server category:(BOOL)category parentID:(NSString *)parentID;
-(void)showServerProfileDialogForServer:(DLServer *)server;
-(void)showServerOverviewForServer:(DLServer *)server;
-(void)showLeaveDialogForServer:(DLServer *)server;

@end
