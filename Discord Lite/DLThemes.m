//
//  DLThemes.m
//  Legacy Discord
//

#import "DLThemes.h"
#import "DLPreferencesHandler.h"
#import "DLLocalization.h"
#include <math.h>

typedef struct { double r, g, b; } DLRGB;

static NSArray *presetList = nil;
static NSMutableDictionary *presetData = nil;   // id -> {light, angle, colors (HSL triples), stops ([index, position])}
static NSMutableArray *surfaceColors = nil;     // NSColor per DLThemeSurface for the cached preset
static NSString *cachedPresetID = nil;
static NSSize gradientSize = {0.0, 0.0};
static NSSize cachedSize = {0.0, 0.0};

#pragma mark Color math

static DLRGB DLRGBFromHSL(double h, double s, double l) {
    h = fmod(h, 360.0) / 360.0;
    double q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
    double p = 2.0 * l - q;
    double t[3] = { h + 1.0 / 3.0, h, h - 1.0 / 3.0 };
    double c[3];
    int i;
    for (i = 0; i < 3; i++) {
        double x = t[i];
        if (x < 0.0) x += 1.0;
        if (x > 1.0) x -= 1.0;
        if (x < 1.0 / 6.0) c[i] = p + (q - p) * 6.0 * x;
        else if (x < 0.5) c[i] = q;
        else if (x < 2.0 / 3.0) c[i] = p + (q - p) * (2.0 / 3.0 - x) * 6.0;
        else c[i] = p;
    }
    DLRGB rgb = { c[0], c[1], c[2] };
    return rgb;
}

static void DLHSLFromRGB(DLRGB c, double *h, double *s, double *l) {
    double maxv = MAX(c.r, MAX(c.g, c.b)), minv = MIN(c.r, MIN(c.g, c.b));
    *l = (maxv + minv) / 2.0;
    if (maxv == minv) { *h = 0.0; *s = 0.0; return; }
    double d = maxv - minv;
    *s = *l > 0.5 ? d / (2.0 - maxv - minv) : d / (maxv + minv);
    if (maxv == c.r) *h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
    else if (maxv == c.g) *h = (c.b - c.r) / d + 2.0;
    else *h = (c.r - c.g) / d + 4.0;
    *h *= 60.0;
}

static double DLLinear(double v) { return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4); }
static double DLGamma(double v) { v = MAX(0.0, MIN(1.0, v)); return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1.0 / 2.4) - 0.055; }

// color-mix(in oklab, a, b amount)
static DLRGB DLOklabMix(DLRGB a, DLRGB b, double amount) {
    DLRGB in[2] = { a, b };
    double lab[2][3];
    int i;
    for (i = 0; i < 2; i++) {
        double r = DLLinear(in[i].r), g = DLLinear(in[i].g), bl = DLLinear(in[i].b);
        double l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl);
        double m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl);
        double s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl);
        lab[i][0] = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
        lab[i][1] = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
        lab[i][2] = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
    }
    double L = lab[0][0] + (lab[1][0] - lab[0][0]) * amount;
    double A = lab[0][1] + (lab[1][1] - lab[0][1]) * amount;
    double B = lab[0][2] + (lab[1][2] - lab[0][2]) * amount;
    double l = pow(L + 0.3963377774 * A + 0.2158037573 * B, 3.0);
    double m = pow(L - 0.1055613458 * A - 0.0638541728 * B, 3.0);
    double s = pow(L - 0.0894841775 * A - 1.2914855480 * B, 3.0);
    DLRGB out = { DLGamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                  DLGamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                  DLGamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s) };
    return out;
}

static NSColor *DLColorFromRGB(DLRGB c) {
    return [NSColor colorWithCalibratedRed:c.r green:c.g blue:c.b alpha:1.0];
}

@implementation DLThemes

#pragma mark Presets

