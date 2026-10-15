#import <Foundation/Foundation.h>

@class DLMessage;
@class DLUser;

@class DLServer;

@interface DLReplayFixtureProvider : NSObject
+ (NSArray *)messagesForFixtureNamed:(NSString *)fixtureName;
+ (NSString *)channelNameForFixtureNamed:(NSString *)fixtureName;
+ (NSArray *)serversForNavigationFixture;
+ (NSArray *)channelsForNavigationFixture;
// Fictional server with hoisted/plain roles and members in every presence
// state, for the production member list.
+ (DLServer *)serverForMembersFixture;
+ (DLMessage *)composerReplyMessage;
+ (NSArray *)composerCandidateUsers;
+ (NSArray *)composerAttachmentPaths;
+ (NSArray *)composerStickerItems;
+ (DLUser *)profileNoteUser;
@end
