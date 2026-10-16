//
//  DLVoiceConnection.m
//  Legacy Discord
//
//  Protocol: https://docs.discord.com/developers/topics/voice-connections
//  (voice gateway v8, aead_aes256_gcm_rtpsize) and the DAVE protocol
//  (https://daveprotocol.com) through libdave's C API.
//

#import "DLVoiceConnection.h"
#import "DLVoiceLibrary.h"
#import "DLUtil.h"
#import "CJSONSerializer.h"
#import "CJSONDeserializer.h"
#include "curl_headers/curl.h"
#include "ldv_protocol.h"
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#include <libkern/OSAtomic.h>

// Voice gateway opcodes.
enum {
    DLVoiceOpIdentify = 0,
    DLVoiceOpSelectProtocol = 1,
    DLVoiceOpReady = 2,
    DLVoiceOpHeartbeat = 3,
    DLVoiceOpSessionDescription = 4,
    DLVoiceOpSpeaking = 5,
    DLVoiceOpHeartbeatAck = 6,
    DLVoiceOpHello = 8,
    DLVoiceOpClientsConnect = 11,
    DLVoiceOpClientDisconnect = 13,
    DLVoiceOpDavePrepareTransition = 21,
    DLVoiceOpDaveExecuteTransition = 22,
    DLVoiceOpDaveTransitionReady = 23,
    DLVoiceOpDavePrepareEpoch = 24,
    DLVoiceOpDaveExternalSender = 25,
    DLVoiceOpDaveKeyPackage = 26,
    DLVoiceOpDaveProposals = 27,
    DLVoiceOpDaveCommitWelcome = 28,
    DLVoiceOpDaveAnnounceCommit = 29,
    DLVoiceOpDaveWelcome = 30,
    DLVoiceOpDaveInvalidCommitWelcome = 31
};

static const char *DLVoiceEncryptionMode = "aead_aes256_gcm_rtpsize";

// Everything below is owned by the voice thread.
typedef struct {
    const DLVoiceAPI *api;
    CURL *ws;
    int udp;
    // Gateway
    int sequenceAck;
    double heartbeatInterval;      // seconds, 0 until Hello
    double nextHeartbeat;
    double lastHeartbeatAck;
    BOOL identified;
    // Media
    uint32_t ssrc;
    char remoteIP[64];
    uint16_t remotePort;
    BOOL discoveryDone;
    double nextDiscovery;
    int discoveryAttempts;
    BOOL haveKey;
    uint8_t secretKey[32];
    uint32_t sendNonce;
    uint16_t sendSequence;
    uint32_t sendTimestamp;
    double nextKeepAlive;
    uint32_t keepAliveCounter;
    BOOL speaking;
    // DAVE
    uint16_t daveVersion;
    DAVESessionHandle session;
    DAVEEncryptorHandle encryptor;
    NSMutableDictionary *decryptors;     // user id -> NSValue(DAVEDecryptorHandle)
    NSMutableDictionary *ssrcUsers;      // NSNumber ssrc -> user id
    NSMutableSet *connectedUsers;        // recognised user ids (excluding self)
    NSMutableDictionary *pendingTransitions; // NSNumber id -> NSNumber version
    BOOL daveActive;
} DLVoiceThread;

static double DLNow(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1000000.0;
}

@interface DLVoiceConnection ()
-(void)runVoiceThread;
-(void)notifyState:(DLVoiceConnectionState)state reason:(NSString *)reason;
@end

@implementation DLVoiceConnection

-(id)initWithEndpoint:(NSString *)inEndpoint token:(NSString *)inToken sessionID:(NSString *)inSessionID
             serverID:(NSString *)inServerID userID:(NSString *)inUserID channelID:(NSString *)inChannelID {
    self = [super init];
    if (self) {
        // The endpoint comes as "host:port" (sometimes with a scheme).
        NSString *host = inEndpoint;
        if ([host hasPrefix:@"wss://"]) host = [host substringFromIndex:6];
        if ([host hasSuffix:@"/"]) host = [host substringToIndex:[host length] - 1];
        endpoint = [host copy];
        token = [inToken copy];
        sessionID = [inSessionID copy];
        serverID = [inServerID copy];
        userID = [[inUserID description] copy];
        channelID = [[inChannelID description] copy];
        outgoingFrames = [[NSMutableArray alloc] init];
        statistics = [[NSMutableDictionary alloc] init];
    }
    return self;
}

-(void)setDelegate:(id<DLVoiceConnectionDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)start {
    if (running) return;
    running = 1;
    [self retain]; // released when the thread ends
    [NSThread detachNewThreadSelector:@selector(runVoiceThread) toTarget:self withObject:nil];
}

-(void)stop {
    OSAtomicCompareAndSwap32Barrier(1, 0, &running);
}

-(void)sendOpusFrame:(NSData *)frame {
    if (![frame length]) return;
    @synchronized(outgoingFrames) {
        // Never let a stalled connection build up latency.
        if ([outgoingFrames count] > 10) [outgoingFrames removeObjectAtIndex:0];
        [outgoingFrames addObject:frame];
    }
}

-(NSDictionary *)statistics {
    @synchronized(statistics) {
        return [[statistics copy] autorelease];
    }
}

