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

@implementation DLStatusDotView
-(void)setDotColor:(NSColor *)color ringColor:(NSColor *)ring {
    [color retain]; [dotColor release]; dotColor = color;
    [ring retain]; [ringColor release]; ringColor = ring;
    [self setNeedsDisplay:YES];
}
-(BOOL)isOpaque {
    return NO;
}
-(NSView *)hitTest:(NSPoint)point {
    return nil;
}
-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    if (ringColor) {
        [ringColor setFill];
        [[NSBezierPath bezierPathWithOvalInRect:bounds] fill];
    }
    [(dotColor ? dotColor : [DLUtil nativeOfflineStatusColor]) setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(bounds, 2.5, 2.5)] fill];
}
-(void)dealloc {
    [dotColor release];
    [ringColor release];
    [super dealloc];
}
@end

@implementation DLUserPanelIconButton
-(void)setIconKind:(NSInteger)kind {
    iconKind = kind;
    [self setNeedsDisplay:YES];
}
-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    NSColor *color = [DLUtil nativeSecondaryTextColor];
    if (![self isEnabled]) color = [color colorWithAlphaComponent:0.45];
    else if ([[self cell] isHighlighted]) color = [DLUtil nativePrimaryTextColor];
    [color set];
    CGFloat cx = floor(NSMidX(bounds)) + 0.5;
    CGFloat cy = floor(NSMidY(bounds));
    BOOL flipped = [self isFlipped];
    CGFloat up = flipped ? -1.0 : 1.0;
    if (iconKind == DLUserPanelIconMicrophone) {
        NSRect capsule = NSMakeRect(cx - 3.5, cy - (flipped ? 6.0 : 1.0), 7.0, 9.0);
        [[NSBezierPath bezierPathWithRoundedRect:capsule xRadius:3.5 yRadius:3.5] fill];
        NSBezierPath *cup = [NSBezierPath bezierPath];
        [cup appendBezierPathWithArcWithCenter:NSMakePoint(cx, cy + 2.0 * up) radius:6.0
                                    startAngle:(flipped ? 0.0 : 180.0) endAngle:(flipped ? 180.0 : 360.0) clockwise:NO];
        [cup moveToPoint:NSMakePoint(cx, cy - 4.0 * up)];
        [cup lineToPoint:NSMakePoint(cx, cy - 7.0 * up)];
        [cup setLineWidth:1.6];
        [cup stroke];
    } else {
        NSBezierPath *band = [NSBezierPath bezierPath];
        [band appendBezierPathWithArcWithCenter:NSMakePoint(cx, cy) radius:7.0
                                     startAngle:(flipped ? 180.0 : 0.0) endAngle:(flipped ? 360.0 : 180.0) clockwise:NO];
        [band setLineWidth:1.8];
        [band stroke];
        CGFloat earY = flipped ? cy : cy - 7.0;
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(cx - 8.0, earY, 4.5, 7.0) xRadius:1.5 yRadius:1.5] fill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(cx + 3.5, earY, 4.5, 7.0) xRadius:1.5 yRadius:1.5] fill];
    }
}
@end

@implementation DLDarkPopUpButtonCell
-(void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    NSRect boxRect = NSInsetRect(cellFrame, 1.5, 1.5);
    NSBezierPath *box = [NSBezierPath bezierPathWithRoundedRect:boxRect xRadius:4.0 yRadius:4.0];
    [[DLUtil nativeServerRailColor] setFill];
    [box fill];
    [[DLUtil nativeBorderColor] setStroke];
    [box setLineWidth:1.0];
    [box stroke];

    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [style setLineBreakMode:NSLineBreakByTruncatingTail];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont systemFontOfSize:12.0], NSFontAttributeName,
                                ([self isEnabled] ? [DLUtil nativePrimaryTextColor] : [DLUtil nativeSecondaryTextColor]), NSForegroundColorAttributeName,
                                style, NSParagraphStyleAttributeName, nil];
    NSString *title = [self titleOfSelectedItem] ? [self titleOfSelectedItem] : @"";
    NSSize titleSize = [title sizeWithAttributes:attributes];
    [title drawInRect:NSMakeRect(NSMinX(boxRect) + 10.0, floor(NSMidY(boxRect) - titleSize.height / 2.0),
                                 MAX(0.0, NSWidth(boxRect) - 34.0), titleSize.height)
       withAttributes:attributes];

    BOOL flipped = [controlView isFlipped];
    CGFloat cx = NSMaxX(boxRect) - 14.0;
    CGFloat cy = NSMidY(boxRect);
    CGFloat dy = flipped ? 2.0 : -2.0;
    NSBezierPath *chevron = [NSBezierPath bezierPath];
    [chevron moveToPoint:NSMakePoint(cx - 4.0, cy - dy)];
    [chevron lineToPoint:NSMakePoint(cx, cy + dy)];
    [chevron lineToPoint:NSMakePoint(cx + 4.0, cy - dy)];
    [chevron setLineWidth:1.5];
    [chevron setLineCapStyle:NSRoundLineCapStyle];
    [chevron setLineJoinStyle:NSRoundLineJoinStyle];
    [[DLUtil nativeSecondaryTextColor] setStroke];
    [chevron stroke];
}
@end

@implementation DLContextTableView
-(id)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) hoveredRow = -1;
    return self;
}
-(NSInteger)menuRow {
    return menuRow;
}
-(NSInteger)hoveredRow {
    return hoveredRow;
}
-(void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (hoverTrackingArea) {
        [self removeTrackingArea:hoverTrackingArea];
        [hoverTrackingArea release];
        hoverTrackingArea = nil;
    }
    hoverTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:(NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect)
        owner:self userInfo:nil];
    [self addTrackingArea:hoverTrackingArea];
}
-(void)setHoveredRow:(NSInteger)row {
    if (row == hoveredRow) return;
    if (hoveredRow >= 0 && hoveredRow < [self numberOfRows]) [self setNeedsDisplayInRect:[self rectOfRow:hoveredRow]];
    hoveredRow = row;
    if (hoveredRow >= 0 && hoveredRow < [self numberOfRows]) [self setNeedsDisplayInRect:[self rectOfRow:hoveredRow]];
}
-(void)mouseMoved:(NSEvent *)event {
    [self setHoveredRow:[self rowAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]]];
}
-(void)mouseExited:(NSEvent *)event {
    [self setHoveredRow:-1];
}
-(void)dealloc {
    if (hoverTrackingArea) [self removeTrackingArea:hoverTrackingArea];
    [hoverTrackingArea release];
    [super dealloc];
}
// Not calling super skips the Aqua context-menu row outline; the menu's
// delegate builds items for menuRow.
-(NSMenu *)menuForEvent:(NSEvent *)event {
    menuRow = [self rowAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
    return menuRow >= 0 ? [self menu] : nil;
}
@end
