//
//  DLController.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/25/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLController.h"
#import "DLLocalization.h"
#import "DLServer.h"
#import <Security/Security.h>

static const char DLKeychainService[] = "org.legacydiscord.client";
static const char DLKeychainAccount[] = "discord-user-token";

@interface DLController ()
-(NSString *)tokenFromKeychain;
-(void)storeTokenInKeychain:(NSString *)newToken;
-(void)deleteTokenFromKeychain;
-(NSString *)URLQueryValue:(NSString *)value;
-(void)handleMessageSearchRequestResponse:(AsyncHTTPRequest *)req;
-(void)handleMessagesAroundRequestResponse:(AsyncHTTPRequest *)req;
-(void)handleMessagesNewerRequestResponse:(AsyncHTTPRequest *)req;
-(void)handleActiveThreadsRequestResponse:(AsyncHTTPRequest *)req;
-(void)handleArchivedThreadsRequestResponse:(AsyncHTTPRequest *)req;
-(void)handleUserProfileRequestResponse:(AsyncHTTPRequest *)req;
-(void)handleUserNoteRequestResponse:(AsyncHTTPRequest *)req;
-(void)handleChannelPinsRequestResponse:(AsyncHTTPRequest *)req;
-(void)parseUserProfileInBackground:(NSDictionary *)context;
-(void)finishUserProfileParsing:(NSDictionary *)result;
-(void)storeThreadData:(NSArray *)threads forServerWithID:(NSString *)serverID replacingExisting:(BOOL)replace;
@end

@implementation DLController

static DLController* sharedObject = nil;

-(id)init {
    self = [super init];
    OSStatus interactionStatus = SecKeychainSetUserInteractionAllowed(TRUE);
    if (interactionStatus != errSecSuccess) {
        NSLog(@"Unable to enable Keychain interaction (OSStatus %ld).", (long)interactionStatus);
    }
    [[DLWSController sharedInstance] setDelegate:self];
    loadedChannels = [[NSMutableDictionary alloc] init];
    loadedServers = [[NSMutableDictionary alloc] init];
    loadedMessages = [[NSMutableArray alloc] init];
    [[AsyncHTTPRequestSettings sharedInstance] setUserAgentString:[DLUtil userAgentString]];
    [[AsyncHTTPRequestSettings sharedInstance] setPersistentPOSTHeaders:[DLUtil defaultHTTPPostHeaders]];
    [DLUtil refreshClientBuildNumber];
    [self loadUserDefaults];
    return self;
}

+(DLController *)existingInstance {
    return sharedObject;
}

+(DLController *)sharedInstance {
    if (!sharedObject) {
        sharedObject = [[[super allocWithZone: NULL] init] retain];
    }
    return sharedObject;
}
-(void)loadUserDefaults {
    token = [[self tokenFromKeychain] retain];

    // Migrate tokens saved by the upstream client, then remove the plaintext copy.
    if (!token || [token length] == 0) {
        NSString *legacyToken = [[NSUserDefaults standardUserDefaults] objectForKey:@kDefaultsToken];
        if (legacyToken && [legacyToken length] > 0) {
            [self storeTokenInKeychain:legacyToken];
            [token release];
            token = [legacyToken retain];
        }
    }
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@kDefaultsToken];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

-(DLServer *)selectedServer {
    return selectedServer;
}
-(DLChannel *)selectedChannel {
    return selectedChannel;
}
-(void)setSelectedChannel:(DLChannel *)c {
    if (selectedChannel != c) {
        [selectedChannel release];
        selectedChannel = [c retain];
    }
}
-(void)setLoginDelegate:(id <DLLoginDelegate>)inLoginDelegate {
    loginDelegate = inLoginDelegate;
}

-(void)setDelegate:(id <DLControllerDelegate>)inDelegate {
    delegate = inDelegate;
}
-(void)setToken:(NSString *)t {
    if (token != t) {
        [token release];
        token = [t copy];
    }
    if (token && [token length] > 0) {
        [self storeTokenInKeychain:token];
    } else {
        [self deleteTokenFromKeychain];
    }
}

-(NSString *)tokenFromKeychain {
    UInt32 passwordLength = 0;
    void *passwordData = NULL;
    OSStatus status = SecKeychainFindGenericPassword(NULL,
                                                      (UInt32)(sizeof(DLKeychainService) - 1), DLKeychainService,
                                                      (UInt32)(sizeof(DLKeychainAccount) - 1), DLKeychainAccount,
                                                      &passwordLength, &passwordData, NULL);
    if (status != errSecSuccess || !passwordData) {
        if (status != errSecItemNotFound) {
            NSLog(@"Unable to read saved Discord session from Keychain (OSStatus %ld).", (long)status);
        }
        return nil;
    }

    NSData *data = [NSData dataWithBytes:passwordData length:passwordLength];
    NSString *storedToken = [[[NSString alloc] initWithData:data
                                                   encoding:NSUTF8StringEncoding] autorelease];
    SecKeychainItemFreeContent(NULL, passwordData);
    return storedToken;
}

-(void)storeTokenInKeychain:(NSString *)newToken {
    NSData *tokenData = [newToken dataUsingEncoding:NSUTF8StringEncoding];
    UInt32 previousLength = 0;
    void *previousData = NULL;
    SecKeychainItemRef item = NULL;
    OSStatus status = SecKeychainFindGenericPassword(NULL,
                                                      (UInt32)(sizeof(DLKeychainService) - 1), DLKeychainService,
                                                      (UInt32)(sizeof(DLKeychainAccount) - 1), DLKeychainAccount,
                                                      &previousLength, &previousData, &item);
    if (status == errSecSuccess) {
        if (previousData) SecKeychainItemFreeContent(NULL, previousData);
        OSStatus updateStatus = SecKeychainItemModifyAttributesAndData(item, NULL,
                                                                       (UInt32)[tokenData length],
                                                                       [tokenData bytes]);
        if (item) CFRelease(item);
        if (updateStatus != errSecSuccess) {
            NSLog(@"Unable to update Discord session in Keychain (OSStatus %ld).", (long)updateStatus);
        }
        return;
    }
    if (status != errSecItemNotFound) {
        NSLog(@"Unable to update Discord session in Keychain (OSStatus %ld).", (long)status);
        if (previousData) SecKeychainItemFreeContent(NULL, previousData);
        if (item) CFRelease(item);
        return;
    }
    OSStatus addStatus = SecKeychainAddGenericPassword(NULL,
                                                        (UInt32)(sizeof(DLKeychainService) - 1), DLKeychainService,
                                                        (UInt32)(sizeof(DLKeychainAccount) - 1), DLKeychainAccount,
                                                        (UInt32)[tokenData length], [tokenData bytes], NULL);
    if (addStatus != errSecSuccess) {
        NSLog(@"Unable to save Discord session in Keychain (OSStatus %ld).", (long)addStatus);
    }
}

-(void)deleteTokenFromKeychain {
    UInt32 passwordLength = 0;
    void *passwordData = NULL;
    SecKeychainItemRef item = NULL;
    OSStatus status = SecKeychainFindGenericPassword(NULL,
                                                      (UInt32)(sizeof(DLKeychainService) - 1), DLKeychainService,
                                                      (UInt32)(sizeof(DLKeychainAccount) - 1), DLKeychainAccount,
                                                      &passwordLength, &passwordData, &item);
    if (passwordData) SecKeychainItemFreeContent(NULL, passwordData);
    if (status == errSecSuccess && item) status = SecKeychainItemDelete(item);
    if (item) CFRelease(item);
    if (status != errSecSuccess && status != errSecItemNotFound) {
        NSLog(@"Unable to delete Discord session from Keychain (OSStatus %ld).", (long)status);
    }
}
-(void)setCaptchaKey:(NSString *)inKey {
    [captchaKey release];
    [inKey retain];
    captchaKey = inKey;
}

-(BOOL)isLoggedIn {
    return (token && ![token isEqualToString:@""]);
}

-(NSDictionary *)requestHeaders {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            token, @"Authorization", [DLUtil superPropertiesString], @"X-Super-Properties", nil];
}

-(NSString *)URLQueryValue:(NSString *)value {
    if (!value) {
        return @"";
    }
    CFStringRef escaped = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                  (CFStringRef)value,
                                                                  NULL,
                                                                  CFSTR("!*'();:@&=+$,/?%#[]"),
                                                                  kCFStringEncodingUTF8);
    return [(NSString *)escaped autorelease];
}

-(void)loginWithEmail:(NSString *)email andPassword:(NSString *)password {
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObjects:[NSArray arrayWithObjects:email, password, [NSNull null], [NSNull null], [NSNumber numberWithBool:NO], nil] forKeys:[NSArray arrayWithObjects:@"login", @"password", @"gift_code_sku_id", @"login_source", @"undelete", nil]];
    if (captchaKey) {
        [params setObject:captchaKey forKey:@"captcha_key"];
    }
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setParameters:params];
    [req setHeaders:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[DLUtil superPropertiesString], authFingerprint, nil] forKeys:[NSArray arrayWithObjects:@"X-Super-Properties", @"X-Fingerprint", nil]]];
    [req setIdentifier:RequestIDLogin];
    
    [req setUrl:[@API_ROOT stringByAppendingString:@"/auth/login"]];
    [req start];
}

-(void)loginWithTwoFactorAuthCode:(NSString *)twoFactorCode {
    NSDictionary *params = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:twoFactorTicket, twoFactorCode, [NSNull null
], [NSNull null], nil] forKeys:[NSArray arrayWithObjects:@"ticket", @"code", @"gift_code_sku_id", @"login_source", nil]];
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setParameters:params];
    [req setHeaders:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[DLUtil superPropertiesString], authFingerprint, nil] forKeys:[NSArray arrayWithObjects:@"X-Super-Properties", @"X-Fingerprint", nil]]];
    [req setIdentifier:RequestIDTwoFactor];
    
    [req setUrl:[@API_ROOT stringByAppendingString:@"/auth/mfa/totp"]];
    [req start];
}

// The web client gets its login fingerprint from GET /experiments (the old
// POST /auth/fingerprint is no longer used by official clients).
-(void)getAuthFingerprint {
    AsyncHTTPGetRequest *req = [[AsyncHTTPGetRequest alloc] init];
    [req setDelegate:self];
    [req setHeaders:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[DLUtil superPropertiesString], nil] forKeys:[NSArray arrayWithObjects:@"X-Super-Properties", nil]]];
    [req setIdentifier:RequestIDGetFingerprint];
    [req setUrl:[@API_ROOT stringByAppendingString:@"/experiments?with_guild_experiments=true"]];
    [req start];
}

