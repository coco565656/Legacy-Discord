//
//  DLServerChannel.h
//  Discord Lite
//
//  Created by Collin Mistr on 11/1/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLChannel.h"

@interface DLServerChannel : DLChannel {
    NSString *parentID;
    NSString *serverID;
    NSString *topic;
    NSArray *permissionOverwrites;
    NSInteger position;
    NSArray *children;
    BOOL joinedThread;
    BOOL archivedThread;
    NSInteger messageCount;
    NSString *ownerID;
    NSArray *appliedTagIDs;
    NSArray *availableTags;
    NSDictionary *starterSummary;
}

-(id)initWithDict:(NSDictionary *)d;
-(void)updateWithDict:(NSDictionary *)d;

-(NSString *)name;
// Raw permission_overwrites from the API (array of {id, type, allow, deny}).
-(NSArray *)permissionOverwrites;
-(NSString *)parentID;
-(NSString *)serverID;
-(NSString *)topic;
-(NSInteger) position;
-(NSArray *)children;
-(BOOL)joinedThread;
-(BOOL)archivedThread;
// Thread/forum post details (message_count, owner_id, applied_tags).
-(NSInteger)messageCount;
-(NSString *)ownerID;
-(NSArray *)appliedTagIDs;
// A forum's tags: [{id, name, emoji_name, emoji_id}].
-(NSArray *)availableTags;
// A forum post's opening message: {author, text, imageURL}, once loaded.
-(NSDictionary *)starterSummary;
-(void)setStarterSummary:(NSDictionary *)summary;
// When the last message was sent (from its snowflake), else creation time.
-(NSDate *)lastActivityDate;

- (NSComparisonResult)compare:(DLServerChannel *)o;

-(void)setChildren:(NSArray *)inChildren;
-(void)setServerID:(NSString *)inServerID;
-(void)setJoinedThread:(BOOL)joined;
-(void)setArchivedThread:(BOOL)archived;

-(NSComparisonResult)compareThreadRecency:(DLServerChannel *)other;


@end
