//
//  ChannelItemViewController.m
//  Discord Lite
//
//  Created by Collin Mistr on 11/1/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import "ChannelItemViewController.h"
#import "DLUtil.h"

@implementation ChannelItemViewController

-(void)awakeFromNib {
    defaultTextColor = [[DLUtil nativeSecondaryTextColor] retain];
    [childChannelLabel setTextColor:defaultTextColor];
    [parentChannelLabel setTextColor:[DLUtil nativeSecondaryTextColor]];
    [statusIndicatorView setIndicatorColor:[DLUtil nativePrimaryTextColor]];
    [view setDelegate:self];
    [dmView setDelegate:self];
    isSelected = NO;
    [view setNeedsDisplay:YES];
}

-(DLChannel *)representedObject {
    return representedObject;
}

-(void)setRepresentedObject:(DLChannel *)c {
    [representedObject release];
    [c retain];
    representedObject = c;
    [representedObject setDelegate:self];
    if ([representedObject type] == ChannelTypeHeader) {
        [self setType:ChannelItemViewTypeParent];
        [parentChannelLabel setStringValue:[(DLServerChannel *)representedObject name]];
    } else {
        [childChannelLabel setStringValue:[(DLServerChannel *)representedObject name]];
    }
    [self updateMentionsLabel];
    [self updateUnreadStatus];
    [view setNeedsDisplay:YES];
}

-(void)setType:(ChannelItemViewType)t {
    switch (t) {
        case ChannelItemViewTypeParent:
            view = headerView;
            break;
        case ChannelItemViewTypeDM:
            view = dmView;
            break;
        default:
            break;
    }
    type = t;
}
-(void)setDelegate:(id<ChannelItemDelegate>)inDelegate {
    delegate = inDelegate;
}
-(void)updateUnreadStatus {
    if ([representedObject hasUnreadMessages]) {
        [childChannelLabel setTextColor:[DLUtil nativePrimaryTextColor]];
        [statusIndicatorView setDrawnIndicator:ServerStatusIndicatorUnread];
    } else {
        if (!isSelected) {
            [childChannelLabel setTextColor:defaultTextColor];
        }
        [statusIndicatorView setDrawnIndicator:ServerStatusIndicatorNone];
    }
    [statusIndicatorView setNeedsDisplay:YES];
}
-(void)mouseWasDepressedWithEvent:(NSEvent *)event {
    [delegate channelItemWasSelected:self];
    [self setSelected:YES];
}
-(void)setSelected:(BOOL)selected {
    isSelected = selected;
    if (selected) {
        [view setBackgroundColor:[DLUtil nativeSelectionColor]];
        [childChannelLabel setTextColor:[DLUtil nativeSelectedTextColor]];
        [statusIndicatorView setIndicatorColor:[DLUtil nativeSelectedTextColor]];
        [view setNeedsDisplay:YES];
    } else {
        [view setBackgroundColor:[NSColor clearColor]];
        [statusIndicatorView setIndicatorColor:[DLUtil nativePrimaryTextColor]];
        [self updateUnreadStatus];
        [view setNeedsDisplay:YES];
    }
}
-(void)updateMentionsLabel {
    NSInteger mentionCount = [representedObject mentionCount];
    if (mentionCount < 1) {
        [mentionBadgeLabel setHidden:YES];
    } else {
        [mentionBadgeLabel setHidden:NO];
        [mentionBadgeLabel setStringValue:[NSString stringWithFormat:@"%ld", mentionCount]];
    }
}

-(void)dealloc {
    [representedObject setDelegate:nil];
    [representedObject release];
    [view setDelegate:nil];
    [view release];
    [dmView setDelegate:nil];
    [dmView release];
    [super dealloc];
}


#pragma mark Delegated Functions 

-(void)mentionsUpdatedForChannel:(DLChannel *)c {
    [self updateMentionsLabel];
}
-(void)unreadStatusUpdatedForChannel:(DLChannel *)c {
    [self updateUnreadStatus];
}

@end
