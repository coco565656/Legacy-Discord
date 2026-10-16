//
//  DLVoiceManager.m
//  Legacy Discord
//

#import "DLVoiceManager.h"
#import "DLVoiceLibrary.h"
#import "DLWSController.h"
#import "DLController.h"
#import "DLChannel.h"
#import "DLServerChannel.h"

static DLVoiceManager *sharedVoiceManager = nil;

@interface DLVoiceManager ()
-(void)startConnectionIfReady;
-(void)postChange;
@end

@implementation DLVoiceManager

+(DLVoiceManager *)sharedManager {
    if (!sharedVoiceManager) sharedVoiceManager = [[DLVoiceManager alloc] init];
    return sharedVoiceManager;
}

+(BOOL)isAvailable {
    return [DLVoiceLibrary api] != NULL;
}

-(id)init {
    self = [super init];
    if (self) {
        voiceStates = [[NSMutableDictionary alloc] init];
        speakingUsers = [[NSMutableSet alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(voiceStateUpdate:)
                                                     name:DLVoiceStateUpdateNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(voiceServerUpdate:)
                                                     name:DLVoiceServerUpdateNotification object:nil];
    }
    return self;
}

-(NSString *)myUserID {
    return [[[[DLController sharedInstance] myUser] userID] description];
}

-(void)postChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:DLVoiceManagerDidChangeNotification object:self];
}

-(void)setState:(DLVoiceState)newState {
    if (state == newState) return;
    state = newState;
    [self postChange];
}

#pragma mark Public

-(void)joinChannel:(DLChannel *)inChannel {
    if (!inChannel || ![DLVoiceManager isAvailable]) return;
    if (connection || state != DLVoiceStateIdle) [self disconnect];
    [channel release];
    channel = [inChannel retain];
    [guildID release];
    NSString *server = [inChannel isKindOfClass:[DLServerChannel class]] ? [[(DLServerChannel *)inChannel serverID] description] : nil;
    guildID = [server copy];
    [voiceSessionID release];
    voiceSessionID = nil;
    [serverInfo release];
    serverInfo = nil;
    [lastError release];
    lastError = nil;
    endToEndEncrypted = NO;
    [self setState:DLVoiceStateRequesting];
    NSLog(@"Voice: joining channel %@ (guild %@)", [inChannel channelID], guildID ? guildID : @"none");
    [[DLWSController sharedInstance] sendVoiceStateUpdateForGuildID:guildID channelID:[[inChannel channelID] description]
                                                           selfMute:selfMute selfDeaf:selfDeaf];
}

-(void)disconnect {
    if (state == DLVoiceStateIdle && !connection) return;
    [[DLWSController sharedInstance] sendVoiceStateUpdateForGuildID:guildID channelID:nil selfMute:selfMute selfDeaf:selfDeaf];
    [connection setDelegate:nil];
    [connection stop];
    [connection release];
    connection = nil;
    [statisticsTimer invalidate];
    statisticsTimer = nil;
    [channel release];
    channel = nil;
    [speakingUsers removeAllObjects];
    endToEndEncrypted = NO;
    state = DLVoiceStateIdle;
    [self postChange];
}

-(void)setSelfMute:(BOOL)mute deaf:(BOOL)deaf {
    selfMute = mute || deaf;
    selfDeaf = deaf;
    if (channel) {
        [[DLWSController sharedInstance] sendVoiceStateUpdateForGuildID:guildID channelID:[[channel channelID] description]
                                                               selfMute:selfMute selfDeaf:selfDeaf];
    }
    [self postChange];
}

-(DLVoiceState)state { return state; }
-(DLChannel *)channel { return channel; }
-(BOOL)selfMute { return selfMute; }
-(BOOL)selfDeaf { return selfDeaf; }
-(BOOL)isEndToEndEncrypted { return endToEndEncrypted; }
-(NSString *)lastError { return lastError; }
-(DLVoiceConnection *)connection { return connection; }
-(BOOL)isUserSpeaking:(NSString *)userID { return [speakingUsers containsObject:[userID description]]; }

-(NSArray *)userIDsInChannelID:(NSString *)channelID {
    NSMutableArray *users = [NSMutableArray array];
    NSEnumerator *enumerator = [voiceStates keyEnumerator];
    NSString *user;
    while (user = [enumerator nextObject]) {
        if ([[[[voiceStates objectForKey:user] objectForKey:@"channel_id"] description] isEqualToString:[channelID description]]) {
            [users addObject:user];
        }
    }
    return users;
}

