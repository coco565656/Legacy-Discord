//
//  DLDialog.m
//  Legacy Discord
//

#import "DLDialog.h"
#import "DLDarkMenu.h"
#import "DLUtil.h"
#import "NSScroller+BGColor.h"

#define DLDialogPadding 16.0
#define DLDialogFooterHeight 70.0

static NSColor *DLDialogCardColor(void) { return [DLUtil nativeContentColor]; }
static NSColor *DLDialogFooterColor(void) { return [DLUtil nativeSidebarColor]; }

@interface DLDialogPanel : NSPanel {
    DLDialog *owner;
}
-(void)setOwner:(DLDialog *)owner;
@end

@interface DLDialogBackdropView : NSView {
    DLDialog *owner;
}
-(void)setOwner:(DLDialog *)owner;
@end

@interface DLDialogCardView : NSView
@end

@interface DLDialogButton : NSButton {
    DLDialogButtonStyle style;
}
-(void)setStyle:(DLDialogButtonStyle)style;
@end

@interface DLDialog ()
-(void)cancel;
-(void)buttonPressed:(id)sender;
-(void)layoutWindows;
@end

@implementation DLDialogPanel
-(BOOL)canBecomeKeyWindow { return YES; }
-(BOOL)canBecomeMainWindow { return NO; }
-(void)setOwner:(DLDialog *)inOwner { owner = inOwner; }
-(void)cancelOperation:(id)sender { [owner cancel]; }
-(NSText *)fieldEditor:(BOOL)createFlag forObject:(id)object {
    NSText *editor = [super fieldEditor:createFlag forObject:object];
    if ([editor isKindOfClass:[NSTextView class]]) {
        [(NSTextView *)editor setInsertionPointColor:[DLUtil nativePrimaryTextColor]];
        NSMutableDictionary *selection = [NSMutableDictionary dictionary];
        [selection setObject:[NSColor colorWithCalibratedRed:0.345 green:0.396 blue:0.949 alpha:0.6] forKey:NSBackgroundColorAttributeName];
        [(NSTextView *)editor setSelectedTextAttributes:selection];
    }
    return editor;
}
@end

@implementation DLDialogBackdropView
-(void)setOwner:(DLDialog *)inOwner { owner = inOwner; }
-(void)drawRect:(NSRect)dirtyRect {
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.7] setFill];
    NSRectFill(dirtyRect);
}
-(BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
-(void)mouseDown:(NSEvent *)event { [owner cancel]; }
@end

@implementation DLDialogCardView
-(BOOL)isFlipped { return YES; }
-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    NSBezierPath *card = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:8.0 yRadius:8.0];
    [DLDialogCardColor() setFill];
    [card fill];
    [NSGraphicsContext saveGraphicsState];
    [card addClip];
    [DLDialogFooterColor() setFill];
    NSRectFill(NSMakeRect(0.0, NSHeight(bounds) - DLDialogFooterHeight, NSWidth(bounds), DLDialogFooterHeight));
    [NSGraphicsContext restoreGraphicsState];
}
@end

@implementation DLDialogButton
-(void)setStyle:(DLDialogButtonStyle)inStyle { style = inStyle; [self setNeedsDisplay:YES]; }
-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    BOOL pressed = [[self cell] isHighlighted];
    CGFloat alpha = [self isEnabled] ? 1.0 : 0.5;
    NSColor *textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:alpha];
    if (style == DLDialogButtonStylePrimary || style == DLDialogButtonStyleDanger) {
        NSColor *fill = (style == DLDialogButtonStylePrimary)
            ? (pressed ? [NSColor colorWithCalibratedRed:0.278 green:0.322 blue:0.769 alpha:alpha]
                       : [NSColor colorWithCalibratedRed:0.345 green:0.396 blue:0.949 alpha:alpha])
            : (pressed ? [NSColor colorWithCalibratedRed:0.631 green:0.157 blue:0.169 alpha:alpha]
                       : [NSColor colorWithCalibratedRed:0.855 green:0.216 blue:0.235 alpha:alpha]);
        [fill setFill];
        [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:4.0 yRadius:4.0] fill];
    } else {
        textColor = [[DLUtil nativePrimaryTextColor] colorWithAlphaComponent:alpha];
    }
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                       [NSFont boldSystemFontOfSize:13.0], NSFontAttributeName,
                                       textColor, NSForegroundColorAttributeName, nil];
    if (style == DLDialogButtonStyleLink && pressed) {
        [attributes setObject:[NSNumber numberWithInt:NSUnderlineStyleSingle] forKey:NSUnderlineStyleAttributeName];
    }
    NSSize size = [[self title] sizeWithAttributes:attributes];
    [[self title] drawAtPoint:NSMakePoint(floor(NSMidX(bounds) - size.width / 2.0),
                                          floor(NSMidY(bounds) - size.height / 2.0) + ([self isFlipped] ? 0.0 : 1.0))
               withAttributes:attributes];
}
@end

