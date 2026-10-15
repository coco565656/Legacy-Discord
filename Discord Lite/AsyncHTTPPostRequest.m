//
//  AsyncHTTPPostRequest.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/26/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "AsyncHTTPPostRequest.h"

@implementation AsyncHTTPPostRequest

-(id)init {
    self = [super init];
    if (self) method = [@"POST" retain];
    return self;
}

-(void)start {
    [super initializeRequest];
    
    curl_easy_setopt(curlRequestHandle, CURLOPT_CUSTOMREQUEST, [method UTF8String]);
    
    
    NSData *jsonData = [[CJSONSerializer serializer] serializeDictionary:parameters error:nil];
    NSData *queryData = nil;
    if (files) {
        // Discord's multipart form: one payload_json part carrying the full
        // message (content, reply, stickers) plus files[n] parts. Using an
        // array keeps two attachments with the same name (image.png) apart.
        NSMutableData *formData = [[[NSMutableData alloc] init] autorelease];
        NSString *boundary = [NSString stringWithFormat:@"---------------------------%@", [DLUtil randomStringWithLength:30]];
        NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:(parameters ? parameters : [NSDictionary dictionary])];
        NSMutableArray *attachmentEntries = [NSMutableArray array];
        NSUInteger index;
        for (index = 0; index < [files count]; index++) {
            NSDictionary *file = [files objectAtIndex:index];
            [attachmentEntries addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                          [NSNumber numberWithUnsignedInteger:index], @"id",
                                          [file objectForKey:@"filename"], @"filename", nil]];
        }
        [payload setObject:attachmentEntries forKey:@"attachments"];
        NSData *payloadData = [[CJSONSerializer serializer] serializeDictionary:payload error:nil];
        [formData appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json\r\n\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        if (payloadData) [formData appendData:payloadData];
        [formData appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        for (index = 0; index < [files count]; index++) {
            NSDictionary *file = [files objectAtIndex:index];
            NSString *fileName = [file objectForKey:@"filename"];
            NSString *headerName = [[[fileName stringByReplacingOccurrencesOfString:@"\"" withString:@"%22"]
                                     stringByReplacingOccurrencesOfString:@"\r" withString:@""]
                                    stringByReplacingOccurrencesOfString:@"\n" withString:@""];
            NSString *mimeType = [DLUtil mimeTypeForExtension:[fileName pathExtension]];
            [formData appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"files[%lu]\"; filename=\"%@\"\r\nContent-Type: %@\r\n\r\n", boundary, (unsigned long)index, headerName, mimeType ? mimeType : @"application/octet-stream"] dataUsingEncoding:NSUTF8StringEncoding]];
            [formData appendData:[file objectForKey:@"data"]];
            [formData appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        }
        [formData appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        
        queryData = formData;
        
        rootHeader = curl_slist_append(rootHeader, [[NSString stringWithFormat:@"Content-Type: multipart/form-data; boundary=%@", boundary] UTF8String]);
        
    } else {
        //NSLog(@"Req: %@", [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]);
        queryData = jsonData;
        rootHeader = curl_slist_append(rootHeader, [@"Content-Type: application/json" UTF8String]);
    }
    
    postData = malloc([queryData length]);
    memcpy(postData, [queryData bytes], [queryData length]);
    curl_easy_setopt(curlRequestHandle, CURLOPT_POSTFIELDSIZE, [queryData length]);
    curl_easy_setopt(curlRequestHandle, CURLOPT_POSTFIELDS, postData);
    
    rootHeader = curl_slist_append(rootHeader, [@"Accept: */*" UTF8String]);
    
    if ([[AsyncHTTPRequestSettings sharedInstance] persistentPOSTHeaders]) {
        NSEnumerator *e = [[[[AsyncHTTPRequestSettings sharedInstance] persistentPOSTHeaders] allKeys] objectEnumerator];
        NSString *key;
        while (key = [e nextObject]) {
            rootHeader = curl_slist_append(rootHeader, [[NSString stringWithFormat:@"%@: %@", key, [[[AsyncHTTPRequestSettings sharedInstance] persistentPOSTHeaders] objectForKey:key]] UTF8String]);
        }
    }
    
    if (headers) {
        
        NSEnumerator *e = [[headers allKeys] objectEnumerator];
        NSString *key;
        while (key = [e nextObject]) {
            rootHeader = curl_slist_append(rootHeader, [[NSString stringWithFormat:@"%@: %@", key, [headers objectForKey:key]] UTF8String]);
        }
    }
    curl_easy_setopt(curlRequestHandle, CURLOPT_HTTPHEADER, rootHeader);
    [super start];
}

-(void)setParameters:(NSDictionary *)inParameters {
    [parameters release];
    [inParameters retain];
    parameters = inParameters;
}
-(void)setMethod:(NSString *)inMethod {
    [method release];
    [inMethod retain];
    method = inMethod;
}
-(void)setFiles:(NSArray *)inFiles {
    [files release];
    [inFiles retain];
    files = inFiles;
}

-(void)dealloc {
    [parameters release];
    [files release];
    [method release];
    [super dealloc];
}

@end
