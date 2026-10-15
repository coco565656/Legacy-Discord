//
//  AsyncHTTPPostRequest.h
//  Discord Lite
//
//  Created by Collin Mistr on 10/26/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "AsyncHTTPRequest.h"
#import "DLUtil.h"

@interface AsyncHTTPPostRequest : AsyncHTTPRequest {
    NSDictionary *parameters;
    NSArray *files;
    NSString *method;
}

-(id)init;
-(void)start;

-(void)setParameters:(NSDictionary *)inParameters;
-(void)setMethod:(NSString *)inMethod;
// Array of {filename, data} dictionaries, sent with the parameters as payload_json.
-(void)setFiles:(NSArray *)inFiles;

@end
