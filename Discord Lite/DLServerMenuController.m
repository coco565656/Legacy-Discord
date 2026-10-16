//
//  DLServerMenuController.m
//  Legacy Discord
//

#import "DLServerMenuController.h"
#import "DLDarkMenu.h"
#import "DLDialog.h"
#import "DLController.h"
#import "DLPreferencesHandler.h"
#import "DLMainWindowChromeControls.h"
#import "DLUtil.h"
#import <objc/runtime.h>

static DLServerMenuController *sharedServerMenuController = nil;
static char DLDialogServerKey;
static char DLDialogLevelRowsKey;
static char DLDialogTypeRowsKey;

// Discord's message_notifications values.
enum {
    DLNotifyAllMessages = 0,
    DLNotifyOnlyMentions = 1,
    DLNotifyNothing = 2,
    DLNotifyServerDefault = 3
};

static NSString *DLErrorMessageFromResponse(id json, NSInteger status) {
    if ([json isKindOfClass:[NSDictionary class]] && [[json objectForKey:@"message"] isKindOfClass:[NSString class]]) {
        return [json objectForKey:@"message"];
    }
    if (status == 0) return @"Could not reach Discord. Check your connection and try again.";
    return [NSString stringWithFormat:@"Something went wrong (HTTP %ld).", (long)status];
}

static BOOL DLStatusIsSuccess(NSInteger status) {
    return status >= 200 && status < 300;
}

@interface DLServerMenuController ()
-(NSWindow *)dialogWindow;
-(NSMenuItem *)itemWithTitle:(NSString *)title action:(SEL)action server:(DLServer *)server;
@end

@implementation DLServerMenuController

+(DLServerMenuController *)sharedController {
    if (!sharedServerMenuController) sharedServerMenuController = [[DLServerMenuController alloc] init];
    return sharedServerMenuController;
}

-(void)setWindow:(NSWindow *)inWindow {
    window = inWindow;
}

-(NSWindow *)dialogWindow {
    return window ? window : [NSApp mainWindow];
}

-(BOOL)isOwnerOfServer:(DLServer *)server {
    NSString *me = [[[[DLController sharedInstance] myUser] userID] description];
    return me && [[[server ownerID] description] isEqualToString:me];
}

-(NSDictionary *)settingsForServer:(DLServer *)server {
    return [[DLController sharedInstance] notificationSettingsForServerID:[server serverID]];
}

-(BOOL)settingsBoolForKey:(NSString *)key server:(DLServer *)server defaultValue:(BOOL)defaultValue {
    id value = [[self settingsForServer:server] objectForKey:key];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : defaultValue;
}

-(NSInteger)messageNotificationsForServer:(DLServer *)server {
    id value = [[self settingsForServer:server] objectForKey:@"message_notifications"];
    NSInteger level = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : DLNotifyServerDefault;
    return (level == DLNotifyServerDefault) ? [server defaultMessageNotifications] : level;
}

-(void)updateSettings:(NSDictionary *)changes forServer:(DLServer *)server {
    [[DLController sharedInstance] updateNotificationSettings:changes forServerID:[server serverID]];
}

#pragma mark Menus

-(NSMenuItem *)itemWithTitle:(NSString *)title action:(SEL)action server:(DLServer *)server {
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""] autorelease];
    [item setTarget:self];
    [item setRepresentedObject:server];
    return item;
}

-(NSMenuItem *)muteItemForServer:(DLServer *)server {
    if ([[DLController sharedInstance] isServerMuted:server]) {
        return [self itemWithTitle:@"Unmute Server" action:@selector(unmuteServer:) server:server];
    }
    NSMenuItem *mute = [self itemWithTitle:@"Mute Server" action:NULL server:server];
    NSMenu *durations = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    NSArray *titles = [NSArray arrayWithObjects:@"For 15 Minutes", @"For 1 Hour", @"For 3 Hours",
                       @"For 8 Hours", @"For 24 Hours", @"Until I turn it back on", nil];
    NSInteger seconds[] = { 15 * 60, 60 * 60, 3 * 60 * 60, 8 * 60 * 60, 24 * 60 * 60, 0 };
    NSUInteger index;
    for (index = 0; index < [titles count]; index++) {
        NSMenuItem *item = [self itemWithTitle:[titles objectAtIndex:index] action:@selector(muteServer:) server:server];
        [item setTag:seconds[index]];
        [durations addItem:item];
    }
    [mute setSubmenu:durations];
    return mute;
}

-(NSMenuItem *)notificationSubmenuItemForServer:(DLServer *)server {
    NSMenuItem *notifications = [self itemWithTitle:@"Notification Settings" action:NULL server:server];
    NSMenu *submenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    NSInteger level = [self messageNotificationsForServer:server];
    NSArray *titles = [NSArray arrayWithObjects:@"All Messages", @"Only @mentions", @"Nothing", nil];
    NSInteger index;
    for (index = 0; index < 3; index++) {
        NSMenuItem *item = [self itemWithTitle:[titles objectAtIndex:index] action:@selector(setNotificationLevel:) server:server];
        [item setTag:index];
        [item setState:(level == index ? NSOnState : NSOffState)];
        [DLDarkMenu setStyle:DLDarkMenuItemStyleRadio forItem:item];
        [submenu addItem:item];
    }
    [submenu addItem:[NSMenuItem separatorItem]];
    NSArray *toggles = [NSArray arrayWithObjects:
                        [NSArray arrayWithObjects:@"Suppress @everyone and @here", @"suppress_everyone", nil],
                        [NSArray arrayWithObjects:@"Suppress All Role @mentions", @"suppress_roles", nil],
                        [NSArray arrayWithObjects:@"Suppress Highlights", @"notify_highlights", nil],
                        [NSArray arrayWithObjects:@"Mute New Events", @"mute_scheduled_events", nil],
                        [NSArray arrayWithObjects:@"Mobile Push Notifications", @"mobile_push", nil], nil];
    NSEnumerator *enumerator = [toggles objectEnumerator];
    NSArray *toggle;
    while (toggle = [enumerator nextObject]) {
        NSString *key = [toggle objectAtIndex:1];
        NSMenuItem *item = [self itemWithTitle:[toggle objectAtIndex:0] action:@selector(toggleNotificationSetting:) server:server];
        [item setToolTip:key];
        BOOL on;
        if ([key isEqualToString:@"notify_highlights"]) {
            on = [[[self settingsForServer:server] objectForKey:key] respondsToSelector:@selector(integerValue)] &&
                 [[[self settingsForServer:server] objectForKey:key] integerValue] == 1;
        } else {
            on = [self settingsBoolForKey:key server:server defaultValue:[key isEqualToString:@"mobile_push"]];
        }
        [item setState:(on ? NSOnState : NSOffState)];
        [DLDarkMenu setStyle:DLDarkMenuItemStyleCheckbox forItem:item];
        [submenu addItem:item];
    }
    [notifications setSubmenu:submenu];
    return notifications;
}