@implementation DLDialog

+(DLDialog *)dialogWithTitle:(NSString *)inTitle message:(NSString *)inMessage {
    DLDialog *dialog = [[[DLDialog alloc] init] autorelease];
    dialog->title = [inTitle copy];
    dialog->message = [inMessage copy];
    return dialog;
}

-(id)init {
    self = [super init];
    if (self) {
        buttonSpecs = [[NSMutableArray alloc] init];
        buttons = [[NSMutableArray alloc] init];
        width = 440.0;
    }
    return self;
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [title release];
    [message release];
    [contentView release];
    [buttonSpecs release];
    [buttons release];
    [handler release];
    [backdropWindow release];
    [panel release];
    [errorLabel release];
    [super dealloc];
}

-(void)setWidth:(CGFloat)inWidth { width = inWidth; }

-(void)setContentView:(NSView *)view {
    [contentView release];
    contentView = [view retain];
}

-(void)addButtonWithTitle:(NSString *)buttonTitle style:(DLDialogButtonStyle)style {
    [buttonSpecs addObject:[NSArray arrayWithObjects:buttonTitle, [NSNumber numberWithInt:style], nil]];
}

-(void)setHandler:(DLDialogHandler)inHandler {
    [handler release];
    handler = [inHandler copy];
}

-(NSPanel *)panel { return panel; }

+(NSTextField *)labelWithString:(NSString *)string frame:(NSRect)frame {
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [label setStringValue:(string ? string : @"")];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setFont:[NSFont systemFontOfSize:13.0]];
    [label setTextColor:[DLUtil nativeSecondaryTextColor]];
    [[label cell] setWraps:YES];
    [[label cell] setLineBreakMode:NSLineBreakByWordWrapping];
    return label;
}

+(NSTextField *)sectionLabelWithString:(NSString *)string frame:(NSRect)frame {
    NSTextField *label = [self labelWithString:[string uppercaseString] frame:frame];
    [label setFont:[NSFont boldSystemFontOfSize:11.0]];
    [[label cell] setWraps:NO];
    return label;
}

+(NSTextField *)textFieldWithFrame:(NSRect)frame placeholder:(NSString *)placeholder {
    NSTextField *field = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [field setBezeled:NO];
    [field setBordered:NO];
    [field setDrawsBackground:YES];
    [field setBackgroundColor:[DLUtil nativeServerRailColor]];
    [field setTextColor:[DLUtil nativePrimaryTextColor]];
    [field setFont:[NSFont systemFontOfSize:14.0]];
    [field setFocusRingType:NSFocusRingTypeNone];
    [[field cell] setScrollable:YES];
    [[field cell] setLineBreakMode:NSLineBreakByClipping];
    if (placeholder) {
        NSAttributedString *placeholderString = [[[NSAttributedString alloc] initWithString:placeholder attributes:
            [NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:14.0], NSFontAttributeName,
             [DLUtil nativeSecondaryTextColor], NSForegroundColorAttributeName, nil]] autorelease];
        [[field cell] setPlaceholderAttributedString:placeholderString];
    }
    return field;
}

+(CGFloat)heightOfLabel:(NSTextField *)label forWidth:(CGFloat)labelWidth {
    return ceil([[label cell] cellSizeForBounds:NSMakeRect(0.0, 0.0, labelWidth, 10000.0)].height);
}

