//
//  DLUserPanelController.m
//  Legacy Discord
//

#import "DLUserPanelController.h"
#import "DLMainWindowChromeControls.h"
#import "DLUtil.h"
#import "NSView+BGColor.h"
#import "NSView+Border.h"

static const CGFloat DLUserPanelButtonSize = 28.0;
static const CGFloat DLUserPanelButtonGap = 2.0;
static const CGFloat DLUserPanelStatusDotSize = 14.0;

@interface DLUserPanelController ()
-(NSButton *)findSettingsButton;
-(void)installControls;
@end

@implementation DLUserPanelController

-(id)initWithPanelView:(NSView_BGColor *)inPanelView
            avatarView:(NSImageView *)inAvatarView
             nameField:(NSTextField *)inNameField
         usernameField:(NSTextField *)inUsernameField {
    self = [super init];
    if (self) {
        panelView = [inPanelView retain];
        avatarView = [inAvatarView retain];
        nameField = [inNameField retain];
        usernameField = [inUsernameField retain];
        settingsButton = [[self findSettingsButton] retain];
        [settingsButton setToolTip:@"User Settings"];
        connectionState = DLWSConnectionStateDisconnected;
        [self installControls];
        [self applyCurrentTheme];
    }
    return self;
}

-(NSButton *)findSettingsButton {
    NSEnumerator *enumerator = [[panelView subviews] objectEnumerator];
    NSView *subview;
    while (subview = [enumerator nextObject]) {
        if ([subview isKindOfClass:[NSButton class]] &&
            [(NSButton *)subview action] == @selector(showSettingsMenu:)) {
            return (NSButton *)subview;
        }
    }
    return nil;
}

-(DLUserPanelIconButton *)iconButtonWithKind:(NSInteger)kind frame:(NSRect)frame {
    DLUserPanelIconButton *button = [[[DLUserPanelIconButton alloc] initWithFrame:frame] autorelease];
    [button setIconKind:kind];
    [button setBordered:NO];
    [button setTitle:@""];
    [button setButtonType:NSMomentaryChangeButton];
    [button setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    // Voice is not implemented yet; the controls keep Discord's panel layout
    // and are enabled once a voice session exists.
    [button setEnabled:NO];
    [button setToolTip:@"Voice chat is not available yet"];
    return button;
}

-(void)installControls {
    // Settings sits at the right edge; microphone and headphones go to its left.
    NSRect settingsFrame = settingsButton ? [settingsButton frame]
        : NSMakeRect(NSWidth([panelView bounds]) - 38.0, 19.0, 18.0, 18.0);
    CGFloat centerY = NSMidY(settingsFrame);
    CGFloat right = NSMinX(settingsFrame) - 5.0;
    NSRect headphoneFrame = NSMakeRect(right - DLUserPanelButtonSize, round(centerY - DLUserPanelButtonSize / 2.0),
                                       DLUserPanelButtonSize, DLUserPanelButtonSize);
    NSRect microphoneFrame = NSOffsetRect(headphoneFrame, -(DLUserPanelButtonSize + DLUserPanelButtonGap), 0.0);
    headphoneButton = [[self iconButtonWithKind:DLUserPanelIconHeadphones frame:headphoneFrame] retain];
    microphoneButton = [[self iconButtonWithKind:DLUserPanelIconMicrophone frame:microphoneFrame] retain];
    [panelView addSubview:microphoneButton];
    [panelView addSubview:headphoneButton];

    // Keep the labels clear of the new buttons.
    CGFloat labelRight = NSMinX(microphoneFrame) - 4.0;
    NSTextField *fields[2] = { nameField, usernameField };
    for (NSUInteger index = 0; index < 2; index++) {
        NSRect frame = [fields[index] frame];
        frame.size.width = MAX(20.0, labelRight - NSMinX(frame));
        [fields[index] setFrame:frame];
        [[fields[index] cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    }

    NSRect avatarFrame = [avatarView frame];
    statusDotView = [[DLStatusDotView alloc] initWithFrame:
                     NSMakeRect(NSMaxX(avatarFrame) - DLUserPanelStatusDotSize + 3.0,
                                NSMinY(avatarFrame) - 3.0,
                                DLUserPanelStatusDotSize, DLUserPanelStatusDotSize)];
    [statusDotView setAutoresizingMask:[avatarView autoresizingMask]];
    [panelView addSubview:statusDotView positioned:NSWindowAbove relativeTo:nil];
}

-(void)setConnectionState:(DLWSConnectionState)state {
    connectionState = state;
    [self applyCurrentTheme];
}

-(void)applyCurrentTheme {
    NSColor *panelColor = [DLUtil nativeUserPanelColor];
    [panelView setBackgroundColor:panelColor];
    [panelView setBottomBorderColor:panelColor];
    [nameField setTextColor:[DLUtil nativePrimaryTextColor]];
    [usernameField setTextColor:[DLUtil nativeSecondaryTextColor]];
    NSColor *statusColor = (connectionState == DLWSConnectionStateConnected)
        ? [DLUtil nativeOnlineStatusColor] : [DLUtil nativeOfflineStatusColor];
    [statusDotView setDotColor:statusColor ringColor:panelColor];
    [statusDotView setToolTip:(connectionState == DLWSConnectionStateConnected ? @"Online" : @"Connecting")];
    [microphoneButton setNeedsDisplay:YES];
    [headphoneButton setNeedsDisplay:YES];
    [panelView setNeedsDisplay:YES];
}

-(void)dealloc {
    [statusDotView release];
    [microphoneButton release];
    [headphoneButton release];
    [settingsButton release];
    [usernameField release];
    [nameField release];
    [avatarView release];
    [panelView release];
    [super dealloc];
}

@end