+(void)addPreset:(NSString *)presetID name:(NSString *)name light:(BOOL)light angle:(double)angle
          colors:(NSArray *)colors stops:(NSArray *)stops {
    NSDictionary *summary = [NSDictionary dictionaryWithObjectsAndKeys:presetID, @"id", name, @"name",
                             [NSNumber numberWithBool:light], @"light", nil];
    [(NSMutableArray *)presetList addObject:summary];
    [presetData setObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:light], @"light",
                           [NSNumber numberWithDouble:angle], @"angle", colors, @"colors", stops, @"stops", nil]
                   forKey:presetID];
}

#define HSL(h, s, l) [NSArray arrayWithObjects:[NSNumber numberWithDouble:h], [NSNumber numberWithDouble:(s) / 100.0], [NSNumber numberWithDouble:(l) / 100.0], nil]
#define STOP(i, p) [NSArray arrayWithObjects:[NSNumber numberWithInt:(i)], [NSNumber numberWithDouble:p], nil]

// Values from the official web client (BG_GRADIENT_* tokens and presets).
+(void)loadPresets {
    if (presetList) return;
    presetList = [[NSMutableArray alloc] init];
    presetData = [[NSMutableDictionary alloc] init];
    [self addPreset:@"mint-apple" name:@"Mint Apple" light:YES angle:180
             colors:[NSArray arrayWithObjects:HSL(165.625, 39.669, 52.549), HSL(118.681, 40.444, 55.882), HSL(86.667, 48.293, 59.804), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 6.15), STOP(1, 48.7), STOP(2, 93.07), nil]];
    [self addPreset:@"citrus-sherbert" name:@"Citrus Sherbert" light:YES angle:180
             colors:[NSArray arrayWithObjects:HSL(39.683, 88.732, 58.235), HSL(18, 81.522, 63.922), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 31.1), STOP(1, 67.09), nil]];
    [self addPreset:@"retro-raincloud" name:@"Retro Raincloud" light:YES angle:148.71
             colors:[NSArray arrayWithObjects:HSL(201.553, 47.032, 42.941), HSL(241.017, 29.648, 60.98), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 5.64), STOP(1, 26.38), STOP(1, 49.92), STOP(0, 73.12), nil]];
    [self addPreset:@"hanami" name:@"Hanami" light:YES angle:38.08
             colors:[NSArray arrayWithObjects:HSL(352.174, 68.317, 80.196), HSL(43.146, 73.554, 76.275), HSL(115.714, 43.077, 74.51), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 3.56), STOP(1, 35.49), STOP(2, 68.78), nil]];
    [self addPreset:@"sunrise" name:@"Sunrise" light:YES angle:154.19
             colors:[NSArray arrayWithObjects:HSL(326.809, 41.964, 43.922), HSL(27.5, 44.86, 58.039), HSL(50.286, 46.256, 44.51), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 8.62), STOP(1, 48.07), STOP(2, 76.04), nil]];
    [self addPreset:@"cotton-candy" name:@"Cotton Candy" light:YES angle:180.14
             colors:[NSArray arrayWithObjects:HSL(349.315, 76.842, 81.373), HSL(226.4, 92.593, 84.118), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 8.5), STOP(1, 94.28), nil]];
    [self addPreset:@"lofi-vibes" name:@"Lofi Vibes" light:YES angle:179.52
             colors:[NSArray arrayWithObjects:HSL(219.759, 83.838, 80.588), HSL(183.81, 57.798, 78.627), HSL(129.6, 46.296, 78.824), HSL(75.738, 48.8, 75.49), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 7.08), STOP(1, 34.94), STOP(2, 65.12), STOP(3, 96.23), nil]];
    [self addPreset:@"desert-khaki" name:@"Desert Khaki" light:YES angle:38.99
             colors:[NSArray arrayWithObjects:HSL(28.696, 32.394, 86.078), HSL(40, 41.284, 78.627), HSL(50.164, 49.593, 75.882), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 12.92), STOP(1, 32.92), STOP(2, 52.11), nil]];
    [self addPreset:@"sunset" name:@"Sunset" light:NO angle:141.68
             colors:[NSArray arrayWithObjects:HSL(259.2, 55.556, 35.294), HSL(21.667, 66.667, 57.647), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 27.57), STOP(1, 71.25), nil]];
    [self addPreset:@"chroma-glow" name:@"Chroma Glow" light:NO angle:128.92
             colors:[NSArray arrayWithObjects:HSL(183.39, 86.341, 40.196), HSL(258.113, 89.831, 46.275), HSL(298.491, 90.857, 34.314), HSL(264.767, 100, 66.275), HSL(206.702, 75.494, 50.392), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 3.94), STOP(1, 26.1), STOP(2, 39.82), STOP(3, 56.89), STOP(4, 76.45), nil]];
    [self addPreset:@"forest" name:@"Forest" light:NO angle:162.27
             colors:[NSArray arrayWithObjects:HSL(124.286, 25.926, 10.588), HSL(142.5, 26.23, 23.922), HSL(76.154, 20.635, 24.706), HSL(116.667, 16.981, 41.569), HSL(42.766, 38.525, 47.843), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 11.2), STOP(1, 29.93), STOP(2, 48.64), STOP(3, 67.85), STOP(4, 83.54), nil]];
    [self addPreset:@"crimson-moon" name:@"Crimson Moon" light:NO angle:64.92
             colors:[NSArray arrayWithObjects:HSL(0, 88.608, 30.98), HSL(0, 0, 0), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 16.17), STOP(1, 72), nil]];
    [self addPreset:@"midnight-blurple" name:@"Midnight Blurple" light:NO angle:48.17
             colors:[NSArray arrayWithObjects:HSL(245.077, 55.085, 53.725), HSL(259.024, 74.545, 10.784), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 11.21), STOP(1, 61.92), nil]];
    [self addPreset:@"mars" name:@"Mars" light:NO angle:170.82
             colors:[NSArray arrayWithObjects:HSL(14.795, 36.318, 39.412), HSL(0, 36.19, 41.176), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 14.61), STOP(1, 74.62), nil]];
    [self addPreset:@"dusk" name:@"Dusk" light:NO angle:180
             colors:[NSArray arrayWithObjects:HSL(292.8, 13.514, 36.275), HSL(223.125, 41.026, 69.412), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 12.84), STOP(1, 85.99), nil]];
    [self addPreset:@"under-the-sea" name:@"Under the Sea" light:NO angle:179.14
             colors:[NSArray arrayWithObjects:HSL(114.783, 10.502, 42.941), HSL(158.667, 20.362, 43.333), HSL(175.385, 10.924, 46.667), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 1.91), STOP(1, 48.99), STOP(2, 96.35), nil]];
    [self addPreset:@"retro-storm" name:@"Retro Storm" light:NO angle:148.71
             colors:[NSArray arrayWithObjects:HSL(201.553, 47.032, 42.941), HSL(240.896, 27.801, 47.255), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 5.64), STOP(1, 26.38), STOP(1, 49.92), STOP(0, 73.12), nil]];
    [self addPreset:@"neon-nights" name:@"Neon Nights" light:NO angle:180
             colors:[NSArray arrayWithObjects:HSL(176.407, 98.817, 33.137), HSL(259.333, 39.474, 55.294), HSL(313.548, 52.542, 46.275), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 0), STOP(1, 50), STOP(2, 100), nil]];
    [self addPreset:@"strawberry-lemonade" name:@"Strawberry Lemonade" light:NO angle:161.03
             colors:[NSArray arrayWithObjects:HSL(326.98, 74.129, 39.412), HSL(27.778, 71.681, 44.314), HSL(39.588, 80.165, 52.549), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 18.79), STOP(1, 49.76), STOP(2, 80.72), nil]];
    [self addPreset:@"aurora" name:@"Aurora" light:NO angle:239.16
             colors:[NSArray arrayWithObjects:HSL(219.74, 86.517, 17.451), HSL(237.778, 76.415, 41.569), HSL(183.556, 78.035, 33.922), HSL(169.2, 60.241, 32.549), HSL(229.839, 92.537, 26.275), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 10.39), STOP(1, 26.87), STOP(2, 48.31), STOP(3, 64.98), STOP(4, 92.5), nil]];
    [self addPreset:@"sepia" name:@"Sepia" light:NO angle:69.98
             colors:[NSArray arrayWithObjects:HSL(32.727, 14.163, 45.686), HSL(36.207, 46.774, 24.314), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 14.14), STOP(1, 60.35), nil]];
    [self addPreset:@"blurple-twilight" name:@"Blurple Twilight" light:NO angle:47.61
             colors:[NSArray arrayWithObjects:HSL(233.904, 79.574, 53.922), HSL(245.294, 63.75, 31.373), nil]
              stops:[NSArray arrayWithObjects:STOP(0, 11.18), STOP(1, 64.54), nil]];
}

