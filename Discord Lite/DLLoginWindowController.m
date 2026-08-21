//
//  DLLoginWindowController.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/26/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLLoginWindowController.h"
#import "DLUtil.h"
#import "NSView+BGColor.h"

@interface DLLoginWindowController ()

@end

@implementation DLLoginWindowController

- (void)windowDidLoad {
    [super windowDidLoad];
    [self.window setTitle:@"Legacy Discord — Login"];
    NSRect frame = [self.window frame];
    frame.size = NSMakeSize(440.0, 430.0);
    [self.window setFrame:frame display:NO];

    NSView *content = [self.window contentView];
    NSArray *oldViews = [[content subviews] copy];
    for (NSView *view in oldViews) [view setHidden:YES];
    [oldViews release];

    NSView_BGColor *background = [[NSView_BGColor alloc] initWithFrame:[content bounds]];
    [background setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [background setGradientStartColor:[DLUtil nativeHeaderTopColor] endColor:[DLUtil nativeServerRailColor]];
    [content addSubview:background];

    NSView_BGColor *card = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(42.0, 36.0, 356.0, 350.0)];
    [card setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin];
    [card setBackgroundColor:[DLUtil nativeContentColor]];
    [background addSubview:card];

    NSTextField *brand = [self loginLabelWithFrame:NSMakeRect(26.0, 292.0, 304.0, 34.0)
                                              text:@"Legacy Discord"
                                              font:[NSFont boldSystemFontOfSize:25.0]
                                             color:[DLUtil nativePrimaryTextColor]
                                         alignment:NSCenterTextAlignment];
    [card addSubview:brand];
    NSTextField *welcome = [self loginLabelWithFrame:NSMakeRect(26.0, 262.0, 304.0, 22.0)
                                                text:@"Welcome back — sign in to continue"
                                                font:[NSFont systemFontOfSize:12.0]
                                               color:[DLUtil nativeSecondaryTextColor]
                                           alignment:NSCenterTextAlignment];
    [card addSubview:welcome];

    NSTextField *emailLabel = [self loginLabelWithFrame:NSMakeRect(30.0, 224.0, 296.0, 18.0)
                                                   text:@"EMAIL ADDRESS"
                                                   font:[NSFont boldSystemFontOfSize:10.0]
                                                  color:[DLUtil nativeSecondaryTextColor]
                                              alignment:NSLeftTextAlignment];
    [card addSubview:emailLabel];
    NSTextField *passwordLabel = [self loginLabelWithFrame:NSMakeRect(30.0, 151.0, 296.0, 18.0)
                                                      text:@"PASSWORD"
                                                      font:[NSFont boldSystemFontOfSize:10.0]
                                                     color:[DLUtil nativeSecondaryTextColor]
                                                 alignment:NSLeftTextAlignment];
    [card addSubview:passwordLabel];

    [emailField retain]; [emailField removeFromSuperviewWithoutNeedingDisplay];
    [emailField setFrame:NSMakeRect(30.0, 190.0, 296.0, 28.0)];
    [emailField setHidden:NO];
    [emailField setBackgroundColor:[DLUtil nativeInputColor]];
    [emailField setTextColor:[DLUtil nativePrimaryTextColor]];
    [card addSubview:emailField]; [emailField release];
    [passwordField retain]; [passwordField removeFromSuperviewWithoutNeedingDisplay];
    [passwordField setFrame:NSMakeRect(30.0, 117.0, 296.0, 28.0)];
    [passwordField setHidden:NO];
    [passwordField setBackgroundColor:[DLUtil nativeInputColor]];
    [passwordField setTextColor:[DLUtil nativePrimaryTextColor]];
    [card addSubview:passwordField]; [passwordField release];

    [loginButton retain]; [loginButton removeFromSuperviewWithoutNeedingDisplay];
    [loginButton setFrame:NSMakeRect(218.0, 55.0, 108.0, 34.0)];
    [loginButton setTitle:@"Sign In"];
    [loginButton setHidden:NO];
    [card addSubview:loginButton]; [loginButton release];
    [useTokenButton retain]; [useTokenButton removeFromSuperviewWithoutNeedingDisplay];
    [useTokenButton setFrame:NSMakeRect(25.0, 55.0, 125.0, 34.0)];
    [useTokenButton setTitle:@"Use Token…"];
    [useTokenButton setHidden:NO];
    [card addSubview:useTokenButton]; [useTokenButton release];
    [progressIndicator retain]; [progressIndicator removeFromSuperviewWithoutNeedingDisplay];
    [progressIndicator setFrame:NSMakeRect(194.0, 64.0, 16.0, 16.0)];
    [card addSubview:progressIndicator]; [progressIndicator release];

    NSTextField *compatibility = [self loginLabelWithFrame:NSMakeRect(30.0, 18.0, 296.0, 18.0)
                                                       text:@"Built for OS X Mountain Lion and Mavericks"
                                                       font:[NSFont systemFontOfSize:9.0]
                                                      color:[DLUtil nativeSecondaryTextColor]
                                                  alignment:NSCenterTextAlignment];
    [card addSubview:compatibility];
    [background release];
    [card release];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    [[DLController sharedInstance] setLoginDelegate:self];
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
