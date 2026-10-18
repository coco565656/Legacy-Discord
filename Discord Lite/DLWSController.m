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
// READY's geo_ordered_rtc_regions, sent with voice state updates like the official client.
static NSArray *preferredVoiceRegions = nil;
// Enqueued as a frame marker; the WebSocket thread turns it into a ping.
// MITM proxies such as AquaProxy close tunnels that stay quiet for ~30 s,
// and Discord's heartbeat interval is longer than that.
static NSString *GatewayKeepalivePingMarker = @"dl-gateway-keepalive-ping";

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
    // When the system proxy (AquaProxy and friends) carries the connection,
    // direct-host reachability flags do not describe the usable path.
    if ([DLUtil systemProxyServesHost:@"discord.com"]) return YES;
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
    if (connectionState != DLWSConnectionStateConnected && ![self isDiscordNetworkReachable]) {
        [self notifyConnectionState:DLWSConnectionStateReconnecting];
        return;
    }
    if (connectionState == DLWSConnectionStateConnected) return;
    // The network is usable but nothing is connecting and nothing is
    // scheduled: the retry loop died through one of the superseded-thread
    // paths (stale generation) and nobody would ever start again. Re-arm it.
    // This is what turns "one Websocket Closed and then silence" back into a
    // working login once the network settles.
    if (!reconnectScheduled && !connectionAttemptActive) {
        NSLog(@"[WS] Watchdog: reconnect loop was lost; re-arming (gen %d, resume=%d).", connectionGeneration, sessionID != nil);
        [self scheduleReconnectCanResume:(sessionID != nil)];
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
    connectionAttemptActive = NO;
    reconnectDelay = 2.0;
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
        if ([frame isKindOfClass:[NSString class]] && [(NSString *)frame isEqualToString:GatewayKeepalivePingMarker]) {
            size_t sent = 0;
            CURLcode pingResult = curl_ws_send(handle, "", 0, &sent, 0, CURLWS_PING);
            if (pingResult != CURLE_OK) NSLog(@"Gateway keepalive ping failed (%s).", curl_easy_strerror(pingResult));
            continue;
        }
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
    NSLog(@"[WS] Thread enter gen=%d.", generation);
    [connectionLock lock];
    if (generation != connectionGeneration) {
        [connectionLock unlock];
        NSLog(@"[WS] Thread stale-exit gen=%d (current %d).", generation, connectionGeneration);
        // Superseded before we started: report the end so the reachability
        // watchdog knows no attempt from THIS thread is in flight.
        [self performSelectorOnMainThread:@selector(wsThreadDidEndWithGeneration:)
                               withObject:[NSNumber numberWithInt:generation]
                            waitUntilDone:NO];
        [pool release];
        return;
    }
    @synchronized(outgoingFrames) {
        [outgoingFrames removeAllObjects];
    }

    CURL *handle = curl_easy_init();
    if (handle) {
        curl_easy_setopt(handle, CURLOPT_URL, WS_GATEWAY_URL);
        char errorBuffer[CURL_ERROR_SIZE];
        errorBuffer[0] = '\0';
        curl_easy_setopt(handle, CURLOPT_ERRORBUFFER, errorBuffer);
        NSString *caBundlePath = [DLUtil effectiveCAPath];
        curl_easy_setopt(handle, CURLOPT_SSL_VERIFYPEER, 1L);
        curl_easy_setopt(handle, CURLOPT_SSL_VERIFYHOST, 2L);
        if (caBundlePath) {
            curl_easy_setopt(handle, CURLOPT_CAINFO, [caBundlePath fileSystemRepresentation]);
        }
        curl_easy_setopt(handle, CURLOPT_USERAGENT, [[DLUtil userAgentString] UTF8String]);
        [DLUtil applySystemProxyToCurlHandle:handle url:[NSString stringWithUTF8String:WS_GATEWAY_URL]];
        // The upgrade handshake needs HTTP/1.1; never let curl pick h2 here.
        curl_easy_setopt(handle, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1);
        curl_easy_setopt(handle, CURLOPT_CONNECT_ONLY, 2L);
        curl_easy_setopt(handle, CURLOPT_CONNECTTIMEOUT, 20L);
        CURLcode res = curl_easy_perform(handle);
        if (res != CURLE_OK) {
            NSLog(@"WebSocket connect failed: %s (%s)", curl_easy_strerror(res), errorBuffer[0] ? errorBuffer : "no detail");
        } else {
            NSLog(@"Gateway connection established.");
            curlWebSocketHandle = handle;
            [self performSelectorOnMainThread:@selector(scheduleGatewayKeepalive) withObject:nil waitUntilDone:NO];
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
                if (socket == CURL_SOCKET_BAD) {
                    NSLog(@"Gateway socket disappeared after %.1f seconds.", -[connectedAt timeIntervalSinceNow]);
                    open = NO;
                }
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
                    if (result != CURLE_OK) {
                        NSLog(@"Gateway receive failed after %.1f seconds (%s).", -[connectedAt timeIntervalSinceNow], curl_easy_strerror(result));
                        open = NO;
                        break;
                    }
                    if (meta && (meta->flags & CURLWS_CLOSE)) {
                        unsigned int closeCode = 0;
                        if (received >= 2) closeCode = ((unsigned char)buffer[0] << 8) | (unsigned char)buffer[1];
                        NSLog(@"Gateway close frame after %.1f seconds (code %u).", -[connectedAt timeIntervalSinceNow], closeCode);
                        open = NO;
                        break;
                    }
                    if (meta && (meta->flags & CURLWS_PONG)) continue;
                    if (meta && (meta->flags & CURLWS_PING)) {
                        // A server ping must be answered with the same payload.
                        size_t sent = 0;
                        if (received > 0) curl_ws_send(handle, buffer, received, &sent, 0, CURLWS_PONG);
                        continue;
                    }
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
            [self performSelectorOnMainThread:@selector(invalidateGatewayKeepalive) withObject:nil waitUntilDone:NO];
            curlWebSocketHandle = NULL;
        }
        curl_easy_cleanup(handle);
    }
    [connectionLock unlock];
    [pool release];

    int32_t endGeneration = connectionGeneration;
    NSLog(@"[WS] Thread end gen=%d state=%d.", endGeneration, connectionState);
    if (endGeneration == connectionGeneration && connectionState != DLWSConnectionStateDisconnected) {
        // The connection ended without us asking (stall, server close or
        // network error): reconnect instead of waiting for a heartbeat that
        // may never have been scheduled.
        [self notifyConnectionState:DLWSConnectionStateReconnecting];
        [self performSelectorOnMainThread:@selector(reconnectAfterUnexpectedClose) withObject:nil waitUntilDone:NO];
    }
    // Re-read the generation now: if a successor was scheduled above, its
    // abort bumped it and it owns the attempt flag from here on. When we are
    // still current and nobody was scheduled, clear the flag so the
    // reachability watchdog can schedule a fresh attempt within 2 seconds.
    [self performSelectorOnMainThread:@selector(wsThreadDidEndWithGeneration:)
                           withObject:[NSNumber numberWithInt:endGeneration]
                        waitUntilDone:NO];
    NSLog(@"Websocket Closed");
}

