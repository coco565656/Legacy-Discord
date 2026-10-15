//
//  DLPreferencesHandler.h
//  Discord Lite
//
//  Created by Collin Mistr on 8/22/22.
//  Copyright (c) 2022 dosdude1. All rights reserved.
//

#import <Foundation/Foundation.h>

#define kShouldUseSOCKSProxy "UseSOCKSProxy"
#define kSOCKSProxyPort "SOCKSProxyPort"
#define kSOCKSProxyHost "SOCKSProxyHost"
#define kSOCKSProxyRequiresPassword "SOCKSRequiresPassword"
#define kSOCKSProxyUsername "SOCKSUsername"
#define kSOCKSProxyPassword "SOCKSPassword"
#define kMessageDisplayScale "MessageDisplayScale"
#define kAppearanceTheme "AppearanceTheme"
#define DLMessageDisplayScaleDidChangeNotification @"DLMessageDisplayScaleDidChangeNotification"
#define DLAppearanceThemeDidChangeNotification @"DLAppearanceThemeDidChangeNotification"
#define kChatFontSize "ChatFontSize"
#define kShowRoleColors "ShowRoleColors"
#define kAutoplayAnimatedEmoji "AutoplayAnimatedEmoji"
#define kShowReactions "ShowReactions"
#define kShowEmbeds "ShowEmbeds"
#define kPlayMentionSound "PlayMentionSound"
#define kDeveloperMode "DeveloperMode"
// Posted when a setting that changes how messages are rendered is changed.
// Observers re-render messages and lists; the object is the handler.
#define DLChatDisplayPreferencesDidChangeNotification @"DLChatDisplayPreferencesDidChangeNotification"

@interface DLPreferencesHandler : NSObject

+(DLPreferencesHandler *)sharedInstance;

-(BOOL)shouldUseSOCKSProxy;
-(NSInteger)SOCKSProxyPort;
-(NSString *)SOCKSProxyHost;
-(BOOL)SOCKSProxyRequiresPassword;
-(NSString *)SOCKSProxyUsername;
-(NSString *)SOCKSProxyPassword;
-(CGFloat)messageDisplayScale;
-(NSString *)appearanceTheme;
// Base message text size in points before the display scale is applied.
-(CGFloat)chatFontSize;
-(BOOL)showRoleColors;
-(BOOL)autoplayAnimatedEmoji;
-(BOOL)showReactions;
-(BOOL)showEmbeds;
-(BOOL)playMentionSound;
-(BOOL)developerMode;

-(void)setShouldUseSOCKSProxy:(BOOL)shouldUse;
-(void)setSOCKSProxyPort:(NSInteger)proxyPort;
-(void)setSOCKSProxyHost:(NSString *)proxyHost;
-(void)setSOCKSProxyRequiresPassword:(BOOL)requiresPassword;
-(void)setSOCKSProxyUsername:(NSString *)username;
-(void)setSOCKSProxyPassword:(NSString *)password;
-(void)setMessageDisplayScale:(CGFloat)scale;
-(void)setAppearanceTheme:(NSString *)theme;
-(void)setChatFontSize:(CGFloat)size;
-(void)setShowRoleColors:(BOOL)show;
-(void)setAutoplayAnimatedEmoji:(BOOL)autoplay;
-(void)setShowReactions:(BOOL)show;
-(void)setShowEmbeds:(BOOL)show;
-(void)setPlayMentionSound:(BOOL)play;
-(void)setDeveloperMode:(BOOL)enabled;

@end
