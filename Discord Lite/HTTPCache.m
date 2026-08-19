//
//  HTTPCache.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/3/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "HTTPCache.h"

static HTTPCache* sharedObject = nil;

@implementation HTTPCache 

-(id)init {
    self = [super init];
    cacheData = [[NSMutableDictionary alloc] init];
    loadingURLs = [[NSMutableSet alloc] init];
    return self;
}

+(HTTPCache *)sharedInstance
{
    if (!sharedObject) {
        sharedObject = [[[super allocWithZone: NULL] init] retain];
    }
    return sharedObject;
}
-(NSData *)cachedDataForURL:(NSString *)url {
    return [[cacheData objectForKey:url] data];
}
-(void)setCachedData:(NSData *)data forURL:(NSString *)url {
    if (![cacheData objectForKey:url]) {
        HTTPCacheData *d = [[HTTPCacheData alloc] init];
        [d setUrl:url];
        [d setData:data];
        [cacheData setObject:d forKey:url];
    }
    [loadingURLs removeObject:url];
    [[NSNotificationCenter defaultCenter] postNotificationName:HTTPCacheDataDidUpdateNotification object:url];
}
-(BOOL)beginLoadingURL:(NSString *)url {
    if ([cacheData objectForKey:url] || [loadingURLs containsObject:url]) {
        return NO;
    }
    [loadingURLs addObject:url];
    return YES;
}
-(void)endLoadingURL:(NSString *)url {
    [loadingURLs removeObject:url];
}

@end