-(void)loadMessagesForChannel:(DLChannel *)c beforeMessage:(DLMessage *)m quantity:(NSInteger)numMsgs {
    if (![c isEqual:selectedChannel]) {
        [loadedMessages removeAllObjects];
        [selectedChannel release];
        [c retain];
        selectedChannel = c;
        if ([selectedServer isEqual:[self myServerItem]]) {
            [[DLWSController sharedInstance] updateWSForDirectMessageChannel:c];
        } else {
            [[DLWSController sharedInstance] updateWSForChannel:c inServer:selectedServer];
        }
    }
    
    AsyncHTTPGetRequest *req = [[AsyncHTTPGetRequest alloc] init];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDMessages];
    [req setUserInfo:[NSDictionary dictionaryWithObject:c forKey:@"channel"]];
    NSString *requestURL = [@API_ROOT stringByAppendingString:[NSString stringWithFormat:@"/channels/%@/messages?limit=%ld", c.channelID, numMsgs]];
    if (m != nil) {
        requestURL = [requestURL stringByAppendingString:[NSString stringWithFormat:@"&before=%@", m.messageID]];
    }
    [req setUrl:requestURL];
    [req start];
}

-(void)searchMessagesForChannel:(DLChannel *)c query:(NSString *)query authorID:(NSString *)authorID offset:(NSInteger)offset {
    if (!c || !query || [query length] == 0) {
        return;
    }
    AsyncHTTPGetRequest *req = [[AsyncHTTPGetRequest alloc] init];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDSearchMessages];
    [req setUserInfo:[NSDictionary dictionaryWithObjectsAndKeys:c, @"channel", query, @"query",
                      [NSNumber numberWithInteger:offset], @"offset", nil]];

    NSString *contentQuery = query;
    if ([query hasPrefix:@"from:"]) {
        NSRange separator = [query rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
        contentQuery = separator.location == NSNotFound ? @"" :
            [[query substringFromIndex:separator.location + 1]
             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    NSString *escapedQuery = [self URLQueryValue:contentQuery];
    NSMutableString *parameters = [NSMutableString string];
    if ([escapedQuery length] > 0) {
        [parameters appendFormat:@"content=%@&", escapedQuery];
    }
    if (authorID && [authorID length] > 0) {
        [parameters appendFormat:@"author_id=%@&", [self URLQueryValue:authorID]];
    }
    [parameters appendFormat:@"offset=%ld", (long)offset];
    NSString *requestURL = nil;
    if ([c type] == ChannelTypeDM || [c type] == ChannelTypeGroup) {
        requestURL = [@API_ROOT stringByAppendingString:
                      [NSString stringWithFormat:@"/channels/%@/messages/search?%@",
                       [c channelID], parameters]];
    } else {
        requestURL = [@API_ROOT stringByAppendingString:
                      [NSString stringWithFormat:@"/guilds/%@/messages/search?%@",
                       [c serverID], parameters]];
    }
    [req setUrl:requestURL];
    [req start];
}

-(void)loadMessagesAroundMessage:(DLMessage *)m inChannel:(DLChannel *)c {
    if (!m || !c) {
        return;
    }
    if (![c isEqual:selectedChannel]) {
        [loadedMessages removeAllObjects];
        [selectedChannel release];
        selectedChannel = [c retain];
        if ([selectedServer isEqual:[self myServerItem]]) {
            [[DLWSController sharedInstance] updateWSForDirectMessageChannel:c];
        } else {
            [[DLWSController sharedInstance] updateWSForChannel:c inServer:selectedServer];
        }
    }
    AsyncHTTPGetRequest *req = [[AsyncHTTPGetRequest alloc] init];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDMessagesAround];
    [req setUserInfo:[NSDictionary dictionaryWithObjectsAndKeys:c, @"channel", [m messageID], @"messageID", nil]];
    [req setUrl:[@API_ROOT stringByAppendingString:
                 [NSString stringWithFormat:@"/channels/%@/messages?limit=15&around=%@", [c channelID], [m messageID]]]];
    [req start];
}

-(void)loadMessagesForChannel:(DLChannel *)c afterMessage:(DLMessage *)m quantity:(NSInteger)numMsgs {
    if (!c || !m || ![c isEqual:selectedChannel]) {
        return;
    }
    AsyncHTTPGetRequest *req = [[AsyncHTTPGetRequest alloc] init];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDMessagesNewer];
    [req setUserInfo:[NSDictionary dictionaryWithObject:c forKey:@"channel"]];
    [req setUrl:[@API_ROOT stringByAppendingString:
                 [NSString stringWithFormat:@"/channels/%@/messages?limit=%ld&after=%@",
                  [c channelID], (long)numMsgs, [m messageID]]]];
    [req start];
}

-(void)loadActiveThreadsForServer:(DLServer *)server {
    if (!server || [server isEqual:[self myServerItem]]) {
        return;
    }
    AsyncHTTPGetRequest *req = [[AsyncHTTPGetRequest alloc] init];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDActiveThreads];
    [req setUserInfo:[NSDictionary dictionaryWithObject:server forKey:@"server"]];
    [req setUrl:[@API_ROOT stringByAppendingString:
                 [NSString stringWithFormat:@"/guilds/%@/threads/active", [server serverID]]]];
    [req start];
}

-(void)loadArchivedThreadsForChannel:(DLChannel *)channel {
    DLServer *server = [self selectedServer];
    if (!channel || !server || [server isEqual:[self myServerItem]]) {
        return;
    }
    AsyncHTTPGetRequest *req = [[AsyncHTTPGetRequest alloc] init];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDArchivedThreads];
    [req setUserInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                      channel, @"channel", server, @"server", nil]];
    [req setUrl:[@API_ROOT stringByAppendingString:
                 [NSString stringWithFormat:@"/channels/%@/threads/archived/public?limit=50",
                  [channel channelID]]]];
    [req start];
}

-(void)loadProfileForUser:(DLUser *)user inServer:(DLServer *)server {
    if (!user || ![user userID]) {
        return;
    }
    AsyncHTTPGetRequest *req = [[AsyncHTTPGetRequest alloc] init];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDUserProfile];
    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithObject:user forKey:@"user"];
    if (server) {
        [context setObject:server forKey:@"server"];
    }
    [req setUserInfo:context];
    NSMutableString *requestURL = [NSMutableString stringWithFormat:
                                   @API_ROOT @"/users/%@/profile?with_mutual_guilds=true&with_mutual_friends_count=false",
                                   [user userID]];
    if (server && ![server isEqual:[self myServerItem]] && [server serverID]) {
        [requestURL appendFormat:@"&guild_id=%@", [server serverID]];
    }
    [req setUrl:requestURL];
    [req start];
}

-(void)loadNoteForUser:(DLUser *)user {
    if (![self isLoggedIn] || !user || ![user userID]) return;
    AsyncHTTPGetRequest *req = [[AsyncHTTPGetRequest alloc] init];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDUserNoteLoad];
    [req setUserInfo:[NSDictionary dictionaryWithObject:user forKey:@"user"]];
    [req setUrl:[@API_ROOT stringByAppendingFormat:@"/users/@me/notes/%@", [user userID]]];
    [req start];
}

-(void)saveNote:(NSString *)note forUser:(DLUser *)user {
    if (![self isLoggedIn] || !user || ![user userID] || !note) return;
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setMethod:@"PUT"];
    [req setParameters:[NSDictionary dictionaryWithObject:note forKey:@"note"]];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDUserNoteSave];
    [req setUserInfo:[NSDictionary dictionaryWithObjectsAndKeys:user, @"user", note, @"note", nil]];
    [req setUrl:[@API_ROOT stringByAppendingFormat:@"/users/@me/notes/%@", [user userID]]];
    [req start];
}

-(void)loadStarterMessageForThread:(DLServerChannel *)thread {
    if (![thread isThread] || [thread starterSummary] || ![[thread channelID] length]) return;
    if (!pendingStarterRequests) pendingStarterRequests = [[NSMutableSet alloc] init];
    if ([pendingStarterRequests containsObject:[thread channelID]]) return;
    [pendingStarterRequests addObject:[thread channelID]];
    AsyncHTTPGetRequest *req = [[AsyncHTTPGetRequest alloc] init];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDForumStarter];
    [req setUserInfo:[NSDictionary dictionaryWithObject:thread forKey:@"thread"]];
    // GET /messages/{id} is bot-only; "around" with limit 1 returns the same
    // opening message to a user account.
    [req setUrl:[@API_ROOT stringByAppendingFormat:@"/channels/%@/messages?around=%@&limit=1", [thread channelID], [thread channelID]]];
    [req start];
}

-(void)handleForumStarterResponse:(AsyncHTTPRequest *)req {
    DLServerChannel *thread = [[req userInfo] objectForKey:@"thread"];
    NSMutableDictionary *summary = [NSMutableDictionary dictionary];
    if ([req result] == HTTPResultOK) {
        id response = [[CJSONDeserializer deserializer] deserialize:[req responseData] error:nil];
        if ([response isKindOfClass:[NSArray class]]) response = [response count] ? [response objectAtIndex:0] : nil;
        if ([response isKindOfClass:[NSDictionary class]] &&
            [[[response objectForKey:@"id"] description] isEqualToString:[thread channelID]]) {
            DLMessage *message = [[[DLMessage alloc] initWithDict:response] autorelease];
            NSString *author = [[message author] globalName];
            if (author) [summary setObject:author forKey:@"author"];
            NSString *text = [[message content] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            text = [[text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
            if (![text length] && [[message attachments] count]) text = DLLocalizedString(@"Sent an attachment");
            if (text) [summary setObject:text forKey:@"text"];
        }
    }
    // An empty summary still marks the post as fetched (deleted starter).
    [thread setStarterSummary:summary];
    [[NSNotificationCenter defaultCenter] postNotificationName:DLThreadStarterDidLoadNotification object:thread];
}

-(void)createForumPostInChannel:(DLServerChannel *)forum title:(NSString *)title
                        content:(NSString *)content tagIDs:(NSArray *)tagIDs {
    if (!forum || ![title length] || ![content length]) return;
    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                       title, @"name",
                                       [NSDictionary dictionaryWithObject:content forKey:@"content"], @"message", nil];
    if ([tagIDs count]) [parameters setObject:tagIDs forKey:@"applied_tags"];
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setParameters:parameters];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDCreateForumPost];
    [req setUserInfo:[NSDictionary dictionaryWithObject:forum forKey:@"forum"]];
    [req setUrl:[@API_ROOT stringByAppendingFormat:@"/channels/%@/threads", [forum channelID]]];
    [req start];
}

-(void)handleCreateForumPostResponse:(AsyncHTTPRequest *)req {
    DLServerChannel *forum = [[req userInfo] objectForKey:@"forum"];
    id response = [[CJSONDeserializer deserializer] deserialize:[req responseData] error:nil];
    NSDictionary *userInfo = nil;
    if ([req result] == HTTPResultOK && [response isKindOfClass:[NSDictionary class]] && [response objectForKey:@"id"]) {
        NSMutableDictionary *threadData = [NSMutableDictionary dictionaryWithDictionary:response];
        // The creator is a member of the new post, so it appears as joined.
        if (![threadData objectForKey:@"member"]) [threadData setObject:[NSDictionary dictionary] forKey:@"member"];
        [self storeThreadData:[NSArray arrayWithObject:threadData] forServerWithID:[forum serverID] replacingExisting:NO];
        DLChannel *thread = [self loadedChannelWithID:[response objectForKey:@"id"]];
        if (thread) userInfo = [NSDictionary dictionaryWithObject:thread forKey:@"thread"];
    }
    if (!userInfo) {
        NSString *message = [response isKindOfClass:[NSDictionary class]] ? [response objectForKey:@"message"] : nil;
        userInfo = [NSDictionary dictionaryWithObject:([message isKindOfClass:[NSString class]] ? message : DLLocalizedString(@"The post could not be created."))
                                               forKey:@"error"];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:DLForumPostCreationDidFinishNotification
                                                        object:forum userInfo:userInfo];
}

