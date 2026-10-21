//
//  AppDelegate.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/26/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "AppDelegate.h"
#import "DLLocalization.h"
#import "DLUtil.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

#if LEGACY_DISCORD_UI_DIAGNOSTICS
- (void)saveSanitizedUIDiagnostics:(id)sender {
    NSString *path = [mainWindow writeSanitizedUIDiagnostics];
    if (path) NSLog(@"Sanitized UI diagnostics written to %@", path);
    else NSLog(@"Unable to write sanitized UI diagnostics.");
}
#endif

#if LEGACY_DISCORD_LOCAL_DEV
- (NSString *)localFixtureNameFromLaunchArguments {
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];
    NSUInteger index = [arguments indexOfObject:@"--fixture"];
    if (index != NSNotFound && index + 1 < [arguments count]) return [arguments objectAtIndex:index + 1];
    return @"channel-basic";
}
- (NSString *)localScreenshotPathFromLaunchArguments {
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];
    NSUInteger index = [arguments indexOfObject:@"--screenshot"];
    if (index != NSNotFound && index + 1 < [arguments count]) return [arguments objectAtIndex:index + 1];
    return nil;
}
- (BOOL)localDiagnosticsRequestedFromLaunchArguments {
    return [[[NSProcessInfo processInfo] arguments] containsObject:@"--write-sanitized-ui-diagnostics"];
}
- (NSSize)localWindowSizeFromLaunchArguments {
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];
    NSUInteger index = [arguments indexOfObject:@"--window-size"];
    if (index == NSNotFound || index + 1 >= [arguments count]) return NSMakeSize(960, 640);
    NSString *value = [arguments objectAtIndex:index + 1];
    NSRange separator = [value rangeOfString:@"x"];
    if (separator.location == NSNotFound) return NSMakeSize(960, 640);
    CGFloat width = [[value substringToIndex:separator.location] doubleValue];
    CGFloat height = [[value substringFromIndex:separator.location + 1] doubleValue];
    if (width < 720 || height < 520) return NSMakeSize(960, 640);
    return NSMakeSize(width, height);
}
- (void)captureLocalFixtureScreenshot:(NSString *)path {
    NSWindowController *captureController = (preferencesWindow && [[preferencesWindow window] isVisible]) ? (NSWindowController *)preferencesWindow
        : ((loginWindow && [[loginWindow window] isVisible]) ? (NSWindowController *)loginWindow : nil);
    if (captureController) {
        NSView *content = [[captureController window] contentView];
        NSBitmapImageRep *image = [content bitmapImageRepForCachingDisplayInRect:[content bounds]];
        [content cacheDisplayInRect:[content bounds] toBitmapImageRep:image];
        if (![[image representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]] writeToFile:path atomically:YES]) {
            NSLog(@"Unable to save settings screenshot to %@", path);
        }
        [NSApp terminate:nil];
        return;
    }
    if (![mainWindow captureLocalReplayPNGToPath:path]) {
        NSLog(@"Unable to save local replay screenshot to %@", path);
        return;
    }
    [NSApp terminate:nil];
}
#endif

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [DLLocalization localizeMenu:[NSApp mainMenu]];
    NSMenuItem *applicationMenuItem = [[NSApp mainMenu] itemAtIndex:0];
    NSMenuItem *preferencesItem = [[applicationMenuItem submenu] itemWithTitle:DLLocalizedString(@"Preferences…")];
    [preferencesItem setTarget:self];
    [preferencesItem setAction:@selector(showPreferencesWindow:)];
#if LEGACY_DISCORD_UI_DIAGNOSTICS
    NSMenu *applicationMenu = [applicationMenuItem submenu];
    NSMenuItem *diagnosticsItem = [[NSMenuItem alloc] initWithTitle:@"Save Sanitized UI Diagnostics" action:@selector(saveSanitizedUIDiagnostics:) keyEquivalent:@""];
    [diagnosticsItem setTarget:self];
    [applicationMenu addItem:[NSMenuItem separatorItem]];
    [applicationMenu addItem:diagnosticsItem];
    [diagnosticsItem release];
#endif

    //[NSURLProtocol registerClass:[DLURLProtocol class]];
    
