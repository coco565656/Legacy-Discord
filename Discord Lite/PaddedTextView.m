//
//  PaddedTextView.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/2/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "PaddedTextView.h"

@implementation PaddedTextView

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    // Drawing code here.
}

- (void)awakeFromNib {
    [super setTextContainerInset:NSMakeSize(0.0f, 3.0f)];
    [self setAllowsUndo:YES];
}

-(void)paste:(id)sender {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    NSArray *filePaths = [pasteboard propertyListForType:NSFilenamesPboardType];
    if ([filePaths count] > 0 &&
        [[self delegate] respondsToSelector:@selector(updatePendingAttachmentsWithFilePaths:)]) {
        [(id)[self delegate] updatePendingAttachmentsWithFilePaths:filePaths];
        return;
    }

    NSData *imageData = [pasteboard dataForType:@"public.png"];
    if (!imageData) {
        NSImage *clipboardImage = [[[NSImage alloc] initWithPasteboard:pasteboard] autorelease];
        NSData *tiffData = [clipboardImage TIFFRepresentation];
        if (tiffData) {
            NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:tiffData];
            imageData = [imageRep representationUsingType:NSPNGFileType
                                                properties:[NSDictionary dictionary]];
        }
    }
    if (imageData &&
        [[self delegate] respondsToSelector:@selector(updatePendingAttachmentsWithFilePaths:)]) {
        NSString *filename = [NSString stringWithFormat:@"pasted-image-%@.%@",
                              [[NSProcessInfo processInfo] globallyUniqueString], @"png"];
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
        if ([imageData writeToFile:path atomically:YES]) {
            [(id)[self delegate] updatePendingAttachmentsWithFilePaths:[NSArray arrayWithObject:path]];
            return;
        }
    }
    [super paste:sender];
}

-(BOOL)performKeyEquivalent:(NSEvent *)event {
    NSString *characters = [[event charactersIgnoringModifiers] lowercaseString];
    NSUInteger modifierFlags = [event modifierFlags];
    if ((modifierFlags & NSCommandKeyMask) == NSCommandKeyMask &&
        [characters isEqualToString:@"v"] && [self isEditable]) {
        [self paste:self];
        return YES;
    }
    if ((modifierFlags & NSCommandKeyMask) == NSCommandKeyMask &&
        [characters isEqualToString:@"z"] && [self isEditable]) {
        NSUndoManager *undoManager = [self undoManager];
        if ((modifierFlags & NSShiftKeyMask) == NSShiftKeyMask) {
            if ([undoManager canRedo]) {
                [undoManager redo];
                return YES;
            }
        } else if ([undoManager canUndo]) {
            [undoManager undo];
            return YES;
        }
    }
    return [super performKeyEquivalent:event];
}

@end
