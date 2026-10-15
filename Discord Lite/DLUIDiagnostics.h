#import <Cocoa/Cocoa.h>

@class ChatScrollView;

@interface DLUIDiagnostics : NSObject
+ (NSString *)writeSanitizedSnapshotForWindow:(NSWindow *)window
                              chatScrollView:(ChatScrollView *)chatScrollView;
+ (void)recordEvent:(NSString *)event details:(NSDictionary *)details;
@end
