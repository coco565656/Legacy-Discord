#import "DLCompatibilityPopover.h"
#import "DLUtil.h"

static const CGFloat DLPopoutCornerRadius = 8.0;
static const CGFloat DLPopoutAnchorGap = 6.0;
static const CGFloat DLPopoutScreenMargin = 8.0;

// Borderless panels refuse key status by default; the pickers need it for
// their search fields. Escape closes the popout like Discord.
@interface DLPopoutPanel : NSPanel {
    DLCompatibilityPopover *owner;
}
- (void)setOwner:(DLCompatibilityPopover *)inOwner;
@end

@implementation DLPopoutPanel
- (void)setOwner:(DLCompatibilityPopover *)inOwner {
    owner = inOwner;
}
- (BOOL)canBecomeKeyWindow {
    return YES;
}
- (void)cancelOperation:(id)sender {
    [owner close];
}
@end

// Drawn above the content. Without layers, 10.6 cannot clip subviews to a
// rounded path, so the corners outside the path are cleared to transparent
// after the content has drawn, then a 1-pixel border is stroked.
@interface DLPopoutCornerView : NSView
@end

@implementation DLPopoutCornerView
- (BOOL)isOpaque {
    return NO;
}
- (NSView *)hitTest:(NSPoint)point {
    return nil;
}
- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    NSBezierPath *rounded = [NSBezierPath bezierPathWithRoundedRect:bounds
                                                            xRadius:DLPopoutCornerRadius
                                                            yRadius:DLPopoutCornerRadius];
    NSBezierPath *corners = [NSBezierPath bezierPathWithRect:bounds];
    [corners appendBezierPath:rounded];
    [corners setWindingRule:NSEvenOddWindingRule];
    [NSGraphicsContext saveGraphicsState];
    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeCopy];
    [[NSColor clearColor] setFill];
    [corners fill];
    [NSGraphicsContext restoreGraphicsState];

    NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 0.5, 0.5)
                                                           xRadius:DLPopoutCornerRadius - 0.5
                                                           yRadius:DLPopoutCornerRadius - 0.5];
    [border setLineWidth:1.0];
    [[DLUtil nativeBorderColor] setStroke];
    [border stroke];
    [[self window] invalidateShadow];
}
@end

@implementation DLCompatibilityPopover

- (id)init {
    self = [super init];
    if (self) {
        contentSize = NSMakeSize(320.0, 320.0);
    }
    return self;
}

- (void)setBehavior:(NSInteger)behavior {
    // Popouts are always transient: they close when they lose key status.
}

- (void)setDelegate:(id)inDelegate {
    delegate = inDelegate;
}

