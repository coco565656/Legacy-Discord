//
//  DLController.h
//  Discord Lite
//
//  Created by Collin Mistr on 10/25/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AsyncHTTPPostRequest.h"
#import "AsyncHTTPGetRequest.h"
#import "DLError.h"
#import "DLServer.h"
#import "DLServerChannel.h"
#import "DLMessage.h"
#import "DLDirectMessageChannel.h"
#import "DLWSController.h"

#define API_ROOT "https://discord.com/api/v10"
// Posted on the main thread after newly received members are stored in their
// DLServer. The object is the DLServer.
#define DLServerMembersDidUpdateNotification @"DLServerMembersDidUpdateNotification"
// Posted on the main thread when server/channel mute settings change.
#define DLNotificationSettingsDidChangeNotification @"DLNotificationSettingsDidChangeNotification"
// Posted (object: the thread) when a forum post's opening message loaded.
#define DLThreadStarterDidLoadNotification @"DLThreadStarterDidLoadNotification"
// Posted after creating a forum post: userInfo {thread} on success or {error}.
#define DLForumPostCreationDidFinishNotification @"DLForumPostCreationDidFinishNotification"
// Posted when a 1:1 DM is ready to open: userInfo {channel, draft}.
#define DLDirectMessageChannelReadyNotification @"DLDirectMessageChannelReadyNotification"

#define kDefaultsToken "token"

typedef enum {
    RequestIDLogin = 0,
    RequestIDMessages = 1,
    RequestIDSendMessage = 2,
    RequestIDAckMessage = 3,
    RequestIDLogout = 4,
    RequestIDTyping = 5,
    RequestIDTwoFactor = 6,
    RequestIDMessageEdit = 7,
    RequestIDMessageDelete = 8,
    RequestIDGetFingerprint = 9,
    RequestIDAddReaction = 10,
    RequestIDRemoveReaction = 11,
    RequestIDSearchMessages = 12,
    RequestIDMessagesAround = 13,
    RequestIDMessagesNewer = 14,
    RequestIDActiveThreads = 15,
    RequestIDArchivedThreads = 16,
    RequestIDUserProfile = 17,
    RequestIDChannelPins = 18,
    RequestIDUserNoteLoad = 19,
    RequestIDUserNoteSave = 20,
    RequestIDMyGuildMember = 21,
    RequestIDNotificationSettings = 22,
    RequestIDForumStarter = 23,
    RequestIDCreateForumPost = 24,
    RequestIDDeleteThread = 25,
    RequestIDOpenDirectMessage = 26,
    RequestIDGeneric = 27
} RequestID;

@protocol DLLoginDelegate <NSObject>
@optional
-(void)didLoginWithError:(DLError *)e;
-(void)didReceiveCaptchaRequestOfType:(NSString *)captchaType withSiteKey:(NSString *)siteKey;
-(void)didReceiveTwoFactorAuthRequest;
-(void)didReceiveAuthFingerprint:(NSString *)fingerprint;
-(void)authFingerprintFailedWithError:(DLError *)e;
@end

@protocol DLControllerDelegate <NSObject>
@optional
-(void)requestDidFailWithError:(DLError *)e;
// The signed-in user's roles for a server arrived (or failed); channel
// visibility for it may have changed.
-(void)memberPermissionsDidLoadForServer:(DLServer *)server;
-(void)relationshipsDidUpdate;
-(void)initialDataWasReceived;
-(void)messages:(NSArray *)messages receivedForChannel:(DLChannel *)c;
-(void)newMessage:(DLMessage *)m receivedForChannel:(DLChannel *)c inServer:(DLServer *)s;
-(void)didLogoutSuccessfully;
-(void)userDidStartTypingInSelectedChannel:(DLUser *)u;
-(void)members:(NSArray *)members didUpdateForServer:(DLServer *)s;
-(void)connectionStateDidChange:(DLWSConnectionState)state;
-(void)messageSearchResults:(NSArray *)messages totalResults:(NSInteger)total offset:(NSInteger)offset forChannel:(DLChannel *)channel query:(NSString *)query;
-(void)messages:(NSArray *)messages receivedAroundSearchResult:(NSString *)messageID forChannel:(DLChannel *)channel;
-(void)newerMessages:(NSArray *)messages receivedForChannel:(DLChannel *)channel;
-(void)threadsDidUpdateForServer:(DLServer *)server;
-(void)archivedThreadsDidUpdateForServer:(DLServer *)server channel:(DLChannel *)channel;
-(void)userProfile:(NSDictionary *)profile didLoadForUser:(DLUser *)user inServer:(DLServer *)server;
-(void)channelPins:(NSArray *)messages didLoadForChannel:(DLChannel *)channel;
-(void)userNote:(NSString *)note didLoadForUser:(DLUser *)user error:(BOOL)error;
-(void)userNote:(NSString *)note didSaveForUser:(DLUser *)user error:(BOOL)error;
// A channel was created or removed by this client.
-(void)channelsDidChangeForServer:(DLServer *)server;
// The user left the server (or it was removed).
-(void)serverWasRemoved:(DLServer *)server;
@end

