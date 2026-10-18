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
#include "curl_headers/curl.h"
#include <pthread.h>
#import <Security/Security.h>
#import <SystemConfiguration/SystemConfiguration.h>

@implementation DLUtil

// System proxy state (SCDynamicStoreCopyProxies) shared by REST and Gateway
// threads; refreshed at most every 10 seconds.
static pthread_mutex_t systemProxyInfoMutex = PTHREAD_MUTEX_INITIALIZER;
static NSDictionary *systemProxyInfoCache = nil;
static NSDate *systemProxyInfoTimestamp = nil;

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

+(NSString *)wrappedPEMBodyOfBase64String:(NSString *)base64 {
    NSMutableString *wrapped = [[NSMutableString alloc] init];
    NSInteger length = [base64 length];
    for (NSInteger offset = 0; offset < length; offset += 64) {
        NSInteger end = offset + 64;
        if (end > length) end = length;
        [wrapped appendString:[base64 substringWithRange:NSMakeRange(offset, end - offset)]];
        [wrapped appendString:@"\n"];
    }
    return [wrapped autorelease];
}

// YES when a certificate's trust settings in this domain make it a trusted
// root. An empty settings array means "always trust"; an entry whose result
// is Deny (the user chose "Never Trust") excludes the certificate.
static BOOL DLCertificateIsTrustedRoot(SecCertificateRef certificate, SecTrustSettingsDomain domain) {
    CFArrayRef settings = NULL;
    if (SecTrustSettingsCopyTrustSettings(certificate, domain, &settings) != errSecSuccess) return NO;
    BOOL trusted = NO;
    BOOL denied = NO;
    CFIndex count = settings ? CFArrayGetCount(settings) : 0;
    if (count == 0) trusted = YES;
    CFIndex index;
    for (index = 0; index < count; index++) {
        CFDictionaryRef entry = (CFDictionaryRef)CFArrayGetValueAtIndex(settings, index);
        if (!entry || CFGetTypeID(entry) != CFDictionaryGetTypeID()) continue;
        SInt32 result = kSecTrustSettingsResultTrustRoot;
        CFNumberRef resultNumber = (CFNumberRef)CFDictionaryGetValue(entry, kSecTrustSettingsResult);
        if (resultNumber && CFGetTypeID(resultNumber) == CFNumberGetTypeID()) {
            CFNumberGetValue(resultNumber, kCFNumberSInt32Type, &result);
        }
        if (result == kSecTrustSettingsResultDeny) denied = YES;
        else if (result == kSecTrustSettingsResultTrustRoot || result == kSecTrustSettingsResultTrustAsRoot) trusted = YES;
    }
    if (settings) CFRelease(settings);
    return trusted && !denied;
}

