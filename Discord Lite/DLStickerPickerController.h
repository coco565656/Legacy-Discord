//
//  DLStickerPickerController.h
//  Legacy Discord
//

#import <Cocoa/Cocoa.h>
#import "AsyncHTTPRequest.h"

@class DLStickerPickerController;
@class DLCompatibilityPopover;

@protocol DLStickerPickerControllerDelegate <NSObject>
-(void)stickerPickerController:(DLStickerPickerController *)controller didSelectSticker:(NSDictionary *)sticker;
-(void)stickerPickerControllerDidClose:(DLStickerPickerController *)controller;
@end

@interface DLStickerPickerController : NSObject <AsyncHTTPRequestDelegate> {
    id<DLStickerPickerControllerDelegate> delegate;
    NSButton *button;
    DLCompatibilityPopover *popover;
    NSViewController *popoverController;
    NSSearchField *searchField;
    NSScrollView *scrollView;
    NSArray *items;
}

-(id)initWithButton:(NSButton *)button;
-(void)setDelegate:(id<DLStickerPickerControllerDelegate>)delegate;
-(void)setEnabled:(BOOL)enabled;
-(void)close;
#if LEGACY_DISCORD_LOCAL_DEV
-(void)showOfflineReplayItems:(NSArray *)stickerItems;
-(BOOL)offlineReplayIsShown;
-(NSView *)offlineReplayContentView;
#endif

@end
