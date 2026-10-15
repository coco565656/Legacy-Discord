//
//  DLEmojiPickerController.h
//  Legacy Discord
//

#import <Cocoa/Cocoa.h>
#import "AsyncHTTPRequest.h"

@class DLEmojiPickerController;
@class DLCompatibilityPopover;
@class ChatItemViewController;

@protocol DLEmojiPickerControllerDelegate <NSObject>
-(void)emojiPickerController:(DLEmojiPickerController *)controller didSelectEmoji:(NSDictionary *)emoji;
@end

@interface DLEmojiPickerController : NSObject <AsyncHTTPRequestDelegate> {
    id<DLEmojiPickerControllerDelegate> delegate;
    NSButton *button;
    DLCompatibilityPopover *popover;
    NSViewController *popoverController;
    NSSearchField *searchField;
    NSScrollView *scrollView;
    NSView *categoryBar;
    NSArray *visibleSections;
    NSArray *items;
    NSCache *pickerImageCache;
    ChatItemViewController *reactionChatView;
}

-(id)initWithButton:(NSButton *)button;
-(void)setDelegate:(id<DLEmojiPickerControllerDelegate>)delegate;
-(void)setEnabled:(BOOL)enabled;
-(void)showReactionPickerForChatView:(ChatItemViewController *)chatView relativeToView:(NSView *)anchorView;
-(void)close;
#if LEGACY_DISCORD_LOCAL_DEV
-(void)showOfflineReplayPicker;
-(BOOL)offlineReplayIsShown;
-(NSView *)offlineReplayContentView;
#endif

@end
