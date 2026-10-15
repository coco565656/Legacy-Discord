#import <Cocoa/Cocoa.h>

// Discord-style popout: a borderless, rounded, shadowed panel attached to the
// parent window. The same AppKit panel is used on every supported OS so that
// Snow Leopard and Lion+ look identical (NSPopover's arrow and system chrome
// do not match the Discord look and do not exist on 10.6).
enum {
    DLCompatibilityPopoverBehaviorTransient = 1
};

@interface DLCompatibilityPopover : NSObject <NSWindowDelegate> {
    NSPanel *fallbackPanel;
    NSView *panelContainerView;
    NSView *panelCornerView;
    NSViewController *contentViewController;
    NSWindow *parentWindow;
    id delegate;
    NSSize contentSize;
    BOOL fallbackShown;
}

- (void)setBehavior:(NSInteger)behavior;
- (void)setDelegate:(id)inDelegate;
- (void)setContentViewController:(NSViewController *)controller;
- (void)setContentSize:(NSSize)size;
- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge;
- (void)close;
- (BOOL)isShown;

@end
