//
//  DLPreferencesWindowController.m
//  Discord Lite
//
//  Created by Collin Mistr on 8/23/22.
//  Copyright (c) 2022 dosdude1. All rights reserved.
//

#import "DLPreferencesWindowController.h"
#import "DLLocalization.h"
#import "HTTPCache.h"
#import "DLController.h"
#import "DLUtil.h"
#import "DLMainWindowChromeControls.h"
#import "DLTwemojiRenderer.h"
#import "NSView+BGColor.h"
#import "DLDialog.h"
#import "DLThemes.h"
#import "DLPreferencesHandler.h"

static const CGFloat DLSettingsWindowWidth = 760.0;
static const CGFloat DLSettingsWindowHeight = 600.0;
static const CGFloat DLSettingsSidebarWidth = 210.0;
static const CGFloat DLSettingsContentLeft = 38.0;
static const CGFloat DLSettingsContentWidth = 470.0;

enum {
    DLSettingsSectionMyAccount = 0,
    DLSettingsSectionContentSocial,
    DLSettingsSectionAppearance,
    DLSettingsSectionAccessibility,
    DLSettingsSectionChat,
    DLSettingsSectionNotifications,
    DLSettingsSectionKeybinds,
    DLSettingsSectionLanguage,
    DLSettingsSectionAdvanced,
    DLSettingsSectionCount
};

// Tags identifying which preference a toggle switch controls.
enum {
    DLSettingsToggleRoleColors = 1,
    DLSettingsToggleAnimatedEmoji,
    DLSettingsToggleReactions,
    DLSettingsToggleEmbeds,
    DLSettingsToggleMentionSound,
    DLSettingsToggleUnreadBadge,
    DLSettingsToggleBounceDock,
    DLSettingsToggleDeveloperMode,
    DLSettingsToggleConvertEmoticons,
    DLSettingsToggleDesktopNotifications,
    DLSettingsToggleServerDMs,
    DLSettingsToggleFriendsEveryone,
    DLSettingsToggleFriendsOfFriends,
    DLSettingsToggleFriendsServerMembers
};

#pragma mark - Draw-only controls

// Discord-style sidebar entry: rounded highlight when selected.
@interface DLSettingsSidebarButton : NSButton {
    BOOL selected;
}
-(void)setSelected:(BOOL)flag;
@end

@implementation DLSettingsSidebarButton
-(void)setSelected:(BOOL)flag {
    selected = flag;
    [self setNeedsDisplay:YES];
}
-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    if (selected) {
        [[DLUtil nativeSelectionColor] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 0.0, 2.0) xRadius:4.0 yRadius:4.0] fill];
    } else if ([[self cell] isHighlighted]) {
        [[DLUtil nativeHoverColor] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 0.0, 2.0) xRadius:4.0 yRadius:4.0] fill];
    }
    NSColor *color = selected ? [DLUtil nativePrimaryTextColor] : [DLUtil nativeSecondaryTextColor];
    if (![self isEnabled]) color = [color colorWithAlphaComponent:0.45];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont systemFontOfSize:13.0], NSFontAttributeName,
                                color, NSForegroundColorAttributeName, nil];
    NSSize size = [[self title] sizeWithAttributes:attributes];
    [[self title] drawAtPoint:NSMakePoint(10.0, floor(NSMidY(bounds) - size.height / 2.0)) withAttributes:attributes];
}
@end

// Pill-shaped on/off switch like Discord's settings toggles.
@interface DLSettingsSwitch : NSButton
@end

@implementation DLSettingsSwitch
-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = NSInsetRect([self bounds], 1.0, 1.0);
    BOOL on = [self state] == NSOnState;
    CGFloat radius = NSHeight(bounds) / 2.0;
    [(on ? [DLUtil nativeOnlineStatusColor] : [DLUtil nativeOfflineStatusColor]) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:radius yRadius:radius] fill];
    CGFloat knobSide = NSHeight(bounds) - 6.0;
    CGFloat knobX = on ? NSMaxX(bounds) - knobSide - 3.0 : NSMinX(bounds) + 3.0;
    [[NSColor whiteColor] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(knobX, NSMinY(bounds) + 3.0, knobSide, knobSide)] fill];
}
@end

// Theme choice: a swatch of the theme's chat color, ringed when selected.
@interface DLThemeSwatchButton : NSButton {
    NSColor *swatchColor;
    NSColor *swatchAccentColor;
    NSImage *swatchImage;
    BOOL selected;
}
-(void)setSwatchColor:(NSColor *)color accentColor:(NSColor *)accent;
-(void)setSwatchImage:(NSImage *)image;
-(void)setSelected:(BOOL)flag;
@end

@implementation DLThemeSwatchButton
-(void)setSwatchColor:(NSColor *)color accentColor:(NSColor *)accent {
    [color retain]; [swatchColor release]; swatchColor = color;
    [accent retain]; [swatchAccentColor release]; swatchAccentColor = accent;
    [self setNeedsDisplay:YES];
}
-(void)setSelected:(BOOL)flag {
    selected = flag;
    [self setNeedsDisplay:YES];
}
-(void)setSwatchImage:(NSImage *)image {
    [image retain]; [swatchImage release]; swatchImage = image;
    [self setNeedsDisplay:YES];
}
-(void)drawRect:(NSRect)dirtyRect {
    if (swatchImage) {
        // Round Nitro preset with a blurple ring when selected.
        NSRect circle = NSInsetRect([self bounds], 3.0, 3.0);
        [swatchImage drawInRect:circle fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0 respectFlipped:YES hints:nil];
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect([self bounds], 1.0, 1.0)];
        [ring setLineWidth:(selected ? 2.0 : 0.0)];
        if (selected) {
            [[NSColor colorWithCalibratedRed:0.345 green:0.396 blue:0.949 alpha:1.0] setStroke];
            [ring stroke];
        }
        return;
    }
    NSRect bounds = NSInsetRect([self bounds], 3.0, 3.0);
    NSBezierPath *swatch = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:8.0 yRadius:8.0];
    if (swatchAccentColor) {
        NSGradient *gradient = [[[NSGradient alloc] initWithStartingColor:swatchAccentColor endingColor:swatchColor] autorelease];
        [gradient drawInBezierPath:swatch angle:90.0];
    } else {
        [swatchColor setFill];
        [swatch fill];
    }
    NSBezierPath *ring = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect([self bounds], 1.5, 1.5) xRadius:9.0 yRadius:9.0];
    [ring setLineWidth:(selected ? 2.0 : 1.0)];
    [(selected ? [NSColor colorWithCalibratedRed:0.345 green:0.396 blue:0.949 alpha:1.0] : [DLUtil nativeBorderColor]) setStroke];
    [ring stroke];
}
-(void)dealloc {
    [swatchColor release];
    [swatchAccentColor release];
    [swatchImage release];
    [super dealloc];
}
@end

#pragma mark - Window controller

