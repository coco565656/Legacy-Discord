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
@class DLChannel;

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

// Channel and category menu pieces (used by the channel list).
-(void)showInviteDialogForServer:(DLServer *)server channel:(DLChannel *)channel;
-(void)showEditChannelDialogForChannel:(DLChannel *)channel;
-(void)showDeleteChannelDialogForChannel:(DLChannel *)channel;
// "Notification Settings" submenu with the channel's override.
-(NSMenuItem *)notificationItemForChannel:(DLChannel *)channel;
// Own permission in a channel (categories and channels use their overwrites).
-(BOOL)hasPermission:(unsigned long long)permission inChannel:(DLChannel *)channel;

@end
