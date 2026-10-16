//
//  DLWSController.h
//  Discord Lite
//
//  Created by Collin Mistr on 11/4/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DLChannel.h"
#import "DLUserSettings.h"
#import "CJSONDeserializer.h"
#import "CJSONSerializer.h"
#import "DLServer.h"
#import "DLPreferencesHandler.h"

#include "curl_headers/curl.h"


#define WS_GATEWAY_URL "wss://gateway.discord.gg/?encoding=json&v=10"

#define kWSOperation "op"
#define kWSData "d"
#define kWSSequence "s"
#define kWSType "t"

// Voice events, posted on the main thread with the event data as userInfo.
#define DLVoiceStateUpdateNotification @"DLVoiceStateUpdateNotification"
#define DLVoiceServerUpdateNotification @"DLVoiceServerUpdateNotification"

typedef enum {
    OPCodeGeneral = 0,
    OPCodeHeartbeat = 1,
    OPCodeIdentify = 2,
    OPCodeVoiceStateUpdate = 4,
    OPCodeResume = 6,
    OPCodeReconnect = 7,
    OPCodeQueryServerMembers = 8,
    OPCodeInvalidSession = 9,
    OPCodeHello = 10,
    OPCodeHeartbeatAck = 11,
    OPCodeDMParticipantOp = 13,
    OPCodeServerMemberOp = 14
} OPCode;

typedef enum {
    DLWSConnectionStateDisconnected = 0,
    DLWSConnectionStateConnecting = 1,
    DLWSConnectionStateConnected = 2,
    DLWSConnectionStateReconnecting = 3
} DLWSConnectionState;

@protocol DLWSControllerDelegate <NSObject>
@optional
-(void)wsDidReceiveMessage:(DLMessage *)m;
-(void)wsDidReceivePrivateChannelData:(NSArray *)data;
-(void)wsDidReceiveServerData:(NSArray *)data;
-(void)wsDidReceiveReadStateData:(NSArray *)data;
-(void)wsDidReceiveUserData:(NSDictionary *)data;
@optional
// Friends, blocked users and pending requests, with friends' presences.
-(void)wsDidReceiveRelationships:(NSArray *)relationships presences:(NSArray *)presences;
-(void)wsUserWithID:(NSString *)userID didUpdatePresenceStatus:(NSString *)status;
// Per-server notification settings (mutes); a READY list or one updated entry.
-(void)wsDidReceiveUserGuildSettings:(id)settings replacingAll:(BOOL)replacingAll;
@required
-(void)wsDidReceiveUserSettingsData:(NSDictionary *)data;
-(void)wsDidLoadAllDataAfterReconnection:(BOOL)didReconnect;
-(void)wsDidAcknowledgeMessage:(DLMessage *)m;
-(void)wsUserWithID:(NSString *)userID didStartTypingInServerWithID:(NSString *)serverID inChannelWithID:(NSString *)channelID withMemberData:(NSDictionary *)memberData;
-(void)wsUserWithID:(NSString *)userID didStartTypingInDirectMessageChannelWithID:(NSString *)channelID;
-(void)wsDidReceiveMemberData:(NSArray *)memberData forServerWithID:(NSString *)serverID;
-(void)wsMessageWithID:(NSString *)messageID wasUpdatedWithData:(NSDictionary *)data;
-(void)wsMessageWithID:(NSString *)messageID reactionEmoji:(NSDictionary *)emoji wasAdded:(BOOL)added byUserID:(NSString *)userID;
-(void)wsMessageWithIDWasDeleted:(NSString *)messageID;
-(void)wsDidReceiveThreads:(NSArray *)threads forServerWithID:(NSString *)serverID;
-(void)wsDidDeleteThreadWithID:(NSString *)threadID forServerWithID:(NSString *)serverID;
-(void)wsConnectionStateDidChange:(DLWSConnectionState)state;
@end

@interface DLWSController : NSObject {
    // Owned by the WebSocket thread only. libcurl handles are not
    // thread-safe; other threads queue frames in outgoingFrames instead.
    CURL *curlWebSocketHandle;
    NSMutableArray *outgoingFrames;
    NSLock *connectionLock;
    volatile int32_t connectionGeneration;
    NSString *token;
    NSString *sessionID;
    NSTimer *heartbeatTimer;
    NSTimer *reachabilityTimer;
    int heartbeatInterval;
    id<DLWSControllerDelegate> delegate;
    BOOL heartbeatResponseReceived;
    BOOL shouldResume;
    int sequenceNumber;
    BOOL didReconnect;
    BOOL didResume;
    BOOL reconnectScheduled;
    DLWSConnectionState connectionState;
}

+(DLWSController *)sharedInstance;
-(void)setDelegate:(id<DLWSControllerDelegate>)inDelegate;

-(void)startWithAuthToken:(NSString *)inToken;
-(void)stop;

-(void)updateWSForDirectMessageChannel:(DLChannel *)c;
-(void)updateWSForChannel:(DLChannel *)c inServer:(DLServer *)s;

// Gateway opcode 4: join (channelID set) or leave (nil) a voice channel.
// guildID is nil for DM and group calls.
-(void)sendVoiceStateUpdateForGuildID:(NSString *)guildID channelID:(NSString *)channelID
                             selfMute:(BOOL)selfMute selfDeaf:(BOOL)selfDeaf;
-(void)queryServer:(DLServer *)s forMembersContainingUsername:(NSString *)username;
-(void)requestMembersForChannel:(DLChannel *)c inServer:(DLServer *)s from:(NSInteger)start to:(NSInteger)end;


//For libcurl callback

-(void)wsTextDataReceived:(NSData *)textData;

@end
