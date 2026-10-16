//
//  DLVoiceManager.h
//  Legacy Discord
//
//  Joining and leaving voice: sends Gateway opcode 4, waits for this
//  session's VOICE_STATE_UPDATE and the VOICE_SERVER_UPDATE, then runs a
//  DLVoiceConnection. Main thread only.
//

#import <Foundation/Foundation.h>
#import "DLVoiceConnection.h"

@class DLChannel;

typedef enum {
    DLVoiceStateIdle = 0,
    DLVoiceStateRequesting = 1,    // op 4 sent, waiting for the gateway
    DLVoiceStateConnecting = 2,    // voice server handshake
    DLVoiceStateConnected = 3
} DLVoiceState;

// Posted on the main thread whenever state, channel, encryption or the set
// of users in voice channels changes.
#define DLVoiceManagerDidChangeNotification @"DLVoiceManagerDidChangeNotification"

@interface DLVoiceManager : NSObject <DLVoiceConnectionDelegate> {
    DLVoiceState state;
    DLChannel *channel;
    NSString *guildID;
    NSString *voiceSessionID;
    NSDictionary *serverInfo;
    DLVoiceConnection *connection;
    BOOL selfMute;
    BOOL selfDeaf;
    BOOL endToEndEncrypted;
    NSString *lastError;
    NSMutableDictionary *voiceStates;   // user id -> VOICE_STATE_UPDATE data
    NSMutableSet *speakingUsers;
    NSTimer *statisticsTimer;
}

+(DLVoiceManager *)sharedManager;
// YES on OS X 10.8+ with the voice library present.
+(BOOL)isAvailable;

-(void)joinChannel:(DLChannel *)channel;
-(void)disconnect;
-(void)setSelfMute:(BOOL)mute deaf:(BOOL)deaf;

-(DLVoiceState)state;
-(DLChannel *)channel;
-(BOOL)selfMute;
-(BOOL)selfDeaf;
-(BOOL)isEndToEndEncrypted;
-(NSString *)lastError;
-(BOOL)isUserSpeaking:(NSString *)userID;
// User ids currently in the given voice channel (from voice states).
-(NSArray *)userIDsInChannelID:(NSString *)channelID;
-(DLVoiceConnection *)connection;

@end
