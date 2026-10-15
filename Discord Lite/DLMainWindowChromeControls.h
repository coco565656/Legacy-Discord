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
