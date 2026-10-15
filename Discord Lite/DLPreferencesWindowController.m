//
//  DLPreferencesWindowController.m
//  Discord Lite
//
//  Created by Collin Mistr on 8/23/22.
//  Copyright (c) 2022 dosdude1. All rights reserved.
//

#import "DLPreferencesWindowController.h"
#import "DLController.h"
#import "DLUtil.h"
#import "DLMainWindowChromeControls.h"
#import "DLTwemojiRenderer.h"
#import "NSView+BGColor.h"

static const CGFloat DLSettingsWindowWidth = 760.0;
static const CGFloat DLSettingsWindowHeight = 520.0;
static const CGFloat DLSettingsSidebarWidth = 210.0;
static const CGFloat DLSettingsContentLeft = 38.0;
static const CGFloat DLSettingsContentWidth = 470.0;

enum {
    DLSettingsSectionMyAccount = 0,
    DLSettingsSectionAppearance,
    DLSettingsSectionAccessibility,
    DLSettingsSectionChat,
    DLSettingsSectionNotifications,
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
    DLSettingsToggleDeveloperMode
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
        [[[DLUtil nativeSelectionColor] colorWithAlphaComponent:0.55] setFill];
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
    BOOL selected;
}
-(void)setSwatchColor:(NSColor *)color accentColor:(NSColor *)accent;
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
-(void)drawRect:(NSRect)dirtyRect {
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
-(void)selectSection:(NSInteger)section;
-(void)syncThemeButtons;
@end

@implementation DLPreferencesWindowController

- (void)windowDidLoad {
    [super windowDidLoad];

    [self.window setTitle:@"Legacy Discord Settings"];
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

    NSView_BGColor *background = [[NSView_BGColor alloc] initWithFrame:[[self.window contentView] bounds]];
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
        @"#USER SETTINGS", @"My Account",
        @"#APP SETTINGS", @"Appearance", @"Accessibility", @"-Voice & Video", @"Chat", @"Notifications", @"Advanced", nil];
    NSInteger sectionTags[] = { -1, DLSettingsSectionMyAccount, -1, DLSettingsSectionAppearance,
                                DLSettingsSectionAccessibility, -1, DLSettingsSectionChat,
                                DLSettingsSectionNotifications, DLSettingsSectionAdvanced };
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
            [button setToolTip:@"Voice chat is not available yet"];
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
    [logoutButton setTitle:@"Log Out"];
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
    [self selectSection:DLSettingsSectionAppearance];
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

-(NSView *)buildAccountPane {
    NSView *pane = [self newPaneWithTitle:@"My Account"];
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
    NSArray *fieldTitles = [NSArray arrayWithObjects:@"DISPLAY NAME", @"USERNAME", nil];
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
                                        text:@"Account details are shown read-only. Edit them in the official client; changes appear here after reconnecting."
                                        font:[NSFont systemFontOfSize:11.0]
                                       color:[DLUtil nativeSecondaryTextColor]];
    [[note cell] setWraps:YES];
    [note setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:note];
    return pane;
}

-(NSView *)buildAppearancePane {
    NSView *pane = [self newPaneWithTitle:@"Appearance"];
    CGFloat top = NSHeight([pane bounds]) - 82.0;

    [self sectionHeaderInPane:pane top:top text:@"THEME"];
    NSArray *themeTitles = [NSArray arrayWithObjects:@"Dark", @"Midnight", @"Aurora", nil];
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
        NSTextField *caption = [self labelWithFrame:NSMakeRect(DLSettingsContentLeft + index * 76.0 - 4.0, top - 102.0, 68.0, 16.0)
                                               text:[themeTitles objectAtIndex:index]
                                               font:[NSFont systemFontOfSize:11.0]
                                              color:[DLUtil nativeSecondaryTextColor]];
        [caption setAlignment:NSCenterTextAlignment];
        [caption setAutoresizingMask:NSViewMinYMargin];
        [pane addSubview:caption];
    }
    [self addDividerToPane:pane y:top - 118.0];

    CGFloat rowTop = top - 136.0;
    [self sectionHeaderInPane:pane top:rowTop text:@"CHAT FONT SCALING"];
    chatFontPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(DLSettingsContentLeft - 2.0, rowTop - 50.0, 220.0, 30.0) pullsDown:NO];
    [chatFontPopup setCell:[[[DLDarkPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO] autorelease]];
    NSInteger fontSizes[] = { 12, 13, 14, 15, 16, 18, 20 };
    for (NSUInteger index = 0; index < sizeof(fontSizes) / sizeof(fontSizes[0]); index++) {
        NSString *title = fontSizes[index] == 13 ? @"13px (default)" : [NSString stringWithFormat:@"%ldpx", (long)fontSizes[index]];
        [chatFontPopup addItemWithTitle:title];
        [[chatFontPopup lastItem] setTag:fontSizes[index]];
    }
    [chatFontPopup setTarget:self];
    [chatFontPopup setAction:@selector(chatFontSizeChanged:)];
    [chatFontPopup setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:chatFontPopup];

    rowTop -= 80.0;
    [self sectionHeaderInPane:pane top:rowTop text:@"ZOOM LEVEL"];
    displayScalePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(DLSettingsContentLeft - 2.0, rowTop - 50.0, 220.0, 30.0) pullsDown:NO];
    [displayScalePopup setCell:[[[DLDarkPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO] autorelease]];
    NSArray *titles = [NSArray arrayWithObjects:@"80%", @"90% (default)", @"100%", @"110%", @"125%", nil];
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
                                            text:@"Scales message text, avatars and spacing."
                                            font:[NSFont systemFontOfSize:11.0]
                                           color:[DLUtil nativeSecondaryTextColor]];
    [[zoomHelp cell] setWraps:YES];
    [zoomHelp setAutoresizingMask:NSViewMinYMargin];
    [pane addSubview:zoomHelp];
    return pane;
}