@interface DLPreferencesWindowController ()
-(NSTextField *)labelWithFrame:(NSRect)frame text:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
-(NSView *)newPaneWithTitle:(NSString *)title;
-(CGFloat)addToggleToPane:(NSView *)pane top:(CGFloat)top title:(NSString *)title help:(NSString *)help tag:(NSInteger)tag on:(BOOL)on;
-(void)addDividerToPane:(NSView *)pane y:(CGFloat)y;
-(NSView *)buildAccountPane;
-(NSView *)buildAppearancePane;
-(NSView *)buildAccessibilityPane;
-(NSView *)buildChatPane;
-(NSView *)buildNotificationsPane;
-(NSView *)buildAdvancedPane;
-(NSView *)buildContentSocialPane;
-(NSView *)buildKeybindsPane;
-(NSView *)buildLanguagePane;
-(void)syncAccountControls;
-(void)selectSection:(NSInteger)section;
-(void)buildContent;
-(void)refreshCacheUsage;
-(void)syncThemeButtons;
@end

@implementation DLPreferencesWindowController

- (void)windowDidLoad {
    [super windowDidLoad];

    [self.window setTitle:DLLocalizedString(@"Legacy Discord Settings")];
    NSRect windowFrame = [self.window frame];
    windowFrame.origin.y -= 123.0;
    windowFrame.size = NSMakeSize(DLSettingsWindowWidth, DLSettingsWindowHeight);
    [self.window setFrame:windowFrame display:NO];
    [self.window setMinSize:NSMakeSize(680.0, 460.0)];
    [DLDarkTitlebarView installInWindow:self.window];

    NSArray *oldViews = [[[self.window contentView] subviews] copy];
    NSEnumerator *oldViewEnumerator = [oldViews objectEnumerator];
    NSView *oldView;
    while (oldView = [oldViewEnumerator nextObject]) [oldView setHidden:YES];
    [oldViews release];

    [self buildContent];
    [self selectSection:DLSettingsSectionAppearance];
    // Theme changes repaint the settings window too (colors are baked into
    // its controls when they are built).
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appearanceThemeDidChange:)
                                                 name:DLAppearanceThemeDidChangeNotification object:nil];
}

-(void)appearanceThemeDidChange:(NSNotification *)notification {
    NSInteger section = selectedSection;
    [contentBackground removeFromSuperview];
    [contentBackground release];
    contentBackground = nil;
    [settingsPanes release]; settingsPanes = nil;
    [settingsSidebarButtons release]; settingsSidebarButtons = nil;
    [themeButtons release]; themeButtons = nil;
    [displayScalePopup release]; displayScalePopup = nil;
    [chatFontPopup release]; chatFontPopup = nil;
    [contentHost release]; contentHost = nil;
    [friendEveryoneToggle release]; friendEveryoneToggle = nil;
    [friendsOfFriendsToggle release]; friendsOfFriendsToggle = nil;
    [friendServerMembersToggle release]; friendServerMembersToggle = nil;
    [explicitFilterRows release]; explicitFilterRows = nil;
    [spoilerRows release]; spoilerRows = nil;
    [languageRows release];
    [contentBackground release];
    [[NSNotificationCenter defaultCenter] removeObserver:self]; languageRows = nil;
    [accountSettingsControls release]; accountSettingsControls = nil;
    [self buildContent];
    [self selectSection:section];
}

