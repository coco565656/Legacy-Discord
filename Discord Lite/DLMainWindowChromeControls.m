#import "DLMainWindowChromeControls.h"
#import "DLUtil.h"

@implementation DLDarkSplitView
-(void)drawDividerInRect:(NSRect)rect {
    [[DLUtil nativeBorderColor] set];
    NSRectFill(rect);
}
@end

@implementation DLDarkSearchFieldCell
-(void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    NSRect backgroundRect = NSInsetRect(cellFrame, 0.5, 0.5);
    [[DLUtil nativeInputColor] set];
    [[NSBezierPath bezierPathWithRoundedRect:backgroundRect xRadius:6.0 yRadius:6.0] fill];
    [[DLUtil nativeBorderColor] set];
    [[NSBezierPath bezierPathWithRoundedRect:backgroundRect xRadius:6.0 yRadius:6.0] stroke];
    [self drawInteriorWithFrame:NSInsetRect(cellFrame, 2.0, 1.0) inView:controlView];
}
@end

@implementation DLConnectionIndicatorView

-(void)setIndicatorColor:(NSColor *)color {
    if (indicatorColor != color) {
        [indicatorColor release];
        indicatorColor = [color retain];
    }
    [self setNeedsDisplay:YES];
}

-(void)drawRect:(NSRect)dirtyRect {
    NSRect circleRect = NSMakeRect(NSMidX([self bounds]) - 6.0, NSMidY([self bounds]) - 6.0, 12.0, 12.0);
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.18] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(circleRect, -1.0, -1.0)] fill];
    [(indicatorColor ? indicatorColor : [NSColor grayColor]) set];
    [[NSBezierPath bezierPathWithOvalInRect:circleRect] fill];
}

-(void)dealloc {
    [indicatorColor release];
    [super dealloc];
}

@end

@implementation DLMemberButton
-(void)drawRect:(NSRect)dirtyRect {
    [NSGraphicsContext saveGraphicsState];
    if ([self isFlipped]) {
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:0.0 yBy:NSHeight([self bounds])];
        [transform scaleXBy:1.0 yBy:-1.0];
        [transform concat];
    }
    NSColor *color = [self isEnabled] ? [DLUtil nativePrimaryTextColor] : [DLUtil nativeSecondaryTextColor];
    [color set];
    NSRect bounds = [self bounds];
    CGFloat cx = NSMidX(bounds);
    CGFloat cy = NSMidY(bounds);
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(cx - 7.0, cy + 1.0, 6.0, 6.0)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(cx + 2.0, cy + 2.0, 5.0, 5.0)] fill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(cx - 9.0, cy - 7.0, 10.0, 7.0)
                                     xRadius:3.0 yRadius:3.0] fill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(cx + 1.0, cy - 6.0, 8.0, 6.0)
                                     xRadius:3.0 yRadius:3.0] fill];
    [NSGraphicsContext restoreGraphicsState];
}
@end

@implementation DLPinsButton
-(void)drawRect:(NSRect)dirtyRect {
    [NSGraphicsContext saveGraphicsState];
    if ([self isFlipped]) {
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:0.0 yBy:NSHeight([self bounds])];
        [transform scaleXBy:1.0 yBy:-1.0];
        [transform concat];
    }
    NSColor *color = [self isEnabled] ? [DLUtil nativePrimaryTextColor] : [DLUtil nativeSecondaryTextColor];
    [color set];
    CGFloat cx = NSMidX([self bounds]);
    CGFloat cy = NSMidY([self bounds]);
    NSBezierPath *pin = [NSBezierPath bezierPath];
    [pin moveToPoint:NSMakePoint(cx - 5.0, cy + 6.0)];
    [pin lineToPoint:NSMakePoint(cx + 5.0, cy + 6.0)];
    [pin lineToPoint:NSMakePoint(cx + 3.0, cy + 1.0)];
    [pin lineToPoint:NSMakePoint(cx + 7.0, cy - 4.0)];
    [pin lineToPoint:NSMakePoint(cx - 7.0, cy - 4.0)];
    [pin lineToPoint:NSMakePoint(cx - 3.0, cy + 1.0)];
    [pin closePath];
    [pin fill];
    NSBezierPath *needle = [NSBezierPath bezierPath];
    [needle moveToPoint:NSMakePoint(cx, cy - 4.0)];
    [needle lineToPoint:NSMakePoint(cx, cy - 10.0)];
    [needle setLineWidth:1.5];
    [needle stroke];
    [NSGraphicsContext restoreGraphicsState];
}
@end
