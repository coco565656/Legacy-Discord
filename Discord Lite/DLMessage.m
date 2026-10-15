//
//  DLMessage.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/2/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLMessage.h"

@implementation DLMessage

-(id)init {
    self = [super init];
    mentionedEveryone = NO;
    return self;
}
-(id)initWithDict:(NSDictionary *)d {
    self = [self init];
    [self updateWithDict:d];
    return self;
}
-(void)updateWithDict:(NSDictionary *)d {
    id value = [d objectForKey:@"id"];
    if (value && ![value isKindOfClass:[NSNull class]]) {
        [messageID release];
        messageID = [value retain];
    }
    value = [d objectForKey:@"content"];
    if (value && ![value isKindOfClass:[NSNull class]]) {
        [content release];
        content = [value retain];
    }
    value = [d objectForKey:@"channel_id"];
    if (value && ![value isKindOfClass:[NSNull class]]) {
        [channelID release];
        channelID = [value retain];
    }
    value = [d objectForKey:@"author"];
    if ([value isKindOfClass:[NSDictionary class]]) {
        [author release];
        author = [[DLUser alloc] initWithDict:value];
    }
    value = [d objectForKey:@"member"];
    if ([value isKindOfClass:[NSDictionary class]] && [[value objectForKey:@"roles"] isKindOfClass:[NSArray class]]) {
        [memberRoles release];
        memberRoles = [[value objectForKey:@"roles"] copy];
    }
    value = [d objectForKey:@"attachments"];
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *attachmentData = [[NSMutableArray alloc] init];
        NSEnumerator *e = [value objectEnumerator];
        NSDictionary *attachmentDict;
        while (attachmentDict = [e nextObject]) {
            DLAttachment *a = [[DLAttachment alloc] initWithDict:attachmentDict];
            [attachmentData addObject:a];
            [a release];
        }
        [attachments release];
        attachments = attachmentData;
    }
    NSString *timestampString = [d objectForKey:@"timestamp"];
    if (timestampString && ![timestampString isKindOfClass:[NSNull class]]) {
        [timestamp release];
        timestamp = [[DLUtil dateFromTimestampString:timestampString] retain];
    }
    NSString *editedTimestampString = [d objectForKey:@"edited_timestamp"];
    if (editedTimestampString && ![editedTimestampString isKindOfClass:[NSNull class]]) {
        [editedTimestamp release];
        editedTimestamp = [[DLUtil dateFromTimestampString:editedTimestampString] retain];
    }
    value = [d objectForKey:@"mentions"];
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *mentionedUsersTemp = [[NSMutableArray alloc] init];
        NSEnumerator *e = [value objectEnumerator];
        NSDictionary *mentionedUserData;
        while (mentionedUserData = [e nextObject]) {
            DLUser *u = [[DLUser alloc] initWithDict:mentionedUserData];
            [mentionedUsersTemp addObject:u];
            [u release];
        }
        [mentionedUsers release];
        mentionedUsers = mentionedUsersTemp;
    }
    value = [d objectForKey:@"reactions"];
    if ([value isKindOfClass:[NSArray class]]) {
        [reactions release];
        reactions = [value copy];
    }
    value = [d objectForKey:@"embeds"];
    if ([value isKindOfClass:[NSArray class]]) {
        [embeds release];
        embeds = [value copy];
    }
    value = [d objectForKey:@"sticker_items"];
    if (![value isKindOfClass:[NSArray class]]) {
        value = [d objectForKey:@"stickers"];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        [stickerItems release];
        stickerItems = [value copy];
    }
    if ([d objectForKey:@"mention_everyone"]) {
        mentionedEveryone = [[d objectForKey:@"mention_everyone"] boolValue];
    }
    if ([[d objectForKey:@"mention_roles"] isKindOfClass:[NSArray class]]) {
        [mentionedRoleIDs release];
        mentionedRoleIDs = [[d objectForKey:@"mention_roles"] copy];
    }
    if ([d objectForKey:@"referenced_message"] && ![[d objectForKey:@"referenced_message"] isKindOfClass:[NSNull class]]) {
        [referencedMessage release];
        referencedMessage = [[DLMessage alloc] initWithDict:[d objectForKey:@"referenced_message"]];
    }
    if ([delegate respondsToSelector:@selector(messageContentWasUpdated)]) {
        [delegate messageContentWasUpdated];
    }
}

