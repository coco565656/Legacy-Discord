//
//  HTTPCache.h
//  Discord Lite
//
//  Created by Collin Mistr on 11/3/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HTTPCacheData.h"

#define HTTPCacheDataDidUpdateNotification @"HTTPCacheDataDidUpdateNotification"

// Image cache for avatars, emoji, stickers, banners and attachment previews.
// A bounded in-memory layer sits in front of a bounded disk cache in
// ~/Library/Caches, so images survive relaunches without growing forever.
@interface HTTPCache : NSObject {
    NSMutableDictionary *memoryData;
    NSMutableArray *memoryOrder;
    unsigned long long memoryBytes;
    NSMutableSet *loadingURLs;
    NSString *diskDirectory;
    NSUInteger writesSinceTrim;
}

-(id)init;
+(HTTPCache *)sharedInstance;
-(NSData *)cachedDataForURL:(NSString *)url;
-(void)setCachedData:(NSData *)data forURL:(NSString *)url;
-(BOOL)beginLoadingURL:(NSString *)url;
-(void)endLoadingURL:(NSString *)url;
// Total size of the disk cache, and removing everything (Settings > Advanced).
-(unsigned long long)diskUsage;
-(void)clearDiskCache;

@end
