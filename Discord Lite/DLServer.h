//
//  DLServer.h
//  Discord Lite
//
//  Created by Collin Mistr on 10/27/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AsyncHTTPGetRequest.h"
#import "DLServerMember.h"

#define IconCDNRoot "https://cdn.discordapp.com/icons"

// Discord permission bits used by the client.
#define DLPermissionCreateInvite (1ULL << 0)
#define DLPermissionManageChannels (1ULL << 4)
#define DLPermissionManageGuild (1ULL << 5)
#define DLPermissionChangeNickname (1ULL << 26)
#define DLPermissionAdministrator (1ULL << 3)
#define DLPermissionViewChannel (1ULL << 10)
#define DLPermissionManageMessages (1ULL << 13)
#define DLPermissionCreatePublicThreads (1ULL << 35)
#define DLPermissionPinMessages (1ULL << 51)

// Posted whenever a server's mention count changes (drives the Dock badge).
#define DLServerMentionCountDidChangeNotification @"DLServerMentionCountDidChangeNotification"

@protocol DLServerDelegate <NSObject>
@optional
-(void)iconDidUpdateWithData:(NSData *)data;
-(void)mentionCountDidUpdate;
-(void)unreadStatusDidUpdate;
@end

@interface DLServer : NSObject <AsyncHTTPRequestDelegate> {
    NSString *serverID;
    NSString *name;
    NSString *iconID;
    NSData *iconImageData;
    NSInteger mentionCount;
    NSMutableArray *members;
    NSArray *emojis;
    NSArray *stickers;
    NSArray *roles;
    NSString *ownerID;
    NSArray *myRoleIDs;
    NSString *myNickname;
    NSInteger defaultMessageNotifications;
    BOOL myRolesUnavailable;
    id<DLServerDelegate> delegate;
    BOOL hasUnreadMessages;
}

-(id)init;
-(id)initWithDict:(NSDictionary *)d;

-(NSString *)serverID;
-(NSString *)name;
-(NSString *)iconID;
-(NSData *)iconImageData;
-(NSInteger)mentionCount;
-(NSArray *)members;
-(NSArray *)emojis;
-(NSArray *)stickers;
-(NSArray *)roles;
-(NSDictionary *)roleWithID:(NSString *)roleID;
// Whether the signed-in user may view a channel, computed like the official
// client (base role permissions, then @everyone/role/member overwrites).
// Returns YES when the user's roles are unknown so nothing is hidden wrongly.
-(BOOL)canUserWithID:(NSString *)userID viewChannelWithOverwrites:(NSArray *)overwrites;
-(BOOL)hasKnownMemberRoles;
// Guild-level permission check for the current user (owner and administrator
// have every permission). Unknown roles answer NO.
-(BOOL)iHavePermission:(unsigned long long)permission;
// The same with a channel's permission overwrites applied.
-(BOOL)iHavePermission:(unsigned long long)permission withOverwrites:(NSArray *)overwrites;
-(unsigned long long)myPermissionsWithOverwrites:(NSArray *)overwrites;
-(NSArray *)myRoleIDs;
-(NSString *)ownerID;
-(void)setMyRoleIDs:(NSArray *)roleIDs;
// Own server nickname (nil when none).
-(NSString *)myNickname;
-(void)setMyNickname:(NSString *)nickname;
// The server's default for message_notifications (0 all, 1 mentions).
-(NSInteger)defaultMessageNotifications;
// Set when the own-member request failed; channels are then shown unfiltered.
-(BOOL)myRolesUnavailable;
-(void)setMyRolesUnavailable:(BOOL)unavailable;
-(BOOL)hasUnreadMessages;

-(void)setServerID:(NSString *)inId;
-(void)setName:(NSString *)inName;
-(void)setIconImageData:(NSData *)data;

-(void)addMember:(DLServerMember *)m;
-(void)replaceMember:(DLServerMember *)m;

-(DLServerMember *)memberWithUserID:(NSString *)userID;

-(void)setDelegate:(id <DLServerDelegate>)inDelegate;
-(BOOL)isEqual:(DLServer *)object;

-(void)notifyOfNewMention;
-(void)addMentionCount:(NSInteger)inMentions;
-(void)setMentionCount:(NSInteger)inMentions;

-(void)setHasUnreadMessages:(BOOL)unread;

@end