@interface DLController : NSObject <AsyncHTTPRequestDelegate, DLWSControllerDelegate> {
    NSString *token;
    NSString *twoFactorTicket;
    id <DLControllerDelegate> delegate;
    NSMutableSet *pendingMemberRequests;
    NSArray *relationships;
    NSMutableDictionary *friendPresences;
    // user_guild_settings entries keyed by guild ID ("@me" for DMs).
    NSMutableDictionary *guildNotificationSettings;
    NSMutableSet *pendingStarterRequests;
    id <DLLoginDelegate> loginDelegate;
    NSString *captchaKey;
    DLServer *selectedServer;
    DLServer *myServerItem;
    DLChannel *selectedChannel;
    DLUser *myUser;
    DLUserSettings *myUserSettings;
    NSMutableDictionary *accountSettings;
    NSMutableDictionary *loadedServers;
    NSMutableDictionary *loadedChannels;
    NSMutableArray *loadedMessages;
    NSString *authFingerprint;
    // Set when the main window has been filled with initial data. When the
    // first launch spends its first connections failing (unstable network),
    // the WS layer reports READY with its per-session reconnect flag set,
    // which must not make the client skip building the initial UI.
    BOOL initialContentLoaded;
}

-(DLServer *)selectedServer;
// The shared controller if it already exists, without creating it. Rendering
// code uses this so offline replay never reads the Keychain.
+(DLController *)existingInstance;
-(DLChannel *)selectedChannel;

-(void)setSelectedChannel:(DLChannel *)c;

-(void)setLoginDelegate:(id <DLLoginDelegate>)inLoginDelegate;
-(void)setDelegate:(id <DLControllerDelegate>)inDelegate;

-(void)setToken:(NSString *)t;
-(void)setCaptchaKey:(NSString *)inKey;

+(DLController *)sharedInstance;

-(void)loadUserDefaults;
-(BOOL)isLoggedIn;
-(void)loginWithEmail:(NSString *)email andPassword:(NSString *)password;
-(void)loginWithTwoFactorAuthCode:(NSString *)twoFactorCode;
-(void)loadMessagesForChannel:(DLChannel *)c beforeMessage:(DLMessage *)m quantity:(NSInteger)numMsgs;
-(void)searchMessagesForChannel:(DLChannel *)c query:(NSString *)query authorID:(NSString *)authorID offset:(NSInteger)offset;
-(void)loadMessagesAroundMessage:(DLMessage *)m inChannel:(DLChannel *)c;
-(void)loadMessagesForChannel:(DLChannel *)c afterMessage:(DLMessage *)m quantity:(NSInteger)numMsgs;
-(void)sendMessage:(DLMessage *)m toChannel:(DLChannel *)c;
-(void)acknowledgeMessage:(DLMessage *)m;
// Acknowledge the newest known message and clear unread/mention state.
-(void)markChannelAsRead:(DLChannel *)channel;
-(void)markServerAsRead:(DLServer *)server;
// Discord's per-server notification settings. A channel is muted when it, its
// category or its server is muted (unless a timed mute has expired).
-(BOOL)isServerMuted:(DLServer *)server;
-(BOOL)isChannelMuted:(DLChannel *)channel;
-(BOOL)isChannelMutedItself:(DLChannel *)channel;
-(BOOL)suppressesEveryoneInServerWithID:(NSString *)serverID;
// duration is in seconds; 0 mutes until turned back on.
-(void)setMuted:(BOOL)muted duration:(NSTimeInterval)duration forServer:(DLServer *)server;
-(void)setMuted:(BOOL)muted duration:(NSTimeInterval)duration forChannel:(DLChannel *)channel;
// Mentions across servers plus DMs, for the Dock badge.
-(NSInteger)totalMentionCount;
// READY relationships: dictionaries with id, type (1 friend, 2 blocked,
// 3 incoming request, 4 outgoing request) and user.
-(NSArray *)relationships;
// "online", "idle", "dnd" or "offline" for a friend.
-(NSString *)presenceStatusForUserID:(NSString *)userID;
-(void)deleteMessage:(DLMessage *)m;
-(void)logOutUser;
-(void)informTypingInChannel:(DLChannel *)c;
-(void)submitEditedMessage:(DLMessage *)m;
-(void)addReactionWithEmoji:(NSString *)emoji toMessage:(DLMessage *)m;
-(void)removeReactionWithEmoji:(NSString *)emoji fromMessage:(DLMessage *)m;
-(void)getAuthFingerprint;

