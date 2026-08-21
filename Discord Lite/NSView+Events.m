//
//  NSView+Events.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/12/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "NSView+Events.h"

@implementation NSView_Events

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    // Drawing code here.
}

-(void)setDelegate:(id<NSViewEventDelegate>)inDelegate {
    delegate = inDelegate;
}
-(void)mouseDown:(NSEvent *)theEvent {
    if ([delegate respondsToSelector:@selector(mouseWasDepressedWithEvent:)]) {
        [delegate mouseWasDepressedWithEvent:theEvent];
    }
}
-(void)rightMouseDown:(NSEvent *)theEvent {
    if ([delegate respondsToSelector:@selector(mouseRightButtonWasDepressedWithEvent:)]) {
        [delegate mouseRightButtonWasDepressedWithEvent:theEvent];
    }
}
-(void)viewDidMoveToWindow {
    [self updateTrackingAreas];
    if ([delegate respondsToSelector:@selector(viewMovedToWindow:)]) {
        [delegate viewMovedToWindow:self];
    }
}
-(void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (eventTrackingArea) {
        [self removeTrackingArea:eventTrackingArea];
        [eventTrackingArea release];
        eventTrackingArea = nil;
    }
    if ([self window]) {
        NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited |
            NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect;
        eventTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
            options:options owner:self userInfo:nil];
        [self addTrackingArea:eventTrackingArea];
    }
}
-(void)mouseEntered:(NSEvent *)event {
    if ([delegate respondsToSelector:@selector(mouseEnteredView:)]) {
        [delegate mouseEnteredView:self];
    }
}
-(void)mouseExited:(NSEvent *)event {
    if ([delegate respondsToSelector:@selector(mouseExitedView:)]) {
        [delegate mouseExitedView:self];
    }
}
-(void)dealloc {
    if (eventTrackingArea) {
        [self removeTrackingArea:eventTrackingArea];
        [eventTrackingArea release];
    }
    [super dealloc];
}
@end
