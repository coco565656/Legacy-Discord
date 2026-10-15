#import <Cocoa/Cocoa.h>

// NSPopover was introduced in OS X 10.7. This wrapper keeps the native
// implementation on Lion and later and uses a small utility panel on 10.6.
enum {
    DLCompatibilityPopoverBehaviorTransient = 1
};

@interface DLCompatibilityPopover : NSObject <NSWindowDelegate> {
    id nativePopover;
    NSPanel *fallbackPanel;
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
