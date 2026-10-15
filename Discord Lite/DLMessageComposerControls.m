#import "DLMessageComposerControls.h"
#import "DLUtil.h"

@implementation DLMessageComposerBackgroundView

-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = NSInsetRect([self bounds], 0.5, 0.5);
    NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:7.0 yRadius:7.0];
    [[DLUtil nativeInputColor] set];
    [background fill];
    [[DLUtil nativeBorderColor] set];
    [background setLineWidth:1.0];
    [background stroke];
}

@end

@implementation DLEmojiButton

-(void)drawRect:(NSRect)dirtyRect {
    [NSGraphicsContext saveGraphicsState];
    if ([self isFlipped]) {
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:0.0 yBy:NSHeight([self bounds])];
        [transform scaleXBy:1.0 yBy:-1.0];
        [transform concat];
    }
    NSRect bounds = [self bounds];
    NSPoint center = NSMakePoint(NSMidX(bounds), NSMidY(bounds));
    NSColor *faceColor = [self isEnabled] ? [DLUtil nativePrimaryTextColor]
                                           : [DLUtil nativeSecondaryTextColor];
    [faceColor set];

    NSBezierPath *face = [NSBezierPath bezierPathWithOvalInRect:
                          NSMakeRect(center.x - 8.0, center.y - 8.0, 16.0, 16.0)];
    [face setLineWidth:1.8];
    [face stroke];

    CGFloat eyeY = center.y + 2.0;
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x - 4.5, eyeY, 2.0, 2.0)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x + 2.5, eyeY, 2.0, 2.0)] fill];

    NSBezierPath *smile = [NSBezierPath bezierPath];
    CGFloat mouthY = center.y - 2.0;
    CGFloat smileY = center.y - 5.0;
    [smile moveToPoint:NSMakePoint(center.x - 4.5, mouthY)];
    [smile curveToPoint:NSMakePoint(center.x + 4.5, mouthY)
           controlPoint1:NSMakePoint(center.x - 2.5, smileY)
           controlPoint2:NSMakePoint(center.x + 2.5, smileY)];
    [smile setLineWidth:2.0];
    [smile stroke];
    [NSGraphicsContext restoreGraphicsState];
}

@end

@implementation DLStickerButton

-(void)drawRect:(NSRect)dirtyRect {
    [NSGraphicsContext saveGraphicsState];
    if ([self isFlipped]) {
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:0.0 yBy:NSHeight([self bounds])];
        [transform scaleXBy:1.0 yBy:-1.0];
        [transform concat];
    }
    NSColor *color = [self isEnabled] ? [DLUtil nativePrimaryTextColor]
                                      : [DLUtil nativeSecondaryTextColor];
    [color set];
    NSRect bounds = [self bounds];
    NSRect stickerRect = NSMakeRect(NSMidX(bounds) - 7.5, NSMidY(bounds) - 7.5, 15.0, 15.0);
    NSBezierPath *sticker = [NSBezierPath bezierPath];
    [sticker moveToPoint:NSMakePoint(NSMinX(stickerRect), NSMinY(stickerRect))];
    [sticker lineToPoint:NSMakePoint(NSMinX(stickerRect), NSMaxY(stickerRect))];
    [sticker lineToPoint:NSMakePoint(NSMaxX(stickerRect), NSMaxY(stickerRect))];
    [sticker lineToPoint:NSMakePoint(NSMaxX(stickerRect), NSMinY(stickerRect) + 5.0)];
    [sticker lineToPoint:NSMakePoint(NSMaxX(stickerRect) - 5.0, NSMinY(stickerRect))];
    [sticker closePath];
    [sticker setLineWidth:1.8];
    [sticker stroke];
    NSBezierPath *fold = [NSBezierPath bezierPath];
    [fold moveToPoint:NSMakePoint(NSMaxX(stickerRect) - 5.0, NSMinY(stickerRect))];
    [fold lineToPoint:NSMakePoint(NSMaxX(stickerRect) - 5.0, NSMinY(stickerRect) + 5.0)];
    [fold lineToPoint:NSMakePoint(NSMaxX(stickerRect), NSMinY(stickerRect) + 5.0)];
    [fold setLineWidth:1.5];
    [fold stroke];
    [NSGraphicsContext restoreGraphicsState];
}

@end