-(void)deleteThread:(DLChannel *)thread {
    if (![thread isThread]) return;
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDDeleteThread];
    [req setMethod:@"DELETE"];
    [req setUrl:[@API_ROOT stringByAppendingFormat:@"/channels/%@", [thread channelID]]];
    [req start];
}

-(void)postDirectMessageReady:(DLChannel *)channel draft:(NSString *)draft {
    [[NSNotificationCenter defaultCenter] postNotificationName:DLDirectMessageChannelReadyNotification object:self
        userInfo:[NSDictionary dictionaryWithObjectsAndKeys:channel, @"channel", (draft ? draft : @""), @"draft", nil]];
}

-(void)openDirectMessageWithUser:(DLUser *)user draft:(NSString *)draft {
    if (![user userID]) return;
    NSEnumerator *enumerator = [[loadedChannels allValues] objectEnumerator];
    DLChannel *channel;
    while (channel = [enumerator nextObject]) {
        if ([channel isKindOfClass:[DLDirectMessageChannel class]] && ![(DLDirectMessageChannel *)channel isGroupMessage] &&
            [(DLDirectMessageChannel *)channel recipientWithUserID:[[user userID] description]]) {
            [self postDirectMessageReady:channel draft:draft];
            return;
        }
    }
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setParameters:[NSDictionary dictionaryWithObject:[[user userID] description] forKey:@"recipient_id"]];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDOpenDirectMessage];
    [req setUserInfo:[NSDictionary dictionaryWithObject:(draft ? draft : @"") forKey:@"draft"]];
    [req setUrl:[@API_ROOT stringByAppendingString:@"/users/@me/channels"]];
    [req start];
}

-(void)handleOpenDirectMessageResponse:(AsyncHTTPRequest *)req {
    if ([req result] != HTTPResultOK) {
        [self handleHTTPRequestError:req];
        return;
    }
    id response = [[CJSONDeserializer deserializer] deserialize:[req responseData] error:nil];
    if (![response isKindOfClass:[NSDictionary class]] || ![response objectForKey:@"id"]) return;
    DLChannel *channel = [loadedChannels objectForKey:[response objectForKey:@"id"]];
    if (!channel) {
        channel = [[[DLDirectMessageChannel alloc] initWithDict:response] autorelease];
        [loadedChannels setObject:channel forKey:[channel channelID]];
    }
    [self postDirectMessageReady:channel draft:[[req userInfo] objectForKey:@"draft"]];
}

-(void)sendAPIRequestWithMethod:(NSString *)method path:(NSString *)path body:(NSDictionary *)body
                     completion:(DLAPICompletion)completion {
    AsyncHTTPRequest *req;
    if ([method isEqualToString:@"GET"]) {
        req = [[AsyncHTTPGetRequest alloc] init];
    } else {
        AsyncHTTPPostRequest *post = [[AsyncHTTPPostRequest alloc] init];
        [post setMethod:method];
        [post setParameters:(body ? body : [NSDictionary dictionary])];
        req = post;
    }
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDGeneric];
    if (completion) {
        DLAPICompletion copy = [[completion copy] autorelease];
        [req setUserInfo:[NSDictionary dictionaryWithObject:copy forKey:@"completion"]];
    }
    [req setUrl:[@API_ROOT stringByAppendingString:path]];
    [req start];
}

-(void)handleGenericResponse:(AsyncHTTPRequest *)req {
    DLAPICompletion completion = [[req userInfo] objectForKey:@"completion"];
    if (!completion) return;
    id json = [[req responseData] length] ? [[CJSONDeserializer deserializer] deserialize:[req responseData] error:nil] : nil;
    completion(json, [req statusCode]);
}

-(NSDictionary *)notificationSettingsForServerID:(NSString *)serverID {
    return [guildNotificationSettings objectForKey:[self settingsKeyForServerID:serverID]];
}

-(void)updateNotificationSettings:(NSDictionary *)changes forServerID:(NSString *)serverID {
    [self patchNotificationSettings:changes forServerKey:[self settingsKeyForServerID:serverID]];
}

-(void)loadPinsForChannel:(DLChannel *)channel {
    if (!channel) return;
    AsyncHTTPGetRequest *req = [[AsyncHTTPGetRequest alloc] init];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDChannelPins];
    [req setUserInfo:[NSDictionary dictionaryWithObject:channel forKey:@"channel"]];
    [req setUrl:[@API_ROOT stringByAppendingString:
                 [NSString stringWithFormat:@"/channels/%@/messages/pins?limit=50", [channel channelID]]]];
    [req start];
}

-(void)sendMessage:(DLMessage *)m toChannel:(DLChannel *)c {
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setParameters:[m dictRepresentation]];
    if ([m attachments].count > 0) {
        NSMutableArray *files = [NSMutableArray array];
        NSEnumerator *e = [[m attachments] objectEnumerator];
        DLAttachment *a;
        while (a = [e nextObject]) {
            if (![a attachmentData] || ![a filename]) continue;
            [files addObject:[NSDictionary dictionaryWithObjectsAndKeys:[a filename], @"filename", [a attachmentData], @"data", nil]];
        }
        [req setFiles:files];
    }
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDSendMessage];
    [req setUserInfo:[NSDictionary dictionaryWithObject:c forKey:@"channel"]];
    NSString *requestURL = [@API_ROOT stringByAppendingString:[NSString stringWithFormat:@"/channels/%@/messages", c.channelID]];
    [req setUrl:requestURL];
    [req start];
}

-(void)deleteMessage:(DLMessage *)m {
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDMessageDelete];
    [req setMethod:@"DELETE"];
    NSString *requestURL = [@API_ROOT stringByAppendingString:[NSString stringWithFormat:@"/channels/%@/messages/%@", [m channelID], [m messageID]]];
    [req setUrl:requestURL];
    [req start];
}

-(void)acknowledgeMessage:(DLMessage *)m {
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setParameters:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[NSNull null], [NSNumber numberWithInt:0], [NSNumber numberWithInt:1], nil] forKeys:[NSArray arrayWithObjects:@"token", @"last_viewed", @"flags", nil]]];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDAckMessage];
    NSString *requestURL = [@API_ROOT stringByAppendingString:[NSString stringWithFormat:@"/channels/%@/messages/%@/ack", [m channelID], [m messageID]]];
    [req setUrl:requestURL];
    [req start];
}

-(void)markChannelAsRead:(DLChannel *)channel {
    if (!channel) return;
    if ([channel lastMessage] && [[channel lastMessage] messageID]) [self acknowledgeMessage:[channel lastMessage]];
    [channel setHasUnreadMessages:NO];
    DLServer *server = [self loadedServerWithID:[channel serverID]];
    if (server && [channel mentionCount] > 0) {
        [server setMentionCount:MAX(0, [server mentionCount] - [channel mentionCount])];
    }
    [channel setMentionCount:0];
}

-(void)markServerAsRead:(DLServer *)server {
    if (!server) return;
    NSEnumerator *enumerator = [[loadedChannels allValues] objectEnumerator];
    DLChannel *channel;
    while (channel = [enumerator nextObject]) {
        if (![channel isKindOfClass:[DLServerChannel class]]) continue;
        if (![[(DLServerChannel *)channel serverID] isEqualToString:[server serverID]]) continue;
        if ([channel hasUnreadMessages] || [channel mentionCount] > 0) [self markChannelAsRead:channel];
    }
    [server setHasUnreadMessages:NO];
    [server setMentionCount:0];
}

-(void)logOutUser {
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setParameters:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"apns_voip", @"apns", nil] forKeys:[NSArray arrayWithObjects:@"voip_provider", @"provider", nil]]];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDLogout];
    NSString *requestURL = [@API_ROOT stringByAppendingString:@"/auth/logout"];
    [req setUrl:requestURL];
    [req start];
    
    [self setToken:@""];
    [loadedChannels release];
    [loadedServers release];
    loadedChannels = [[NSMutableDictionary alloc] init];
    loadedServers = [[NSMutableDictionary alloc] init];
    [myServerItem release];
    myServerItem = nil;
    [myUser release];
    myUser = nil;
    [myUserSettings release];
    myUserSettings = nil;
    [selectedServer release];
    selectedServer = nil;
    [selectedChannel release];
    selectedChannel = nil;
    [delegate didLogoutSuccessfully];
}

-(void)informTypingInChannel:(DLChannel *)c {
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setParameters:[NSDictionary dictionaryWithObject:[NSNull null] forKey:@"token"]];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDTyping];
    NSString *requestURL = [@API_ROOT stringByAppendingString:[NSString stringWithFormat:@"/channels/%@/typing", [c channelID]]];
    [req setUrl:requestURL];
    [req start];
}

-(void)submitEditedMessage:(DLMessage *)m {
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setParameters:[NSDictionary dictionaryWithObject:[m content] forKey:@"content"]];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDMessageEdit];
    [req setMethod:@"PATCH"];
    NSString *requestURL = [@API_ROOT stringByAppendingString:[NSString stringWithFormat:@"/channels/%@/messages/%@", [m channelID], [m messageID]]];
    [req setUrl:requestURL];
    [req start];
}

-(void)addReactionWithEmoji:(NSString *)emoji toMessage:(DLMessage *)m {
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setParameters:[NSDictionary dictionary]];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDAddReaction];
    [req setMethod:@"PUT"];
    NSString *encodedEmoji = [DLUtil URLPathEncodedString:emoji];
    NSString *requestURL = [@API_ROOT stringByAppendingString:[NSString stringWithFormat:@"/channels/%@/messages/%@/reactions/%@/@me", [m channelID], [m messageID], encodedEmoji]];
    [req setUrl:requestURL];
    [req start];
}

-(void)removeReactionWithEmoji:(NSString *)emoji fromMessage:(DLMessage *)m {
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setParameters:[NSDictionary dictionary]];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDRemoveReaction];
    [req setMethod:@"DELETE"];
    NSString *encodedEmoji = [DLUtil URLPathEncodedString:emoji];
    NSString *requestURL = [@API_ROOT stringByAppendingString:[NSString stringWithFormat:@"/channels/%@/messages/%@/reactions/%@/@me", [m channelID], [m messageID], encodedEmoji]];
    [req setUrl:requestURL];
    [req start];
}

