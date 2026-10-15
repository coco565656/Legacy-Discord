//
//  AttachmentPreviewViewController.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/3/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "AttachmentPreviewViewController.h"
#import <WebKit/WebKit.h>

@implementation AttachmentPreviewViewController

-(NSView *)attachmentView {
    return attachmentView;
}

-(void)setRepresentedObject:(DLAttachment *)inRepresentedObject {
    [representedObject release];
    [inRepresentedObject retain];
    representedObject = inRepresentedObject;
    [representedObject setPreviewDelegate:self];
    
    NSRect frame = NSMakeRect(0, 0, [representedObject scaledWidth], [representedObject scaledHeight]);
    
    if ([representedObject type] == AttachmentTypeImage) {
        imageView = [[NSImageView alloc] initWithFrame:frame];
        attachmentView = imageView;
        
        //Add invisible overlay to handle mouse events
        eventHandlerView = [[NSView_Events alloc] initWithFrame:frame];
        [eventHandlerView setDelegate:self];
        [attachmentView addSubview:eventHandlerView];
        NSData *previewData = [representedObject scaledAttachmentData];
        if (previewData) {
            [self attachment:representedObject previewDataWasUpdated:previewData];
        } else {
            [representedObject loadScaledData];
        }
    } else if ([representedObject type] == AttachmentTypeVideo) {
        WebView *videoView = [[WebView alloc] initWithFrame:frame];
        attachmentView = videoView;
        NSString *videoURL = [representedObject proxyURL] ? [representedObject proxyURL] : [representedObject url];
        NSString *escapedURL = [[videoURL stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"] stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
        NSString *html = [NSString stringWithFormat:@"<html><body style='margin:0;background:#111;overflow:hidden'><video src=\"%@\" controls preload='metadata' style='width:100%%;height:100%%'></video></body></html>", escapedURL];
        [[videoView mainFrame] loadHTMLString:html baseURL:nil];
    } else {
        attachmentView = nonImageAttachmentView;
        
        [fileIconImageView setImage:[[NSWorkspace sharedWorkspace] iconForFileType:[[representedObject filename] pathExtension]]];
        [filenameTextField setStringValue:[representedObject filename]];
        NSString *sizeString = @"";
        if ([representedObject fileSize] < 1000000) {
            sizeString = [NSString stringWithFormat:@"%.2f KB", [representedObject fileSize] / 1000.0];
        } else if ([representedObject fileSize] < 1000000000) {
            sizeString = [NSString stringWithFormat:@"%.2f MB", [representedObject fileSize] / 1000000.0];
        } else {
            sizeString = [NSString stringWithFormat:@"%.2f GB", [representedObject fileSize] / 1000000000.0];
        }
        [sizeTextField setStringValue:sizeString];
    }
}

- (IBAction)downloadAttachment:(id)sender {
    [downloadButton setHidden:YES];
    [downloadProgressIndicator setHidden:NO];
    [downloadProgressIndicator setIndeterminate:YES];
    [downloadProgressIndicator startAnimation:self];
    
    [saveFilePath release];
    
    NSString *path = [DLUtil downloadsPath];
    
    NSFileManager *man = [NSFileManager defaultManager];
    saveFilePath = [path stringByAppendingPathComponent:[representedObject filename]];
    
    NSInteger i = 1;
    while ([man fileExistsAtPath:saveFilePath]) {
        NSString *testName = [NSString stringWithFormat:@"%@-%ld.%@", [[representedObject filename] stringByDeletingPathExtension], i, [[representedObject filename] pathExtension]];
        saveFilePath = [path stringByAppendingPathComponent:testName];
        i++;
    }
    
    [saveFilePath retain];
    [representedObject downloadToPath:saveFilePath];
}

-(void)dealloc {
    [eventHandlerView setDelegate:nil];
    [eventHandlerView release];
    if ([attachmentView isKindOfClass:[WebView class]]) {
        WebView *videoView = (WebView *)attachmentView;
        [videoView setFrameLoadDelegate:nil];
        [videoView setResourceLoadDelegate:nil];
        [videoView setPolicyDelegate:nil];
        [videoView setUIDelegate:nil];
        [[videoView mainFrame] stopLoading];
        [videoView close];
    }
    [attachmentView release];
    [representedObject setPreviewDelegate:nil];
    [representedObject release];
    [attachmentViewerWindow setDelegate:nil];
    [attachmentViewerWindow release];
    [super dealloc];
}

#pragma mark Delegated Functions

-(void)attachment:(DLAttachment *)a previewDataWasUpdated:(NSData *)data {
    //Check type
    //if image:
    [imageView setImage:[[[NSImage alloc] initWithData:data] autorelease]];
}
-(void)attachment:(DLAttachment *)a downloadPercentageWasUpdated:(float)percent {
    if ([downloadProgressIndicator isIndeterminate]) {
        [downloadProgressIndicator setIndeterminate:NO];
        [downloadProgressIndicator setMinValue:0.0];
        [downloadProgressIndicator setMaxValue:100.0];
    }
    [downloadProgressIndicator setDoubleValue:percent];
}
-(void)attachmentDownloadDidComplete:(DLAttachment *)a {
    [downloadProgressIndicator stopAnimation:self];
    [downloadProgressIndicator setHidden:YES];
    [downloadButton setHidden:NO];
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"com.apple.DownloadFileFinished" object:saveFilePath];
}
-(void)mouseWasDepressedWithEvent:(NSEvent *)event {
    if (!attachmentViewerWindow) {
        attachmentViewerWindow = [[DLAttachmentWindowController alloc] initWithWindowNibName:@"DLAttachmentWindowController"];
        [attachmentViewerWindow setDelegate:self];
        [attachmentViewerWindow setViewedAttachmemt:representedObject];
    }
    [attachmentViewerWindow showWindow:attachmentViewerWindow.window];
}
-(void)viewerWindowDidClose {
    [attachmentViewerWindow release];
    attachmentViewerWindow = nil;
}


@end