-(NSMenuItem *)hideMutedItemForServer:(DLServer *)server {
    NSMenuItem *item = [self itemWithTitle:@"Hide Muted Channels" action:@selector(toggleHideMutedChannels:) server:server];
    [item setState:([[DLController sharedInstance] hidesMutedChannelsInServer:server] ? NSOnState : NSOffState)];
    [DLDarkMenu setStyle:DLDarkMenuItemStyleCheckbox forItem:item];
    return item;
}

-(void)addManagementItemsForServer:(DLServer *)server toMenu:(NSMenu *)menu icons:(BOOL)icons {
    if ([server iHavePermission:DLPermissionManageGuild]) {
        NSMenuItem *settings = [self itemWithTitle:@"Server Settings" action:@selector(openServerOverview:) server:server];
        if (icons) [DLDarkMenu setIconName:@"settings" forItem:settings];
        [menu addItem:settings];
    }
    if ([server iHavePermission:DLPermissionManageChannels]) {
        NSMenuItem *channel = [self itemWithTitle:@"Create Channel" action:@selector(createChannel:) server:server];
        NSMenuItem *category = [self itemWithTitle:@"Create Category" action:@selector(createCategory:) server:server];
        if (icons) {
            [DLDarkMenu setIconName:@"add" forItem:channel];
            [DLDarkMenu setIconName:@"folder" forItem:category];
        }
        [menu addItem:channel];
        [menu addItem:category];
    }
}

-(NSMenuItem *)leaveItemForServer:(DLServer *)server icon:(BOOL)icon {
    NSMenuItem *leave = [self itemWithTitle:@"Leave Server" action:@selector(leaveServer:) server:server];
    [DLDarkMenu setStyle:DLDarkMenuItemStyleDanger forItem:leave];
    if (icon) [DLDarkMenu setIconName:@"leave" forItem:leave];
    return leave;
}

-(NSMenu *)headerMenuForServer:(DLServer *)server {
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    if (!server) return menu;
    if ([server iHavePermission:DLPermissionCreateInvite]) {
        NSMenuItem *invite = [self itemWithTitle:@"Invite to Server" action:@selector(invitePeople:) server:server];
        [DLDarkMenu setStyle:DLDarkMenuItemStyleBrand forItem:invite];
        [DLDarkMenu setIconName:@"invite" forItem:invite];
        [menu addItem:invite];
    }
    [self addManagementItemsForServer:server toMenu:menu icons:YES];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *notifications = [self itemWithTitle:@"Notification Settings" action:@selector(openNotificationSettings:) server:server];
    [DLDarkMenu setIconName:@"bell" forItem:notifications];
    [menu addItem:notifications];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *profile = [self itemWithTitle:@"Edit Per-server Profile" action:@selector(editServerProfile:) server:server];
    [DLDarkMenu setIconName:@"pencil" forItem:profile];
    [menu addItem:profile];
    [menu addItem:[self hideMutedItemForServer:server]];
    if (![self isOwnerOfServer:server]) {
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:[self leaveItemForServer:server icon:YES]];
    }
    if ([[DLPreferencesHandler sharedInstance] developerMode]) {
        [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *copyID = [self itemWithTitle:@"Copy Server ID" action:@selector(copyServerID:) server:server];
        [DLDarkMenu setIconName:@"id" forItem:copyID];
        [menu addItem:copyID];
    }
    return menu;
}

-(NSMenu *)contextMenuForServer:(DLServer *)server {
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    if (!server || [server isEqual:[[DLController sharedInstance] myServerItem]]) return menu;
    NSMenuItem *markRead = [self itemWithTitle:@"Mark As Read" action:@selector(markServerAsRead:) server:server];
    [markRead setEnabled:([server hasUnreadMessages] || [server mentionCount] > 0)];
    [menu setAutoenablesItems:NO];
    [menu addItem:markRead];
    [menu addItem:[NSMenuItem separatorItem]];
    if ([server iHavePermission:DLPermissionCreateInvite]) {
        NSMenuItem *invite = [self itemWithTitle:@"Invite to Server" action:@selector(invitePeople:) server:server];
        [DLDarkMenu setStyle:DLDarkMenuItemStyleBrand forItem:invite];
        [menu addItem:invite];
        [menu addItem:[NSMenuItem separatorItem]];
    }
    [menu addItem:[self muteItemForServer:server]];
    [menu addItem:[self notificationSubmenuItemForServer:server]];
    [menu addItem:[self hideMutedItemForServer:server]];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addManagementItemsForServer:server toMenu:menu icons:NO];
    [menu addItem:[self itemWithTitle:@"Edit Per-server Profile" action:@selector(editServerProfile:) server:server]];
    if (![self isOwnerOfServer:server]) {
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:[self leaveItemForServer:server icon:NO]];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *link = [self itemWithTitle:@"Copy Server Link" action:@selector(copyServerLink:) server:server];
    [DLDarkMenu setIconName:@"link" forItem:link];
    [menu addItem:link];
    if ([[DLPreferencesHandler sharedInstance] developerMode]) {
        NSMenuItem *copyID = [self itemWithTitle:@"Copy Server ID" action:@selector(copyServerID:) server:server];
        [DLDarkMenu setIconName:@"id" forItem:copyID];
        [menu addItem:copyID];
    }
    return menu;
}

