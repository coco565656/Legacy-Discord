//
//  DLController.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/25/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLController.h"
#import <Security/Security.h>

static const char *DLKeychainService = "org.legacydiscord.client";
static const char *DLKeychainAccount = "discord-user-token";

@interface DLController ()
-(NSString *)tokenFromKeychain;
-(void)storeTokenInKeychain:(NSString *)newToken;
-(void)deleteTokenFromKeychain;
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
    [self loadUserDefaults];
    return self;
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
    selectedChannel = c;
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
    NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
                           (id)kSecClassGenericPassword, (id)kSecClass,
                           [NSString stringWithUTF8String:DLKeychainService], (id)kSecAttrService,
                           [NSString stringWithUTF8String:DLKeychainAccount], (id)kSecAttrAccount,
                           [NSNumber numberWithBool:YES], (id)kSecReturnData,
                           (id)kSecMatchLimitOne, (id)kSecMatchLimit,
                           nil];
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) {
        if (status != errSecItemNotFound) {
            NSLog(@"Unable to read saved Discord session from Keychain (OSStatus %ld).", (long)status);
        }
        return nil;
    }

    NSData *passwordData = (NSData *)result;
    NSString *storedToken = [[[NSString alloc] initWithData:passwordData
                                                   encoding:NSUTF8StringEncoding] autorelease];
    CFRelease(result);
    return storedToken;
}

-(void)storeTokenInKeychain:(NSString *)newToken {
    NSData *tokenData = [newToken dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
                           (id)kSecClassGenericPassword, (id)kSecClass,
                           [NSString stringWithUTF8String:DLKeychainService], (id)kSecAttrService,
                           [NSString stringWithUTF8String:DLKeychainAccount], (id)kSecAttrAccount,
                           nil];
    NSDictionary *changes = [NSDictionary dictionaryWithObject:tokenData forKey:(id)kSecValueData];
    OSStatus status = SecItemUpdate((CFDictionaryRef)query, (CFDictionaryRef)changes);
    if (status == errSecSuccess) {
        return;
    }

    if (status != errSecItemNotFound) {
        NSLog(@"Unable to update Discord session in Keychain (OSStatus %ld).", (long)status);
        return;
    }

    NSMutableDictionary *newItem = [NSMutableDictionary dictionaryWithDictionary:query];
    [newItem setObject:tokenData forKey:(id)kSecValueData];
    OSStatus addStatus = SecItemAdd((CFDictionaryRef)newItem, NULL);
    if (addStatus != errSecSuccess) {
        NSLog(@"Unable to save Discord session in Keychain (OSStatus %ld).", (long)addStatus);
    }
}

-(void)deleteTokenFromKeychain {
    NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
                           (id)kSecClassGenericPassword, (id)kSecClass,
                           [NSString stringWithUTF8String:DLKeychainService], (id)kSecAttrService,
                           [NSString stringWithUTF8String:DLKeychainAccount], (id)kSecAttrAccount,
                           nil];
    OSStatus status = SecItemDelete((CFDictionaryRef)query);
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
    return [[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:token, [DLUtil superPropertiesString], nil] forKeys:[NSArray arrayWithObjects:@"Authorization", @"X-Super-Properties", nil]] autorelease];
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

-(void)getAuthFingerprint {
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setHeaders:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[DLUtil superPropertiesString], nil] forKeys:[NSArray arrayWithObjects:@"X-Super-Properties", nil]]];
    [req setIdentifier:RequestIDGetFingerprint];
    [req setUrl:[@API_ROOT stringByAppendingString:@"/auth/fingerprint"]];
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
    NSString *requestURL = [@API_ROOT stringByAppendingString:[NSString stringWithFormat:@"/channels/%@/messages?limit=%ld", c.channelID, numMsgs]];
    if (m != nil) {
        requestURL = [requestURL stringByAppendingString:[NSString stringWithFormat:@"&before=%@", m.messageID]];
    }
    [req setUrl:requestURL];
    [req start];
}

