//
//  DLDarkMenu.m
//  Legacy Discord
//

#import "DLDarkMenu.h"
#import <objc/runtime.h>

static char DLDarkMenuStyleKey;
static char DLDarkMenuIconKey;

#define DLMenuPadding 6.0
#define DLMenuItemHeight 32.0
#define DLMenuSeparatorHeight 9.0
#define DLMenuMinimumWidth 188.0

@class DLDarkMenuView;

static NSMutableArray *menuPanels = nil;   // root first, open submenus after it
static id menuEventMonitor = nil;
static NSMenu *rootMenu = nil;

static NSColor *DLMenuBackgroundColor(void) { return [NSColor colorWithCalibratedRed:0.067 green:0.071 blue:0.078 alpha:1.0]; }
static NSColor *DLMenuTextColor(void) { return [NSColor colorWithCalibratedRed:0.859 green:0.871 blue:0.882 alpha:1.0]; }
static NSColor *DLMenuMutedTextColor(void) { return [NSColor colorWithCalibratedRed:0.580 green:0.608 blue:0.643 alpha:1.0]; }
static NSColor *DLMenuHoverColor(void) { return [NSColor colorWithCalibratedRed:0.345 green:0.396 blue:0.949 alpha:1.0]; }
static NSColor *DLMenuDangerColor(void) { return [NSColor colorWithCalibratedRed:0.949 green:0.247 blue:0.259 alpha:1.0]; }
static NSColor *DLMenuDangerHoverColor(void) { return [NSColor colorWithCalibratedRed:0.855 green:0.216 blue:0.235 alpha:1.0]; }
static NSColor *DLMenuBrandColor(void) { return [NSColor colorWithCalibratedRed:0.580 green:0.612 blue:0.969 alpha:1.0]; }

@interface DLDarkMenuPanel : NSPanel
@end

@implementation DLDarkMenuPanel
-(BOOL)canBecomeKeyWindow { return NO; }
-(BOOL)canBecomeMainWindow { return NO; }
@end

@interface DLDarkMenuView : NSView {
    NSMenu *menu;
    NSMutableArray *items;     // visible NSMenuItems
    NSMutableArray *itemRects; // NSValue rects, flipped coordinates
    NSInteger highlightedIndex;
    NSTrackingArea *trackingArea;
}
-(id)initWithMenu:(NSMenu *)menu minimumWidth:(CGFloat)minimumWidth;
-(NSMenu *)menu;
-(void)setHighlightedIndex:(NSInteger)index;
-(NSInteger)highlightedIndex;
-(NSArray *)items;
-(NSRect)rectForItemAtIndex:(NSInteger)index;
-(void)moveHighlightBy:(NSInteger)delta;
-(void)activateHighlightedItem;
@end

@interface DLDarkMenu ()
+(void)showPanelForMenu:(NSMenu *)menu topLeft:(NSPoint)topLeft minimumWidth:(CGFloat)minimumWidth
            parentWindow:(NSWindow *)parentWindow flipLeftOfX:(CGFloat)flipX;
+(void)closePanelsAfterLevel:(NSUInteger)level;
+(NSUInteger)levelOfView:(DLDarkMenuView *)view;
+(void)openSubmenuForView:(DLDarkMenuView *)view index:(NSInteger)index;
+(void)performItem:(NSMenuItem *)item;
@end

static DLDarkMenuItemStyle DLStyleForItem(NSMenuItem *item) {
    NSNumber *style = objc_getAssociatedObject(item, &DLDarkMenuStyleKey);
    return style ? (DLDarkMenuItemStyle)[style intValue] : DLDarkMenuItemStyleNormal;
}

static NSString *DLIconForItem(NSMenuItem *item) {
    return objc_getAssociatedObject(item, &DLDarkMenuIconKey);
}

@implementation DLDarkMenuView

-(id)initWithMenu:(NSMenu *)inMenu minimumWidth:(CGFloat)minimumWidth {
    items = [[NSMutableArray alloc] init];
    itemRects = [[NSMutableArray alloc] init];
    NSFont *font = [NSFont systemFontOfSize:13.0];
    CGFloat width = minimumWidth;
    CGFloat y = DLMenuPadding;
    BOOL lastWasSeparator = YES;
    NSArray *menuItems = [inMenu itemArray];
    NSUInteger index;
    for (index = 0; index < [menuItems count]; index++) {
        NSMenuItem *item = [menuItems objectAtIndex:index];
        if ([item isHidden]) continue;
        if ([item isSeparatorItem]) {
            // No leading, trailing or doubled separators.
            if (lastWasSeparator) continue;
            lastWasSeparator = YES;
        } else {
            lastWasSeparator = NO;
        }
        [items addObject:item];
    }
    while ([items count] && [[items lastObject] isSeparatorItem]) [items removeLastObject];
    for (index = 0; index < [items count]; index++) {
        NSMenuItem *item = [items objectAtIndex:index];
        CGFloat height = [item isSeparatorItem] ? DLMenuSeparatorHeight : DLMenuItemHeight;
        [itemRects addObject:[NSValue valueWithRect:NSMakeRect(DLMenuPadding, y, 0.0, height)]];
        y += height;
        if (![item isSeparatorItem]) {
            CGFloat titleWidth = [[item title] sizeWithAttributes:[NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName]].width;
            BOOL accessory = [item hasSubmenu] || DLIconForItem(item) ||
                DLStyleForItem(item) == DLDarkMenuItemStyleCheckbox || DLStyleForItem(item) == DLDarkMenuItemStyleRadio;
            width = MAX(width, ceil(titleWidth) + 2.0 * DLMenuPadding + 16.0 + (accessory ? 32.0 : 0.0) +
                               ([item image] ? 26.0 : 0.0));
        }
    }
    width = MIN(width, 320.0);
    for (index = 0; index < [itemRects count]; index++) {
        NSRect rect = [[itemRects objectAtIndex:index] rectValue];
        rect.size.width = width - 2.0 * DLMenuPadding;
        [itemRects replaceObjectAtIndex:index withObject:[NSValue valueWithRect:rect]];
    }
    self = [super initWithFrame:NSMakeRect(0.0, 0.0, width, y + DLMenuPadding)];
    if (self) {
        menu = [inMenu retain];
        highlightedIndex = -1;
    }
    return self;
}

