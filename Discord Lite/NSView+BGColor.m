//
//  NSView+BGColor.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/31/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "NSView+BGColor.h"

@implementation NSView_BGColor

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    if (gradientStartColor && gradientEndColor) {
        NSGradient *gradient = [[[NSGradient alloc] initWithStartingColor:gradientStartColor
                                                              endingColor:gradientEndColor] autorelease];
        [gradient drawInRect:[self bounds] angle:90.0];
    } else {
        NSColor *fillColor = backgroundColor ? backgroundColor : [NSColor clearColor];
        [fillColor set];
        NSRectFillUsingOperation([self bounds], NSCompositeSourceOver);
    }

    if (bottomBorderColor) {
        [bottomBorderColor set];
        NSRect borderRect = NSMakeRect(0.0, 0.0, NSWidth([self bounds]), 1.0);
        NSRectFill(borderRect);
    }
    if (leftBorderColor) {
        [leftBorderColor set];
        NSRectFill(NSMakeRect(0.0, 0.0, 1.0, NSHeight([self bounds])));
    }
}
-(void)setBackgroundColor:(NSColor *)bgColor {
    [backgroundColor release];
    backgroundColor = [bgColor retain];
    [gradientStartColor release];
    gradientStartColor = nil;
    [gradientEndColor release];
    gradientEndColor = nil;
    [self setNeedsDisplay:YES];
}
-(void)setGradientStartColor:(NSColor *)startColor endColor:(NSColor *)endColor {
    [gradientStartColor release];
    gradientStartColor = [startColor retain];
    [gradientEndColor release];
    gradientEndColor = [endColor retain];
    [self setNeedsDisplay:YES];
}
-(void)setBottomBorderColor:(NSColor *)borderColor {
    [bottomBorderColor release];
    bottomBorderColor = [borderColor retain];
    [self setNeedsDisplay:YES];
}
-(void)setLeftBorderColor:(NSColor *)borderColor {
    [leftBorderColor release];
    leftBorderColor = [borderColor retain];
    [self setNeedsDisplay:YES];
}
-(void)dealloc {
    [backgroundColor release];
    [gradientStartColor release];
    [gradientEndColor release];
    [bottomBorderColor release];
    [leftBorderColor release];
    [super dealloc];
}

@end
