//
//  DLWSController.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/4/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLWSController.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <libkern/OSAtomic.h>
#include <sys/select.h>

@implementation DLWSController


static DLWSController* sharedObject = nil;

-(void)deliverConnectionState:(NSNumber *)stateNumber {
    [delegate wsConnectionStateDidChange:(DLWSConnectionState)[stateNumber intValue]];
}

-(void)notifyConnectionState:(DLWSConnectionState)state {
    if (connectionState == state) {
        return;
    }
    connectionState = state;
    [self performSelectorOnMainThread:@selector(deliverConnectionState:)
                           withObject:[NSNumber numberWithInt:state]
                        waitUntilDone:NO];
}

-(BOOL)isDiscordNetworkReachable {
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, "discord.com");
    if (!reachability) {
        return YES;
    }
    SCNetworkReachabilityFlags flags = 0;
    BOOL obtainedFlags = SCNetworkReachabilityGetFlags(reachability, &flags);
    CFRelease(reachability);
    if (!obtainedFlags) {
        return YES;
    }
    BOOL reachable = (flags & kSCNetworkReachabilityFlagsReachable) != 0;
    BOOL connectionRequired = (flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0;
    return reachable && !connectionRequired;
}

-(void)checkNetworkReachability:(NSTimer *)timer {
    if (connectionState != DLWSConnectionStateDisconnected && ![self isDiscordNetworkReachable]) {
        [self notifyConnectionState:DLWSConnectionStateReconnecting];
    }
}

-(void)startReachabilityMonitoring {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(startReachabilityMonitoring) withObject:nil waitUntilDone:NO];
        return;
    }
    if (!reachabilityTimer) {
        reachabilityTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                            target:self
                                                          selector:@selector(checkNetworkReachability:)
                                                          userInfo:nil
                                                           repeats:YES];
    }
    [self checkNetworkReachability:reachabilityTimer];
}

-(id)init {
    self = [super init];
    heartbeatResponseReceived = NO;
    shouldResume = NO;
    didReconnect = NO;
    didResume = NO;
    reconnectScheduled = NO;
    sequenceNumber = 0;
    connectionState = DLWSConnectionStateDisconnected;
    outgoingFrames = [[NSMutableArray alloc] init];
    connectionLock = [[NSLock alloc] init];
    connectionGeneration = 0;
    return self;
}

+(DLWSController *)sharedInstance
{
    if (!sharedObject) {
        sharedObject = [[[super allocWithZone: NULL] init] retain];
    }
    return sharedObject;
}

-(void)setDelegate:(id<DLWSControllerDelegate>)inDelegate {
    delegate = inDelegate;
}

// Ends the current connection. Its thread notices within one poll interval;
// no libcurl call is made from this (main) thread.
-(void)abortCurrentConnection {
    OSAtomicIncrement32Barrier(&connectionGeneration);
}

-(void)sendQueuedFramesOnHandle:(CURL *)handle {
    NSArray *frames = nil;
    @synchronized(outgoingFrames) {
        if ([outgoingFrames count] == 0) return;
        frames = [[outgoingFrames copy] autorelease];
        [outgoingFrames removeAllObjects];
    }
    NSEnumerator *enumerator = [frames objectEnumerator];
    NSData *frame;
    while (frame = [enumerator nextObject]) {
        // Gateway frames are small; libcurl either accepts the whole frame or
        // asks to retry it unchanged (CURLE_AGAIN).
        for (int attempt = 0; attempt < 200; attempt++) {
            size_t sent = 0;
            CURLcode result = curl_ws_send(handle, [frame bytes], [frame length], &sent, 0, CURLWS_TEXT);
            if (result == CURLE_AGAIN) { usleep(10000); continue; }
            if (result != CURLE_OK) return;
            if (sent < [frame length]) NSLog(@"Gateway frame partially sent (%lu of %lu bytes).", (unsigned long)sent, (unsigned long)[frame length]);
            break;
        }
    }
}