-(void)dealloc {
    if (trackingArea) [self removeTrackingArea:trackingArea];
    [trackingArea release];
    [items release];
    [itemRects release];
    [menu release];
    [super dealloc];
}

-(BOOL)isFlipped { return YES; }
-(BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
-(NSMenu *)menu { return menu; }
-(NSArray *)items { return items; }
-(NSInteger)highlightedIndex { return highlightedIndex; }

-(NSRect)rectForItemAtIndex:(NSInteger)index {
    return [[itemRects objectAtIndex:index] rectValue];
}

-(void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (trackingArea) {
        [self removeTrackingArea:trackingArea];
        [trackingArea release];
    }
    trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:(NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect)
        owner:self userInfo:nil];
    [self addTrackingArea:trackingArea];
}

-(BOOL)itemIsSelectable:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)[items count]) return NO;
    NSMenuItem *item = [items objectAtIndex:index];
    return ![item isSeparatorItem] && [item isEnabled];
}

-(NSInteger)indexAtPoint:(NSPoint)point {
    NSUInteger index;
    for (index = 0; index < [itemRects count]; index++) {
        if (NSPointInRect(point, [[itemRects objectAtIndex:index] rectValue])) return (NSInteger)index;
    }
    return -1;
}

-(void)setHighlightedIndex:(NSInteger)index {
    if (![self itemIsSelectable:index]) index = -1;
    if (index == highlightedIndex) return;
    highlightedIndex = index;
    [self setNeedsDisplay:YES];
    NSUInteger level = [DLDarkMenu levelOfView:self];
    if (index >= 0 && [[items objectAtIndex:index] hasSubmenu]) {
        [DLDarkMenu openSubmenuForView:self index:index];
    } else {
        [DLDarkMenu closePanelsAfterLevel:level];
    }
}

-(void)mouseMoved:(NSEvent *)event {
    [self setHighlightedIndex:[self indexAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]]];
}

-(void)mouseEntered:(NSEvent *)event {
    [self mouseMoved:event];
}

-(void)mouseExited:(NSEvent *)event {
    // Keep the highlight on an item whose submenu is open.
    if (highlightedIndex >= 0 && [[items objectAtIndex:highlightedIndex] hasSubmenu]) return;
    [self setHighlightedIndex:-1];
}

-(void)mouseDown:(NSEvent *)event {
    [self setHighlightedIndex:[self indexAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]]];
}

-(void)rightMouseDown:(NSEvent *)event {
    [self mouseDown:event];
}

-(void)mouseUp:(NSEvent *)event {
    NSInteger index = [self indexAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
    if (index == highlightedIndex) [self activateHighlightedItem];
}

-(void)rightMouseUp:(NSEvent *)event {
    [self mouseUp:event];
}

-(void)moveHighlightBy:(NSInteger)delta {
    NSInteger count = (NSInteger)[items count];
    if (!count) return;
    NSInteger index = highlightedIndex;
    NSInteger step;
    for (step = 0; step < count; step++) {
        index = (index < 0 && delta < 0) ? count - 1 : (index + delta + count) % count;
        if ([self itemIsSelectable:index]) {
            [self setHighlightedIndex:index];
            return;
        }
    }
}

-(void)activateHighlightedItem {
    if (![self itemIsSelectable:highlightedIndex]) return;
    NSMenuItem *item = [items objectAtIndex:highlightedIndex];
    if ([item hasSubmenu]) {
        [DLDarkMenu openSubmenuForView:self index:highlightedIndex];
        return;
    }
    [DLDarkMenu performItem:item];
}

-(void)drawCheckboxInRect:(NSRect)rect on:(BOOL)on highlighted:(BOOL)highlighted radio:(BOOL)radio {
    NSBezierPath *box = radio ? [NSBezierPath bezierPathWithOvalInRect:rect]
                              : [NSBezierPath bezierPathWithRoundedRect:rect xRadius:4.0 yRadius:4.0];
    if (on) {
        [(highlighted ? [NSColor whiteColor] : DLMenuHoverColor()) setFill];
        [box fill];
        NSColor *mark = highlighted ? DLMenuHoverColor() : [NSColor whiteColor];
        if (radio) {
            [mark setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 5.0, 5.0)] fill];
        } else {
            [DLDarkMenu drawIconNamed:@"check" inRect:NSInsetRect(rect, 2.0, 2.0) color:mark];
        }
    } else {
        NSBezierPath *outline = radio ? [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 1.0, 1.0)]
                                      : [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 1.0, 1.0) xRadius:3.0 yRadius:3.0];
        [outline setLineWidth:2.0];
        [(highlighted ? [NSColor whiteColor] : DLMenuTextColor()) setStroke];
        [outline stroke];
    }
}

