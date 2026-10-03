//
//  MLMarqueeLabel.h
//
//
//  Created by JH on 2024/9/1.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(MarqueeLabel)
@interface MLMarqueeLabel : NSView

@property (nonatomic, readonly) NSFont *font;
@property (nonatomic, readonly) BOOL needGradientMask;
@property (nonatomic, readonly) NSString *stringValue;


- (void)setFont:(NSFont *)font needGradientMask:(BOOL)needGradientMask;
- (void)setStringValue:(NSString *)stringValue lineDisplayTime:(NSTimeInterval)lineDisplayTime;

@end

NS_ASSUME_NONNULL_END