-(NSArray *)userServers {
    NSMutableArray *servers = [[NSMutableArray alloc] init];
    NSEnumerator *e = [[myUserSettings serverFolders] objectEnumerator];
    DLServerFolder *folder;
    while (folder = [e nextObject]) {
        NSEnumerator *ee = [[folder serverIDs] objectEnumerator];
        NSString *serverID;
        while (serverID = [ee nextObject]) {
            if ([loadedServers objectForKey:serverID]) {
                [servers addObject:[loadedServers objectForKey:serverID]];
            }
        }
    }
    //Load unordered servers
    e = [[loadedServers allKeys] objectEnumerator];
    NSString *serverID;
    while (serverID = [e nextObject]) {
        if ([loadedServers objectForKey:serverID]) {
            if (![servers containsObject:[loadedServers objectForKey:serverID]]) {
                [servers insertObject:[loadedServers objectForKey:serverID] atIndex:0];
            }
        }
    }
    return servers;
}
// READY does not always include merged_members, so the own member object
// (for role-based channel visibility) is fetched when a server is opened.
-(void)loadMyMemberForServer:(DLServer *)server {
    if (![self isLoggedIn] || !server || [server hasKnownMemberRoles] || [server myRolesUnavailable]) return;
    if (!pendingMemberRequests) pendingMemberRequests = [[NSMutableSet alloc] init];
    NSString *serverID = [[server serverID] description];
    if ([pendingMemberRequests containsObject:serverID]) return;
    [pendingMemberRequests addObject:serverID];
    AsyncHTTPGetRequest *req = [[AsyncHTTPGetRequest alloc] init];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDMyGuildMember];
    [req setUserInfo:[NSDictionary dictionaryWithObject:server forKey:@"server"]];
    [req setUrl:[@API_ROOT stringByAppendingFormat:@"/users/@me/guilds/%@/member", serverID]];
    [req start];
}

-(void)handleMyGuildMemberResponse:(AsyncHTTPRequest *)req {
    DLServer *server = [[req userInfo] objectForKey:@"server"];
    [pendingMemberRequests removeObject:[[server serverID] description]];
    NSDictionary *member = ([req result] == HTTPResultOK && [req responseData])
        ? [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil] : nil;
    NSArray *roles = [member objectForKey:@"roles"];
    if ([roles isKindOfClass:[NSArray class]]) [server setMyRoleIDs:roles];
    else [server setMyRolesUnavailable:YES];
    if ([member isKindOfClass:[NSDictionary class]]) [server setMyNickname:[member objectForKey:@"nick"]];
    if ([delegate respondsToSelector:@selector(memberPermissionsDidLoadForServer:)]) {
        [delegate memberPermissionsDidLoadForServer:server];
    }
}

-(NSArray *)channelsForServer:(DLServer *)s {
    if (![s hasKnownMemberRoles] && ![s myRolesUnavailable] && ![s isEqual:[self myServerItem]]) {
        [self performSelectorOnMainThread:@selector(loadMyMemberForServer:) withObject:s waitUntilDone:NO];
    }
    [selectedServer release];
    [s retain];
    selectedServer = s;
    NSMutableArray *channels = [[NSMutableArray alloc] init];
    BOOL hideMuted = [self hidesMutedChannelsInServer:s];
    
    NSEnumerator *e = [[loadedChannels allKeys] objectEnumerator];
    NSString *channelKey;
    while (channelKey = [e nextObject]) {
        DLServerChannel *c = [loadedChannels objectForKey:channelKey];
        if ([[c serverID] isEqualToString:[s serverID]] &&
            [s canUserWithID:[[self myUser] userID] viewChannelWithOverwrites:[c permissionOverwrites]]) {
            if (hideMuted && c != (DLServerChannel *)selectedChannel && [self isChannelMutedIgnoringServer:c]) continue;
            [channels addObject:c];
        }
    }
    
    NSMutableArray *parentChannels = [[NSMutableArray alloc] init];
    NSMutableArray *uncategorizedChannels = [[NSMutableArray alloc] init];
    NSMutableArray *childChannels = [[NSMutableArray alloc] init];
    NSMutableArray *recentThreads = [[NSMutableArray alloc] init];
    
    e = [channels objectEnumerator];
    DLServerChannel *c;
    while (c = [e nextObject]) {
        if (c.type == ChannelTypeHeader) {
            [parentChannels addObject:c];
        } else if ([c isThread]) {
            if ([c joinedThread]) {
                [recentThreads addObject:c];
            }
        } else if (!c.parentID || [c.parentID isEqual:[NSNull null]]) {
            [uncategorizedChannels addObject:c];
            
        } else {
            [childChannels addObject:c];
        }
    }
    
    NSMutableArray *sortedParentChannels = [NSMutableArray arrayWithArray:[parentChannels sortedArrayUsingSelector:@selector(compare:)]];
    NSArray *sortedChildChannels = [childChannels sortedArrayUsingSelector:@selector(compare:)];
    NSArray *sortedUncategorizedChannels = [uncategorizedChannels sortedArrayUsingSelector:@selector(compare:)];

    NSMutableArray *regularChannels = [NSMutableArray arrayWithArray:sortedUncategorizedChannels];
    [regularChannels addObjectsFromArray:sortedChildChannels];
    e = [regularChannels objectEnumerator];
    while (c = [e nextObject]) {
        NSMutableArray *channelThreads = [NSMutableArray array];
        NSEnumerator *threadEnumerator = [recentThreads objectEnumerator];
        DLServerChannel *thread;
        while (thread = [threadEnumerator nextObject]) {
            if ([[thread parentID] isEqualToString:[c channelID]]) {
                [channelThreads addObject:thread];
            }
        }
        [c setChildren:[channelThreads sortedArrayUsingSelector:@selector(compareThreadRecency:)]];
    }

    e = [sortedParentChannels objectEnumerator];
    while (c = [e nextObject]) {
        NSMutableArray *children = [[NSMutableArray alloc] init];
        DLServerChannel *cc;
        NSEnumerator *ee = [sortedChildChannels objectEnumerator];
        while(cc = [ee nextObject]) {
            if ((!cc.parentID || ![cc.parentID isEqual:[NSNull null]]) && [cc.parentID isEqualToString:c.channelID]) {
                [children addObject:cc];
            }
        }
        [c setChildren:children];
        [children release];
    }
    
    NSMutableArray *result = [NSMutableArray arrayWithArray:sortedUncategorizedChannels];
    // Categories whose channels are all hidden are not shown either.
    e = [sortedParentChannels objectEnumerator];
    while (c = [e nextObject]) {
        if ([[c children] count] > 0) [result addObject:c];
    }
    
    [channels release];
    [uncategorizedChannels release];
    [childChannels release];
    [recentThreads release];
    [parentChannels release];
    return result;
}

-(NSArray *)activeThreadsForServer:(DLServer *)server parentChannel:(DLChannel *)parentChannel {
    NSMutableArray *threads = [NSMutableArray array];
    NSEnumerator *enumerator = [[loadedChannels allValues] objectEnumerator];
    DLServerChannel *channel;
    while (channel = [enumerator nextObject]) {
        if (![channel isThread] || ![[channel serverID] isEqualToString:[server serverID]]) {
            continue;
        }
        if (parentChannel && ![[channel parentID] isEqualToString:[parentChannel channelID]]) {
            continue;
        }
        [threads addObject:channel];
    }
    return [threads sortedArrayUsingSelector:@selector(compareThreadRecency:)];
}

-(NSArray *)directMessageChannels {
    [selectedServer release];
    selectedServer = [[self myServerItem] retain];
    NSMutableArray *dms = [[NSMutableArray alloc] init];
    NSEnumerator *e = [[loadedChannels allKeys] objectEnumerator];
    NSString *channelKey;
    while (channelKey = [e nextObject]) {
        DLDirectMessageChannel *c = [loadedChannels objectForKey:channelKey];
        if ([[c serverID] isEqualToString:[[self myServerItem] serverID]]) {
            [dms addObject:c];
        }
        
    }
    NSArray *sorted = [dms sortedArrayUsingSelector:@selector(compare:)];
    [dms release];
    return sorted;
}

-(DLUser *)myUser {
    return myUser;
}

-(void)startWebSocket {
    [[DLWSController sharedInstance] startWithAuthToken:token];
}
-(void)stopWebSocket {
    [[DLWSController sharedInstance] stop];
}

-(DLServer *)loadedServerWithID:(NSString *)srvID {
    if ([loadedServers objectForKey:srvID]) {
        return [loadedServers objectForKey:srvID];
    }
    return nil;
}
-(DLChannel *)loadedChannelWithID:(NSString *)chanID {
    if ([loadedChannels objectForKey:chanID]) {
        return [loadedChannels objectForKey:chanID];
    }
    return nil;
}

-(DLServer *)myServerItem {
    if (!myServerItem) {
        myServerItem = [[DLServer alloc] init];
        [myServerItem setIconImageData:[NSData dataWithContentsOfFile:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"discord_purple.png"]]];
        [myServerItem setServerID:@"@me"];
        [myServerItem setName:DLLocalizedString(@"Direct Messages")];
    }
    return myServerItem;
}

-(NSString *)authFingerprint {
    return authFingerprint;
}

-(void)queryServer:(DLServer *)s forMembersContainingUsername:(NSString *)username {
    [[DLWSController sharedInstance] queryServer:s forMembersContainingUsername:username];
}

-(void)requestMembersForChannel:(DLChannel *)c inServer:(DLServer *)s from:(NSInteger)start to:(NSInteger)end {
    [[DLWSController sharedInstance] requestMembersForChannel:c inServer:s from:start to:end];
}


#pragma mark Response Handlers

-(void)handleLoginRequestResponse:(AsyncHTTPRequest *)req {
    
    switch ([req result]) {
        case HTTPResultOK: {
            NSDictionary *resDict = nil;
            if ([req responseData]) {
                resDict = [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil];
            }
            if ([resDict objectForKey:@"token"] && ![[resDict objectForKey:@"token"] isKindOfClass:[NSNull class]]) {
                [self setToken:[resDict objectForKey:@"token"]];
                [loginDelegate didLoginWithError:nil];
            } else if ([resDict objectForKey:@"ticket"] && ![[resDict objectForKey:@"ticket"] isKindOfClass:[NSNull class]]) {
                twoFactorTicket = [[resDict objectForKey:@"ticket"] retain];
                [loginDelegate didReceiveTwoFactorAuthRequest];
            }
            break;
        }
        case HTTPResultErrParameter: {
            NSDictionary *resDict = nil;
            if ([req responseData]) {
                resDict = [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil];
            }
            if ([resDict objectForKey:@"captcha_key"]) {
                [loginDelegate didReceiveCaptchaRequestOfType:[resDict objectForKey:@"captcha_service"] withSiteKey:[resDict objectForKey:@"captcha_sitekey"]];
            } else {
                NSString *message = @"";
                if ([[resDict objectForKey:[resDict.allKeys objectAtIndex:0]] isKindOfClass:[NSArray class]]) {
                    message = [[resDict objectForKey:[resDict.allKeys objectAtIndex:0]] objectAtIndex:0];
                } else {
                    message = [resDict objectForKey:@"message"];
                }
                [loginDelegate didLoginWithError:[DLError requestErrorWithMessage:message]];
            }
            
            break;
        }
        case HTTPResultErrGeneral: {
            NSDictionary *resDict = nil;
            if ([req responseData]) {
                resDict = [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil];
            }
            [loginDelegate didLoginWithError:[DLError requestErrorWithMessage:[resDict objectForKey:@"message"]]];
            break;
        }
        case HTTPResultErrConnecting:
            [loginDelegate didLoginWithError:[DLError generalConnectionError]];
            break;
        default:
            break;
    }
}