-(void)drawRect:(NSRect)dirtyRect {
    [DLMenuBackgroundColor() setFill];
    [[NSBezierPath bezierPathWithRoundedRect:[self bounds] xRadius:5.0 yRadius:5.0] fill];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.06] setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect([self bounds], 0.5, 0.5) xRadius:5.0 yRadius:5.0];
    [border setLineWidth:1.0];
    [border stroke];

    NSUInteger index;
    for (index = 0; index < [items count]; index++) {
        NSMenuItem *item = [items objectAtIndex:index];
        NSRect rect = [[itemRects objectAtIndex:index] rectValue];
        if ([item isSeparatorItem]) {
            [[NSColor colorWithCalibratedWhite:1.0 alpha:0.08] setFill];
            NSRectFill(NSMakeRect(NSMinX(rect) + 4.0, floor(NSMidY(rect)), NSWidth(rect) - 8.0, 1.0));
            continue;
        }
        DLDarkMenuItemStyle style = DLStyleForItem(item);
        BOOL highlighted = ((NSInteger)index == highlightedIndex);
        BOOL enabled = [item isEnabled];
        NSColor *textColor = DLMenuTextColor();
        if (style == DLDarkMenuItemStyleDanger) textColor = DLMenuDangerColor();
        else if (style == DLDarkMenuItemStyleBrand) textColor = DLMenuBrandColor();
        if (highlighted) {
            [(style == DLDarkMenuItemStyleDanger ? DLMenuDangerHoverColor() : DLMenuHoverColor()) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 0.0, 1.0) xRadius:3.0 yRadius:3.0] fill];
            textColor = [NSColor whiteColor];
        }
        if (!enabled) textColor = [DLMenuMutedTextColor() colorWithAlphaComponent:0.6];
        NSMutableParagraphStyle *paragraph = [[[NSMutableParagraphStyle alloc] init] autorelease];
        [paragraph setLineBreakMode:NSLineBreakByTruncatingTail];
        NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSFont systemFontOfSize:13.0], NSFontAttributeName,
                                    textColor, NSForegroundColorAttributeName,
                                    paragraph, NSParagraphStyleAttributeName, nil];
        NSString *icon = DLIconForItem(item);
        BOOL accessory = [item hasSubmenu] || icon || style == DLDarkMenuItemStyleCheckbox || style == DLDarkMenuItemStyleRadio;
        CGFloat titleX = NSMinX(rect) + 8.0;
        if ([item image]) {
            // Leading image (emoji in Add Reaction).
            [[item image] drawInRect:NSMakeRect(titleX, NSMinY(rect) + 8.0, 16.0, 16.0) fromRect:NSZeroRect
                           operation:NSCompositeSourceOver fraction:(enabled ? 1.0 : 0.5) respectFlipped:YES hints:nil];
            titleX += 26.0;
        }
        NSRect titleRect = NSMakeRect(titleX, NSMinY(rect) + 8.0,
                                      NSMaxX(rect) - 8.0 - titleX - (accessory ? 28.0 : 0.0), 18.0);
        [[item title] drawInRect:titleRect withAttributes:attributes];
        NSRect accessoryRect = NSMakeRect(NSMaxX(rect) - 8.0 - 18.0, NSMinY(rect) + 7.0, 18.0, 18.0);
        if (style == DLDarkMenuItemStyleCheckbox || style == DLDarkMenuItemStyleRadio) {
            [self drawCheckboxInRect:accessoryRect on:([item state] == NSOnState) highlighted:highlighted
                               radio:(style == DLDarkMenuItemStyleRadio)];
        } else if ([item hasSubmenu]) {
            [DLDarkMenu drawIconNamed:@"chevron-right" inRect:accessoryRect color:textColor];
        } else if (icon) {
            [DLDarkMenu drawIconNamed:icon inRect:accessoryRect color:textColor];
        } else if ([item state] == NSOnState) {
            [DLDarkMenu drawIconNamed:@"check" inRect:accessoryRect color:textColor];
        }
    }
}

@end

@implementation DLDarkMenu