#pragma mark Menu actions

-(void)markServerAsRead:(NSMenuItem *)sender {
    [[DLController sharedInstance] markServerAsRead:[sender representedObject]];
}

-(void)muteServer:(NSMenuItem *)sender {
    [[DLController sharedInstance] setMuted:YES duration:(NSTimeInterval)[sender tag] forServer:[sender representedObject]];
}

-(void)unmuteServer:(NSMenuItem *)sender {
    [[DLController sharedInstance] setMuted:NO duration:0 forServer:[sender representedObject]];
}

-(void)setNotificationLevel:(NSMenuItem *)sender {
    [self updateSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:[sender tag]] forKey:@"message_notifications"]
               forServer:[sender representedObject]];
}

-(void)toggleNotificationSetting:(NSMenuItem *)sender {
    NSString *key = [sender toolTip];
    BOOL on = ([sender state] != NSOnState);
    id value = [key isEqualToString:@"notify_highlights"] ? (id)[NSNumber numberWithInteger:(on ? 1 : 0)]
                                                         : (id)[NSNumber numberWithBool:on];
    [self updateSettings:[NSDictionary dictionaryWithObject:value forKey:key] forServer:[sender representedObject]];
}

-(void)toggleHideMutedChannels:(NSMenuItem *)sender {
    DLServer *server = [sender representedObject];
    BOOL hide = ![[DLController sharedInstance] hidesMutedChannelsInServer:server];
    [self updateSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:hide] forKey:@"hide_muted_channels"]
               forServer:server];
    [[DLController sharedInstance] notifyChannelsChangedForServer:server];
}

-(void)invitePeople:(NSMenuItem *)sender { [self showInviteDialogForServer:[sender representedObject]]; }
-(void)openServerOverview:(NSMenuItem *)sender { [self showServerOverviewForServer:[sender representedObject]]; }
-(void)createChannel:(NSMenuItem *)sender { [self showCreateChannelDialogForServer:[sender representedObject] category:NO parentID:nil]; }
-(void)createCategory:(NSMenuItem *)sender { [self showCreateChannelDialogForServer:[sender representedObject] category:YES parentID:nil]; }
-(void)openNotificationSettings:(NSMenuItem *)sender { [self showNotificationSettingsForServer:[sender representedObject]]; }
-(void)editServerProfile:(NSMenuItem *)sender { [self showServerProfileDialogForServer:[sender representedObject]]; }
-(void)leaveServer:(NSMenuItem *)sender { [self showLeaveDialogForServer:[sender representedObject]]; }

-(void)copyServerLink:(NSMenuItem *)sender {
    [DLUtil copyStringToPasteboard:[NSString stringWithFormat:@"https://discord.com/channels/%@", [[sender representedObject] serverID]]];
}

-(void)copyServerID:(NSMenuItem *)sender {
    [DLUtil copyStringToPasteboard:[[[sender representedObject] serverID] description]];
}

#pragma mark Invite

-(void)showInviteDialogForServer:(DLServer *)server {
    [self showInviteDialogForServer:server channel:nil];
}

