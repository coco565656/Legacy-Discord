//
//  DLLoginWindowController.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/26/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLLoginWindowController.h"
#import "DLLocalization.h"
#import "DLUtil.h"
#import "NSView+BGColor.h"
#import "DLMainWindowChromeControls.h"

@interface DLLoginWindowController ()

@end

@implementation DLLoginWindowController

- (void)windowDidLoad {
    [super windowDidLoad];
    [DLLocalization localizeWindow:self.window];
    [self.window setTitle:DLLocalizedString(@"Legacy Discord — Login")];
    NSRect frame = [self.window frame];
    frame.size = NSMakeSize(440.0, 452.0);
    [self.window setFrame:frame display:NO];
    [DLDarkTitlebarView installInWindow:self.window];

    NSView *content = [self.window contentView];
    NSArray *oldViews = [[content subviews] copy];
    for (NSView *view in oldViews) [view setHidden:YES];
    [oldViews release];

    // Laid out like the official login: blurple backdrop, a dark card with
    // "Welcome back!", labelled inputs and a full-width Log In button.
    NSView_BGColor *background = [[NSView_BGColor alloc] initWithFrame:[content bounds]];
    [background setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [background setBackgroundColor:[NSColor colorWithCalibratedRed:0.345 green:0.396 blue:0.949 alpha:1.0]];
    [content addSubview:background];

    NSView_BGColor *card = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(32.0, 30.0, 376.0, 370.0)];
    [card setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin];
    [card setBackgroundColor:[DLUtil nativeContentColor]];
    [background addSubview:card];

    [card addSubview:[self loginLabelWithFrame:NSMakeRect(24.0, 316.0, 328.0, 30.0)
                                          text:DLLocalizedString(@"Welcome back!")
                                          font:[NSFont boldSystemFontOfSize:22.0]
                                         color:[DLUtil nativePrimaryTextColor]
                                     alignment:NSCenterTextAlignment]];
    [card addSubview:[self loginLabelWithFrame:NSMakeRect(24.0, 292.0, 328.0, 20.0)
                                          text:DLLocalizedString(@"We're so excited to see you again!")
                                          font:[NSFont systemFontOfSize:13.0]
                                         color:[DLUtil nativeSecondaryTextColor]
                                     alignment:NSCenterTextAlignment]];
    [card addSubview:[self loginLabelWithFrame:NSMakeRect(24.0, 254.0, 328.0, 16.0)
                                          text:DLLocalizedString(@"EMAIL OR PHONE NUMBER")
                                          font:[NSFont boldSystemFontOfSize:10.0]
                                         color:[DLUtil nativeSecondaryTextColor]
                                     alignment:NSLeftTextAlignment]];
    [card addSubview:[self loginLabelWithFrame:NSMakeRect(24.0, 186.0, 328.0, 16.0)
                                          text:DLLocalizedString(@"PASSWORD")
                                          font:[NSFont boldSystemFontOfSize:10.0]
                                         color:[DLUtil nativeSecondaryTextColor]
                                     alignment:NSLeftTextAlignment]];

    NSTextField *fields[2] = { emailField, passwordField };
    CGFloat fieldY[2] = { 218.0, 150.0 };
    for (NSUInteger index = 0; index < 2; index++) {
        NSTextField *field = fields[index];
        [field retain]; [field removeFromSuperviewWithoutNeedingDisplay];
        [field setFrame:NSMakeRect(24.0, fieldY[index], 328.0, 30.0)];
        [field setHidden:NO];
        [field setBezeled:NO];
        [field setBordered:NO];
        [field setDrawsBackground:YES];
        [field setBackgroundColor:[DLUtil nativeServerRailColor]];
        [field setTextColor:[DLUtil nativePrimaryTextColor]];
        [field setFont:[NSFont systemFontOfSize:14.0]];
        [card addSubview:field]; [field release];
    }

    // The XIB's Aqua buttons stay hidden; Discord-style buttons take over
    // their actions (resetUI enables/disables through the same ivars).
    DLPrimaryButton *logInButton = [[[DLPrimaryButton alloc] initWithFrame:NSMakeRect(24.0, 88.0, 328.0, 40.0)] autorelease];
    [logInButton setBordered:NO];
    [logInButton setButtonType:NSMomentaryChangeButton];
    [logInButton setTitle:DLLocalizedString(@"Log In")];
    [logInButton setTarget:self];
    [logInButton setAction:@selector(login:)];
    [logInButton setKeyEquivalent:@"\r"];
    [card addSubview:logInButton];
    [loginButton setHidden:YES];
    loginButton = logInButton;

    NSButton *tokenLink = [[[NSButton alloc] initWithFrame:NSMakeRect(24.0, 56.0, 328.0, 20.0)] autorelease];
    [tokenLink setBordered:NO];
    [tokenLink setButtonType:NSMomentaryChangeButton];
    [tokenLink setAlignment:NSLeftTextAlignment];
    [tokenLink setAttributedTitle:[[[NSAttributedString alloc] initWithString:DLLocalizedString(@"Log in with a token instead")
        attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:12.0], NSFontAttributeName,
                    [DLUtil nativeLinkColor], NSForegroundColorAttributeName, nil]] autorelease]];
    [tokenLink setTarget:self];
    [tokenLink setAction:@selector(showTokenEntryPanel:)];
    [card addSubview:tokenLink];
    [useTokenButton setHidden:YES];
    useTokenButton = tokenLink;

    [progressIndicator retain]; [progressIndicator removeFromSuperviewWithoutNeedingDisplay];
    [progressIndicator setFrame:NSMakeRect(180.0, 100.0, 16.0, 16.0)];
    [card addSubview:progressIndicator positioned:NSWindowAbove relativeTo:logInButton]; [progressIndicator release];

    NSTextField *compatibility = [self loginLabelWithFrame:NSMakeRect(24.0, 16.0, 328.0, 16.0)
                                                       text:DLLocalizedString(@"Legacy Discord · Mac OS X 10.6 – 10.8")
                                                       font:[NSFont systemFontOfSize:9.0]
                                                      color:[DLUtil nativeSecondaryTextColor]
                                                  alignment:NSCenterTextAlignment];
    [card addSubview:compatibility];
    [background release];
    [card release];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