+(void)setStyle:(DLDarkMenuItemStyle)style forItem:(NSMenuItem *)item {
    objc_setAssociatedObject(item, &DLDarkMenuStyleKey, [NSNumber numberWithInt:style], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+(void)setIconName:(NSString *)name forItem:(NSMenuItem *)item {
    objc_setAssociatedObject(item, &DLDarkMenuIconKey, name, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

+(BOOL)isShown {
    return [menuPanels count] > 0;
}

+(NSMenu *)shownMenu {
    return rootMenu;
}

+(NSUInteger)levelOfView:(DLDarkMenuView *)view {
    NSUInteger index;
    for (index = 0; index < [menuPanels count]; index++) {
        if ([[menuPanels objectAtIndex:index] contentView] == view) return index;
    }
    return 0;
}

+(DLDarkMenuView *)deepestView {
    // The deepest menu with a highlight takes the keyboard, else the root.
    NSInteger index;
    for (index = (NSInteger)[menuPanels count] - 1; index >= 0; index--) {
        DLDarkMenuView *view = (DLDarkMenuView *)[[menuPanels objectAtIndex:index] contentView];
        if ([view highlightedIndex] >= 0 || index == 0) return view;
    }
    return nil;
}

+(void)closePanelsAfterLevel:(NSUInteger)level {
    while ([menuPanels count] > level + 1) {
        NSPanel *panel = [menuPanels lastObject];
        [[panel parentWindow] removeChildWindow:panel];
        [panel orderOut:nil];
        [menuPanels removeLastObject];
    }
}

+(BOOL)handleKeyEvent:(NSEvent *)event {
    DLDarkMenuView *view = [self deepestView];
    if (!view) return NO;
    switch ([event keyCode]) {
        case 53: // Escape
            if ([menuPanels count] > 1) [self closePanelsAfterLevel:[menuPanels count] - 2];
            else [self dismiss];
            return YES;
        case 125: [view moveHighlightBy:1]; return YES;   // Down
        case 126: [view moveHighlightBy:-1]; return YES;  // Up
        case 124: // Right
            if ([view highlightedIndex] >= 0 && [[[view items] objectAtIndex:[view highlightedIndex]] hasSubmenu]) {
                [self openSubmenuForView:view index:[view highlightedIndex]];
                [(DLDarkMenuView *)[[menuPanels lastObject] contentView] moveHighlightBy:1];
            }
            return YES;
        case 123: // Left
            if ([menuPanels count] > 1) {
                NSUInteger level = [self levelOfView:view];
                if (level > 0) {
                    [view setHighlightedIndex:-1];
                    [self closePanelsAfterLevel:level - 1];
                }
            }
            return YES;
        case 36: case 76: // Return, Enter
            [view activateHighlightedItem];
            return YES;
        default:
            return YES; // the menu is modal for typing
    }
}

+(void)installEventMonitor {
    if (menuEventMonitor) return;
    menuEventMonitor = [[NSEvent addLocalMonitorForEventsMatchingMask:
                         (NSLeftMouseDownMask | NSRightMouseDownMask | NSOtherMouseDownMask | NSKeyDownMask | NSScrollWheelMask)
                         handler:^NSEvent *(NSEvent *event) {
        if ([event type] == NSKeyDown) {
            return [DLDarkMenu handleKeyEvent:event] ? nil : event;
        }
        NSWindow *window = [event window];
        if (window && [menuPanels containsObject:window]) return event;
        [DLDarkMenu dismiss];
        // A scroll elsewhere closes the menu and still scrolls; a click
        // outside only closes it, like the official overlay.
        return ([event type] == NSScrollWheel) ? event : nil;
    }] retain];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidResignActive:)
                                                 name:NSApplicationDidResignActiveNotification object:nil];
}

+(void)applicationDidResignActive:(NSNotification *)notification {
    [self dismiss];
}

+(void)dismiss {
    [self closePanelsAfterLevel:0];
    if ([menuPanels count]) {
        NSPanel *panel = [menuPanels objectAtIndex:0];
        [[panel parentWindow] removeChildWindow:panel];
        [panel orderOut:nil];
        [menuPanels removeAllObjects];
    }
    if (menuEventMonitor) {
        [NSEvent removeMonitor:menuEventMonitor];
        [menuEventMonitor release];
        menuEventMonitor = nil;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationDidResignActiveNotification object:nil];
    if (rootMenu) {
        NSMenu *closed = [rootMenu autorelease];
        rootMenu = nil;
        [[NSNotificationCenter defaultCenter] postNotificationName:DLDarkMenuDidCloseNotification object:closed];
    }
}

+(void)updateMenu:(NSMenu *)menu {
    id delegate = [menu delegate];
    if ([delegate respondsToSelector:@selector(menuNeedsUpdate:)]) [delegate menuNeedsUpdate:menu];
    [menu update];
}

+(void)showPanelForMenu:(NSMenu *)menu topLeft:(NSPoint)topLeft minimumWidth:(CGFloat)minimumWidth
            parentWindow:(NSWindow *)parentWindow flipLeftOfX:(CGFloat)flipX {
    if (!menuPanels) menuPanels = [[NSMutableArray alloc] init];
    DLDarkMenuView *view = [[[DLDarkMenuView alloc] initWithMenu:menu minimumWidth:minimumWidth] autorelease];
    if (![[view items] count]) return;
    NSSize size = [view frame].size;
    NSScreen *screen = [parentWindow screen] ? [parentWindow screen] : [NSScreen mainScreen];
    NSRect visible = [screen visibleFrame];
    NSRect frame = NSMakeRect(topLeft.x, topLeft.y - size.height, size.width, size.height);
    if (NSMaxX(frame) > NSMaxX(visible)) {
        frame.origin.x = (flipX > 0.0) ? flipX - size.width : NSMaxX(visible) - size.width;
    }
    if (NSMinX(frame) < NSMinX(visible)) frame.origin.x = NSMinX(visible);
    if (NSMinY(frame) < NSMinY(visible)) {
        // Open upwards from the point (context menus near the bottom).
        frame.origin.y = MIN(topLeft.y, NSMaxY(visible) - size.height);
        if ([menuPanels count] == 0 && topLeft.y + size.height <= NSMaxY(visible)) frame.origin.y = topLeft.y;
        if (NSMinY(frame) < NSMinY(visible)) frame.origin.y = NSMinY(visible);
    }
    DLDarkMenuPanel *panel = [[[DLDarkMenuPanel alloc] initWithContentRect:frame
                                                                  styleMask:(NSBorderlessWindowMask | NSNonactivatingPanelMask)
                                                                    backing:NSBackingStoreBuffered defer:NO] autorelease];
    [panel setOpaque:NO];
    [panel setBackgroundColor:[NSColor clearColor]];
    [panel setHasShadow:YES];
    [panel setLevel:NSPopUpMenuWindowLevel];
    [panel setHidesOnDeactivate:YES];
    [panel setReleasedWhenClosed:NO];
    [panel setAcceptsMouseMovedEvents:YES];
    [panel setContentView:view];
    [parentWindow addChildWindow:panel ordered:NSWindowAbove];
    [panel orderFront:nil];
    [menuPanels addObject:panel];
}

+(void)openSubmenuForView:(DLDarkMenuView *)view index:(NSInteger)index {
    NSUInteger level = [self levelOfView:view];
    NSMenuItem *item = [[view items] objectAtIndex:index];
    NSMenu *submenu = [item submenu];
    if ([menuPanels count] > level + 1 && [[[menuPanels objectAtIndex:level + 1] contentView] menu] == submenu) return;
    [self closePanelsAfterLevel:level];
    [self updateMenu:submenu];
    NSRect rowRect = [view rectForItemAtIndex:index];
    NSRect rowInWindow = [view convertRect:rowRect toView:nil];
    NSWindow *window = [view window];
    NSPoint rowTopRight = [window convertBaseToScreen:NSMakePoint(NSMaxX([view bounds]), NSMaxY(rowInWindow))];
    NSPoint rowTopLeft = [window convertBaseToScreen:NSMakePoint(0.0, NSMaxY(rowInWindow))];
    [self showPanelForMenu:submenu topLeft:NSMakePoint(rowTopRight.x + 4.0, rowTopRight.y + DLMenuPadding)
              minimumWidth:DLMenuMinimumWidth parentWindow:window flipLeftOfX:rowTopLeft.x - 4.0];
}

+(void)performItem:(NSMenuItem *)item {
    [[item retain] autorelease];
    id target = [[[item target] retain] autorelease];
    SEL action = [item action];
    [self dismiss];
    if (action) [NSApp sendAction:action to:target from:item];
}

+(void)popUpMenu:(NSMenu *)menu belowRect:(NSRect)rect ofView:(NSView *)view width:(CGFloat)width {
    [self dismiss];
    [DLTooltip hide];
    if (!menu || ![view window]) return;
    [self updateMenu:menu];
    rootMenu = [menu retain];
    NSRect inWindow = [view convertRect:rect toView:nil];
    NSPoint bottomLeft = [[view window] convertBaseToScreen:NSMakePoint(NSMinX(inWindow), NSMinY(inWindow))];
    CGFloat menuWidth = width > 0.0 ? width : NSWidth(inWindow);
    [self showPanelForMenu:menu topLeft:NSMakePoint(bottomLeft.x + (NSWidth(inWindow) - menuWidth) / 2.0, bottomLeft.y - 4.0)
              minimumWidth:menuWidth parentWindow:[view window] flipLeftOfX:0.0];
    if ([self isShown]) [self installEventMonitor];
    else {
        [rootMenu release];
        rootMenu = nil;
    }
}

+(void)popUpContextMenu:(NSMenu *)menu withEvent:(NSEvent *)event forView:(NSView *)view {
    [self dismiss];
    [DLTooltip hide];
    if (!menu || ![view window]) return;
    [self updateMenu:menu];
    rootMenu = [menu retain];
    NSPoint point = [[view window] convertBaseToScreen:[event locationInWindow]];
    [self showPanelForMenu:menu topLeft:NSMakePoint(point.x + 2.0, point.y - 2.0)
              minimumWidth:DLMenuMinimumWidth parentWindow:[view window] flipLeftOfX:point.x - 2.0];
    if ([self isShown]) [self installEventMonitor];
    else {
        [rootMenu release];
        rootMenu = nil;
    }
}

#pragma mark Icons

+(void)drawIconNamed:(NSString *)name inRect:(NSRect)rect color:(NSColor *)color {
    // Icons are drawn on an 18-point grid in flipped coordinates.
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    BOOL flipped = [[NSView focusView] isFlipped];
    [transform translateXBy:NSMinX(rect) yBy:(flipped ? NSMinY(rect) : NSMaxY(rect))];
    [transform scaleXBy:NSWidth(rect) / 18.0 yBy:(flipped ? 1.0 : -1.0) * NSHeight(rect) / 18.0];
    [transform concat];
    [color setStroke];
    [color setFill];
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path setLineWidth:1.6];
    [path setLineCapStyle:NSRoundLineCapStyle];
    [path setLineJoinStyle:NSRoundLineJoinStyle];
    if ([name isEqualToString:@"check"]) {
        [path moveToPoint:NSMakePoint(4.0, 9.5)];
        [path lineToPoint:NSMakePoint(7.5, 13.0)];
        [path lineToPoint:NSMakePoint(14.0, 5.5)];
        [path setLineWidth:2.0];
        [path stroke];
    } else if ([name isEqualToString:@"chevron-right"]) {
        [path moveToPoint:NSMakePoint(7.0, 4.5)];
        [path lineToPoint:NSMakePoint(11.5, 9.0)];
        [path lineToPoint:NSMakePoint(7.0, 13.5)];
        [path setLineWidth:2.0];
        [path stroke];
    } else if ([name isEqualToString:@"invite"]) {
        [path appendBezierPathWithOvalInRect:NSMakeRect(3.5, 2.5, 6.0, 6.0)];
        [path moveToPoint:NSMakePoint(1.5, 15.5)];
        [path curveToPoint:NSMakePoint(11.5, 15.5) controlPoint1:NSMakePoint(1.5, 9.5) controlPoint2:NSMakePoint(11.5, 9.5)];
        [path moveToPoint:NSMakePoint(14.0, 4.5)];
        [path lineToPoint:NSMakePoint(14.0, 10.5)];
        [path moveToPoint:NSMakePoint(11.0, 7.5)];
        [path lineToPoint:NSMakePoint(17.0, 7.5)];
        [path stroke];
    } else if ([name isEqualToString:@"settings"]) {
        NSInteger tooth;
        for (tooth = 0; tooth < 8; tooth++) {
            CGFloat angle = tooth * M_PI / 4.0;
            [path moveToPoint:NSMakePoint(9.0 + cos(angle) * 5.5, 9.0 + sin(angle) * 5.5)];
            [path lineToPoint:NSMakePoint(9.0 + cos(angle) * 7.5, 9.0 + sin(angle) * 7.5)];
        }
        [path setLineWidth:2.2];
        [path stroke];
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(3.8, 3.8, 10.4, 10.4)];
        [ring setLineWidth:1.6];
        [ring stroke];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(7.0, 7.0, 4.0, 4.0)] stroke];
    } else if ([name isEqualToString:@"add"]) {
        [path appendBezierPathWithOvalInRect:NSMakeRect(1.5, 1.5, 15.0, 15.0)];
        [path moveToPoint:NSMakePoint(9.0, 5.5)];
        [path lineToPoint:NSMakePoint(9.0, 12.5)];
        [path moveToPoint:NSMakePoint(5.5, 9.0)];
        [path lineToPoint:NSMakePoint(12.5, 9.0)];
        [path stroke];
    } else if ([name isEqualToString:@"folder"]) {
        [path moveToPoint:NSMakePoint(1.5, 4.0)];
        [path lineToPoint:NSMakePoint(6.5, 4.0)];
        [path lineToPoint:NSMakePoint(8.0, 5.5)];
        [path lineToPoint:NSMakePoint(16.5, 5.5)];
        [path lineToPoint:NSMakePoint(16.5, 15.0)];
        [path lineToPoint:NSMakePoint(1.5, 15.0)];
        [path closePath];
        [path moveToPoint:NSMakePoint(9.0, 7.8)];
        [path lineToPoint:NSMakePoint(9.0, 12.8)];
        [path moveToPoint:NSMakePoint(6.5, 10.3)];
        [path lineToPoint:NSMakePoint(11.5, 10.3)];
        [path stroke];
    } else if ([name isEqualToString:@"bell"]) {
        [path moveToPoint:NSMakePoint(3.0, 13.0)];
        [path lineToPoint:NSMakePoint(4.5, 11.0)];
        [path lineToPoint:NSMakePoint(4.5, 7.5)];
        [path curveToPoint:NSMakePoint(13.5, 7.5) controlPoint1:NSMakePoint(4.5, 1.5) controlPoint2:NSMakePoint(13.5, 1.5)];
        [path lineToPoint:NSMakePoint(13.5, 11.0)];
        [path lineToPoint:NSMakePoint(15.0, 13.0)];
        [path closePath];
        [path moveToPoint:NSMakePoint(7.3, 15.5)];
        [path lineToPoint:NSMakePoint(10.7, 15.5)];
        [path stroke];
    } else if ([name isEqualToString:@"pencil"]) {
        [path moveToPoint:NSMakePoint(3.0, 15.0)];
        [path lineToPoint:NSMakePoint(3.5, 11.5)];
        [path lineToPoint:NSMakePoint(12.0, 3.0)];
        [path lineToPoint:NSMakePoint(15.0, 6.0)];
        [path lineToPoint:NSMakePoint(6.5, 14.5)];
        [path closePath];
        [path moveToPoint:NSMakePoint(10.0, 5.0)];
        [path lineToPoint:NSMakePoint(13.0, 8.0)];
        [path stroke];
    } else if ([name isEqualToString:@"leave"]) {
        [path moveToPoint:NSMakePoint(10.0, 2.5)];
        [path lineToPoint:NSMakePoint(3.0, 2.5)];
        [path lineToPoint:NSMakePoint(3.0, 15.5)];
        [path lineToPoint:NSMakePoint(10.0, 15.5)];
        [path moveToPoint:NSMakePoint(7.0, 9.0)];
        [path lineToPoint:NSMakePoint(16.0, 9.0)];
        [path moveToPoint:NSMakePoint(12.5, 5.5)];
        [path lineToPoint:NSMakePoint(16.0, 9.0)];
        [path lineToPoint:NSMakePoint(12.5, 12.5)];
        [path stroke];
    } else if ([name isEqualToString:@"link"]) {
        [path appendBezierPathWithRoundedRect:NSMakeRect(1.5, 6.0, 8.5, 6.0) xRadius:3.0 yRadius:3.0];
        [path appendBezierPathWithRoundedRect:NSMakeRect(8.0, 6.0, 8.5, 6.0) xRadius:3.0 yRadius:3.0];
        [path stroke];
    } else if ([name isEqualToString:@"id"]) {
        [path appendBezierPathWithRoundedRect:NSMakeRect(1.5, 3.5, 15.0, 11.0) xRadius:2.0 yRadius:2.0];
        [path moveToPoint:NSMakePoint(5.0, 7.0)];
        [path lineToPoint:NSMakePoint(5.0, 11.0)];
        [path moveToPoint:NSMakePoint(8.0, 7.0)];
        [path lineToPoint:NSMakePoint(8.0, 11.0)];
        [path curveToPoint:NSMakePoint(8.0, 7.0) controlPoint1:NSMakePoint(13.5, 11.0) controlPoint2:NSMakePoint(13.5, 7.0)];
        [path stroke];
    } else if ([name isEqualToString:@"eye"]) {
        [path moveToPoint:NSMakePoint(1.5, 9.0)];
        [path curveToPoint:NSMakePoint(16.5, 9.0) controlPoint1:NSMakePoint(5.0, 3.0) controlPoint2:NSMakePoint(13.0, 3.0)];
        [path curveToPoint:NSMakePoint(1.5, 9.0) controlPoint1:NSMakePoint(13.0, 15.0) controlPoint2:NSMakePoint(5.0, 15.0)];
        [path appendBezierPathWithOvalInRect:NSMakeRect(6.5, 6.5, 5.0, 5.0)];
        [path stroke];
    } else if ([name isEqualToString:@"pin"]) {
        [path moveToPoint:NSMakePoint(6.0, 2.5)];
        [path lineToPoint:NSMakePoint(12.0, 2.5)];
        [path moveToPoint:NSMakePoint(7.0, 2.5)];
        [path lineToPoint:NSMakePoint(6.5, 8.0)];
        [path lineToPoint:NSMakePoint(4.0, 11.0)];
        [path lineToPoint:NSMakePoint(14.0, 11.0)];
        [path lineToPoint:NSMakePoint(11.5, 8.0)];
        [path lineToPoint:NSMakePoint(11.0, 2.5)];
        [path moveToPoint:NSMakePoint(9.0, 11.0)];
        [path lineToPoint:NSMakePoint(9.0, 16.0)];
        [path stroke];
    } else if ([name isEqualToString:@"reply"]) {
        [path moveToPoint:NSMakePoint(7.0, 3.5)];
        [path lineToPoint:NSMakePoint(2.5, 8.0)];
        [path lineToPoint:NSMakePoint(7.0, 12.5)];
        [path moveToPoint:NSMakePoint(2.5, 8.0)];
        [path lineToPoint:NSMakePoint(10.0, 8.0)];
        [path curveToPoint:NSMakePoint(15.5, 15.0) controlPoint1:NSMakePoint(14.0, 8.0) controlPoint2:NSMakePoint(15.5, 10.0)];
        [path stroke];
    } else if ([name isEqualToString:@"copy"]) {
        [path appendBezierPathWithRoundedRect:NSMakeRect(5.5, 5.5, 10.0, 10.5) xRadius:2.0 yRadius:2.0];
        [path moveToPoint:NSMakePoint(12.5, 2.5)];
        [path lineToPoint:NSMakePoint(4.0, 2.5)];
        [path curveToPoint:NSMakePoint(2.5, 4.0) controlPoint1:NSMakePoint(3.0, 2.5) controlPoint2:NSMakePoint(2.5, 3.0)];
        [path lineToPoint:NSMakePoint(2.5, 12.5)];
        [path stroke];
    } else if ([name isEqualToString:@"trash"]) {
        [path moveToPoint:NSMakePoint(2.5, 4.5)];
        [path lineToPoint:NSMakePoint(15.5, 4.5)];
        [path moveToPoint:NSMakePoint(7.0, 4.5)];
        [path lineToPoint:NSMakePoint(7.0, 2.0)];
        [path lineToPoint:NSMakePoint(11.0, 2.0)];
        [path lineToPoint:NSMakePoint(11.0, 4.5)];
        [path moveToPoint:NSMakePoint(4.0, 4.5)];
        [path lineToPoint:NSMakePoint(5.0, 16.0)];
        [path lineToPoint:NSMakePoint(13.0, 16.0)];
        [path lineToPoint:NSMakePoint(14.0, 4.5)];
        [path stroke];
    } else if ([name isEqualToString:@"thread"]) {
        [path moveToPoint:NSMakePoint(4.0, 3.0)];
        [path lineToPoint:NSMakePoint(4.0, 15.0)];
        [path moveToPoint:NSMakePoint(9.0, 3.0)];
        [path lineToPoint:NSMakePoint(9.0, 15.0)];
        [path moveToPoint:NSMakePoint(1.5, 6.5)];
        [path lineToPoint:NSMakePoint(16.5, 6.5)];
        [path moveToPoint:NSMakePoint(1.5, 11.5)];
        [path lineToPoint:NSMakePoint(11.0, 11.5)];
        [path stroke];
    } else if ([name isEqualToString:@"close"]) {
        [path moveToPoint:NSMakePoint(4.5, 4.5)];
        [path lineToPoint:NSMakePoint(13.5, 13.5)];
        [path moveToPoint:NSMakePoint(13.5, 4.5)];
        [path lineToPoint:NSMakePoint(4.5, 13.5)];
        [path setLineWidth:2.0];
        [path stroke];
    } else if ([name isEqualToString:@"hash"]) {
        [path moveToPoint:NSMakePoint(7.0, 2.5)];
        [path lineToPoint:NSMakePoint(5.5, 15.5)];
        [path moveToPoint:NSMakePoint(12.5, 2.5)];
        [path lineToPoint:NSMakePoint(11.0, 15.5)];
        [path moveToPoint:NSMakePoint(3.0, 6.5)];
        [path lineToPoint:NSMakePoint(15.5, 6.5)];
        [path moveToPoint:NSMakePoint(2.5, 11.5)];
        [path lineToPoint:NSMakePoint(15.0, 11.5)];
        [path setLineWidth:1.8];
        [path stroke];
    } else if ([name isEqualToString:@"speaker"]) {
        [path moveToPoint:NSMakePoint(2.0, 7.0)];
        [path lineToPoint:NSMakePoint(5.0, 7.0)];
        [path lineToPoint:NSMakePoint(9.5, 3.0)];
        [path lineToPoint:NSMakePoint(9.5, 15.0)];
        [path lineToPoint:NSMakePoint(5.0, 11.0)];
        [path lineToPoint:NSMakePoint(2.0, 11.0)];
        [path closePath];
        [path fill];
        NSBezierPath *waves = [NSBezierPath bezierPath];
        [waves setLineWidth:1.6];
        [waves setLineCapStyle:NSRoundLineCapStyle];
        [waves moveToPoint:NSMakePoint(12.0, 6.5)];
        [waves curveToPoint:NSMakePoint(12.0, 11.5) controlPoint1:NSMakePoint(13.5, 7.5) controlPoint2:NSMakePoint(13.5, 10.5)];
        [waves moveToPoint:NSMakePoint(14.0, 4.0)];
        [waves curveToPoint:NSMakePoint(14.0, 14.0) controlPoint1:NSMakePoint(17.0, 6.5) controlPoint2:NSMakePoint(17.0, 11.5)];
        [waves stroke];
    } else if ([name isEqualToString:@"forum"]) {
        [path appendBezierPathWithRoundedRect:NSMakeRect(1.5, 2.5, 11.0, 8.5) xRadius:2.5 yRadius:2.5];
        [path moveToPoint:NSMakePoint(14.5, 6.5)];
        [path curveToPoint:NSMakePoint(16.5, 8.5) controlPoint1:NSMakePoint(15.6, 6.5) controlPoint2:NSMakePoint(16.5, 7.4)];
        [path lineToPoint:NSMakePoint(16.5, 15.5)];
        [path lineToPoint:NSMakePoint(14.0, 13.5)];
        [path lineToPoint:NSMakePoint(8.5, 13.5)];
        [path curveToPoint:NSMakePoint(6.5, 12.5) controlPoint1:NSMakePoint(7.6, 13.5) controlPoint2:NSMakePoint(6.9, 13.1)];
        [path stroke];
    } else if ([name isEqualToString:@"chevron-down"]) {
        [path moveToPoint:NSMakePoint(4.5, 7.0)];
        [path lineToPoint:NSMakePoint(9.0, 11.5)];
        [path lineToPoint:NSMakePoint(13.5, 7.0)];
        [path setLineWidth:2.0];
        [path stroke];
    }
    [context restoreGraphicsState];
}