-(void)showInWindow:(NSWindow *)window {
    if (!window || panel) return;
    [DLDarkMenu dismiss];
    parentWindow = window;
    [self retain]; // released in -close
    CGFloat inner = width - 2.0 * DLDialogPadding;

    DLDialogCardView *card = [[[DLDialogCardView alloc] initWithFrame:NSMakeRect(0.0, 0.0, width, 100.0)] autorelease];
    CGFloat y = 24.0;
    NSTextField *titleLabel = [DLDialog labelWithString:title frame:NSMakeRect(DLDialogPadding, y, inner - 24.0, 26.0)];
    [titleLabel setFont:[NSFont boldSystemFontOfSize:19.0]];
    [titleLabel setTextColor:[DLUtil nativePrimaryTextColor]];
    CGFloat titleHeight = [DLDialog heightOfLabel:titleLabel forWidth:inner - 24.0];
    [titleLabel setFrameSize:NSMakeSize(inner - 24.0, titleHeight)];
    [card addSubview:titleLabel];
    y += titleHeight + 10.0;

    DLDialogButton *closeButton = [[[DLDialogButton alloc] initWithFrame:NSMakeRect(width - 40.0, 16.0, 24.0, 24.0)] autorelease];
    [closeButton setTitle:@"✕"];
    [closeButton setStyle:DLDialogButtonStyleLink];
    [closeButton setBordered:NO];
    [closeButton setTarget:self];
    [closeButton setAction:@selector(cancel)];
    [closeButton setRefusesFirstResponder:YES];
    [card addSubview:closeButton];

    if ([message length]) {
        NSTextField *messageLabel = [DLDialog labelWithString:message frame:NSMakeRect(DLDialogPadding, y, inner, 20.0)];
        [messageLabel setFont:[NSFont systemFontOfSize:14.0]];
        CGFloat messageHeight = [DLDialog heightOfLabel:messageLabel forWidth:inner];
        [messageLabel setFrameSize:NSMakeSize(inner, messageHeight)];
        [card addSubview:messageLabel];
        y += messageHeight + 16.0;
    }
    if (contentView) {
        CGFloat contentHeight = NSHeight([contentView frame]);
        // Keep the whole card inside the window; taller content scrolls.
        NSRect parentContent = [window contentRectForFrameRect:[window frame]];
        CGFloat available = floor(NSHeight(parentContent) - 32.0 - y - 20.0 - DLDialogFooterHeight);
        available = MAX(available, 160.0);
        if (contentHeight > available) {
            NSScrollView *scrollView = [[[NSScrollView alloc] initWithFrame:NSMakeRect(DLDialogPadding, y, inner + 12.0, available)] autorelease];
            [scrollView setDrawsBackground:NO];
            [scrollView setBorderType:NSNoBorder];
            [scrollView setHasVerticalScroller:YES];
            [scrollView setAutohidesScrollers:YES];
            NSScroller_BGColor *scroller = [[[NSScroller_BGColor alloc] initWithFrame:NSMakeRect(0.0, 0.0, 11.0, available)] autorelease];
            [scroller setBackgroundColor:DLDialogCardColor()];
            [scrollView setVerticalScroller:scroller];
            [[scrollView contentView] setDrawsBackground:NO];
            [contentView setFrame:NSMakeRect(0.0, 0.0, inner, contentHeight)];
            [scrollView setDocumentView:contentView];
            // Start at the top of the (non-flipped) content.
            [[scrollView contentView] scrollToPoint:NSMakePoint(0.0, contentHeight - available)];
            [scrollView reflectScrolledClipView:[scrollView contentView]];
            [card addSubview:scrollView];
            contentHeight = available;
        } else {
            [contentView setFrame:NSMakeRect(DLDialogPadding, y, inner, contentHeight)];
            [card addSubview:contentView];
        }
        y += contentHeight + 12.0;
    }
    errorLabel = [[DLDialog labelWithString:@"" frame:NSMakeRect(DLDialogPadding, y, inner, 18.0)] retain];
    [errorLabel setTextColor:[NSColor colorWithCalibratedRed:0.949 green:0.247 blue:0.259 alpha:1.0]];
    [errorLabel setHidden:YES];
    [card addSubview:errorLabel];
    y += 8.0;

    CGFloat height = y + DLDialogFooterHeight;
    [card setFrameSize:NSMakeSize(width, height)];
    CGFloat x = width - DLDialogPadding;
    NSUInteger index;
    for (index = 0; index < [buttonSpecs count]; index++) {
        NSArray *spec = [buttonSpecs objectAtIndex:index];
        NSString *buttonTitle = [spec objectAtIndex:0];
        DLDialogButtonStyle style = (DLDialogButtonStyle)[[spec objectAtIndex:1] intValue];
        CGFloat buttonWidth = MAX(96.0, ceil([buttonTitle sizeWithAttributes:
            [NSDictionary dictionaryWithObject:[NSFont boldSystemFontOfSize:13.0] forKey:NSFontAttributeName]].width) + 32.0);
        if (style == DLDialogButtonStyleLink) buttonWidth -= 16.0;
        x -= buttonWidth;
        DLDialogButton *button = [[[DLDialogButton alloc] initWithFrame:
                                   NSMakeRect(x, height - DLDialogFooterHeight + 19.0, buttonWidth, 32.0)] autorelease];
        [button setTitle:buttonTitle];
        [button setStyle:style];
        [button setBordered:NO];
        [button setTag:(NSInteger)index];
        [button setTarget:self];
        [button setAction:@selector(buttonPressed:)];
        [button setRefusesFirstResponder:YES];
        if (index == 0) [button setKeyEquivalent:@"\r"];
        [card addSubview:button];
        [buttons addObject:button];
        x -= 8.0;
    }

    backdropWindow = [[NSWindow alloc] initWithContentRect:NSZeroRect styleMask:NSBorderlessWindowMask
                                                   backing:NSBackingStoreBuffered defer:NO];
    [backdropWindow setOpaque:NO];
    [backdropWindow setBackgroundColor:[NSColor clearColor]];
    [backdropWindow setReleasedWhenClosed:NO];
    DLDialogBackdropView *backdrop = [[[DLDialogBackdropView alloc] initWithFrame:NSZeroRect] autorelease];
    [backdrop setOwner:self];
    [backdropWindow setContentView:backdrop];

    DLDialogPanel *dialogPanel = [[DLDialogPanel alloc] initWithContentRect:NSMakeRect(0.0, 0.0, width, height)
                                                                  styleMask:NSBorderlessWindowMask
                                                                    backing:NSBackingStoreBuffered defer:NO];
    [dialogPanel setOwner:self];
    [dialogPanel setOpaque:NO];
    [dialogPanel setBackgroundColor:[NSColor clearColor]];
    [dialogPanel setHasShadow:YES];
    [dialogPanel setReleasedWhenClosed:NO];
    [dialogPanel setContentView:card];
    panel = dialogPanel;

    [self layoutWindows];
    [parentWindow addChildWindow:backdropWindow ordered:NSWindowAbove];
    [backdropWindow addChildWindow:panel ordered:NSWindowAbove];
    [backdropWindow orderFront:nil];
    [panel makeKeyAndOrderFront:nil];
    if (contentView) {
        // First text field gets the focus, like the official modals.
        NSEnumerator *enumerator = [[contentView subviews] objectEnumerator];
        NSView *subview;
        while (subview = [enumerator nextObject]) {
            if ([subview isKindOfClass:[NSTextField class]] && [(NSTextField *)subview isEditable]) {
                [panel makeFirstResponder:subview];
                break;
            }
        }
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(parentWindowDidChange:)
                                                 name:NSWindowDidResizeNotification object:parentWindow];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(parentWindowWillClose:)
                                                 name:NSWindowWillCloseNotification object:parentWindow];
}

