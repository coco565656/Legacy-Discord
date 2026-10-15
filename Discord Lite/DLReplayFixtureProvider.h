#import <Foundation/Foundation.h>

@class DLMessage;
@class DLUser;

@interface DLReplayFixtureProvider : NSObject
+ (NSArray *)messagesForFixtureNamed:(NSString *)fixtureName;
+ (NSString *)channelNameForFixtureNamed:(NSString *)fixtureName;
+ (NSArray *)serversForNavigationFixture;
+ (NSArray *)channelsForNavigationFixture;
+ (DLMessage *)composerReplyMessage;
+ (NSArray *)composerCandidateUsers;
+ (NSArray *)composerAttachmentPaths;
+ (NSArray *)composerStickerItems;
+ (DLUser *)profileNoteUser;
@end
