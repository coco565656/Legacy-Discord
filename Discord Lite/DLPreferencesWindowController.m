//
//  DLPreferencesWindowController.m
//  Discord Lite
//
//  Created by Collin Mistr on 8/23/22.
//  Copyright (c) 2022 dosdude1. All rights reserved.
//

#import "DLPreferencesWindowController.h"
#import "DLUtil.h"
#import "NSView+BGColor.h"

@interface DLPreferencesWindowController ()

@end

@implementation DLPreferencesWindowController

- (void)windowDidLoad {
    [super windowDidLoad];

    [self.window setTitle:@"Legacy Discord Settings"];
    NSRect windowFrame = [self.window frame];
    windowFrame.origin.y -= 123.0;
    windowFrame.size = NSMakeSize(760.0, 520.0);
    [self.window setFrame:windowFrame display:NO];
    [self.window setMinSize:NSMakeSize(680.0, 460.0)];

    NSArray *oldViews = [[[self.window contentView] subviews] copy];
    NSEnumerator *oldViewEnumerator = [oldViews objectEnumerator];
    NSView *oldView;
    while (oldView = [oldViewEnumerator nextObject]) [oldView setHidden:YES];
    [oldViews release];

    NSView_BGColor *background = [[NSView_BGColor alloc] initWithFrame:[[self.window contentView] bounds]];
    [background setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [background setBackgroundColor:[DLUtil nativeContentColor]];
    [[self.window contentView] addSubview:background];

    NSView_BGColor *sidebar = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0, 0.0, 210.0, 520.0)];
    [sidebar setAutoresizingMask:NSViewHeightSizable];
    [sidebar setBackgroundColor:[DLUtil nativeSidebarColor]];
    [background addSubview:sidebar];

    NSTextField *brand = [self labelWithFrame:NSMakeRect(20.0, 474.0, 174.0, 24.0)
                                         text:@"Legacy Discord"
                                         font:[NSFont boldSystemFontOfSize:17.0]
                                        color:[DLUtil nativePrimaryTextColor]];
    [sidebar addSubview:brand];
    NSTextField *caption = [self labelWithFrame:NSMakeRect(20.0, 453.0, 174.0, 17.0)
                                           text:@"USER SETTINGS"
                                           font:[NSFont boldSystemFontOfSize:10.0]
                                          color:[DLUtil nativeSecondaryTextColor]];
    [sidebar addSubview:caption];

    settingsSidebarButtons = [[NSMutableArray alloc] init];
    NSArray *sections = [NSArray arrayWithObjects:@"Appearance", @"Account", @"Privacy & Safety", @"Notifications", @"Voice & Video", @"Advanced", nil];
    for (NSInteger index = 0; index < (NSInteger)[sections count]; index++) {
        NSButton *button = [[[NSButton alloc] initWithFrame:NSMakeRect(14.0, 410.0 - index * 40.0, 182.0, 32.0)] autorelease];
        [button setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
        [button setBordered:NO];
        [button setAlignment:NSLeftTextAlignment];
        [button setFont:[NSFont boldSystemFontOfSize:13.0]];
        [button setTitle:[sections objectAtIndex:index]];
        NSDictionary *sidebarAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                             [NSFont boldSystemFontOfSize:13.0], NSFontAttributeName,
                                             [DLUtil nativePrimaryTextColor], NSForegroundColorAttributeName, nil];
        [button setAttributedTitle:[[[NSAttributedString alloc] initWithString:[sections objectAtIndex:index]
                                                                          attributes:sidebarAttributes] autorelease]];
        [button setTag:index];
        [button setTarget:self];
        [button setAction:@selector(showSettingsSection:)];
        [button setToolTip:(index == 0 ? @"Display scale and theme" : @"Coming soon in a future release")];
        [sidebar addSubview:button];
        [settingsSidebarButtons addObject:button];
    }

    NSButton *logoutHint = [[[NSButton alloc] initWithFrame:NSMakeRect(14.0, 20.0, 182.0, 32.0)] autorelease];
    [logoutHint setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
    [logoutHint setBordered:NO];
    [logoutHint setEnabled:NO];
    [logoutHint setAlignment:NSLeftTextAlignment];
    [logoutHint setTitle:@"Log Out — user menu"];
    [sidebar addSubview:logoutHint];

    appearancePane = [[NSView alloc] initWithFrame:NSMakeRect(210.0, 0.0, 550.0, 520.0)];
    [appearancePane setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [background addSubview:appearancePane];
    NSTextField *title = [self labelWithFrame:NSMakeRect(38.0, 464.0, 450.0, 30.0)
                                         text:@"Appearance"
                                         font:[NSFont boldSystemFontOfSize:22.0]
                                        color:[DLUtil nativePrimaryTextColor]];
    [appearancePane addSubview:title];
    NSTextField *scaleTitle = [self labelWithFrame:NSMakeRect(40.0, 405.0, 300.0, 22.0)
                                              text:@"Message display scale"
                                              font:[NSFont boldSystemFontOfSize:15.0]
                                             color:[DLUtil nativePrimaryTextColor]];
    [appearancePane addSubview:scaleTitle];
    NSTextField *scaleHelp = [self labelWithFrame:NSMakeRect(40.0, 383.0, 450.0, 18.0)
                                             text:@"Adjust message text, avatars, and spacing."
                                             font:[NSFont systemFontOfSize:11.0]
                                            color:[DLUtil nativeSecondaryTextColor]];
    [appearancePane addSubview:scaleHelp];

    displayScalePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(38.0, 341.0, 260.0, 28.0) pullsDown:NO];
    NSArray *titles = [NSArray arrayWithObjects:@"Small (80%)", @"Compact (90%)", @"Default (100%)", @"Large (110%)", @"Larger (125%)", nil];
    NSArray *tags = [NSArray arrayWithObjects:[NSNumber numberWithInt:80], [NSNumber numberWithInt:90], [NSNumber numberWithInt:100], [NSNumber numberWithInt:110], [NSNumber numberWithInt:125], nil];
    for (NSInteger index = 0; index < (NSInteger)[titles count]; index++) {
        [displayScalePopup addItemWithTitle:[titles objectAtIndex:index]];
        [[displayScalePopup itemAtIndex:index] setTag:[[tags objectAtIndex:index] integerValue]];
    }
    [displayScalePopup setTarget:self];
    [displayScalePopup setAction:@selector(displayScaleChanged:)];
    [appearancePane addSubview:displayScalePopup];

    NSTextField *themeTitle = [self labelWithFrame:NSMakeRect(40.0, 284.0, 300.0, 22.0)
                                              text:@"Theme"
                                              font:[NSFont boldSystemFontOfSize:15.0]
                                             color:[DLUtil nativePrimaryTextColor]];
    [appearancePane addSubview:themeTitle];
    NSTextField *themeHelp = [self labelWithFrame:NSMakeRect(40.0, 262.0, 460.0, 18.0)
                                             text:@"Lightweight AppKit palettes — no Nitro requirement."
                                             font:[NSFont systemFontOfSize:11.0]
                                            color:[DLUtil nativeSecondaryTextColor]];
    [appearancePane addSubview:themeHelp];
    NSArray *themeTitles = [NSArray arrayWithObjects:@"Default", @"Midnight", @"Aurora gradient", nil];
    for (NSInteger index = 0; index < 3; index++) {
        NSButton *themeButton = [[[NSButton alloc] initWithFrame:NSMakeRect(38.0 + index * 150.0, 208.0, 138.0, 36.0)] autorelease];
        [themeButton setBezelStyle:NSRoundRectBezelStyle];
        [themeButton setTitle:[themeTitles objectAtIndex:index]];
        [themeButton setTag:index];
        [themeButton setTarget:self];
        [themeButton setAction:@selector(themeChanged:)];
        [appearancePane addSubview:themeButton];
    }
    NSTextField *betaNote = [self labelWithFrame:NSMakeRect(40.0, 112.0, 455.0, 48.0)
                                            text:@"Changes are saved immediately. Aurora uses native gradients compatible with Snow Leopard through Mountain Lion."
                                            font:[NSFont systemFontOfSize:11.0]
                                           color:[DLUtil nativeSecondaryTextColor]];
    [[betaNote cell] setWraps:YES];
    [appearancePane addSubview:betaNote];

    comingSoonPane = [[NSView alloc] initWithFrame:[appearancePane frame]];
    [comingSoonPane setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    comingSoonTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(30.0, 225.0, 490.0, 70.0)];
    [comingSoonTitle setBezeled:NO];
    [comingSoonTitle setDrawsBackground:NO];
    [comingSoonTitle setEditable:NO];
    [comingSoonTitle setSelectable:NO];
    [comingSoonTitle setAlignment:NSCenterTextAlignment];
    [comingSoonTitle setFont:[NSFont boldSystemFontOfSize:20.0]];
    [comingSoonTitle setTextColor:[DLUtil nativePrimaryTextColor]];
    [[comingSoonTitle cell] setWraps:YES];
    [comingSoonPane addSubview:comingSoonTitle];
    [background addSubview:comingSoonPane];
    [comingSoonPane setHidden:YES];

    [self initPreferences];
    [background release];
    [sidebar release];
}

