//
//  AsyncHTTPRequest.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/26/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "AsyncHTTPRequest.h"


size_t writeResponseData(char *data, size_t size, size_t nmemb, void* ptr) {
    AsyncHTTPRequest *reqObj = (AsyncHTTPRequest *)ptr;
    [[reqObj responseData] appendBytes:data length:size * nmemb];
    return size * nmemb;
}

size_t writeFileData(char *data, size_t size, size_t nmemb, void *ptr) {
    AsyncHTTPRequest *reqObj = (AsyncHTTPRequest *)ptr;
    [[reqObj downloadingFile] writeData:[NSData dataWithBytes:data length:size * nmemb]];
    [reqObj performSelectorOnMainThread:@selector(dataChunkWasDownloaded) withObject:nil waitUntilDone:YES];
    return size * nmemb;
}




@implementation AsyncHTTPRequest

-(id)init {
    self = [super init];
    cached = NO;
    isFileDownload = NO;
    return self;
}

-(void)initializeRequest {
    if (isFileDownload) {
        [downloadingFile seekToEndOfFile];
    } else {
        responseData = [[NSMutableData alloc] init];
    }
    
    curlRequestHandle = curl_easy_init();
    if (curlRequestHandle) {
        curl_easy_setopt(curlRequestHandle, CURLOPT_URL, [url UTF8String]);
        curl_easy_setopt(curlRequestHandle, CURLOPT_NOPROGRESS, 1L);
        curl_easy_setopt(curlRequestHandle, CURLOPT_USERAGENT, [[[AsyncHTTPRequestSettings sharedInstance] userAgentString] UTF8String]);
        curl_easy_setopt(curlRequestHandle, CURLOPT_MAXREDIRS, 50L);
        curl_easy_setopt(curlRequestHandle, CURLOPT_TCP_KEEPALIVE, 1L);
        curl_easy_setopt(curlRequestHandle, CURLOPT_TIMEOUT, 120L);
        NSString *caBundlePath = [DLUtil effectiveCAPath];
        curl_easy_setopt(curlRequestHandle, CURLOPT_SSL_VERIFYPEER, 1L);
        curl_easy_setopt(curlRequestHandle, CURLOPT_SSL_VERIFYHOST, 2L);
        if (caBundlePath) {
            curl_easy_setopt(curlRequestHandle, CURLOPT_CAINFO, [caBundlePath fileSystemRepresentation]);
        }
        curl_easy_setopt(curlRequestHandle, CURLOPT_FAILONERROR, 0L);
        [DLUtil applySystemProxyToCurlHandle:curlRequestHandle url:url];
        
        if (isFileDownload) {
            curl_easy_setopt(curlRequestHandle, CURLOPT_WRITEFUNCTION, writeFileData);

        } else {
            curl_easy_setopt(curlRequestHandle, CURLOPT_WRITEFUNCTION, writeResponseData);
        }
        
        
        curl_easy_setopt(curlRequestHandle, CURLOPT_WRITEDATA, self);
    }
}

-(void)startRequestThread {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    int response = curl_easy_perform(curlRequestHandle);
    if (response == CURLE_OK) {
        curl_easy_getinfo(curlRequestHandle, CURLINFO_RESPONSE_CODE, &statusCode);
        // Any 2xx is a success: creating a forum post answers 201 Created.
        if (statusCode >= 200 && statusCode < 300) {
            result = HTTPResultOK;
        } else if (statusCode == 400) {
            result = HTTPResultErrParameter;
        } else {
            result = HTTPResultErrGeneral;
        }
    } else {
        result = HTTPResultErrConnecting;
        NSLog(@"HTTP request failed (curl error %d).", response);
    }
    // Always release the sequencer slot and notify the owner, including TLS and
    // connection failures. Otherwise a failed note load can block later work.
    [self performSelectorOnMainThread:@selector(requestDidFinishLoading) withObject:nil waitUntilDone:NO];
    [pool release];
}

-(void)start {
    [[AsyncHTTPRequestSequencer sharedInstance] enqueueRequest:self];
}

-(HTTPResult)result {
    return result;
}
-(long)statusCode {
    return statusCode;
}
-(NSMutableData *)responseData {
    return responseData;
}
-(int)identifier {
    return identifier;
}
-(NSString *)userAgentString {
    return [DLUtil userAgentString];
}
-(NSString *)url {
    return url;
}
-(id)userInfo {
    return userInfo;
}
-(NSFileHandle *)downloadingFile {
    return downloadingFile;
}


-(void)setUrl:(NSString *)inUrl {
    [url release];
    [inUrl retain];
    url = inUrl;
}

-(void)setDelegate:(id <AsyncHTTPRequestDelegate>)inDelegate {
    delegate = inDelegate;
}
-(void)setUserInfo:(id)inUserInfo {
    if (userInfo != inUserInfo) {
        [userInfo release];
        userInfo = [inUserInfo retain];
    }
}
-(void)setIdentifier:(int)inIdentifier {
    identifier = inIdentifier;
}
-(void)setHeaders:(NSDictionary *)inHeaders {
    [headers release];
    [inHeaders retain];
    headers = inHeaders;
}
-(void)setCached:(BOOL)inCached {
    cached = inCached;
}
-(void)setDownloadingFile:(NSFileHandle *)inDownloadingFile {
    isFileDownload = YES;
    downloadingFile = inDownloadingFile;
}


#pragma mark Delegated Functions



-(void)requestDidFinishLoading {
    if (isFileDownload) {
        [downloadingFile closeFile];
    } else {
        if (cached && result == HTTPResultOK) {
            [[HTTPCache sharedInstance] setCachedData:responseData forURL:url];
        }
    }
    [delegate requestDidFinishLoading:self];
    curl_easy_cleanup(curlRequestHandle);
    curlRequestHandle = nil;
    curl_slist_free_all(rootHeader);
    rootHeader = nil;
    if (postData) {
        free(postData);
        postData = nil;
    }
    [[AsyncHTTPRequestSequencer sharedInstance] requestDidFinish:self];
}

-(void)dataChunkWasDownloaded {
    if ([delegate respondsToSelector:@selector(responseDataDidUpdateWithSize:)]) {
        [delegate responseDataDidUpdateWithSize:[downloadingFile offsetInFile]];
    }
}

#pragma mark Request Sequencer Protocol

-(void)shouldBeginRequest {
    [NSThread detachNewThreadSelector:@selector(startRequestThread) toTarget:self withObject:nil];
}


-(void)dealloc {
    [url release];
    [responseData release];
    [userInfo release];
    [super dealloc];
}

@end
