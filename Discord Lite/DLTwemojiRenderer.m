#import "DLTwemojiRenderer.h"

static NSDictionary *DLTwemojiExactNames = nil;
static NSDictionary *DLTwemojiNormalizedNames = nil;
static NSSet *DLTwemojiKeyPrefixes = nil;
static NSCache *DLTwemojiImageCache = nil;
static NSArray *DLTwemojiCatalog = nil;
static NSDictionary *DLTwemojiDisplayNames = nil;

static NSUInteger DLNextUnicodeScalar(NSString *text, NSUInteger index, unsigned int *scalar) {
    unichar first = [text characterAtIndex:index];
    if (first >= 0xd800 && first <= 0xdbff && index + 1 < [text length]) {
        unichar second = [text characterAtIndex:index + 1];
        if (second >= 0xdc00 && second <= 0xdfff) {
            *scalar = 0x10000 + ((first - 0xd800) << 10) + (second - 0xdc00);
            return index + 2;
        }
    }
    *scalar = first;
    return index + 1;
}

static void DLAppendScalarToKeys(NSMutableString *exact, NSMutableString *normalized, unsigned int scalar) {
    NSString *component = [NSString stringWithFormat:@"%x", scalar];
    if ([exact length]) [exact appendString:@"-"];
    [exact appendString:component];
    if (scalar != 0xfe0e && scalar != 0xfe0f) {
        if ([normalized length]) [normalized appendString:@"-"];
        [normalized appendString:component];
    }
}

@implementation DLTwemojiRenderer

+ (void)loadAssetIndex {
    if (DLTwemojiExactNames) return;
    @synchronized(self) {
        if (DLTwemojiExactNames) return;
        NSString *directory = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Twemoji72"];
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL];
        NSMutableDictionary *exact = [NSMutableDictionary dictionary];
        NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
        NSMutableSet *prefixes = [NSMutableSet set];
        for (NSString *file in files) {
            if (![file hasSuffix:@".png"]) continue;
            NSString *name = [file substringToIndex:[file length] - 4];
            [exact setObject:name forKey:name];
            NSArray *components = [name componentsSeparatedByString:@"-"];
            NSMutableArray *withoutVariation = [NSMutableArray arrayWithCapacity:[components count]];
            for (NSString *component in components) {
                if (![component isEqualToString:@"fe0e"] && ![component isEqualToString:@"fe0f"]) {
                    [withoutVariation addObject:component];
                }
            }
            NSString *key = [withoutVariation componentsJoinedByString:@"-"];
            if (![normalized objectForKey:key]) [normalized setObject:name forKey:key];
            for (NSString *sequence in [NSArray arrayWithObjects:name, key, nil]) {
                NSArray *parts = [sequence componentsSeparatedByString:@"-"];
                NSMutableString *prefix = [NSMutableString string];
                for (NSString *part in parts) {
                    if ([prefix length]) [prefix appendString:@"-"];
                    [prefix appendString:part];
                    [prefixes addObject:[[prefix copy] autorelease]];
                }
            }
        }
        DLTwemojiExactNames = [exact copy];
        DLTwemojiNormalizedNames = [normalized copy];
        DLTwemojiKeyPrefixes = [prefixes copy];
        DLTwemojiImageCache = [[NSCache alloc] init];
        [DLTwemojiImageCache setCountLimit:512];
    }
}

+ (NSString *)assetNameForExactKey:(NSString *)exact normalizedKey:(NSString *)normalized {
    [self loadAssetIndex];
    NSString *name = [DLTwemojiExactNames objectForKey:exact];
    return name ? name : [DLTwemojiNormalizedNames objectForKey:normalized];
}