-(void)buildContent {
    NSView_BGColor *background = [[NSView_BGColor alloc] initWithFrame:[[self.window contentView] bounds]];
    contentBackground = [background retain];
    [background setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [background setBackgroundColor:[DLUtil nativeContentColor]];
    [[self.window contentView] addSubview:background];

    CGFloat height = NSHeight([background bounds]);
    NSView_BGColor *sidebar = [[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0, 0.0, DLSettingsSidebarWidth, height)];
    [sidebar setAutoresizingMask:NSViewHeightSizable];
    [sidebar setBackgroundColor:[DLUtil nativeSidebarColor]];
    [background addSubview:sidebar];

    // Sidebar entries follow the web client's grouping. Voice & Video is
    // listed but disabled until voice support exists.
    NSArray *entries = [NSArray arrayWithObjects:
        DLLocalizedString(@"#USER SETTINGS"), DLLocalizedString(@"My Account"), DLLocalizedString(@"Content & Social"),
        DLLocalizedString(@"#APP SETTINGS"), DLLocalizedString(@"Appearance"), DLLocalizedString(@"Accessibility"), DLLocalizedString(@"-Voice & Video"), DLLocalizedString(@"Chat"), DLLocalizedString(@"Notifications"),
        DLLocalizedString(@"Keybinds"), DLLocalizedString(@"Language"), DLLocalizedString(@"Advanced"), nil];
    NSInteger sectionTags[] = { -1, DLSettingsSectionMyAccount, DLSettingsSectionContentSocial, -1,
                                DLSettingsSectionAppearance, DLSettingsSectionAccessibility, -1, DLSettingsSectionChat,
                                DLSettingsSectionNotifications, DLSettingsSectionKeybinds, DLSettingsSectionLanguage,
                                DLSettingsSectionAdvanced };
    settingsSidebarButtons = [[NSMutableArray alloc] init];
    CGFloat y = height - 40.0;
    for (NSUInteger index = 0; index < [entries count]; index++) {
        NSString *entry = [entries objectAtIndex:index];
        if ([entry hasPrefix:@"#"]) {
            y -= (index == 0 ? 0.0 : 10.0);
            NSTextField *header = [self labelWithFrame:NSMakeRect(24.0, y, 170.0, 16.0)
                                                  text:[entry substringFromIndex:1]
                                                  font:[NSFont boldSystemFontOfSize:10.0]
                                                 color:[DLUtil nativeSecondaryTextColor]];
            [header setAutoresizingMask:NSViewMinYMargin];
            [sidebar addSubview:header];
            y -= 32.0;
            continue;
        }
        BOOL disabled = [entry hasPrefix:@"-"];
        NSString *title = disabled ? [entry substringFromIndex:1] : entry;
        DLSettingsSidebarButton *button = [[[DLSettingsSidebarButton alloc] initWithFrame:NSMakeRect(14.0, y, 182.0, 32.0)] autorelease];
        [button setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
        [button setBordered:NO];
        [button setButtonType:NSMomentaryChangeButton];
        [button setTitle:title];
        [button setTag:sectionTags[index]];
        [button setTarget:self];
        [button setAction:@selector(showSettingsSection:)];
        if (disabled) {
            [button setEnabled:NO];
            [button setToolTip:DLLocalizedString(@"Voice chat is not available yet")];
        } else {
            [settingsSidebarButtons addObject:button];
        }
        [sidebar addSubview:button];
        y -= 34.0;
    }

    NSButton *logoutButton = [[[DLSettingsSidebarButton alloc] initWithFrame:NSMakeRect(14.0, 46.0, 182.0, 32.0)] autorelease];
    [logoutButton setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
    [logoutButton setBordered:NO];
    [logoutButton setButtonType:NSMomentaryChangeButton];
    [logoutButton setTitle:DLLocalizedString(@"Log Out")];
    [logoutButton setTarget:self];
    [logoutButton setAction:@selector(confirmLogOut:)];
    [sidebar addSubview:logoutButton];
    NSTextField *version = [self labelWithFrame:NSMakeRect(24.0, 16.0, 170.0, 16.0)
                                           text:[NSString stringWithFormat:@"Legacy Discord %@", [DLUtil appVersionString]]
                                           font:[NSFont systemFontOfSize:10.0]
                                          color:[DLUtil nativeSecondaryTextColor]];
    [version setAutoresizingMask:NSViewMaxYMargin];
    [sidebar addSubview:version];

    contentHost = [[NSView alloc] initWithFrame:NSMakeRect(DLSettingsSidebarWidth, 0.0,
                                                           NSWidth([background bounds]) - DLSettingsSidebarWidth, height)];
    [contentHost setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [background addSubview:contentHost];

    settingsPanes = [[NSMutableArray alloc] init];
    themeButtons = [[NSMutableArray alloc] init];
    NSView *panes[DLSettingsSectionCount];
    panes[DLSettingsSectionMyAccount] = [self buildAccountPane];
    panes[DLSettingsSectionContentSocial] = [self buildContentSocialPane];
    panes[DLSettingsSectionKeybinds] = [self buildKeybindsPane];
    panes[DLSettingsSectionLanguage] = [self buildLanguagePane];
    panes[DLSettingsSectionAppearance] = [self buildAppearancePane];
    panes[DLSettingsSectionAccessibility] = [self buildAccessibilityPane];
    panes[DLSettingsSectionChat] = [self buildChatPane];
    panes[DLSettingsSectionNotifications] = [self buildNotificationsPane];
    panes[DLSettingsSectionAdvanced] = [self buildAdvancedPane];
    for (NSInteger index = 0; index < DLSettingsSectionCount; index++) {
        [settingsPanes addObject:panes[index]];
        [contentHost addSubview:panes[index]];
        [panes[index] release];
    }

    [self initPreferences];
    [background release];
    [sidebar release];
}

#pragma mark Builders

-(NSTextField *)labelWithFrame:(NSRect)frame text:(NSString *)text font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setStringValue:(text ? text : @"")];
    [label setFont:font];
    [label setTextColor:color];
    return label;
}

// Returns a retained pane filling the content area, with its large title.
-(NSView *)newPaneWithTitle:(NSString *)title {
    NSView *pane = [[NSView alloc] initWithFrame:[contentHost bounds]];
    [pane setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    NSTextField *titleField = [self labelWithFrame:NSMakeRect(DLSettingsContentLeft, NSHeight([pane bounds]) - 62.0, DLSettingsContentWidth, 28.0)
                                              text:title
                                              font:[NSFont boldSystemFontOfSize:20.0]
                                             color:[DLUtil nativePrimaryTextColor]];
    [titleField setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:titleField];
    return pane;
}

-(NSTextField *)sectionHeaderInPane:(NSView *)pane top:(CGFloat)top text:(NSString *)text {
    NSTextField *header = [self labelWithFrame:NSMakeRect(DLSettingsContentLeft, top - 16.0, DLSettingsContentWidth, 16.0)
                                          text:text
                                          font:[NSFont boldSystemFontOfSize:10.0]
                                         color:[DLUtil nativeSecondaryTextColor]];
    [header setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:header];
    return header;
}

-(void)addDividerToPane:(NSView *)pane y:(CGFloat)y {
    NSView_BGColor *divider = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(DLSettingsContentLeft, y, DLSettingsContentWidth, 1.0)] autorelease];
    [divider setBackgroundColor:[DLUtil nativeSelectionColor]];
    [divider setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:divider];
}

// A Discord-style setting row: bold title, secondary help text below and a
// switch on the right. Returns the y coordinate below the row.
-(CGFloat)addToggleToPane:(NSView *)pane top:(CGFloat)top title:(NSString *)title help:(NSString *)help tag:(NSInteger)tag on:(BOOL)on {
    NSTextField *titleField = [self labelWithFrame:NSMakeRect(DLSettingsContentLeft, top - 20.0, DLSettingsContentWidth - 60.0, 18.0)
                                              text:title
                                              font:[NSFont boldSystemFontOfSize:13.0]
                                             color:[DLUtil nativePrimaryTextColor]];
    [titleField setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:titleField];
    NSTextField *helpField = [self labelWithFrame:NSMakeRect(DLSettingsContentLeft, top - 52.0, DLSettingsContentWidth - 60.0, 30.0)
                                             text:help
                                             font:[NSFont systemFontOfSize:11.0]
                                            color:[DLUtil nativeSecondaryTextColor]];
    [[helpField cell] setWraps:YES];
    [helpField setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:helpField];
    DLSettingsSwitch *toggle = [[[DLSettingsSwitch alloc] initWithFrame:NSMakeRect(DLSettingsContentLeft + DLSettingsContentWidth - 42.0, top - 22.0, 42.0, 24.0)] autorelease];
    [toggle setButtonType:NSToggleButton];
    [toggle setBordered:NO];
    [toggle setTitle:@""];
    [toggle setState:(on ? NSOnState : NSOffState)];
    [toggle setTag:tag];
    [toggle setTarget:self];
    [toggle setAction:@selector(toggleChanged:)];
    [toggle setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:toggle];
    [self addDividerToPane:pane y:top - 62.0];
    return top - 78.0;
}

// A one-line setting with a switch (friend request sources).
-(DLSettingsSwitch *)addCompactToggleToPane:(NSView *)pane top:(CGFloat)top title:(NSString *)title tag:(NSInteger)tag on:(BOOL)on {
    NSTextField *titleField = [self labelWithFrame:NSMakeRect(DLSettingsContentLeft, top - 22.0, DLSettingsContentWidth - 60.0, 18.0)
                                              text:title
                                              font:[NSFont systemFontOfSize:13.0]
                                             color:[DLUtil nativePrimaryTextColor]];
    [titleField setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:titleField];
    DLSettingsSwitch *toggle = [[[DLSettingsSwitch alloc] initWithFrame:NSMakeRect(DLSettingsContentLeft + DLSettingsContentWidth - 42.0, top - 26.0, 42.0, 24.0)] autorelease];
    [toggle setButtonType:NSToggleButton];
    [toggle setBordered:NO];
    [toggle setTitle:@""];
    [toggle setState:(on ? NSOnState : NSOffState)];
    [toggle setTag:tag];
    [toggle setTarget:self];
    [toggle setAction:@selector(toggleChanged:)];
    [toggle setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:toggle];
    return toggle;
}

// Radio group of full-width option rows; returns the rows (tag = value).
-(NSArray *)addOptionRowsToPane:(NSView *)pane top:(CGFloat)top titles:(NSArray *)titles details:(NSArray *)details
                         values:(NSArray *)values selected:(NSInteger)selected action:(SEL)action {
    NSMutableArray *rows = [NSMutableArray array];
    CGFloat height = details ? 52.0 : 40.0;
    for (NSUInteger index = 0; index < [titles count]; index++) {
        DLOptionRow *row = [[[DLOptionRow alloc] initWithFrame:NSMakeRect(DLSettingsContentLeft, top - (index + 1) * (height + 6.0),
                                                                          DLSettingsContentWidth, height)] autorelease];
        [row setTitle:[titles objectAtIndex:index]];
        if (details) [row setDetail:[details objectAtIndex:index]];
        NSInteger value = [[values objectAtIndex:index] integerValue];
        [row setTag:value];
        [row setSelected:(value == selected)];
        [row setTarget:self];
        [row setAction:action];
        [row setAutoresizingMask:NSViewMinYMargin];
        [pane addSubview:row];
        [rows addObject:row];
    }
    return rows;
}

-(void)selectOptionRow:(DLOptionRow *)selectedRow inRows:(NSArray *)rows {
    NSEnumerator *enumerator = [rows objectEnumerator];
    DLOptionRow *row;
    while (row = [enumerator nextObject]) [row setSelected:(row == selectedRow)];
}

-(NSView *)buildContentSocialPane {
    NSView *pane = [self newPaneWithTitle:DLLocalizedString(@"Content & Social")];
    CGFloat top = NSHeight([pane bounds]) - 82.0;
    [self sectionHeaderInPane:pane top:top text:DLLocalizedString(@"DIRECT MESSAGES")];
    top -= 24.0;
    top = [self addToggleToPane:pane top:top title:DLLocalizedString(@"Allow DMs from other members in your servers")
                           help:DLLocalizedString(@"This setting is applied when you join a new server. It does not apply retroactively to your existing servers.")
                            tag:DLSettingsToggleServerDMs on:YES];
    [self sectionHeaderInPane:pane top:top text:DLLocalizedString(@"WHO CAN SEND YOU A FRIEND REQUEST")];
    top -= 22.0;
    friendEveryoneToggle = [[self addCompactToggleToPane:pane top:top title:DLLocalizedString(@"Everyone") tag:DLSettingsToggleFriendsEveryone on:YES] retain];
    top -= 36.0;
    friendsOfFriendsToggle = [[self addCompactToggleToPane:pane top:top title:DLLocalizedString(@"Friends of Friends") tag:DLSettingsToggleFriendsOfFriends on:YES] retain];
    top -= 36.0;
    friendServerMembersToggle = [[self addCompactToggleToPane:pane top:top title:DLLocalizedString(@"Server Members") tag:DLSettingsToggleFriendsServerMembers on:YES] retain];
    top -= 44.0;
    [self addDividerToPane:pane y:top + 6.0];
    top -= 8.0;
    [self sectionHeaderInPane:pane top:top text:DLLocalizedString(@"EXPLICIT IMAGE FILTER")];
    top -= 22.0;
    explicitFilterRows = [[self addOptionRowsToPane:pane top:top
        titles:[NSArray arrayWithObjects:DLLocalizedString(@"Keep me safe"), DLLocalizedString(@"My friends are nice"), DLLocalizedString(@"I live on the edge"), nil]
        details:[NSArray arrayWithObjects:DLLocalizedString(@"Scan images sent in all direct messages."),
                 DLLocalizedString(@"Scan images sent in direct messages unless they are from a friend."),
                 DLLocalizedString(@"Do not scan direct messages."), nil]
        values:[NSArray arrayWithObjects:[NSNumber numberWithInt:2], [NSNumber numberWithInt:1], [NSNumber numberWithInt:0], nil]
        selected:1 action:@selector(explicitFilterChanged:)] retain];
    accountSettingsControls = [[NSMutableArray alloc] init];
    NSEnumerator *enumerator = [[pane subviews] objectEnumerator];
    NSView *subview;
    while (subview = [enumerator nextObject]) {
        if ([subview isKindOfClass:[NSControl class]]) [accountSettingsControls addObject:subview];
    }
    return pane;
}

// Mirrors the account settings into the Content & Social controls.
-(void)syncAccountControls {
    NSDictionary *settings = [[DLController sharedInstance] accountSettings];
    NSEnumerator *enumerator = [accountSettingsControls objectEnumerator];
    NSControl *control;
    while (control = [enumerator nextObject]) [control setEnabled:(settings != nil)];
    if (!settings) return;
    enumerator = [accountSettingsControls objectEnumerator];
    while (control = [enumerator nextObject]) {
        if ([control tag] == DLSettingsToggleServerDMs && [control isKindOfClass:[DLSettingsSwitch class]]) {
            id restricted = [settings objectForKey:@"default_guilds_restricted"];
            BOOL restrictedOn = [restricted respondsToSelector:@selector(boolValue)] && [restricted boolValue];
            [(NSButton *)control setState:(restrictedOn ? NSOffState : NSOnState)];
        }
    }
    // Values may be JSON null; a missing friend_source_flags means everyone.
    NSDictionary *sources = [settings objectForKey:@"friend_source_flags"];
    if (![sources isKindOfClass:[NSDictionary class]]) sources = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"all"];
    BOOL everyone = [[sources objectForKey:@"all"] respondsToSelector:@selector(boolValue)] && [[sources objectForKey:@"all"] boolValue];
    [friendEveryoneToggle setState:(everyone ? NSOnState : NSOffState)];
    id mutualFriends = [sources objectForKey:@"mutual_friends"];
    id mutualGuilds = [sources objectForKey:@"mutual_guilds"];
    [friendsOfFriendsToggle setState:((everyone || ([mutualFriends respondsToSelector:@selector(boolValue)] && [mutualFriends boolValue])) ? NSOnState : NSOffState)];
    [friendServerMembersToggle setState:((everyone || ([mutualGuilds respondsToSelector:@selector(boolValue)] && [mutualGuilds boolValue])) ? NSOnState : NSOffState)];
    [friendsOfFriendsToggle setEnabled:!everyone];
    [friendServerMembersToggle setEnabled:!everyone];
    NSInteger filter = [[settings objectForKey:@"explicit_content_filter"] respondsToSelector:@selector(integerValue)]
        ? [[settings objectForKey:@"explicit_content_filter"] integerValue] : 1;
    enumerator = [explicitFilterRows objectEnumerator];
    DLOptionRow *row;
    while (row = [enumerator nextObject]) [row setSelected:([row tag] == filter)];
    [friendEveryoneToggle setNeedsDisplay:YES];
    [friendsOfFriendsToggle setNeedsDisplay:YES];
    [friendServerMembersToggle setNeedsDisplay:YES];
}