+(NSArray *)presets {
    [self loadPresets];
    return presetList;
}

+(NSString *)activePresetID {
    NSString *theme = [[DLPreferencesHandler sharedInstance] appearanceTheme];
    if (![theme hasPrefix:DLNitroThemePrefix]) return nil;
    [self loadPresets];
    NSString *presetID = [theme substringFromIndex:[DLNitroThemePrefix length]];
    return [presetData objectForKey:presetID] ? presetID : nil;
}

+(BOOL)isGradientThemeActive {
    return [self activePresetID] != nil;
}

+(BOOL)isLightThemeActive {
    NSString *presetID = [self activePresetID];
    return presetID && [[[presetData objectForKey:presetID] objectForKey:@"light"] boolValue];
}

#pragma mark Gradient

static DLRGB DLStopColor(NSDictionary *preset, NSArray *stop) {
    NSArray *hsl = [[preset objectForKey:@"colors"] objectAtIndex:(NSUInteger)[[stop objectAtIndex:0] intValue]];
    return DLRGBFromHSL([[hsl objectAtIndex:0] doubleValue], [[hsl objectAtIndex:1] doubleValue], [[hsl objectAtIndex:2] doubleValue]);
}

// CSS linear-gradient(angle, stops) sampled at fraction t of the gradient line.
static DLRGB DLGradientColor(NSDictionary *preset, double t) {
    NSArray *stops = [preset objectForKey:@"stops"];
    double position = t * 100.0;
    NSArray *first = [stops objectAtIndex:0];
    if (position <= [[first objectAtIndex:1] doubleValue]) return DLStopColor(preset, first);
    NSUInteger index;
    for (index = 1; index < [stops count]; index++) {
        NSArray *stop = [stops objectAtIndex:index];
        double end = [[stop objectAtIndex:1] doubleValue];
        if (position <= end) {
            NSArray *previous = [stops objectAtIndex:index - 1];
            double start = [[previous objectAtIndex:1] doubleValue];
            double f = end > start ? (position - start) / (end - start) : 1.0;
            DLRGB a = DLStopColor(preset, previous), b = DLStopColor(preset, stop);
            DLRGB c = { a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f };
            return c;
        }
    }
    return DLStopColor(preset, [stops lastObject]);
}

