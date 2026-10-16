//
//  PaddedTextView.h
//  Discord Lite
//
//  Created by Collin Mistr on 11/2/21.
//  Copyright (c) 2021 dosdude1. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface PaddedTextView : NSTextView {
    NSString *placeholderString;
    NSAttributedString *placeholderDisplay;
    NSFont *placeholderDisplayFont;
}

// Drawn in the secondary text color while the view is empty.
-(void)setPlaceholderString:(NSString *)placeholder;

// Redraws the placeholder with the current theme colors.
-(void)refreshPlaceholderColors;
@end