-(void)showInviteDialogForServer:(DLServer *)server channel:(DLChannel *)inviteChannel {
    DLChannel *channel = inviteChannel ? inviteChannel : (DLChannel *)[[DLController sharedInstance] defaultInviteChannelForServer:server];
    DLDialog *dialog = [DLDialog dialogWithTitle:[NSString stringWithFormat:@"Invite friends to %@", [server name]]
                                         message:(inviteChannel ? [@"Recipients will land in #" stringByAppendingString:[inviteChannel name]] : nil)];
    CGFloat inner = 440.0 - 32.0;
    NSView *content = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, inner, 92.0)] autorelease];
    NSTextField *section = [DLDialog sectionLabelWithString:@"Send a server invite link to a friend"
                                                      frame:NSMakeRect(0.0, 66.0, inner, 16.0)];
    [content addSubview:section];
    NSView *box = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 22.0, inner, 40.0)] autorelease];
    [box setWantsLayer:NO];
    NSTextField *linkField = [DLDialog textFieldWithFrame:NSMakeRect(10.0, 10.0, inner - 100.0, 20.0) placeholder:nil];
    [linkField setEditable:NO];
    [linkField setSelectable:YES];
    [linkField setDrawsBackground:NO];
    [linkField setStringValue:(channel ? @"Creating an invite…" : @"No channel to invite to.")];
    DLPrimaryButton *copyButton = [[[DLPrimaryButton alloc] initWithFrame:NSMakeRect(inner - 80.0, 4.0, 76.0, 32.0)] autorelease];
    [copyButton setTitle:@"Copy"];
    [copyButton setBordered:NO];
    [copyButton setEnabled:NO];
    NSBox *background = [[[NSBox alloc] initWithFrame:NSMakeRect(0.0, 22.0, inner, 40.0)] autorelease];
    [background setBoxType:NSBoxCustom];
    [background setBorderType:NSNoBorder];
    [background setFillColor:[DLUtil nativeServerRailColor]];
    [background setCornerRadius:4.0];
    [background setContentViewMargins:NSZeroSize];
    [[background contentView] addSubview:linkField];
    [[background contentView] addSubview:copyButton];
    [content addSubview:background];
    NSTextField *expiry = [DLDialog labelWithString:@"Your invite link expires in 7 days." frame:NSMakeRect(0.0, 0.0, inner, 16.0)];
    [expiry setFont:[NSFont systemFontOfSize:12.0]];
    [content addSubview:expiry];
    [dialog setContentView:content];
    [dialog addButtonWithTitle:@"Done" style:DLDialogButtonStylePrimary];
    [dialog showInWindow:[self dialogWindow]];
    if (!channel) return;

    [dialog retain];
    [[DLController sharedInstance] sendAPIRequestWithMethod:@"POST"
        path:[NSString stringWithFormat:@"/channels/%@/invites", [channel channelID]]
        body:[NSDictionary dictionaryWithObjectsAndKeys:
              [NSNumber numberWithInteger:604800], @"max_age",
              [NSNumber numberWithInteger:0], @"max_uses",
              [NSNumber numberWithBool:NO], @"temporary", nil]
        completion:^(id json, NSInteger status) {
            NSString *code = [json isKindOfClass:[NSDictionary class]] ? [json objectForKey:@"code"] : nil;
            if (DLStatusIsSuccess(status) && [code isKindOfClass:[NSString class]]) {
                NSString *link = [@"https://discord.gg/" stringByAppendingString:code];
                [linkField setStringValue:link];
                [copyButton setEnabled:YES];
                [copyButton setTarget:self];
                [copyButton setAction:@selector(copyInviteLink:)];
                [copyButton setToolTip:link];
            } else {
                [linkField setStringValue:@""];
                [dialog setErrorMessage:DLErrorMessageFromResponse(json, status)];
            }
            [dialog release];
        }];
}

-(void)copyInviteLink:(NSButton *)sender {
    [DLUtil copyStringToPasteboard:[sender toolTip]];
    [sender setTitle:@"Copied"];
}

#pragma mark Notification settings

-(void)showNotificationSettingsForServer:(DLServer *)server {
    CGFloat inner = 480.0 - 32.0;
    NSView *content = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, inner, 10.0)] autorelease];
    NSMutableArray *rows = [NSMutableArray array];

    DLSwitchRow *muteRow = [[[DLSwitchRow alloc] initWithFrame:NSMakeRect(0.0, 0.0, inner, 10.0)
        title:[NSString stringWithFormat:@"Mute %@", [server name]]
        detail:@"Muting a server prevents unread indicators and notifications from appearing unless you are mentioned."] autorelease];
    [[muteRow toggle] setOn:[[DLController sharedInstance] isServerMuted:server]];
    [[muteRow toggle] setTarget:self];
    [[muteRow toggle] setAction:@selector(notificationSwitchChanged:)];
    [[muteRow toggle] setToolTip:@"muted"];
    [rows addObject:muteRow];

    [rows addObject:[DLDialog sectionLabelWithString:@"Server Notification Settings" frame:NSMakeRect(0.0, 0.0, inner, 28.0)]];
    NSArray *levels = [NSArray arrayWithObjects:@"All Messages", @"Only @mentions", @"Nothing", nil];
    NSInteger level = [self messageNotificationsForServer:server];
    NSMutableArray *levelRows = [NSMutableArray array];
    NSInteger index;
    for (index = 0; index < 3; index++) {
        DLOptionRow *row = [[[DLOptionRow alloc] initWithFrame:NSMakeRect(0.0, 0.0, inner, 44.0)] autorelease];
        [row setTitle:[levels objectAtIndex:index]];
        [row setSelected:(index == level)];
        [row setTag:index];
        [row setTarget:self];
        [row setAction:@selector(notificationLevelRowClicked:)];
        [levelRows addObject:row];
        [rows addObject:row];
    }

    NSArray *switches = [NSArray arrayWithObjects:
        [NSArray arrayWithObjects:@"Suppress @everyone and @here", @"suppress_everyone", @"", nil],
        [NSArray arrayWithObjects:@"Suppress All Role @mentions", @"suppress_roles", @"", nil],
        [NSArray arrayWithObjects:@"Suppress Highlights", @"notify_highlights",
         @"Highlights provide occasional updates when your friends are chatting in busy servers.", nil],
        [NSArray arrayWithObjects:@"Mute New Events", @"mute_scheduled_events",
         @"Turning this on will prevent you from being notified of new events.", nil],
        [NSArray arrayWithObjects:@"Mobile Push Notifications", @"mobile_push", @"", nil], nil];
    NSEnumerator *enumerator = [switches objectEnumerator];
    NSArray *spec;
    BOOL first = YES;
    while (spec = [enumerator nextObject]) {
        NSString *key = [spec objectAtIndex:1];
        DLSwitchRow *row = [[[DLSwitchRow alloc] initWithFrame:NSMakeRect(0.0, 0.0, inner, 10.0)
                                                         title:[spec objectAtIndex:0] detail:[spec objectAtIndex:2]] autorelease];
        BOOL on;
        if ([key isEqualToString:@"notify_highlights"]) {
            id value = [[self settingsForServer:server] objectForKey:key];
            on = [value respondsToSelector:@selector(integerValue)] && [value integerValue] == 1;
        } else {
            on = [self settingsBoolForKey:key server:server defaultValue:[key isEqualToString:@"mobile_push"]];
        }
        [[row toggle] setOn:on];
        [[row toggle] setToolTip:key];
        [[row toggle] setTarget:self];
        [[row toggle] setAction:@selector(notificationSwitchChanged:)];
        if (first) {
            NSView *spacer = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, inner, 12.0)] autorelease];
            [rows addObject:spacer];
            first = NO;
        }
        [rows addObject:row];
    }

    // Stack top to bottom (the content view is not flipped).
    CGFloat total = 0.0;
    enumerator = [rows objectEnumerator];
    NSView *row;
    while (row = [enumerator nextObject]) total += NSHeight([row frame]) + ([row isKindOfClass:[DLOptionRow class]] ? 8.0 : 8.0);
    [content setFrameSize:NSMakeSize(inner, total)];
    CGFloat y = total;
    enumerator = [rows objectEnumerator];
    while (row = [enumerator nextObject]) {
        y -= NSHeight([row frame]);
        NSRect frame = [row frame];
        frame.origin = NSMakePoint(0.0, y);
        [row setFrame:frame];
        [content addSubview:row];
        y -= 8.0;
    }
    objc_setAssociatedObject(content, &DLDialogServerKey, server, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(content, &DLDialogLevelRowsKey, levelRows, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    DLDialog *dialog = [DLDialog dialogWithTitle:@"Notification Settings" message:[server name]];
    [dialog setWidth:480.0];
    [dialog setContentView:content];
    [dialog addButtonWithTitle:@"Done" style:DLDialogButtonStylePrimary];
    [dialog showInWindow:[self dialogWindow]];
}

-(DLServer *)serverForDialogControl:(NSView *)control {
    NSView *view = control;
    while (view) {
        DLServer *server = objc_getAssociatedObject(view, &DLDialogServerKey);
        if (server) return server;
        view = [view superview];
    }
    return nil;
}

-(void)notificationSwitchChanged:(DLToggleSwitch *)sender {
    DLServer *server = [self serverForDialogControl:sender];
    if (!server) return;
    NSString *key = [sender toolTip];
    if ([key isEqualToString:@"muted"]) {
        [[DLController sharedInstance] setMuted:[sender isOn] duration:0 forServer:server];
        return;
    }
    id value = [key isEqualToString:@"notify_highlights"] ? (id)[NSNumber numberWithInteger:([sender isOn] ? 1 : 0)]
                                                         : (id)[NSNumber numberWithBool:[sender isOn]];
    [self updateSettings:[NSDictionary dictionaryWithObject:value forKey:key] forServer:server];
}

-(void)notificationLevelRowClicked:(DLOptionRow *)sender {
    DLServer *server = [self serverForDialogControl:sender];
    NSArray *levelRows = objc_getAssociatedObject([sender superview], &DLDialogLevelRowsKey);
    NSEnumerator *enumerator = [levelRows objectEnumerator];
    DLOptionRow *row;
    while (row = [enumerator nextObject]) [row setSelected:(row == sender)];
    if (server) {
        [self updateSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:[sender tag]] forKey:@"message_notifications"]
                   forServer:server];
    }
}

