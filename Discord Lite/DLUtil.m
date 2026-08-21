//
//  DLUtil.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/27/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "DLUtil.h"

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
    return [[NSString stringWithFormat:@"%ld", snowflake] autorelease];
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
    return [NSColor colorWithCalibratedRed:0.118 green:0.122 blue:0.133 alpha:1.0];
}
+(NSColor *)nativeSidebarColor {
    return [NSColor colorWithCalibratedRed:0.169 green:0.176 blue:0.192 alpha:1.0];
}
+(NSColor *)nativeContentColor {
    return [NSColor colorWithCalibratedRed:0.192 green:0.200 blue:0.220 alpha:1.0];
}
+(NSColor *)nativeChromeColor {
    return [NSColor colorWithCalibratedRed:0.169 green:0.176 blue:0.192 alpha:1.0];
}
+(NSColor *)nativeInputColor {
    return [NSColor colorWithCalibratedRed:0.220 green:0.227 blue:0.247 alpha:1.0];
}
+(NSColor *)nativeBorderColor {
    return [NSColor colorWithCalibratedRed:0.125 green:0.129 blue:0.141 alpha:1.0];
}
+(NSColor *)nativeHeaderTopColor {
    return [self nativeContentColor];
}
+(NSColor *)nativeHeaderBottomColor {
    return [self nativeContentColor];
}
+(NSColor *)nativePrimaryTextColor {
    return [NSColor colorWithCalibratedRed:0.949 green:0.953 blue:0.961 alpha:1.0];
}
+(NSColor *)nativeSecondaryTextColor {
    return [NSColor colorWithCalibratedRed:0.710 green:0.729 blue:0.757 alpha:1.0];
}
+(NSColor *)nativeSelectionColor {
    return [NSColor colorWithCalibratedRed:0.251 green:0.259 blue:0.286 alpha:1.0];
}
+(NSColor *)nativeSelectedTextColor {
    return [NSColor colorWithCalibratedRed:0.949 green:0.953 blue:0.961 alpha:1.0];
}
+(NSColor *)nativeMentionColor {
    return [NSColor colorWithCalibratedRed:0.250 green:0.257 blue:0.333 alpha:1.0];
}
+(NSColor *)nativeTagColor {
    return [NSColor colorWithCalibratedRed:0.255 green:0.275 blue:0.459 alpha:1.0];
}
+(NSColor *)nativeLinkColor {
    return [NSColor colorWithCalibratedRed:0.000 green:0.659 blue:0.988 alpha:1.0];
}

@end
