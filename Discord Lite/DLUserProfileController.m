//
//  DLUserProfileController.m
//  Legacy Discord
//

#import "DLUserProfileController.h"
#import "DLLocalization.h"
#import "DLController.h"
#import "DLUtil.h"
#import "DLTwemojiRenderer.h"
#import "DLMainWindowChromeControls.h"
#import "DLServerMember.h"
#import "HTTPCache.h"
#import "AsyncHTTPGetRequest.h"
#import "NSScroller+BGColor.h"
#include <float.h>

@interface DLProfileStatusBubbleView : NSView
@end

@implementation DLProfileStatusBubbleView
-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = NSInsetRect([self bounds], 1.0, 1.0);
    NSBezierPath *bubble = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:13.0 yRadius:13.0];
    [[DLUtil nativeInputColor] set];
    [bubble fill];
    [[NSColor colorWithCalibratedWhite:0.55 alpha:0.28] set];
    [bubble setLineWidth:1.0];
    [bubble stroke];
}
@end

@interface DLProfileRoleChipView : NSView {
    NSAttributedString *roleName;
    NSColor *roleColor;
}
+(NSAttributedString *)displayStringForName:(NSString *)name;
-(id)initWithFrame:(NSRect)frame name:(NSString *)name color:(NSColor *)color;
@end

@implementation DLProfileRoleChipView
// Role names frequently contain emoji, which Snow Leopard cannot draw, so
// measuring and drawing both use the shared Twemoji replacement.
+(NSAttributedString *)displayStringForName:(NSString *)name {
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont systemFontOfSize:10.0], NSFontAttributeName,
                                [DLUtil nativePrimaryTextColor], NSForegroundColorAttributeName, nil];
    NSMutableAttributedString *display = [[[NSMutableAttributedString alloc]
        initWithString:(name ? name : @"") attributes:attributes] autorelease];
    [DLTwemojiRenderer replaceEmojiInAttributedString:display size:10.0
                                   excludingAttribute:nil recordingAttribute:nil cursorLocation:NULL];
    return display;
}
-(id)initWithFrame:(NSRect)frame name:(NSString *)name color:(NSColor *)color {
    self = [super initWithFrame:frame];
    if (self) {
        roleName = [[DLProfileRoleChipView displayStringForName:name] copy];
        roleColor = [color retain];
    }
    return self;
}
-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = NSInsetRect([self bounds], 0.5, 0.5);
    NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:8.0 yRadius:8.0];
    [[NSColor colorWithCalibratedWhite:0.5 alpha:0.10] set];
    [pill fill];
    [[NSColor colorWithCalibratedWhite:0.5 alpha:0.28] set];
    [pill setLineWidth:1.0];
    [pill stroke];
    [(roleColor ? roleColor : [NSColor grayColor]) set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(7.0, NSMidY(bounds) - 4.0, 8.0, 8.0)] fill];
    [roleName drawAtPoint:NSMakePoint(19.0, NSMidY(bounds) - 6.0)];
}
-(void)dealloc {
    [roleName release];
    [roleColor release];
    [super dealloc];
}
@end

@interface DLUserProfileController ()
-(void)updateVisibleProfileData;
-(BOOL)mayDiscardUnsavedProfileNote;
@end

@implementation DLUserProfileController

