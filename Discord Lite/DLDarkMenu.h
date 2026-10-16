//
//  DLDarkMenu.h
//  Legacy Discord
//
//  Discord-style dark menu drawn in a borderless panel. It shows an ordinary
//  NSMenu (titles, separators, enabled state, on/off state, submenus,
//  target/action), so menus are still built the AppKit way; the white Aqua
//  menu is never shown. Main thread only.
//

#import <Cocoa/Cocoa.h>

// Posted when a shown menu closes (an item was chosen or it was dismissed).
#define DLDarkMenuDidCloseNotification @"DLDarkMenuDidCloseNotification"

typedef enum {
    DLDarkMenuItemStyleNormal = 0,
    DLDarkMenuItemStyleDanger = 1,    // red, like Leave Server or Delete
    DLDarkMenuItemStyleBrand = 2,     // blurple, like Invite to Server
    DLDarkMenuItemStyleCheckbox = 3,  // checkbox at the right, from the item state
    DLDarkMenuItemStyleRadio = 4      // radio at the right, from the item state
} DLDarkMenuItemStyle;

@interface DLDarkMenu : NSObject

// Dropdown under a view rect (the server header menu). width <= 0 uses the
// rect width.
+(void)popUpMenu:(NSMenu *)menu belowRect:(NSRect)rect ofView:(NSView *)view width:(CGFloat)width;
// Context menu at the mouse location of a right-click event.
+(void)popUpContextMenu:(NSMenu *)menu withEvent:(NSEvent *)event forView:(NSView *)view;
+(void)dismiss;
+(BOOL)isShown;
// The menu shown last (nil once dismissed).
+(NSMenu *)shownMenu;

+(void)setStyle:(DLDarkMenuItemStyle)style forItem:(NSMenuItem *)item;
// Small line icon at the right edge: invite, settings, add, folder, bell,
// pencil, leave, link, id, check, eye, pin, reply, copy, trash, thread.
+(void)setIconName:(NSString *)name forItem:(NSMenuItem *)item;
// Draws one of the icons above, in rect, for reuse in other views.
+(void)drawIconNamed:(NSString *)name inRect:(NSRect)rect color:(NSColor *)color;

@end