// One connection per thread run. All libcurl calls for the handle happen
// here: connect, receive, send queued frames, cleanup. A new thread waits for
// the previous one to finish (connectionLock) so connections never overlap.
-(void)startWebSocketThread {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int32_t generation = connectionGeneration;
    [connectionLock lock];
    if (generation != connectionGeneration) {
        [connectionLock unlock];
        [pool release];
        return;
    }
    @synchronized(outgoingFrames) {
        [outgoingFrames removeAllObjects];
    }

    CURL *handle = curl_easy_init();
    if (handle) {
        curl_easy_setopt(handle, CURLOPT_URL, WS_GATEWAY_URL);
        NSString *caBundlePath = [DLUtil caBundlePath];
        curl_easy_setopt(handle, CURLOPT_SSL_VERIFYPEER, 1L);
        curl_easy_setopt(handle, CURLOPT_SSL_VERIFYHOST, 2L);
        if (caBundlePath) {
            curl_easy_setopt(handle, CURLOPT_CAINFO, [caBundlePath fileSystemRepresentation]);
        }
        curl_easy_setopt(handle, CURLOPT_USERAGENT, [[DLUtil userAgentString] UTF8String]);
        curl_easy_setopt(handle, CURLOPT_CONNECT_ONLY, 2L);
        curl_easy_setopt(handle, CURLOPT_CONNECTTIMEOUT, 20L);
        CURLcode res = curl_easy_perform(handle);
        if (res != CURLE_OK) {
            printf("WebSocket connect failed: %s\n", curl_easy_strerror(res));
        } else {
            curlWebSocketHandle = handle;
            NSMutableData *message = [[NSMutableData alloc] init];
            char buffer[16384];
            BOOL open = YES;
            // Discord sends Hello right after the handshake. If nothing at all
            // arrives, the connection is stalled; drop it so it is retried.
            NSDate *connectedAt = [NSDate date];
            BOOL receivedAnyFrame = NO;
            while (open && generation == connectionGeneration) {
                if (!receivedAnyFrame && -[connectedAt timeIntervalSinceNow] > 20.0) {
                    NSLog(@"Gateway sent no data within 20 seconds; reconnecting.");
                    break;
                }
                NSAutoreleasePool *loopPool = [[NSAutoreleasePool alloc] init];
                [self sendQueuedFramesOnHandle:handle];
                curl_socket_t socket = CURL_SOCKET_BAD;
                curl_easy_getinfo(handle, CURLINFO_ACTIVESOCKET, &socket);
                if (socket == CURL_SOCKET_BAD) open = NO;
                if (open) {
                    fd_set readSet;
                    FD_ZERO(&readSet);
                    FD_SET(socket, &readSet);
                    struct timeval timeout = { 0, 250000 };
                    select(socket + 1, &readSet, NULL, NULL, &timeout);
                }
                while (open && generation == connectionGeneration) {
                    size_t received = 0;
                    const struct curl_ws_frame *meta = NULL;
                    CURLcode result = curl_ws_recv(handle, buffer, sizeof(buffer), &received, &meta);
                    if (result == CURLE_AGAIN) break;
                    if (result != CURLE_OK) { open = NO; break; }
                    if (meta && (meta->flags & CURLWS_CLOSE)) { open = NO; break; }
                    if (received > 0) {
                        [message appendBytes:buffer length:received];
                        receivedAnyFrame = YES;
                    }
                    if (meta && meta->bytesleft == 0 && !(meta->flags & CURLWS_CONT) &&
                        (meta->flags & (CURLWS_TEXT | CURLWS_BINARY)) && [message length] > 0) {
                        NSData *complete = [NSData dataWithData:message];
                        [message setLength:0];
                        [self performSelectorOnMainThread:@selector(wsTextDataReceived:) withObject:complete waitUntilDone:YES];
                    }
                }
                [loopPool release];
            }
            [message release];
            curlWebSocketHandle = NULL;
        }
        curl_easy_cleanup(handle);
    }
    [connectionLock unlock];
    [pool release];

    if (generation == connectionGeneration && connectionState != DLWSConnectionStateDisconnected) {
        // The connection ended without us asking (stall, server close or
        // network error): reconnect instead of waiting for a heartbeat that
        // may never have been scheduled.
        [self notifyConnectionState:DLWSConnectionStateReconnecting];
        [self performSelectorOnMainThread:@selector(reconnectAfterUnexpectedClose) withObject:nil waitUntilDone:NO];
    }
    NSLog(@"Websocket Closed");
}

