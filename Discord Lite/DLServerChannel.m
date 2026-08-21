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
    parentID = [[d objectForKey:@"parent_id"] retain];
    serverID = [[d objectForKey:@"guild_id"] retain];
    topic = [[d objectForKey:@"topic"] retain];
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

-(void)dealloc {
    [children release];
    [serverID release];
    [super dealloc];
}

@end
