//
//  DLServerMember.h
//  Discord Lite
//
//  Created by Collin Mistr on 11/22/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DLUser.h"

@interface DLServerMember : NSObject {
    DLUser *user;
    NSArray *roles;
    NSDictionary *presence;
}

-(id)initWithDict:(NSDictionary *)d;

-(DLUser *)user;
-(NSArray *)roles;
-(NSDictionary *)presence;

-(void)setUser:(DLUser *)u;
-(NSComparisonResult)compareDisplayName:(DLServerMember *)other;
// "online", "idle", "dnd" or "offline" (also when no presence is known).
-(NSString *)presenceStatus;
// Text of the member's custom status activity, if any.
-(NSString *)customStatusText;

@end