-(void)startWithAuthToken:(NSString *)inToken {
    reconnectScheduled = NO;
    [self notifyConnectionState:(didReconnect || shouldResume) ? DLWSConnectionStateReconnecting : DLWSConnectionStateConnecting];
    [token release];
    [inToken retain];
    token = inToken;
    [self startReachabilityMonitoring];
    [self abortCurrentConnection];
    [NSThread detachNewThreadSelector:@selector(startWebSocketThread) toTarget:self withObject:nil];
}
-(void)stop {
    if (heartbeatTimer) {
        [heartbeatTimer invalidate];
        heartbeatTimer = nil;
    }
    if (reachabilityTimer) {
        [reachabilityTimer invalidate];
        reachabilityTimer = nil;
    }
    [self abortCurrentConnection];
    shouldResume = NO;
    [self notifyConnectionState:DLWSConnectionStateDisconnected];
}
-(void)sendWSTextData:(NSData *)textData {
    if (![textData length]) return;
    @synchronized(outgoingFrames) {
        [outgoingFrames addObject:textData];
    }
}

-(void)sendWSHeartbeat {
    if (heartbeatResponseReceived) {
        heartbeatResponseReceived = NO;
        NSDictionary *response = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[NSNumber numberWithInt:OPCodeHeartbeat], [NSNumber numberWithInt:sequenceNumber], nil] forKeys:[NSArray arrayWithObjects:@kWSOperation, @kWSData, nil]];
        NSData *toSend = [[CJSONSerializer serializer] serializeDictionary:response error:nil];
        [self sendWSTextData:toSend];
    } else {
        shouldResume = YES;
        didResume = NO;
        [self abortCurrentConnection];
        [self performSelector:@selector(startWithAuthToken:) withObject:token afterDelay:1];
    }
}

-(void)handleResumeStatus {
    shouldResume = NO;
    if (!didResume) {
        didReconnect = YES;
        [self abortCurrentConnection];
        [self performSelector:@selector(startWithAuthToken:) withObject:token afterDelay:1];
    }
}

-(void)reconnectAfterUnexpectedClose {
    if (connectionState == DLWSConnectionStateDisconnected) return;
    [self scheduleReconnectCanResume:(sessionID != nil)];
}

-(void)scheduleReconnectCanResume:(BOOL)canResume {
    if (reconnectScheduled) {
        return;
    }
    reconnectScheduled = YES;
    [self notifyConnectionState:DLWSConnectionStateReconnecting];
    shouldResume = canResume;
    didResume = NO;
    if (!canResume) {
        [sessionID release];
        sessionID = nil;
        sequenceNumber = 0;
        didReconnect = YES;
    }
    [self abortCurrentConnection];
    [self performSelector:@selector(startWithAuthToken:) withObject:token afterDelay:2.0];
}

-(void)updateWSForDirectMessageChannel:(DLChannel *)c {
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    [data setObject:[c channelID] forKey:@"channel_id"];
    [d setObject:[NSNumber numberWithInt:OPCodeDMParticipantOp] forKey:@kWSOperation];
    [d setObject:data forKey:@kWSData];
    NSData *str = [[CJSONSerializer serializer] serializeDictionary:d error:nil];
    [self sendWSTextData:str];
}

-(void)updateWSForChannel:(DLChannel *)c inServer:(DLServer *)s {
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    [data setObject:[s serverID] forKey:@"guild_id"];
    [data setObject:[NSNumber numberWithBool:YES] forKey:@"typing"];
    [data setObject:[NSNumber numberWithBool:YES] forKey:@"activities"];
    [data setObject:[NSNumber numberWithBool:YES] forKey:@"threads"];
    NSArray *channelInfo = [NSArray arrayWithObjects:[NSArray arrayWithObjects:[NSNumber numberWithInt:0], [NSNumber numberWithInt:99], nil], nil];
    NSMutableDictionary *channels = [[NSMutableDictionary alloc] init];
    [channels setObject:channelInfo forKey:[c channelID]];
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    [data setObject:channels forKey:@"channels"];
    [d setObject:data forKey:@kWSData];
    [d setObject:[NSNumber numberWithInt:OPCodeServerMemberOp] forKey:@kWSOperation];
    NSData *str = [[CJSONSerializer serializer] serializeDictionary:d error:nil];
    [self sendWSTextData:str];
}

-(void)queryServer:(DLServer *)s forMembersContainingUsername:(NSString *)username {
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    [data setObject:[NSArray arrayWithObject:[s serverID]] forKey:@"guild_id"];
    [data setObject:username forKey:@"query"];
    [data setObject:[NSNumber numberWithInt:([username length] == 0 ? 100 : 10)] forKey:@"limit"];
    [data setObject:[NSNumber numberWithBool:YES] forKey:@"presences"];
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    [d setObject:data forKey:@kWSData];
    [d setObject:[NSNumber numberWithInt:OPCodeQueryServerMembers] forKey:@kWSOperation];
    NSData *str = [[CJSONSerializer serializer] serializeDictionary:d error:nil];
    [self sendWSTextData:str];
}

