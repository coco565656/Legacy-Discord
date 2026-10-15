#import "DLReplayFixtureProvider.h"
#import "DLServer.h"
#import "DLServerChannel.h"
#import "DLMessage.h"
#import "DLUser.h"

#if LEGACY_DISCORD_LOCAL_DEV

@implementation DLReplayFixtureProvider

+ (NSDictionary *)userWithID:(NSString *)userID name:(NSString *)name {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            userID, @"id", name, @"username", name, @"global_name",
            [NSNull null], @"avatar", @"0", @"discriminator", nil];
}

+ (NSDictionary *)messageWithID:(NSString *)messageID
                         author:(NSDictionary *)author
                        content:(NSString *)content
                      timestamp:(NSString *)timestamp {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            messageID, @"id", @"local-replay-channel", @"channel_id",
            author, @"author", content, @"content", timestamp, @"timestamp",
            [NSArray array], @"attachments", [NSArray array], @"embeds",
            [NSArray array], @"mentions", nil];
}

+ (NSDictionary *)unicodeReaction {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSDictionary dictionaryWithObjectsAndKeys:@"👍", @"name", [NSNull null], @"id", nil], @"emoji",
            [NSNumber numberWithInteger:3], @"count",
            [NSNumber numberWithBool:NO], @"me", nil];
}

+ (NSDictionary *)localImageAttachment {
    NSMutableDictionary *attachment = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                       @"local-attachment-image-001", @"id",
                                       @"synthetic-local-image.png", @"filename",
                                       @"image/png", @"content_type",
                                       [NSNumber numberWithInteger:1000], @"width",
                                       [NSNumber numberWithInteger:784], @"height",
                                       [NSNumber numberWithInteger:24000], @"size", nil];
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Discord-Logo" ofType:@"png"];
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    [attachment setObject:(data ? data : [NSData data]) forKey:@"preview_data"];
    return attachment;
}

