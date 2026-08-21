//
//  DLServer.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/27/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLServer.h"

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
}
-(void)addMentionCount:(NSInteger)inMentions; {
    mentionCount += inMentions;
    [delegate mentionCountDidUpdate];
}

-(void)setMentionCount:(NSInteger)inMentions {
    mentionCount = inMentions;
    [delegate mentionCountDidUpdate];
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

-(void)dealloc {
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