-(NSView *)buildAccessibilityPane {
    NSView *pane = [self newPaneWithTitle:@"Accessibility"];
    DLPreferencesHandler *preferences = [DLPreferencesHandler sharedInstance];
    CGFloat top = NSHeight([pane bounds]) - 82.0;
    top = [self addToggleToPane:pane top:top title:@"Show role colors in names"
                           help:@"Color member names in chat and the member list with their highest colored role."
                            tag:DLSettingsToggleRoleColors on:[preferences showRoleColors]];
    [self addToggleToPane:pane top:top title:@"Automatically play animated emoji"
                     help:@"When off, animated custom emoji show their first frame. Reduces CPU use on older Macs."
                      tag:DLSettingsToggleAnimatedEmoji on:[preferences autoplayAnimatedEmoji]];
    return pane;
}

-(NSView *)buildChatPane {
    NSView *pane = [self newPaneWithTitle:@"Chat"];
    DLPreferencesHandler *preferences = [DLPreferencesHandler sharedInstance];
    CGFloat top = NSHeight([pane bounds]) - 82.0;
    top = [self addToggleToPane:pane top:top title:@"Show emoji reactions on messages"
                           help:@"Display the reaction bar under messages that have reactions."
                            tag:DLSettingsToggleReactions on:[preferences showReactions]];
    [self addToggleToPane:pane top:top title:@"Show embeds and preview website links"
                     help:@"Show link previews and rich embeds sent by bots."
                      tag:DLSettingsToggleEmbeds on:[preferences showEmbeds]];
    return pane;
}

-(NSView *)buildNotificationsPane {
    NSView *pane = [self newPaneWithTitle:@"Notifications"];
    CGFloat top = NSHeight([pane bounds]) - 82.0;
    DLPreferencesHandler *preferences = [DLPreferencesHandler sharedInstance];
    top = [self addToggleToPane:pane top:top title:@"Enable Unread Message Badge"
                           help:@"Shows a red badge on the Dock icon with your mention and direct message count."
                            tag:DLSettingsToggleUnreadBadge on:[preferences showUnreadBadge]];
    top = [self addToggleToPane:pane top:top title:@"Bounce Dock Icon"
                           help:@"Bounces the Dock icon once when you are mentioned or receive a direct message while Legacy Discord is in the background."
                            tag:DLSettingsToggleBounceDock on:[preferences bounceDockIcon]];
    [self addToggleToPane:pane top:top title:@"Play a sound for mentions and direct messages"
                     help:@"Plays the mention sound when you are mentioned or receive a direct message."
                      tag:DLSettingsToggleMentionSound on:[preferences playMentionSound]];
    return pane;
}

-(NSView *)buildAdvancedPane {
    NSView *pane = [self newPaneWithTitle:@"Advanced"];
    CGFloat top = NSHeight([pane bounds]) - 82.0;
    [self addToggleToPane:pane top:top title:@"Developer Mode"
                     help:@"Adds Copy Message ID and Copy User ID to the message context menu."
                      tag:DLSettingsToggleDeveloperMode on:[[DLPreferencesHandler sharedInstance] developerMode]];
    return pane;
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
    NSArray *themes = [NSArray arrayWithObjects:@"default", @"midnight", @"aurora", nil];
    NSUInteger selectedIndex = [themes indexOfObject:[[DLPreferencesHandler sharedInstance] appearanceTheme]];
    for (NSUInteger index = 0; index < [themeButtons count]; index++) {
        [(DLThemeSwatchButton *)[themeButtons objectAtIndex:index] setSelected:(index == selectedIndex)];
    }
}

-(void)selectSection:(NSInteger)section {
    if (section < 0 || section >= DLSettingsSectionCount) return;
    selectedSection = section;
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
    NSInteger index = [(NSButton *)sender tag];
    if (index >= 0 && index < (NSInteger)[themes count]) {
        [[DLPreferencesHandler sharedInstance] setAppearanceTheme:[themes objectAtIndex:index]];
    }
    [self syncThemeButtons];
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
    }
    [sender setNeedsDisplay:YES];
}

- (IBAction)showSettingsSection:(id)sender {
    [self selectSection:[(NSButton *)sender tag]];
}

#if LEGACY_DISCORD_LOCAL_DEV
-(void)selectSettingsSectionNamed:(NSString *)name {
    NSArray *names = [NSArray arrayWithObjects:@"account", @"appearance", @"accessibility", @"chat", @"notifications", @"advanced", nil];
    NSUInteger index = [names indexOfObject:name];
    if (index != NSNotFound) [self selectSection:(NSInteger)index];
}
#endif

-(void)confirmLogOut:(id)sender {
    NSAlert *alert = [NSAlert alertWithMessageText:@"Log Out"
                                     defaultButton:@"Log Out"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@"Are you sure you want to log out?"];
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
    [super dealloc];
}
@end
