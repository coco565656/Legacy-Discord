//
//  HTTPCache.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/3/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "HTTPCache.h"
#import <CommonCrypto/CommonDigest.h>
#include <sys/time.h>

static HTTPCache* sharedObject = nil;

// Memory is the scarce resource on the 2007 test MacBook; disk is not.
static const unsigned long long DLMemoryCacheLimit = 32ULL * 1024 * 1024;
static const unsigned long long DLDiskCacheLimit = 200ULL * 1024 * 1024;
static const unsigned long long DLDiskCacheTrimTarget = 150ULL * 1024 * 1024;
static const NSUInteger DLWritesBetweenTrims = 200;

@interface HTTPCache ()
-(NSString *)keyForURL:(NSString *)url;
-(NSString *)diskPathForKey:(NSString *)key;
-(void)storeInMemory:(NSData *)data forKey:(NSString *)key;
-(void)trimDiskCache;
@end

@implementation HTTPCache

-(id)init {
    self = [super init];
    memoryData = [[NSMutableDictionary alloc] init];
    memoryOrder = [[NSMutableArray alloc] init];
    loadingURLs = [[NSMutableSet alloc] init];
    NSArray *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ? [[NSBundle mainBundle] bundleIdentifier] : @"org.legacydiscord.client";
    if ([caches count]) {
        diskDirectory = [[[[caches objectAtIndex:0] stringByAppendingPathComponent:bundleID]
                          stringByAppendingPathComponent:@"Images"] retain];
        [[NSFileManager defaultManager] createDirectoryAtPath:diskDirectory withIntermediateDirectories:YES
                                                   attributes:nil error:NULL];
        [self performSelectorInBackground:@selector(trimDiskCache) withObject:nil];
    }
    return self;
}

+(HTTPCache *)sharedInstance
{
    if (!sharedObject) {
        sharedObject = [[[super allocWithZone: NULL] init] retain];
    }
    return sharedObject;
}

// Discord signs CDN attachment links with expiring ex/is/hm parameters; the
// same image comes back with new values every session, so they are not part
// of the cache key. Size and format parameters are kept.
-(NSString *)keyForURL:(NSString *)url {
    NSRange query = [url rangeOfString:@"?"];
    if (query.location == NSNotFound) return url;
    NSString *base = [url substringToIndex:query.location];
    NSArray *pairs = [[url substringFromIndex:query.location + 1] componentsSeparatedByString:@"&"];
    NSMutableArray *kept = [NSMutableArray array];
    NSEnumerator *enumerator = [pairs objectEnumerator];
    NSString *pair;
    while (pair = [enumerator nextObject]) {
        if (![pair length] || [pair hasPrefix:@"ex="] || [pair hasPrefix:@"is="] || [pair hasPrefix:@"hm="]) continue;
        [kept addObject:pair];
    }
    return [kept count] ? [NSString stringWithFormat:@"%@?%@", base, [kept componentsJoinedByString:@"&"]] : base;
}

