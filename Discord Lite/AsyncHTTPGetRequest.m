//
//  AsyncHTTPGetRequest.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/26/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "AsyncHTTPGetRequest.h"

@implementation AsyncHTTPGetRequest

-(id)init {
    self = [super init];
    return self;
}

-(void)start {
    [self initializeRequest];
    
    
    // Discord API requests carry the same browser headers as POSTs, so every
    // request describes one client. Media and CDN requests are left alone.
    if ([url hasPrefix:@"https://discord.com/api/"]) {
        NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:
                                       [[AsyncHTTPRequestSettings sharedInstance] persistentPOSTHeaders]];
        [merged setObject:@"*/*" forKey:@"Accept"];
        if (headers) [merged addEntriesFromDictionary:headers];
        [self setHeaders:merged];
    }
    if (headers) {
        rootHeader = nil;
        NSEnumerator *e = [[headers allKeys] objectEnumerator];
        NSString *key;
        while (key = [e nextObject]) {
            rootHeader = curl_slist_append(rootHeader, [[NSString stringWithFormat:@"%@: %@", key, [headers objectForKey:key]] UTF8String]);
        }
        curl_easy_setopt(curlRequestHandle, CURLOPT_HTTPHEADER, rootHeader);
    }
    
    if (cached) {
        if ([[HTTPCache sharedInstance] cachedDataForURL:url]) {
            [responseData release];
            responseData = (NSMutableData *)[[[HTTPCache sharedInstance] cachedDataForURL:url] retain];
            result = HTTPResultOK;
            [delegate requestDidFinishLoading:self];
        } else {
            [super start];
        }
    } else {
        [super start];
    }
}

@end