-(void)saveFriendSources {
    BOOL everyone = [friendEveryoneToggle state] == NSOnState;
    NSDictionary *sources = everyone ? [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"all"]
        : [NSDictionary dictionaryWithObjectsAndKeys:
           [NSNumber numberWithBool:([friendsOfFriendsToggle state] == NSOnState)], @"mutual_friends",
           [NSNumber numberWithBool:([friendServerMembersToggle state] == NSOnState)], @"mutual_guilds", nil];
    [[DLController sharedInstance] updateAccountSettings:[NSDictionary dictionaryWithObject:sources forKey:@"friend_source_flags"]];
    [self syncAccountControls];
}

-(void)explicitFilterChanged:(DLOptionRow *)sender {
    [self selectOptionRow:sender inRows:explicitFilterRows];
    [[DLController sharedInstance] updateAccountSettings:
        [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:[sender tag]] forKey:@"explicit_content_filter"]];
}

-(void)spoilerDisplayChanged:(DLOptionRow *)sender {
    [self selectOptionRow:sender inRows:spoilerRows];
    [[DLPreferencesHandler sharedInstance] setSpoilerDisplay:[sender tag]];
}

-(NSView *)buildLanguagePane {
    NSView *pane = [self newPaneWithTitle:DLLocalizedString(@"Language")];
    CGFloat top = NSHeight([pane bounds]) - 82.0;
    [self sectionHeaderInPane:pane top:top text:DLLocalizedString(@"LANGUAGE")];
    top -= 22.0;
    NSString *setting = [DLLocalization preferredLanguageSetting];
    NSInteger selected = [setting isEqualToString:@"en"] ? 1 : ([setting isEqualToString:@"ja"] ? 2 : 0);
    // Language names stay in their own language, as in the official client.
    languageRows = [[self addOptionRowsToPane:pane top:top
        titles:[NSArray arrayWithObjects:DLLocalizedString(@"Follow system"), @"English", @"日本語", nil]
        details:[NSArray arrayWithObjects:DLLocalizedString(@"Uses the first language in System Preferences > Language & Text."),
                 @"English", @"Japanese", nil]
        values:[NSArray arrayWithObjects:[NSNumber numberWithInt:0], [NSNumber numberWithInt:1], [NSNumber numberWithInt:2], nil]
        selected:selected action:@selector(languageChanged:)] retain];
    return pane;
}

