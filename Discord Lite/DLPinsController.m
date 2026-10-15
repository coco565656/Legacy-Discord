//
//  DLPinsController.m
//  Legacy Discord
//

#import "DLPinsController.h"
#import "DLMessageSearchController.h"
#import "DLController.h"
#import "DLChannel.h"

@implementation DLPinsController

-(id)initWithButton:(NSButton *)inButton searchController:(DLMessageSearchController *)inSearchController {
    self = [super init];
    if (self) {
        button = [inButton retain];
        searchController = [inSearchController retain];
        [button setTarget:self];
        [button setAction:@selector(togglePinnedMessages:)];
    }
    return self;
}

-(void)setDelegate:(id<DLPinsControllerDelegate>)inDelegate { delegate = inDelegate; }
-(void)setEnabled:(BOOL)enabled { [button setEnabled:enabled]; }

-(IBAction)togglePinnedMessages:(id)sender {
    if (active) {
        [self close];
        return;
    }
    DLChannel *channel = [[DLController sharedInstance] selectedChannel];
    if (!channel || ![delegate pinsControllerMayOpen:self]) {
        [button setState:NSOffState];
        NSBeep();
        return;
    }
    [searchController showPinnedMessagesLoading];
    active = YES;
    [button setState:NSOnState];
    [[DLController sharedInstance] loadPinsForChannel:channel];
}

-(void)deactivate {
    active = NO;
    [button setState:NSOffState];
}

-(void)close {
    [self deactivate];
    [searchController close];
}

-(void)channelPins:(NSArray *)messages didLoadForChannel:(DLChannel *)channel {
    if (!active || ![[[DLController sharedInstance] selectedChannel] isEqual:channel]) return;
    [searchController showPinnedMessages:messages];
}

-(void)requestDidFail {
    if (active) [searchController showPinnedMessagesError];
}

-(void)dealloc {
    [button setTarget:nil];
    [button release];
    [searchController release];
    [super dealloc];
}

@end