-(void)countStatistic:(NSString *)name {
    @synchronized(statistics) {
        NSNumber *value = [statistics objectForKey:name];
        [statistics setObject:[NSNumber numberWithUnsignedLongLong:[value unsignedLongLongValue] + 1] forKey:name];
    }
}

-(void)setStatistic:(NSString *)name value:(id)value {
    @synchronized(statistics) {
        if (value) [statistics setObject:value forKey:name];
    }
}

#pragma mark Main-thread notifications

-(void)deliverState:(NSArray *)stateAndReason {
    DLVoiceConnectionState state = (DLVoiceConnectionState)[[stateAndReason objectAtIndex:0] intValue];
    NSString *reason = [stateAndReason count] > 1 ? [stateAndReason objectAtIndex:1] : nil;
    [delegate voiceConnection:self didChangeState:state reason:reason];
}

-(void)notifyState:(DLVoiceConnectionState)state reason:(NSString *)reason {
    NSArray *payload = reason ? [NSArray arrayWithObjects:[NSNumber numberWithInt:state], reason, nil]
                              : [NSArray arrayWithObject:[NSNumber numberWithInt:state]];
    [self performSelectorOnMainThread:@selector(deliverState:) withObject:payload waitUntilDone:NO];
}

-(void)deliverFrame:(NSArray *)frameInfo {
    if ([delegate respondsToSelector:@selector(voiceConnection:didReceiveOpusFrame:fromUserID:sequence:)]) {
        [delegate voiceConnection:self didReceiveOpusFrame:[frameInfo objectAtIndex:0]
                       fromUserID:[frameInfo objectAtIndex:1]
                         sequence:(uint16_t)[[frameInfo objectAtIndex:2] unsignedShortValue]];
    }
}

-(void)deliverSpeaking:(NSArray *)speakingInfo {
    if ([delegate respondsToSelector:@selector(voiceConnection:userID:didSpeak:)]) {
        [delegate voiceConnection:self userID:[speakingInfo objectAtIndex:0]
                         didSpeak:[[speakingInfo objectAtIndex:1] boolValue]];
    }
}

-(void)deliverEncryption:(NSNumber *)active {
    if ([delegate respondsToSelector:@selector(voiceConnection:endToEndEncryptionDidChange:)]) {
        [delegate voiceConnection:self endToEndEncryptionDidChange:[active boolValue]];
    }
}

#pragma mark WebSocket I/O (voice thread)

-(BOOL)sendWS:(DLVoiceThread *)t bytes:(const void *)bytes length:(size_t)length binary:(BOOL)binary {
    int attempt;
    for (attempt = 0; attempt < 200; attempt++) {
        size_t sent = 0;
        CURLcode result = curl_ws_send(t->ws, bytes, length, &sent, 0, binary ? CURLWS_BINARY : CURLWS_TEXT);
        if (result == CURLE_AGAIN) { usleep(5000); continue; }
        return result == CURLE_OK;
    }
    return NO;
}

-(void)sendOp:(int)op data:(id)data thread:(DLVoiceThread *)t {
    NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:op], @"op",
                             (data ? data : [NSNull null]), @"d", nil];
    NSData *json = [[CJSONSerializer serializer] serializeDictionary:payload error:nil];
    if (json) [self sendWS:t bytes:[json bytes] length:[json length] binary:NO];
}

-(void)sendBinaryOp:(uint8_t)op payload:(const uint8_t *)payload length:(size_t)length thread:(DLVoiceThread *)t {
    NSMutableData *message = [NSMutableData dataWithCapacity:length + 1];
    [message appendBytes:&op length:1];
    if (length) [message appendBytes:payload length:length];
    [self sendWS:t bytes:[message bytes] length:[message length] binary:YES];
}

-(void)sendHeartbeat:(DLVoiceThread *)t {
    long long nonce = (long long)(DLNow() * 1000.0);
    NSDictionary *data = [NSDictionary dictionaryWithObjectsAndKeys:
                          [NSNumber numberWithLongLong:nonce], @"t",
                          [NSNumber numberWithInt:t->sequenceAck], @"seq_ack", nil];
    [self sendOp:DLVoiceOpHeartbeat data:data thread:t];
}

#pragma mark DAVE (voice thread)

static void DLVoiceMLSFailure(const char *source, const char *reason, void *userData) {
    NSLog(@"DAVE MLS failure in %s: %s", source ? source : "?", reason ? reason : "?");
}

-(void)setDaveActive:(BOOL)active thread:(DLVoiceThread *)t {
    if (t->daveActive == active) return;
    t->daveActive = active;
    [self setStatistic:@"dave" value:[NSNumber numberWithBool:active]];
    [self performSelectorOnMainThread:@selector(deliverEncryption:) withObject:[NSNumber numberWithBool:active] waitUntilDone:NO];
}

-(DAVEDecryptorHandle)decryptorForUser:(NSString *)user thread:(DLVoiceThread *)t create:(BOOL)create {
    NSValue *value = [t->decryptors objectForKey:user];
    if (value) return (DAVEDecryptorHandle)[value pointerValue];
    if (!create) return NULL;
    DAVEDecryptorHandle decryptor = t->api->decryptorCreate();
    if (!decryptor) return NULL;
    t->api->decryptorSetPassthrough(decryptor, t->daveVersion == 0);
    [t->decryptors setObject:[NSValue valueWithPointer:decryptor] forKey:user];
    return decryptor;
}