#pragma mark Create channel

-(void)channelTypeRowClicked:(DLOptionRow *)sender {
    NSArray *typeRows = objc_getAssociatedObject([sender superview], &DLDialogTypeRowsKey);
    NSEnumerator *enumerator = [typeRows objectEnumerator];
    DLOptionRow *row;
    while (row = [enumerator nextObject]) [row setSelected:(row == sender)];
}

-(void)showCreateChannelDialogForServer:(DLServer *)server category:(BOOL)category parentID:(NSString *)parentID {
    CGFloat inner = 460.0 - 32.0;
    NSView *content = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, inner, 10.0)] autorelease];
    NSMutableArray *typeRows = [NSMutableArray array];
    CGFloat y = 0.0;
    NSTextField *nameField = [DLDialog textFieldWithFrame:NSMakeRect(0.0, y, inner, 40.0)
                                              placeholder:(category ? @"New Category" : @"new-channel")];
    [content addSubview:nameField];
    y += 40.0 + 8.0;
    NSTextField *nameLabel = [DLDialog sectionLabelWithString:(category ? @"Category Name" : @"Channel Name")
                                                        frame:NSMakeRect(0.0, y, inner, 16.0)];
    [content addSubview:nameLabel];
    y += 16.0 + 16.0;
    if (!category) {
        NSArray *types = [NSArray arrayWithObjects:
            [NSArray arrayWithObjects:@"Forum", @"Create a space for organized discussions", @"forum",
             [NSNumber numberWithInt:ChannelTypeForum], nil],
            [NSArray arrayWithObjects:@"Voice", @"Hang out together with voice, video, and screen share", @"speaker",
             [NSNumber numberWithInt:ChannelTypeVoice], nil],
            [NSArray arrayWithObjects:@"Text", @"Send messages, images, GIFs, emoji, opinions, and puns", @"hash",
             [NSNumber numberWithInt:ChannelTypeStandard], nil], nil];
        NSEnumerator *enumerator = [types objectEnumerator];
        NSArray *type;
        while (type = [enumerator nextObject]) {
            DLOptionRow *row = [[[DLOptionRow alloc] initWithFrame:NSMakeRect(0.0, y, inner, 56.0)] autorelease];
            [row setTitle:[type objectAtIndex:0]];
            [row setDetail:[type objectAtIndex:1]];
            [row setIconName:[type objectAtIndex:2]];
            [row setTag:[[type objectAtIndex:3] intValue]];
            [row setSelected:([[type objectAtIndex:3] intValue] == ChannelTypeStandard)];
            [row setTarget:self];
            [row setAction:@selector(channelTypeRowClicked:)];
            [content addSubview:row];
            [typeRows insertObject:row atIndex:0];
            y += 56.0 + 8.0;
        }
        NSTextField *typeLabel = [DLDialog sectionLabelWithString:@"Channel Type" frame:NSMakeRect(0.0, y, inner, 16.0)];
        [content addSubview:typeLabel];
        y += 16.0;
        objc_setAssociatedObject(content, &DLDialogTypeRowsKey, typeRows, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [content setFrameSize:NSMakeSize(inner, y)];

    NSString *subtitle = nil;
    if (parentID) {
        DLChannel *parent = [[DLController sharedInstance] loadedChannelWithID:parentID];
        if ([parent name]) subtitle = [NSString stringWithFormat:@"in %@", [parent name]];
    }
    DLDialog *dialog = [DLDialog dialogWithTitle:(category ? @"Create Category" : @"Create Channel") message:subtitle];
    [dialog setWidth:460.0];
    [dialog setContentView:content];
    [dialog addButtonWithTitle:(category ? @"Create Category" : @"Create Channel") style:DLDialogButtonStylePrimary];
    [dialog addButtonWithTitle:@"Cancel" style:DLDialogButtonStyleLink];
    NSString *serverID = [[server serverID] description];
    NSString *parent = [[parentID copy] autorelease];
    [dialog setHandler:^BOOL(DLDialog *shown, NSInteger buttonIndex) {
        if (buttonIndex != 0) return YES;
        NSString *name = [[nameField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (![name length]) {
            [shown setErrorMessage:@"Enter a name."];
            return NO;
        }
        NSInteger type = category ? ChannelTypeHeader : ChannelTypeStandard;
        NSEnumerator *rowEnumerator = [typeRows objectEnumerator];
        DLOptionRow *row;
        while (row = [rowEnumerator nextObject]) if ([row isSelected]) type = [row tag];
        NSMutableDictionary *body = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                     name, @"name", [NSNumber numberWithInteger:type], @"type", nil];
        if (parent && !category) [body setObject:parent forKey:@"parent_id"];
        [shown setBusy:YES];
        [shown setErrorMessage:nil];
        [shown retain];
        [[DLController sharedInstance] sendAPIRequestWithMethod:@"POST"
            path:[NSString stringWithFormat:@"/guilds/%@/channels", serverID] body:body
            completion:^(id json, NSInteger status) {
                if (DLStatusIsSuccess(status) && [json isKindOfClass:[NSDictionary class]]) {
                    NSMutableDictionary *data = [NSMutableDictionary dictionaryWithDictionary:json];
                    if (![data objectForKey:@"guild_id"]) [data setObject:serverID forKey:@"guild_id"];
                    [[DLController sharedInstance] addServerChannelWithData:data];
                    [shown close];
                } else {
                    [shown setBusy:NO];
                    [shown setErrorMessage:DLErrorMessageFromResponse(json, status)];
                }
                [shown release];
            }];
        return NO;
    }];
    [dialog showInWindow:[self dialogWindow]];
}

#pragma mark Per-server profile

-(void)showServerProfileDialogForServer:(DLServer *)server {
    CGFloat inner = 440.0 - 32.0;
    BOOL canChange = [server iHavePermission:DLPermissionChangeNickname];
    NSView *content = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, inner, 64.0)] autorelease];
    NSTextField *label = [DLDialog sectionLabelWithString:@"Server Nickname" frame:NSMakeRect(0.0, 48.0, inner, 16.0)];
    [content addSubview:label];
    DLUser *me = [[DLController sharedInstance] myUser];
    NSString *placeholder = [me globalName] ? [me globalName] : [me username];
    NSTextField *field = [DLDialog textFieldWithFrame:NSMakeRect(0.0, 0.0, inner, 40.0) placeholder:placeholder];
    [field setStringValue:([server myNickname] ? [server myNickname] : @"")];
    [field setEditable:canChange];
    [content addSubview:field];
    DLDialog *dialog = [DLDialog dialogWithTitle:@"Edit Per-server Profile"
        message:(canChange ? [NSString stringWithFormat:@"Your nickname is shown to everyone in %@ instead of your display name.", [server name]]
                           : @"You do not have permission to change your nickname in this server.")];
    [dialog setContentView:content];
    if (canChange) [dialog addButtonWithTitle:@"Save" style:DLDialogButtonStylePrimary];
    [dialog addButtonWithTitle:(canChange ? @"Cancel" : @"Close") style:DLDialogButtonStyleLink];
    NSString *serverID = [[server serverID] description];
    [dialog setHandler:^BOOL(DLDialog *shown, NSInteger buttonIndex) {
        if (buttonIndex != 0 || !canChange) return YES;
        NSString *nick = [[field stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [shown setBusy:YES];
        [shown retain];
        [[DLController sharedInstance] sendAPIRequestWithMethod:@"PATCH"
            path:[NSString stringWithFormat:@"/guilds/%@/members/@me", serverID]
            body:[NSDictionary dictionaryWithObject:([nick length] ? (id)nick : (id)[NSNull null]) forKey:@"nick"]
            completion:^(id json, NSInteger status) {
                if (DLStatusIsSuccess(status)) {
                    [[[DLController sharedInstance] loadedServerWithID:serverID] setMyNickname:nick];
                    [shown close];
                } else {
                    [shown setBusy:NO];
                    [shown setErrorMessage:DLErrorMessageFromResponse(json, status)];
                }
                [shown release];
            }];
        return NO;
    }];
    [dialog showInWindow:[self dialogWindow]];
}

#pragma mark Server overview

-(void)showServerOverviewForServer:(DLServer *)server {
    CGFloat inner = 440.0 - 32.0;
    NSView *content = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, inner, 64.0)] autorelease];
    [content addSubview:[DLDialog sectionLabelWithString:@"Server Name" frame:NSMakeRect(0.0, 48.0, inner, 16.0)]];
    NSTextField *field = [DLDialog textFieldWithFrame:NSMakeRect(0.0, 0.0, inner, 40.0) placeholder:nil];
    [field setStringValue:([server name] ? [server name] : @"")];
    [content addSubview:field];
    DLDialog *dialog = [DLDialog dialogWithTitle:@"Server Overview" message:nil];
    [dialog setContentView:content];
    [dialog addButtonWithTitle:@"Save Changes" style:DLDialogButtonStylePrimary];
    [dialog addButtonWithTitle:@"Cancel" style:DLDialogButtonStyleLink];
    NSString *serverID = [[server serverID] description];
    [dialog setHandler:^BOOL(DLDialog *shown, NSInteger buttonIndex) {
        if (buttonIndex != 0) return YES;
        NSString *name = [[field stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([name length] < 2) {
            [shown setErrorMessage:@"Server names must be between 2 and 100 characters."];
            return NO;
        }
        DLServer *current = [[DLController sharedInstance] loadedServerWithID:serverID];
        if ([name isEqualToString:[current name]]) return YES;
        [shown setBusy:YES];
        [shown retain];
        [[DLController sharedInstance] sendAPIRequestWithMethod:@"PATCH"
            path:[NSString stringWithFormat:@"/guilds/%@", serverID]
            body:[NSDictionary dictionaryWithObject:name forKey:@"name"]
            completion:^(id json, NSInteger status) {
                if (DLStatusIsSuccess(status)) {
                    DLServer *updated = [[DLController sharedInstance] loadedServerWithID:serverID];
                    [updated setName:name];
                    [[DLController sharedInstance] notifyChannelsChangedForServer:updated];
                    [shown close];
                } else {
                    [shown setBusy:NO];
                    [shown setErrorMessage:DLErrorMessageFromResponse(json, status)];
                }
                [shown release];
            }];
        return NO;
    }];
    [dialog showInWindow:[self dialogWindow]];
}

#pragma mark Channels

-(DLServer *)serverForChannel:(DLChannel *)channel {
    if (![channel isKindOfClass:[DLServerChannel class]]) return nil;
    return [[DLController sharedInstance] loadedServerWithID:[(DLServerChannel *)channel serverID]];
}

-(BOOL)hasPermission:(unsigned long long)permission inChannel:(DLChannel *)channel {
    DLServer *server = [self serverForChannel:channel];
    return server && [server iHavePermission:permission withOverwrites:[(DLServerChannel *)channel permissionOverwrites]];
}

-(NSDictionary *)overrideForChannel:(DLChannel *)channel {
    id overrides = [[self settingsForServer:[self serverForChannel:channel]] objectForKey:@"channel_overrides"];
    NSString *channelID = [[channel channelID] description];
    if ([overrides isKindOfClass:[NSDictionary class]]) return [overrides objectForKey:channelID];
    NSEnumerator *enumerator = [overrides objectEnumerator];
    NSDictionary *override;
    while (override = [enumerator nextObject]) {
        if ([override isKindOfClass:[NSDictionary class]] &&
            [[[override objectForKey:@"channel_id"] description] isEqualToString:channelID]) return override;
    }
    return nil;
}

-(NSMenuItem *)notificationItemForChannel:(DLChannel *)channel {
    NSMenuItem *notifications = [[[NSMenuItem alloc] initWithTitle:@"Notification Settings" action:NULL keyEquivalent:@""] autorelease];
    NSMenu *submenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    id value = [[self overrideForChannel:channel] objectForKey:@"message_notifications"];
    NSInteger level = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : DLNotifyServerDefault;
    BOOL inCategory = [channel isKindOfClass:[DLServerChannel class]] &&
                      [[(DLServerChannel *)channel parentID] isKindOfClass:[NSString class]] && [channel type] != ChannelTypeHeader;
    NSArray *titles = [NSArray arrayWithObjects:(inCategory ? @"Use Category Default" : @"Use Server Default"),
                       @"All Messages", @"Only @mentions", @"Nothing", nil];
    NSInteger values[] = { DLNotifyServerDefault, DLNotifyAllMessages, DLNotifyOnlyMentions, DLNotifyNothing };
    NSUInteger index;
    for (index = 0; index < [titles count]; index++) {
        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:[titles objectAtIndex:index]
                                                       action:@selector(setChannelNotificationLevel:) keyEquivalent:@""] autorelease];
        [item setTarget:self];
        [item setRepresentedObject:channel];
        [item setTag:values[index]];
        [item setState:(level == values[index] ? NSOnState : NSOffState)];
        [DLDarkMenu setStyle:DLDarkMenuItemStyleRadio forItem:item];
        [submenu addItem:item];
        if (index == 0) [submenu addItem:[NSMenuItem separatorItem]];
    }
    [notifications setSubmenu:submenu];
    return notifications;
}

