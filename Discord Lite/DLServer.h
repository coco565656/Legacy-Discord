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
-(NSArray *)myRoleIDs;
-(void)setMyRoleIDs:(NSArray *)roleIDs;
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