-(void)recognisedUsers:(DLVoiceThread *)t list:(const char ***)list count:(size_t *)count holder:(NSMutableArray *)holder {
    [holder addObject:userID];
    [holder addObjectsFromArray:[t->connectedUsers allObjects]];
    const char **ids = malloc(sizeof(char *) * [holder count]);
    NSUInteger index;
    for (index = 0; index < [holder count]; index++) ids[index] = [[holder objectAtIndex:index] UTF8String];
    *list = ids;
    *count = [holder count];
}

// Starts (or restarts) membership in the MLS group for daveVersion.
-(void)daveReinitialize:(DLVoiceThread *)t {
    if (t->daveVersion == 0) {
        if (t->session) t->api->sessionReset(t->session);
        t->api->encryptorSetPassthrough(t->encryptor, true);
        [self setDaveActive:NO thread:t];
        return;
    }
    if (!t->session) t->session = t->api->sessionCreate(NULL, NULL, DLVoiceMLSFailure, NULL);
    if (!t->session) return;
    t->api->sessionInit(t->session, t->daveVersion, strtoull([channelID UTF8String], NULL, 10), [userID UTF8String]);
    uint8_t *keyPackage = NULL;
    size_t keyPackageLength = 0;
    t->api->sessionGetKeyPackage(t->session, &keyPackage, &keyPackageLength);
    if (keyPackage && keyPackageLength) {
        [self sendBinaryOp:DLVoiceOpDaveKeyPackage payload:keyPackage length:keyPackageLength thread:t];
    }
    if (keyPackage) t->api->free(keyPackage);
    [self countStatistic:@"daveKeyPackages"];
}

// Hands the current group's media keys to the encryptor and decryptors.
-(void)daveApplyKeyRatchets:(DLVoiceThread *)t roster:(NSArray *)roster {
    if (!t->session || t->daveVersion == 0) return;
    DAVEKeyRatchetHandle own = t->api->sessionGetKeyRatchet(t->session, [userID UTF8String]);
    if (own) {
        t->api->encryptorSetKeyRatchet(t->encryptor, own); // copies the ratchet
        t->api->encryptorSetPassthrough(t->encryptor, false);
        t->api->keyRatchetDestroy(own);
    }
    NSMutableSet *users = [NSMutableSet setWithArray:roster];
    [users addObjectsFromArray:[t->decryptors allKeys]];
    [users removeObject:userID];
    NSEnumerator *enumerator = [users objectEnumerator];
    NSString *user;
    while (user = [enumerator nextObject]) {
        DAVEKeyRatchetHandle ratchet = t->api->sessionGetKeyRatchet(t->session, [user UTF8String]);
        if (!ratchet) continue;
        DAVEDecryptorHandle decryptor = [self decryptorForUser:user thread:t create:YES];
        if (decryptor) {
            t->api->decryptorSetKeyRatchet(decryptor, ratchet);
            t->api->decryptorSetPassthrough(decryptor, false);
        }
        t->api->keyRatchetDestroy(ratchet);
    }
    NSLog(@"Voice: DAVE key ratchets applied for %lu other user(s)", (unsigned long)[users count]);
    [self setDaveActive:YES thread:t];
}

-(NSArray *)rosterFromIds:(uint64_t *)ids count:(size_t)count {
    NSMutableArray *roster = [NSMutableArray arrayWithCapacity:count];
    size_t index;
    for (index = 0; index < count; index++) {
        [roster addObject:[NSString stringWithFormat:@"%llu", (unsigned long long)ids[index]]];
    }
    return roster;
}

-(void)daveExecuteTransition:(uint16_t)transitionId thread:(DLVoiceThread *)t {
    NSNumber *key = [NSNumber numberWithUnsignedShort:transitionId];
    NSNumber *version = [t->pendingTransitions objectForKey:key];
    if (!version) return;
    uint16_t oldVersion = t->daveVersion;
    t->daveVersion = [version unsignedShortValue];
    [t->pendingTransitions removeObjectForKey:key];
    if (t->daveVersion == 0) {
        // Downgrade: media goes unencrypted end to end from now on.
        t->api->encryptorSetPassthrough(t->encryptor, true);
        NSEnumerator *enumerator = [t->decryptors objectEnumerator];
        NSValue *value;
        while (value = [enumerator nextObject]) t->api->decryptorSetPassthrough((DAVEDecryptorHandle)[value pointerValue], true);
        [self setDaveActive:NO thread:t];
    } else {
        [self daveApplyKeyRatchets:t roster:nil];
    }
    if (oldVersion != t->daveVersion) NSLog(@"Voice: DAVE protocol v%u -> v%u (transition %u)", oldVersion, t->daveVersion, transitionId);
}

