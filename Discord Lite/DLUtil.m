//
//  DLUtil.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/27/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLUtil.h"
#import "DLLocalization.h"
#import "DLServer.h"
#import "DLPreferencesHandler.h"
#import "DLThemes.h"

@implementation DLUtil

static NSDictionary *superPropertiesDict;

+(NSImage *)imageResize:(NSImage*)anImage newSize:(NSSize)newSize cornerRadius:(CGFloat)radius {
    if (!anImage || [anImage size].width <= 0.0 || [anImage size].height <= 0.0 ||
        newSize.width <= 0.0 || newSize.height <= 0.0) {
        return nil;
    }
    [anImage setScalesWhenResized:YES];
    NSImage *smallImage = [[NSImage alloc] initWithSize: newSize];
    [smallImage lockFocus];
    [anImage setSize: newSize];
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    if (radius != 0) {
        NSBezierPath *clipPath = [BezierPathRoundedRect bezierPathWithRoundedRect:NSMakeRect(0, 0, anImage.size.width, anImage.size.height) radius:radius];
        [clipPath setWindingRule:NSEvenOddWindingRule];
        [clipPath addClip];
    }
    [anImage drawAtPoint:NSZeroPoint fromRect:NSMakeRect(0, 0, newSize.width, newSize.height) operation:NSCompositeSourceOver fraction:1.0];
    [smallImage unlockFocus];
    return [smallImage autorelease];
}
+(NSString *)appVersionString {
    return [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"];
}
+(NSString *)networkVersionString {
    return [[NSBundle bundleWithIdentifier:@"com.apple.CFNetwork"] objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey];
}
+(NSString *)kernelVersion {
    size_t size = 0;
    int mib[] = {CTL_KERN, KERN_OSRELEASE};
    sysctl(mib, sizeof mib / sizeof(int), NULL, &size, NULL, 0);
    if (size > 0) {
        char *str = malloc(size);
        sysctl(mib, sizeof mib / sizeof(int), str, &size, NULL, 0);
        NSString *ret = [[NSString stringWithUTF8String:str] retain];
        free(str);
        return [ret autorelease];
    }
    return @"";
}
+(NSString *)randomStringWithLength:(NSInteger)len {
    NSMutableString *randomString = [NSMutableString stringWithCapacity: len];
    for (int i=0; i<len; i++) {
        [randomString appendFormat: @"%d", arc4random() % 10];
    }
    
    return randomString;
}
+(NSString *)mimeTypeForExtension:(NSString *)ext {
    NSString *UTI = [(NSString*)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)ext, NULL) autorelease];
    NSString *mimeType = [(NSString*)UTTypeCopyPreferredTagWithClass((CFStringRef)UTI, kUTTagClassMIMEType) autorelease];
    if (!mimeType) {
        mimeType = @"application/octet-stream";
    }
    return mimeType;
}
+(NSString *)downloadsPath {
    if ([[NSFileManager defaultManager] fileExistsAtPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"]]) {
        return [NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"];
    }
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Desktop"];
}
+(NSString *)generateSnowflake {
    NSTimeInterval date = [[NSDate date] timeIntervalSince1970];
    long snowflake = (((long)date * 1000) - 1420070400000) * 4194304;
    return [NSString stringWithFormat:@"%ld", snowflake];
}
+(NSDate *)dateFromSnowflake:(NSString *)snowflake {
    unsigned long long value = strtoull([snowflake UTF8String], NULL, 10);
    if (value == 0) return nil;
    return [NSDate dateWithTimeIntervalSince1970:((value >> 22) + 1420070400000ULL) / 1000.0];
}

+(NSString *)discordTimestampStringForDate:(NSDate *)date {
    if (!date) return @"";
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *comps = [cal components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit) fromDate:[NSDate date]];
    NSDate *today = [cal dateFromComponents:comps];
    NSDateComponents *components = [[[NSDateComponents alloc] init] autorelease];
    [components setDay:-1];
    NSDate *yesterday = [cal dateByAddingComponents:components toDate:today options:0];
    NSDateFormatter *timeFormatter = [[[NSDateFormatter alloc] init] autorelease];
    [timeFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
    [timeFormatter setDateStyle:NSDateFormatterNoStyle];
    [timeFormatter setTimeStyle:NSDateFormatterShortStyle];
    if ([date isGreaterThan:today]) {
        return [DLLocalizedString(@"Today at ") stringByAppendingString:[timeFormatter stringFromDate:date]];
    }
    if ([date isGreaterThan:yesterday]) {
        return [DLLocalizedString(@"Yesterday at ") stringByAppendingString:[timeFormatter stringFromDate:date]];
    }
    NSDateFormatter *fullFormatter = [[[NSDateFormatter alloc] init] autorelease];
    [fullFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
    // 10.6's short style uses "yy" and its templates produce 年月日 forms, so
    // only the year is widened.
    [fullFormatter setDateStyle:NSDateFormatterShortStyle];
    NSString *format = [fullFormatter dateFormat];
    if (format && [format rangeOfString:@"yyyy"].location == NSNotFound && [format rangeOfString:@"yy"].location != NSNotFound) {
        [fullFormatter setDateFormat:[format stringByReplacingOccurrencesOfString:@"yy" withString:@"yyyy"]];
    }
    return [NSString stringWithFormat:@"%@ %@", [fullFormatter stringFromDate:date], [timeFormatter stringFromDate:date]];
}

+(NSDate *)dateFromTimestampString:(NSString *)timestampString {
    if ([timestampString rangeOfString:@"."].location != NSNotFound) {
        timestampString = [timestampString substringToIndex:[timestampString rangeOfString:@"."].location];
    } else {
        timestampString = [timestampString substringToIndex:[timestampString rangeOfString:@"+"].location];
    }
    timestampString = [timestampString stringByAppendingString:@"+0000"];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setFormatterBehavior:NSDateFormatterBehavior10_4];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];
    NSDate *date = [formatter dateFromString:timestampString];
    [formatter release];
    return date;
}
+(NSString *)userAgentString {
    return @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) discord/0.0.326 Chrome/128.0.6613.186 Electron/32.2.2 Safari/537.36";
}
+(NSString *)superPropertiesString {
    if (!superPropertiesDict) {
        superPropertiesDict = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:@"Mac OS X", @"Discord Client", @"stable", @"0.0.326", [DLUtil kernelVersion], @"x64", @"x64", @"en-US", [self userAgentString], @"32.2.2", @"23", @"209354", [NSNull null], [NSNull null], nil] forKeys:[NSArray arrayWithObjects:@"os", @"browser", @"release_channel", @"client_version", @"os_version", @"os_arch", @"app_arch", @"system_locale", @"browser_user_agent", @"browser_version", @"os_sdk_version", @"client_build_number", @"native_build_number", @"client_event_source", nil]];
    }
    NSData *serializedData = [[CJSONSerializer serializer] serializeDictionary:superPropertiesDict error:nil];
    return [NSString encodeBase64WithData:serializedData];
}
+(NSDictionary *)defaultHTTPPostHeaders {
    NSDictionary *headers = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:@"en-US,en;q=0.5", @"en-US", @"America/New_York", @"bugReporterEnabled", @"https://discord.com", @"1", @"1", @"keep-alive", @"https://discord.com/login?redirect_to=%2Flogin", @"empty", @"cors", @"same-origin", @"u=0", @"trailers", nil] forKeys:[NSArray arrayWithObjects:@"Accept-Language", @"X-Discord-Locale", @"X-Discord-Timezone", @"X-Debug-Options", @"Origin", @"DNT", @"Sec-GPC", @"Connection", @"Referer", @"Sec-Fetch-Dest", @"Sec-Fetch-Mode", @"Sec-Fetch-Site", @"Priority", @"TE", nil]];
    return [headers autorelease];
}
+(NSString *)caBundlePath {
    return [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
}
+(NSString *)URLPathEncodedString:(NSString *)string {
    CFStringRef escaped = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                  (CFStringRef)string,
                                                                  NULL,
                                                                  CFSTR(":/?#[]@!$&'()*+,;="),
                                                                  kCFStringEncodingUTF8);
    return [(NSString *)escaped autorelease];
}

