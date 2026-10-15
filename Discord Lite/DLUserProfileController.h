//
//  DLUserProfileController.h
//  Legacy Discord
//

#import <Cocoa/Cocoa.h>
#import "AsyncHTTPRequest.h"
#import "DLCompatibilityPopover.h"
#import "NSView+BGColor.h"

@class DLUser;
@class DLServer;
@class DLServerMember;

@interface DLUserProfileController : NSObject <AsyncHTTPRequestDelegate, NSTextViewDelegate, NSWindowDelegate> {
    NSWindow *hostWindow;
    NSImageView *accountAvatarView;
    NSButton *myProfileButton;
    DLCompatibilityPopover *profilePopover;
    NSViewController *profilePopoverController;
    DLUser *profileUser;
    DLServer *profileServer;
    DLServerMember *profileMember;
    NSPanel *profileDetailPanel;
    NSButton *profileAvatarButton;
    NSImageView *profileDetailAvatarView;
    NSCache *profileAvatarCache;
    NSMutableSet *profileAvatarRequests;
    NSCache *profileBannerImageCache;
    NSMutableSet *profileBannerImageRequests;
    NSMutableDictionary *profileDataCache;
    NSMutableSet *profileDataRequests;
    NSView_BGColor *profileBannerView;
    NSImageView *profileBannerImageView;
    NSTextField *profileBioField;
    NSTextField *profileMetadataField;
    NSView *profileRoleContainer;
    NSView *profileStatusBubble;
    NSTextField *profileStatusField;
    NSView_BGColor *profileDetailBannerView;
    NSImageView *profileDetailBannerImageView;
    NSTextField *profileDetailBioField;
    NSTextField *profileDetailMetadataField;
    NSTextField *profileDetailConnectionsField;
    NSView *profileDetailRoleContainer;
    NSView *profileDetailStatusBubble;
    NSTextField *profileDetailStatusField;
    NSString *profileBannerURL;
    NSTextView *profileNoteView;
    NSButton *profileNoteSaveButton;
    NSTextField *profileNoteStatusField;
    NSString *profileNoteUserID;
    DLUser *profileNoteUser;
    NSString *profileSavedNote;
    BOOL profileNoteSaving;
#if LEGACY_DISCORD_LOCAL_DEV
    BOOL offlineNotePreview;
#endif
}

-(id)initWithHostWindow:(NSWindow *)window
           userInfoView:(NSView *)userInfoView
             avatarView:(NSImageView *)avatarView;
-(void)showProfileForUser:(DLUser *)user relativeToRect:(NSRect)rect ofView:(NSView *)view;
-(void)userProfile:(NSDictionary *)profile didLoadForUser:(DLUser *)user inServer:(DLServer *)server;
-(void)userNote:(NSString *)note didLoadForUser:(DLUser *)user error:(BOOL)error;
-(void)userNote:(NSString *)note didSaveForUser:(DLUser *)user error:(BOOL)error;
-(void)members:(NSArray *)members didUpdateForServer:(DLServer *)server;
-(void)avatarDidUpdateForUser:(DLUser *)user data:(NSData *)data;
-(void)applyCurrentTheme;
-(void)close;
#if LEGACY_DISCORD_LOCAL_DEV
-(void)showOfflineProfileNoteForUser:(DLUser *)user note:(NSString *)note;
-(NSView *)offlineProfileDetailView;
#endif

@end
