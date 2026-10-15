//
//  DLUserPanelController.h
//  Legacy Discord
//

#import <Cocoa/Cocoa.h>
#import "DLWSController.h"

@class NSView_BGColor;
@class DLStatusDotView;
@class DLUserPanelIconButton;

// Owns the account panel under the channel list: background, presence dot,
// name/username labels and the microphone, headphone and settings buttons.
@interface DLUserPanelController : NSObject {
    NSView_BGColor *panelView;
    NSImageView *avatarView;
    NSTextField *nameField;
    NSTextField *usernameField;
    NSButton *settingsButton;
    DLStatusDotView *statusDotView;
    DLUserPanelIconButton *microphoneButton;
    DLUserPanelIconButton *headphoneButton;
    DLWSConnectionState connectionState;
}

-(id)initWithPanelView:(NSView_BGColor *)inPanelView
            avatarView:(NSImageView *)inAvatarView
             nameField:(NSTextField *)inNameField
         usernameField:(NSTextField *)inUsernameField;
-(void)setConnectionState:(DLWSConnectionState)state;
-(void)applyCurrentTheme;

@end