-(NSString *)diskPathForKey:(NSString *)key {
    if (!diskDirectory) return nil;
    const char *bytes = [key UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(bytes, (CC_LONG)strlen(bytes), digest);
    NSMutableString *name = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    NSUInteger index;
    for (index = 0; index < CC_MD5_DIGEST_LENGTH; index++) [name appendFormat:@"%02x", digest[index]];
    return [diskDirectory stringByAppendingPathComponent:name];
}

-(void)storeInMemory:(NSData *)data forKey:(NSString *)key {
    if (!data || !key) return;
    NSData *existing = [memoryData objectForKey:key];
    if (existing) {
        memoryBytes -= [existing length];
        [memoryOrder removeObject:key];
    }
    [memoryData setObject:data forKey:key];
    [memoryOrder addObject:key];
    memoryBytes += [data length];
    // Drop the least recently used entries; they are still on disk.
    while (memoryBytes > DLMemoryCacheLimit && [memoryOrder count] > 1) {
        NSString *oldest = [memoryOrder objectAtIndex:0];
        memoryBytes -= [[memoryData objectForKey:oldest] length];
        [memoryData removeObjectForKey:oldest];
        [memoryOrder removeObjectAtIndex:0];
    }
}

-(NSData *)cachedDataForURL:(NSString *)url {
    if (!url) return nil;
    NSString *key = [self keyForURL:url];
    NSData *data = [memoryData objectForKey:key];
    if (data) {
        [[data retain] autorelease];
        [memoryOrder removeObject:key];
        [memoryOrder addObject:key];
        return data;
    }
    NSString *path = [self diskPathForKey:key];
    data = path ? [NSData dataWithContentsOfFile:path] : nil;
    if ([data length]) {
        // Touch the file so trimming removes the least recently used first.
        utimes([path fileSystemRepresentation], NULL);
        [self storeInMemory:data forKey:key];
        return data;
    }
    return nil;
}

-(void)writeToDisk:(NSArray *)pathAndData {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [[pathAndData objectAtIndex:1] writeToFile:[pathAndData objectAtIndex:0] atomically:YES];
    [pool drain];
}

-(void)setCachedData:(NSData *)data forURL:(NSString *)url {
    NSString *key = [self keyForURL:url];
    if ([data length] && ![memoryData objectForKey:key]) {
        NSData *copy = [[data copy] autorelease];
        [self storeInMemory:copy forKey:key];
        NSString *path = [self diskPathForKey:key];
        if (path) {
            [self performSelectorInBackground:@selector(writeToDisk:) withObject:[NSArray arrayWithObjects:path, copy, nil]];
            if (++writesSinceTrim >= DLWritesBetweenTrims) {
                writesSinceTrim = 0;
                [self performSelectorInBackground:@selector(trimDiskCache) withObject:nil];
            }
        }
    }
    [loadingURLs removeObject:url];
    [[NSNotificationCenter defaultCenter] postNotificationName:HTTPCacheDataDidUpdateNotification object:url];
}

-(BOOL)beginLoadingURL:(NSString *)url {
    if ([self cachedDataForURL:url] || [loadingURLs containsObject:url]) {
        return NO;
    }
    [loadingURLs addObject:url];
    return YES;
}
-(void)endLoadingURL:(NSString *)url {
    [loadingURLs removeObject:url];
}

-(NSArray *)diskEntries {
    NSMutableArray *entries = [NSMutableArray array];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSEnumerator *enumerator = [[manager contentsOfDirectoryAtPath:diskDirectory error:NULL] objectEnumerator];
    NSString *name;
    while (name = [enumerator nextObject]) {
        NSString *path = [diskDirectory stringByAppendingPathComponent:name];
        NSDictionary *attributes = [manager attributesOfItemAtPath:path error:NULL];
        if (![[attributes fileType] isEqualToString:NSFileTypeRegular]) continue;
        [entries addObject:[NSDictionary dictionaryWithObjectsAndKeys:path, @"path",
                            [attributes fileModificationDate], @"date",
                            [NSNumber numberWithUnsignedLongLong:[attributes fileSize]], @"size", nil]];
    }
    return entries;
}

-(unsigned long long)diskUsage {
    if (!diskDirectory) return 0;
    unsigned long long total = 0;
    NSEnumerator *enumerator = [[self diskEntries] objectEnumerator];
    NSDictionary *entry;
    while (entry = [enumerator nextObject]) total += [[entry objectForKey:@"size"] unsignedLongLongValue];
    return total;
}

static NSInteger DLCompareEntryDates(NSDictionary *a, NSDictionary *b, void *context) {
    return [[a objectForKey:@"date"] compare:[b objectForKey:@"date"]];
}

// Runs on a background thread: removes the least recently used files once
// the cache grows past its limit.
-(void)trimDiskCache {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    @synchronized (self) {
        NSArray *entries = [self diskEntries];
        unsigned long long total = 0;
        NSEnumerator *enumerator = [entries objectEnumerator];
        NSDictionary *entry;
        while (entry = [enumerator nextObject]) total += [[entry objectForKey:@"size"] unsignedLongLongValue];
        if (total > DLDiskCacheLimit) {
            enumerator = [[entries sortedArrayUsingFunction:DLCompareEntryDates context:NULL] objectEnumerator];
            while (total > DLDiskCacheTrimTarget && (entry = [enumerator nextObject])) {
                if ([[NSFileManager defaultManager] removeItemAtPath:[entry objectForKey:@"path"] error:NULL]) {
                    total -= [[entry objectForKey:@"size"] unsignedLongLongValue];
                }
            }
        }
    }
    [pool drain];
}

-(void)clearDiskCache {
    @synchronized (self) {
        NSEnumerator *enumerator = [[self diskEntries] objectEnumerator];
        NSDictionary *entry;
        while (entry = [enumerator nextObject]) {
            [[NSFileManager defaultManager] removeItemAtPath:[entry objectForKey:@"path"] error:NULL];
        }
    }
    [memoryData removeAllObjects];
    [memoryOrder removeAllObjects];
    memoryBytes = 0;
}

@end
