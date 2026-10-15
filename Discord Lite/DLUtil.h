//
//  DLUtil.h
//  Discord Lite
//
//  Created by Collin Mistr on 10/27/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#include <sys/sysctl.h>
#import "BezierPathRoundedRect.h"
#import "NSString+Base64.h"
#import "CJSONSerializer.h"

@class DLServer;

@interface DLUtil : NSObject

+(NSImage *)imageResize:(NSImage*)anImage newSize:(NSSize)newSize cornerRadius:(CGFloat)radius;
+(NSString *)appVersionString;
+(NSString *)networkVersionString;
+(NSString *)kernelVersion;
+(NSString *)randomStringWithLength:(NSInteger)len;
+(NSString *)mimeTypeForExtension:(NSString *)ext;
+(NSString *)downloadsPath;
+(NSString *)generateSnowflake;
+(NSDate *)dateFromTimestampString:(NSString *)timestampString;
+(NSString *)userAgentString;
+(NSString *)superPropertiesString;
+(NSDictionary *)defaultHTTPPostHeaders;
+(NSString *)caBundlePath;
+(NSString *)URLPathEncodedString:(NSString *)string;

// Discord-inspired appearance shared by the legacy-compatible AppKit UI.
+(NSColor *)nativeServerRailColor;
+(NSColor *)nativeSidebarColor;
+(NSColor *)nativeContentColor;
+(NSColor *)nativeChromeColor;
+(NSColor *)nativeInputColor;
+(NSColor *)nativeBorderColor;
+(NSColor *)nativeScrollerKnobColor;
+(NSColor *)nativeUserPanelColor;
+(void)copyStringToPasteboard:(NSString *)string;
// Chat background of a named theme, for theme previews.
+(NSColor *)nativeContentColorForTheme:(NSString *)theme;
+(NSColor *)nativeOnlineStatusColor;
+(NSColor *)nativeOfflineStatusColor;
// Presence dot color for a Discord status string (online, idle, dnd, offline).
+(NSColor *)statusColorForPresenceStatus:(NSString *)status;
+(NSColor *)colorFromDiscordColorValue:(id)value;
+(NSColor *)roleColorForRoleIDs:(NSArray *)roleIDs inServer:(DLServer *)server;
+(NSColor *)nativeHeaderTopColor;
+(NSColor *)nativeHeaderBottomColor;
+(NSColor *)nativePrimaryTextColor;
+(NSColor *)nativeSecondaryTextColor;
+(NSColor *)nativeSelectionColor;
+(NSColor *)nativeSelectedTextColor;
+(NSColor *)nativeMentionColor;
+(NSColor *)nativeTagColor;
+(NSColor *)nativeLinkColor;

@end