// Fills a bitmap with the gradient for a box of the given size (CSS pixels,
// y down), then lets block blend the overlay for one surface.
static NSBitmapImageRep *DLRenderGradient(NSDictionary *preset, NSSize size, NSInteger pixelsWide, NSInteger pixelsHigh,
                                          DLRGB overlay, double overlayAlpha, DLRGB tint, double tintAlpha) {
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:pixelsWide pixelsHigh:pixelsHigh
                                                                   bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:NO
                                                                  colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0] autorelease];
    unsigned char *data = [rep bitmapData];
    NSInteger rowBytes = [rep bytesPerRow];
    double angle = [[preset objectForKey:@"angle"] doubleValue] * M_PI / 180.0;
    double sx = sin(angle), sy = -cos(angle);
    double W = size.width, H = size.height;
    double length = fabs(W * sin(angle)) + fabs(H * cos(angle));
    if (length <= 0.0) length = 1.0;
    NSInteger x, y;
    for (y = 0; y < pixelsHigh; y++) {
        double py = (y + 0.5) * H / pixelsHigh;
        unsigned char *row = data + y * rowBytes;
        for (x = 0; x < pixelsWide; x++) {
            double px = (x + 0.5) * W / pixelsWide;
            double t = ((px - W / 2.0) * sx + (py - H / 2.0) * sy) / length + 0.5;
            DLRGB c = DLGradientColor(preset, MAX(0.0, MIN(1.0, t)));
            c.r = overlay.r * overlayAlpha + c.r * (1.0 - overlayAlpha);
            c.g = overlay.g * overlayAlpha + c.g * (1.0 - overlayAlpha);
            c.b = overlay.b * overlayAlpha + c.b * (1.0 - overlayAlpha);
            if (tintAlpha > 0.0) {
                c.r = tint.r * tintAlpha + c.r * (1.0 - tintAlpha);
                c.g = tint.g * tintAlpha + c.g * (1.0 - tintAlpha);
                c.b = tint.b * tintAlpha + c.b * (1.0 - tintAlpha);
            }
            row[x * 3] = (unsigned char)lround(MAX(0.0, MIN(1.0, c.r)) * 255.0);
            row[x * 3 + 1] = (unsigned char)lround(MAX(0.0, MIN(1.0, c.g)) * 255.0);
            row[x * 3 + 2] = (unsigned char)lround(MAX(0.0, MIN(1.0, c.b)) * 255.0);
        }
    }
    return rep;
}

