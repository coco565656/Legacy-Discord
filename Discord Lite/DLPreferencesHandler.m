//
//  DLPreferencesHandler.m
//  Discord Lite
//
//  Created by Collin Mistr on 8/22/22.
//  Copyright (c) 2022 dosdude1. All rights reserved.
//

#import "DLPreferencesHandler.h"

@implementation DLPreferencesHandler

static DLPreferencesHandler* sharedObject = nil;

-(id)init {
    self = [super init];
    return self;
}

+(DLPreferencesHandler *)sharedInstance {
    if (!sharedObject) {
        sharedObject = [[[super allocWithZone: NULL] init] retain];
    }
    return sharedObject;
}

-(BOOL)shouldUseSOCKSProxy {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@kShouldUseSOCKSProxy];
}
-(NSInteger)SOCKSProxyPort {
    return [[NSUserDefaults standardUserDefaults] integerForKey:@kSOCKSProxyPort];
}
-(NSString *)SOCKSProxyHost {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@kSOCKSProxyHost];
}
-(BOOL)SOCKSProxyRequiresPassword {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@kSOCKSProxyRequiresPassword];
}
-(NSString *)SOCKSProxyUsername {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@kSOCKSProxyUsername];
}
-(NSString *)SOCKSProxyPassword {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@kSOCKSProxyPassword];
}
-(CGFloat)messageDisplayScale {
    CGFloat scale = [[NSUserDefaults standardUserDefaults] floatForKey:@kMessageDisplayScale];
    return scale >= 0.8 && scale <= 1.25 ? scale : 0.9;
}
-(NSString *)appearanceTheme {
    NSString *theme = [[NSUserDefaults standardUserDefaults] stringForKey:@kAppearanceTheme];
    if ([theme isEqualToString:@"midnight"] || [theme isEqualToString:@"aurora"]) {
        return theme;
    }
    return @"default";
}

-(void)setShouldUseSOCKSProxy:(BOOL)shouldUse {
    [[NSUserDefaults standardUserDefaults] setBool:shouldUse forKey:@kShouldUseSOCKSProxy];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
-(void)setSOCKSProxyPort:(NSInteger)proxyPort {
    [[NSUserDefaults standardUserDefaults] setInteger:proxyPort forKey:@kSOCKSProxyPort];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
-(void)setSOCKSProxyHost:(NSString *)proxyHost {
    [[NSUserDefaults standardUserDefaults] setObject:proxyHost forKey:@kSOCKSProxyHost];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
-(void)setSOCKSProxyRequiresPassword:(BOOL)requiresPassword {
    [[NSUserDefaults standardUserDefaults] setBool:requiresPassword forKey:@kSOCKSProxyRequiresPassword];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
-(void)setSOCKSProxyUsername:(NSString *)username {
    [[NSUserDefaults standardUserDefaults] setObject:username forKey:@kSOCKSProxyUsername];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
-(void)setSOCKSProxyPassword:(NSString *)password {
    [[NSUserDefaults standardUserDefaults] setObject:password forKey:@kSOCKSProxyPassword];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
-(void)setMessageDisplayScale:(CGFloat)scale {
    scale = MAX(0.8, MIN(1.25, scale));
    [[NSUserDefaults standardUserDefaults] setFloat:scale forKey:@kMessageDisplayScale];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:DLMessageDisplayScaleDidChangeNotification object:self];
}
-(void)setAppearanceTheme:(NSString *)theme {
    if (![theme isEqualToString:@"midnight"] && ![theme isEqualToString:@"aurora"]) {
        theme = @"default";
    }
    [[NSUserDefaults standardUserDefaults] setObject:theme forKey:@kAppearanceTheme];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:DLAppearanceThemeDidChangeNotification object:self];
}

@end
