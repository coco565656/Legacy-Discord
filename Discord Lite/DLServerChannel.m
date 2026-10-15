//
//  DLServerChannel.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/1/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLServerChannel.h"

@implementation DLServerChannel

-(id)initWithDict:(NSDictionary *)d {
    self = [super initWithDict:d];
    [self updateWithDict:d];
    return self;
}

-(void)updateWithDict:(NSDictionary *)d {
    [super updateWithDict:d];
    // Partial updates must not drop fields they do not carry (a missing
    // guild_id used to clear the server set by setServerID:).
    id value = [d objectForKey:@"parent_id"];
    if (value) { [parentID release]; parentID = [value retain]; }
    value = [d objectForKey:@"guild_id"];
    if ([value isKindOfClass:[NSString class]]) { [serverID release]; serverID = [value retain]; }
    value = [d objectForKey:@"topic"];
    if (value) { [topic release]; topic = [value retain]; }
    value = [d objectForKey:@"message_count"];
    if ([value respondsToSelector:@selector(integerValue)]) messageCount = [value integerValue];
    value = [d objectForKey:@"owner_id"];
    if ([value isKindOfClass:[NSString class]]) { [ownerID release]; ownerID = [value copy]; }
    value = [d objectForKey:@"applied_tags"];
    if ([value isKindOfClass:[NSArray class]]) { [appliedTagIDs release]; appliedTagIDs = [value copy]; }
    value = [d objectForKey:@"flags"];
    if ([value respondsToSelector:@selector(integerValue)]) channelFlags = [value integerValue];
    value = [d objectForKey:@"available_tags"];
    if ([value isKindOfClass:[NSArray class]]) { [availableTags release]; availableTags = [value copy]; }
    id overwrites = [d objectForKey:@"permission_overwrites"];
    if ([overwrites isKindOfClass:[NSArray class]]) {
        [permissionOverwrites release];
        permissionOverwrites = [overwrites copy];
    }
    position = [[d objectForKey:@"position"] intValue];
    if ([d objectForKey:@"member"] && ![[d objectForKey:@"member"] isKindOfClass:[NSNull class]]) {
        joinedThread = YES;
    }
    NSDictionary *threadMetadata = [d objectForKey:@"thread_metadata"];
    if ([threadMetadata isKindOfClass:[NSDictionary class]]) {
        archivedThread = [[threadMetadata objectForKey:@"archived"] boolValue];
    }
}

-(NSString *)name {
    return name;
}
-(NSString *)parentID {
    return parentID;
}
-(NSString *)serverID {
    return serverID;
}
-(NSString *)topic {
    return topic;
}
-(NSInteger) position {
    return position;
}

- (NSComparisonResult)compare:(DLServerChannel *)o {
    if (position > o.position) {
        return NSOrderedDescending;
    } else if (position < o.position) {
        return NSOrderedAscending;
    } else {
        return NSOrderedSame;
    }
}

-(NSArray *)children {
    return children;
}
-(BOOL)joinedThread {
    return joinedThread;
}
-(BOOL)archivedThread {
    return archivedThread;
}

-(void)setChildren:(NSArray *)inChildren {
    [children release];
    [inChildren retain];
    children = inChildren;
}
-(void)setServerID:(NSString *)inServerID {
    [serverID release];
    [inServerID retain];
    serverID = inServerID;
}
-(void)setJoinedThread:(BOOL)joined {
    joinedThread = joined;
}
-(void)setArchivedThread:(BOOL)archived {
    archivedThread = archived;
}

-(NSComparisonResult)compareThreadRecency:(DLServerChannel *)other {
    if (archivedThread != [other archivedThread]) {
        return archivedThread ? NSOrderedDescending : NSOrderedAscending;
    }
    NSString *myLastID = [[[self lastMessage] messageID] description];
    NSString *otherLastID = [[[other lastMessage] messageID] description];
    unsigned long long mine = myLastID ? [myLastID longLongValue] : [[self channelID] longLongValue];
    unsigned long long theirs = otherLastID ? [otherLastID longLongValue] : [[other channelID] longLongValue];
    if (mine > theirs) {
        return NSOrderedAscending;
    }
    if (mine < theirs) {
        return NSOrderedDescending;
    }
    return NSOrderedSame;
}

-(NSArray *)permissionOverwrites {
    return permissionOverwrites;
}

-(NSInteger)messageCount {
    return messageCount;
}
-(NSString *)ownerID {
    return ownerID;
}
-(NSArray *)appliedTagIDs {
    return appliedTagIDs;
}
-(NSArray *)availableTags {
    return availableTags;
}
-(BOOL)requiresTag {
    return (channelFlags & (1 << 4)) != 0;
}
-(NSDictionary *)starterSummary {
    return starterSummary;
}
-(void)setStarterSummary:(NSDictionary *)summary {
    [starterSummary release];
    starterSummary = [summary copy];
}

-(NSDate *)lastActivityDate {
    NSString *snowflake = [[[self lastMessage] messageID] description];
    if (![snowflake length]) snowflake = [[self channelID] description];
    unsigned long long value = strtoull([snowflake UTF8String], NULL, 10);
    if (value == 0) return nil;
    // Discord snowflakes carry milliseconds since 2015-01-01 in bits 22+.
    NSTimeInterval milliseconds = (NSTimeInterval)((value >> 22) + 1420070400000ULL);
    return [NSDate dateWithTimeIntervalSince1970:milliseconds / 1000.0];
}

-(void)dealloc {
    [permissionOverwrites release];
    [children release];
    [serverID release];
    [parentID release];
    [topic release];
    [ownerID release];
    [appliedTagIDs release];
    [availableTags release];
    [starterSummary release];
    [super dealloc];
}

@end