-(void)handleMessagesRequestResponse:(AsyncHTTPRequest *)req {
    if ([req result] == HTTPResultOK) {
        DLChannel *requestedChannel = [[req userInfo] objectForKey:@"channel"];
        if (requestedChannel && ![requestedChannel isEqual:selectedChannel]) {
            return;
        }
        NSArray *resArray = [[CJSONDeserializer deserializer] deserializeAsArray:[req responseData] error:nil];
        NSEnumerator *e = [resArray objectEnumerator];
        NSDictionary *messageData;
        NSMutableArray *newMessages = [[NSMutableArray alloc] init];
        while (messageData = [e nextObject]) {
            DLMessage *m = [[DLMessage alloc] initWithDict:messageData];
            [newMessages addObject:m];
            [m release];
        }
        [loadedMessages addObjectsFromArray:newMessages];
        [delegate messages:newMessages receivedForChannel:(requestedChannel ? requestedChannel : selectedChannel)];
        [newMessages release];
    } else {
        [self handleHTTPRequestError:req];
    }
}

-(void)handleMessageSearchRequestResponse:(AsyncHTTPRequest *)req {
    if ([req result] != HTTPResultOK) {
        [self handleHTTPRequestError:req];
        return;
    }

    NSDictionary *context = [req userInfo];
    DLChannel *channel = [context objectForKey:@"channel"];
    NSString *query = [context objectForKey:@"query"];
    NSDictionary *response = [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil];
    NSArray *groups = [response objectForKey:@"messages"];
    NSMutableArray *results = [NSMutableArray array];
    NSEnumerator *groupEnumerator = [groups objectEnumerator];
    id group;
    while (group = [groupEnumerator nextObject]) {
        NSArray *candidates = [group isKindOfClass:[NSArray class]] ? group : [NSArray arrayWithObject:group];
        NSDictionary *selectedData = nil;
        NSEnumerator *candidateEnumerator = [candidates objectEnumerator];
        NSDictionary *candidate;
        while (candidate = [candidateEnumerator nextObject]) {
            if (![candidate isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            if (!selectedData) {
                selectedData = candidate;
            }
            if ([[candidate objectForKey:@"hit"] boolValue]) {
                selectedData = candidate;
                break;
            }
        }
        if (selectedData) {
            DLMessage *message = [[[DLMessage alloc] initWithDict:selectedData] autorelease];
            if (![message serverID] && [channel serverID]) {
                [message setServerID:[channel serverID]];
            }
            [results addObject:message];
        }
    }
    id totalValue = [response objectForKey:@"total_results"];
    NSInteger total = [totalValue respondsToSelector:@selector(integerValue)] ? [totalValue integerValue] : [results count];
    NSInteger offset = [[context objectForKey:@"offset"] integerValue];
    [delegate messageSearchResults:results totalResults:total offset:offset forChannel:channel query:query];
}

-(void)handleMessagesAroundRequestResponse:(AsyncHTTPRequest *)req {
    if ([req result] != HTTPResultOK) {
        [self handleHTTPRequestError:req];
        return;
    }
    NSDictionary *context = [req userInfo];
    DLChannel *channel = [context objectForKey:@"channel"];
    NSArray *response = [[CJSONDeserializer deserializer] deserializeAsArray:[req responseData] error:nil];
    NSMutableArray *messages = [NSMutableArray array];
    NSEnumerator *enumerator = [response objectEnumerator];
    NSDictionary *messageData;
    while (messageData = [enumerator nextObject]) {
        if (![messageData isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        DLMessage *message = [[[DLMessage alloc] initWithDict:messageData] autorelease];
        if (![message serverID] && [channel serverID]) {
            [message setServerID:[channel serverID]];
        }
        [messages addObject:message];
    }
    [delegate messages:messages
receivedAroundSearchResult:[context objectForKey:@"messageID"]
             forChannel:channel];
}

-(void)handleMessagesNewerRequestResponse:(AsyncHTTPRequest *)req {
    if ([req result] != HTTPResultOK) {
        [self handleHTTPRequestError:req];
        return;
    }
    DLChannel *channel = [[req userInfo] objectForKey:@"channel"];
    NSArray *response = [[CJSONDeserializer deserializer] deserializeAsArray:[req responseData] error:nil];
    NSMutableArray *messages = [NSMutableArray array];
    NSEnumerator *enumerator = [response objectEnumerator];
    NSDictionary *messageData;
    while (messageData = [enumerator nextObject]) {
        if (![messageData isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        DLMessage *message = [[[DLMessage alloc] initWithDict:messageData] autorelease];
        if (![message serverID] && [channel serverID]) {
            [message setServerID:[channel serverID]];
        }
        [messages addObject:message];
    }
    if ([messages count] > 1 &&
        [[(DLMessage *)[messages objectAtIndex:0] timestamp] compare:[(DLMessage *)[messages lastObject] timestamp]] == NSOrderedAscending) {
        [messages setArray:[[messages reverseObjectEnumerator] allObjects]];
    }
    [delegate newerMessages:messages receivedForChannel:channel];
}

-(void)handleChannelPinsRequestResponse:(AsyncHTTPRequest *)req {
    if ([req result] != HTTPResultOK) {
        [self handleHTTPRequestError:req];
        return;
    }
    DLChannel *channel = [[req userInfo] objectForKey:@"channel"];
    id response = [[CJSONDeserializer deserializer] deserialize:[req responseData] error:nil];
    NSArray *items = [response isKindOfClass:[NSDictionary class]] ? [response objectForKey:@"items"] : response;
    NSMutableArray *messages = [NSMutableArray array];
    NSEnumerator *enumerator = [items objectEnumerator];
    id item;
    while (item = [enumerator nextObject]) {
        NSDictionary *messageData = [item isKindOfClass:[NSDictionary class]] ? [item objectForKey:@"message"] : nil;
        if (!messageData && [item isKindOfClass:[NSDictionary class]] && [item objectForKey:@"id"]) {
            messageData = item;
        }
        if (![messageData isKindOfClass:[NSDictionary class]]) continue;
        DLMessage *message = [[[DLMessage alloc] initWithDict:messageData] autorelease];
        if (![message serverID] && [channel serverID]) [message setServerID:[channel serverID]];
        [messages addObject:message];
    }
    [delegate channelPins:messages didLoadForChannel:channel];
}

-(void)storeThreadData:(NSArray *)threads forServerWithID:(NSString *)serverID replacingExisting:(BOOL)replace {
    if (!serverID || ![threads isKindOfClass:[NSArray class]]) {
        return;
    }
    if (replace) {
        NSMutableArray *keysToRemove = [NSMutableArray array];
        NSEnumerator *keyEnumerator = [[loadedChannels allKeys] objectEnumerator];
        NSString *channelID;
        while (channelID = [keyEnumerator nextObject]) {
            DLChannel *channel = [loadedChannels objectForKey:channelID];
            if ([channel isThread] && [[channel serverID] isEqualToString:serverID]) {
                [keysToRemove addObject:channelID];
            }
        }
        [loadedChannels removeObjectsForKeys:keysToRemove];
    }

    NSEnumerator *threadEnumerator = [threads objectEnumerator];
    NSDictionary *threadData;
    while (threadData = [threadEnumerator nextObject]) {
        if (![threadData isKindOfClass:[NSDictionary class]] || ![threadData objectForKey:@"id"]) {
            continue;
        }
        DLServerChannel *thread = [loadedChannels objectForKey:[threadData objectForKey:@"id"]];
        if (thread && [thread isThread]) {
            [thread updateWithDict:threadData];
            [thread setServerID:serverID];
        } else {
            thread = [[[DLServerChannel alloc] initWithDict:threadData] autorelease];
            [thread setServerID:serverID];
            [loadedChannels setObject:thread forKey:[thread channelID]];
        }
    }
}

-(void)handleActiveThreadsRequestResponse:(AsyncHTTPRequest *)req {
    DLServer *server = [[req userInfo] objectForKey:@"server"];
    if ([req result] != HTTPResultOK) {
        NSLog(@"Unable to load active threads for server %@.", [server serverID]);
        return;
    }
    NSDictionary *response = [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil];
    NSArray *threads = [response objectForKey:@"threads"];
    [self storeThreadData:threads ? threads : [NSArray array]
          forServerWithID:[server serverID]
        replacingExisting:YES];
    NSEnumerator *memberEnumerator = [[response objectForKey:@"members"] objectEnumerator];
    NSDictionary *member;
    while (member = [memberEnumerator nextObject]) {
        DLServerChannel *thread = [loadedChannels objectForKey:[member objectForKey:@"id"]];
        if ([thread isThread]) {
            [thread setJoinedThread:YES];
        }
    }
    [delegate threadsDidUpdateForServer:server];
}

-(void)handleArchivedThreadsRequestResponse:(AsyncHTTPRequest *)req {
    if ([req result] != HTTPResultOK) {
        NSLog(@"Unable to load archived threads for channel %@.",
              [[[req userInfo] objectForKey:@"channel"] channelID]);
        return;
    }
    NSDictionary *response = [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil];
    NSArray *threads = [response objectForKey:@"threads"];
    DLServer *server = [[req userInfo] objectForKey:@"server"];
    [self storeThreadData:threads ? threads : [NSArray array]
          forServerWithID:[server serverID]
        replacingExisting:NO];
    NSEnumerator *enumerator = [threads objectEnumerator];
    NSDictionary *threadData;
    while (threadData = [enumerator nextObject]) {
        DLServerChannel *thread = [loadedChannels objectForKey:[threadData objectForKey:@"id"]];
        [thread setArchivedThread:YES];
    }
    DLChannel *channel = [[req userInfo] objectForKey:@"channel"];
    if ([delegate respondsToSelector:@selector(archivedThreadsDidUpdateForServer:channel:)]) {
        [delegate archivedThreadsDidUpdateForServer:server channel:channel];
    }
}

-(void)handleUserProfileRequestResponse:(AsyncHTTPRequest *)req {
    if ([req result] == HTTPResultOK && [req responseData]) {
        NSMutableDictionary *context = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                        [NSData dataWithData:[req responseData]], @"data",
                                        [[req userInfo] objectForKey:@"user"], @"user", nil];
        if ([[req userInfo] objectForKey:@"server"]) {
            [context setObject:[[req userInfo] objectForKey:@"server"] forKey:@"server"];
        }
        [self performSelectorInBackground:@selector(parseUserProfileInBackground:) withObject:context];
        return;
    } else {
        NSLog(@"Unable to load optional profile data for user %@.",
              [[[[req userInfo] objectForKey:@"user"] userID] description]);
    }
    if ([delegate respondsToSelector:@selector(userProfile:didLoadForUser:inServer:)]) {
        [delegate userProfile:nil
               didLoadForUser:[[req userInfo] objectForKey:@"user"]
                      inServer:[[req userInfo] objectForKey:@"server"]];
    }
}

-(void)handleUserNoteRequestResponse:(AsyncHTTPRequest *)req {
    DLUser *user = [[req userInfo] objectForKey:@"user"];
    if ([req identifier] == RequestIDUserNoteSave) {
        if ([delegate respondsToSelector:@selector(userNote:didSaveForUser:error:)]) {
            [delegate userNote:[[req userInfo] objectForKey:@"note"]
                didSaveForUser:user error:[req result] != HTTPResultOK];
        }
        return;
    }
    // Discord returns 404 for a user whose note has never been set.
    BOOL missing = [req statusCode] == 404;
    NSDictionary *body = [req result] == HTTPResultOK
        ? [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil] : nil;
    NSString *note = [body objectForKey:@"note"];
    BOOL error = !missing && ([req result] != HTTPResultOK || ![note isKindOfClass:[NSString class]]);
    if ([delegate respondsToSelector:@selector(userNote:didLoadForUser:error:)]) {
        [delegate userNote:error ? nil : (missing ? @"" : note) didLoadForUser:user error:error];
    }
}

-(void)parseUserProfileInBackground:(NSDictionary *)context {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    id response = [[CJSONDeserializer deserializer]
                   deserializeAsDictionary:[context objectForKey:@"data"] error:nil];
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:[context objectForKey:@"user"]
                                                                      forKey:@"user"];
    if ([context objectForKey:@"server"]) [result setObject:[context objectForKey:@"server"] forKey:@"server"];
    if ([response isKindOfClass:[NSDictionary class]]) [result setObject:response forKey:@"profile"];
    [self performSelectorOnMainThread:@selector(finishUserProfileParsing:)
                           withObject:result waitUntilDone:NO];
    [pool drain];
}

-(void)finishUserProfileParsing:(NSDictionary *)result {
    if ([delegate respondsToSelector:@selector(userProfile:didLoadForUser:inServer:)]) {
        [delegate userProfile:[result objectForKey:@"profile"]
               didLoadForUser:[result objectForKey:@"user"]
                      inServer:[result objectForKey:@"server"]];
    }
}

-(void)handleSendMessageRequestResponse:(AsyncHTTPRequest *)req {
    if ([req result] != HTTPResultOK) {
        [self handleHTTPRequestError:req];
        return;
    }
    DLServerChannel *channel = [[req userInfo] objectForKey:@"channel"];
    if ([channel isThread]) {
        [channel setJoinedThread:YES];
        [channel setArchivedThread:NO];
        DLServer *server = [self loadedServerWithID:[channel serverID]];
        if (server) {
            [delegate threadsDidUpdateForServer:server];
        }
    }
}

-(void)handleFingerprintRequestResponse:(AsyncHTTPRequest *)req {
    if ([req result] == HTTPResultOK) {
        if ([req responseData]) {
            NSDictionary *resDict = [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil];
            authFingerprint = [[resDict objectForKey:@"fingerprint"] retain];
            [loginDelegate didReceiveAuthFingerprint:authFingerprint];
        }
    } else if ([req result] == HTTPResultErrGeneral) {
        NSDictionary *resDict = nil;
        if ([req responseData]) {
            resDict = [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil];
        }
        [loginDelegate authFingerprintFailedWithError:[DLError requestErrorWithMessage:[resDict objectForKey:@"message"]]];
    } else {
        [loginDelegate authFingerprintFailedWithError:[DLError generalConnectionError]];
    }
}


-(void)handleHTTPRequestError:(AsyncHTTPRequest *)req {
    switch ([req result]) {
        case HTTPResultErrParameter: {
            NSDictionary *resDict = nil;
            if ([req responseData]) {
                resDict = [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil];
            }
            NSString *message = @"";
            if ([[resDict objectForKey:[resDict.allKeys objectAtIndex:0]] isKindOfClass:[NSArray class]]) {
                message = [[resDict objectForKey:[resDict.allKeys objectAtIndex:0]] objectAtIndex:0];
            } else {
                message = [resDict objectForKey:@"message"];
            }
            [delegate requestDidFailWithError:[DLError requestErrorWithMessage:message]];
            break;
        }
        case HTTPResultErrGeneral: {
            NSDictionary *resDict = nil;
            if ([req responseData]) {
                resDict = [[CJSONDeserializer deserializer] deserializeAsDictionary:[req responseData] error:nil];
            }
            [delegate requestDidFailWithError:[DLError requestErrorWithMessage:[resDict objectForKey:@"message"]]];
            break;
        }
        case HTTPResultErrConnecting:
            [delegate requestDidFailWithError:[DLError generalConnectionError]];
            break;
        default:
            break;
    }
}

#pragma mark Delegated Functions

-(void)requestDidFinishLoading:(AsyncHTTPRequest *)request {
    switch ([request identifier]) {
        case RequestIDLogin:
        case RequestIDTwoFactor:
            [self handleLoginRequestResponse:request];
            break;
        case RequestIDMessages:
            [self handleMessagesRequestResponse:request];
            break;
        case RequestIDSearchMessages:
            [self handleMessageSearchRequestResponse:request];
            break;
        case RequestIDMessagesAround:
            [self handleMessagesAroundRequestResponse:request];
            break;
        case RequestIDMessagesNewer:
            [self handleMessagesNewerRequestResponse:request];
            break;
        case RequestIDActiveThreads:
            [self handleActiveThreadsRequestResponse:request];
            break;
        case RequestIDArchivedThreads:
            [self handleArchivedThreadsRequestResponse:request];
            break;
        case RequestIDUserProfile:
            [self handleUserProfileRequestResponse:request];
            break;
        case RequestIDMyGuildMember:
            [self handleMyGuildMemberResponse:request];
            break;
        case RequestIDUserNoteLoad:
        case RequestIDUserNoteSave:
            [self handleUserNoteRequestResponse:request];
            break;
        case RequestIDChannelPins:
            [self handleChannelPinsRequestResponse:request];
            break;
        case RequestIDForumStarter:
            [self handleForumStarterResponse:request];
            break;
        case RequestIDCreateForumPost:
            [self handleCreateForumPostResponse:request];
            break;
        case RequestIDGeneric:
            [self handleGenericResponse:request];
            break;
        case RequestIDOpenDirectMessage:
            [self handleOpenDirectMessageResponse:request];
            break;
        case RequestIDDeleteThread:
            if ([request result] != HTTPResultOK) [self handleHTTPRequestError:request];
            break;
        case RequestIDLogout:
            
            break;
        case RequestIDSendMessage:
        case RequestIDAddReaction:
        case RequestIDRemoveReaction:
            [self handleSendMessageRequestResponse:request];
            break;
        case RequestIDTyping:
            break;
        case RequestIDGetFingerprint:
            [self handleFingerprintRequestResponse:request];
            break;
        default:
            break;
    }
    [request release];
}

#pragma mark Websocket Delegated Functions

-(void)wsConnectionStateDidChange:(DLWSConnectionState)state {
    [delegate connectionStateDidChange:state];
}

-(void)wsDidReceiveMessage:(DLMessage *)m {
    [loadedMessages addObject:m];
    DLChannel *c = [self loadedChannelWithID:[m channelID]];
    DLServer *s = [self loadedServerWithID:[c serverID]];
    [c setLastMessage:m];
    // message_count excludes the opening message, which shares the post's ID.
    if ([c isThread] && ![[[m messageID] description] isEqualToString:[[c channelID] description]]) {
        [(DLServerChannel *)c incrementMessageCount];
    }
    if ([c isThread] && [[m author] isEqual:myUser]) {
        [(DLServerChannel *)c setJoinedThread:YES];
        [(DLServerChannel *)c setArchivedThread:NO];
        if (s) {
            [delegate threadsDidUpdateForServer:s];
        }
    }
    [delegate newMessage:m receivedForChannel:c inServer:s];
}

-(void)wsDidReceivePrivateChannelData:(NSArray *)data {
    NSEnumerator *e = [data objectEnumerator];
    NSDictionary *channelData;
    while (channelData = [e nextObject]) {
        if (![loadedChannels objectForKey:[channelData objectForKey:@"id"]]) {
            DLDirectMessageChannel *c = [[DLDirectMessageChannel alloc] initWithDict:channelData];
            [loadedChannels setObject:c forKey:[channelData objectForKey:@"id"]];
            [c release];
        }
    }
}

-(void)wsDidReceiveServerData:(NSArray *)data {
    NSEnumerator *e = [data objectEnumerator];
    NSDictionary *serverData;
    while (serverData = [e nextObject]) {
        if (![loadedServers objectForKey:[serverData objectForKey:@"id"]]) {
            DLServer *s = [[DLServer alloc] initWithDict:serverData];
            [loadedServers setObject:s forKey:[serverData objectForKey:@"id"]];
            [s release];
        }
        NSEnumerator *ee = [[serverData objectForKey:@"channels"] objectEnumerator];
        NSDictionary *channelData;
        while (channelData = [ee nextObject]) {
            if (![loadedChannels objectForKey:[channelData objectForKey:@"id"]]) {
                DLServerChannel *c = [[DLServerChannel alloc] initWithDict:channelData];
                [c setServerID:[serverData objectForKey:@"id"]];
                [loadedChannels setObject:c forKey:[channelData objectForKey:@"id"]];
                [c release];
            }
        }
        NSArray *threads = [serverData objectForKey:@"threads"];
        if ([threads isKindOfClass:[NSArray class]]) {
            [self storeThreadData:threads
                  forServerWithID:[serverData objectForKey:@"id"]
                replacingExisting:NO];
        }
    }
    [loadedServers setObject:[self myServerItem] forKey:[[self myServerItem] serverID]];
}

-(void)wsDidReceiveThreads:(NSArray *)threads forServerWithID:(NSString *)serverID {
    [self storeThreadData:threads forServerWithID:serverID replacingExisting:NO];
    DLServer *server = [self loadedServerWithID:serverID];
    if (server) {
        [delegate threadsDidUpdateForServer:server];
    }
}

-(void)wsDidDeleteThreadWithID:(NSString *)threadID forServerWithID:(NSString *)serverID {
    DLChannel *thread = [loadedChannels objectForKey:threadID];
    if ([thread isThread]) {
        [loadedChannels removeObjectForKey:threadID];
    }
    DLServer *server = [self loadedServerWithID:serverID];
    if (server) {
        [delegate threadsDidUpdateForServer:server];
    }
}

-(void)wsDidReceiveReadStateData:(NSArray *)data {
    
    NSEnumerator *e = [[loadedServers allKeys] objectEnumerator];
    NSString *key;
    while (key = [e nextObject]) {
        [[loadedServers objectForKey:key] setMentionCount:0];
    }
    
    e = [data objectEnumerator];
    NSDictionary *channelData;
    while (channelData = [e nextObject]) {
        if ([loadedChannels objectForKey:[channelData objectForKey:@"id"]]) {
            DLChannel *c = [loadedChannels objectForKey:[channelData objectForKey:@"id"]];
            DLServer *associatedServer = [self loadedServerWithID:[c serverID]];
            [c setMentionCount:[[channelData objectForKey:@"mention_count"] intValue]];
            [associatedServer addMentionCount:[[channelData objectForKey:@"mention_count"] intValue]];
            
            if ([channelData objectForKey:@"last_message_id"] != [NSNull null] && [c lastMessage]) {
                if (![[[c lastMessage] messageID] isEqualToString:[channelData objectForKey:@"last_message_id"]] && ![c isEqual:selectedChannel]) {
                    [c setHasUnreadMessages:YES];
                    // Muted channels do not light up their server.
                    if (![associatedServer isEqual:[self myServerItem]] && ![self isChannelMuted:c]) {
                        [associatedServer setHasUnreadMessages:YES];
                    }
                }
            }
        }
    }
}

#pragma mark Notification settings

static BOOL DLMuteEntryIsActive(NSDictionary *entry) {
    if (![entry isKindOfClass:[NSDictionary class]]) return NO;
    if (![[entry objectForKey:@"muted"] respondsToSelector:@selector(boolValue)] ||
        ![[entry objectForKey:@"muted"] boolValue]) return NO;
    NSDictionary *config = [entry objectForKey:@"mute_config"];
    NSString *endTime = [config isKindOfClass:[NSDictionary class]] ? [config objectForKey:@"end_time"] : nil;
    if (![endTime isKindOfClass:[NSString class]] || [endTime length] < 19) return YES;
    // A timed mute ("for 1 hour") ends at end_time, an ISO 8601 UTC string.
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
    [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss"];
    NSDate *end = [formatter dateFromString:[endTime substringToIndex:19]];
    return !end || [end timeIntervalSinceNow] > 0;
}

-(NSString *)settingsKeyForServerID:(id)serverID {
    // Channel and guild IDs may arrive as NSNull from JSON.
    if ([serverID isKindOfClass:[NSNumber class]]) serverID = [serverID description];
    return ([serverID isKindOfClass:[NSString class]] && [serverID length]) ? serverID : @"@me";
}

-(NSDictionary *)channelOverrideForChannelID:(NSString *)channelID inSettings:(NSDictionary *)settings {
    id overrides = [settings objectForKey:@"channel_overrides"];
    if ([overrides isKindOfClass:[NSDictionary class]]) return [overrides objectForKey:channelID];
    if (![overrides isKindOfClass:[NSArray class]]) return nil;
    NSEnumerator *enumerator = [overrides objectEnumerator];
    NSDictionary *override;
    while (override = [enumerator nextObject]) {
        if ([override isKindOfClass:[NSDictionary class]] &&
            [[[override objectForKey:@"channel_id"] description] isEqualToString:channelID]) return override;
    }
    return nil;
}

-(void)storeUserGuildSettingsEntry:(NSDictionary *)entry {
    if (![entry isKindOfClass:[NSDictionary class]]) return;
    id guildID = [entry objectForKey:@"guild_id"];
    NSString *key = [self settingsKeyForServerID:([guildID isKindOfClass:[NSString class]] ? guildID : nil)];
    [guildNotificationSettings setObject:entry forKey:key];
}

-(void)wsDidReceiveUserGuildSettings:(id)settings replacingAll:(BOOL)replacingAll {
    if (!guildNotificationSettings) guildNotificationSettings = [[NSMutableDictionary alloc] init];
    if (replacingAll) [guildNotificationSettings removeAllObjects];
    // READY sends {entries: [...]} (or a bare list on older payloads); an
    // update event sends one entry.
    id entries = settings;
    if ([settings isKindOfClass:[NSDictionary class]] && [settings objectForKey:@"entries"]) {
        entries = [settings objectForKey:@"entries"];
    }
    if ([entries isKindOfClass:[NSArray class]]) {
        NSEnumerator *enumerator = [entries objectEnumerator];
        NSDictionary *entry;
        while (entry = [enumerator nextObject]) [self storeUserGuildSettingsEntry:entry];
    } else {
        [self storeUserGuildSettingsEntry:entries];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:DLNotificationSettingsDidChangeNotification object:self];
}

-(BOOL)isServerMuted:(DLServer *)server {
    if (!server || [server isEqual:[self myServerItem]]) return NO;
    return DLMuteEntryIsActive([guildNotificationSettings objectForKey:[self settingsKeyForServerID:[server serverID]]]);
}

-(BOOL)isChannelMutedItself:(DLChannel *)channel {
    if (![[channel channelID] isKindOfClass:[NSString class]]) return NO;
    NSString *serverID = [channel isKindOfClass:[DLServerChannel class]] ? [(DLServerChannel *)channel serverID] : nil;
    NSDictionary *settings = [guildNotificationSettings objectForKey:[self settingsKeyForServerID:serverID]];
    return DLMuteEntryIsActive([self channelOverrideForChannelID:[channel channelID] inSettings:settings]);
}

-(BOOL)isChannelMuted:(DLChannel *)channel {
    if (!channel) return NO;
    if ([self isChannelMutedItself:channel]) return YES;
    if (![channel isKindOfClass:[DLServerChannel class]]) return NO;
    id parentID = [(DLServerChannel *)channel parentID];
    if ([parentID isKindOfClass:[NSString class]] && [parentID length] &&
        [self isChannelMutedItself:[self loadedChannelWithID:parentID]]) return YES;
    return [self isServerMuted:[self loadedServerWithID:[(DLServerChannel *)channel serverID]]];
}

// Hide Muted Channels hides muted channels and categories, not the whole
// list of a muted server.
-(BOOL)isChannelMutedIgnoringServer:(DLChannel *)channel {
    if ([self isChannelMutedItself:channel]) return YES;
    if (![channel isKindOfClass:[DLServerChannel class]]) return NO;
    id parentID = [(DLServerChannel *)channel parentID];
    return [parentID isKindOfClass:[NSString class]] && [parentID length] &&
           [self isChannelMutedItself:[self loadedChannelWithID:parentID]];
}

-(BOOL)hidesMutedChannelsInServer:(DLServer *)server {
    NSDictionary *settings = [guildNotificationSettings objectForKey:[self settingsKeyForServerID:[server serverID]]];
    id value = [settings objectForKey:@"hide_muted_channels"];
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

-(void)addServerChannelWithData:(NSDictionary *)data {
    if (![data isKindOfClass:[NSDictionary class]] || ![data objectForKey:@"id"]) return;
    NSString *serverID = [[data objectForKey:@"guild_id"] description];
    if (![loadedChannels objectForKey:[data objectForKey:@"id"]]) {
        DLServerChannel *channel = [[[DLServerChannel alloc] initWithDict:data] autorelease];
        [channel setServerID:serverID];
        [loadedChannels setObject:channel forKey:[data objectForKey:@"id"]];
    }
    [self notifyChannelsChangedForServer:[self loadedServerWithID:serverID]];
}

-(void)notifyChannelsChangedForServer:(DLServer *)server {
    if (server && [delegate respondsToSelector:@selector(channelsDidChangeForServer:)]) {
        [delegate channelsDidChangeForServer:server];
    }
}

-(DLServerChannel *)defaultInviteChannelForServer:(DLServer *)server {
    NSString *serverID = [[server serverID] description];
    if ([selectedChannel isKindOfClass:[DLServerChannel class]] &&
        [[[(DLServerChannel *)selectedChannel serverID] description] isEqualToString:serverID] &&
        ![selectedChannel isThread] && [selectedChannel type] != ChannelTypeHeader) {
        return (DLServerChannel *)selectedChannel;
    }
    DLServerChannel *best = nil;
    NSEnumerator *enumerator = [loadedChannels objectEnumerator];
    DLChannel *channel;
    while (channel = [enumerator nextObject]) {
        if (![channel isKindOfClass:[DLServerChannel class]] || [channel type] != ChannelTypeStandard) continue;
        DLServerChannel *serverChannel = (DLServerChannel *)channel;
        if (![[[serverChannel serverID] description] isEqualToString:serverID]) continue;
        if (![server canUserWithID:[[self myUser] userID] viewChannelWithOverwrites:[serverChannel permissionOverwrites]]) continue;
        if (!best || [serverChannel position] < [best position]) best = serverChannel;
    }
    return best;
}

-(void)removeChannelWithID:(NSString *)channelID {
    if (!channelID) return;
    NSEnumerator *enumerator = [loadedChannels objectEnumerator];
    DLChannel *channel;
    while (channel = [enumerator nextObject]) {
        // Channels of a deleted category become uncategorized.
        if ([channel isKindOfClass:[DLServerChannel class]] &&
            [[[(DLServerChannel *)channel parentID] description] isEqualToString:channelID]) {
            [(DLServerChannel *)channel updateWithDict:[NSDictionary dictionaryWithObject:[NSNull null] forKey:@"parent_id"]];
        }
    }
    if ([[[selectedChannel channelID] description] isEqualToString:channelID]) {
        [selectedChannel release];
        selectedChannel = nil;
    }
    [loadedChannels removeObjectForKey:channelID];
}

-(void)removeServer:(DLServer *)server {
    if (!server || [server isEqual:[self myServerItem]]) return;
    [[server retain] autorelease];
    NSString *serverID = [[server serverID] description];
    NSEnumerator *enumerator = [[loadedChannels allKeys] objectEnumerator];
    NSString *channelID;
    while (channelID = [enumerator nextObject]) {
        DLChannel *channel = [loadedChannels objectForKey:channelID];
        if ([channel isKindOfClass:[DLServerChannel class]] &&
            [[[(DLServerChannel *)channel serverID] description] isEqualToString:serverID]) {
            [loadedChannels removeObjectForKey:channelID];
        }
    }
    [loadedServers removeObjectForKey:serverID];
    [guildNotificationSettings removeObjectForKey:serverID];
    if ([delegate respondsToSelector:@selector(serverWasRemoved:)]) [delegate serverWasRemoved:server];
}

-(BOOL)suppressesEveryoneInServerWithID:(NSString *)serverID {
    NSDictionary *settings = [guildNotificationSettings objectForKey:[self settingsKeyForServerID:serverID]];
    return [[settings objectForKey:@"suppress_everyone"] respondsToSelector:@selector(boolValue)] &&
           [[settings objectForKey:@"suppress_everyone"] boolValue];
}

// Applies the change locally right away (Discord echoes it back through
// USER_GUILD_SETTINGS_UPDATE) and sends the same PATCH the official client does.
-(void)patchNotificationSettings:(NSDictionary *)parameters forServerKey:(NSString *)key {
    if (!guildNotificationSettings) guildNotificationSettings = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:
                                  ([guildNotificationSettings objectForKey:key] ? [guildNotificationSettings objectForKey:key] : [NSDictionary dictionary])];
    NSDictionary *overrideChanges = [parameters objectForKey:@"channel_overrides"];
    if (overrideChanges) {
        NSMutableArray *overrides = [NSMutableArray array];
        id existing = [entry objectForKey:@"channel_overrides"];
        if ([existing isKindOfClass:[NSArray class]]) [overrides addObjectsFromArray:existing];
        else if ([existing isKindOfClass:[NSDictionary class]]) [overrides addObjectsFromArray:[existing allValues]];
        NSEnumerator *keyEnumerator = [overrideChanges keyEnumerator];
        NSString *channelID;
        while (channelID = [keyEnumerator nextObject]) {
            NSInteger index;
            for (index = (NSInteger)[overrides count] - 1; index >= 0; index--) {
                if ([[[[overrides objectAtIndex:index] objectForKey:@"channel_id"] description] isEqualToString:channelID]) {
                    [overrides removeObjectAtIndex:index];
                }
            }
            NSMutableDictionary *override = [NSMutableDictionary dictionaryWithDictionary:[overrideChanges objectForKey:channelID]];
            [override setObject:channelID forKey:@"channel_id"];
            [overrides addObject:override];
        }
        [entry setObject:overrides forKey:@"channel_overrides"];
    } else {
        [entry addEntriesFromDictionary:parameters];
    }
    [guildNotificationSettings setObject:entry forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:DLNotificationSettingsDidChangeNotification object:self];
    if (![self isLoggedIn]) return;
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setMethod:@"PATCH"];
    [req setParameters:parameters];
    [req setDelegate:self];
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDNotificationSettings];
    [req setUrl:[@API_ROOT stringByAppendingFormat:@"/users/@me/guilds/%@/settings", key]];
    [req start];
}

-(id)muteConfigForDuration:(NSTimeInterval)duration muted:(BOOL)muted {
    if (!muted || duration <= 0) return [NSNull null];
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
    [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'.000Z'"];
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInteger:(NSInteger)duration], @"selected_time_window",
            [formatter stringFromDate:[NSDate dateWithTimeIntervalSinceNow:duration]], @"end_time", nil];
}

-(void)setMuted:(BOOL)muted duration:(NSTimeInterval)duration forServer:(DLServer *)server {
    if (!server || [server isEqual:[self myServerItem]] || ![server serverID]) return;
    NSDictionary *parameters = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSNumber numberWithBool:muted], @"muted",
                                [self muteConfigForDuration:duration muted:muted], @"mute_config", nil];
    [self patchNotificationSettings:parameters forServerKey:[self settingsKeyForServerID:[server serverID]]];
}

