#import <Cocoa/Cocoa.h>

@interface DLDarkSplitView : NSSplitView
@end

@interface DLDarkSearchFieldCell : NSSearchFieldCell
@end

@interface DLConnectionIndicatorView : NSView {
    NSColor *indicatorColor;
}
-(void)setIndicatorColor:(NSColor *)color;
@end

@interface DLMemberButton : NSButton
@end

// Official "Threads" header icon: a hash mark with a speech bubble.
@interface DLThreadsButton : NSButton
@end

@interface DLPinsButton : NSButton
@end

// Presence dot drawn over the bottom-right of an avatar, ringed with the
// background color like Discord. Does not take mouse events.
@interface DLStatusDotView : NSView {
    NSColor *dotColor;
    NSColor *ringColor;
}
-(void)setDotColor:(NSColor *)color ringColor:(NSColor *)ring;
@end

enum {
    DLUserPanelIconMicrophone = 0,
    DLUserPanelIconHeadphones = 1
};

// Table that shows its menu without AppKit's blue "clicked row" outline.
// menuRow is the row under the right-click, for the menu delegate.
@interface DLContextTableView : NSTableView {
    NSInteger menuRow;
    NSInteger hoveredRow;
    NSTrackingArea *hoverTrackingArea;
}
-(NSInteger)menuRow;
// Row under the mouse (-1 when none), for Discord-style hover states.
-(NSInteger)hoveredRow;
@end

// Discord-style dark dropdown in place of the white Aqua pop-up bezel. The
// menu itself stays the native AppKit menu.
@interface DLDarkPopUpButtonCell : NSPopUpButtonCell
@end

// Dark Discord-style title bar painted over a standard titled window's title
// area. The native frame keeps the traffic-light buttons, dragging,
// double-click and resizing; this view only draws and ignores the mouse.
@interface DLDarkTitlebarView : NSView {
    NSString *drawnTitle;
}
// Adds the overlay to window's frame view, below its standard buttons.
+(void)installInWindow:(NSWindow *)window;
@end

// Discord's filled blurple button (Log In and other primary actions).
@interface DLPrimaryButton : NSButton
@end

// Microphone / headphone buttons of the account panel.
@interface DLUserPanelIconButton : NSButton {
    NSInteger iconKind;
}
-(void)setIconKind:(NSInteger)kind;
@end