-(void)daveInvalidate:(uint16_t)transitionId thread:(DLVoiceThread *)t {
    NSDictionary *data = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedShort:transitionId] forKey:@"transition_id"];
    [self sendOp:DLVoiceOpDaveInvalidCommitWelcome data:data thread:t];
    [self countStatistic:@"daveInvalidations"];
    [self daveReinitialize:t];
}

// After a commit or welcome: transition 0 applies at once, others wait for
// Execute Transition after telling the gateway we are ready.
-(void)daveAcceptTransition:(uint16_t)transitionId roster:(NSArray *)roster thread:(DLVoiceThread *)t {
    if (transitionId == 0) {
        [self daveApplyKeyRatchets:t roster:roster];
    } else {
        [t->pendingTransitions setObject:[NSNumber numberWithUnsignedShort:t->daveVersion]
                                  forKey:[NSNumber numberWithUnsignedShort:transitionId]];
        // Prepare decryptors for the new members now so the switch is instant.
        NSEnumerator *enumerator = [roster objectEnumerator];
        NSString *user;
        while (user = [enumerator nextObject]) if (![user isEqualToString:userID]) [self decryptorForUser:user thread:t create:YES];
        NSDictionary *data = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedShort:transitionId] forKey:@"transition_id"];
        [self sendOp:DLVoiceOpDaveTransitionReady data:data thread:t];
    }
}

-(void)handleBinaryMessage:(NSData *)message thread:(DLVoiceThread *)t {
    uint16_t sequence = 0;
    uint8_t op = 0;
    const uint8_t *payload = NULL;
    size_t payloadLength = 0;
    if (!ldv_binary_parse([message bytes], [message length], &sequence, &op, &payload, &payloadLength)) return;
    t->sequenceAck = sequence;
    NSLog(@"Voice: DAVE binary op %u (%lu bytes)", op, (unsigned long)payloadLength);
    if (!t->session) return;
    if (op == DLVoiceOpDaveExternalSender) {
        t->api->sessionSetExternalSender(t->session, payload, payloadLength);
    } else if (op == DLVoiceOpDaveProposals) {
        NSMutableArray *holder = [NSMutableArray array];
        const char **ids = NULL;
        size_t count = 0;
        [self recognisedUsers:t list:&ids count:&count holder:holder];
        uint8_t *commitWelcome = NULL;
        size_t commitWelcomeLength = 0;
        t->api->sessionProcessProposals(t->session, payload, payloadLength, ids, count, &commitWelcome, &commitWelcomeLength);
        free(ids);
        NSLog(@"Voice: DAVE proposals -> commit %lu bytes", (unsigned long)commitWelcomeLength);
        if (commitWelcome && commitWelcomeLength) {
            [self sendBinaryOp:DLVoiceOpDaveCommitWelcome payload:commitWelcome length:commitWelcomeLength thread:t];
        }
        if (commitWelcome) t->api->free(commitWelcome);
    } else if (op == DLVoiceOpDaveAnnounceCommit) {
        uint16_t transitionId = 0;
        const uint8_t *commit = NULL;
        size_t commitLength = 0;
        if (!ldv_transition_payload(payload, payloadLength, &transitionId, &commit, &commitLength)) return;
        DAVECommitResultHandle result = t->api->sessionProcessCommit(t->session, commit, commitLength);
        NSLog(@"Voice: DAVE commit for transition %u: %@", transitionId,
              !result ? @"error" : (t->api->commitIsFailed(result) ? @"failed" : (t->api->commitIsIgnored(result) ? @"ignored" : @"ok")));
        if (!result || t->api->commitIsFailed(result)) {
            if (result) t->api->commitDestroy(result);
            [self daveInvalidate:transitionId thread:t];
            return;
        }
        if (t->api->commitIsIgnored(result)) {
            t->api->commitDestroy(result);
            return;
        }
        uint64_t *ids = NULL;
        size_t count = 0;
        t->api->commitRosterIds(result, &ids, &count);
        NSArray *roster = [self rosterFromIds:ids count:count];
        if (ids) t->api->free(ids);
        t->api->commitDestroy(result);
        [self daveAcceptTransition:transitionId roster:roster thread:t];
    } else if (op == DLVoiceOpDaveWelcome) {
        uint16_t transitionId = 0;
        const uint8_t *welcome = NULL;
        size_t welcomeLength = 0;
        if (!ldv_transition_payload(payload, payloadLength, &transitionId, &welcome, &welcomeLength)) return;
        NSMutableArray *holder = [NSMutableArray array];
        const char **recognised = NULL;
        size_t recognisedCount = 0;
        [self recognisedUsers:t list:&recognised count:&recognisedCount holder:holder];
        DAVEWelcomeResultHandle result = t->api->sessionProcessWelcome(t->session, welcome, welcomeLength, recognised, recognisedCount);
        NSLog(@"Voice: DAVE welcome for transition %u: %@", transitionId, result ? @"ok" : @"failed");
        free(recognised);
        if (!result) {
            [self daveInvalidate:transitionId thread:t];
            return;
        }
        uint64_t *ids = NULL;
        size_t count = 0;
        t->api->welcomeRosterIds(result, &ids, &count);
        NSArray *roster = [self rosterFromIds:ids count:count];
        if (ids) t->api->free(ids);
        t->api->welcomeDestroy(result);
        [self daveAcceptTransition:transitionId roster:roster thread:t];
    }
}

