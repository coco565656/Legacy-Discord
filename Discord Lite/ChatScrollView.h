//
//  ChatScrollView.h
//  Discord Lite
//
//  Created by Collin Mistr on 11/2/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "ChatItemViewController.h"
#import "NSScroller+BGColor.h"

@protocol ChatScrollViewDelegate <NSObject>
@optional
-(void)updatePendingAttachmentsWithFilePaths:(NSArray *)paths;
@end

@interface ChatScrollView : NSScrollView {
    NSMutableArray *content;
    id<ChatScrollViewDelegate> delegate;
    ChatItemViewController *visibleActionBarItem;
    NSView *sharedMessageActionBar;
    NSTrackingArea *messageHoverTrackingArea;
    NSString *unreadStartMessageID;
    NSView *unreadSeparatorView;
}

-(NSArray *)content;

-(void)setDelegate:(id<ChatScrollViewDelegate>)inDelegate;
-(void)setContent:(NSArray *)inContent;
-(void)appendContent:(NSArray *)inContent;
-(void)prependContent:(NSArray *)inContent preservingVisiblePosition:(BOOL)preservePosition;
-(void)prependViewController:(ChatItemViewController *)vc;
-(void)removeViewController:(ChatItemViewController *)vc;
-(void)screenResize;
-(void)endAllChatContentEditing;
-(void)setUnreadStartMessageID:(NSString *)messageID;
-(void)clearUnreadSeparator;

@end