#if !LEGACY_DISCORD_LOCAL_DEV
    [[DLController sharedInstance] setLoginDelegate:self];
#endif
}

-(NSTextField *)loginLabelWithFrame:(NSRect)frame text:(NSString *)text font:(NSFont *)font color:(NSColor *)color alignment:(NSTextAlignment)alignment {
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [label setBezeled:NO]; [label setDrawsBackground:NO]; [label setEditable:NO]; [label setSelectable:NO];
    [label setStringValue:text]; [label setFont:font]; [label setTextColor:color]; [label setAlignment:alignment];
    return label;
}

- (IBAction)login:(id)sender {
    if (![[DLController sharedInstance] authFingerprint]) {
        [[DLController sharedInstance] getAuthFingerprint];
    } else {
        [[DLController sharedInstance] loginWithEmail:[emailField stringValue] andPassword:[passwordField stringValue]];
    }
    
    [progressIndicator setHidden:NO];
    [progressIndicator startAnimation:self];
    [emailField setEnabled:NO];
    [passwordField setEnabled:NO];
    [loginButton setEnabled:NO];
    [useTokenButton setEnabled:NO];
}

- (IBAction)showTokenEntryPanel:(id)sender {
    [tokenEntryTextField setStringValue:@""];
    [NSApp beginSheet:tokenEntryPanel modalForWindow:self.window modalDelegate:nil didEndSelector:nil contextInfo:nil];
}

- (IBAction)loginWithToken:(id)sender {
    [NSApp endSheet:tokenEntryPanel];
    [tokenEntryPanel orderOut:sender];
    [[DLController sharedInstance] setToken:[tokenEntryTextField stringValue]];
    [delegate loginWasSuccessful];
}

- (IBAction)dismissTokenEntryPanel:(id)sender {
    [NSApp endSheet:tokenEntryPanel];
    [tokenEntryPanel orderOut:sender];
}

-(void)setDelegate:(id<DLLoginWindowDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)resetUI {
    [progressIndicator stopAnimation:self];
    [progressIndicator setHidden:YES];
    [emailField setEnabled:YES];
    [passwordField setEnabled:YES];
    [loginButton setEnabled:YES];
    [useTokenButton setEnabled:YES];
}

-(void)dealloc {
    [captchaWindow release];
    [twoFactorWindow release];
    [super dealloc];
}

#pragma mark Delegated Functions

-(void)didLoginWithError:(DLError *)e {
    [self resetUI];
    if (e) {
        [DLErrorHandler displayError:e onWindow:self.window];
    } else {
        [delegate loginWasSuccessful];
    }
    
}

-(void)didReceiveCaptchaRequestOfType:(NSString *)captchaType withSiteKey:(NSString *)siteKey {
    if (!captchaWindow) {
        captchaWindow = [[DLCaptchaWindowController alloc] initWithWindowNibName:@"DLCaptchaWindowController"];
        [captchaWindow setDelegate:self];
    }
    [captchaWindow showWindow:captchaWindow.window];
    if ([captchaType isEqualToString:@"hcaptcha"]) {
        [captchaWindow loadHCaptchaWithSiteKey:siteKey];
    } else if ([captchaType isEqualToString:@"recaptcha"]) {
        [captchaWindow loadRecaptchaWithSiteKey:siteKey];
    }
}

-(void)didReceiveTwoFactorAuthRequest {
    if (!twoFactorWindow) {
        twoFactorWindow = [[DLTwoFactorWindowController alloc] initWithWindowNibName:@"DLTwoFactorWindowController"];
        [twoFactorWindow setDelegate:self];
    }
    [twoFactorWindow clear];
    [NSApp beginSheet:twoFactorWindow.window modalForWindow:self.window modalDelegate:nil didEndSelector:nil contextInfo:nil];
}

-(void)didReceiveAuthFingerprint:(NSString *)fingerprint {
    [[DLController sharedInstance] loginWithEmail:[emailField stringValue] andPassword:[passwordField stringValue]];
}
-(void)authFingerprintFailedWithError:(DLError *)e {
    [self resetUI];
    [DLErrorHandler displayError:e onWindow:self.window];
}

#pragma mark CaptchaDelegate

-(void)didCompleteCaptchaSuccessfully:(BOOL)success {
    if (success) {
        [[DLController sharedInstance] loginWithEmail:[emailField stringValue] andPassword:[passwordField stringValue]];
    } else {
        [self resetUI];
    }
}

#pragma mark TwoFactorDelegate

-(void)didSubmitTwoFactorWithCode:(NSString *)twoFactorCode {
    [NSApp endSheet:twoFactorWindow.window];
    [twoFactorWindow.window orderOut:self];
    [[DLController sharedInstance] loginWithTwoFactorAuthCode:twoFactorCode];
}
-(void)didCancelTwoFactorEntry {
    [NSApp endSheet:twoFactorWindow.window];
    [twoFactorWindow.window orderOut:self];
    [self resetUI];
}

@end
