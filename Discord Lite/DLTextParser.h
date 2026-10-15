//
//  DLTextParser.h
//  Discord Lite
//
//  Created by Collin Mistr on 11/28/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DLMessage.h"

// URL scheme of links that hide spoiler text until clicked.
extern NSString * const DLSpoilerLinkScheme;

@interface DLTextParser : NSObject

+(NSColor *)DEFAULT_TEXT_COLOR;
+(NSColor *)DEFAULT_TEXT_HIGHLIGHT_COLOR;
+(NSColor *)DEFAULT_LINK_TEXT_COLOR;
+(BOOL)isEmojiOnlyMessage:(DLMessage *)m;

+(NSAttributedString *)attributedContentStringForMessage:(DLMessage *)m;

@end
