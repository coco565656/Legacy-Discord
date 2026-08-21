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

-(void)dealloc {
    [user release];
    [roles release];
    [presence release];
    [super dealloc];
}

@end