-(void)requestMembersForChannel:(DLChannel *)c inServer:(DLServer *)s from:(NSInteger)start to:(NSInteger)end {
    if (!c || !s) return;
    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    [data setObject:[s serverID] forKey:@"guild_id"];
    [data setObject:[NSNumber numberWithBool:NO] forKey:@"typing"];
    [data setObject:[NSNumber numberWithBool:YES] forKey:@"activities"];
    [data setObject:[NSNumber numberWithBool:YES] forKey:@"threads"];
    NSArray *range = [NSArray arrayWithObjects:[NSNumber numberWithInteger:start],
                                               [NSNumber numberWithInteger:end], nil];
    NSDictionary *channels = [NSDictionary dictionaryWithObject:[NSArray arrayWithObject:range]
                                                           forKey:[c channelID]];
    [data setObject:channels forKey:@"channels"];
    NSDictionary *packet = [NSDictionary dictionaryWithObjectsAndKeys:
                            [NSNumber numberWithInt:OPCodeServerMemberOp], @kWSOperation,
                            data, @kWSData, nil];
    NSData *serialized = [[CJSONSerializer serializer] serializeDictionary:packet error:nil];
    [self sendWSTextData:serialized];
}

// READY lists the signed-in user's member object per guild in merged_members
// (same order as guilds). Attach it so DLServer can evaluate permissions.
-(NSArray *)guildsWithOwnMembersFromReady:(NSDictionary *)ready {
    NSArray *guilds = [ready objectForKey:@"guilds"];
    NSArray *mergedMembers = [ready objectForKey:@"merged_members"];
    NSString *myID = [[[ready objectForKey:@"user"] objectForKey:@"id"] description];
    if (![guilds isKindOfClass:[NSArray class]] || ![mergedMembers isKindOfClass:[NSArray class]] ||
        [mergedMembers count] != [guilds count] || !myID) return guilds;
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:[guilds count]];
    for (NSUInteger index = 0; index < [guilds count]; index++) {
        NSDictionary *guild = [guilds objectAtIndex:index];
        NSArray *members = [mergedMembers objectAtIndex:index];
        NSDictionary *mine = nil;
        if ([members isKindOfClass:[NSArray class]]) {
            NSEnumerator *enumerator = [members objectEnumerator];
            NSDictionary *member;
            while ((member = [enumerator nextObject]) && !mine) {
                if ([member isKindOfClass:[NSDictionary class]] &&
                    [[[member objectForKey:@"user_id"] description] isEqualToString:myID]) mine = member;
            }
        }
        if (mine && [guild isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *copy = [NSMutableDictionary dictionaryWithDictionary:guild];
            [copy setObject:mine forKey:@"legacy_my_member"];
            [result addObject:copy];
        } else {
            [result addObject:guild];
        }
    }
    return result;
}

#pragma mark Delegated Functions

