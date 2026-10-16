//
//  DLPreferencesWindowController.h
//  Discord Lite
//
//  Created by Collin Mistr on 8/23/22.
//  Copyright (c) 2022 dosdude1. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "DLPreferencesHandler.h"

// Discord-style settings window. The XIB still provides the window and the
// legacy (hidden, unused) proxy controls; every visible view is built in code.
@interface DLPreferencesWindowController : NSWindowController {

    IBOutlet NSButton *useSOCKSCheckbox;
    IBOutlet NSTextField *hostTextField;
    IBOutlet NSTextField *portTextField;
    IBOutlet NSButton *SOCKSPasswordCheckbox;
    IBOutlet NSTextField *SOCKSUsernameTextField;
    IBOutlet NSSecureTextField *SOCKSPasswordTextField;
    IBOutlet NSButton *applyButton;
    NSPopUpButton *displayScalePopup;
    NSPopUpButton *chatFontPopup;
    NSView *contentHost;
    NSMutableArray *settingsPanes;
    NSMutableArray *settingsSidebarButtons;
    NSMutableArray *themeButtons;
    NSInteger selectedSection;
    NSTextField *cacheUsageField;
    NSButton *friendEveryoneToggle;
    NSButton *friendsOfFriendsToggle;
    NSButton *friendServerMembersToggle;
    NSArray *explicitFilterRows;
    NSArray *spoilerRows;
    NSArray *languageRows;
    NSMutableArray *accountSettingsControls;
}
- (IBAction)useProxyToggled:(id)sender;
- (IBAction)useSOCKSPasswordToggled:(id)sender;
- (IBAction)applyChanges:(id)sender;
- (IBAction)displayScaleChanged:(id)sender;
- (IBAction)themeChanged:(id)sender;
- (IBAction)showSettingsSection:(id)sender;
#if LEGACY_DISCORD_LOCAL_DEV
// DevLocal capture route: "account", "appearance", "accessibility", "chat",
// "notifications" or "advanced".
-(void)selectSettingsSectionNamed:(NSString *)name;
#endif

@end
