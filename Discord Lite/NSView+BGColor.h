//
//  NSView+BGColor.h
//  Discord Lite
//
//  Created by Collin Mistr on 10/31/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "NSView+Events.h"

@interface NSView_BGColor : NSView_Events {
    NSColor *backgroundColor;
    NSColor *gradientStartColor;
    NSColor *gradientEndColor;
    NSColor *bottomBorderColor;
}

-(void)setBackgroundColor:(NSColor *)bgColor;
-(void)setGradientStartColor:(NSColor *)startColor endColor:(NSColor *)endColor;
-(void)setBottomBorderColor:(NSColor *)borderColor;

@end