- (void)installContentView {
    if (!panelContainerView) return;
    NSArray *existing = [[[panelContainerView subviews] copy] autorelease];
    for (NSView *subview in existing) {
        if (subview != panelCornerView) [subview removeFromSuperview];
    }
    NSView *content = [contentViewController view];
    if (!content) return;
    [content setFrame:[panelContainerView bounds]];
    [content setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [panelContainerView addSubview:content positioned:NSWindowBelow relativeTo:panelCornerView];
}

- (void)setContentViewController:(NSViewController *)controller {
    if (controller == contentViewController) return;
    [contentViewController release];
    contentViewController = [controller retain];
    [self installContentView];
}

- (void)setContentSize:(NSSize)size {
    contentSize = size;
    if (fallbackPanel) [fallbackPanel setContentSize:size];
}

- (void)ensureFallbackPanel {
    if (fallbackPanel) return;
    DLPopoutPanel *panel = [[DLPopoutPanel alloc] initWithContentRect:NSMakeRect(0.0, 0.0, contentSize.width, contentSize.height)
                                                            styleMask:NSBorderlessWindowMask
                                                              backing:NSBackingStoreBuffered
                                                                defer:NO];
    [panel setOwner:self];
    fallbackPanel = panel;
    [fallbackPanel setReleasedWhenClosed:NO];
    [fallbackPanel setFloatingPanel:YES];
    [fallbackPanel setHidesOnDeactivate:YES];
    [fallbackPanel setOpaque:NO];
    [fallbackPanel setBackgroundColor:[NSColor clearColor]];
    [fallbackPanel setHasShadow:YES];
    [fallbackPanel setDelegate:self];

    NSRect bounds = NSMakeRect(0.0, 0.0, contentSize.width, contentSize.height);
    panelContainerView = [[NSView alloc] initWithFrame:bounds];
    [panelContainerView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    panelCornerView = [[DLPopoutCornerView alloc] initWithFrame:bounds];
    [panelCornerView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [panelContainerView addSubview:panelCornerView];
    [fallbackPanel setContentView:panelContainerView];
    [self installContentView];
}

- (NSPoint)fallbackOriginForRect:(NSRect)rect view:(NSView *)view edge:(NSRectEdge)edge {
    NSRect windowRect = [view convertRect:rect toView:nil];
    NSPoint anchor = [[view window] convertBaseToScreen:windowRect.origin];
    CGFloat width = contentSize.width;
    CGFloat height = contentSize.height;
    NSPoint origin;
    // Side popouts (profiles) line up with the top of the clicked row, like
    // the official client, instead of centring on it.
    CGFloat sideTop = anchor.y + NSHeight(windowRect);
    if (edge == NSMinXEdge) {
        origin = NSMakePoint(anchor.x - width - DLPopoutAnchorGap, sideTop - height);
    } else if (edge == NSMaxXEdge) {
        origin = NSMakePoint(anchor.x + NSWidth(windowRect) + DLPopoutAnchorGap, sideTop - height);
    } else if (edge == NSMinYEdge) {
        origin = NSMakePoint(anchor.x + NSWidth(windowRect) / 2.0 - width / 2.0, anchor.y - height - DLPopoutAnchorGap);
    } else {
        origin = NSMakePoint(anchor.x + NSWidth(windowRect) / 2.0 - width / 2.0, anchor.y + NSHeight(windowRect) + DLPopoutAnchorGap);
    }

    // Keep it inside the window's content area (below the title bar) first.
    NSWindow *window = [view window];
    NSRect content = [window contentRectForFrameRect:[window frame]];
    content = NSInsetRect(content, 8.0, 8.0);
    if (height <= NSHeight(content)) {
        if (origin.y + height > NSMaxY(content)) origin.y = NSMaxY(content) - height;
        if (origin.y < NSMinY(content)) origin.y = NSMinY(content);
    }
    if (width <= NSWidth(content)) {
        if (origin.x + width > NSMaxX(content)) origin.x = NSMaxX(content) - width;
        if (origin.x < NSMinX(content)) origin.x = NSMinX(content);
    }
    NSScreen *screen = [[view window] screen] ? [[view window] screen] : [NSScreen mainScreen];
    if (screen) {
        NSRect visible = NSInsetRect([screen visibleFrame], DLPopoutScreenMargin, DLPopoutScreenMargin);
        if (origin.x + width > NSMaxX(visible)) origin.x = NSMaxX(visible) - width;
        if (origin.x < NSMinX(visible)) origin.x = NSMinX(visible);
        if (origin.y + height > NSMaxY(visible)) origin.y = NSMaxY(visible) - height;
        if (origin.y < NSMinY(visible)) origin.y = NSMinY(visible);
    }
    return NSMakePoint(round(origin.x), round(origin.y));
}

- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge {
    if (!view || ![view window]) return;
    [self ensureFallbackPanel];
    parentWindow = [view window];
    [fallbackPanel setContentSize:contentSize];
    [fallbackPanel setFrameOrigin:[self fallbackOriginForRect:rect view:view edge:edge]];
    [parentWindow addChildWindow:fallbackPanel ordered:NSWindowAbove];
    fallbackShown = YES;
    [fallbackPanel makeKeyAndOrderFront:nil];
    [fallbackPanel invalidateShadow];
}

- (void)notifyDidClose {
    if ([delegate respondsToSelector:@selector(popoverDidClose:)]) {
        NSNotification *notification = [NSNotification notificationWithName:@"DLCompatibilityPopoverDidCloseNotification"
                                                                     object:self];
        [delegate popoverDidClose:notification];
    }
}

- (void)close {
    if (!fallbackShown) return;
    if (parentWindow) [parentWindow removeChildWindow:fallbackPanel];
    [fallbackPanel orderOut:nil];
    parentWindow = nil;
    fallbackShown = NO;
    [self notifyDidClose];
}

- (BOOL)isShown {
    return fallbackShown && [fallbackPanel isVisible];
}

- (void)windowWillClose:(NSNotification *)notification {
    if (!fallbackShown) return;
    if (parentWindow) [parentWindow removeChildWindow:fallbackPanel];
    parentWindow = nil;
    fallbackShown = NO;
    [self notifyDidClose];
}

- (void)windowDidResignKey:(NSNotification *)notification {
    [self close];
}

- (void)dealloc {
    [(DLPopoutPanel *)fallbackPanel setOwner:nil];
    [fallbackPanel setDelegate:nil];
    [fallbackPanel close];
    [fallbackPanel release];
    [panelCornerView release];
    [panelContainerView release];
    [contentViewController release];
    [super dealloc];
}

@end