#pragma mark Gateway events

-(void)voiceStateUpdate:(NSNotification *)notification {
    NSDictionary *data = [notification userInfo];
    NSString *user = [[data objectForKey:@"user_id"] description];
    if (!user) return;
    id channelValue = [data objectForKey:@"channel_id"];
    if ([channelValue isKindOfClass:[NSString class]]) [voiceStates setObject:data forKey:user];
    else [voiceStates removeObjectForKey:user];

    if ([user isEqualToString:[self myUserID]]) {
        NSLog(@"Voice: own voice state channel=%@ session=%@", channelValue, [data objectForKey:@"session_id"] ? @"yes" : @"no");
    }
    if ([user isEqualToString:[self myUserID]] && state != DLVoiceStateIdle) {
        if (![channelValue isKindOfClass:[NSString class]]) {
            // Moved out or disconnected by the server or another client.
            if (state == DLVoiceStateConnected || state == DLVoiceStateConnecting) {
                [connection setDelegate:nil];
                [connection stop];
                [connection release];
                connection = nil;
                [channel release];
                channel = nil;
                state = DLVoiceStateIdle;
            }
        } else if ([channelValue isEqualToString:[[channel channelID] description]]) {
            [voiceSessionID release];
            voiceSessionID = [[[data objectForKey:@"session_id"] description] copy];
            [self startConnectionIfReady];
        }
    }
    [self postChange];
}

-(void)voiceServerUpdate:(NSNotification *)notification {
    NSLog(@"Voice: VOICE_SERVER_UPDATE received in state %d", state);
    if (state != DLVoiceStateRequesting && state != DLVoiceStateConnecting) return;
    NSDictionary *data = [notification userInfo];
    id endpoint = [data objectForKey:@"endpoint"];
    NSLog(@"Voice: server update endpoint=%@", endpoint);
    if (![endpoint isKindOfClass:[NSString class]]) return; // server being allocated; another update follows
    [serverInfo release];
    serverInfo = [data copy];
    [self startConnectionIfReady];
}

-(void)startConnectionIfReady {
    if (!voiceSessionID || !serverInfo || !channel) return;
    NSString *server = guildID ? guildID : [[serverInfo objectForKey:@"channel_id"] description];
    if (!server) server = [[channel channelID] description];
    [connection setDelegate:nil];
    [connection stop];
    [connection release];
    connection = [[DLVoiceConnection alloc] initWithEndpoint:[serverInfo objectForKey:@"endpoint"]
                                                       token:[[serverInfo objectForKey:@"token"] description]
                                                   sessionID:voiceSessionID
                                                    serverID:server
                                                      userID:[self myUserID]
                                                   channelID:[[channel channelID] description]];
    [connection setDelegate:self];
    [serverInfo release];
    serverInfo = nil;
    [self setState:DLVoiceStateConnecting];
    [connection start];
    [statisticsTimer invalidate];
    statisticsTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(logStatistics:)
                                                     userInfo:nil repeats:YES];
}

-(void)logStatistics:(NSTimer *)timer {
    if (connection) NSLog(@"Voice statistics: %@", [connection statistics]);
}

#pragma mark DLVoiceConnectionDelegate

-(void)voiceConnection:(DLVoiceConnection *)inConnection didChangeState:(DLVoiceConnectionState)connectionState
                reason:(NSString *)reason {
    if (inConnection != connection) return;
    NSLog(@"Voice: connection state %d", connectionState);
    if (connectionState == DLVoiceConnectionStateConnected) {
        [self setState:DLVoiceStateConnected];
    } else if (connectionState == DLVoiceConnectionStateClosed) {
        NSLog(@"Voice connection closed: %@ %@", reason ? reason : @"", [connection statistics]);
        [lastError release];
        lastError = [reason copy];
        [self disconnect];
    }
}

-(void)voiceConnection:(DLVoiceConnection *)inConnection userID:(NSString *)userID didSpeak:(BOOL)speaking {
    if (speaking) [speakingUsers addObject:userID];
    else [speakingUsers removeObject:userID];
    [self postChange];
}

-(void)voiceConnection:(DLVoiceConnection *)inConnection endToEndEncryptionDidChange:(BOOL)active {
    endToEndEncrypted = active;
    NSLog(@"Voice: end-to-end encryption %@", active ? @"active" : @"inactive");
    [self postChange];
}

@end