+(NSColor *)nativeServerRailColor {
    if ([DLThemes isGradientThemeActive]) return [DLThemes colorForSurface:DLThemeSurfaceLowest];
    NSString *theme = [[DLPreferencesHandler sharedInstance] appearanceTheme];
    if ([theme isEqualToString:@"midnight"]) return [NSColor colorWithCalibratedRed:0.055 green:0.059 blue:0.075 alpha:1.0];
    if ([theme isEqualToString:@"aurora"]) return [NSColor colorWithCalibratedRed:0.075 green:0.094 blue:0.110 alpha:1.0];
    return [NSColor colorWithCalibratedRed:0.118 green:0.122 blue:0.133 alpha:1.0];
}
+(NSColor *)nativeSidebarColor {
    if ([DLThemes isGradientThemeActive]) return [DLThemes colorForSurface:DLThemeSurfaceLower];
    NSString *theme = [[DLPreferencesHandler sharedInstance] appearanceTheme];
    if ([theme isEqualToString:@"midnight"]) return [NSColor colorWithCalibratedRed:0.090 green:0.098 blue:0.125 alpha:1.0];
    if ([theme isEqualToString:@"aurora"]) return [NSColor colorWithCalibratedRed:0.105 green:0.145 blue:0.145 alpha:1.0];
    return [NSColor colorWithCalibratedRed:0.169 green:0.176 blue:0.192 alpha:1.0];
}
+(NSColor *)nativeContentColor {
    if ([DLThemes isGradientThemeActive]) return [DLThemes colorForSurface:DLThemeSurfaceChat];
    return [self nativeContentColorForTheme:[[DLPreferencesHandler sharedInstance] appearanceTheme]];
}
+(NSColor *)nativeContentColorForTheme:(NSString *)theme {
    if ([theme isEqualToString:@"midnight"]) return [NSColor colorWithCalibratedRed:0.115 green:0.122 blue:0.153 alpha:1.0];
    if ([theme isEqualToString:@"aurora"]) return [NSColor colorWithCalibratedRed:0.125 green:0.180 blue:0.170 alpha:1.0];
    return [NSColor colorWithCalibratedRed:0.192 green:0.200 blue:0.220 alpha:1.0];
}
+(NSColor *)nativeChromeColor {
    return [self nativeSidebarColor];
}
+(NSColor *)nativeInputColor {
    if ([DLThemes isGradientThemeActive]) return [DLThemes colorForSurface:DLThemeSurfaceHigher];
    NSString *theme = [[DLPreferencesHandler sharedInstance] appearanceTheme];
    if ([theme isEqualToString:@"midnight"]) return [NSColor colorWithCalibratedRed:0.145 green:0.153 blue:0.188 alpha:1.0];
    if ([theme isEqualToString:@"aurora"]) return [NSColor colorWithCalibratedRed:0.165 green:0.225 blue:0.205 alpha:1.0];
    return [NSColor colorWithCalibratedRed:0.220 green:0.227 blue:0.247 alpha:1.0];
}
+(NSColor *)nativeBorderColor {
    if ([DLThemes isGradientThemeActive]) return [DLThemes colorForSurface:DLThemeSurfaceBorder];
    NSString *theme = [[DLPreferencesHandler sharedInstance] appearanceTheme];
    if ([theme isEqualToString:@"midnight"]) return [NSColor colorWithCalibratedRed:0.045 green:0.047 blue:0.063 alpha:1.0];
    if ([theme isEqualToString:@"aurora"]) return [NSColor colorWithCalibratedRed:0.060 green:0.110 blue:0.105 alpha:1.0];
    return [NSColor colorWithCalibratedRed:0.125 green:0.129 blue:0.141 alpha:1.0];
}
+(NSColor *)nativeScrollerKnobColor {
    if ([DLThemes isGradientThemeActive]) return [DLThemes colorForSurface:DLThemeSurfaceHighest];
    NSString *theme = [[DLPreferencesHandler sharedInstance] appearanceTheme];
    if ([theme isEqualToString:@"midnight"]) return [NSColor colorWithCalibratedRed:0.035 green:0.038 blue:0.050 alpha:1.0];
    if ([theme isEqualToString:@"aurora"]) return [NSColor colorWithCalibratedRed:0.045 green:0.075 blue:0.072 alpha:1.0];
    return [NSColor colorWithCalibratedRed:0.102 green:0.106 blue:0.118 alpha:1.0];
}
+(void)copyStringToPasteboard:(NSString *)string {
    if (![string length]) return;
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [pasteboard setString:string forType:NSStringPboardType];
}
// The account panel under the channel list is one step darker than the sidebar.
+(NSColor *)nativeUserPanelColor {
    if ([DLThemes isGradientThemeActive]) return [DLThemes colorForSurface:DLThemeSurfaceLow];
    NSString *theme = [[DLPreferencesHandler sharedInstance] appearanceTheme];
    if ([theme isEqualToString:@"midnight"]) return [NSColor colorWithCalibratedRed:0.072 green:0.078 blue:0.102 alpha:1.0];
    if ([theme isEqualToString:@"aurora"]) return [NSColor colorWithCalibratedRed:0.088 green:0.122 blue:0.122 alpha:1.0];
    return [NSColor colorWithCalibratedRed:0.137 green:0.141 blue:0.157 alpha:1.0];
}
+(NSColor *)nativeOnlineStatusColor {
    return [NSColor colorWithCalibratedRed:0.137 green:0.647 blue:0.353 alpha:1.0];
}
+(NSColor *)nativeOfflineStatusColor {
    return [NSColor colorWithCalibratedRed:0.502 green:0.518 blue:0.557 alpha:1.0];
}
+(NSColor *)statusColorForPresenceStatus:(NSString *)status {
    if ([status isEqualToString:@"online"]) return [self nativeOnlineStatusColor];
    if ([status isEqualToString:@"idle"]) return [NSColor colorWithCalibratedRed:0.941 green:0.698 blue:0.196 alpha:1.0];
    if ([status isEqualToString:@"dnd"]) return [NSColor colorWithCalibratedRed:0.949 green:0.247 blue:0.263 alpha:1.0];
    return [self nativeOfflineStatusColor];
}
// Discord stores colors as 0xRRGGBB integers; 0 means "no color".
+(NSColor *)colorFromDiscordColorValue:(id)value {
    if (![value isKindOfClass:[NSNumber class]]) return nil;
    unsigned long color = [value unsignedLongValue];
    if (color == 0) return nil;
    return [NSColor colorWithCalibratedRed:((color >> 16) & 0xff) / 255.0
                                     green:((color >> 8) & 0xff) / 255.0
                                      blue:(color & 0xff) / 255.0 alpha:1.0];
}
// The displayed name color is the color of the highest-positioned role that
// has one, matching the official client. Returns nil when no role is colored.
+(NSColor *)roleColorForRoleIDs:(NSArray *)roleIDs inServer:(DLServer *)server {
    if (![[DLPreferencesHandler sharedInstance] showRoleColors]) return nil;
    if (![roleIDs isKindOfClass:[NSArray class]] || !server) return nil;
    NSColor *bestColor = nil;
    NSInteger bestPosition = NSIntegerMin;
    NSEnumerator *enumerator = [roleIDs objectEnumerator];
    id roleID;
    while (roleID = [enumerator nextObject]) {
        NSDictionary *role = [server roleWithID:[roleID description]];
        NSColor *color = [self colorFromDiscordColorValue:[role objectForKey:@"color"]];
        if (!color) continue;
        id positionValue = [role objectForKey:@"position"];
        NSInteger position = [positionValue isKindOfClass:[NSNumber class]] ? [positionValue integerValue] : 0;
        if (position >= bestPosition) {
            bestPosition = position;
            bestColor = color;
        }
    }
    return bestColor;
}
+(NSColor *)nativeHeaderTopColor {
    if ([DLThemes isGradientThemeActive]) return [DLThemes colorForSurface:DLThemeSurfaceChat];
    if ([[[DLPreferencesHandler sharedInstance] appearanceTheme] isEqualToString:@"aurora"]) {
        return [NSColor colorWithCalibratedRed:0.105 green:0.175 blue:0.155 alpha:1.0];
    }
    return [self nativeContentColor];
}
+(NSColor *)nativeHeaderBottomColor {
    if ([DLThemes isGradientThemeActive]) return [DLThemes colorForSurface:DLThemeSurfaceChat];
    if ([[[DLPreferencesHandler sharedInstance] appearanceTheme] isEqualToString:@"aurora"]) {
        return [NSColor colorWithCalibratedRed:0.145 green:0.170 blue:0.235 alpha:1.0];
    }
    return [self nativeContentColor];
}
+(NSColor *)nativePrimaryTextColor {
    if ([DLThemes isGradientThemeActive]) return [DLThemes primaryTextColor];
    return [NSColor colorWithCalibratedRed:0.949 green:0.953 blue:0.961 alpha:1.0];
}
+(NSColor *)nativeSecondaryTextColor {
    if ([DLThemes isGradientThemeActive]) return [DLThemes secondaryTextColor];
    return [NSColor colorWithCalibratedRed:0.710 green:0.729 blue:0.757 alpha:1.0];
}
+(NSColor *)nativeSelectionColor {
    if ([DLThemes isGradientThemeActive]) return [DLThemes colorForSurface:DLThemeSurfaceSelected];
    NSString *theme = [[DLPreferencesHandler sharedInstance] appearanceTheme];
    if ([theme isEqualToString:@"midnight"]) return [NSColor colorWithCalibratedRed:0.200 green:0.210 blue:0.270 alpha:1.0];
    if ([theme isEqualToString:@"aurora"]) return [NSColor colorWithCalibratedRed:0.205 green:0.315 blue:0.285 alpha:1.0];
    return [NSColor colorWithCalibratedRed:0.251 green:0.259 blue:0.286 alpha:1.0];
}
// Row and card hover: a solid color (or the gradient pattern) a step lighter
// than the list it is drawn on.
+(NSColor *)nativeHoverColor {
    if ([DLThemes isGradientThemeActive]) return [DLThemes colorForSurface:DLThemeSurfaceHover];
    return [[self nativeSelectionColor] blendedColorWithFraction:0.45 ofColor:[self nativeSidebarColor]];
}
+(NSColor *)nativeSelectedTextColor {
    if ([DLThemes isGradientThemeActive]) return [DLThemes primaryTextColor];
    return [NSColor colorWithCalibratedRed:0.949 green:0.953 blue:0.961 alpha:1.0];
}
+(NSColor *)nativeMentionColor {
    // Light Nitro themes: the light-theme mention colors.
    if ([DLThemes isLightThemeActive]) return [NSColor colorWithCalibratedRed:0.996 green:0.957 blue:0.851 alpha:1.0];
    return [NSColor colorWithCalibratedRed:0.250 green:0.257 blue:0.333 alpha:1.0];
}
+(NSColor *)nativeTagColor {
    // Light Nitro themes: the light-theme mention colors.
    if ([DLThemes isLightThemeActive]) return [NSColor colorWithCalibratedRed:0.851 green:0.871 blue:0.992 alpha:1.0];
    return [NSColor colorWithCalibratedRed:0.255 green:0.275 blue:0.459 alpha:1.0];
}
+(NSColor *)nativeLinkColor {
    return [NSColor colorWithCalibratedRed:0.000 green:0.659 blue:0.988 alpha:1.0];
}

@end