#pragma mark Gateway messages (voice thread)

-(BOOL)openUDP:(DLVoiceThread *)t {
    struct addrinfo hints, *result = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;
    char port[8];
    snprintf(port, sizeof(port), "%u", t->remotePort);
    if (getaddrinfo(t->remoteIP, port, &hints, &result) != 0 || !result) return NO;
    t->udp = socket(result->ai_family, result->ai_socktype, result->ai_protocol);
    BOOL ok = t->udp >= 0 && connect(t->udp, result->ai_addr, result->ai_addrlen) == 0;
    freeaddrinfo(result);
    if (!ok) return NO;
    fcntl(t->udp, F_SETFL, fcntl(t->udp, F_GETFL, 0) | O_NONBLOCK);
    int bufferSize = 256 * 1024;
    setsockopt(t->udp, SOL_SOCKET, SO_RCVBUF, &bufferSize, sizeof(bufferSize));
    return YES;
}

-(void)handleTextMessage:(NSData *)message thread:(DLVoiceThread *)t {
    NSDictionary *packet = [[CJSONDeserializer deserializer] deserializeAsDictionary:message error:nil];
    if (![packet isKindOfClass:[NSDictionary class]]) return;
    int op = [[packet objectForKey:@"op"] intValue];
    id seq = [packet objectForKey:@"seq"];
    if ([seq respondsToSelector:@selector(intValue)]) t->sequenceAck = [seq intValue];
    NSDictionary *d = [[packet objectForKey:@"d"] isKindOfClass:[NSDictionary class]] ? [packet objectForKey:@"d"] : nil;

    if (op != DLVoiceOpHeartbeatAck) NSLog(@"Voice: gateway op %d", op);
    if (op == DLVoiceOpHello) {
        t->heartbeatInterval = [[d objectForKey:@"heartbeat_interval"] doubleValue] / 1000.0;
        if (t->heartbeatInterval <= 0) t->heartbeatInterval = 13.75;
        t->nextHeartbeat = DLNow() + t->heartbeatInterval * 0.5;
        t->lastHeartbeatAck = DLNow();
        if (!t->identified) {
            t->identified = YES;
            NSDictionary *identify = [NSDictionary dictionaryWithObjectsAndKeys:
                                      serverID, @"server_id", userID, @"user_id", sessionID, @"session_id", token, @"token",
                                      [NSNumber numberWithUnsignedShort:t->api->maxProtocolVersion()], @"max_dave_protocol_version", nil];
            [self sendOp:DLVoiceOpIdentify data:identify thread:t];
        }
    } else if (op == DLVoiceOpHeartbeatAck) {
        t->lastHeartbeatAck = DLNow();
    } else if (op == DLVoiceOpReady) {
        t->ssrc = (uint32_t)[[d objectForKey:@"ssrc"] unsignedLongLongValue];
        NSString *ip = [d objectForKey:@"ip"];
        t->remotePort = (uint16_t)[[d objectForKey:@"port"] intValue];
        NSArray *modes = [d objectForKey:@"modes"];
        if (![modes containsObject:[NSString stringWithUTF8String:DLVoiceEncryptionMode]]) {
            [self setStatistic:@"error" value:@"The voice server offered no supported encryption mode."];
            OSAtomicCompareAndSwap32Barrier(1, 0, &running);
            return;
        }
        strlcpy(t->remoteIP, [ip UTF8String], sizeof(t->remoteIP));
        if (![self openUDP:t]) {
            [self setStatistic:@"error" value:@"Could not open the voice UDP socket."];
            OSAtomicCompareAndSwap32Barrier(1, 0, &running);
            return;
        }
        [self notifyState:DLVoiceConnectionStateNegotiating reason:nil];
        t->nextDiscovery = DLNow();
    } else if (op == DLVoiceOpSessionDescription) {
        NSArray *key = [d objectForKey:@"secret_key"];
        if ([key count] != 32) return;
        NSUInteger index;
        for (index = 0; index < 32; index++) t->secretKey[index] = (uint8_t)[[key objectAtIndex:index] intValue];
        t->haveKey = YES;
        t->daveVersion = (uint16_t)[[d objectForKey:@"dave_protocol_version"] intValue];
        [self setStatistic:@"daveVersion" value:[NSNumber numberWithUnsignedShort:t->daveVersion]];
        t->api->encryptorAssignSsrc(t->encryptor, t->ssrc, DAVE_CODEC_OPUS);
        [self daveReinitialize:t];
        t->nextKeepAlive = DLNow();
        [self notifyState:DLVoiceConnectionStateConnected reason:nil];
    } else if (op == DLVoiceOpSpeaking) {
        NSString *user = [[d objectForKey:@"user_id"] description];
        id ssrcValue = [d objectForKey:@"ssrc"];
        if (user && [ssrcValue respondsToSelector:@selector(unsignedLongLongValue)]) {
            [t->ssrcUsers setObject:user forKey:[NSNumber numberWithUnsignedLongLong:[ssrcValue unsignedLongLongValue]]];
            if (![user isEqualToString:userID]) [t->connectedUsers addObject:user];
            BOOL speaking = [[d objectForKey:@"speaking"] intValue] != 0;
            [self performSelectorOnMainThread:@selector(deliverSpeaking:)
                                   withObject:[NSArray arrayWithObjects:user, [NSNumber numberWithBool:speaking], nil]
                                waitUntilDone:NO];
        }
    } else if (op == DLVoiceOpClientsConnect) {
        NSEnumerator *enumerator = [[d objectForKey:@"user_ids"] objectEnumerator];
        id user;
        while (user = [enumerator nextObject]) [t->connectedUsers addObject:[user description]];
    } else if (op == DLVoiceOpClientDisconnect) {
        NSString *user = [[d objectForKey:@"user_id"] description];
        if (user) {
            [t->connectedUsers removeObject:user];
            NSValue *value = [t->decryptors objectForKey:user];
            if (value) {
                t->api->decryptorDestroy((DAVEDecryptorHandle)[value pointerValue]);
                [t->decryptors removeObjectForKey:user];
            }
        }
    } else if (op == DLVoiceOpDavePrepareTransition) {
        uint16_t transitionId = (uint16_t)[[d objectForKey:@"transition_id"] intValue];
        uint16_t version = (uint16_t)[[d objectForKey:@"protocol_version"] intValue];
        [t->pendingTransitions setObject:[NSNumber numberWithUnsignedShort:version] forKey:[NSNumber numberWithUnsignedShort:transitionId]];
        if (transitionId == 0) {
            [self daveExecuteTransition:0 thread:t];
        } else {
            NSDictionary *data = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedShort:transitionId] forKey:@"transition_id"];
            [self sendOp:DLVoiceOpDaveTransitionReady data:data thread:t];
        }
    } else if (op == DLVoiceOpDaveExecuteTransition) {
        [self daveExecuteTransition:(uint16_t)[[d objectForKey:@"transition_id"] intValue] thread:t];
    } else if (op == DLVoiceOpDavePrepareEpoch) {
        if ([[d objectForKey:@"epoch"] intValue] == 1) {
            t->daveVersion = (uint16_t)[[d objectForKey:@"protocol_version"] intValue];
            [self daveReinitialize:t];
        }
    }
}