-(void)languageChanged:(DLOptionRow *)sender {
    NSArray *settings = [NSArray arrayWithObjects:@"system", @"en", @"ja", nil];
    NSString *setting = [settings objectAtIndex:(NSUInteger)[sender tag]];
    if ([setting isEqualToString:[DLLocalization preferredLanguageSetting]]) return;
    [self selectOptionRow:sender inRows:languageRows];
    [DLLocalization setPreferredLanguageSetting:setting];
    DLDialog *dialog = [DLDialog dialogWithTitle:DLLocalizedString(@"Restart to change the language")
                                         message:DLLocalizedString(@"Legacy Discord will restart to apply the new language.")];
    [dialog addButtonWithTitle:DLLocalizedString(@"Restart Now") style:DLDialogButtonStylePrimary];
    [dialog addButtonWithTitle:DLLocalizedString(@"Later") style:DLDialogButtonStyleLink];
    [dialog setHandler:^BOOL(DLDialog *shown, NSInteger buttonIndex) {
        if (buttonIndex == 0) {
            // A shell waits for this process to exit, then opens the app again.
            NSString *script = [NSString stringWithFormat:@"while kill -0 %d 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                                [[NSProcessInfo processInfo] processIdentifier]];
            [NSTask launchedTaskWithLaunchPath:@"/bin/sh"
                                     arguments:[NSArray arrayWithObjects:@"-c", script, [[NSBundle mainBundle] bundlePath], nil]];
            [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.1];
        }
        return YES;
    }];
    [dialog showInWindow:self.window];
}

-(NSView *)buildKeybindsPane {
    NSView *pane = [self newPaneWithTitle:DLLocalizedString(@"Keybinds")];
    CGFloat top = NSHeight([pane bounds]) - 82.0;
    [self sectionHeaderInPane:pane top:top text:DLLocalizedString(@"MESSAGES")];
    top -= 24.0;
    NSArray *bindings = [NSArray arrayWithObjects:
        [NSArray arrayWithObjects:DLLocalizedString(@"Send message"), DLLocalizedString(@"Return"), nil],
        [NSArray arrayWithObjects:DLLocalizedString(@"New line in message"), DLLocalizedString(@"Shift + Return"), nil],
        [NSArray arrayWithObjects:DLLocalizedString(@"Edit your last message"), DLLocalizedString(@"Up Arrow (empty message)"), nil],
        [NSArray arrayWithObjects:DLLocalizedString(@"Cancel reply or editing"), DLLocalizedString(@"Escape"), nil],
        [NSArray arrayWithObjects:DLLocalizedString(@"Delete without confirmation"), DLLocalizedString(@"Shift + Delete Message"), nil],
        [NSArray arrayWithObjects:DLLocalizedString(@"Search messages"), @"\u2318 F", nil],
        [NSArray arrayWithObjects:DLLocalizedString(@"Open settings"), @"\u2318 ,", nil],
        [NSArray arrayWithObjects:DLLocalizedString(@"Close window"), @"\u2318 W", nil],
        [NSArray arrayWithObjects:DLLocalizedString(@"Quit Legacy Discord"), @"\u2318 Q", nil], nil];
    NSEnumerator *enumerator = [bindings objectEnumerator];
    NSArray *binding;
    while (binding = [enumerator nextObject]) {
        NSTextField *action = [self labelWithFrame:NSMakeRect(DLSettingsContentLeft, top - 22.0, 260.0, 18.0)
                                              text:[binding objectAtIndex:0]
                                              font:[NSFont systemFontOfSize:13.0]
                                             color:[DLUtil nativePrimaryTextColor]];
        [action setAutoresizingMask:NSViewMinYMargin];
        [pane addSubview:action];
        NSTextField *keys = [self labelWithFrame:NSMakeRect(DLSettingsContentLeft + 260.0, top - 22.0, DLSettingsContentWidth - 260.0, 18.0)
                                            text:[binding objectAtIndex:1]
                                            font:[NSFont boldSystemFontOfSize:12.0]
                                           color:[DLUtil nativeSecondaryTextColor]];
        [keys setAlignment:NSRightTextAlignment];
        [keys setAutoresizingMask:NSViewMinYMargin];
        [pane addSubview:keys];
        [self addDividerToPane:pane y:top - 32.0];
        top -= 40.0;
    }
    return pane;
}

-(NSView *)buildAccountPane {
    NSView *pane = [self newPaneWithTitle:DLLocalizedString(@"My Account")];
    CGFloat top = NSHeight([pane bounds]) - 82.0;
    DLUser *user = [[DLController sharedInstance] myUser];

    NSView_BGColor *card = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(DLSettingsContentLeft, top - 230.0, DLSettingsContentWidth, 230.0)] autorelease];
    [card setBackgroundColor:[DLUtil nativeUserPanelColor]];
    [card setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:card];
    NSView_BGColor *banner = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0, 230.0 - 72.0, DLSettingsContentWidth, 72.0)] autorelease];
    [banner setBackgroundColor:[NSColor colorWithCalibratedRed:0.345 green:0.396 blue:0.949 alpha:1.0]];
    [card addSubview:banner];

    NSImageView *avatar = [[[NSImageView alloc] initWithFrame:NSMakeRect(16.0, 230.0 - 72.0 - 36.0, 72.0, 72.0)] autorelease];
    [avatar setImageFrameStyle:NSImageFrameNone];
    NSImage *avatarImage = [[[NSImage alloc] initWithData:[user avatarImageData]] autorelease];
    if (avatarImage) [avatar setImage:[DLUtil imageResize:avatarImage newSize:NSMakeSize(72.0, 72.0) cornerRadius:36.0]];
    [card addSubview:avatar];

    NSString *displayName = [user globalName] ? [user globalName] : [user username];
    NSTextField *nameField = [self labelWithFrame:NSMakeRect(100.0, 230.0 - 72.0 - 30.0, DLSettingsContentWidth - 116.0, 24.0)
                                             text:@""
                                             font:[NSFont boldSystemFontOfSize:17.0]
                                            color:[DLUtil nativePrimaryTextColor]];
    [DLTwemojiRenderer setText:displayName forLabel:nameField];
    [card addSubview:nameField];

    NSView_BGColor *fields = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(16.0, 16.0, DLSettingsContentWidth - 32.0, 96.0)] autorelease];
    [fields setBackgroundColor:[DLUtil nativeSidebarColor]];
    [card addSubview:fields];
    NSArray *fieldTitles = [NSArray arrayWithObjects:DLLocalizedString(@"DISPLAY NAME"), DLLocalizedString(@"USERNAME"), nil];
    NSArray *fieldValues = [NSArray arrayWithObjects:(displayName ? displayName : @""), ([user username] ? [user username] : @""), nil];
    for (NSUInteger index = 0; index < 2; index++) {
        CGFloat rowTop = 96.0 - 12.0 - index * 42.0;
        [fields addSubview:[self labelWithFrame:NSMakeRect(14.0, rowTop - 14.0, 300.0, 14.0)
                                           text:[fieldTitles objectAtIndex:index]
                                           font:[NSFont boldSystemFontOfSize:10.0]
                                          color:[DLUtil nativeSecondaryTextColor]]];
        NSTextField *value = [self labelWithFrame:NSMakeRect(14.0, rowTop - 32.0, NSWidth([fields bounds]) - 28.0, 18.0)
                                             text:@""
                                             font:[NSFont systemFontOfSize:13.0]
                                            color:[DLUtil nativePrimaryTextColor]];
        [DLTwemojiRenderer setText:[fieldValues objectAtIndex:index] forLabel:value];
        [fields addSubview:value];
    }

    NSTextField *note = [self labelWithFrame:NSMakeRect(DLSettingsContentLeft, top - 280.0, DLSettingsContentWidth, 32.0)
                                        text:DLLocalizedString(@"Account details are shown read-only. Edit them in the official client; changes appear here after reconnecting.")
                                        font:[NSFont systemFontOfSize:11.0]
                                       color:[DLUtil nativeSecondaryTextColor]];
    [[note cell] setWraps:YES];
    [note setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:note];
    return pane;
}

