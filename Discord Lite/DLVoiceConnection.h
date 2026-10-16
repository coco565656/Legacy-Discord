//
//  DLVoiceConnection.h
//  Legacy Discord
//
//  One voice session: the voice WebSocket (gateway v8), the UDP media socket
//  and DAVE end-to-end encryption, all on a dedicated thread. Callbacks are
//  delivered on the main thread.
//

#import <Foundation/Foundation.h>

typedef enum {
    DLVoiceConnectionStateConnecting = 0,   // WebSocket handshake and identify
    DLVoiceConnectionStateNegotiating = 1,  // UDP discovery and session keys
    DLVoiceConnectionStateConnected = 2,    // media flows (DAVE may still be setting up)
    DLVoiceConnectionStateClosed = 3
} DLVoiceConnectionState;

@class DLVoiceConnection;

@protocol DLVoiceConnectionDelegate <NSObject>
-(void)voiceConnection:(DLVoiceConnection *)connection didChangeState:(DLVoiceConnectionState)state
                reason:(NSString *)reason;
@optional
// An Opus frame from userID, already decrypted (transport and DAVE).
-(void)voiceConnection:(DLVoiceConnection *)connection didReceiveOpusFrame:(NSData *)frame
            fromUserID:(NSString *)userID sequence:(uint16_t)sequence;
-(void)voiceConnection:(DLVoiceConnection *)connection userID:(NSString *)userID didSpeak:(BOOL)speaking;
// DAVE: YES once media is end-to-end encrypted with the current group.
-(void)voiceConnection:(DLVoiceConnection *)connection endToEndEncryptionDidChange:(BOOL)active;
@end

@interface DLVoiceConnection : NSObject {
    id<DLVoiceConnectionDelegate> delegate;
    NSString *endpoint;
    NSString *token;
    NSString *sessionID;
    NSString *serverID;
    NSString *userID;
    NSString *channelID;
    volatile int32_t running;
    NSMutableArray *outgoingFrames;   // NSData Opus frames from the capture side
    NSMutableDictionary *statistics;
}

-(id)initWithEndpoint:(NSString *)endpoint token:(NSString *)token sessionID:(NSString *)sessionID
             serverID:(NSString *)serverID userID:(NSString *)userID channelID:(NSString *)channelID;
-(void)setDelegate:(id<DLVoiceConnectionDelegate>)delegate;
-(void)start;
// Closes the connection; the delegate then gets DLVoiceConnectionStateClosed.
-(void)stop;
// Queues a 20 ms Opus frame for sending (phase 6, capture).
-(void)sendOpusFrame:(NSData *)frame;
// Counters for diagnostics: packets, decrypt failures, DAVE state.
-(NSDictionary *)statistics;

@end
