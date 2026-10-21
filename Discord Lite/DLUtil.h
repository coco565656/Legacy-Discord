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
// Official message time: "Today at 22:54", "Yesterday at 22:54", else the
// locale's short date (four-digit year) and time.
+(NSString *)discordTimestampStringForDate:(NSDate *)date;
// Creation time encoded in a Discord ID.
+(NSDate *)dateFromSnowflake:(NSString *)snowflake;
+(NSString *)userAgentString;
+(NSString *)superPropertiesString;
// The client description shared by X-Super-Properties and the gateway
// IDENTIFY "properties" (they must always match).
+(NSDictionary *)clientProperties;
// Fetches the web client's current build number (at most once a day).
+(void)refreshClientBuildNumber;
+(NSDictionary *)defaultHTTPPostHeaders;
+(NSString *)caBundlePath;
// CA bundle including the macOS Keychain trusted anchors (AquaProxy and
// similar local MITM proxies install their root certificate there).
+(NSString *)effectiveCAPath;
// CA file for a URL: the bundled set only for Discord's hosts (so an
// intercepting proxy cannot read or rewrite Discord traffic), else
// effectiveCAPath.
+(NSString *)caPathForURL:(NSString *)url;
+(BOOL)isDiscordHost:(NSString *)host;
// Honor the system Proxy settings (10.6 Network > Advanced > Proxies), which
// AquaProxy configures. curlHandle is a CURL * to keep this header curl-free.
+(void)applySystemProxyToCurlHandle:(void *)curlHandle url:(NSString *)url;
// YES when a system proxy would carry connections to this host.
+(BOOL)systemProxyServesHost:(NSString *)host;
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
+(NSColor *)nativeHoverColor;
+(NSColor *)nativeMentionColor;
+(NSColor *)nativeTagColor;
+(NSColor *)nativeLinkColor;

@end