-(void)setChannelNotificationLevel:(NSMenuItem *)sender {
    DLChannel *channel = [sender representedObject];
    NSDictionary *change = [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:[sender tag]] forKey:@"message_notifications"];
    [self updateSettings:[NSDictionary dictionaryWithObject:[NSDictionary dictionaryWithObject:change forKey:[[channel channelID] description]]
                                                     forKey:@"channel_overrides"]
               forServer:[self serverForChannel:channel]];
}

-(void)showEditChannelDialogForChannel:(DLChannel *)channel {
    BOOL category = [channel type] == ChannelTypeHeader;
    CGFloat inner = 440.0 - 32.0;
    NSView *content = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, inner, category ? 64.0 : 148.0)] autorelease];
    CGFloat top = NSHeight([content frame]);
    [content addSubview:[DLDialog sectionLabelWithString:(category ? @"Category Name" : @"Channel Name")
                                                   frame:NSMakeRect(0.0, top - 16.0, inner, 16.0)]];
    NSTextField *nameField = [DLDialog textFieldWithFrame:NSMakeRect(0.0, top - 64.0, inner, 40.0) placeholder:nil];
    [nameField setStringValue:([channel name] ? [channel name] : @"")];
    [content addSubview:nameField];
    NSTextField *topicField = nil;
    if (!category) {
        [content addSubview:[DLDialog sectionLabelWithString:@"Channel Topic" frame:NSMakeRect(0.0, 64.0, inner, 16.0)]];
        topicField = [DLDialog textFieldWithFrame:NSMakeRect(0.0, 16.0, inner, 40.0) placeholder:@"Let everyone know how to use this channel!"];
        NSString *topic = [channel respondsToSelector:@selector(topic)] ? [(DLServerChannel *)channel topic] : nil;
        [topicField setStringValue:([topic isKindOfClass:[NSString class]] ? topic : @"")];
        [content addSubview:topicField];
    }
    DLDialog *dialog = [DLDialog dialogWithTitle:(category ? @"Edit Category" : @"Edit Channel") message:nil];
    [dialog setContentView:content];
    [dialog addButtonWithTitle:@"Save Changes" style:DLDialogButtonStylePrimary];
    [dialog addButtonWithTitle:@"Cancel" style:DLDialogButtonStyleLink];
    NSString *channelID = [[channel channelID] description];
    [dialog setHandler:^BOOL(DLDialog *shown, NSInteger buttonIndex) {
        if (buttonIndex != 0) return YES;
        NSString *name = [[nameField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (![name length]) {
            [shown setErrorMessage:@"Enter a name."];
            return NO;
        }
        NSMutableDictionary *body = [NSMutableDictionary dictionaryWithObject:name forKey:@"name"];
        if (topicField) [body setObject:[topicField stringValue] forKey:@"topic"];
        [shown setBusy:YES];
        [shown retain];
        [[DLController sharedInstance] sendAPIRequestWithMethod:@"PATCH" path:[NSString stringWithFormat:@"/channels/%@", channelID]
            body:body completion:^(id json, NSInteger status) {
                if (DLStatusIsSuccess(status) && [json isKindOfClass:[NSDictionary class]]) {
                    DLChannel *updated = [[DLController sharedInstance] loadedChannelWithID:channelID];
                    [updated updateWithDict:json];
                    [[DLController sharedInstance] notifyChannelsChangedForServer:[self serverForChannel:updated]];
                    [shown close];
                } else {
                    [shown setBusy:NO];
                    [shown setErrorMessage:DLErrorMessageFromResponse(json, status)];
                }
                [shown release];
            }];
        return NO;
    }];
    [dialog showInWindow:[self dialogWindow]];
}

-(void)showDeleteChannelDialogForChannel:(DLChannel *)channel {
    BOOL category = [channel type] == ChannelTypeHeader;
    DLDialog *dialog = [DLDialog dialogWithTitle:(category ? @"Delete Category" : @"Delete Channel")
        message:[NSString stringWithFormat:@"Are you sure you want to delete %@%@? This cannot be undone.",
                 (category ? @"" : @"#"), [channel name]]];
    [dialog addButtonWithTitle:(category ? @"Delete Category" : @"Delete Channel") style:DLDialogButtonStyleDanger];
    [dialog addButtonWithTitle:@"Cancel" style:DLDialogButtonStyleLink];
    NSString *channelID = [[channel channelID] description];
    DLServer *server = [self serverForChannel:channel];
    [dialog setHandler:^BOOL(DLDialog *shown, NSInteger buttonIndex) {
        if (buttonIndex != 0) return YES;
        [shown setBusy:YES];
        [shown retain];
        [[DLController sharedInstance] sendAPIRequestWithMethod:@"DELETE" path:[NSString stringWithFormat:@"/channels/%@", channelID]
            body:nil completion:^(id json, NSInteger status) {
                if (DLStatusIsSuccess(status)) {
                    [[DLController sharedInstance] removeChannelWithID:channelID];
                    [[DLController sharedInstance] notifyChannelsChangedForServer:server];
                    [shown close];
                } else {
                    [shown setBusy:NO];
                    [shown setErrorMessage:DLErrorMessageFromResponse(json, status)];
                }
                [shown release];
            }];
        return NO;
    }];
    [dialog showInWindow:[self dialogWindow]];
}

#pragma mark Leave

-(void)showLeaveDialogForServer:(DLServer *)server {
    DLDialog *dialog = [DLDialog dialogWithTitle:[NSString stringWithFormat:@"Leave '%@'", [server name]]
        message:[NSString stringWithFormat:@"Are you sure you want to leave %@? You won't be able to rejoin this server unless you are re-invited.", [server name]]];
    [dialog addButtonWithTitle:@"Leave Server" style:DLDialogButtonStyleDanger];
    [dialog addButtonWithTitle:@"Cancel" style:DLDialogButtonStyleLink];
    NSString *serverID = [[server serverID] description];
    [dialog setHandler:^BOOL(DLDialog *shown, NSInteger buttonIndex) {
        if (buttonIndex != 0) return YES;
        [shown setBusy:YES];
        [shown retain];
        [[DLController sharedInstance] sendAPIRequestWithMethod:@"DELETE"
            path:[NSString stringWithFormat:@"/users/@me/guilds/%@", serverID]
            body:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:NO] forKey:@"lurking"]
            completion:^(id json, NSInteger status) {
                if (DLStatusIsSuccess(status)) {
                    [shown close];
                    [[DLController sharedInstance] removeServer:[[DLController sharedInstance] loadedServerWithID:serverID]];
                } else {
                    [shown setBusy:NO];
                    [shown setErrorMessage:DLErrorMessageFromResponse(json, status)];
                }
                [shown release];
            }];
        return NO;
    }];
    [dialog showInWindow:[self dialogWindow]];
}

@end