+ (NSImage *)imageForAssetName:(NSString *)name size:(CGFloat)size {
    if (!name) return nil;
    NSString *cacheKey = [NSString stringWithFormat:@"%@-%.2f", name, size];
    NSImage *image = [DLTwemojiImageCache objectForKey:cacheKey];
    if (image) return image;
    NSString *path = [[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Twemoji72"]
                      stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
    image = [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
    if (image) {
        [image setSize:NSMakeSize(size, size)];
        [DLTwemojiImageCache setObject:image forKey:cacheKey];
    }
    return image;
}

+ (NSImage *)imageForEmoji:(NSString *)emoji size:(CGFloat)size {
    if (![emoji length]) return nil;
    NSMutableString *exact = [NSMutableString string];
    NSMutableString *normalized = [NSMutableString string];
    NSUInteger index = 0;
    while (index < [emoji length]) {
        unsigned int scalar = 0;
        index = DLNextUnicodeScalar(emoji, index, &scalar);
        DLAppendScalarToKeys(exact, normalized, scalar);
    }
    return [self imageForAssetName:[self assetNameForExactKey:exact normalizedKey:normalized] size:size];
}

+ (NSArray *)standardEmojiItems {
    if (DLTwemojiCatalog) return DLTwemojiCatalog;
    @synchronized(self) {
        if (DLTwemojiCatalog) return DLTwemojiCatalog;
        NSString *path = [[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Twemoji72"]
                          stringByAppendingPathComponent:@"standard-emoji.tsv"];
        NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        NSMutableArray *catalog = [NSMutableArray array];
        NSMutableDictionary *names = [NSMutableDictionary dictionary];
        for (NSString *line in [contents componentsSeparatedByString:@"\n"]) {
            if (![line length] || [line hasPrefix:@"# "]) continue;
            NSRange separator = [line rangeOfString:@"\t"];
            if (separator.location == NSNotFound) continue;
            NSString *emoji = [line substringToIndex:separator.location];
            NSString *name = [line substringFromIndex:NSMaxRange(separator)];
            [catalog addObject:[NSDictionary dictionaryWithObjectsAndKeys:emoji, @"name", name, @"search", nil]];
            [names setObject:name forKey:emoji];
        }
        DLTwemojiCatalog = [catalog copy];
        DLTwemojiDisplayNames = [names copy];
    }
    return DLTwemojiCatalog;
}

+ (NSString *)displayNameForEmoji:(NSString *)emoji {
    [self standardEmojiItems];
    NSString *name = [DLTwemojiDisplayNames objectForKey:emoji];
    return name ? name : @"emoji";
}

+ (void)setText:(NSString *)text forLabel:(NSTextField *)label {
    NSMutableParagraphStyle *paragraph = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [paragraph setAlignment:[label alignment]];
    [paragraph setLineBreakMode:NSLineBreakByTruncatingTail];
    NSFont *font = [label font] ? [label font] : [NSFont systemFontOfSize:[NSFont systemFontSize]];
    NSMutableAttributedString *display = [[[NSMutableAttributedString alloc]
        initWithString:(text ? text : @"") attributes:[NSDictionary dictionaryWithObjectsAndKeys:
            font, NSFontAttributeName, ([label textColor] ? [label textColor] : [NSColor textColor]),
            NSForegroundColorAttributeName, paragraph, NSParagraphStyleAttributeName, nil]] autorelease];
    [self replaceEmojiInAttributedString:display size:[font pointSize]
                     excludingAttribute:nil recordingAttribute:nil cursorLocation:NULL];
    [label setAttributedStringValue:display];
}

+ (NSUInteger)replaceEmojiInAttributedString:(NSMutableAttributedString *)text
                                       size:(CGFloat)size
                         excludingAttribute:(NSString *)attributeName
                        recordingAttribute:(NSString *)recordingAttribute
                             cursorLocation:(NSUInteger *)cursorLocation {
    if (![text length]) return 0;
    [self loadAssetIndex];
    NSString *source = [[text string] copy];
    NSMutableArray *matches = [NSMutableArray array];
    NSUInteger index = 0;
    while (index < [source length]) {
        if (attributeName && [text attribute:attributeName atIndex:index effectiveRange:NULL]) {
            unsigned int ignored = 0;
            index = DLNextUnicodeScalar(source, index, &ignored);
            continue;
        }
        NSMutableString *exact = [NSMutableString string];
        NSMutableString *normalized = [NSMutableString string];
        NSUInteger probe = index;
        NSUInteger matchEnd = index;
        NSString *matchName = nil;
        for (NSUInteger count = 0; count < 16 && probe < [source length]; count++) {
            unsigned int scalar = 0;
            probe = DLNextUnicodeScalar(source, probe, &scalar);
            DLAppendScalarToKeys(exact, normalized, scalar);
            NSString *candidate = [self assetNameForExactKey:exact normalizedKey:normalized];
            if (candidate) {
                matchEnd = probe;
                matchName = candidate;
            }
            if (![DLTwemojiKeyPrefixes containsObject:exact] &&
                ![DLTwemojiKeyPrefixes containsObject:normalized]) break;
        }
        if (matchName) {
            [matches addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                [NSValue valueWithRange:NSMakeRange(index, matchEnd - index)], @"range",
                                matchName, @"name", nil]];
            index = matchEnd;
        } else {
            unsigned int ignored = 0;
            index = DLNextUnicodeScalar(source, index, &ignored);
        }
    }
    if (cursorLocation) {
        NSUInteger originalCursor = *cursorLocation;
        NSUInteger removedLength = 0;
        BOOL insideMatch = NO;
        for (NSDictionary *match in matches) {
            NSRange range = [[match objectForKey:@"range"] rangeValue];
            if (NSMaxRange(range) <= originalCursor) {
                removedLength += range.length - 1;
            } else if (range.location < originalCursor) {
                *cursorLocation = range.location - removedLength + 1;
                insideMatch = YES;
                break;
            } else {
                break;
            }
        }
        if (!insideMatch) *cursorLocation = originalCursor - removedLength;
    }
    NSUInteger replaced = 0;
    for (NSInteger matchIndex = (NSInteger)[matches count] - 1; matchIndex >= 0; matchIndex--) {
        NSDictionary *match = [matches objectAtIndex:matchIndex];
        NSImage *image = [self imageForAssetName:[match objectForKey:@"name"] size:size];
        if (!image) continue;
        NSTextAttachmentCell *cell = [[[NSTextAttachmentCell alloc] initImageCell:image] autorelease];
        NSTextAttachment *attachment = [[[NSTextAttachment alloc] init] autorelease];
        [attachment setAttachmentCell:cell];
        NSRange range = [[match objectForKey:@"range"] rangeValue];
        NSMutableAttributedString *replacement = [[[NSMutableAttributedString alloc]
            initWithAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]] autorelease];
        [replacement addAttributes:[text attributesAtIndex:range.location effectiveRange:NULL]
                             range:NSMakeRange(0, [replacement length])];
        if (recordingAttribute) {
            [replacement addAttribute:recordingAttribute value:[source substringWithRange:range]
                               range:NSMakeRange(0, [replacement length])];
        }
        [text replaceCharactersInRange:range withAttributedString:replacement];
        replaced++;
    }
    [source release];
    return replaced;
}

@end
