//
//  AttachmentPreviewViewController.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/3/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "AttachmentPreviewViewController.h"
#import "DLLocalization.h"
#import "DLTextParser.h"
#import "DLController.h"
#import <WebKit/WebKit.h>
#import "DLUtil.h"

// Image attachments have no menu of their own, so a right-click follows the
// official client and opens the containing message row's context menu instead
// of being swallowed (the 10.6 base class does nothing when unhandled).
static void DLForwardRightMouseDownToMessageRow(NSView *view, NSEvent *event) {
    NSView *ancestor = [view superview];
    while (ancestor && ![ancestor isKindOfClass:[NSView_Events class]]) ancestor = [ancestor superview];
    if (ancestor) [ancestor rightMouseDown:event];
}

// Black "SPOILER" pill centred over a hidden image, like the official client.
@interface DLSpoilerLabelView : NSView
@end

@implementation DLSpoilerLabelView
-(NSView *)hitTest:(NSPoint)point {
    return nil;
}
-(void)drawRect:(NSRect)dirtyRect {
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont boldSystemFontOfSize:12.0], NSFontAttributeName,
                                [NSColor whiteColor], NSForegroundColorAttributeName, nil];
    NSSize size = [DLLocalizedString(@"SPOILER") sizeWithAttributes:attributes];
    NSRect pill = NSMakeRect(floor(NSMidX([self bounds]) - size.width / 2.0 - 12.0),
                             floor(NSMidY([self bounds]) - size.height / 2.0 - 5.0),
                             size.width + 24.0, size.height + 10.0);
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.75] set];
    [[NSBezierPath bezierPathWithRoundedRect:pill xRadius:NSHeight(pill) / 2.0 yRadius:NSHeight(pill) / 2.0] fill];
    [DLLocalizedString(@"SPOILER") drawAtPoint:NSMakePoint(NSMinX(pill) + 12.0, NSMinY(pill) + 5.0) withAttributes:attributes];
}
@end

// Heavily blurred and darkened copy of a spoiler image: drawn at a tiny
// size and scaled back up with smooth interpolation (no Core Image needed).
static NSImage *DLSpoilerImage(NSData *data) {
    NSImage *source = [[[NSImage alloc] initWithData:data] autorelease];
    NSSize size = [source size];
    if (size.width < 1.0 || size.height < 1.0) return nil;
    NSSize tiny = NSMakeSize(MAX(2.0, round(size.width / 24.0)), MAX(2.0, round(size.height / 24.0)));
    NSImage *small = [[[NSImage alloc] initWithSize:tiny] autorelease];
    [small lockFocus];
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    [source drawInRect:NSMakeRect(0, 0, tiny.width, tiny.height) fromRect:NSZeroRect operation:NSCompositeCopy fraction:1.0];
    [small unlockFocus];
    NSImage *blurred = [[[NSImage alloc] initWithSize:size] autorelease];
    [blurred lockFocus];
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    [small drawInRect:NSMakeRect(0, 0, size.width, size.height) fromRect:NSZeroRect operation:NSCompositeCopy fraction:1.0];
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.35] set];
    NSRectFillUsingOperation(NSMakeRect(0, 0, size.width, size.height), NSCompositeSourceOver);
    [blurred unlockFocus];
    return blurred;
}

// Attachments show rounded corners like the official client. 10.6 has no
// layer-based clipping, so the image view clips its own drawing.
@interface DLRoundedAttachmentImageView : NSImageView
@end

@implementation DLRoundedAttachmentImageView
-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    [NSGraphicsContext saveGraphicsState];
    CGFloat radius = MIN(8.0, MIN(NSWidth(bounds) / 2.0, NSHeight(bounds) / 2.0));
    [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:radius yRadius:radius] addClip];
    [super drawRect:dirtyRect];
    [NSGraphicsContext restoreGraphicsState];
}
@end

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
        imageView = [[DLRoundedAttachmentImageView alloc] initWithFrame:frame];
        attachmentView = imageView;
        
        //Add invisible overlay to handle mouse events
        eventHandlerView = [[NSView_Events alloc] initWithFrame:frame];
        [eventHandlerView setDelegate:self];
        [attachmentView addSubview:eventHandlerView];
        spoilerHidden = [[representedObject filename] hasPrefix:@"SPOILER_"] &&
            ![DLTextParser revealsSpoilersInServerWithID:[[[DLController existingInstance] selectedServer] serverID]];
        if (spoilerHidden) {
            spoilerLabel = [[DLSpoilerLabelView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
            [spoilerLabel setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
            [attachmentView addSubview:spoilerLabel positioned:NSWindowBelow relativeTo:eventHandlerView];
        }
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
        NSString *html = [NSString stringWithFormat:@"<html><body style='margin:0;background:#111;overflow:hidden'><video src=\"%@\" controls preload='metadata' style='width:100%%;height:100%%;border-radius:8px'></video></body></html>", escapedURL];
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
    [spoilerLabel release];
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
    NSImage *image = spoilerHidden ? DLSpoilerImage(data) : nil;
    if (!image) image = [[[NSImage alloc] initWithData:data] autorelease];
    [imageView setImage:image];
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
    if (spoilerHidden) {
        // First click reveals the spoiler; the next one opens the viewer.
        spoilerHidden = NO;
        [spoilerLabel removeFromSuperview];
        NSData *data = [representedObject scaledAttachmentData];
        if (data) [imageView setImage:[[[NSImage alloc] initWithData:data] autorelease]];
        return;
    }
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

-(void)mouseRightButtonWasDepressedWithEvent:(NSEvent *)event {
    DLForwardRightMouseDownToMessageRow(eventHandlerView, event);
}


@end
