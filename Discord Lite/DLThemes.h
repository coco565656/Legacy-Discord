//
//  DLThemes.h
//  Legacy Discord
//
//  Nitro color themes: the official gradient presets, drawn the way the web
//  client does. The gradient covers the window (CSS "fixed 0 0 / cover") and
//  every surface is the gradient under a black (dark presets) or white (light
//  presets) overlay of the official opacity. Surfaces are returned as pattern
//  colors anchored to the window, so any view that fills with them shows its
//  part of the one window-wide gradient.
//

#import <Cocoa/Cocoa.h>

// Surface levels, from the darkest to the lightest in dark themes.
typedef enum {
    DLThemeSurfaceLowest = 0,   // server rail
    DLThemeSurfaceLower,        // channel list, member list
    DLThemeSurfaceLow,          // user panel
    DLThemeSurfaceChat,         // messages
    DLThemeSurfaceHigh,
    DLThemeSurfaceHigher,       // inputs, app frame
    DLThemeSurfaceHighest,
    DLThemeSurfaceHover,        // list hover
    DLThemeSurfaceSelected,     // selected row
    DLThemeSurfaceBorder,
    DLThemeSurfaceCount
} DLThemeSurface;

// Posted when the gradient is laid out again for a new window size.
#define DLThemeGradientDidChangeNotification @"DLThemeGradientDidChangeNotification"

// Appearance theme keys for presets are "nitro:<id>", e.g. "nitro:sunset".
#define DLNitroThemePrefix @"nitro:"

@interface DLThemes : NSObject

// Preset descriptions: dictionaries with id, name, light (NSNumber BOOL).
+(NSArray *)presets;
// YES while a Nitro preset is the appearance theme.
+(BOOL)isGradientThemeActive;
+(BOOL)isLightThemeActive;
+(NSColor *)colorForSurface:(DLThemeSurface)surface;
+(NSColor *)primaryTextColor;
+(NSColor *)secondaryTextColor;
// Round preview of a preset for the theme picker.
+(NSImage *)swatchImageForPresetID:(NSString *)presetID size:(CGFloat)size;
// The gradient is laid out for the main window's size; call after it
// changes (end of live resize). Posts the theme change notification.
+(void)setGradientSize:(NSSize)size;

@end