+ (NSArray *)messagesForFixtureNamed:(NSString *)fixtureName {
    NSDictionary *avery = [self userWithID:@"local-user-avery" name:@"Avery Park"];
    NSDictionary *mika = [self userWithID:@"local-user-mika" name:@"Mika Ito"];
    NSDictionary *replay = [self userWithID:@"local-user-replay" name:@"Replay Bot"];

    NSDictionary *first = [self messageWithID:@"local-message-001"
                                       author:avery
                                      content:@"This is a synthetic replay message. It uses the normal message view, Markdown parser, layout calculation, and row-height path."
                                    timestamp:@"2024-06-10T10:00:00.000000+00:00"];
    NSMutableDictionary *reply = [[[self messageWithID:@"local-message-002"
                                                author:mika
                                               content:@"The replay is offline and contains no account data."
                                             timestamp:@"2024-06-10T10:03:00.000000+00:00"] mutableCopy] autorelease];
    [reply setValue:first forKey:@"referenced_message"];
    [reply setValue:@"2024-06-10T10:04:00.000000+00:00" forKey:@"edited_timestamp"];

    NSDictionary *groupOlder = [self messageWithID:@"local-message-003"
                                            author:replay
                                           content:@"A second message from the same author tests compact-message grouping."
                                         timestamp:@"2024-06-10T10:06:00.000000+00:00"];
    NSMutableDictionary *groupNewer = [[[self messageWithID:@"local-message-004"
                                                     author:replay
                                                    content:@"日本語、English, and Unicode emoji ✨ are rendered by the shared text path."
                                                  timestamp:@"2024-06-10T10:08:00.000000+00:00"] mutableCopy] autorelease];
    [groupNewer setValue:[NSArray arrayWithObject:[self unicodeReaction]] forKey:@"reactions"];

    if ([fixtureName isEqualToString:@"channel-message-states"]) {
        NSDictionary *nextDay = [self messageWithID:@"local-message-005"
                                             author:avery
                                            content:@"A message on the following day tests the date divider."
                                          timestamp:@"2024-06-11T10:00:00.000000+00:00"];
        return [NSArray arrayWithObjects:nextDay, groupNewer, groupOlder, reply, first, nil];
    }
    if ([fixtureName isEqualToString:@"channel-layout"] ||
        [fixtureName isEqualToString:@"channel-layout-text"]) {
        NSDictionary *longMessage = [self messageWithID:@"local-layout-001"
                                                   author:avery
                                                  content:@"A deliberately long synthetic message verifies that the production text measurement and row layout agree when ordinary words wrap across several lines at narrow, standard, and wide window sizes. The sentence remains long enough to exercise multiple wrapping decisions without using any live account content."
                                                timestamp:@"2024-06-10T11:00:00.000000+00:00"];
        NSDictionary *multilineMessage = [self messageWithID:@"local-layout-002"
                                                        author:mika
                                                       content:@"First explicit line.\nSecond explicit line.\nThird explicit line with symbols: ★ ✓ →"
                                                     timestamp:@"2024-06-10T11:04:00.000000+00:00"];
        NSDictionary *japaneseMessage = [self messageWithID:@"local-layout-003"
                                                      author:replay
                                                     content:@"日本語の一行目です。\n二行目では幅の狭い画面を確認します。\n三行目にも絵文字を含めます 🌸"
                                                   timestamp:@"2024-06-10T11:08:00.000000+00:00"];
        return [NSArray arrayWithObjects:japaneseMessage, multilineMessage, longMessage, nil];
    }
    if ([fixtureName isEqualToString:@"channel-layout-unbroken"]) {
        NSString *unbroken = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
                              @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
                              @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
                              @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        NSDictionary *message = [self messageWithID:@"local-unbroken-001"
                                              author:avery
                                             content:unbroken
                                           timestamp:@"2024-06-10T11:20:00.000000+00:00"];
        return [NSArray arrayWithObject:message];
    }
    if ([fixtureName isEqualToString:@"channel-layout-states"]) {
        NSMutableDictionary *edited = [[[self messageWithID:@"local-state-001"
                                                      author:avery
                                                     content:@"Edited messages keep their marker after multiline content.\nThis second line verifies the shared text container."
                                                   timestamp:@"2024-06-10T11:30:00.000000+00:00"] mutableCopy] autorelease];
        [edited setObject:@"2024-06-10T11:31:00.000000+00:00" forKey:@"edited_timestamp"];

        NSDictionary *referenced = [self messageWithID:@"local-state-reference"
                                                 author:mika
                                                content:@"Synthetic referenced message"
                                              timestamp:@"2024-06-10T11:32:00.000000+00:00"];
        NSMutableDictionary *replyState = [[[self messageWithID:@"local-state-002"
                                                          author:replay
                                                         content:@"A reply can also contain multiple lines.\nIts body and reference must not overlap."
                                                       timestamp:@"2024-06-10T11:33:00.000000+00:00"] mutableCopy] autorelease];
        [replyState setObject:referenced forKey:@"referenced_message"];

        NSMutableDictionary *reactionState = [[[self messageWithID:@"local-state-003"
                                                             author:mika
                                                            content:@"Reactions remain below a multiline message.\nThe second line must stay clear of the reaction row."
                                                          timestamp:@"2024-06-10T11:36:00.000000+00:00"] mutableCopy] autorelease];
        [reactionState setObject:[NSArray arrayWithObject:[self unicodeReaction]] forKey:@"reactions"];
        return [NSArray arrayWithObjects:reactionState, replyState, edited, nil];
    }
    if ([fixtureName isEqualToString:@"channel-layout-attachment"]) {
        NSMutableDictionary *imageMessage = [[[self messageWithID:@"local-image-001"
                                                            author:replay
                                                           content:@"This bundled image uses the production attachment preview and stays fully offline."
                                                         timestamp:@"2024-06-10T11:40:00.000000+00:00"] mutableCopy] autorelease];
        [imageMessage setObject:[NSArray arrayWithObject:[self localImageAttachment]] forKey:@"attachments"];
        return [NSArray arrayWithObject:imageMessage];
    }
    return [NSArray arrayWithObjects:reply, first, nil];
}

+ (NSString *)channelNameForFixtureNamed:(NSString *)fixtureName {
    if ([fixtureName isEqualToString:@"channel-navigation"]) return @"general";
    if ([fixtureName isEqualToString:@"channel-message-states"]) return @"replay-message-states";
    if ([fixtureName isEqualToString:@"channel-layout"] || [fixtureName isEqualToString:@"channel-layout-text"]) return @"replay-layout-text";
    if ([fixtureName isEqualToString:@"channel-layout-unbroken"]) return @"replay-layout-unbroken";
    if ([fixtureName isEqualToString:@"channel-layout-states"]) return @"replay-layout-states";
    if ([fixtureName isEqualToString:@"channel-layout-attachment"]) return @"replay-layout-attachment";
    return @"replay-basic";
}