-(void)startWithAuthToken:(NSString *)inToken {
    reconnectScheduled = NO;
    // A retry attempt belongs to a new connection: the previous session's
    // heartbeat timer must not keep firing around the new one (each Hello
    // creates a fresh timer).
    if (heartbeatTimer) {
        [heartbeatTimer invalidate];
        heartbeatTimer = nil;
    }
    [self notifyConnectionState:(didReconnect || shouldResume) ? DLWSConnectionStateReconnecting : DLWSConnectionStateConnecting];
    [token release];
    [inToken retain];
    token = inToken;
    [self startReachabilityMonitoring];
    [self abortCurrentConnection];
    // The thread is spawning: mark the attempt live so the reachability
    // watchdog stays out of the way until this thread's end notice arrives.
    connectionAttemptActive = YES;
    NSLog(@"[WS] Start attempt gen=%d resume=%d.", connectionGeneration, shouldResume);
    [NSThread detachNewThreadSelector:@selector(startWebSocketThread) toTarget:self withObject:nil];
}
-(void)wsThreadDidEndWithGeneration:(NSNumber *)generationNumber {
    if ((int32_t)[generationNumber intValue] == connectionGeneration) {
        connectionAttemptActive = NO;
    }
    NSLog(@"[WS] Thread-end notice gen=%d (current %d, active=%d, scheduled=%d).",
          (int)[generationNumber intValue], connectionGeneration, connectionAttemptActive, reconnectScheduled);
}
-(void)stop {
    [self invalidateGatewayKeepalive];
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
// Keep the tunnel warmer than MITM-proxy idle deadlines (about 30 s). Pings
// are queued like other frames so all curl_ws_send calls stay on the
// WebSocket thread.
-(void)scheduleGatewayKeepalive {
    if (connectionState == DLWSConnectionStateDisconnected) return;
    if (keepaliveTimer) return;
    // Retained here and released in invalidateGatewayKeepalive.
    keepaliveTimer = [[NSTimer timerWithTimeInterval:15.0 target:self selector:@selector(gatewayKeepaliveTick:) userInfo:nil repeats:YES] retain];
    [[NSRunLoop currentRunLoop] addTimer:keepaliveTimer forMode:NSRunLoopCommonModes];
}
-(void)gatewayKeepaliveTick:(NSTimer *)timer {
    if (!curlWebSocketHandle) return;
    @synchronized(outgoingFrames) {
        [outgoingFrames addObject:GatewayKeepalivePingMarker];
    }
}
-(void)invalidateGatewayKeepalive {
    if (keepaliveTimer) {
        [keepaliveTimer invalidate];
        [keepaliveTimer release];
        keepaliveTimer = nil;
    }
}

-(void)sendWSHeartbeat {
    if (heartbeatResponseReceived) {
        heartbeatResponseReceived = NO;
        NSDictionary *response = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[NSNumber numberWithInt:OPCodeHeartbeat], [NSNumber numberWithInt:sequenceNumber], nil] forKeys:[NSArray arrayWithObjects:@kWSOperation, @kWSData, nil]];
        NSData *toSend = [[CJSONSerializer serializer] serializeDictionary:response error:nil];
        [self sendWSTextData:toSend];
    } else {
        // Heartbeats time out only in a live session: a tick landing while an
        // attempt is still connecting belongs to an older connection and must
        // not abort the newer one.
        if (connectionState != DLWSConnectionStateConnected) {
            NSLog(@"[WS] Heartbeat tick while state=%d ignored (gen %d).", connectionState, connectionGeneration);
            return;
        }
        shouldResume = YES;
        didResume = NO;
        // A retry is already pending 1 second out; mark it so the reachability
        // watchdog does not schedule a second overlapping attempt meanwhile.
        reconnectScheduled = YES;
        NSLog(@"[WS] No heartbeat response (gen %d): reconnecting.", connectionGeneration);
        if (heartbeatTimer) {
            [heartbeatTimer invalidate];
            heartbeatTimer = nil;
        }
        [self abortCurrentConnection];
        [self performSelector:@selector(performReconnectIfCurrent:)
                   withObject:[NSNumber numberWithInt:connectionGeneration]
                   afterDelay:1.0];
    }
}

