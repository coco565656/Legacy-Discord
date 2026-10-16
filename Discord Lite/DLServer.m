//
//  DLServer.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/27/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLServer.h"
#import "DLController.h"

@implementation DLServer


-(id)init {
    self = [super init];
    mentionCount = 0;
    serverID = @"";
    hasUnreadMessages = NO;
    return self;
}

-(id)initWithDict:(NSDictionary *)d {
    self = [self init];
    serverID = [[d objectForKey:@"id"] retain];
    name = [[d objectForKey:@"name"] retain];
    iconID = [[d objectForKey:@"icon"] retain];
    id owner = [d objectForKey:@"owner_id"];
    if ([owner isKindOfClass:[NSString class]]) ownerID = [owner copy];
    // Own member entry injected from READY merged_members by DLWSController.
    NSDictionary *myMember = [d objectForKey:@"legacy_my_member"];
    if ([myMember isKindOfClass:[NSDictionary class]] && [[myMember objectForKey:@"roles"] isKindOfClass:[NSArray class]]) {
        myRoleIDs = [[myMember objectForKey:@"roles"] copy];
    }
    if ([myMember isKindOfClass:[NSDictionary class]] && [[myMember objectForKey:@"nick"] isKindOfClass:[NSString class]]) {
        myNickname = [[myMember objectForKey:@"nick"] copy];
    }
    id notifications = [d objectForKey:@"default_message_notifications"];
    if (![notifications respondsToSelector:@selector(integerValue)]) {
        notifications = [[d objectForKey:@"properties"] isKindOfClass:[NSDictionary class]]
            ? [[d objectForKey:@"properties"] objectForKey:@"default_message_notifications"] : nil;
    }
    defaultMessageNotifications = [notifications respondsToSelector:@selector(integerValue)] ? [notifications integerValue] : 0;
    NSMutableArray *membersList = [[NSMutableArray alloc] init];
    NSEnumerator *e = [[d objectForKey:@"members"] objectEnumerator];
    NSDictionary *memberData;
    while (memberData = [e nextObject]) {
        DLServerMember *m = [[DLServerMember alloc] initWithDict:memberData];
        [membersList addObject:m];
        [m release];
    }
    members = membersList;
    id emojiData = [d objectForKey:@"emojis"];
    if ([emojiData isKindOfClass:[NSArray class]]) {
        emojis = [emojiData copy];
    }
    id stickerData = [d objectForKey:@"stickers"];
    if ([stickerData isKindOfClass:[NSArray class]]) {
        stickers = [stickerData copy];
    }
    id roleData = [d objectForKey:@"roles"];
    if ([roleData isKindOfClass:[NSArray class]]) {
        roles = [roleData copy];
    }
    [self loadIconData];
    return self;
}


-(void)loadIconData {
    if (iconID && ![iconID isKindOfClass:[NSNull class]]) {
        AsyncHTTPGetRequest *req = [[AsyncHTTPGetRequest alloc] init];
        [req setDelegate:self];
        [req setUrl:[@IconCDNRoot stringByAppendingString:[NSString stringWithFormat:@"/%@/%@.png", serverID, iconID]]];
        [req setCached:YES];
        [req start];
    }
}
-(NSString *)serverID {
    return serverID;
}
-(NSString *)name {
    return name;
}
-(NSString *)iconID {
    return iconID;
}
-(NSData *)iconImageData {
    if (!iconImageData) {
        iconImageData = [[NSData alloc] initWithContentsOfFile:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"discord_placeholder.png"]];
    }
    return iconImageData;
}
-(NSInteger)mentionCount {
    return mentionCount;
}
-(NSArray *)members {
    return members;
}
-(NSArray *)emojis {
    return emojis;
}
-(NSArray *)stickers {
    return stickers;
}
-(NSArray *)roles {
    return roles;
}
-(NSDictionary *)roleWithID:(NSString *)roleID {
    NSEnumerator *enumerator = [roles objectEnumerator];
    NSDictionary *role;
    while (role = [enumerator nextObject]) {
        if ([[[role objectForKey:@"id"] description] isEqualToString:[roleID description]]) return role;
    }
    return nil;
}
-(BOOL)hasUnreadMessages {
    return hasUnreadMessages;
}
-(void)setDelegate:(id <DLServerDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)setServerID:(NSString *)inId {
    [serverID release];
    [inId retain];
    serverID = inId;
}
-(void)setName:(NSString *)inName {
    [name release];
    [inName retain];
    name = inName;
}
-(void)setIconImageData:(NSData *)data {
    [iconImageData release];
    [data retain];
    iconImageData = data;
}

-(void)addMember:(DLServerMember *)m {
    [members addObject:m];
}

-(void)replaceMember:(DLServerMember *)m {
    DLServerMember *existing = [self memberWithUserID:[[m user] userID]];
    if (existing) [members removeObjectIdenticalTo:existing];
    [members addObject:m];
}

-(DLServerMember *)memberWithUserID:(NSString *)userID {
    NSEnumerator *e = [members objectEnumerator];
    DLServerMember *m;
    while (m = [e nextObject]) {
        if ([[[m user] userID] isEqualToString:userID]) {
            return m;
        }
    }
    return nil;
}

-(void)notifyOfNewMention {
    mentionCount++;
    [delegate mentionCountDidUpdate];
    [[NSNotificationCenter defaultCenter] postNotificationName:DLServerMentionCountDidChangeNotification object:self];
}
-(void)addMentionCount:(NSInteger)inMentions; {
    mentionCount += inMentions;
    [delegate mentionCountDidUpdate];
    [[NSNotificationCenter defaultCenter] postNotificationName:DLServerMentionCountDidChangeNotification object:self];
}