-(void)layoutWindows {
    NSRect content = [parentWindow contentRectForFrameRect:[parentWindow frame]];
    [backdropWindow setFrame:content display:YES];
    NSRect frame = [panel frame];
    frame.origin.x = floor(NSMidX(content) - NSWidth(frame) / 2.0);
    frame.origin.y = floor(NSMidY(content) - NSHeight(frame) / 2.0);
    [panel setFrame:frame display:YES];
}

-(void)parentWindowDidChange:(NSNotification *)notification {
    [self layoutWindows];
}

-(void)parentWindowWillClose:(NSNotification *)notification {
    [self close];
}

-(void)close {
    if (closed || !panel) return;
    closed = YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [backdropWindow removeChildWindow:panel];
    [parentWindow removeChildWindow:backdropWindow];
    [panel orderOut:nil];
    [backdropWindow orderOut:nil];
    [parentWindow makeKeyAndOrderFront:nil];
    [self autorelease];
}

-(void)finishWithIndex:(NSInteger)index {
    if (closed) return;
    BOOL shouldClose = YES;
    if (handler) {
        DLDialogHandler block = [[handler retain] autorelease];
        shouldClose = block(self, index);
    }
    if (shouldClose) [self close];
}

-(void)cancel {
    [self finishWithIndex:DLDialogCancelIndex];
}