-(NSTextField *)labelWithFrame:(NSRect)frame text:(NSString *)text font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setStringValue:text];
    [label setFont:font];
    [label setTextColor:color];
    return label;
}

-(void)initPreferences {
    if ([[DLPreferencesHandler sharedInstance] shouldUseSOCKSProxy]) {
        [useSOCKSCheckbox setState:NSOnState];
    }
    if ([[DLPreferencesHandler sharedInstance] SOCKSProxyRequiresPassword]) {
        [SOCKSPasswordCheckbox setState:NSOnState];
    }
    
    if ([[DLPreferencesHandler sharedInstance] SOCKSProxyHost]) {
        [hostTextField setStringValue:[[DLPreferencesHandler sharedInstance] SOCKSProxyHost]];
    }
    if ([[DLPreferencesHandler sharedInstance] SOCKSProxyPort]) {
        [portTextField setStringValue:[NSString stringWithFormat:@"%ld", [[DLPreferencesHandler sharedInstance] SOCKSProxyPort]]];
    }
    if ([[DLPreferencesHandler sharedInstance] SOCKSProxyUsername]) {
        [SOCKSUsernameTextField setStringValue:[[DLPreferencesHandler sharedInstance] SOCKSProxyUsername]];
    }
    if ([[DLPreferencesHandler sharedInstance] SOCKSProxyPassword]) {
        [SOCKSPasswordTextField setStringValue:[[DLPreferencesHandler sharedInstance] SOCKSProxyPassword]];
    }
    NSInteger scaleTag = (NSInteger)round([[DLPreferencesHandler sharedInstance] messageDisplayScale] * 100.0);
    [displayScalePopup selectItemWithTag:scaleTag];
}