-(NSView *)buildAppearancePane {
    NSView *pane = [self newPaneWithTitle:DLLocalizedString(@"Appearance")];
    CGFloat top = NSHeight([pane bounds]) - 82.0;

    [self sectionHeaderInPane:pane top:top text:DLLocalizedString(@"THEME")];
    NSArray *themeTitles = [NSArray arrayWithObjects:DLLocalizedString(@"Dark"), DLLocalizedString(@"Midnight"), DLLocalizedString(@"Aurora"), nil];
    NSArray *themeKeys = [NSArray arrayWithObjects:@"default", @"midnight", @"aurora", nil];
    for (NSInteger index = 0; index < 3; index++) {
        DLThemeSwatchButton *swatch = [[[DLThemeSwatchButton alloc] initWithFrame:NSMakeRect(DLSettingsContentLeft + index * 76.0, top - 82.0, 60.0, 60.0)] autorelease];
        // Aurora's swatch shows its header gradient over the chat color.
        [swatch setSwatchColor:[DLUtil nativeContentColorForTheme:[themeKeys objectAtIndex:index]]
                   accentColor:(index == 2 ? [NSColor colorWithCalibratedRed:0.145 green:0.170 blue:0.235 alpha:1.0] : nil)];
        [swatch setBordered:NO];
        [swatch setTitle:@""];
        [swatch setTag:index];
        [swatch setToolTip:[themeTitles objectAtIndex:index]];
        [swatch setTarget:self];
        [swatch setAction:@selector(themeChanged:)];
        [swatch setAutoresizingMask:NSViewMinYMargin];
        [pane addSubview:swatch];
        [themeButtons addObject:swatch];
        NSTextField *caption = [self labelWithFrame:NSMakeRect(DLSettingsContentLeft + index * 76.0 - 8.0, top - 102.0, 76.0, 16.0)
                                               text:[themeTitles objectAtIndex:index]
                                               font:[NSFont systemFontOfSize:11.0]
                                              color:[DLUtil nativeSecondaryTextColor]];
        [caption setAlignment:NSCenterTextAlignment];
        [caption setAutoresizingMask:NSViewMinYMargin];
        [pane addSubview:caption];
    }
    [self addDividerToPane:pane y:top - 118.0];

    // Nitro color themes, in the official order (light presets first).
    [self sectionHeaderInPane:pane top:top - 136.0 text:DLLocalizedString(@"COLOR THEMES")];
    NSArray *presets = [DLThemes presets];
    for (NSUInteger index = 0; index < [presets count]; index++) {
        NSDictionary *preset = [presets objectAtIndex:index];
        NSInteger column = index % 9, row = index / 9;
        DLThemeSwatchButton *swatch = [[[DLThemeSwatchButton alloc] initWithFrame:
            NSMakeRect(DLSettingsContentLeft + column * 52.0, top - 200.0 - row * 50.0, 46.0, 46.0)] autorelease];
        [swatch setSwatchImage:[DLThemes swatchImageForPresetID:[preset objectForKey:@"id"] size:40.0]];
        [swatch setBordered:NO];
        [swatch setTitle:@""];
        [swatch setTag:100 + (NSInteger)index];
        [swatch setToolTip:DLLocalizedString([preset objectForKey:@"name"])];
        [swatch setTarget:self];
        [swatch setAction:@selector(themeChanged:)];
        [swatch setAutoresizingMask:NSViewMinYMargin];
        [pane addSubview:swatch];
        [themeButtons addObject:swatch];
    }
    CGFloat gridBottom = top - 200.0 - (([presets count] + 8) / 9 - 1) * 50.0;
    [self addDividerToPane:pane y:gridBottom - 14.0];

    CGFloat rowTop = gridBottom - 30.0;
    [self sectionHeaderInPane:pane top:rowTop text:DLLocalizedString(@"CHAT FONT SCALING")];
    chatFontPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(DLSettingsContentLeft - 2.0, rowTop - 50.0, 220.0, 30.0) pullsDown:NO];
    [chatFontPopup setCell:[[[DLDarkPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO] autorelease]];
    NSInteger fontSizes[] = { 12, 13, 14, 15, 16, 18, 20 };
    for (NSUInteger index = 0; index < sizeof(fontSizes) / sizeof(fontSizes[0]); index++) {
        NSString *title = fontSizes[index] == 13 ? DLLocalizedString(@"13px (default)") : [NSString stringWithFormat:@"%ldpx", (long)fontSizes[index]];
        [chatFontPopup addItemWithTitle:title];
        [[chatFontPopup lastItem] setTag:fontSizes[index]];
    }
    [chatFontPopup setTarget:self];
    [chatFontPopup setAction:@selector(chatFontSizeChanged:)];
    [chatFontPopup setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:chatFontPopup];

    rowTop -= 80.0;
    [self sectionHeaderInPane:pane top:rowTop text:DLLocalizedString(@"ZOOM LEVEL")];
    displayScalePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(DLSettingsContentLeft - 2.0, rowTop - 50.0, 220.0, 30.0) pullsDown:NO];
    [displayScalePopup setCell:[[[DLDarkPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO] autorelease]];
    NSArray *titles = [NSArray arrayWithObjects:@"80%", DLLocalizedString(@"90% (default)"), @"100%", @"110%", @"125%", nil];
    NSInteger tags[] = { 80, 90, 100, 110, 125 };
    for (NSInteger index = 0; index < (NSInteger)[titles count]; index++) {
        [displayScalePopup addItemWithTitle:[titles objectAtIndex:index]];
        [[displayScalePopup itemAtIndex:index] setTag:tags[index]];
    }
    [displayScalePopup setTarget:self];
    [displayScalePopup setAction:@selector(displayScaleChanged:)];
    [displayScalePopup setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:displayScalePopup];
    NSTextField *zoomHelp = [self labelWithFrame:NSMakeRect(DLSettingsContentLeft + 230.0, rowTop - 50.0, 240.0, 28.0)
                                            text:DLLocalizedString(@"Scales message text, avatars and spacing.")
                                            font:[NSFont systemFontOfSize:11.0]
                                           color:[DLUtil nativeSecondaryTextColor]];
    [[zoomHelp cell] setWraps:YES];
    [zoomHelp setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:zoomHelp];
    return pane;
}