-(void)buttonPressed:(id)sender {
    NSInteger index = [sender tag];
    NSArray *spec = [buttonSpecs objectAtIndex:(NSUInteger)index];
    // A link-styled button (Cancel) always dismisses.
    if ([[spec objectAtIndex:1] intValue] == DLDialogButtonStyleLink) [self finishWithIndex:DLDialogCancelIndex];
    else [self finishWithIndex:index];
}

-(void)setBusy:(BOOL)busy {
    NSEnumerator *enumerator = [buttons objectEnumerator];
    NSButton *button;
    while (button = [enumerator nextObject]) [button setEnabled:!busy];
}

-(void)setErrorMessage:(NSString *)error {
    [errorLabel setStringValue:(error ? error : @"")];
    [errorLabel setHidden:([error length] == 0)];
}

@end

@implementation DLToggleSwitch

// NSControl keeps target and action in its cell; without one they are lost.
+(Class)cellClass { return [NSActionCell class]; }

-(BOOL)isFlipped { return YES; }
-(BOOL)isOn { return on; }
-(void)setOn:(BOOL)inOn { on = inOn; [self setNeedsDisplay:YES]; }
-(BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

-(void)drawRect:(NSRect)dirtyRect {
    NSRect track = NSMakeRect(0.0, floor((NSHeight([self bounds]) - 24.0) / 2.0), 40.0, 24.0);
    CGFloat alpha = [self isEnabled] ? 1.0 : 0.4;
    NSColor *fill = on ? [NSColor colorWithCalibratedRed:0.137 green:0.647 blue:0.353 alpha:alpha]
                       : [NSColor colorWithCalibratedRed:0.502 green:0.518 blue:0.557 alpha:alpha];
    [fill setFill];
    [[NSBezierPath bezierPathWithRoundedRect:track xRadius:12.0 yRadius:12.0] fill];
    NSRect knob = NSMakeRect(on ? 19.0 : 3.0, NSMinY(track) + 3.0, 18.0, 18.0);
    [[NSColor colorWithCalibratedWhite:1.0 alpha:alpha] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:knob] fill];
    [DLDarkMenu drawIconNamed:(on ? @"check" : @"close") inRect:NSInsetRect(knob, 3.5, 3.5) color:fill];
}

-(void)mouseDown:(NSEvent *)event {
    if (![self isEnabled]) return;
    [self setOn:!on];
    [self sendAction:[self action] to:[self target]];
}

@end

@implementation DLOptionRow

// NSControl keeps target and action in its cell; without one they are lost.
+(Class)cellClass { return [NSActionCell class]; }

-(void)dealloc {
    if (trackingArea) [self removeTrackingArea:trackingArea];
    [trackingArea release];
    [title release];
    [detail release];
    [iconName release];
    [super dealloc];
}

-(BOOL)isFlipped { return YES; }
-(BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
-(void)setTitle:(NSString *)inTitle { [title release]; title = [inTitle copy]; [self setNeedsDisplay:YES]; }
-(void)setDetail:(NSString *)inDetail { [detail release]; detail = [inDetail copy]; [self setNeedsDisplay:YES]; }
-(void)setIconName:(NSString *)inIcon { [iconName release]; iconName = [inIcon copy]; [self setNeedsDisplay:YES]; }
-(BOOL)isSelected { return selected; }
-(void)setSelected:(BOOL)inSelected { selected = inSelected; [self setNeedsDisplay:YES]; }

-(void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (trackingArea) {
        [self removeTrackingArea:trackingArea];
        [trackingArea release];
    }
    trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect) owner:self userInfo:nil];
    [self addTrackingArea:trackingArea];
}

-(void)mouseEntered:(NSEvent *)event { hovered = YES; [self setNeedsDisplay:YES]; }
-(void)mouseExited:(NSEvent *)event { hovered = NO; [self setNeedsDisplay:YES]; }