#if LEGACY_DISCORD_LOCAL_DEV
    // --dump-client-identity: write the client description and API headers
    // the app sends (no network use, no token) to stdout, then quit.
    if ([[[NSProcessInfo processInfo] arguments] containsObject:@"--dump-client-identity"]) {
        NSMutableDictionary *dump = [NSMutableDictionary dictionary];
        [dump setObject:[DLUtil clientProperties] forKey:@"identify_properties_and_super_properties"];
        [dump setObject:[DLUtil userAgentString] forKey:@"user_agent"];
        [dump setObject:[DLUtil superPropertiesString] forKey:@"x_super_properties"];
        [dump setObject:[DLUtil defaultHTTPPostHeaders] forKey:@"api_headers"];
        NSData *json = [[CJSONSerializer serializer] serializeDictionary:dump error:nil];
        fprintf(stdout, "%s\n", [[[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] autorelease] UTF8String]);
        fflush(stdout);
        exit(0);
    }
    mainWindow = [[DLMainWindowController alloc] initWithWindowNibName:@"DLMainWindowController"];
    [mainWindow setDelegate:self];
    [mainWindow showWindow:self];
    NSString *fixtureName = [self localFixtureNameFromLaunchArguments];
    [mainWindow showLocalReplayFixtureNamed:fixtureName
                                 windowSize:[self localWindowSizeFromLaunchArguments]];
    // "settings-<section>" opens the production settings window on that section.
    // "login-screen" opens the production login window (no network use).
    if ([fixtureName isEqualToString:@"login-screen"]) {
        loginWindow = [[DLLoginWindowController alloc] initWithWindowNibName:@"DLLoginWindowController"];
        [loginWindow showWindow:self];
    }
    if ([fixtureName hasPrefix:@"settings-"]) {
        preferencesWindow = [[DLPreferencesWindowController alloc] initWithWindowNibName:@"DLPreferencesWindowController"];
        [preferencesWindow showWindow:self];
        [preferencesWindow selectSettingsSectionNamed:[fixtureName substringFromIndex:[@"settings-" length]]];
    }
    if ([self localDiagnosticsRequestedFromLaunchArguments]) {
        [self performSelector:@selector(saveSanitizedUIDiagnostics:) withObject:nil afterDelay:0.25];
    }
    NSString *screenshotPath = [self localScreenshotPathFromLaunchArguments];
    if (screenshotPath) [self performSelector:@selector(captureLocalFixtureScreenshot:) withObject:screenshotPath afterDelay:0.5];
#else
    if (![[DLController sharedInstance] isLoggedIn]) {
        loginWindow = [[DLLoginWindowController alloc] initWithWindowNibName:@"DLLoginWindowController"];
        [loginWindow setDelegate:self];
        [loginWindow showWindow:loginWindow.window];
    } else {
        [[DLController sharedInstance] startWebSocket];
        mainWindow = [[DLMainWindowController alloc] initWithWindowNibName:@"DLMainWindowController"];
        [mainWindow setDelegate:self];
        [mainWindow showWindow:mainWindow.window];
    }
#endif
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
#if !LEGACY_DISCORD_LOCAL_DEV
    [[DLController sharedInstance] stopWebSocket];
#endif
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag {
#if LEGACY_DISCORD_LOCAL_DEV
    [mainWindow showWindow:self];
#else
    if (![[DLController sharedInstance] isLoggedIn]) {
        if (!loginWindow) {
            loginWindow = [[DLLoginWindowController alloc] initWithWindowNibName:@"DLLoginWindowController"];
        }
        [loginWindow setDelegate:self];
        [loginWindow showWindow:loginWindow.window];
    } else {
        if (!mainWindow) {
            mainWindow = [[DLMainWindowController alloc] initWithWindowNibName:@"DLMainWindowController"];
            [[DLController sharedInstance] startWebSocket];
        }
        [mainWindow setDelegate:self];
        [mainWindow showWindow:mainWindow.window];
    }
#endif
    return YES;
}

- (IBAction)showPreferencesWindow:(id)sender {
#if LEGACY_DISCORD_LOCAL_DEV
    [mainWindow showWindow:self];
#else
    if (!preferencesWindow) {
        preferencesWindow = [[DLPreferencesWindowController alloc] initWithWindowNibName:@"DLPreferencesWindowController"];
    }
    [preferencesWindow showWindow:preferencesWindow.window];
#endif
}

#pragma mark Delegated Functions

-(void)loginWasSuccessful {
    [[DLController sharedInstance] setLoginDelegate:nil];
    [loginWindow close];
    [loginWindow release];
    loginWindow = nil;
    [[DLController sharedInstance] startWebSocket];
    mainWindow = [[DLMainWindowController alloc] initWithWindowNibName:@"DLMainWindowController"];
    [mainWindow setDelegate:self];
    [mainWindow showWindow:mainWindow.window];
}

-(void)logoutWasSuccessful {
    // A connection-state delivery can already be queued on the main thread when
    // logout completes. Detach the window before releasing it so that queued
    // WebSocket callbacks safely become no-ops instead of messaging freed memory.
    [[DLController sharedInstance] setDelegate:nil];
    [[DLController sharedInstance] stopWebSocket];
    [mainWindow close];
    [mainWindow release];
    mainWindow = nil;
    loginWindow = [[DLLoginWindowController alloc] initWithWindowNibName:@"DLLoginWindowController"];
    [loginWindow setDelegate:self];
    [loginWindow showWindow:loginWindow.window];
}
@end