// Deferred retries carry the generation number current when they were
// scheduled. abortCurrentConnection bumps the generation, which quietly
// expires every retry scheduled before it — without this, stale one-second
// retries from an earlier failure keep aborting whatever connection the
// newer attempts manage to establish (observed as a rapid connect loop).
-(void)performReconnectIfCurrent:(NSNumber *)generationNumber {
    if ((int32_t)[generationNumber intValue] != connectionGeneration) {
        NSLog(@"[WS] Retry dropped: generation moved (%d -> %d).", [generationNumber intValue], connectionGeneration);
        // A superseded retry is no longer pending anything: release the flag
        // so the reachability watchdog can re-arm instead of seeing a
        // schedule that will never fire.
        reconnectScheduled = NO;
        return;
    }
    NSLog(@"[WS] Retry firing (gen %d).", connectionGeneration);
    [self startWithAuthToken:token];
}

// Gives a resumed session two seconds to be confirmed before falling back to
// a fresh identify. The callback validates the generation of the connection
// whose resume it guards: if that connection died meanwhile — or was replaced
// by a newer attempt — this must not touch the successor's live connection.
-(void)validateResumeForGeneration:(NSNumber *)generationNumber {
    if ((int32_t)[generationNumber intValue] != connectionGeneration) {
        NSLog(@"[WS] Stale resume check dropped (gen %d, current %d).", [generationNumber intValue], connectionGeneration);
        return;
    }
    if (didResume) return;
    NSLog(@"[WS] Resume unconfirmed after 2s (gen %d): reconnecting.", connectionGeneration);
    didReconnect = YES;
    reconnectScheduled = YES;
    [self abortCurrentConnection];
    [self performSelector:@selector(performReconnectIfCurrent:)
               withObject:[NSNumber numberWithInt:connectionGeneration]
               afterDelay:1.0];
}