-(NSDictionary *)dictRepresentation {
    NSMutableDictionary *dict = [[[NSMutableDictionary alloc] initWithObjects:[NSArray arrayWithObjects:(content ? content : @""), [DLUtil generateSnowflake],[NSNumber numberWithBool:NO], [NSNumber numberWithInt:0], nil] forKeys:[NSArray arrayWithObjects:@"content", @"nonce", @"tts", @"flags", nil]] autorelease];
    if ([outgoingStickerIDs count] > 0) {
        [dict setObject:outgoingStickerIDs forKey:@"sticker_ids"];
    }
    if (referencedMessage) {
        NSMutableDictionary *refMsg = [[[NSMutableDictionary alloc] initWithObjects:[NSArray arrayWithObjects:[referencedMessage channelID], [referencedMessage messageID], nil] forKeys:[NSArray arrayWithObjects:@"channel_id", @"message_id", nil]] autorelease];
        if ([referencedMessage serverID]) {
            [refMsg setObject:[referencedMessage serverID] forKey:@"guild_id"];
        }
        [dict setObject:refMsg forKey:@"message_reference"];
    }
    return dict;
}

-(NSString *)messageID {
    return messageID;
}
-(NSString *)content {
    return content;
}
-(NSString *)channelID {
    return channelID;
}
-(NSString *)serverID {
    return serverID;
}
-(DLUser *)author {
    return author;
}
-(NSArray *)memberRoles {
    return memberRoles;
}
-(NSArray *)attachments {
    return attachments;
}
-(NSDate *)timestamp {
    return timestamp;
}
-(NSDate *)editedTimestamp {
    return editedTimestamp;
}
-(NSArray *)mentionedUsers {
    return mentionedUsers;
}
-(NSArray *)reactions {
    return reactions;
}
-(NSArray *)embeds {
    return embeds;
}
-(NSArray *)stickerItems {
    return stickerItems;
}
-(NSString *)reactionSummary {
    NSMutableArray *parts = [NSMutableArray array];
    NSEnumerator *enumerator = [reactions objectEnumerator];
    NSDictionary *reaction;
    while (reaction = [enumerator nextObject]) {
        NSDictionary *emoji = [reaction objectForKey:@"emoji"];
        NSString *name = [emoji objectForKey:@"name"];
        if (!name || [name isKindOfClass:[NSNull class]]) {
            continue;
        }
        NSString *label = [emoji objectForKey:@"id"] && ![[emoji objectForKey:@"id"] isKindOfClass:[NSNull class]]
            ? [NSString stringWithFormat:@":%@:", name]
            : name;
        [parts addObject:[NSString stringWithFormat:@"%@ %@", label, [reaction objectForKey:@"count"]]];
    }
    return [parts componentsJoinedByString:@"   "];
}
-(void)applyReactionEmoji:(NSDictionary *)emoji added:(BOOL)added byCurrentUser:(BOOL)currentUser {
    NSMutableArray *updatedReactions = reactions ? [[reactions mutableCopy] autorelease] : [NSMutableArray array];
    NSDictionary *matchingReaction = nil;
    NSEnumerator *enumerator = [updatedReactions objectEnumerator];
    NSDictionary *candidate;
    while (candidate = [enumerator nextObject]) {
        NSDictionary *candidateEmoji = [candidate objectForKey:@"emoji"];
        id candidateID = [candidateEmoji objectForKey:@"id"];
        id incomingID = [emoji objectForKey:@"id"];
        BOOL idsMatch = candidateID && incomingID &&
            ![candidateID isKindOfClass:[NSNull class]] &&
            ![incomingID isKindOfClass:[NSNull class]] &&
            [candidateID isEqual:incomingID];
        BOOL namesMatchWithoutIDs = (!candidateID || [candidateID isKindOfClass:[NSNull class]]) &&
            (!incomingID || [incomingID isKindOfClass:[NSNull class]]) &&
            [[candidateEmoji objectForKey:@"name"] isEqual:[emoji objectForKey:@"name"]];
        if (idsMatch || namesMatchWithoutIDs) {
            matchingReaction = candidate;
            break;
        }
    }

    if (matchingReaction) {
        BOOL alreadyHasCurrentUserReaction = [[matchingReaction objectForKey:@"me"] boolValue];
        if (currentUser && alreadyHasCurrentUserReaction == added) {
            return;
        }
        NSMutableDictionary *replacement = [NSMutableDictionary dictionaryWithDictionary:matchingReaction];
        NSInteger count = [[matchingReaction objectForKey:@"count"] integerValue] + (added ? 1 : -1);
        if (count <= 0) {
            [updatedReactions removeObject:matchingReaction];
        } else {
            [replacement setObject:[NSNumber numberWithInteger:count] forKey:@"count"];
            if (currentUser) {
                [replacement setObject:[NSNumber numberWithBool:added] forKey:@"me"];
            }
            [updatedReactions replaceObjectAtIndex:[updatedReactions indexOfObject:matchingReaction] withObject:replacement];
        }
    } else if (added) {
        NSDictionary *newReaction = [NSDictionary dictionaryWithObjectsAndKeys:
                                     [NSNumber numberWithInteger:1], @"count",
                                     [NSNumber numberWithBool:currentUser], @"me",
                                     emoji, @"emoji", nil];
        [updatedReactions addObject:newReaction];
    }

    [reactions release];
    reactions = [updatedReactions copy];
    if ([delegate respondsToSelector:@selector(messageContentWasUpdated)]) {
        [delegate messageContentWasUpdated];
    }
}
-(DLMessage *)referencedMessage {
    return referencedMessage;
}
-(BOOL)mentionedEveryone {
    return mentionedEveryone;
}
-(NSArray *)mentionedRoleIDs {
    return mentionedRoleIDs;
}