-(NSView *)buildAccessibilityPane {
    NSView *pane = [self newPaneWithTitle:DLLocalizedString(@"Accessibility")];
    DLPreferencesHandler *preferences = [DLPreferencesHandler sharedInstance];
    CGFloat top = NSHeight([pane bounds]) - 82.0;
    top = [self addToggleToPane:pane top:top title:DLLocalizedString(@"Show role colors in names")
                           help:DLLocalizedString(@"Color member names in chat and the member list with their highest colored role.")
                            tag:DLSettingsToggleRoleColors on:[preferences showRoleColors]];
    [self addToggleToPane:pane top:top title:DLLocalizedString(@"Automatically play animated emoji")
                     help:DLLocalizedString(@"When off, animated custom emoji show their first frame. Reduces CPU use on older Macs.")
                      tag:DLSettingsToggleAnimatedEmoji on:[preferences autoplayAnimatedEmoji]];
    return pane;
}

-(NSView *)buildChatPane {
    NSView *pane = [self newPaneWithTitle:DLLocalizedString(@"Chat")];
    DLPreferencesHandler *preferences = [DLPreferencesHandler sharedInstance];
    CGFloat top = NSHeight([pane bounds]) - 82.0;
    top = [self addToggleToPane:pane top:top title:DLLocalizedString(@"Show emoji reactions on messages")
                           help:DLLocalizedString(@"Display the reaction bar under messages that have reactions.")
                            tag:DLSettingsToggleReactions on:[preferences showReactions]];
    top = [self addToggleToPane:pane top:top title:DLLocalizedString(@"Show embeds and preview website links")
                           help:DLLocalizedString(@"Show link previews and rich embeds sent by bots.")
                            tag:DLSettingsToggleEmbeds on:[preferences showEmbeds]];
    top = [self addToggleToPane:pane top:top title:DLLocalizedString(@"Automatically convert emoticons in your messages to emoji")
                           help:DLLocalizedString(@"For example, when you type :-) Legacy Discord will convert it to the smiling face emoji.")
                            tag:DLSettingsToggleConvertEmoticons on:[preferences convertEmoticons]];
    [self sectionHeaderInPane:pane top:top text:DLLocalizedString(@"SHOW SPOILER CONTENT")];
    top -= 22.0;
    spoilerRows = [[self addOptionRowsToPane:pane top:top
        titles:[NSArray arrayWithObjects:DLLocalizedString(@"On click"), DLLocalizedString(@"On servers I moderate"), DLLocalizedString(@"Always"), nil]
        details:nil
        values:[NSArray arrayWithObjects:[NSNumber numberWithInt:DLSpoilerDisplayOnClick],
                [NSNumber numberWithInt:DLSpoilerDisplayModerated], [NSNumber numberWithInt:DLSpoilerDisplayAlways], nil]
        selected:[preferences spoilerDisplay] action:@selector(spoilerDisplayChanged:)] retain];
    return pane;
}

-(NSView *)buildNotificationsPane {
    NSView *pane = [self newPaneWithTitle:DLLocalizedString(@"Notifications")];
    CGFloat top = NSHeight([pane bounds]) - 82.0;
    DLPreferencesHandler *preferences = [DLPreferencesHandler sharedInstance];
    // Notification Center exists from OS X 10.8.
    BOOL notificationCenter = NSClassFromString(@"NSUserNotificationCenter") != nil;
    top = [self addToggleToPane:pane top:top title:DLLocalizedString(@"Enable Desktop Notifications")
                           help:(notificationCenter ? DLLocalizedString(@"Show a Notification Center banner for mentions and direct messages while Legacy Discord is in the background.")
                                                    : DLLocalizedString(@"Desktop notifications need OS X 10.8 or later."))
                            tag:DLSettingsToggleDesktopNotifications on:(notificationCenter && [preferences desktopNotifications])];
    top = [self addToggleToPane:pane top:top title:DLLocalizedString(@"Enable Unread Message Badge")
                           help:DLLocalizedString(@"Shows a red badge on the Dock icon with your mention and direct message count.")
                            tag:DLSettingsToggleUnreadBadge on:[preferences showUnreadBadge]];
    top = [self addToggleToPane:pane top:top title:DLLocalizedString(@"Bounce Dock Icon")
                           help:DLLocalizedString(@"Bounces the Dock icon once when you are mentioned or receive a direct message while Legacy Discord is in the background.")
                            tag:DLSettingsToggleBounceDock on:[preferences bounceDockIcon]];
    [self addToggleToPane:pane top:top title:DLLocalizedString(@"Play a sound for mentions and direct messages")
                     help:DLLocalizedString(@"Plays the mention sound when you are mentioned or receive a direct message.")
                      tag:DLSettingsToggleMentionSound on:[preferences playMentionSound]];
    return pane;
}

-(NSView *)buildAdvancedPane {
    NSView *pane = [self newPaneWithTitle:DLLocalizedString(@"Advanced")];
    CGFloat top = NSHeight([pane bounds]) - 82.0;
    top = [self addToggleToPane:pane top:top title:DLLocalizedString(@"Developer Mode")
                           help:DLLocalizedString(@"Adds Copy Message ID and Copy User ID to the message context menu.")
                            tag:DLSettingsToggleDeveloperMode on:[[DLPreferencesHandler sharedInstance] developerMode]];
    // Image cache: avatars, emoji and previews kept on disk (up to 200 MB).
    NSTextField *cacheTitle = [self labelWithFrame:NSMakeRect(DLSettingsContentLeft, top - 20.0, DLSettingsContentWidth - 140.0, 18.0)
                                              text:DLLocalizedString(@"Image Cache")
                                              font:[NSFont boldSystemFontOfSize:13.0]
                                             color:[DLUtil nativePrimaryTextColor]];
    [cacheTitle setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:cacheTitle];
    cacheUsageField = [self labelWithFrame:NSMakeRect(DLSettingsContentLeft, top - 52.0, DLSettingsContentWidth - 140.0, 30.0)
                                      text:@""
                                      font:[NSFont systemFontOfSize:11.0]
                                     color:[DLUtil nativeSecondaryTextColor]];
    [[cacheUsageField cell] setWraps:YES];
    [cacheUsageField setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:cacheUsageField];
    NSButton *clearCache = [[[DLPrimaryButton alloc] initWithFrame:
                             NSMakeRect(DLSettingsContentLeft + DLSettingsContentWidth - 120.0, top - 28.0, 120.0, 28.0)] autorelease];
    [clearCache setTitle:DLLocalizedString(@"Clear Cache")];
    [clearCache setTarget:self];
    [clearCache setAction:@selector(clearImageCache:)];
    [clearCache setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:clearCache];
    [self refreshCacheUsage];
    return pane;
}