-(void)sendMessage:(DLMessage *)m toChannel:(DLChannel *)c {
    AsyncHTTPPostRequest *req = [[AsyncHTTPPostRequest alloc] init];
    [req setDelegate:self];
    [req setParameters:[m dictRepresentation]];
    if ([m attachments].count > 0) {
        NSMutableDictionary *files = [[NSMutableDictionary alloc] init];
        NSEnumerator *e = [[m attachments] objectEnumerator];
        DLAttachment *a;
        while (a = [e nextObject]) {
            [files setObject:[a attachmentData] forKey:[a filename]];
        }
        [req setFiles:files];
    }
    [req setHeaders:[self requestHeaders]];
    [req setIdentifier:RequestIDSendMessage];
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
-(NSArray *)channelsForServer:(DLServer *)s {
    [selectedServer release];
    [s retain];
    selectedServer = s;
    [selectedChannel release];
    selectedChannel = nil;
    NSMutableArray *channels = [[NSMutableArray alloc] init];
    
    NSEnumerator *e = [[loadedChannels allKeys] objectEnumerator];
    NSString *channelKey;
    while (channelKey = [e nextObject]) {
        DLServerChannel *c = [loadedChannels objectForKey:channelKey];
        if ([[c serverID] isEqualToString:[s serverID]]) {
            [channels addObject:c];
        }
    }
    
    NSMutableArray *parentChannels = [[NSMutableArray alloc] init];
    NSMutableArray *uncategorizedChannels = [[NSMutableArray alloc] init];
    NSMutableArray *childChannels = [[NSMutableArray alloc] init];
    
    e = [channels objectEnumerator];
    DLServerChannel *c;
    while (c = [e nextObject]) {
        if (c.type == ChannelTypeHeader) {
            [parentChannels addObject:c];
        } else if (!c.parentID || [c.parentID isEqual:[NSNull null]]) {
            [uncategorizedChannels addObject:c];
            
        } else {
            [childChannels addObject:c];
        }
    }
    
    NSMutableArray *sortedParentChannels = [NSMutableArray arrayWithArray:[parentChannels sortedArrayUsingSelector:@selector(compare:)]];
    NSArray *sortedChildChannels = [childChannels sortedArrayUsingSelector:@selector(compare:)];
    NSArray *sortedUncategorizedChannels = [uncategorizedChannels sortedArrayUsingSelector:@selector(compare:)];
    
    
    
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
    
    e = [sortedUncategorizedChannels objectEnumerator];
    while (c = [e nextObject]) {
        if (c) {
            [sortedParentChannels insertObject:c atIndex:0];
        }
    }
    
    [channels release];
    [uncategorizedChannels release];
    [childChannels release];
    [parentChannels release];
    return sortedParentChannels;
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
        [myServerItem setName:@"Direct Messages"];
    }
    return myServerItem;
}

-(NSString *)authFingerprint {
    return authFingerprint;
}

-(void)queryServer:(DLServer *)s forMembersContainingUsername:(NSString *)username {
    [[DLWSController sharedInstance] queryServer:s forMembersContainingUsername:username];
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
        [delegate messages:newMessages receivedForChannel:selectedChannel];
        [newMessages release];
    } else {
        [self handleHTTPRequestError:req];
    }
}

-(void)handleSendMessageRequestResponse:(AsyncHTTPRequest *)req {
    if ([req result] != HTTPResultOK) {
        [self handleHTTPRequestError:req];
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
    }
    [loadedServers setObject:[self myServerItem] forKey:[[self myServerItem] serverID]];
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
                    if (![associatedServer isEqual:[self myServerItem]]) {
                        [associatedServer setHasUnreadMessages:YES];
                    }
                }
            }
        }
    }
}

-(void)wsDidReceiveUserData:(NSDictionary *)data {
    [myUser release];
    myUser = [[DLUser alloc] initWithDict:data];
}

-(void)wsDidReceiveUserSettingsData:(NSDictionary *)data {
    [myUserSettings release];
    myUserSettings = [[DLUserSettings alloc] initWithDict:data];
}

-(void)wsDidLoadAllDataAfterReconnection:(BOOL)didReconnect {
    if (didReconnect) {
        if (selectedServer && selectedChannel) {
            if ([selectedServer isEqual:myServerItem]) {
                [[DLWSController sharedInstance] updateWSForDirectMessageChannel:selectedChannel];
            } else {
                [[DLWSController sharedInstance] updateWSForChannel:selectedChannel inServer:selectedServer];
            }
        }
    } else {
        [delegate initialDataWasReceived];
    }
}

-(void)wsDidAcknowledgeMessage:(DLMessage *)m {
    DLChannel *c = [self loadedChannelWithID:[m channelID]];
    DLServer *associatedServer = [self loadedServerWithID:[c serverID]];
    [associatedServer setMentionCount:0];
    [c setMentionCount:0];
    [c setHasUnreadMessages:NO];
    
    NSEnumerator *e = [[loadedChannels allKeys] objectEnumerator];
    NSString *channelID;
    BOOL hasUnreads = NO;
    while (channelID = [e nextObject]) {
        DLChannel *channel = [loadedChannels objectForKey:channelID];
        if (channel) {
            if ([[channel serverID] isEqualToString:[c serverID]] && [channel hasUnreadMessages]) {
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
