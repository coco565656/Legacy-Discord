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

@interface HTTPCache : NSObject {
    NSMutableDictionary *cacheData;
    NSMutableSet *loadingURLs;
}

-(id)init;
+(HTTPCache *)sharedInstance;
-(NSData *)cachedDataForURL:(NSString *)url;
-(void)setCachedData:(NSData *)data forURL:(NSString *)url;
-(BOOL)beginLoadingURL:(NSString *)url;
-(void)endLoadingURL:(NSString *)url;

@end