-(void)refreshCacheUsage {
    double megabytes = [[HTTPCache sharedInstance] diskUsage] / (1024.0 * 1024.0);
    [cacheUsageField setStringValue:[NSString stringWithFormat:
        DLLocalizedString(@"Avatars, emoji and image previews are kept on disk so channels open faster. Using %.1f MB of 200 MB."), megabytes]];
}

-(IBAction)clearImageCache:(id)sender {
    [[HTTPCache sharedInstance] clearDiskCache];
    [self refreshCacheUsage];
}

#pragma mark State

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
    [chatFontPopup selectItemWithTag:(NSInteger)round([[DLPreferencesHandler sharedInstance] chatFontSize])];
    [self syncThemeButtons];
}

-(void)syncThemeButtons {
    NSString *theme = [[DLPreferencesHandler sharedInstance] appearanceTheme];
    NSArray *themes = [NSArray arrayWithObjects:@"default", @"midnight", @"aurora", nil];
    NSArray *presets = [DLThemes presets];
    NSEnumerator *enumerator = [themeButtons objectEnumerator];
    DLThemeSwatchButton *button;
    while (button = [enumerator nextObject]) {
        NSInteger tag = [button tag];
        NSString *key = nil;
        if (tag >= 100 && tag - 100 < (NSInteger)[presets count]) {
            key = [DLNitroThemePrefix stringByAppendingString:[[presets objectAtIndex:(NSUInteger)(tag - 100)] objectForKey:@"id"]];
        } else if (tag >= 0 && tag < (NSInteger)[themes count]) {
            key = [themes objectAtIndex:(NSUInteger)tag];
        }
        [button setSelected:[key isEqualToString:theme]];
    }
}

-(void)selectSection:(NSInteger)section {
    if (section < 0 || section >= DLSettingsSectionCount) return;
    selectedSection = section;
    if (section == DLSettingsSectionAdvanced) [self refreshCacheUsage];
    if (section == DLSettingsSectionContentSocial) [self syncAccountControls];
    for (NSInteger index = 0; index < (NSInteger)[settingsPanes count]; index++) {
        [[settingsPanes objectAtIndex:index] setHidden:(index != section)];
    }
    NSEnumerator *enumerator = [settingsSidebarButtons objectEnumerator];
    DLSettingsSidebarButton *button;
    while (button = [enumerator nextObject]) {
        [button setSelected:([button tag] == section)];
    }
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

#pragma mark Actions

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

-(void)chatFontSizeChanged:(id)sender {
    [[DLPreferencesHandler sharedInstance] setChatFontSize:(CGFloat)[[chatFontPopup selectedItem] tag]];
}

- (IBAction)themeChanged:(id)sender {
    NSArray *themes = [NSArray arrayWithObjects:@"default", @"midnight", @"aurora", nil];
    NSArray *presets = [DLThemes presets];
    NSInteger tag = [(NSButton *)sender tag];
    NSString *theme = nil;
    if (tag >= 100 && tag - 100 < (NSInteger)[presets count]) {
        theme = [DLNitroThemePrefix stringByAppendingString:[[presets objectAtIndex:(NSUInteger)(tag - 100)] objectForKey:@"id"]];
    } else if (tag >= 0 && tag < (NSInteger)[themes count]) {
        theme = [themes objectAtIndex:(NSUInteger)tag];
    }
    // The setter posts the theme notification, which rebuilds this window.
    if (theme) [[DLPreferencesHandler sharedInstance] setAppearanceTheme:theme];
}

-(void)toggleChanged:(id)sender {
    BOOL on = [(NSButton *)sender state] == NSOnState;
    DLPreferencesHandler *preferences = [DLPreferencesHandler sharedInstance];
    switch ([(NSButton *)sender tag]) {
        case DLSettingsToggleRoleColors: [preferences setShowRoleColors:on]; break;
        case DLSettingsToggleAnimatedEmoji: [preferences setAutoplayAnimatedEmoji:on]; break;
        case DLSettingsToggleReactions: [preferences setShowReactions:on]; break;
        case DLSettingsToggleEmbeds: [preferences setShowEmbeds:on]; break;
        case DLSettingsToggleMentionSound: [preferences setPlayMentionSound:on]; break;
        case DLSettingsToggleUnreadBadge: [preferences setShowUnreadBadge:on]; break;
        case DLSettingsToggleBounceDock: [preferences setBounceDockIcon:on]; break;
        case DLSettingsToggleDeveloperMode: [preferences setDeveloperMode:on]; break;
        case DLSettingsToggleConvertEmoticons: [preferences setConvertEmoticons:on]; break;
        case DLSettingsToggleDesktopNotifications: [preferences setDesktopNotifications:on]; break;
        case DLSettingsToggleServerDMs:
            [[DLController sharedInstance] updateAccountSettings:
                [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:!on] forKey:@"default_guilds_restricted"]];
            break;
        case DLSettingsToggleFriendsEveryone:
        case DLSettingsToggleFriendsOfFriends:
        case DLSettingsToggleFriendsServerMembers:
            [self saveFriendSources];
            break;
    }
    [sender setNeedsDisplay:YES];
}

- (IBAction)showSettingsSection:(id)sender {
    [self selectSection:[(NSButton *)sender tag]];
}

#if LEGACY_DISCORD_LOCAL_DEV
-(void)selectSettingsSectionNamed:(NSString *)name {
    NSArray *names = [NSArray arrayWithObjects:@"account", @"content", @"appearance", @"accessibility", @"chat", @"notifications", @"keybinds", @"language", @"advanced", nil];
    NSUInteger index = [names indexOfObject:name];
    if (index != NSNotFound) [self selectSection:(NSInteger)index];
}
#endif

-(void)confirmLogOut:(id)sender {
    NSAlert *alert = [NSAlert alertWithMessageText:DLLocalizedString(@"Log Out")
                                     defaultButton:DLLocalizedString(@"Log Out")
                                   alternateButton:DLLocalizedString(@"Cancel")
                                       otherButton:nil
                         informativeTextWithFormat:DLLocalizedString(@"Are you sure you want to log out?")];
    [alert beginSheetModalForWindow:self.window modalDelegate:self
                     didEndSelector:@selector(logOutAlertDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

-(void)logOutAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    if (returnCode != NSAlertDefaultReturn) return;
    [[alert window] orderOut:nil];
    [self.window close];
    [[DLController sharedInstance] logOutUser];
}

-(void)dealloc {
    [displayScalePopup release];
    [chatFontPopup release];
    [contentHost release];
    [settingsPanes release];
    [settingsSidebarButtons release];
    [themeButtons release];
    [friendEveryoneToggle release];
    [friendsOfFriendsToggle release];
    [friendServerMembersToggle release];
    [explicitFilterRows release];
    [spoilerRows release];
    [languageRows release];
    [accountSettingsControls release];
    [super dealloc];
}
@end
