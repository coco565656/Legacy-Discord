//
//  DLDialog.h
//  Legacy Discord
//
//  Discord-style modal: a dimmed backdrop over the window and a centered dark
//  card with a title, optional message and content, and a footer of buttons.
//  Used instead of NSAlert, whose Aqua sheet does not match the client.
//

#import <Cocoa/Cocoa.h>

typedef enum {
    DLDialogButtonStylePrimary = 0,
    DLDialogButtonStyleDanger = 1,
    DLDialogButtonStyleLink = 2       // plain text, like Cancel
} DLDialogButtonStyle;

// Index passed to the handler when the dialog is dismissed with Escape, the
// close button or a click on the backdrop.
#define DLDialogCancelIndex (-1)

@class DLDialog;
// Return YES to close the dialog; NO keeps it open (for example while a
// request runs, then call -close yourself).
typedef BOOL (^DLDialogHandler)(DLDialog *dialog, NSInteger buttonIndex);

@interface DLDialog : NSObject <NSWindowDelegate> {
    NSString *title;
    NSString *message;
    NSView *contentView;
    NSMutableArray *buttonSpecs;
    NSMutableArray *buttons;
    DLDialogHandler handler;
    NSWindow *parentWindow;
    NSWindow *backdropWindow;
    NSPanel *panel;
    NSTextField *errorLabel;
    CGFloat width;
    BOOL closed;
}

+(DLDialog *)dialogWithTitle:(NSString *)title message:(NSString *)message;
-(void)setWidth:(CGFloat)width;
// Extra controls between the message and the footer; its width is set to
// the card's inner width, its height is kept.
-(void)setContentView:(NSView *)view;
// Buttons are laid out from the right in the order added; the first one is
// the default (Return) button.
-(void)addButtonWithTitle:(NSString *)title style:(DLDialogButtonStyle)style;
-(void)setHandler:(DLDialogHandler)handler;
-(void)showInWindow:(NSWindow *)window;
-(void)close;
-(void)setBusy:(BOOL)busy;
-(void)setErrorMessage:(NSString *)error;
-(NSPanel *)panel;

// Controls styled for the dialog card.
+(NSTextField *)labelWithString:(NSString *)string frame:(NSRect)frame;
+(NSTextField *)sectionLabelWithString:(NSString *)string frame:(NSRect)frame;
+(NSTextField *)textFieldWithFrame:(NSRect)frame placeholder:(NSString *)placeholder;
// Height a wrapping label needs at the given width.
+(CGFloat)heightOfLabel:(NSTextField *)label forWidth:(CGFloat)width;

@end

// Official on/off switch.
@interface DLToggleSwitch : NSControl {
    BOOL on;
}
-(BOOL)isOn;
-(void)setOn:(BOOL)on;
@end

// Full-width option row with a radio circle at the left (Notification
// Settings, channel type). The owner keeps one of a group selected.
@interface DLOptionRow : NSControl {
    NSString *title;
    NSString *detail;
    NSString *iconName;
    BOOL selected;
    BOOL hovered;
    NSTrackingArea *trackingArea;
}
-(void)setTitle:(NSString *)title;
-(void)setDetail:(NSString *)detail;
-(void)setIconName:(NSString *)iconName;
-(BOOL)isSelected;
-(void)setSelected:(BOOL)selected;
@end

// A title with a description and a switch at the right, as in settings.
@interface DLSwitchRow : NSView {
    NSTextField *titleLabel;
    NSTextField *detailLabel;
    DLToggleSwitch *toggle;
}
-(id)initWithFrame:(NSRect)frame title:(NSString *)title detail:(NSString *)detail;
-(DLToggleSwitch *)toggle;
@end