@end

#pragma mark Tooltip

#define DLTooltipArrow 5.0

@interface DLTooltipView : NSView {
    NSString *text;
}
-(void)setText:(NSString *)text;
+(NSDictionary *)textAttributes;
@end

@implementation DLTooltipView
+(NSDictionary *)textAttributes {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSFont boldSystemFontOfSize:13.0], NSFontAttributeName,
            DLMenuTextColor(), NSForegroundColorAttributeName, nil];
}
-(void)dealloc {
    [text release];
    [super dealloc];
}
-(void)setText:(NSString *)inText {
    [text release];
    text = [inText copy];
    [self setNeedsDisplay:YES];
}
-(NSView *)hitTest:(NSPoint)point { return nil; }
-(void)drawRect:(NSRect)dirtyRect {
    NSRect bubble = NSMakeRect(DLTooltipArrow, 0.0, NSWidth([self bounds]) - DLTooltipArrow, NSHeight([self bounds]));
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:bubble xRadius:5.0 yRadius:5.0];
    [path moveToPoint:NSMakePoint(DLTooltipArrow + 0.5, NSMidY(bubble) - DLTooltipArrow)];
    [path lineToPoint:NSMakePoint(0.0, NSMidY(bubble))];
    [path lineToPoint:NSMakePoint(DLTooltipArrow + 0.5, NSMidY(bubble) + DLTooltipArrow)];
    [path closePath];
    [DLMenuBackgroundColor() setFill];
    [path fill];
    NSSize size = [text sizeWithAttributes:[DLTooltipView textAttributes]];
    [text drawAtPoint:NSMakePoint(NSMinX(bubble) + 12.0, floor(NSMidY(bubble) - size.height / 2.0))
       withAttributes:[DLTooltipView textAttributes]];
}
@end

