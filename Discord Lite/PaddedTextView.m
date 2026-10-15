//
//  PaddedTextView.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/2/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "PaddedTextView.h"
#import "DLUtil.h"
#import "DLTwemojiRenderer.h"

@implementation PaddedTextView

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    if ([placeholderString length] == 0 || [[self string] length] > 0) return;
    NSFont *font = [self font] ? [self font] : [NSFont systemFontOfSize:[NSFont systemFontSize]];
    // Channel names often contain emoji; Snow Leopard has no emoji font, so
    // the placeholder goes through the shared Twemoji path like other labels.
    if (!placeholderDisplay || ![placeholderDisplayFont isEqual:font]) {
        NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
        [style setLineBreakMode:NSLineBreakByTruncatingTail];
        NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                    font, NSFontAttributeName,
                                    [DLUtil nativeSecondaryTextColor], NSForegroundColorAttributeName,
                                    style, NSParagraphStyleAttributeName, nil];
        NSMutableAttributedString *display = [[[NSMutableAttributedString alloc]
            initWithString:placeholderString attributes:attributes] autorelease];
        [DLTwemojiRenderer replaceEmojiInAttributedString:display size:[font pointSize]
                                       excludingAttribute:nil recordingAttribute:nil cursorLocation:NULL];
        [placeholderDisplay release];
        placeholderDisplay = [display copy];
        [placeholderDisplayFont release];
        placeholderDisplayFont = [font retain];
    }
    NSPoint origin = [self textContainerOrigin];
    CGFloat padding = [[self textContainer] lineFragmentPadding];
    NSRect rect = NSMakeRect(origin.x + padding, origin.y,
                             MAX(0.0, NSWidth([self bounds]) - origin.x - padding * 2.0),
                             ceil([font ascender] - [font descender] + [font leading]) + 2.0);
    [placeholderDisplay drawInRect:rect];
}

-(void)setPlaceholderString:(NSString *)placeholder {
    if (placeholderString == placeholder || [placeholderString isEqualToString:placeholder]) return;
    [placeholderString release];
    placeholderString = [placeholder copy];
    [placeholderDisplay release];
    placeholderDisplay = nil;
    [self setNeedsDisplay:YES];
}

-(void)didChangeText {
    [super didChangeText];
    if ([placeholderString length] && [[self string] length] <= 1) [self setNeedsDisplay:YES];
}

-(void)setString:(NSString *)string {
    [super setString:string];
    if ([placeholderString length]) [self setNeedsDisplay:YES];
}

-(void)dealloc {
    [placeholderString release];
    [placeholderDisplay release];
    [placeholderDisplayFont release];
    [super dealloc];
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
        // Pasted images upload as "image.png" like the official client; each
        // paste gets its own temporary folder so the names never collide.
        NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:
                            [[NSProcessInfo processInfo] globallyUniqueString]];
        [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *path = [folder stringByAppendingPathComponent:@"image.png"];
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