-(void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    NSColor *fill = selected ? [DLUtil nativeSelectionColor]
                  : (hovered ? [DLUtil nativeHoverColor] : [DLUtil nativeSidebarColor]);
    [fill setFill];
    [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:4.0 yRadius:4.0] fill];
    NSRect radio = NSMakeRect(12.0, floor(NSMidY(bounds) - 10.0), 20.0, 20.0);
    NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(radio, 1.0, 1.0)];
    [ring setLineWidth:2.0];
    [(selected ? [NSColor whiteColor] : [DLUtil nativeSecondaryTextColor]) setStroke];
    [ring stroke];
    if (selected) {
        [[NSColor whiteColor] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(radio, 5.0, 5.0)] fill];
    }
    CGFloat x = NSMaxX(radio) + 12.0;
    if (iconName) {
        [DLDarkMenu drawIconNamed:iconName inRect:NSMakeRect(x, floor(NSMidY(bounds) - 10.0), 20.0, 20.0)
                            color:[DLUtil nativeSecondaryTextColor]];
        x += 30.0;
    }
    NSDictionary *titleAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                     [NSFont boldSystemFontOfSize:14.0], NSFontAttributeName,
                                     [DLUtil nativePrimaryTextColor], NSForegroundColorAttributeName, nil];
    if ([detail length]) {
        [title drawAtPoint:NSMakePoint(x, NSMidY(bounds) - 19.0) withAttributes:titleAttributes];
        NSDictionary *detailAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                          [NSFont systemFontOfSize:12.0], NSFontAttributeName,
                                          [DLUtil nativeSecondaryTextColor], NSForegroundColorAttributeName, nil];
        [detail drawInRect:NSMakeRect(x, NSMidY(bounds) + 1.0, NSWidth(bounds) - x - 8.0, 18.0) withAttributes:detailAttributes];
    } else {
        [title drawAtPoint:NSMakePoint(x, NSMidY(bounds) - 9.0) withAttributes:titleAttributes];
    }
}

-(void)mouseDown:(NSEvent *)event {
    if (![self isEnabled]) return;
    [self sendAction:[self action] to:[self target]];
}

@end

@implementation DLSwitchRow

-(id)initWithFrame:(NSRect)frame title:(NSString *)rowTitle detail:(NSString *)rowDetail {
    self = [super initWithFrame:frame];
    if (self) {
        CGFloat textWidth = NSWidth(frame) - 60.0;
        titleLabel = [[DLDialog labelWithString:rowTitle frame:NSMakeRect(0.0, 0.0, textWidth, 20.0)] retain];
        [titleLabel setFont:[NSFont systemFontOfSize:14.0]];
        [titleLabel setTextColor:[DLUtil nativePrimaryTextColor]];
        [titleLabel setFrameSize:NSMakeSize(textWidth, [DLDialog heightOfLabel:titleLabel forWidth:textWidth])];
        [self addSubview:titleLabel];
        CGFloat height = NSHeight([titleLabel frame]);
        if ([rowDetail length]) {
            detailLabel = [[DLDialog labelWithString:rowDetail frame:NSMakeRect(0.0, height + 4.0, textWidth, 18.0)] retain];
            [detailLabel setFont:[NSFont systemFontOfSize:12.0]];
            [detailLabel setFrameSize:NSMakeSize(textWidth, [DLDialog heightOfLabel:detailLabel forWidth:textWidth])];
            [self addSubview:detailLabel];
            height = NSMaxY([detailLabel frame]);
        }
        toggle = [[DLToggleSwitch alloc] initWithFrame:NSMakeRect(NSWidth(frame) - 40.0, 0.0, 40.0, 24.0)];
        [self addSubview:toggle];
        [self setFrameSize:NSMakeSize(NSWidth(frame), MAX(height, 24.0) + 12.0)];
    }
    return self;
}

-(void)dealloc {
    [titleLabel release];
    [detailLabel release];
    [toggle release];
    [super dealloc];
}

-(BOOL)isFlipped { return YES; }
-(DLToggleSwitch *)toggle { return toggle; }

-(void)drawRect:(NSRect)dirtyRect {
    [[[DLUtil nativeSecondaryTextColor] colorWithAlphaComponent:0.15] setFill];
    NSRectFill(NSMakeRect(0.0, NSHeight([self bounds]) - 1.0, NSWidth([self bounds]), 1.0));
}

@end