+(NSSize)currentGradientSize {
    if (gradientSize.width > 0.0 && gradientSize.height > 0.0) return gradientSize;
    return [[NSScreen mainScreen] frame].size;
}

+(void)rebuildSurfacesIfNeeded {
    NSString *presetID = [self activePresetID];
    NSSize size = [self currentGradientSize];
    if (surfaceColors && [presetID isEqualToString:cachedPresetID] && NSEqualSizes(size, cachedSize)) return;
    [surfaceColors release];
    surfaceColors = nil;
    [cachedPresetID release];
    cachedPresetID = [presetID copy];
    cachedSize = size;
    if (!presetID) return;
    NSDictionary *preset = [presetData objectForKey:presetID];
    BOOL light = [[preset objectForKey:@"light"] boolValue];
    // Official overlay opacities (web client, opacity mix amount 1).
    double darkAlpha[] = { 0.9, 0.85, 0.8, 0.8, 0.75, 0.7, 0.65 };
    double lightAlpha[] = { 0.85, 0.8, 0.75, 0.85, 0.7, 0.65, 0.95 };
    DLRGB black = { 0.0, 0.0, 0.0 }, white = { 1.0, 1.0, 1.0 };
    DLRGB overlay = light ? white : black;
    // Half resolution: the gradient is smooth and the pattern scales it up.
    NSInteger pixelsWide = MAX(16, (NSInteger)ceil(size.width / 2.0));
    NSInteger pixelsHigh = MAX(16, (NSInteger)ceil(size.height / 2.0));
    surfaceColors = [[NSMutableArray alloc] init];
    NSInteger surface;
    for (surface = 0; surface < DLThemeSurfaceCount; surface++) {
        double alpha;
        DLRGB tint = light ? black : white;
        double tintAlpha = 0.0;
        if (surface <= DLThemeSurfaceHighest) {
            alpha = light ? lightAlpha[surface] : darkAlpha[surface];
        } else {
            alpha = light ? lightAlpha[DLThemeSurfaceLower] : darkAlpha[DLThemeSurfaceLower];
            if (surface == DLThemeSurfaceHover) tintAlpha = light ? 0.05 : 0.06;
            else if (surface == DLThemeSurfaceSelected) tintAlpha = light ? 0.1 : 0.12;
            else { tint = black; tintAlpha = light ? 0.12 : 0.4; }
        }
        NSBitmapImageRep *rep = DLRenderGradient(preset, size, pixelsWide, pixelsHigh, overlay, alpha, tint, tintAlpha);
        NSImage *image = [[[NSImage alloc] initWithSize:size] autorelease];
        [rep setSize:size];
        [image addRepresentation:rep];
        [surfaceColors addObject:[NSColor colorWithPatternImage:image]];
    }
}