#pragma mark Media (voice thread)

-(void)handleDatagram:(const uint8_t *)packet length:(size_t)length thread:(DLVoiceThread *)t {
    if (!t->discoveryDone) {
        char address[65];
        uint16_t port = 0;
        if (ldv_discovery_parse(packet, length, address, &port)) {
            t->discoveryDone = YES;
            NSLog(@"Voice: UDP discovery ok (port %u)", port);
            NSDictionary *data = [NSDictionary dictionaryWithObjectsAndKeys:
                                  [NSString stringWithUTF8String:address], @"address",
                                  [NSNumber numberWithUnsignedShort:port], @"port",
                                  [NSString stringWithUTF8String:DLVoiceEncryptionMode], @"mode", nil];
            NSDictionary *select = [NSDictionary dictionaryWithObjectsAndKeys:@"udp", @"protocol", data, @"data", nil];
            [self sendOp:DLVoiceOpSelectProtocol data:select thread:t];
        }
        return;
    }
    if (!t->haveKey) return;
    ldv_rtp_header header;
    if (!ldv_rtp_parse(packet, length, &header)) return;
    [self countStatistic:@"packetsReceived"];
    uint8_t plain[2048];
    size_t plainLength = t->api->transportOpen(t->secretKey, packet, length, header.aadLength, plain, sizeof(plain));
    if (!plainLength || plainLength < header.extensionBodyLength) {
        [self countStatistic:@"transportFailures"];
        return;
    }
    const uint8_t *opus = plain + header.extensionBodyLength;
    size_t opusLength = plainLength - header.extensionBodyLength;
    NSString *user = [t->ssrcUsers objectForKey:[NSNumber numberWithUnsignedInt:header.ssrc]];
    if (!user) {
        [self countStatistic:@"unknownSSRC"];
        return;
    }
    NSData *frame = nil;
    if (opusLength == 3 && memcmp(opus, ldv_opus_silence, 3) == 0) {
        frame = [NSData dataWithBytes:opus length:opusLength];
    } else {
        DAVEDecryptorHandle decryptor = [self decryptorForUser:user thread:t create:t->daveVersion == 0];
        if (!decryptor) {
            [self countStatistic:@"daveNoDecryptor"];
            return;
        }
        uint8_t decrypted[2048];
        size_t written = 0;
        DAVEDecryptorResultCode code = t->api->decrypt(decryptor, DAVE_MEDIA_TYPE_AUDIO, opus, opusLength,
                                                       decrypted, sizeof(decrypted), &written);
        if (code != DAVE_DECRYPTOR_RESULT_CODE_SUCCESS) {
            [self countStatistic:@"daveDecryptFailures"];
            return;
        }
        frame = [NSData dataWithBytes:decrypted length:written];
    }
    [self countStatistic:@"framesDecoded"];
    [self performSelectorOnMainThread:@selector(deliverFrame:)
                           withObject:[NSArray arrayWithObjects:frame, user, [NSNumber numberWithUnsignedShort:header.sequence], nil]
                        waitUntilDone:NO];
}