-(void)updateUIState {
    if (useSOCKSCheckbox.state == NSOnState) {
        [hostTextField setEnabled:YES];
        [portTextField setEnabled:YES];
        [SOCKSPasswordCheckbox setEnabled:YES];
    } else {
        [hostTextField setEnabled:NO];
        [portTextField setEnabled:NO];
        [SOCKSPasswordCheckbox setEnabled:NO];
    }
    
    if (SOCKSPasswordCheckbox.state == NSOnState) {
        [SOCKSUsernameTextField setEnabled:YES];
        [SOCKSPasswordTextField setEnabled:YES];
    } else {
        [SOCKSUsernameTextField setEnabled:NO];
        [SOCKSPasswordTextField setEnabled:NO];
    }
}

- (IBAction)useProxyToggled:(id)sender {
    [self updateUIState];
}

- (IBAction)useSOCKSPasswordToggled:(id)sender {
    [self updateUIState];
}

- (IBAction)applyChanges:(id)sender {
    if (useSOCKSCheckbox.state == NSOnState) {
        [[DLPreferencesHandler sharedInstance] setShouldUseSOCKSProxy:YES];
    } else {
        [[DLPreferencesHandler sharedInstance] setShouldUseSOCKSProxy:NO];
    }
    
    if (SOCKSPasswordCheckbox.state == NSOnState) {
        [[DLPreferencesHandler sharedInstance] setSOCKSProxyRequiresPassword:YES];
    } else {
        [[DLPreferencesHandler sharedInstance] setSOCKSProxyRequiresPassword:NO];
    }
    
    [[DLPreferencesHandler sharedInstance] setSOCKSProxyHost:[hostTextField stringValue]];
    [[DLPreferencesHandler sharedInstance] setSOCKSProxyPort:[[portTextField stringValue] intValue]];
    [[DLPreferencesHandler sharedInstance] setSOCKSProxyUsername:[SOCKSUsernameTextField stringValue]];
    [[DLPreferencesHandler sharedInstance] setSOCKSProxyPassword:[SOCKSPasswordTextField stringValue]];
    [[DLPreferencesHandler sharedInstance] setMessageDisplayScale:(CGFloat)[[displayScalePopup selectedItem] tag] / 100.0];
    
    [self.window close];
    
}

- (IBAction)displayScaleChanged:(id)sender {
    [[DLPreferencesHandler sharedInstance] setMessageDisplayScale:(CGFloat)[[displayScalePopup selectedItem] tag] / 100.0];
}

- (IBAction)themeChanged:(id)sender {
    NSArray *themes = [NSArray arrayWithObjects:@"default", @"midnight", @"aurora", nil];
    NSInteger index = [(NSButton *)sender tag];
    if (index >= 0 && index < (NSInteger)[themes count]) {
        [[DLPreferencesHandler sharedInstance] setAppearanceTheme:[themes objectAtIndex:index]];
    }
}

- (IBAction)showSettingsSection:(id)sender {
    NSInteger section = [(NSButton *)sender tag];
    [appearancePane setHidden:(section != 0)];
    [comingSoonPane setHidden:(section == 0)];
    if (section != 0) {
        [comingSoonTitle setStringValue:[NSString stringWithFormat:@"%@\nComing soon…", [(NSButton *)sender title]]];
    }
}

-(void)dealloc {
    [displayScalePopup release];
    [appearancePane release];
    [comingSoonTitle release];
    [comingSoonPane release];
    [settingsSidebarButtons release];
    [super dealloc];
}
@end