-(void)setMentionCount:(NSInteger)inMentions {
    mentionCount = inMentions;
    [delegate mentionCountDidUpdate];
    [[NSNotificationCenter defaultCenter] postNotificationName:DLServerMentionCountDidChangeNotification object:self];
}

-(void)setHasUnreadMessages:(BOOL)unread {
    hasUnreadMessages = unread;
    [delegate unreadStatusDidUpdate];
}

-(BOOL)isEqual:(DLServer *)object {
    return [serverID isEqualToString:[object serverID]];
}

#pragma mark Delegated Functions

-(void)requestDidFinishLoading:(AsyncHTTPRequest *)request {
    
    if ([request result] == HTTPResultOK) {
        [iconImageData release];
        iconImageData = [[request responseData] retain];
        [delegate iconDidUpdateWithData:[request responseData]];
    }
    [request release];
}

-(BOOL)hasKnownMemberRoles {
    return myRoleIDs != nil;
}
-(NSArray *)myRoleIDs {
    return myRoleIDs;
}
-(NSString *)myNickname {
    return myNickname;
}

-(void)setMyNickname:(NSString *)nickname {
    [myNickname release];
    myNickname = ([nickname isKindOfClass:[NSString class]] && [nickname length]) ? [nickname copy] : nil;
}

-(NSInteger)defaultMessageNotifications {
    return defaultMessageNotifications;
}

-(NSString *)ownerID {
    return ownerID;
}
-(void)setMyRoleIDs:(NSArray *)roleIDs {
    [myRoleIDs release];
    myRoleIDs = [roleIDs copy];
}
-(BOOL)myRolesUnavailable {
    return myRolesUnavailable;
}
-(void)setMyRolesUnavailable:(BOOL)unavailable {
    myRolesUnavailable = unavailable;
}

static unsigned long long DLPermissionValue(id value) {
    if ([value isKindOfClass:[NSString class]]) return strtoull([value UTF8String], NULL, 10);
    if ([value isKindOfClass:[NSNumber class]]) return [value unsignedLongLongValue];
    return 0;
}

// Own permission bits in a channel with these overwrites (nil: the server
// level). Owner and administrator have every bit.
-(unsigned long long)myPermissionsWithOverwrites:(NSArray *)overwrites {
    static const unsigned long long DLPermissionAll = ~0ULL;
    NSString *me = [[[[DLController existingInstance] myUser] userID] description];
    if (ownerID && me && [[ownerID description] isEqualToString:me]) return DLPermissionAll;
    if (!myRoleIDs) return 0;
    NSString *guildID = [serverID description];
    unsigned long long permissions = DLPermissionValue([[self roleWithID:guildID] objectForKey:@"permissions"]);
    NSEnumerator *roleEnumerator = [myRoleIDs objectEnumerator];
    id roleID;
    while (roleID = [roleEnumerator nextObject]) {
        permissions |= DLPermissionValue([[self roleWithID:[roleID description]] objectForKey:@"permissions"]);
    }
    if (permissions & DLPermissionAdministrator) return DLPermissionAll;
    unsigned long long roleAllow = 0, roleDeny = 0;
    NSDictionary *everyoneOverwrite = nil, *memberOverwrite = nil;
    NSEnumerator *overwriteEnumerator = [overwrites objectEnumerator];
    NSDictionary *overwrite;
    while (overwrite = [overwriteEnumerator nextObject]) {
        if (![overwrite isKindOfClass:[NSDictionary class]]) continue;
        NSString *targetID = [[overwrite objectForKey:@"id"] description];
        int type = [[overwrite objectForKey:@"type"] intValue];
        if (type == 0 && [targetID isEqualToString:guildID]) { everyoneOverwrite = overwrite; continue; }
        if (type == 1) { if (me && [targetID isEqualToString:me]) memberOverwrite = overwrite; continue; }
        NSEnumerator *mine = [myRoleIDs objectEnumerator];
        id myRole;
        while (myRole = [mine nextObject]) {
            if ([[myRole description] isEqualToString:targetID]) {
                roleAllow |= DLPermissionValue([overwrite objectForKey:@"allow"]);
                roleDeny |= DLPermissionValue([overwrite objectForKey:@"deny"]);
                break;
            }
        }
    }
    if (everyoneOverwrite) {
        permissions &= ~DLPermissionValue([everyoneOverwrite objectForKey:@"deny"]);
        permissions |= DLPermissionValue([everyoneOverwrite objectForKey:@"allow"]);
    }
    permissions &= ~roleDeny;
    permissions |= roleAllow;
    if (memberOverwrite) {
        permissions &= ~DLPermissionValue([memberOverwrite objectForKey:@"deny"]);
        permissions |= DLPermissionValue([memberOverwrite objectForKey:@"allow"]);
    }
    return permissions;
}

-(BOOL)iHavePermission:(unsigned long long)permission {
    return ([self myPermissionsWithOverwrites:nil] & permission) == permission;
}

-(BOOL)iHavePermission:(unsigned long long)permission withOverwrites:(NSArray *)overwrites {
    return ([self myPermissionsWithOverwrites:overwrites] & permission) == permission;
}

-(BOOL)canUserWithID:(NSString *)userID viewChannelWithOverwrites:(NSArray *)overwrites {
    // Channel visibility is only decided for the signed-in user; unknown
    // roles show everything rather than hide channels by mistake.
    if (!myRoleIDs || !userID) return YES;
    return ([self myPermissionsWithOverwrites:overwrites] & DLPermissionViewChannel) != 0;
}

-(void)dealloc {
    [ownerID release];
    [myNickname release];
    [myRoleIDs release];
    [serverID release];
    [name release];
    [iconID release];
    [iconImageData release];
    [members release];
    [emojis release];
    [stickers release];
    [roles release];
    [super dealloc];
}

@end