+ (NSArray *)serversForNavigationFixture {
    NSString *imagePath = [[NSBundle mainBundle] pathForResource:@"Discord-Logo" ofType:@"png"];
    NSData *imageData = imagePath ? [NSData dataWithContentsOfFile:imagePath] : nil;
    NSDictionary *homeData = [NSDictionary dictionaryWithObjectsAndKeys:
                              @"fixture-home", @"id", @"Direct Messages", @"name",
                              [NSNull null], @"icon", [NSArray array], @"members",
                              [NSArray array], @"emojis", [NSArray array], @"stickers",
                              [NSArray array], @"roles", nil];
    NSDictionary *workspaceData = [NSDictionary dictionaryWithObjectsAndKeys:
                                   @"fixture-server", @"id", @"Example Community", @"name",
                                   [NSNull null], @"icon", [NSArray array], @"members",
                                   [NSArray array], @"emojis", [NSArray array], @"stickers",
                                   [NSArray array], @"roles", nil];
    DLServer *home = [[DLServer alloc] initWithDict:homeData];
    [home setIconImageData:imageData];
    DLServer *workspace = [[DLServer alloc] initWithDict:workspaceData];
    [workspace setIconImageData:imageData];
    [workspace setHasUnreadMessages:YES];
    [workspace setMentionCount:3];
    NSArray *result = [NSArray arrayWithObjects:home, workspace, nil];
    [home release];
    [workspace release];
    return result;
}

+ (NSArray *)channelsForNavigationFixture {
    NSDictionary *generalData = [NSDictionary dictionaryWithObjectsAndKeys:
                                 @"fixture-general", @"id", @"general", @"name",
                                 [NSNumber numberWithInteger:ChannelTypeStandard], @"type",
                                 [NSNull null], @"last_message_id", nil];
    NSDictionary *announcementsData = [NSDictionary dictionaryWithObjectsAndKeys:
                                       @"fixture-announcements", @"id", @"announcements", @"name",
                                       [NSNumber numberWithInteger:ChannelTypeAnnouncements], @"type",
                                       [NSNull null], @"last_message_id", nil];
    NSDictionary *voiceData = [NSDictionary dictionaryWithObjectsAndKeys:
                               @"fixture-voice", @"id", @"Voice Lounge", @"name",
                               [NSNumber numberWithInteger:ChannelTypeVoice], @"type",
                               [NSNull null], @"last_message_id", nil];
    NSDictionary *categoryData = [NSDictionary dictionaryWithObjectsAndKeys:
                                  @"fixture-category", @"id", @"Text Channels", @"name",
                                  [NSNumber numberWithInteger:ChannelTypeHeader], @"type",
                                  [NSNull null], @"last_message_id", nil];
    DLServerChannel *general = [[DLServerChannel alloc] initWithDict:generalData];
    [general setHasUnreadMessages:YES];
    [general setMentionCount:2];
    DLServerChannel *announcements = [[DLServerChannel alloc] initWithDict:announcementsData];
    DLServerChannel *voice = [[DLServerChannel alloc] initWithDict:voiceData];
    DLServerChannel *category = [[DLServerChannel alloc] initWithDict:categoryData];
    [category setChildren:[NSArray arrayWithObjects:general, announcements, voice, nil]];
    NSArray *result = [NSArray arrayWithObject:category];
    [general release];
    [announcements release];
    [voice release];
    [category release];
    return result;
}

+ (DLMessage *)composerReplyMessage {
    NSDictionary *author = [self userWithID:@"local-composer-author" name:@"Morgan Lee"];
    NSDictionary *dictionary = [self messageWithID:@"local-composer-reply"
                                            author:author
                                           content:@"Synthetic message selected as the reply target."
                                         timestamp:@"2024-06-10T12:00:00.000000+00:00"];
    return [[[DLMessage alloc] initWithDict:dictionary] autorelease];
}

+ (NSArray *)composerCandidateUsers {
    NSMutableArray *users = [NSMutableArray array];
    NSArray *dictionaries = [NSArray arrayWithObjects:
        [self userWithID:@"local-candidate-avery" name:@"Avery Park"],
        [self userWithID:@"local-candidate-mika" name:@"Mika Ito"],
        [self userWithID:@"local-candidate-morgan" name:@"Morgan Lee"], nil];
    NSEnumerator *enumerator = [dictionaries objectEnumerator];
    NSDictionary *dictionary;
    while (dictionary = [enumerator nextObject]) {
        DLUser *user = [[[DLUser alloc] initWithDict:dictionary] autorelease];
        [users addObject:user];
    }
    return users;
}

+ (NSArray *)composerAttachmentPaths {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Discord-Logo" ofType:@"png"];
    return path ? [NSArray arrayWithObject:path] : [NSArray array];
}

+ (NSArray *)composerStickerItems {
    NSDictionary *sticker = [NSDictionary dictionaryWithObjectsAndKeys:
        @"local-sticker", @"id", @"Synthetic Sticker", @"name",
        @"Offline fixture", @"description", @"test offline", @"tags",
        [NSNumber numberWithInteger:3], @"format_type",
        [NSNumber numberWithBool:YES], @"available", nil];
    return [NSArray arrayWithObject:sticker];
}

+ (DLUser *)profileNoteUser {
    return [[[DLUser alloc] initWithDict:[self userWithID:@"local-note-user" name:@"Avery Park"]] autorelease];
}

@end

#endif