-(id)initWithHostWindow:(NSWindow *)window
           userInfoView:(NSView *)userInfoView
             avatarView:(NSImageView *)avatarView {
    self = [super init];
    if (self) {
        hostWindow = [window retain];
        accountAvatarView = [avatarView retain];
        profileAvatarCache = [[NSCache alloc] init];
        [profileAvatarCache setCountLimit:80];
        profileAvatarRequests = [[NSMutableSet alloc] init];
        profileBannerImageCache = [[NSCache alloc] init];
        [profileBannerImageCache setCountLimit:20];
        profileBannerImageRequests = [[NSMutableSet alloc] init];
        profileDataCache = [[NSMutableDictionary alloc] init];
        profileDataRequests = [[NSMutableSet alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(profileBannerCacheDidUpdate:)
                                                     name:HTTPCacheDataDidUpdateNotification object:nil];

        myProfileButton = [[NSButton alloc] initWithFrame:[avatarView frame]];
        [myProfileButton setBordered:NO];
        [myProfileButton setRefusesFirstResponder:YES];
        [myProfileButton setTitle:@""];
        [myProfileButton setToolTip:DLLocalizedString(@"View your profile")];
        [myProfileButton setTarget:self];
        [myProfileButton setAction:@selector(showMyProfile:)];
        [userInfoView addSubview:myProfileButton];
    }
    return self;
}

-(NSTextField *)profileLabelWithFrame:(NSRect)frame text:(NSString *)text font:(NSFont *)font color:(NSColor *)color {
    NSTextField *field = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [field setBezeled:NO];
    [field setDrawsBackground:NO];
    [field setEditable:NO];
    [field setSelectable:YES];
    [field setFont:font];
    [field setTextColor:color];
    [[field cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    [[field cell] setUsesSingleLineMode:YES];
    [field setStringValue:text ? text : @""];
    [field setToolTip:text];
    return field;
}

-(NSString *)profileAvatarCacheKeyForUser:(DLUser *)user size:(CGFloat)size {
    NSString *userID = [[user userID] description];
    NSString *avatarID = [user avatarID];
    if (!avatarID || [avatarID isKindOfClass:[NSNull class]]) {
        avatarID = @"default";
    }
    NSData *avatarData = [user avatarImageData];
    return [NSString stringWithFormat:@"%@-%@-%lu-%lu-%.0f",
            userID ? userID : @"unknown", avatarID,
            (unsigned long)[avatarData length], (unsigned long)[avatarData hash], size];
}

-(NSImage *)cachedProfileAvatarForUser:(DLUser *)user size:(CGFloat)size {
    return [profileAvatarCache objectForKey:[self profileAvatarCacheKeyForUser:user size:size]];
}

-(void)requestProfileAvatarForUser:(DLUser *)user size:(CGFloat)size radius:(CGFloat)radius {
    if (!user) return;
    NSString *cacheKey = [self profileAvatarCacheKeyForUser:user size:size];
    if ([profileAvatarCache objectForKey:cacheKey] || [profileAvatarRequests containsObject:cacheKey]) {
        return;
    }
    NSData *avatarData = [user avatarImageData];
    if (!avatarData) return;
    [profileAvatarRequests addObject:cacheKey];
    NSDictionary *context = [NSDictionary dictionaryWithObjectsAndKeys:
                             cacheKey, @"key",
                             avatarData, @"data",
                             [NSNumber numberWithDouble:size], @"size",
                             [NSNumber numberWithDouble:radius], @"radius", nil];
    [self performSelectorInBackground:@selector(loadProfileAvatarInBackground:) withObject:context];
}

-(void)loadProfileAvatarInBackground:(NSDictionary *)context {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *cacheKey = [context objectForKey:@"key"];
    CGFloat size = [[context objectForKey:@"size"] doubleValue];
    CGFloat radius = [[context objectForKey:@"radius"] doubleValue];
    NSImage *source = [[[NSImage alloc] initWithData:[context objectForKey:@"data"]] autorelease];
    NSImage *resized = source ? [DLUtil imageResize:source
                                           newSize:NSMakeSize(size, size)
                                      cornerRadius:radius] : nil;
    NSData *renderedData = resized ? [resized TIFFRepresentation] : nil;
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   cacheKey, @"key",
                                   [NSNumber numberWithDouble:size], @"size", nil];
    if (renderedData) {
        [result setObject:renderedData forKey:@"data"];
    }
    [self performSelectorOnMainThread:@selector(profileAvatarDidFinishLoading:)
                           withObject:result waitUntilDone:NO];
    [pool drain];
}

-(void)profileAvatarDidFinishLoading:(NSDictionary *)result {
    NSString *cacheKey = [result objectForKey:@"key"];
    [profileAvatarRequests removeObject:cacheKey];
    NSData *data = [result objectForKey:@"data"];
    if (!data) return;
    NSImage *image = [[[NSImage alloc] initWithData:data] autorelease];
    if (!image) return;
    [profileAvatarCache setObject:image forKey:cacheKey];
    if (!profileUser || ![cacheKey hasPrefix:[NSString stringWithFormat:@"%@-", [[profileUser userID] description]]]) {
        return;
    }
    CGFloat size = [[result objectForKey:@"size"] doubleValue];
    if (size == 80.0 && profileAvatarButton) {
        [profileAvatarButton setImage:image];
    } else if (size == 128.0 && profileDetailAvatarView) {
        [profileDetailAvatarView setImage:image];
    }
}

-(NSString *)profileDataCacheKeyForUser:(DLUser *)user server:(DLServer *)server {
    NSString *serverID = server && [server serverID] ? [server serverID] : @"@me";
    return [NSString stringWithFormat:@"%@-%@", [[user userID] description], serverID];
}

-(void)requestProfileDataForUser:(DLUser *)user server:(DLServer *)server {
    if (!user) return;
    NSString *key = [self profileDataCacheKeyForUser:user server:server];
    if ([profileDataCache objectForKey:key]) {
        [self updateVisibleProfileData];
        return;
    }
    if (![profileDataRequests containsObject:key]) {
        [profileDataRequests addObject:key];
        [[DLController sharedInstance] loadProfileForUser:user inServer:server];
    }
}

-(NSColor *)profileAccentColorFromData:(NSDictionary *)profile {
    NSDictionary *userProfile = [[profile objectForKey:@"user_profile"] isKindOfClass:[NSDictionary class]]
        ? [profile objectForKey:@"user_profile"] : nil;
    NSDictionary *userData = [[profile objectForKey:@"user"] isKindOfClass:[NSDictionary class]]
        ? [profile objectForKey:@"user"] : nil;
    NSNumber *accent = [userProfile objectForKey:@"accent_color"];
    if (![accent isKindOfClass:[NSNumber class]]) accent = [userData objectForKey:@"accent_color"];
    if (![accent isKindOfClass:[NSNumber class]]) {
        return [NSColor colorWithCalibratedRed:0.36 green:0.48 blue:0.72 alpha:1.0];
    }
    unsigned long value = [accent unsignedLongValue];
    return [NSColor colorWithCalibratedRed:((value >> 16) & 0xff) / 255.0
                                     green:((value >> 8) & 0xff) / 255.0
                                      blue:(value & 0xff) / 255.0 alpha:1.0];
}

-(NSString *)profileJoinedDateFromData:(NSDictionary *)profile {
    NSDictionary *member = [[profile objectForKey:@"guild_member"] isKindOfClass:[NSDictionary class]]
        ? [profile objectForKey:@"guild_member"] : nil;
    NSString *timestamp = [member objectForKey:@"joined_at"];
    if (![timestamp isKindOfClass:[NSString class]] || [timestamp length] < 10) return nil;
    return [[timestamp substringToIndex:10] stringByReplacingOccurrencesOfString:@"-" withString:@"/"];
}

-(NSString *)profileConnectionsTextFromData:(NSDictionary *)profile {
    NSArray *connections = [[profile objectForKey:@"connected_accounts"] isKindOfClass:[NSArray class]]
        ? [profile objectForKey:@"connected_accounts"] : nil;
    if ([connections count] == 0) return DLLocalizedString(@"No visible connections");
    NSMutableArray *lines = [NSMutableArray array];
    NSInteger limit = MIN((NSInteger)[connections count], 5);
    for (NSInteger i = 0; i < limit; i++) {
        NSDictionary *connection = [connections objectAtIndex:i];
        if (![connection isKindOfClass:[NSDictionary class]]) continue;
        NSString *type = [connection objectForKey:@"type"];
        NSString *name = [connection objectForKey:@"name"];
        if ([type isKindOfClass:[NSString class]] && [name isKindOfClass:[NSString class]]) {
            [lines addObject:[NSString stringWithFormat:@"%@: %@", [type capitalizedString], name]];
        }
    }
    return [lines count] ? [lines componentsJoinedByString:@"\n"] : DLLocalizedString(@"No visible connections");
}

-(NSString *)profileActivitiesTextFromData:(NSDictionary *)profile {
    NSArray *activities = [[profile objectForKey:@"activities"] isKindOfClass:[NSArray class]]
        ? [profile objectForKey:@"activities"] : nil;
    NSDictionary *member = [[profile objectForKey:@"guild_member"] isKindOfClass:[NSDictionary class]]
        ? [profile objectForKey:@"guild_member"] : nil;
    NSDictionary *presence = [[member objectForKey:@"presence"] isKindOfClass:[NSDictionary class]]
        ? [member objectForKey:@"presence"] : nil;
    if (!presence && [[profileMember presence] isKindOfClass:[NSDictionary class]]) {
        presence = [profileMember presence];
    }
    if (!activities) activities = [[presence objectForKey:@"activities"] isKindOfClass:[NSArray class]]
        ? [presence objectForKey:@"activities"] : nil;
    NSMutableArray *lines = [NSMutableArray array];
    NSEnumerator *enumerator = [activities objectEnumerator];
    NSDictionary *activity;
    while (activity = [enumerator nextObject]) {
        if (![activity isKindOfClass:[NSDictionary class]]) continue;
        if ([[activity objectForKey:@"type"] integerValue] == 4) continue;
        NSString *name = [activity objectForKey:@"name"];
        NSString *details = [activity objectForKey:@"details"];
        if (![details isKindOfClass:[NSString class]]) details = [activity objectForKey:@"state"];
        if ([name isKindOfClass:[NSString class]]) {
            [lines addObject:([details isKindOfClass:[NSString class]] && [details length] > 0)
             ? [NSString stringWithFormat:@"%@ — %@", name, details] : name];
        }
        if ([lines count] >= 3) break;
    }
    return [lines count] ? [lines componentsJoinedByString:@"\n"] : nil;
}

-(NSString *)profileCustomStatusFromData:(NSDictionary *)profile {
    NSArray *activities = [[profile objectForKey:@"activities"] isKindOfClass:[NSArray class]]
        ? [profile objectForKey:@"activities"] : nil;
    NSDictionary *member = [[profile objectForKey:@"guild_member"] isKindOfClass:[NSDictionary class]]
        ? [profile objectForKey:@"guild_member"] : nil;
    NSDictionary *presence = [[member objectForKey:@"presence"] isKindOfClass:[NSDictionary class]]
        ? [member objectForKey:@"presence"] : nil;
    if (!presence && [[profileMember presence] isKindOfClass:[NSDictionary class]]) presence = [profileMember presence];
    if (!activities && [[presence objectForKey:@"activities"] isKindOfClass:[NSArray class]]) {
        activities = [presence objectForKey:@"activities"];
    }
    NSEnumerator *enumerator = [activities objectEnumerator];
    NSDictionary *activity;
    while (activity = [enumerator nextObject]) {
        if (![activity isKindOfClass:[NSDictionary class]] || [[activity objectForKey:@"type"] integerValue] != 4) continue;
        NSString *status = [activity objectForKey:@"state"];
        if ([status isKindOfClass:[NSString class]] && [status length] > 0) return status;
    }
    return nil;
}

// Height the role chips need at maxWidth (same wrapping as below).
-(CGFloat)roleChipsHeightForRoleIDs:(NSArray *)roleIDs maxWidth:(CGFloat)maxWidth {
    CGFloat x = 0.0;
    NSInteger rows = 1;
    NSEnumerator *enumerator = [roleIDs objectEnumerator];
    NSString *roleID;
    while (roleID = [enumerator nextObject]) {
        if ([[roleID description] isEqualToString:[[profileServer serverID] description]]) continue;
        NSString *name = [[profileServer roleWithID:[roleID description]] objectForKey:@"name"];
        if (![name isKindOfClass:[NSString class]] || [name length] == 0) name = @"Role";
        CGFloat width = MIN(maxWidth, MAX(54.0, [[DLProfileRoleChipView displayStringForName:name] size].width + 29.0));
        if (x > 0.0 && x + width > maxWidth) {
            x = 0.0;
            rows++;
        }
        x += width + 5.0;
    }
    return rows * 27.0;
}

-(void)reloadRoleChipsInView:(NSView *)container roleIDs:(NSArray *)roleIDs maxWidth:(CGFloat)maxWidth {
    if (!container) return;
    NSArray *existing = [[container subviews] copy];
    NSEnumerator *oldEnumerator = [existing objectEnumerator];
    NSView *oldView;
    while (oldView = [oldEnumerator nextObject]) [oldView removeFromSuperview];
    [existing release];
    CGFloat x = 0.0;
    CGFloat y = NSHeight([container bounds]) - 23.0;
    NSInteger shown = 0;
    NSEnumerator *enumerator = [roleIDs objectEnumerator];
    NSString *roleID;
    while (roleID = [enumerator nextObject]) {
        if ([[roleID description] isEqualToString:[[profileServer serverID] description]]) continue;
        NSDictionary *role = [profileServer roleWithID:[roleID description]];
        NSString *name = [role objectForKey:@"name"];
        if (![name isKindOfClass:[NSString class]] || [name length] == 0) name = @"Role";
        CGFloat width = MIN(maxWidth, MAX(54.0, [[DLProfileRoleChipView displayStringForName:name] size].width + 29.0));
        if (x > 0.0 && x + width > maxWidth) {
            x = 0.0;
            y -= 27.0;
        }
        if (y < 0.0) break;
        NSNumber *colorValue = [role objectForKey:@"color"];
        unsigned long color = [colorValue isKindOfClass:[NSNumber class]] ? [colorValue unsignedLongValue] : 0;
        NSColor *dotColor = color == 0 ? [DLUtil nativeSecondaryTextColor]
            : [NSColor colorWithCalibratedRed:((color >> 16) & 0xff) / 255.0
                                        green:((color >> 8) & 0xff) / 255.0
                                         blue:(color & 0xff) / 255.0 alpha:1.0];
        DLProfileRoleChipView *chip = [[DLProfileRoleChipView alloc]
                                      initWithFrame:NSMakeRect(x, y, width, 22.0)
                                      name:name color:dotColor];
        [container addSubview:chip];
        [chip release];
        x += width + 5.0;
        shown++;
    }
    if (shown == 0) {
        NSTextField *empty = [self profileLabelWithFrame:NSMakeRect(0.0, MAX(0.0, y), maxWidth, 20.0)
                                                    text:DLLocalizedString(@"No visible roles")
                                                    font:[NSFont systemFontOfSize:10.0]
                                                   color:[DLUtil nativeSecondaryTextColor]];
        [container addSubview:empty];
    }
}

-(void)applyCachedProfileBanner {
    if (!profileBannerURL) return;
    NSImage *cachedImage = [profileBannerImageCache objectForKey:profileBannerURL];
    if (cachedImage) {
        [profileBannerImageView setImage:cachedImage];
        [profileDetailBannerImageView setImage:cachedImage];
        return;
    }
    NSData *data = [[HTTPCache sharedInstance] cachedDataForURL:profileBannerURL];
    if (!data || [profileBannerImageRequests containsObject:profileBannerURL]) return;
    [profileBannerImageRequests addObject:profileBannerURL];
    NSDictionary *context = [NSDictionary dictionaryWithObjectsAndKeys:
                             profileBannerURL, @"url", data, @"data", nil];
    [self performSelectorInBackground:@selector(loadProfileBannerInBackground:) withObject:context];
}

-(void)loadProfileBannerInBackground:(NSDictionary *)context {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSImage *source = [[[NSImage alloc] initWithData:[context objectForKey:@"data"]] autorelease];
    NSImage *rendered = source ? [DLUtil imageResize:source newSize:NSMakeSize(380.0, 160.0) cornerRadius:0.0] : nil;
    NSData *renderedData = rendered ? [rendered TIFFRepresentation] : nil;
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:[context objectForKey:@"url"] forKey:@"url"];
    if (renderedData) [result setObject:renderedData forKey:@"data"];
    [self performSelectorOnMainThread:@selector(profileBannerDidFinishLoading:)
                           withObject:result waitUntilDone:NO];
    [pool drain];
}

-(void)profileBannerDidFinishLoading:(NSDictionary *)result {
    NSString *url = [result objectForKey:@"url"];
    [profileBannerImageRequests removeObject:url];
    NSData *data = [result objectForKey:@"data"];
    if (!data) return;
    NSImage *image = [[[NSImage alloc] initWithData:data] autorelease];
    if (!image) return;
    [profileBannerImageCache setObject:image forKey:url];
    if ([url isEqualToString:profileBannerURL]) {
        [profileBannerImageView setImage:image];
        [profileDetailBannerImageView setImage:image];
    }
}

-(void)profileBannerCacheDidUpdate:(NSNotification *)notification {
    if (profileBannerURL && [[notification object] isEqualToString:profileBannerURL]) {
        [self applyCachedProfileBanner];
    }
}

-(void)updateVisibleProfileData {
    if (!profileUser) return;
    NSDictionary *profile = [profileDataCache objectForKey:
                             [self profileDataCacheKeyForUser:profileUser server:profileServer]];
    if (![profile isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *userProfile = [[profile objectForKey:@"user_profile"] isKindOfClass:[NSDictionary class]]
        ? [profile objectForKey:@"user_profile"] : nil;
    NSDictionary *userData = [[profile objectForKey:@"user"] isKindOfClass:[NSDictionary class]]
        ? [profile objectForKey:@"user"] : nil;
    NSDictionary *guildMember = [[profile objectForKey:@"guild_member"] isKindOfClass:[NSDictionary class]]
        ? [profile objectForKey:@"guild_member"] : nil;
    NSString *bio = [userProfile objectForKey:@"bio"];
    if (![bio isKindOfClass:[NSString class]] || [bio length] == 0) bio = @"";
    NSString *pronouns = [userProfile objectForKey:@"pronouns"];
    NSString *joined = [self profileJoinedDateFromData:profile];
    NSArray *roles = [[guildMember objectForKey:@"roles"] isKindOfClass:[NSArray class]]
        ? [guildMember objectForKey:@"roles"] : [profileMember roles];
    NSArray *mutualGuilds = [[profile objectForKey:@"mutual_guilds"] isKindOfClass:[NSArray class]]
        ? [profile objectForKey:@"mutual_guilds"] : nil;

    NSMutableArray *metadata = [NSMutableArray array];
    if (joined) [metadata addObject:[NSString stringWithFormat:DLLocalizedString(@"Joined %@"), joined]];
    if ([pronouns isKindOfClass:[NSString class]] && [pronouns length] > 0) {
        [metadata addObject:[NSString stringWithFormat:DLLocalizedString(@"Pronouns: %@"), pronouns]];
    }
    if ([mutualGuilds count] > 0) {
        [metadata addObject:[NSString stringWithFormat:DLLocalizedString(@"%ld mutual server%@"), (long)[mutualGuilds count], DLPluralSuffix([mutualGuilds count])]];
    }
    // Popout: "username • pronouns", ABOUT ME only with a bio, and MEMBER
    // SINCE with the account and server dates like the official card.
    NSString *usernameLine = [profileUser username] ? [profileUser username] : @"";
    if ([pronouns isKindOfClass:[NSString class]] && [pronouns length]) {
        usernameLine = [NSString stringWithFormat:@"%@  \u2022  %@", usernameLine, pronouns];
    }
    [DLTwemojiRenderer setText:usernameLine forLabel:profileUsernameField];
    [DLTwemojiRenderer setText:bio forLabel:profileBioField];
    [profileAboutHeader setHidden:([bio length] == 0)];
    if ([bio length] == 0) [profileBioField setStringValue:@""];
    NSMutableArray *since = [NSMutableArray array];
    NSDate *created = [DLUtil dateFromSnowflake:[[profileUser userID] description]];
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setFormatterBehavior:NSDateFormatterBehavior10_4];
    [formatter setDateStyle:NSDateFormatterMediumStyle];
    [formatter setTimeStyle:NSDateFormatterNoStyle];
    if (created) [since addObject:[NSString stringWithFormat:@"Discord %@", [formatter stringFromDate:created]]];
    NSString *joinedAt = [guildMember objectForKey:@"joined_at"];
    NSDate *joinedDate = [joinedAt isKindOfClass:[NSString class]] ? [DLUtil dateFromTimestampString:joinedAt] : nil;
    if (joinedDate && ![profileServer isEqual:[[DLController sharedInstance] myServerItem]]) {
        [since addObject:[NSString stringWithFormat:@"Server %@", [formatter stringFromDate:joinedDate]]];
    }
    [profileMetadataField setStringValue:[since componentsJoinedByString:@"   \u2022   "]];
    [profileDetailBioField setStringValue:bio];
    [profileDetailMetadataField setStringValue:[metadata count] ? [metadata componentsJoinedByString:@"  •  "] : @""];
    [profileMetadataField setToolTip:[profileMetadataField stringValue]];
    [profileDetailMetadataField setToolTip:[profileDetailMetadataField stringValue]];
    [self reloadRoleChipsInView:profileRoleContainer roleIDs:roles maxWidth:NSWidth([profileRoleContainer bounds])];
    [self reloadRoleChipsInView:profileDetailRoleContainer roleIDs:roles maxWidth:NSWidth([profileDetailRoleContainer bounds])];
    NSString *customStatus = [self profileCustomStatusFromData:profile];
    [DLTwemojiRenderer setText:(customStatus ? customStatus : @"") forLabel:profileStatusField];
    [profileStatusBubble setHidden:customStatus == nil];
    [profileDetailStatusField setStringValue:customStatus ? customStatus : @""];
    [profileDetailStatusBubble setHidden:customStatus == nil];
    NSString *activities = [self profileActivitiesTextFromData:profile];
    NSString *connections = [self profileConnectionsTextFromData:profile];
    [profileDetailConnectionsField setStringValue:activities
     ? [NSString stringWithFormat:DLLocalizedString(@"ACTIVE NOW\n%@\n\nCONNECTIONS\n%@"), activities, connections]
     : [NSString stringWithFormat:DLLocalizedString(@"CONNECTIONS\n%@"), connections]];

    NSColor *accent = [self profileAccentColorFromData:profile];
    [profileBannerView setBackgroundColor:accent];
    [profileDetailBannerView setBackgroundColor:accent];
    NSString *bannerHash = [userProfile objectForKey:@"banner"];
    if (![bannerHash isKindOfClass:[NSString class]]) bannerHash = [userData objectForKey:@"banner"];
    [profileBannerURL release];
    profileBannerURL = nil;
    [profileBannerImageView setImage:nil];
    [profileDetailBannerImageView setImage:nil];
    if ([bannerHash isKindOfClass:[NSString class]] && [bannerHash length] > 0) {
        profileBannerURL = [[NSString stringWithFormat:
                            @"https://cdn.discordapp.com/banners/%@/%@.png?size=600",
                            [profileUser userID], bannerHash] retain];
        if ([[HTTPCache sharedInstance] cachedDataForURL:profileBannerURL]) {
            [self applyCachedProfileBanner];
        } else if ([[HTTPCache sharedInstance] beginLoadingURL:profileBannerURL]) {
            AsyncHTTPGetRequest *request = [[AsyncHTTPGetRequest alloc] init];
            [request setDelegate:self];
            [request setUrl:profileBannerURL];
            [request setCached:YES];
            [request start];
        }
    }
}

-(IBAction)messageFromProfile:(id)sender {
    NSString *text = [[profileMessageField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    DLUser *user = [[profileUser retain] autorelease];
    [profilePopover close];
    [[DLController sharedInstance] openDirectMessageWithUser:user draft:text];
}

-(void)showProfileForUser:(DLUser *)user relativeToRect:(NSRect)rect ofView:(NSView *)view {
    if (!user || !view) return;
    if (profileDetailPanel) {
        if (![self mayDiscardUnsavedProfileNote]) return;
        [hostWindow removeChildWindow:profileDetailPanel];
        [profileDetailPanel setDelegate:nil];
        [profileDetailPanel close];
        [profileDetailPanel release];
        profileDetailPanel = nil;
    }
    [profilePopover close];
    [profilePopover release];
    profilePopover = [[DLCompatibilityPopover alloc] init];
    [profilePopover setBehavior:DLCompatibilityPopoverBehaviorTransient];
    [profilePopover setDelegate:self];
    [profilePopoverController release];
    profilePopoverController = [[NSViewController alloc] init];
    [profileUser release];
    profileUser = [user retain];
    [profileServer release];
    profileServer = [[[DLController sharedInstance] selectedServer] retain];
    [profileMember release];
    DLServer *server = profileServer;
    profileMember = [[server memberWithUserID:[user userID]] retain];

    [profileBannerView release]; profileBannerView = nil;
    [profileBannerImageView release]; profileBannerImageView = nil;
    [profileBioField release]; profileBioField = nil;
    [profileMetadataField release]; profileMetadataField = nil;
    [profileRoleContainer release]; profileRoleContainer = nil;
    [profileStatusBubble release]; profileStatusBubble = nil;
    [profileStatusField release]; profileStatusField = nil;

    // Official user popout: banner, avatar with a ring and presence dot,
    // names, then ABOUT ME / MEMBER SINCE / ROLES in an inner panel and a
    // "Message @name" field (not on one's own profile).
    BOOL isMe = [[[user userID] description] isEqualToString:[[[[DLController sharedInstance] myUser] userID] description]];
    CGFloat rolesHeight = MIN(6 * 27.0, [self roleChipsHeightForRoleIDs:[profileMember roles] maxWidth:292.0]);
    CGFloat cardHeight = (isMe ? 403.0 : 447.0) + rolesHeight;
    CGFloat base = isMe ? 0.0 : 44.0;
    NSView_BGColor *card = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0, 0.0, 340.0, cardHeight)] autorelease];
    [card setBackgroundColor:[DLUtil nativeContentColor]];
    NSView_BGColor *banner = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0, cardHeight - 105.0, 340.0, 105.0)] autorelease];
    [banner setBackgroundColor:[NSColor colorWithCalibratedRed:0.36 green:0.48 blue:0.72 alpha:1.0]];
    [card addSubview:banner];
    profileBannerView = [banner retain];
    NSImageView *bannerImage = [[[NSImageView alloc] initWithFrame:[banner bounds]] autorelease];
    [bannerImage setImageScaling:NSImageScaleAxesIndependently];
    [bannerImage setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [banner addSubview:bannerImage];
    profileBannerImageView = [bannerImage retain];

    CGFloat avatarY = cardHeight - 105.0 - 40.0;
    NSView_BGColor *ring = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(12.0, avatarY - 6.0, 92.0, 92.0)] autorelease];
    [ring setBackgroundColor:[DLUtil nativeContentColor]];
    [ring setCornerRadius:46.0];
    [card addSubview:ring];
    NSButton *avatarButton = [[[NSButton alloc] initWithFrame:NSMakeRect(18.0, avatarY, 80.0, 80.0)] autorelease];
    [avatarButton setBordered:NO];
    [avatarButton setRefusesFirstResponder:YES];
    [avatarButton setTitle:@""];
    NSImage *avatar = [self cachedProfileAvatarForUser:user size:80.0];
    if (!avatar) {
        avatar = [[[NSImage alloc] initWithContentsOfFile:
                   [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"discord_placeholder.png"]] autorelease];
        [avatar setSize:NSMakeSize(80.0, 80.0)];
    }
    [avatarButton setImage:avatar];
    [avatarButton setImagePosition:NSImageOnly];
    [avatarButton setToolTip:DLLocalizedString(@"Open full profile")];
    [avatarButton setTarget:self];
    [avatarButton setAction:@selector(showExpandedProfile:)];
    [card addSubview:avatarButton];
    [profileAvatarButton release];
    profileAvatarButton = [avatarButton retain];
    NSString *presence = isMe ? @"online" : [[DLController sharedInstance] presenceStatusForUserID:[user userID]];
    if (!isMe && [profileMember presenceStatus]) presence = [profileMember presenceStatus];
    DLStatusDotView *dot = [[[DLStatusDotView alloc] initWithFrame:NSMakeRect(74.0, avatarY - 2.0, 26.0, 26.0)] autorelease];
    [dot setDotColor:[DLUtil statusColorForPresenceStatus:presence] ringColor:[DLUtil nativeContentColor]];
    [card addSubview:dot];

    DLProfileStatusBubbleView *statusBubble = [[[DLProfileStatusBubbleView alloc]
                                               initWithFrame:NSMakeRect(112.0, avatarY + 12.0, 212.0, 60.0)] autorelease];
    [statusBubble setHidden:YES];
    NSTextField *statusField = [self profileLabelWithFrame:NSMakeRect(12.0, 5.0, 188.0, 50.0)
                                                       text:@"" font:[NSFont systemFontOfSize:11.0]
                                                      color:[DLUtil nativePrimaryTextColor]];
    [[statusField cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [[statusField cell] setUsesSingleLineMode:NO];
    [[statusField cell] setWraps:YES];
    [[statusField cell] setScrollable:NO];
    [statusBubble addSubview:statusField];
    [card addSubview:statusBubble];
    profileStatusBubble = [statusBubble retain];
    profileStatusField = [statusField retain];

    NSString *displayName = [user globalName] ? [user globalName] : [user username];
    NSTextField *nameField = [self profileLabelWithFrame:NSMakeRect(16.0, avatarY - 40.0, 308.0, 26.0)
                                                    text:@"" font:[NSFont boldSystemFontOfSize:20.0]
                                                   color:[DLUtil nativePrimaryTextColor]];
    [DLTwemojiRenderer setText:displayName forLabel:nameField];
    [card addSubview:nameField];
    NSTextField *usernameField = [self profileLabelWithFrame:NSMakeRect(16.0, avatarY - 60.0, 308.0, 18.0)
                                                        text:[user username]
                                                        font:[NSFont systemFontOfSize:13.0]
                                                       color:[DLUtil nativePrimaryTextColor]];
    [card addSubview:usernameField];
    [profileUsernameField release];
    profileUsernameField = [usernameField retain];

    // Inner panel with the sections.
    CGFloat panelTop = avatarY - 70.0;
    NSView_BGColor *panel = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(12.0, base + 12.0, 316.0, panelTop - base - 12.0)] autorelease];
    [panel setBackgroundColor:[DLUtil nativeSidebarColor]];
    [panel setCornerRadius:8.0];
    [card addSubview:panel];
    CGFloat panelHeight = NSHeight([panel bounds]);
    NSTextField *aboutHeader = [self profileLabelWithFrame:NSMakeRect(12.0, panelHeight - 26.0, 290.0, 16.0)
                                                      text:DLLocalizedString(@"ABOUT ME") font:[NSFont boldSystemFontOfSize:11.0]
                                                     color:[DLUtil nativePrimaryTextColor]];
    [panel addSubview:aboutHeader];
    [profileAboutHeader release];
    profileAboutHeader = [aboutHeader retain];
    NSTextField *bioField = [self profileLabelWithFrame:NSMakeRect(12.0, panelHeight - 78.0, 290.0, 50.0)
                                                   text:DLLocalizedString(@"Loading profile…")
                                                   font:[NSFont systemFontOfSize:12.0]
                                                  color:[DLUtil nativePrimaryTextColor]];
    [[bioField cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [[bioField cell] setWraps:YES];
    [[bioField cell] setScrollable:NO];
    [[bioField cell] setUsesSingleLineMode:NO];
    [panel addSubview:bioField];
    profileBioField = [bioField retain];
    [panel addSubview:[self profileLabelWithFrame:NSMakeRect(12.0, panelHeight - 102.0, 290.0, 16.0)
                                             text:DLLocalizedString(@"MEMBER SINCE") font:[NSFont boldSystemFontOfSize:11.0]
                                            color:[DLUtil nativePrimaryTextColor]]];
    NSTextField *metadataField = [self profileLabelWithFrame:NSMakeRect(12.0, panelHeight - 122.0, 290.0, 18.0)
                                                        text:@""
                                                        font:[NSFont systemFontOfSize:12.0]
                                                       color:[DLUtil nativeSecondaryTextColor]];
    [panel addSubview:metadataField];
    profileMetadataField = [metadataField retain];
    [panel addSubview:[self profileLabelWithFrame:NSMakeRect(12.0, panelHeight - 146.0, 290.0, 16.0)
                                             text:DLLocalizedString(@"ROLES") font:[NSFont boldSystemFontOfSize:11.0]
                                            color:[DLUtil nativePrimaryTextColor]]];
    NSView *roleContainer = [[[NSView alloc] initWithFrame:NSMakeRect(12.0, 6.0, 292.0, MAX(27.0, panelHeight - 156.0))] autorelease];
    [panel addSubview:roleContainer];
    profileRoleContainer = [roleContainer retain];
    [self reloadRoleChipsInView:roleContainer roleIDs:[profileMember roles] maxWidth:292.0];

    [profileMessageField release];
    profileMessageField = nil;
    if (!isMe) {
        NSTextField *messageField = [[[NSTextField alloc] initWithFrame:NSMakeRect(12.0, 12.0, 316.0, 32.0)] autorelease];
        [messageField setBezeled:NO];
        [messageField setBordered:NO];
        [messageField setDrawsBackground:YES];
        [messageField setBackgroundColor:[DLUtil nativeInputColor]];
        [messageField setTextColor:[DLUtil nativePrimaryTextColor]];
        [messageField setFont:[NSFont systemFontOfSize:13.0]];
        [messageField setFocusRingType:NSFocusRingTypeNone];
        [[messageField cell] setPlaceholderString:[NSString stringWithFormat:DLLocalizedString(@"Message @%@"), displayName]];
        [[messageField cell] setScrollable:YES];
        [messageField setTarget:self];
        [messageField setAction:@selector(messageFromProfile:)];
        [card addSubview:messageField];
        profileMessageField = [messageField retain];
    }
    [profilePopoverController setView:card];
    [profilePopover setContentViewController:profilePopoverController];
    [profilePopover setContentSize:NSMakeSize(340.0, NSHeight([card frame]))];
    NSRectEdge edge = [view isKindOfClass:[NSTableView class]] ? NSMinXEdge : NSMaxXEdge;
    [profilePopover showRelativeToRect:rect ofView:view preferredEdge:edge];
    // Leave the message field unfocused so its "Message @name" placeholder shows.
    [[card window] makeFirstResponder:nil];
    [self requestProfileAvatarForUser:user size:80.0 radius:40.0];
    [self requestProfileDataForUser:user server:server];
}

-(IBAction)showMyProfile:(id)sender {
    [self showProfileForUser:[[DLController sharedInstance] myUser]
              relativeToRect:[myProfileButton bounds]
                      ofView:myProfileButton];
}

-(void)showExpandedProfile:(id)sender {
    if (!profileUser) return;
    if (profileDetailPanel && ![self mayDiscardUnsavedProfileNote]) return;
    [profilePopover close];
    if (profileDetailPanel) {
        [hostWindow removeChildWindow:profileDetailPanel];
        [profileDetailPanel setDelegate:nil];
        [profileDetailPanel close];
        [profileDetailPanel release];
    }
    [profileNoteView setDelegate:nil];
    [profileNoteView release]; profileNoteView = nil;
    [profileNoteSaveButton release]; profileNoteSaveButton = nil;
    [profileNoteStatusField release]; profileNoteStatusField = nil;
    [profileNoteUserID release]; profileNoteUserID = [[profileUser userID] copy];
    [profileNoteUser release]; profileNoteUser = [profileUser retain];
    [profileSavedNote release]; profileSavedNote = nil;
    profileNoteSaving = NO;
    profileDetailPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 760.0, 520.0)
                                                    styleMask:NSTitledWindowMask | NSClosableWindowMask
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    [profileDetailPanel setTitle:DLLocalizedString(@"User Profile")];
    [profileDetailPanel setReleasedWhenClosed:NO];
    [profileDetailPanel setDelegate:self];
    NSView_BGColor *content = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0, 0.0, 760.0, 520.0)] autorelease];
    [content setBackgroundColor:[DLUtil nativeContentColor]];
    NSView_BGColor *summary = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0, 0.0, 380.0, 520.0)] autorelease];
    [summary setBackgroundColor:[DLUtil nativeSidebarColor]];
    [summary setLeftBorderColor:[DLUtil nativeBorderColor]];
    [content addSubview:summary];
    [profileDetailBannerView release]; profileDetailBannerView = nil;
    [profileDetailBannerImageView release]; profileDetailBannerImageView = nil;
    [profileDetailBioField release]; profileDetailBioField = nil;
    [profileDetailMetadataField release]; profileDetailMetadataField = nil;
    [profileDetailConnectionsField release]; profileDetailConnectionsField = nil;
    [profileDetailRoleContainer release]; profileDetailRoleContainer = nil;
    [profileDetailStatusBubble release]; profileDetailStatusBubble = nil;
    [profileDetailStatusField release]; profileDetailStatusField = nil;
    NSView_BGColor *detailBanner = [[[NSView_BGColor alloc] initWithFrame:NSMakeRect(0.0, 360.0, 380.0, 160.0)] autorelease];
    [detailBanner setBackgroundColor:[NSColor colorWithCalibratedRed:0.36 green:0.48 blue:0.72 alpha:1.0]];
    [summary addSubview:detailBanner];
    profileDetailBannerView = [detailBanner retain];
    NSImageView *detailBannerImage = [[[NSImageView alloc] initWithFrame:[detailBanner bounds]] autorelease];
    [detailBannerImage setImageScaling:NSImageScaleAxesIndependently];
    [detailBannerImage setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [detailBanner addSubview:detailBannerImage];
    profileDetailBannerImageView = [detailBannerImage retain];
    NSImageView *avatarView = [[[NSImageView alloc] initWithFrame:NSMakeRect(32.0, 315.0, 128.0, 128.0)] autorelease];
    NSImage *avatar = [self cachedProfileAvatarForUser:profileUser size:128.0];
    if (!avatar) {
        avatar = [[[NSImage alloc] initWithContentsOfFile:
                   [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"discord_placeholder.png"]] autorelease];
        [avatar setSize:NSMakeSize(128.0, 128.0)];
    }
    [avatarView setImage:avatar];
    [summary addSubview:avatarView];
    [profileDetailAvatarView release];
    profileDetailAvatarView = [avatarView retain];
    DLProfileStatusBubbleView *detailStatusBubble = [[[DLProfileStatusBubbleView alloc]
                                                     initWithFrame:NSMakeRect(172.0, 332.0, 184.0, 58.0)] autorelease];
    [detailStatusBubble setHidden:YES];
    NSTextField *detailStatusField = [self profileLabelWithFrame:NSMakeRect(14.0, 8.0, 156.0, 42.0)
                                                             text:@"" font:[NSFont systemFontOfSize:11.0]
                                                            color:[DLUtil nativePrimaryTextColor]];
    [[detailStatusField cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [[detailStatusField cell] setUsesSingleLineMode:NO];
    [[detailStatusField cell] setWraps:YES];
    [[detailStatusField cell] setScrollable:NO];
    [detailStatusBubble addSubview:detailStatusField];
    [summary addSubview:detailStatusBubble];
    profileDetailStatusBubble = [detailStatusBubble retain];
    profileDetailStatusField = [detailStatusField retain];
    NSString *displayName = [profileUser globalName] ? [profileUser globalName] : [profileUser username];
    [summary addSubview:[self profileLabelWithFrame:NSMakeRect(32.0, 282.0, 316.0, 28.0)
                                                  text:displayName font:[NSFont boldSystemFontOfSize:20.0]
                                                 color:[DLUtil nativePrimaryTextColor]]];
    [summary addSubview:[self profileLabelWithFrame:NSMakeRect(32.0, 257.0, 316.0, 20.0)
                                                  text:[profileUser username] font:[NSFont systemFontOfSize:12.0]
                                                 color:[DLUtil nativeSecondaryTextColor]]];
    NSTextField *detailBio = [self profileLabelWithFrame:NSMakeRect(32.0, 204.0, 316.0, 45.0)
                                                     text:DLLocalizedString(@"Loading profile details…")
                                                     font:[NSFont systemFontOfSize:12.0]
                                                    color:[DLUtil nativePrimaryTextColor]];
    [[detailBio cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [[detailBio cell] setWraps:YES];
    [[detailBio cell] setScrollable:NO];
    [[detailBio cell] setUsesSingleLineMode:NO];
    [summary addSubview:detailBio];
    profileDetailBioField = [detailBio retain];
    NSTextField *detailMetadata = [self profileLabelWithFrame:NSMakeRect(32.0, 175.0, 316.0, 22.0)
                                                          text:DLLocalizedString(@"Loading membership details…")
                                                          font:[NSFont systemFontOfSize:10.0]
                                                         color:[DLUtil nativeSecondaryTextColor]];
    [summary addSubview:detailMetadata];
    profileDetailMetadataField = [detailMetadata retain];
    [summary addSubview:[self profileLabelWithFrame:NSMakeRect(32.0, 140.0, 316.0, 20.0)
                                                  text:DLLocalizedString(@"ROLES") font:[NSFont boldSystemFontOfSize:10.0]
                                                 color:[DLUtil nativeSecondaryTextColor]]];
    NSView *detailRoleContainer = [[[NSView alloc] initWithFrame:NSMakeRect(32.0, 24.0, 316.0, 110.0)] autorelease];
    [summary addSubview:detailRoleContainer];
    profileDetailRoleContainer = [detailRoleContainer retain];
    [self reloadRoleChipsInView:detailRoleContainer roleIDs:[profileMember roles] maxWidth:316.0];

    [content addSubview:[self profileLabelWithFrame:NSMakeRect(410.0, 460.0, 320.0, 30.0)
                                                 text:DLLocalizedString(@"PROFILE DETAILS") font:[NSFont boldSystemFontOfSize:14.0]
                                                color:[DLUtil nativePrimaryTextColor]]];
    NSTextField *detailConnections = [self profileLabelWithFrame:NSMakeRect(410.0, 252.0, 320.0, 198.0)
                                                             text:DLLocalizedString(@"Loading activity and connections…")
                                                             font:[NSFont systemFontOfSize:11.0]
                                                            color:[DLUtil nativePrimaryTextColor]];
    [[detailConnections cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [[detailConnections cell] setUsesSingleLineMode:NO];
    [[detailConnections cell] setWraps:YES];
    [[detailConnections cell] setScrollable:NO];
    [content addSubview:detailConnections];
    profileDetailConnectionsField = [detailConnections retain];
    [content addSubview:[self profileLabelWithFrame:NSMakeRect(410.0, 218.0, 320.0, 22.0)
                                                 text:DLLocalizedString(@"PRIVATE NOTE") font:[NSFont boldSystemFontOfSize:11.0]
                                                color:[DLUtil nativeSecondaryTextColor]]];
    NSScrollView *noteScroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(410.0, 96.0, 320.0, 116.0)] autorelease];
    [noteScroll setBorderType:NSBezelBorder];
    [noteScroll setHasVerticalScroller:YES];
    [noteScroll setDrawsBackground:YES];
    [noteScroll setBackgroundColor:[DLUtil nativeInputColor]];
    [[noteScroll contentView] setBackgroundColor:[DLUtil nativeInputColor]];
    NSScroller_BGColor *noteScroller = [[NSScroller_BGColor alloc] initWithFrame:NSZeroRect];
    [noteScroller setBackgroundColor:[DLUtil nativeInputColor]];
    [noteScroll setVerticalScroller:noteScroller];
    [noteScroller release];
    NSTextView *noteView = [[[NSTextView alloc] initWithFrame:[[noteScroll contentView] bounds]] autorelease];
    [noteView setMinSize:NSMakeSize(0.0, 116.0)];
    [noteView setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    [noteView setVerticallyResizable:YES];
    [noteView setHorizontallyResizable:NO];
    [[noteView textContainer] setWidthTracksTextView:YES];
    [noteView setFont:[NSFont systemFontOfSize:12.0]];
    [noteView setBackgroundColor:[DLUtil nativeInputColor]];
    [noteView setTextColor:[DLUtil nativePrimaryTextColor]];
    [noteView setInsertionPointColor:[DLUtil nativePrimaryTextColor]];
    [noteView setString:DLLocalizedString(@"Loading note…")];
    [noteView setEditable:NO];
    [noteView setDelegate:self];
    [noteScroll setDocumentView:noteView];
    [content addSubview:noteScroll];
    profileNoteView = [noteView retain];
    NSTextField *noteStatus = [self profileLabelWithFrame:NSMakeRect(410.0, 65.0, 235.0, 22.0)
                                                      text:DLLocalizedString(@"Only you can see this note.")
                                                      font:[NSFont systemFontOfSize:10.0]
                                                     color:[DLUtil nativeSecondaryTextColor]];
    [content addSubview:noteStatus];
    profileNoteStatusField = [noteStatus retain];
    NSButton *saveNoteButton = [[[NSButton alloc] initWithFrame:NSMakeRect(650.0, 60.0, 80.0, 30.0)] autorelease];
    [saveNoteButton setTitle:DLLocalizedString(@"Save Note")];
    [saveNoteButton setBezelStyle:NSRoundedBezelStyle];
    [saveNoteButton setTarget:self];
    [saveNoteButton setAction:@selector(saveProfileNote:)];
    [saveNoteButton setEnabled:NO];
    [content addSubview:saveNoteButton];
    profileNoteSaveButton = [saveNoteButton retain];
    [profileDetailPanel setContentView:content];
    NSRect parentFrame = [hostWindow frame];
    NSRect panelFrame = [profileDetailPanel frame];
    panelFrame.origin.x = NSMidX(parentFrame) - NSWidth(panelFrame) / 2.0;
    panelFrame.origin.y = NSMidY(parentFrame) - NSHeight(panelFrame) / 2.0;
    [profileDetailPanel setFrame:panelFrame display:NO];
    [hostWindow addChildWindow:profileDetailPanel ordered:NSWindowAbove];
    [profileDetailPanel makeKeyAndOrderFront:self];
#if LEGACY_DISCORD_LOCAL_DEV
    if (offlineNotePreview) return;
#endif
    [self requestProfileAvatarForUser:profileUser size:128.0 radius:64.0];
    [self requestProfileDataForUser:profileUser server:profileServer];
    [[DLController sharedInstance] loadNoteForUser:profileUser];
}

#if LEGACY_DISCORD_LOCAL_DEV
-(void)showOfflineProfileNoteForUser:(DLUser *)user note:(NSString *)note {
    [profileUser release];
    profileUser = [user retain];
    [profileServer release]; profileServer = nil;
    [profileMember release]; profileMember = nil;
    offlineNotePreview = YES;
    [self showExpandedProfile:nil];
    [profileDetailBioField setStringValue:@"Synthetic offline profile for visual regression."];
    [profileDetailMetadataField setStringValue:@"Fixture account"];
    [profileDetailConnectionsField setStringValue:@"ACTIVE NOW\nOffline preview\n\nCONNECTIONS\nNone"];
    [self userNote:note didLoadForUser:user error:NO];
}

-(NSView *)offlineProfileDetailView {
    return [profileDetailPanel contentView];
}
#endif

-(void)textDidChange:(NSNotification *)notification {
    if ([notification object] != profileNoteView || !profileSavedNote) return;
    [profileNoteSaveButton setEnabled:!profileNoteSaving &&
     ![[profileNoteView string] isEqualToString:profileSavedNote]];
    [profileNoteStatusField setStringValue:DLLocalizedString(@"Only you can see this note.")];
}

-(void)saveProfileNote:(id)sender {
    if (!profileNoteUser || !profileSavedNote || profileNoteSaving) return;
    NSString *note = [profileNoteView string];
    if ([note isEqualToString:profileSavedNote]) return;
    profileNoteSaving = YES;
    [profileNoteSaveButton setEnabled:NO];
    [profileNoteStatusField setStringValue:DLLocalizedString(@"Saving…")];
    [[DLController sharedInstance] saveNote:note forUser:profileNoteUser];
}

-(BOOL)mayDiscardUnsavedProfileNote {
    if (!profileNoteView || !profileSavedNote || profileNoteSaving ||
        [[profileNoteView string] isEqualToString:profileSavedNote]) return YES;
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:DLLocalizedString(@"Discard unsaved note?")];
    [alert setInformativeText:DLLocalizedString(@"Your changes to this private note have not been saved.")];
    [alert addButtonWithTitle:DLLocalizedString(@"Keep Editing")];
    [alert addButtonWithTitle:DLLocalizedString(@"Discard Changes")];
    return [alert runModal] == NSAlertSecondButtonReturn;
}

-(BOOL)windowShouldClose:(id)sender {
    if (sender == profileDetailPanel) return [self mayDiscardUnsavedProfileNote];
    return YES;
}

-(void)windowWillClose:(NSNotification *)notification {
    if ([notification object] != profileDetailPanel) return;
    // On 10.6 a closed child panel remains attached to its parent and can
    // remain on screen even though isVisible is already NO.
    NSWindow *parent = [profileDetailPanel parentWindow];
    [parent removeChildWindow:profileDetailPanel];
}

-(void)userNote:(NSString *)note didLoadForUser:(DLUser *)user error:(BOOL)error {
    if (!profileDetailPanel || ![[user userID] isEqualToString:profileNoteUserID]) return;
    if (error) {
        [profileNoteView setString:DLLocalizedString(@"Could not load note.")];
        [profileNoteStatusField setStringValue:DLLocalizedString(@"Note unavailable. Reopen the profile to retry.")];
        return;
    }
    [profileSavedNote release];
    profileSavedNote = [note copy];
    [profileNoteView setString:note];
    [profileNoteView setEditable:YES];
    [profileNoteSaveButton setEnabled:NO];
    [profileNoteStatusField setStringValue:DLLocalizedString(@"Only you can see this note.")];
}

-(void)userNote:(NSString *)note didSaveForUser:(DLUser *)user error:(BOOL)error {
    if (!profileDetailPanel || ![[user userID] isEqualToString:profileNoteUserID]) return;
    profileNoteSaving = NO;
    if (error) {
        [profileNoteStatusField setStringValue:DLLocalizedString(@"Save failed. Please try again.")];
    } else {
        [profileSavedNote release];
        profileSavedNote = [note copy];
        [profileNoteStatusField setStringValue:DLLocalizedString(@"Note saved.")];
    }
    [profileNoteSaveButton setEnabled:![[profileNoteView string] isEqualToString:profileSavedNote]];
}

-(void)userProfile:(NSDictionary *)profile didLoadForUser:(DLUser *)user inServer:(DLServer *)server {
    NSString *key = [self profileDataCacheKeyForUser:user server:server];
    [profileDataRequests removeObject:key];
    if (profile) {
        [profileDataCache setObject:profile forKey:key];
    }
    if (profileUser && [[profileUser userID] isEqualToString:[user userID]] &&
        [[self profileDataCacheKeyForUser:profileUser server:profileServer] isEqualToString:key]) {
        if (profile) {
            [self updateVisibleProfileData];
        } else {
            [profileBioField setStringValue:@""];
            [profileMetadataField setStringValue:@""];
            [profileDetailBioField setStringValue:@""];
            [profileDetailMetadataField setStringValue:@""];
            NSString *status = [self profileCustomStatusFromData:[NSDictionary dictionary]];
            [profileStatusField setStringValue:status ? status : @""];
            [profileStatusBubble setHidden:status == nil];
            [profileDetailStatusField setStringValue:status ? status : @""];
            [profileDetailStatusBubble setHidden:status == nil];
        }
    }
}

-(void)requestDidFinishLoading:(AsyncHTTPRequest *)request {
    if ([request result] != HTTPResultOK) {
        [[HTTPCache sharedInstance] endLoadingURL:[request url]];
    }
    [request release];
}



-(void)members:(NSArray *)members didUpdateForServer:(DLServer *)server {
    NSEnumerator *enumerator = [members objectEnumerator];
    DLServerMember *member;
    while (member = [enumerator nextObject]) {
        NSString *userID = [[[member user] userID] description];
        if (profileUser && profileServer && [profileServer isEqual:server] &&
            [userID isEqualToString:[[profileUser userID] description]]) {
            [profileMember release];
            profileMember = [member retain];
            [self updateVisibleProfileData];
            break;
        }
    }
}

-(void)avatarDidUpdateForUser:(DLUser *)user data:(NSData *)data {
    if ([user isEqual:[[DLController sharedInstance] myUser]] && data) {
        CGFloat size = NSWidth([accountAvatarView frame]);
        [accountAvatarView setImage:[DLUtil imageResize:[[[NSImage alloc] initWithData:data] autorelease]
                                               newSize:[accountAvatarView frame].size
                                          cornerRadius:size / 2.0]];
    }
    if (profileUser && [user isEqual:profileUser]) {
        [self requestProfileAvatarForUser:user size:80.0 radius:40.0];
        if (profileDetailPanel) [self requestProfileAvatarForUser:user size:128.0 radius:64.0];
    }
}

-(void)applyCurrentTheme {
    NSScrollView *noteScroll = [profileNoteView enclosingScrollView];
    [noteScroll setBackgroundColor:[DLUtil nativeInputColor]];
    [[noteScroll contentView] setBackgroundColor:[DLUtil nativeInputColor]];
    [(NSScroller_BGColor *)[noteScroll verticalScroller] setBackgroundColor:[DLUtil nativeInputColor]];
    [profileNoteView setBackgroundColor:[DLUtil nativeInputColor]];
    [profileNoteView setTextColor:[DLUtil nativePrimaryTextColor]];
    [profileNoteView setInsertionPointColor:[DLUtil nativePrimaryTextColor]];
    [profileBannerView setNeedsDisplay:YES];
    [profileDetailBannerView setNeedsDisplay:YES];
    [[profilePopoverController view] setNeedsDisplay:YES];
    [[profileDetailPanel contentView] setNeedsDisplay:YES];
}

-(void)close {
    [profilePopover close];
    if (profileDetailPanel) {
        [hostWindow removeChildWindow:profileDetailPanel];
        [profileDetailPanel close];
    }
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self close];
    [myProfileButton setTarget:nil];
    [myProfileButton removeFromSuperview];
    [myProfileButton release];
    [profilePopover release];
    [profilePopoverController release];
    [profileUser release];
    [profileServer release];
    [profileMember release];
    [profileAvatarButton release];
    [profileDetailAvatarView release];
    [profileAvatarRequests release];
    [profileAvatarCache release];
    [profileBannerImageRequests release];
    [profileBannerImageCache release];
    [profileDataRequests release];
    [profileDataCache release];
    [profileBannerView release];
    [profileBannerImageView release];
    [profileBioField release];
    [profileMetadataField release];
    [profileRoleContainer release];
    [profileStatusBubble release];
    [profileStatusField release];
    [profileDetailBannerView release];
    [profileDetailBannerImageView release];
    [profileDetailBioField release];
    [profileDetailMetadataField release];
    [profileDetailConnectionsField release];
    [profileDetailRoleContainer release];
    [profileDetailStatusBubble release];
    [profileDetailStatusField release];
    [profileNoteView setDelegate:nil];
    [profileNoteView release];
    [profileNoteSaveButton release];
    [profileNoteStatusField release];
    [profileNoteUserID release];
    [profileNoteUser release];
    [profileSavedNote release];
    [profileBannerURL release];
    [profileDetailPanel release];
    [accountAvatarView release];
    [hostWindow release];
    [super dealloc];
}

@end
