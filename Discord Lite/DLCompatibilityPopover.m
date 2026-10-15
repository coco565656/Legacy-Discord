#import "DLCompatibilityPopover.h"

@implementation DLCompatibilityPopover

- (id)init {
    self = [super init];
    if (self) {
        contentSize = NSMakeSize(320.0, 320.0);
        Class popoverClass = NSClassFromString(@"NSPopover");
        if (popoverClass) {
            nativePopover = [[popoverClass alloc] init];
            [nativePopover setDelegate:self];
        }
    }
    return self;
}

- (void)setBehavior:(NSInteger)behavior {
    if (nativePopover) {
        SEL selector = NSSelectorFromString(@"setBehavior:");
        typedef void (*DLSetBehaviorFunction)(id, SEL, NSInteger);
        DLSetBehaviorFunction function = (DLSetBehaviorFunction)[nativePopover methodForSelector:selector];
        if (function) function(nativePopover, selector, behavior);
    }
}

- (void)setDelegate:(id)inDelegate {
    delegate = inDelegate;
}

- (void)setContentViewController:(NSViewController *)controller {
    if (controller == contentViewController) return;
    [contentViewController release];
    contentViewController = [controller retain];
    if (nativePopover) {
        [nativePopover setContentViewController:controller];
    } else if (fallbackPanel) {
        [fallbackPanel setContentView:[controller view]];
    }
}

- (void)setContentSize:(NSSize)size {
    contentSize = size;
    if (nativePopover) [nativePopover setContentSize:size];
    if (fallbackPanel) [fallbackPanel setContentSize:size];
}

- (void)ensureFallbackPanel {
    if (fallbackPanel) return;
    NSUInteger style = NSTitledWindowMask | NSClosableWindowMask | NSUtilityWindowMask;
    fallbackPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0.0, 0.0, contentSize.width, contentSize.height)
                                               styleMask:style
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    [fallbackPanel setReleasedWhenClosed:NO];
    [fallbackPanel setFloatingPanel:YES];
    [fallbackPanel setHidesOnDeactivate:YES];
    [fallbackPanel setTitle:@"Legacy Discord"];
    [fallbackPanel setDelegate:self];
    if (contentViewController) [fallbackPanel setContentView:[contentViewController view]];
}

- (NSPoint)fallbackOriginForRect:(NSRect)rect view:(NSView *)view edge:(NSRectEdge)edge {
    NSRect windowRect = [view convertRect:rect toView:nil];
    NSPoint anchor = [[view window] convertBaseToScreen:windowRect.origin];
    CGFloat width = contentSize.width;
    CGFloat height = contentSize.height;
    if (edge == NSMinXEdge) {
        return NSMakePoint(anchor.x - width, anchor.y + NSHeight(windowRect) / 2.0 - height / 2.0);
    }
    if (edge == NSMaxXEdge) {
        return NSMakePoint(anchor.x + NSWidth(windowRect), anchor.y + NSHeight(windowRect) / 2.0 - height / 2.0);
    }
    if (edge == NSMinYEdge) {
        return NSMakePoint(anchor.x + NSWidth(windowRect) / 2.0 - width / 2.0, anchor.y - height);
    }
    return NSMakePoint(anchor.x + NSWidth(windowRect) / 2.0 - width / 2.0, anchor.y + NSHeight(windowRect));
}

- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge {
    if (nativePopover) {
        [nativePopover showRelativeToRect:rect ofView:view preferredEdge:edge];
        return;
    }
    if (!view || ![view window]) return;
    [self ensureFallbackPanel];
    parentWindow = [view window];
    [fallbackPanel setContentSize:contentSize];
    [fallbackPanel setFrameOrigin:[self fallbackOriginForRect:rect view:view edge:edge]];
    [parentWindow addChildWindow:fallbackPanel ordered:NSWindowAbove];
    fallbackShown = YES;
    [fallbackPanel makeKeyAndOrderFront:nil];
}

- (void)notifyDidClose {
    if ([delegate respondsToSelector:@selector(popoverDidClose:)]) {
        NSNotification *notification = [NSNotification notificationWithName:@"DLCompatibilityPopoverDidCloseNotification"
                                                                     object:self];
        [delegate popoverDidClose:notification];
    }
}

- (void)close {
    if (nativePopover) {
        [nativePopover close];
        return;
    }
    if (!fallbackShown) return;
    if (parentWindow) [parentWindow removeChildWindow:fallbackPanel];
    [fallbackPanel orderOut:nil];
    parentWindow = nil;
    fallbackShown = NO;
    [self notifyDidClose];
}

- (BOOL)isShown {
    if (nativePopover) return [nativePopover isShown];
    return fallbackShown && [fallbackPanel isVisible];
}

- (void)popoverDidClose:(NSNotification *)notification {
    [self notifyDidClose];
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
    [nativePopover setDelegate:nil];
    [nativePopover release];
    [fallbackPanel setDelegate:nil];
    [fallbackPanel close];
    [fallbackPanel release];
    [contentViewController release];
    [super dealloc];
}

@end