-(void)startWebSocket;
-(void)stopWebSocket;

-(NSArray *)userServers;
-(NSArray *)channelsForServer:(DLServer *)s;
-(NSArray *)activeThreadsForServer:(DLServer *)server parentChannel:(DLChannel *)parentChannel;
-(NSArray *)directMessageChannels;

-(NSString *)authFingerprint;

-(void)queryServer:(DLServer *)s forMembersContainingUsername:(NSString *)username;
-(void)requestMembersForChannel:(DLChannel *)c inServer:(DLServer *)s from:(NSInteger)start to:(NSInteger)end;
-(void)loadActiveThreadsForServer:(DLServer *)server;
-(void)loadArchivedThreadsForChannel:(DLChannel *)channel;
-(void)loadProfileForUser:(DLUser *)user inServer:(DLServer *)server;
-(void)loadNoteForUser:(DLUser *)user;
-(void)saveNote:(NSString *)note forUser:(DLUser *)user;
-(void)loadPinsForChannel:(DLChannel *)channel;
// Fetches a forum post's opening message (same ID as the post) once.
-(void)loadStarterMessageForThread:(DLServerChannel *)thread;
// POST /channels/{forum}/threads with a title, opening message and tag IDs.
-(void)createForumPostInChannel:(DLServerChannel *)forum title:(NSString *)title
                        content:(NSString *)content tagIDs:(NSArray *)tagIDs;
// DELETE /channels/{thread}; THREAD_DELETE then removes it from the lists.
-(void)deleteThread:(DLChannel *)thread;
// Finds the 1:1 DM with user (creating it with POST /users/@me/channels when
// needed) and posts DLDirectMessageChannelReadyNotification with draft.
-(void)openDirectMessageWithUser:(DLUser *)user draft:(NSString *)draft;
// Generic REST call; completion runs on the main thread with the parsed JSON
// (or nil) and the HTTP status (0 when the request did not complete).
typedef void (^DLAPICompletion)(id json, NSInteger status);
-(void)sendAPIRequestWithMethod:(NSString *)method path:(NSString *)path body:(NSDictionary *)body
                     completion:(DLAPICompletion)completion;
// Notification settings for a server ("@me" for DMs), as Discord stores them.
-(NSDictionary *)notificationSettingsForServerID:(NSString *)serverID;
// Account-wide settings from READY user_settings (nil before login), and a
// PATCH /users/@me/settings that applies the change locally at once.
-(NSDictionary *)accountSettings;
-(void)updateAccountSettings:(NSDictionary *)changes;
// user_guild_settings.hide_muted_channels for the server.
-(BOOL)hidesMutedChannelsInServer:(DLServer *)server;
// Adds a channel returned by POST /guilds/{id}/channels and refreshes lists.
-(void)addServerChannelWithData:(NSDictionary *)data;
// Asks the delegate to rebuild the channel list and header of the server.
-(void)notifyChannelsChangedForServer:(DLServer *)server;
// The channel an invite is created for: the selected channel when it is in
// the server, else the first visible text channel.
-(DLServerChannel *)defaultInviteChannelForServer:(DLServer *)server;
// Forgets a server the user left and tells the delegate.
-(void)removeServer:(DLServer *)server;
// Forgets a deleted channel (and, for a category, nothing else: Discord
// moves its channels out of it).
-(void)removeChannelWithID:(NSString *)channelID;
-(void)updateNotificationSettings:(NSDictionary *)changes forServerID:(NSString *)serverID;


-(DLServer *)myServerItem;

-(DLUser *)myUser;
-(DLServer *)loadedServerWithID:(NSString *)srvID;
-(DLChannel *)loadedChannelWithID:(NSString *)chanID;

@end