-(void)setMuted:(BOOL)muted duration:(NSTimeInterval)duration forChannel:(DLChannel *)channel {
    if (![channel channelID]) return;
    NSString *serverID = [channel isKindOfClass:[DLServerChannel class]] ? [(DLServerChannel *)channel serverID] : nil;
    NSDictionary *override = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithBool:muted], @"muted",
                              [self muteConfigForDuration:duration muted:muted], @"mute_config", nil];
    NSDictionary *parameters = [NSDictionary dictionaryWithObject:
                                [NSDictionary dictionaryWithObject:override forKey:[channel channelID]]
                                                           forKey:@"channel_overrides"];
    [self patchNotificationSettings:parameters forServerKey:[self settingsKeyForServerID:serverID]];
}

-(NSInteger)totalMentionCount {
    NSInteger total = 0;
    NSEnumerator *enumerator = [[loadedServers allValues] objectEnumerator];
    DLServer *server;
    while (server = [enumerator nextObject]) total += MAX(0, [server mentionCount]);
    return total;
}

-(NSArray *)relationships {
    return relationships ? relationships : [NSArray array];
}

-(NSString *)presenceStatusForUserID:(NSString *)userID {
    NSString *status = userID ? [friendPresences objectForKey:[userID description]] : nil;
    if ([status isEqualToString:@"online"] || [status isEqualToString:@"idle"] || [status isEqualToString:@"dnd"]) return status;
    return @"offline";
}

