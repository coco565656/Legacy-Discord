//
//  DLLocalization.m
//  Legacy Discord
//

#import "DLLocalization.h"

static NSDictionary *translationTable = nil;
static NSString *activeLanguage = nil;

@implementation DLLocalization

+(NSString *)preferredLanguageSetting {
    NSString *setting = [[NSUserDefaults standardUserDefaults] stringForKey:@kAppLanguage];
    return [setting length] ? setting : @"system";
}

+(void)setPreferredLanguageSetting:(NSString *)setting {
    [[NSUserDefaults standardUserDefaults] setObject:setting forKey:@kAppLanguage];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Decided once per run so that every string in a session uses one language.
+(NSString *)activeLanguage {
    if (activeLanguage) return activeLanguage;
    NSString *setting = [self preferredLanguageSetting];
    if ([setting isEqualToString:@"system"]) {
        NSArray *preferred = [NSLocale preferredLanguages];
        NSString *first = [preferred count] ? [[preferred objectAtIndex:0] lowercaseString] : @"en";
        setting = [first hasPrefix:@"ja"] ? @"ja" : @"en";
    }
    activeLanguage = [([setting isEqualToString:@"ja"] ? @"ja" : @"en") retain];
    return activeLanguage;
}

+(BOOL)isJapanese {
    return [[self activeLanguage] isEqualToString:@"ja"];
}

+(NSLocale *)localeForAppLanguage {
    NSString *identifier = [self isJapanese] ? @"ja_JP" : @"en_US";
    return [[[NSLocale alloc] initWithLocaleIdentifier:identifier] autorelease];
}

+(NSDictionary *)table {
    if (translationTable) return translationTable;
    if ([self isJapanese]) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"Localizable-ja" ofType:@"plist"];
        translationTable = path ? [[NSDictionary alloc] initWithContentsOfFile:path] : nil;
        if (!translationTable) NSLog(@"Japanese strings could not be loaded.");
    }
    if (!translationTable) translationTable = [[NSDictionary alloc] init];
    return translationTable;
}

+(NSString *)translate:(NSString *)english {
    if (![english length]) return english;
    NSString *translated = [[self table] objectForKey:english];
    return [translated length] ? translated : english;
}

+(void)localizeMenu:(NSMenu *)menu {
    if (![self isJapanese] || !menu) return;
    [menu setTitle:[self translate:[menu title]]];
    NSEnumerator *enumerator = [[menu itemArray] objectEnumerator];
    NSMenuItem *item;
    while (item = [enumerator nextObject]) {
        if ([item isSeparatorItem]) continue;
        [item setTitle:[self translate:[item title]]];
        if ([item hasSubmenu]) [self localizeMenu:[item submenu]];
    }
}

+(void)localizeView:(NSView *)view {
    if (![self isJapanese] || !view) return;
    if ([view toolTip]) [view setToolTip:[self translate:[view toolTip]]];
    if ([view isKindOfClass:[NSButton class]]) {
        NSButton *button = (NSButton *)view;
        [button setTitle:[self translate:[button title]]];
    } else if ([view isKindOfClass:[NSTextField class]]) {
        NSTextField *field = (NSTextField *)view;
        if (![field isEditable] && [[field stringValue] length]) [field setStringValue:[self translate:[field stringValue]]];
        NSString *placeholder = [[field cell] placeholderString];
        if ([placeholder length]) [[field cell] setPlaceholderString:[self translate:placeholder]];
    } else if ([view isKindOfClass:[NSBox class]]) {
        [(NSBox *)view setTitle:[self translate:[(NSBox *)view title]]];
    }
    if ([view menu]) [self localizeMenu:[view menu]];
    NSEnumerator *enumerator = [[view subviews] objectEnumerator];
    NSView *subview;
    while (subview = [enumerator nextObject]) [self localizeView:subview];
}

+(void)localizeWindow:(NSWindow *)window {
    if (![self isJapanese] || !window) return;
    [window setTitle:[self translate:[window title]]];
    [self localizeView:[window contentView]];
}

@end

NSString *DLLocalizedString(NSString *english) {
    return [DLLocalization translate:english];
}

NSString *DLPluralSuffix(NSInteger count) {
    if ([DLLocalization isJapanese]) return @"";
    return count == 1 ? @"" : @"s";
}
