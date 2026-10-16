//
//  PendingAttachmentViewController.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/14/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "PendingAttachmentViewController.h"
#import "DLLocalization.h"

@interface PendingAttachmentViewController ()
-(void)updateSpoilerDisplay;
@end

@implementation PendingAttachmentViewController

-(void)setDelegate:(id<PendingAttachmentItemDelegate>)inDelegate {
    delegate = inDelegate;
}

-(void)setRepresentedObject:(DLAttachment *)a {
    [representedObject release];
    [a retain];
    representedObject = a;
    
    if ([representedObject type] == AttachmentTypeImage) {
        [attachmentImageView setImage:[[[NSImage alloc] initWithData:[representedObject attachmentData]] autorelease]];
    } else {
        [attachmentImageView setImage:[[NSWorkspace sharedWorkspace] iconForFileType:[[representedObject filename] pathExtension]]];
        [filenameTextField setHidden:NO];
        [filenameTextField setStringValue:[representedObject filename]];
    }
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    [menu setDelegate:(id)self];
    [[self view] setMenu:menu];
    [attachmentImageView setMenu:menu];
    [self updateSpoilerDisplay];
    
    
}

-(DLAttachment *)representedObject {
    return representedObject;
}

// Discord marks spoilers by the SPOILER_ filename prefix.
-(BOOL)isSpoiler {
    return [[representedObject filename] hasPrefix:@"SPOILER_"];
}

-(void)updateSpoilerDisplay {
    BOOL spoiler = [self isSpoiler];
    if ([representedObject type] == AttachmentTypeImage) {
        [filenameTextField setHidden:!spoiler];
        [filenameTextField setStringValue:(spoiler ? DLLocalizedString(@"SPOILER") : @"")];
        [attachmentImageView setAlphaValue:(spoiler ? 0.35 : 1.0)];
    } else {
        [filenameTextField setStringValue:[representedObject filename]];
    }
}

-(void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    NSMenuItem *spoiler = [[[NSMenuItem alloc] initWithTitle:([self isSpoiler] ? DLLocalizedString(@"Remove Spoiler") : DLLocalizedString(@"Mark as Spoiler"))
                                                      action:@selector(toggleSpoiler:) keyEquivalent:@""] autorelease];
    [spoiler setTarget:self];
    [menu addItem:spoiler];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *remove = [[[NSMenuItem alloc] initWithTitle:DLLocalizedString(@"Remove Attachment") action:@selector(deleteItem:) keyEquivalent:@""] autorelease];
    [remove setTarget:self];
    [menu addItem:remove];
}

-(void)toggleSpoiler:(id)sender {
    NSString *name = [representedObject filename];
    [representedObject setFilename:([self isSpoiler] ? [name substringFromIndex:8] : [@"SPOILER_" stringByAppendingString:name])];
    [self updateSpoilerDisplay];
}

- (IBAction)deleteItem:(id)sender {
    [delegate pendingAttachmentItemWasRemoved:self];
}

-(void)dealloc {
    [representedObject release];
    [self.view release];
    [super dealloc];
}
@end