-(void)setDelegate:(id<DLMessageDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)setMessageID:(NSString *)msgID {
    [messageID release];
    [msgID retain];
    messageID = msgID;
}

-(void)setContent:(NSString *)inContent {
    [content release];
    [inContent retain];
    content = inContent;
}

-(void)setAttachments:(NSArray *)inAttachments {
    [attachments release];
    [inAttachments retain];
    attachments = inAttachments;
}

-(void)setOutgoingStickerIDs:(NSArray *)stickerIDs {
    [outgoingStickerIDs release];
    outgoingStickerIDs = [stickerIDs copy];
}

-(void)setReferencedMessage:(DLMessage *)m {
    [referencedMessage release];
    [m retain];
    referencedMessage = m;
}
-(void)setServerID:(NSString *)inServerID {
    [serverID release];
    [inServerID retain];
    serverID = inServerID;
}
-(void)setChannelID:(NSString *)inChannelID {
    [channelID release];
    [inChannelID retain];
    channelID = inChannelID;
}

-(void)remove {
    if ([delegate respondsToSelector:@selector(messageWasDeleted)]) {
        [delegate messageWasDeleted];
    }
}

-(BOOL)isEqual:(DLMessage *)m {
    return [messageID isEqualToString:[m messageID]];
}

-(void)dealloc {
    [author release];
    [mentionedUsers release];
    [mentionedRoleIDs release];
    [reactions release];
    [embeds release];
    [stickerItems release];
    [outgoingStickerIDs release];
    [content release];
    [attachments release];
    [referencedMessage release];
    [messageID release];
    [channelID release];
    [serverID release];
    [memberRoles release];
    [timestamp release];
    [editedTimestamp release];
    [super dealloc];
}

@end