-(void)wsDidReceiveRelationships:(NSArray *)inRelationships presences:(NSArray *)presences {
    [relationships release];
    relationships = [inRelationships isKindOfClass:[NSArray class]] ? [inRelationships copy] : nil;
    if (!friendPresences) friendPresences = [[NSMutableDictionary alloc] init];
    [friendPresences removeAllObjects];
    if ([presences isKindOfClass:[NSArray class]]) {
        NSEnumerator *enumerator = [presences objectEnumerator];
        NSDictionary *presence;
        while (presence = [enumerator nextObject]) {
            if (![presence isKindOfClass:[NSDictionary class]]) continue;
            NSString *userID = [[[presence objectForKey:@"user"] objectForKey:@"id"] description];
            if (!userID) userID = [[presence objectForKey:@"user_id"] description];
            NSString *status = [presence objectForKey:@"status"];
            if (userID && [status isKindOfClass:[NSString class]]) [friendPresences setObject:status forKey:userID];
        }
    }
    if ([delegate respondsToSelector:@selector(relationshipsDidUpdate)]) [delegate relationshipsDidUpdate];
}

-(void)wsUserWithID:(NSString *)userID didUpdatePresenceStatus:(NSString *)status {
    if (!userID || ![status isKindOfClass:[NSString class]]) return;
    if (!friendPresences) friendPresences = [[NSMutableDictionary alloc] init];
    [friendPresences setObject:status forKey:userID];
    if ([delegate respondsToSelector:@selector(relationshipsDidUpdate)]) [delegate relationshipsDidUpdate];
}