static NSPanel *tooltipPanel = nil;

@implementation DLTooltip

+(void)showText:(NSString *)text rightOfRect:(NSRect)rect inView:(NSView *)view {
    NSWindow *window = [view window];
    if (![text length] || !window) {
        [self hide];
        return;
    }
    if (!tooltipPanel) {
        tooltipPanel = [[DLDarkMenuPanel alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 10.0, 10.0)
                                                          styleMask:(NSBorderlessWindowMask | NSNonactivatingPanelMask)
                                                            backing:NSBackingStoreBuffered defer:NO];
        [tooltipPanel setOpaque:NO];
        [tooltipPanel setBackgroundColor:[NSColor clearColor]];
        [tooltipPanel setHasShadow:YES];
        [tooltipPanel setIgnoresMouseEvents:YES];
        [tooltipPanel setLevel:NSPopUpMenuWindowLevel];
        [tooltipPanel setHidesOnDeactivate:YES];
        [tooltipPanel setContentView:[[[DLTooltipView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)] autorelease]];
    }
    NSSize textSize = [text sizeWithAttributes:[DLTooltipView textAttributes]];
    CGFloat width = MIN(ceil(textSize.width) + 24.0, 280.0) + DLTooltipArrow;
    CGFloat height = MAX(ceil(textSize.height) + 16.0, 32.0);
    NSRect inWindow = [view convertRect:rect toView:nil];
    NSPoint anchor = [window convertBaseToScreen:NSMakePoint(NSMaxX(inWindow) + 8.0, NSMidY(inWindow))];
    [(DLTooltipView *)[tooltipPanel contentView] setText:text];
    [tooltipPanel setFrame:NSMakeRect(anchor.x, floor(anchor.y - height / 2.0), width, height) display:YES];
    if ([tooltipPanel parentWindow] != window) {
        [[tooltipPanel parentWindow] removeChildWindow:tooltipPanel];
        [window addChildWindow:tooltipPanel ordered:NSWindowAbove];
    }
    [tooltipPanel orderFront:nil];
}

+(void)hide {
    if (!tooltipPanel) return;
    [[tooltipPanel parentWindow] removeChildWindow:tooltipPanel];
    [tooltipPanel orderOut:nil];
}

@end