-(void)setSpeaking:(BOOL)speaking thread:(DLVoiceThread *)t {
    if (t->speaking == speaking) return;
    t->speaking = speaking;
    NSDictionary *data = [NSDictionary dictionaryWithObjectsAndKeys:
                          [NSNumber numberWithInt:speaking ? 1 : 0], @"speaking",
                          [NSNumber numberWithInt:0], @"delay",
                          [NSNumber numberWithUnsignedInt:t->ssrc], @"ssrc", nil];
    [self sendOp:DLVoiceOpSpeaking data:data thread:t];
}

-(void)sendFrame:(NSData *)frame thread:(DLVoiceThread *)t {
    uint8_t encrypted[2048];
    size_t encryptedLength = 0;
    const uint8_t *media = [frame bytes];
    size_t mediaLength = [frame length];
    BOOL silence = mediaLength == 3 && memcmp(media, ldv_opus_silence, 3) == 0;
    if (t->daveVersion > 0 && !silence) {
        if (t->api->encrypt(t->encryptor, DAVE_MEDIA_TYPE_AUDIO, t->ssrc, media, mediaLength,
                            encrypted, sizeof(encrypted), &encryptedLength) != DAVE_ENCRYPTOR_RESULT_CODE_SUCCESS) {
            [self countStatistic:@"daveEncryptFailures"];
            return;
        }
        media = encrypted;
        mediaLength = encryptedLength;
    }
    uint8_t header[12];
    t->sendSequence++;
    t->sendTimestamp += 960;
    t->sendNonce++;
    ldv_rtp_write(t->sendSequence, t->sendTimestamp, t->ssrc, header);
    uint8_t packet[2200];
    size_t packetLength = t->api->transportSeal(t->secretKey, t->sendNonce, header, sizeof(header),
                                                media, mediaLength, packet, sizeof(packet));
    if (packetLength && send(t->udp, packet, packetLength, 0) > 0) [self countStatistic:@"packetsSent"];
}

#pragma mark Thread

