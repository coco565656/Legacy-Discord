//
//  DLLocalization.h
//  Legacy Discord
//
//  In-app language switching. User interface text is written in English in
//  the code and looked up in Localizable-ja.plist when the app language is
//  Japanese. The language is chosen in Settings > Language ("system" follows
//  the Mac's preferred languages) and applies after a restart.
//

#import <Cocoa/Cocoa.h>

#define kAppLanguage "AppLanguage"

// The translation of an English UI string, or the string itself.
NSString *DLLocalizedString(NSString *english);
// Plural "s" for English formats like "%ld result%@"; empty in Japanese.
NSString *DLPluralSuffix(NSInteger count);

@interface DLLocalization : NSObject

// "system", "en" or "ja" as stored in the preferences.
+(NSString *)preferredLanguageSetting;
+(void)setPreferredLanguageSetting:(NSString *)setting;
// The language in use for this run: "en" or "ja".
+(NSString *)activeLanguage;
+(BOOL)isJapanese;
// Translates nib text in place: window titles, labels, buttons, placeholders,
// tool tips and menus, for windows and views loaded from xib files.
+(void)localizeView:(NSView *)view;
+(void)localizeWindow:(NSWindow *)window;
+(void)localizeMenu:(NSMenu *)menu;

@end
