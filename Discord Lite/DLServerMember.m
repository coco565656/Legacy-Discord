//
//  DLServerMember.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/22/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLServerMember.h"

@implementation DLServerMember

-(id)init {
    self = [super init];
    return self;
}

-(id)initWithDict:(NSDictionary *)d {
    self = [self init];
    user = [[DLUser alloc] initWithDict:[d objectForKey:@"user"]];
    roles = [[d objectForKey:@"roles"] retain];
    if ([[d objectForKey:@"presence"] isKindOfClass:[NSDictionary class]]) {
        presence = [[d objectForKey:@"presence"] copy];
    }
    return self;
}

-(DLUser *)user {
    return user;
}
-(NSArray *)roles {
    return roles;
}
-(NSDictionary *)presence {
    return presence;
}

-(void)setUser:(DLUser *)u {
    [user release];
    [u retain];
    user = u;
}

-(NSComparisonResult)compareDisplayName:(DLServerMember *)other {
    NSString *mine = [[self user] globalName] ? [[self user] globalName] : [[self user] username];
    NSString *theirs = [[other user] globalName] ? [[other user] globalName] : [[other user] username];
    return [mine localizedCaseInsensitiveCompare:theirs];
}

-(NSString *)presenceStatus {
    NSString *status = [presence objectForKey:@"status"];
    if ([status isEqualToString:@"online"] || [status isEqualToString:@"idle"] || [status isEqualToString:@"dnd"]) return status;
    return @"offline";
}

-(NSString *)customStatusText {
    NSArray *activities = [presence objectForKey:@"activities"];
    if (![activities isKindOfClass:[NSArray class]]) return nil;
    NSEnumerator *enumerator = [activities objectEnumerator];
    NSDictionary *activity;
    while (activity = [enumerator nextObject]) {
        if (![activity isKindOfClass:[NSDictionary class]] || [[activity objectForKey:@"type"] intValue] != 4) continue;
        NSString *state = [activity objectForKey:@"state"];
        if ([state isKindOfClass:[NSString class]] && [state length]) return state;
    }
    return nil;
}

-(void)dealloc {
    [user release];
    [roles release];
    [presence release];
    [super dealloc];
}

@end