-(void)runVoiceThread {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    DLVoiceThread state;
    DLVoiceThread *t = &state;
    memset(t, 0, sizeof(state));
    t->udp = -1;
    t->sequenceAck = -1;
    t->sendSequence = (uint16_t)arc4random();
    t->sendTimestamp = arc4random();
    t->decryptors = [[NSMutableDictionary alloc] init];
    t->ssrcUsers = [[NSMutableDictionary alloc] init];
    t->connectedUsers = [[NSMutableSet alloc] init];
    t->pendingTransitions = [[NSMutableDictionary alloc] init];
    NSString *closeReason = nil;

    t->api = [DLVoiceLibrary api];
    if (!t->api) {
        closeReason = [DLVoiceLibrary unavailableReason];
        goto finished;
    }
    t->encryptor = t->api->encryptorCreate();
    t->api->encryptorSetPassthrough(t->encryptor, true);
    [self notifyState:DLVoiceConnectionStateConnecting reason:nil];

    t->ws = curl_easy_init();
    if (!t->ws) { closeReason = @"Could not start the voice connection."; goto finished; }
    NSString *url = [NSString stringWithFormat:@"wss://%@/?v=8", endpoint];
    curl_easy_setopt(t->ws, CURLOPT_URL, [url UTF8String]);
    curl_easy_setopt(t->ws, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(t->ws, CURLOPT_SSL_VERIFYHOST, 2L);
    if ([DLUtil effectiveCAPath]) curl_easy_setopt(t->ws, CURLOPT_CAINFO, [[DLUtil effectiveCAPath] fileSystemRepresentation]);
    curl_easy_setopt(t->ws, CURLOPT_USERAGENT, [[DLUtil userAgentString] UTF8String]);
    [DLUtil applySystemProxyToCurlHandle:t->ws url:url];
    curl_easy_setopt(t->ws, CURLOPT_CONNECT_ONLY, 2L);
    curl_easy_setopt(t->ws, CURLOPT_CONNECTTIMEOUT, 15L);
    CURLcode connectResult = curl_easy_perform(t->ws);
    if (connectResult != CURLE_OK) {
        closeReason = [NSString stringWithFormat:@"Voice server connection failed (%s).", curl_easy_strerror(connectResult)];
        goto finished;
    }

    {
        NSMutableData *message = [[NSMutableData alloc] init];
        char buffer[16384];
        double started = DLNow();
        while (running) {
            NSAutoreleasePool *loopPool = [[NSAutoreleasePool alloc] init];
            double now = DLNow();
            if (!t->haveKey && now - started > 20.0) {
                [self setStatistic:@"error" value:@"The voice server did not finish the handshake."];
                [loopPool release];
                break;
            }
            if (t->heartbeatInterval > 0 && now >= t->nextHeartbeat) {
                if (now - t->lastHeartbeatAck > t->heartbeatInterval * 2.5) {
                    [self setStatistic:@"error" value:@"The voice server stopped answering heartbeats."];
                    [loopPool release];
                    break;
                }
                [self sendHeartbeat:t];
                t->nextHeartbeat = now + t->heartbeatInterval;
            }
            if (t->udp >= 0 && !t->discoveryDone && now >= t->nextDiscovery) {
                if (t->discoveryAttempts++ >= 5) {
                    [self setStatistic:@"error" value:@"UDP discovery got no answer (firewall?)."];
                    [loopPool release];
                    break;
                }
                uint8_t request[LDV_DISCOVERY_LENGTH];
                ldv_discovery_request(t->ssrc, request);
                send(t->udp, request, sizeof(request), 0);
                t->nextDiscovery = now + 1.0;
            }
            if (t->haveKey && now >= t->nextKeepAlive) {
                uint8_t keepAlive[8] = {0};
                memcpy(keepAlive, &t->keepAliveCounter, 4);
                t->keepAliveCounter++;
                send(t->udp, keepAlive, sizeof(keepAlive), 0);
                t->nextKeepAlive = now + 5.0;
            }
            if (t->haveKey) {
                NSArray *frames = nil;
                @synchronized(outgoingFrames) {
                    if ([outgoingFrames count]) {
                        frames = [[outgoingFrames copy] autorelease];
                        [outgoingFrames removeAllObjects];
                    }
                }
                if ([frames count]) {
                    [self setSpeaking:YES thread:t];
                    NSEnumerator *enumerator = [frames objectEnumerator];
                    NSData *frame;
                    while (frame = [enumerator nextObject]) [self sendFrame:frame thread:t];
                }
            }

            curl_socket_t wsSocket = CURL_SOCKET_BAD;
            curl_easy_getinfo(t->ws, CURLINFO_ACTIVESOCKET, &wsSocket);
            if (wsSocket == CURL_SOCKET_BAD) {
                [self setStatistic:@"error" value:@"The voice server closed the connection."];
                [loopPool release];
                break;
            }
            fd_set readSet;
            FD_ZERO(&readSet);
            FD_SET(wsSocket, &readSet);
            int maxSocket = wsSocket;
            if (t->udp >= 0) {
                FD_SET(t->udp, &readSet);
                if (t->udp > maxSocket) maxSocket = t->udp;
            }
            struct timeval timeout = { 0, 10000 };
            select(maxSocket + 1, &readSet, NULL, NULL, &timeout);

            BOOL closed = NO;
            for (;;) {
                size_t received = 0;
                const struct curl_ws_frame *meta = NULL;
                CURLcode result = curl_ws_recv(t->ws, buffer, sizeof(buffer), &received, &meta);
                if (result == CURLE_AGAIN) break;
                if (result != CURLE_OK || (meta && (meta->flags & CURLWS_CLOSE))) {
                    if (meta && (meta->flags & CURLWS_CLOSE) && received >= 2) {
                        int code = ((unsigned char)buffer[0] << 8) | (unsigned char)buffer[1];
                        [self setStatistic:@"closeCode" value:[NSNumber numberWithInt:code]];
                        [self setStatistic:@"error" value:[NSString stringWithFormat:@"The voice server closed the connection (%d).", code]];
                    } else {
                        [self setStatistic:@"error" value:@"The voice connection was lost."];
                    }
                    closed = YES;
                    break;
                }
                if (received) [message appendBytes:buffer length:received];
                if (meta && meta->bytesleft == 0 && !(meta->flags & CURLWS_CONT) && [message length]) {
                    if (meta->flags & CURLWS_BINARY) [self handleBinaryMessage:message thread:t];
                    else [self handleTextMessage:message thread:t];
                    [message setLength:0];
                }
            }
            if (t->udp >= 0) {
                uint8_t datagram[2048];
                ssize_t length;
                while ((length = recv(t->udp, datagram, sizeof(datagram), 0)) > 0) {
                    [self handleDatagram:datagram length:(size_t)length thread:t];
                }
            }
            [loopPool release];
            if (closed) break;
        }
        [message release];
        if (t->speaking && t->ws) {
            // Five silence frames close the talk spurt cleanly.
            int index;
            for (index = 0; index < 5; index++) [self sendFrame:[NSData dataWithBytes:ldv_opus_silence length:3] thread:t];
            [self setSpeaking:NO thread:t];
        }
    }

finished:
    if (t->ws) curl_easy_cleanup(t->ws);
    if (t->udp >= 0) close(t->udp);
    if (t->api) {
        NSEnumerator *enumerator = [t->decryptors objectEnumerator];
        NSValue *value;
        while (value = [enumerator nextObject]) t->api->decryptorDestroy((DAVEDecryptorHandle)[value pointerValue]);
        if (t->encryptor) t->api->encryptorDestroy(t->encryptor);
        if (t->session) t->api->sessionDestroy(t->session);
    }
    [t->decryptors release];
    [t->ssrcUsers release];
    [t->connectedUsers release];
    [t->pendingTransitions release];
    if (!closeReason) closeReason = [[self statistics] objectForKey:@"error"];
    running = 0;
    [self notifyState:DLVoiceConnectionStateClosed reason:closeReason];
    [pool release];
    [self release];
}

-(void)dealloc {
    [endpoint release];
    [token release];
    [sessionID release];
    [serverID release];
    [userID release];
    [channelID release];
    [outgoingFrames release];
    [statistics release];
    [super dealloc];
}

@end
