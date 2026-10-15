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

// Microphone / headphone buttons of the account panel.
@interface DLUserPanelIconButton : NSButton {
    NSInteger iconKind;
}
-(void)setIconKind:(NSInteger)kind;
@end