-(void)wsDidReceiveUserData:(NSDictionary *)data {
    [myUser release];
    myUser = [[DLUser alloc] initWithDict:data];
}

-(void)wsDidReceiveUserSettingsData:(NSDictionary *)data {
    [myUserSettings release];
    myUserSettings = [[DLUserSettings alloc] initWithDict:data];
    [accountSettings release];
    accountSettings = [data isKindOfClass:[NSDictionary class]] ? [data mutableCopy] : nil;
}

-(NSDictionary *)accountSettings {
    return accountSettings;
}

-(void)updateAccountSettings:(NSDictionary *)changes {
    if (![changes count]) return;
    if (!accountSettings) accountSettings = [[NSMutableDictionary alloc] init];
    [accountSettings addEntriesFromDictionary:changes];
    [self sendAPIRequestWithMethod:@"PATCH" path:@"/users/@me/settings" body:changes completion:^(id json, NSInteger status) {
        if (status >= 200 && status < 300 && [json isKindOfClass:[NSDictionary class]]) {
            [accountSettings addEntriesFromDictionary:json];
        } else {
            NSLog(@"Account settings update failed (HTTP %ld)", (long)status);
        }
    }];
}

-(void)wsDidLoadAllDataAfterReconnection:(BOOL)didReconnect {
    // A reconnect flag from the WS layer only reflects that session's
    // history; on the first launch of an unstable network the READY still
    // comes after failed attempts and must populate the initial UI.
    if (didReconnect && !initialContentLoaded) {
        didReconnect = NO;
    }
    if (didReconnect) {
        if (selectedServer && selectedChannel) {
            if ([selectedServer isEqual:myServerItem]) {
                [[DLWSController sharedInstance] updateWSForDirectMessageChannel:selectedChannel];
            } else {
                [[DLWSController sharedInstance] updateWSForChannel:selectedChannel inServer:selectedServer];
            }
        }
        initialContentLoaded = YES;
    } else {
        [delegate initialDataWasReceived];
        initialContentLoaded = YES;
    }
}

-(void)wsDidAcknowledgeMessage:(DLMessage *)m {
    DLChannel *c = [self loadedChannelWithID:[m channelID]];
    DLServer *associatedServer = [self loadedServerWithID:[c serverID]];
    // Only this channel's mentions are read; the server keeps the others.
    [associatedServer setMentionCount:MAX(0, [associatedServer mentionCount] - [c mentionCount])];
    [c setMentionCount:0];
    [c setHasUnreadMessages:NO];
    
    NSEnumerator *e = [[loadedChannels allKeys] objectEnumerator];
    NSString *channelID;
    BOOL hasUnreads = NO;
    while (channelID = [e nextObject]) {
        DLChannel *channel = [loadedChannels objectForKey:channelID];
        if (channel) {
            if ([[channel serverID] isEqualToString:[c serverID]] && [channel hasUnreadMessages] &&
                ![self isChannelMuted:channel]) {
                hasUnreads = YES;
                break;
            }
        }
    }
    if (![associatedServer isEqual:[self myServerItem]]) {
        [associatedServer setHasUnreadMessages:hasUnreads];
    }
}

-(void)wsUserWithID:(NSString *)userID didStartTypingInServerWithID:(NSString *)serverID inChannelWithID:(NSString *)channelID withMemberData:(NSDictionary *)memberData {
    if ([channelID isEqualToString:[selectedChannel channelID]]) {
        DLServerMember *m = [[self loadedServerWithID:serverID] memberWithUserID:userID];
        if (!m) {
            m = [[DLServerMember alloc] initWithDict:memberData];
            [[self loadedServerWithID:serverID] addMember:m];
            [m autorelease];
        }
        DLUser *u = [m user];
        if (u && (![u isEqual:myUser])) {
            [u setTyping:YES];
            [delegate userDidStartTypingInSelectedChannel:u];
        }
    }
}
-(void)wsUserWithID:(NSString *)userID didStartTypingInDirectMessageChannelWithID:(NSString *)channelID {
    if ([channelID isEqualToString:[selectedChannel channelID]]) {
        DLUser *u = [selectedChannel recipientWithUserID:userID];
        if (u && (![u isEqual:myUser])) {
            [u setTyping:YES];
            [delegate userDidStartTypingInSelectedChannel:u];
        }
    }
}

-(void)wsDidReceiveMemberData:(NSArray *)memberData forServerWithID:(NSString *)serverID {
    NSMutableArray *members = [[NSMutableArray alloc] init];
    NSEnumerator *e = [memberData objectEnumerator];
    NSDictionary *memberDict;
    while (memberDict = [e nextObject]) {
        DLServerMember *m = [[DLServerMember alloc] initWithDict:memberDict];
        [members addObject:m];
        [m release];
    }
    [delegate members:members didUpdateForServer:[self loadedServerWithID:serverID]];
}
-(void)wsMessageWithID:(NSString *)messageID wasUpdatedWithData:(NSDictionary *)data {
    NSEnumerator *e = [loadedMessages objectEnumerator];
    DLMessage *m;
    while (m = [e nextObject]) {
        if ([[m messageID] isEqualToString:messageID]) {
            [m updateWithDict:data];
        }
    }
}
-(void)wsMessageWithID:(NSString *)messageID reactionEmoji:(NSDictionary *)emoji wasAdded:(BOOL)added byUserID:(NSString *)userID {
    NSEnumerator *e = [loadedMessages objectEnumerator];
    DLMessage *m;
    while (m = [e nextObject]) {
        if ([[m messageID] isEqualToString:messageID]) {
            BOOL currentUser = [[[self myUser] userID] isEqualToString:userID];
            [m applyReactionEmoji:emoji added:added byCurrentUser:currentUser];
            break;
        }
    }
}
-(void)wsMessageWithIDWasDeleted:(NSString *)messageID {
    DLMessage *msgToDelete = nil;
    NSEnumerator *e = [loadedMessages objectEnumerator];
    DLMessage *m;
    while (m = [e nextObject]) {
        if ([[m messageID] isEqualToString:messageID]) {
            msgToDelete = m;
            break;
        }
    }
    if (msgToDelete) {
        [msgToDelete remove];
        [loadedMessages removeObject:msgToDelete];
    }
}

@end
