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

-(void)setShouldUseSOCKSProxy:(BOOL)shouldUse;
-(void)setSOCKSProxyPort:(NSInteger)proxyPort;
-(void)setSOCKSProxyHost:(NSString *)proxyHost;
-(void)setSOCKSProxyRequiresPassword:(BOOL)requiresPassword;
-(void)setSOCKSProxyUsername:(NSString *)username;
-(void)setSOCKSProxyPassword:(NSString *)password;
-(void)setMessageDisplayScale:(CGFloat)scale;
-(void)setAppearanceTheme:(NSString *)theme;

@end
