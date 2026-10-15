//
//  NSScroller+BGColor.m
//  Discord Lite
//
//  Created by Collin Mistr on 10/4/22.
//  Copyright (c) 2022 dosdude1. All rights reserved.
//

#import "NSScroller+BGColor.h"
#import "DLUtil.h"

@implementation NSScroller_BGColor

- (void)drawRect:(NSRect)dirtyRect {
    
    if (backgroundColor) {
        [backgroundColor setFill];
        NSRectFillUsingOperation([self bounds], NSCompositeSourceOver);
    }
    
    NSUsableScrollerParts usableParts = [self usableParts];
    if (usableParts == NSAllScrollerParts) {
        [self drawKnob];
    }
}

// Discord-style thin rounded thumb instead of the Aqua knob. The slot is
// repainted first because AppKit may call drawKnob outside drawRect: while
// tracking, which would otherwise leave the previous knob position behind.
- (void)drawKnob {
    if (backgroundColor) {
        [backgroundColor setFill];
        NSRectFillUsingOperation([self rectForPart:NSScrollerKnobSlot], NSCompositeSourceOver);
    }
    NSRect knobRect = [self rectForPart:NSScrollerKnob];
    if (NSIsEmptyRect(knobRect)) return;
    BOOL vertical = NSHeight([self bounds]) >= NSWidth([self bounds]);
    CGFloat crossLength = vertical ? NSWidth(knobRect) : NSHeight(knobRect);
    CGFloat thickness = MIN(8.0, MAX(2.0, crossLength - 4.0));
    CGFloat crossInset = floor((crossLength - thickness) / 2.0);
    knobRect = vertical ? NSInsetRect(knobRect, crossInset, 2.0) : NSInsetRect(knobRect, 2.0, crossInset);
    if (NSIsEmptyRect(knobRect)) return;
    [[DLUtil nativeScrollerKnobColor] setFill];
    CGFloat radius = thickness / 2.0;
    [[NSBezierPath bezierPathWithRoundedRect:knobRect xRadius:radius yRadius:radius] fill];
}

-(void)setBackgroundColor:(NSColor *)bgColor {
    if (backgroundColor == bgColor) return;
    [bgColor retain];
    [backgroundColor release];
    backgroundColor = bgColor;
    [self setNeedsDisplay:YES];
}

-(void)dealloc {
    [backgroundColor release];
    [super dealloc];
}

@end