-(void)wsTextDataReceived:(NSData *)textData {
    NSDictionary *res = [[CJSONDeserializer deserializer] deserializeAsDictionary:textData error:nil];
    //NSLog(@"Res: %@", res);
    OPCode c = [[res objectForKey:@kWSOperation] intValue];
    switch (c) {
        case OPCodeGeneral: {
            [self notifyConnectionState:DLWSConnectionStateConnected];
            sequenceNumber = [[res objectForKey:@kWSSequence] intValue];
            NSString *type = [res objectForKey:@kWSType];
            if ([type isEqualToString:@"MESSAGE_CREATE"]) {
                DLMessage *m = [[DLMessage alloc] initWithDict:[res objectForKey:@kWSData]];
                [delegate wsDidReceiveMessage:m];
                [m release];
            } else if ([type isEqualToString:@"READY"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                sessionID = [[wsData objectForKey:@"session_id"] retain];
                [delegate wsDidReceiveServerData:[self guildsWithOwnMembersFromReady:wsData]];
                [delegate wsDidReceiveUserSettingsData:[wsData objectForKey:@"user_settings"]];
                [delegate wsDidReceiveUserData:[wsData objectForKey:@"user"]];
                if ([delegate respondsToSelector:@selector(wsDidReceiveRelationships:presences:)]) {
                    [delegate wsDidReceiveRelationships:[wsData objectForKey:@"relationships"]
                                              presences:[wsData objectForKey:@"presences"]];
                }
                [delegate wsDidReceivePrivateChannelData:[wsData objectForKey:@"private_channels"]];
                [delegate wsDidLoadAllDataAfterReconnection:didReconnect];
                [delegate wsDidReceiveReadStateData:[wsData
                                                     objectForKey:@"read_state"]];
                [self notifyConnectionState:DLWSConnectionStateConnected];
            } else if ([type isEqualToString:@"MESSAGE_ACK"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                NSMutableDictionary *messageData = [[[NSMutableDictionary alloc] init] autorelease];
                [messageData setObject:[wsData objectForKey:@"message_id"] forKey:@"id"];
                [messageData setObject:[wsData objectForKey:@"channel_id"] forKey:@"channel_id"];
                [delegate wsDidAcknowledgeMessage:[[DLMessage alloc] initWithDict:messageData]];
            } else if ([type isEqualToString:@"TYPING_START"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                if ([wsData objectForKey:@"guild_id"]) {
                    [delegate wsUserWithID:[wsData objectForKey:@"user_id"] didStartTypingInServerWithID:[wsData objectForKey:@"guild_id"] inChannelWithID:[wsData objectForKey:@"channel_id"] withMemberData:[wsData objectForKey:@"member"]];
                } else {
                    [delegate wsUserWithID:[wsData objectForKey:@"user_id"] didStartTypingInDirectMessageChannelWithID:[wsData objectForKey:@"channel_id"]];
                }
            } else if ([type isEqualToString:@"GUILD_MEMBERS_CHUNK"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                NSArray *memberData = [wsData objectForKey:@"members"];
                NSString *serverID = [wsData objectForKey:@"guild_id"];
                [delegate wsDidReceiveMemberData:memberData forServerWithID:serverID];
            } else if ([type isEqualToString:@"GUILD_MEMBER_LIST_UPDATE"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                NSMutableArray *memberData = [NSMutableArray array];
                NSEnumerator *operationEnumerator = [[wsData objectForKey:@"ops"] objectEnumerator];
                NSDictionary *operation;
                while (operation = [operationEnumerator nextObject]) {
                    NSArray *items = [operation objectForKey:@"items"];
                    if (![items isKindOfClass:[NSArray class]] && [operation objectForKey:@"item"]) {
                        items = [NSArray arrayWithObject:[operation objectForKey:@"item"]];
                    }
                    NSEnumerator *itemEnumerator = [items objectEnumerator];
                    NSDictionary *item;
                    while (item = [itemEnumerator nextObject]) {
                        NSDictionary *member = [item objectForKey:@"member"];
                        if ([member isKindOfClass:[NSDictionary class]]) {
                            NSDictionary *presence = [item objectForKey:@"presence"];
                            if ([presence isKindOfClass:[NSDictionary class]]) {
                                NSMutableDictionary *memberWithPresence = [NSMutableDictionary dictionaryWithDictionary:member];
                                [memberWithPresence setObject:presence forKey:@"presence"];
                                [memberData addObject:memberWithPresence];
                            } else {
                                [memberData addObject:member];
                            }
                        }
                    }
                }
                [delegate wsDidReceiveMemberData:memberData
                                  forServerWithID:[wsData objectForKey:@"guild_id"]];
            } else if ([type isEqualToString:@"PRESENCE_UPDATE"]) {
                // Friend presences arrive without a guild_id.
                NSDictionary *wsData = [res objectForKey:@kWSData];
                NSString *userID = [[[wsData objectForKey:@"user"] objectForKey:@"id"] description];
                if (userID && ![wsData objectForKey:@"guild_id"] &&
                    [delegate respondsToSelector:@selector(wsUserWithID:didUpdatePresenceStatus:)]) {
                    [delegate wsUserWithID:userID didUpdatePresenceStatus:[wsData objectForKey:@"status"]];
                }
            } else if ([type isEqualToString:@"MESSAGE_UPDATE"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                NSString *messageID = [wsData objectForKey:@"id"];
                [delegate wsMessageWithID:messageID wasUpdatedWithData:wsData];
            } else if ([type isEqualToString:@"MESSAGE_REACTION_ADD"] || [type isEqualToString:@"MESSAGE_REACTION_REMOVE"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                [delegate wsMessageWithID:[wsData objectForKey:@"message_id"]
                            reactionEmoji:[wsData objectForKey:@"emoji"]
                                  wasAdded:[type isEqualToString:@"MESSAGE_REACTION_ADD"]
                                  byUserID:[wsData objectForKey:@"user_id"]];
            } else if ([type isEqualToString:@"THREAD_CREATE"] || [type isEqualToString:@"THREAD_UPDATE"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                [delegate wsDidReceiveThreads:[NSArray arrayWithObject:wsData]
                              forServerWithID:[wsData objectForKey:@"guild_id"]];
            } else if ([type isEqualToString:@"THREAD_LIST_SYNC"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                NSArray *threads = [wsData objectForKey:@"threads"];
                [delegate wsDidReceiveThreads:threads ? threads : [NSArray array]
                              forServerWithID:[wsData objectForKey:@"guild_id"]];
            } else if ([type isEqualToString:@"THREAD_DELETE"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                [delegate wsDidDeleteThreadWithID:[wsData objectForKey:@"id"]
                                  forServerWithID:[wsData objectForKey:@"guild_id"]];
            } else if ([type isEqualToString:@"RESUMED"]) {
                didResume = YES;
                [self notifyConnectionState:DLWSConnectionStateConnected];
            }
            else if ([type isEqualToString:@"MESSAGE_DELETE"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                NSString *messageID = [wsData objectForKey:@"id"];
                [delegate wsMessageWithIDWasDeleted:messageID];
            }
            break;
        }
        case OPCodeHello: {
            heartbeatResponseReceived = YES;
            if (shouldResume) {
                NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
                [d setObject:[NSNumber numberWithInt:OPCodeResume] forKey:@kWSOperation];
                NSDictionary *data = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:token, sessionID, [NSNumber numberWithInt:sequenceNumber], nil] forKeys:[NSArray arrayWithObjects:@"token", @"session_id", @"seq", nil]];
                [d setObject:data forKey:@kWSData];
                NSData *str = [[CJSONSerializer serializer] serializeDictionary:d error:nil];
                [self sendWSTextData:str];
                if (heartbeatTimer) {
                    [heartbeatTimer invalidate];
                }
                heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:heartbeatInterval/1000.0 target:self selector:@selector(sendWSHeartbeat) userInfo:nil repeats:YES];
                [self performSelector:@selector(handleResumeStatus) withObject:nil afterDelay:2];
            } else {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                heartbeatInterval = [[wsData objectForKey:@"heartbeat_interval"] intValue];
                if (heartbeatTimer) {
                    [heartbeatTimer invalidate];
                }
                heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:heartbeatInterval/1000.0 target:self selector:@selector(sendWSHeartbeat) userInfo:nil repeats:YES];
                
                NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
                [d setObject:[NSNumber numberWithInt:OPCodeIdentify] forKey:@kWSOperation];
                [d setObject:[NSNumber numberWithBool:NO] forKey:@"compress"];
                NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
                [data setObject:[NSString stringWithString:token] forKey:@"token"];
                
                NSMutableDictionary *platformProps = [[NSMutableDictionary alloc] init];
                [platformProps setObject:@"Apple macOS" forKey:@"$os"];
                [platformProps setObject:@"Apple macOS" forKey:@"$browser"];
                [platformProps setObject:@"Apple Mac" forKey:@"$device"];
                [data setObject:platformProps forKey:@"properties"];
                
                NSMutableDictionary *presence = [[NSMutableDictionary alloc] init];
                [presence setObject:@"online" forKey:@"status"];
                [presence setObject:[NSNumber numberWithInt:0] forKey:@"since"];
                [presence setObject:[[NSArray alloc] init] forKey:@"activities"];
                [presence setObject:[NSNumber numberWithBool:NO] forKey:@"afk"];
                
                [data setObject:presence forKey:@"presence"];
                
                [d setObject:data forKey:@kWSData];
                
                NSData *toSend = [[CJSONSerializer serializer] serializeDictionary:d error:nil];
                [self sendWSTextData:toSend];
            }
            
            break;
        }
        case OPCodeHeartbeat:
            heartbeatResponseReceived = YES;
            [self sendWSHeartbeat];
            break;
        case OPCodeHeartbeatAck:
            heartbeatResponseReceived = YES;
            [self notifyConnectionState:DLWSConnectionStateConnected];
            break;
        case OPCodeReconnect:
            [self scheduleReconnectCanResume:YES];
            break;
        case OPCodeInvalidSession: {
            BOOL canResume = [[res objectForKey:@kWSData] boolValue];
            [self scheduleReconnectCanResume:canResume];
            break;
        }
        default:
            break;
    }
}

@end