+(NSData *)keychainAnchorData {
    // PEM for the certificates that macOS trust settings treat as anchors:
    // the System and user keychain trust domains. When AquaProxy and similar
    // local MITM proxies were installed, their root certificate is trusted
    // there by the user, so verification keeps working through them while
    // staying strict everywhere else.
    NSData *beginMarker = [@"-----BEGIN CERTIFICATE-----\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *endMarker = [@"-----END CERTIFICATE-----\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *pemData = [[NSMutableData alloc] init];
    // Admin is where installers (and "Always Trust" by an administrator) put
    // their roots; User is the per-user Keychain Access choice.
    SecTrustSettingsDomain domains[] = {kSecTrustSettingsDomainSystem, kSecTrustSettingsDomainAdmin, kSecTrustSettingsDomainUser};
    NSMutableArray *seenCerts = [[NSMutableArray alloc] init];
    unsigned int domainIndex;
    for (domainIndex = 0; domainIndex < sizeof(domains) / sizeof(domains[0]); domainIndex++) {
        CFArrayRef anchors = NULL;
        OSStatus status = SecTrustSettingsCopyCertificates(domains[domainIndex], &anchors);
        if (status != errSecSuccess || !anchors) {
            if (anchors) CFRelease(anchors);
            continue;
        }
        CFIndex anchorCount = CFArrayGetCount(anchors);
        CFIndex anchorIndex;
        for (anchorIndex = 0; anchorIndex < anchorCount; anchorIndex++) {
            SecCertificateRef certificate = (SecCertificateRef)CFArrayGetValueAtIndex(anchors, anchorIndex);
            if (!certificate || CFGetTypeID(certificate) != SecCertificateGetTypeID()) continue;
            if ([seenCerts containsObject:(id)certificate]) continue;
            if (!DLCertificateIsTrustedRoot(certificate, domains[domainIndex])) continue;
            CFDataRef certificateData = SecCertificateCopyData(certificate);
            if (!certificateData) continue;
            NSString *base64Body = [NSString encodeBase64WithData:(NSData *)certificateData];
            CFRelease(certificateData);
            if (![base64Body length]) continue;
            // A certificate trusted in both domains appears once in the
            // combined bundle (the anchor list is deduplicated by instance).
            [seenCerts addObject:(id)certificate];
            [pemData appendData:beginMarker];
            [pemData appendData:[[self wrappedPEMBodyOfBase64String:base64Body] dataUsingEncoding:NSUTF8StringEncoding]];
            [pemData appendData:endMarker];
        }
        CFRelease(anchors);
    }
    [seenCerts release];
    if (![pemData length]) {
        [pemData release];
        return nil;
    }
    return [pemData autorelease];
}

+(void)refreshSystemProxyInfoCache {
    SCDynamicStoreRef store = SCDynamicStoreCreate(kCFAllocatorDefault, CFSTR("LegacyDiscord"), NULL, NULL);
    if (!store) return;
    CFDictionaryRef proxies = SCDynamicStoreCopyProxies(store);
    CFRelease(store);
    if (!proxies) return;

    NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
    NSString *httpsProxyURL = [self proxyURLFromProxiesDictionary:proxies enableKey:kSCPropNetProxiesHTTPSEnable hostKey:kSCPropNetProxiesHTTPSProxy portKey:kSCPropNetProxiesHTTPSPort];
    if ([httpsProxyURL length]) [info setObject:httpsProxyURL forKey:@"httpsProxy"];
    NSString *httpProxyURL = [self proxyURLFromProxiesDictionary:proxies enableKey:kSCPropNetProxiesHTTPEnable hostKey:kSCPropNetProxiesHTTPProxy portKey:kSCPropNetProxiesHTTPPort];
    if ([httpProxyURL length]) [info setObject:httpProxyURL forKey:@"httpProxy"];
    CFArrayRef exceptions = (CFArrayRef)CFDictionaryGetValue(proxies, kSCPropNetProxiesExceptionsList);
    if (exceptions && CFArrayGetCount(exceptions) > 0) {
        NSMutableArray *bypassList = [[NSMutableArray alloc] init];
        CFIndex exceptionIndex;
        for (exceptionIndex = 0; exceptionIndex < CFArrayGetCount(exceptions); exceptionIndex++) {
            CFStringRef exception = (CFStringRef)CFArrayGetValueAtIndex(exceptions, exceptionIndex);
            if (exception && CFGetTypeID(exception) == CFStringGetTypeID()) {
                [bypassList addObject:[(NSString *)exception lowercaseString]];
            }
        }
        if ([bypassList count]) [info setObject:bypassList forKey:@"bypass"];
        [bypassList release];
    }
    CFRelease(proxies);

    pthread_mutex_lock(&systemProxyInfoMutex);
    [systemProxyInfoCache release];
    systemProxyInfoCache = [info copy];
    [systemProxyInfoTimestamp release];
    systemProxyInfoTimestamp = [[NSDate date] retain];
    pthread_mutex_unlock(&systemProxyInfoMutex);
    [info release];
}

+(NSString *)proxyURLFromProxiesDictionary:(CFDictionaryRef)proxies enableKey:(CFStringRef)enableKey hostKey:(CFStringRef)hostKey portKey:(CFStringRef)portKey {
    CFNumberRef enabledNumber = (CFNumberRef)CFDictionaryGetValue(proxies, enableKey);
    if (!enabledNumber || CFGetTypeID(enabledNumber) != CFNumberGetTypeID()) return nil;
    int enabled = 0;
    if (!CFNumberGetValue(enabledNumber, kCFNumberIntType, &enabled) || !enabled) return nil;
    CFStringRef host = (CFStringRef)CFDictionaryGetValue(proxies, hostKey);
    if (!host || CFGetTypeID(host) != CFStringGetTypeID() || CFStringGetLength(host) == 0) return nil;
    CFNumberRef portNumber = (CFNumberRef)CFDictionaryGetValue(proxies, portKey);
    int port = 80;
    if (portNumber && CFGetTypeID(portNumber) == CFNumberGetTypeID()) {
        if (!CFNumberGetValue(portNumber, kCFNumberIntType, &port) || port <= 0 || port > 65535) return nil;
    }
    return [NSString stringWithFormat:@"http://%@:%d", (NSString *)host, port];
}

+(NSString *)systemProxyInfoValue:(NSString *)key {
    pthread_mutex_lock(&systemProxyInfoMutex);
    NSDictionary *info = systemProxyInfoCache;
    NSDate *stamp = systemProxyInfoTimestamp;
    BOOL stale = (!stamp || -[[NSDate date] timeIntervalSinceDate:stamp] >= 10.0);
    pthread_mutex_unlock(&systemProxyInfoMutex);
    if (stale || !info) [self refreshSystemProxyInfoCache];
    pthread_mutex_lock(&systemProxyInfoMutex);
    // The value is retained on its own; refresh may safely release the
    // container dictionary afterwards.
    NSString *value = [[systemProxyInfoCache objectForKey:key] retain];
    pthread_mutex_unlock(&systemProxyInfoMutex);
    return [value autorelease];
}

+(BOOL)hostIsInSystemProxyBypassList:(NSString *)host {
    if (![host length]) return NO;
    NSString *lowerHost = [host lowercaseString];
    for (NSString *entry in (NSArray *)[DLUtil systemProxyInfoValue:@"bypass"]) {
        if (![entry length]) continue;
        if ([entry hasPrefix:@"."]) {
            // macOS exception lists commonly use ".example.com" for whole
            // domain entries, which the browser meaning matches the apex host
            // and every subdomain.
            if ([lowerHost hasSuffix:entry] || [lowerHost isEqualToString:[entry substringFromIndex:1]]) return YES;
        } else if ([entry hasPrefix:@"*."]) {
            NSString *entryDomain = [entry substringFromIndex:1];
            if ([lowerHost hasSuffix:entryDomain]) return YES;
        } else if ([entry isEqualToString:lowerHost]) {
            return YES;
        }
    }
    return NO;
}

+(NSString *)schemeOfURLString:(NSString *)url {
    NSRange schemeSeparatorRange = [url rangeOfString:@"://"];
    if (schemeSeparatorRange.location == NSNotFound || schemeSeparatorRange.location == 0) return nil;
    return [url substringToIndex:schemeSeparatorRange.location];
}

+(NSString *)hostOfURLString:(NSString *)url {
    NSRange schemeSeparatorRange = [url rangeOfString:@"://"];
    if (schemeSeparatorRange.location == NSNotFound) return nil;
    NSString *authority = [url substringFromIndex:schemeSeparatorRange.location + 3];
    NSUInteger hostLength = [authority length];
    NSRange slashRange = [authority rangeOfString:@"/"];
    if (slashRange.location != NSNotFound) hostLength = slashRange.location;
    NSRange colonRange = [authority rangeOfString:@":"];
    if (colonRange.location != NSNotFound && colonRange.location < hostLength) hostLength = colonRange.location;
    NSRange questionRange = [authority rangeOfString:@"?"];
    if (questionRange.location != NSNotFound && questionRange.location < hostLength) hostLength = questionRange.location;
    if (hostLength == 0 || hostLength > [authority length]) return nil;
    authority = [authority substringToIndex:hostLength];
    // user:password@host — the host part follows the last @.
    NSRange atSignRange = [authority rangeOfString:@"@" options:NSBackwardsSearch];
    if (atSignRange.location != NSNotFound) authority = [authority substringFromIndex:atSignRange.location + 1];
    if (![authority length]) return nil;
    return authority;
}

+(void)applySystemProxyToCurlHandle:(void *)curlHandle url:(NSString *)url {
    CURL *handle = (CURL *)curlHandle;
    if (!handle || ![url length]) return;
    // curl URLs are plain strings here; NSURL-style accessors are not available.
    NSString *scheme = [[self schemeOfURLString:url] lowercaseString];
    if (![scheme length]) return;
    // Discord hosts are HTTPS/WSS, but message media can be plain HTTP.
    NSString *proxyURL = [self systemProxyInfoValue:([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"wss"] ? @"httpsProxy" : @"httpProxy")];
    if (![proxyURL length]) return;
    NSString *host = [self hostOfURLString:url];
    if (![self hostIsInSystemProxyBypassList:host]) {
        curl_easy_setopt(handle, CURLOPT_PROXY, [proxyURL UTF8String]);
        // HTTPS/WSS ride an HTTP CONNECT tunnel; plain HTTP traffic is sent
        // in normal proxy form because MITM proxies serve only TLS CONNECT.
        if ([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"wss"]) {
            curl_easy_setopt(handle, CURLOPT_HTTPPROXYTUNNEL, 1L);
        }
    }
}

+(BOOL)systemProxyServesHost:(NSString *)host {
    if ([[self systemProxyInfoValue:@"httpsProxy"] length]) {
        return ![self hostIsInSystemProxyBypassList:host];
    }
    if ([[self systemProxyInfoValue:@"httpProxy"] length]) {
        return ![self hostIsInSystemProxyBypassList:host];
    }
    return NO;
}

+(NSString *)effectiveCAPath {
    static NSString *cachedEffectiveCAPath = nil;
    static pthread_mutex_t effectiveCAPathMutex = PTHREAD_MUTEX_INITIALIZER;
    // The first caller builds the bundle with the mutex held; later callers
    // receive its result. Concurrent first-calls block briefly at startup.
    pthread_mutex_lock(&effectiveCAPathMutex);
    if (cachedEffectiveCAPath) {
        pthread_mutex_unlock(&effectiveCAPathMutex);
        return [[cachedEffectiveCAPath retain] autorelease];
    }

    NSString *bundlePath = [self caBundlePath];
    if (!bundlePath) {
        pthread_mutex_unlock(&effectiveCAPathMutex);
        return nil;
    }
    NSData *anchorData = [self keychainAnchorData];
    if (![anchorData length]) {
        pthread_mutex_unlock(&effectiveCAPathMutex);
        return bundlePath;
    }
    NSMutableData *combinedData = [[NSMutableData alloc] initWithContentsOfFile:bundlePath];
    if (![combinedData length]) {
        pthread_mutex_unlock(&effectiveCAPathMutex);
        [combinedData release];
        return bundlePath;
    }
    [combinedData appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [combinedData appendData:anchorData];

    NSArray *cacheDirectories = [[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask];
    NSString *cacheDirectory = nil;
    if ([cacheDirectories count] > 0 && [[cacheDirectories objectAtIndex:0] isKindOfClass:[NSURL class]]) {
        cacheDirectory = [[cacheDirectories objectAtIndex:0] path];
    }
    if (![cacheDirectory length]) cacheDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"];
    NSString *combinedPath = [[cacheDirectory stringByAppendingPathComponent:@"LegacyDiscord-ca.pem"] retain];
    BOOL wroteBundle = [combinedData writeToFile:combinedPath atomically:YES];
    [combinedData release];
    if (!wroteBundle) {
        // A failed combined-bundle write must not break the login attempt.
        pthread_mutex_unlock(&effectiveCAPathMutex);
        [combinedPath release];
        return bundlePath;
    }

    [cachedEffectiveCAPath release];
    cachedEffectiveCAPath = combinedPath;
    pthread_mutex_unlock(&effectiveCAPathMutex);
    return [[cachedEffectiveCAPath retain] autorelease];
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