-(void)reconnectAfterUnexpectedClose {
    if (connectionState == DLWSConnectionStateDisconnected) return;
    // A resume request that never received RESUMED means the gateway dropped
    // the session (TTL exceeded or sequence mismatch). Fall back to a fresh
    // identify instead of trying to resume the same dead session forever.
    if (shouldResume && !didResume) {
        NSLog(@"[WS] Discarding unresumed session; next attempt will identify.");
        [sessionID release];
        sessionID = nil;
        sequenceNumber = 0;
        didResume = NO;
        shouldResume = NO;
        didReconnect = YES;
    }
    [self scheduleReconnectCanResume:(sessionID != nil)];
}

-(void)scheduleReconnectCanResume:(BOOL)canResume {
    if (reconnectScheduled) {
        return;
    }
    reconnectScheduled = YES;
    NSLog(@"[WS] Scheduling reconnect gen=%d delay=%.0fs resume=%d.", connectionGeneration, reconnectDelay, canResume);
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
    // Back off between failed attempts; the delay resets to 2 seconds in the
    // Hello handler once the gateway accepts a connection again. The retry
    // validates its generation: if something superseded this schedule the
    // delayed start quietly expires instead of stacking another attempt.
    [self performSelector:@selector(performReconnectIfCurrent:)
               withObject:[NSNumber numberWithInt:connectionGeneration]
               afterDelay:reconnectDelay];
    reconnectDelay = MIN(reconnectDelay * 2.0, 60.0);
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

-(void)sendVoiceStateUpdateForGuildID:(NSString *)guildID channelID:(NSString *)channelID
                             selfMute:(BOOL)selfMute selfDeaf:(BOOL)selfDeaf {
    NSDictionary *data = [NSDictionary dictionaryWithObjectsAndKeys:
                          (guildID ? (id)guildID : (id)[NSNull null]), @"guild_id",
                          (channelID ? (id)channelID : (id)[NSNull null]), @"channel_id",
                          [NSNumber numberWithBool:selfMute], @"self_mute",
                          [NSNumber numberWithBool:selfDeaf], @"self_deaf",
                          [NSNumber numberWithBool:NO], @"self_video", nil];
    if ([preferredVoiceRegions count]) {
        NSMutableDictionary *withRegions = [NSMutableDictionary dictionaryWithDictionary:data];
        [withRegions setObject:[preferredVoiceRegions objectAtIndex:0] forKey:@"preferred_region"];
        [withRegions setObject:preferredVoiceRegions forKey:@"preferred_regions"];
        data = withRegions;
    }
    NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithInt:OPCodeVoiceStateUpdate], @kWSOperation, data, @kWSData, nil];
    NSData *json = [[CJSONSerializer serializer] serializeDictionary:payload error:nil];
    [self sendWSTextData:json];
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
    NSError *parseError = nil;
    NSDictionary *res = [[CJSONDeserializer deserializer] deserializeAsDictionary:textData error:&parseError];
    if (!res) {
        NSString *raw = [[[NSString alloc] initWithData:textData encoding:NSUTF8StringEncoding] autorelease];
        NSLog(@"Gateway message not parsed (%@): %@", [parseError localizedDescription],
              raw ? [raw substringToIndex:MIN((NSUInteger)160, [raw length])] : @"(not UTF-8)");
    }
    //NSLog(@"Res: %@", res);
    OPCode c = [[res objectForKey:@kWSOperation] intValue];
    if (c != OPCodeGeneral) {
        NSLog(@"[WS] Received op=%d (gen %d).", c, connectionGeneration);
    } else {
        NSString *type = [res objectForKey:@kWSType];
        if ([type isEqualToString:@"READY"] || [type isEqualToString:@"RESUMED"]) {
            NSLog(@"[WS] Received %@ (gen %d).", type, connectionGeneration);
        }
    }
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
                id regions = [wsData objectForKey:@"geo_ordered_rtc_regions"];
                if ([regions isKindOfClass:[NSArray class]]) {
                    [preferredVoiceRegions release];
                    preferredVoiceRegions = [regions copy];
                }

                [delegate wsDidReceiveServerData:[self guildsWithOwnMembersFromReady:wsData]];
                [delegate wsDidReceiveUserSettingsData:[wsData objectForKey:@"user_settings"]];
                [delegate wsDidReceiveUserData:[wsData objectForKey:@"user"]];
                if ([delegate respondsToSelector:@selector(wsDidReceiveRelationships:presences:)]) {
                    [delegate wsDidReceiveRelationships:[wsData objectForKey:@"relationships"]
                                              presences:[wsData objectForKey:@"presences"]];
                }
                [delegate wsDidReceivePrivateChannelData:[wsData objectForKey:@"private_channels"]];
                [delegate wsDidLoadAllDataAfterReconnection:didReconnect];
                if ([delegate respondsToSelector:@selector(wsDidReceiveUserGuildSettings:replacingAll:)]) {
                    [delegate wsDidReceiveUserGuildSettings:[wsData objectForKey:@"user_guild_settings"] replacingAll:YES];
                }
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
            } else if ([type isEqualToString:@"USER_GUILD_SETTINGS_UPDATE"]) {
                if ([delegate respondsToSelector:@selector(wsDidReceiveUserGuildSettings:replacingAll:)]) {
                    [delegate wsDidReceiveUserGuildSettings:[res objectForKey:@kWSData] replacingAll:NO];
                }
            } else if ([type isEqualToString:@"VOICE_STATE_UPDATE"] || [type isEqualToString:@"VOICE_SERVER_UPDATE"]) {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                if ([wsData isKindOfClass:[NSDictionary class]]) {
                    [[NSNotificationCenter defaultCenter] postNotificationName:([type isEqualToString:@"VOICE_STATE_UPDATE"]
                                                                               ? DLVoiceStateUpdateNotification
                                                                               : DLVoiceServerUpdateNotification)
                                                                        object:self userInfo:wsData];
                }
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
            // The gateway accepted the connection: clear the reconnect
            // backoff for any future failure.
            reconnectDelay = 2.0;
            if (shouldResume) {
                NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
                [d setObject:[NSNumber numberWithInt:OPCodeResume] forKey:@kWSOperation];
                NSDictionary *data = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:token, sessionID, [NSNumber numberWithInt:sequenceNumber], nil] forKeys:[NSArray arrayWithObjects:@"token", @"session_id", @"seq", nil]];
                [d setObject:data forKey:@kWSData];
                NSData *str = [[CJSONSerializer serializer] serializeDictionary:d error:nil];
                NSLog(@"[WS] Sending resume (gen %d session=%@ seq=%d).", connectionGeneration, sessionID, sequenceNumber);
                [self sendWSTextData:str];
                if (heartbeatTimer) {
                    [heartbeatTimer invalidate];
                }
                heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:heartbeatInterval/1000.0 target:self selector:@selector(sendWSHeartbeat) userInfo:nil repeats:YES];
                [self performSelector:@selector(validateResumeForGeneration:)
                           withObject:[NSNumber numberWithInt:connectionGeneration]
                           afterDelay:2];
            } else {
                NSDictionary *wsData = [res objectForKey:@kWSData];
                heartbeatInterval = [[wsData objectForKey:@"heartbeat_interval"] intValue];
                if (heartbeatTimer) {
                    [heartbeatTimer invalidate];
                }
                heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:heartbeatInterval/1000.0 target:self selector:@selector(sendWSHeartbeat) userInfo:nil repeats:YES];
                
                NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
                [d setObject:[NSNumber numberWithInt:OPCodeIdentify] forKey:@kWSOperation];
                NSLog(@"[WS] Sending identify (gen %d).", connectionGeneration);
                [d setObject:[NSNumber numberWithBool:NO] forKey:@"compress"];
                NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
                [data setObject:[NSString stringWithString:token] forKey:@"token"];
                
                NSMutableDictionary *platformProps = [[NSMutableDictionary alloc] init];
                // Gateway v10 property names (the "$"-prefixed ones are gone).
                [platformProps setObject:@"Mac OS X" forKey:@"os"];
                [platformProps setObject:@"Legacy Discord" forKey:@"browser"];
                [platformProps setObject:@"" forKey:@"device"];
                [platformProps setObject:[[NSProcessInfo processInfo] operatingSystemVersionString] forKey:@"os_version"];
                [platformProps setObject:[[NSLocale currentLocale] localeIdentifier] forKey:@"system_locale"];
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