+(NSColor *)colorForSurface:(DLThemeSurface)surface {
    [self rebuildSurfacesIfNeeded];
    if (!surfaceColors || surface >= DLThemeSurfaceCount) return nil;
    return [surfaceColors objectAtIndex:(NSUInteger)surface];
}

+(void)setGradientSize:(NSSize)size {
    if (NSEqualSizes(size, gradientSize)) return;
    gradientSize = size;
    if (![self isGradientThemeActive]) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:DLThemeGradientDidChangeNotification object:nil];
}

#pragma mark Text

// Theme text color from the first and last gradient stops, as the web client
// derives it: dark presets use the brighter stop, light presets the darker.
+(DLRGB)themeTextColor {
    NSDictionary *preset = [presetData objectForKey:[self activePresetID]];
    NSArray *stops = [preset objectForKey:@"stops"];
    DLRGB first = DLStopColor(preset, [stops objectAtIndex:0]);
    DLRGB last = DLStopColor(preset, [stops lastObject]);
    double h1, s1, l1, h2, s2, l2;
    DLHSLFromRGB(first, &h1, &s1, &l1);
    DLHSLFromRGB(last, &h2, &s2, &l2);
    BOOL light = [[preset objectForKey:@"light"] boolValue];
    BOOL firstIsBrighter = l1 >= l2;
    double hue = (light ? !firstIsBrighter : firstIsBrighter) ? h1 : h2;
    BOOL blueish = hue >= 200.0 && hue <= 300.0;
    double lightness = light ? (blueish ? 0.25 : 0.15) : (blueish ? 0.8 : 0.95);
    return DLRGBFromHSL(hue, 1.0, lightness);
}

+(NSColor *)mixedTextColorWithNeutral:(DLRGB)neutral {
    return DLColorFromRGB(DLOklabMix(neutral, [self themeTextColor], 0.38));
}

+(NSColor *)primaryTextColor {
    DLRGB neutral = [self isLightThemeActive] ? (DLRGB){ 0.192, 0.200, 0.220 } : (DLRGB){ 0.949, 0.953, 0.961 };
    return [self mixedTextColorWithNeutral:neutral];
}

+(NSColor *)secondaryTextColor {
    DLRGB neutral = [self isLightThemeActive] ? (DLRGB){ 0.361, 0.369, 0.400 } : (DLRGB){ 0.710, 0.729, 0.757 };
    return [self mixedTextColorWithNeutral:neutral];
}

#pragma mark Swatches

+(NSImage *)swatchImageForPresetID:(NSString *)presetID size:(CGFloat)side {
    [self loadPresets];
    NSDictionary *preset = [presetData objectForKey:presetID];
    if (!preset) return nil;
    DLRGB none = { 0.0, 0.0, 0.0 };
    NSInteger pixels = (NSInteger)ceil(side * 2.0);
    NSBitmapImageRep *rep = DLRenderGradient(preset, NSMakeSize(side, side), pixels, pixels, none, 0.0, none, 0.0);
    [rep setSize:NSMakeSize(side, side)];
    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(side, side)] autorelease];
    [image lockFocus];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.0, 0.0, side, side)] addClip];
    [rep drawInRect:NSMakeRect(0.0, 0.0, side, side)];
    [image unlockFocus];
    return image;
}

@end
