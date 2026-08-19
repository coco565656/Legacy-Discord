//
//  DLPreferencesWindowController.m
//  Discord Lite
//
//  Created by Collin Mistr on 8/23/22.
//  Copyright (c) 2022 dosdude1. All rights reserved.
//

#import "DLPreferencesWindowController.h"

@interface DLPreferencesWindowController ()

@end

@implementation DLPreferencesWindowController

- (void)windowDidLoad {
    [super windowDidLoad];

    NSRect windowFrame = [self.window frame];
    windowFrame.origin.y -= 66.0;
    windowFrame.size.height += 66.0;
    [self.window setFrame:windowFrame display:NO];
    NSTextField *displayLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(18, 42, 110, 17)];
    [displayLabel setBordered:NO];
    [displayLabel setDrawsBackground:NO];
    [displayLabel setEditable:NO];
    [displayLabel setStringValue:@"Message size:"];
    [[self.window contentView] addSubview:displayLabel];
    [displayLabel release];
    displayScalePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(128, 36, 205, 26) pullsDown:NO];
    NSArray *titles = [NSArray arrayWithObjects:@"Small (80%)", @"Compact (90%)", @"Default (100%)", @"Large (110%)", @"Larger (125%)", nil];
    NSArray *tags = [NSArray arrayWithObjects:[NSNumber numberWithInt:80], [NSNumber numberWithInt:90], [NSNumber numberWithInt:100], [NSNumber numberWithInt:110], [NSNumber numberWithInt:125], nil];
    for (NSInteger index = 0; index < (NSInteger)[titles count]; index++) {
        [displayScalePopup addItemWithTitle:[titles objectAtIndex:index]];
        [[displayScalePopup itemAtIndex:index] setTag:[[tags objectAtIndex:index] integerValue]];
    }
    [[self.window contentView] addSubview:displayScalePopup];
    [self initPreferences];
    [self updateUIState];
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
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

-(void)dealloc {
    [displayScalePopup release];
    [super dealloc];
}
@end
