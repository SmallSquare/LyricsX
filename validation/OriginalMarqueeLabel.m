//
//  MLMarqueeLabel.m
//
//
//  Created by JH on 2024/9/1.
//

#import "MLMarqueeLabel.h"
#import <QuartzCore/QuartzCore.h>

@interface MLMarqueeLabel () {
    NSTextField *_textField;
    NSTimer *_animationTimer;
    CAGradientLayer *_layer;
    CGFloat _lineDisplayTime;
    NSString *_maskString;
    CGFloat _maskWidth;
}
- (void)animateTextFieldWithBeginStayDuration:(NSTimeInterval)beginStayDuration animateDuration:(NSTimeInterval)animateDuration endStayDuration:(NSTimeInterval)endStayDuration repeat:(BOOL)repeat;
- (void)animateTextFieldWithDelay:(NSTimeInterval)delay animationDuration:(NSTimeInterval)animationDuration completionHandler:(void(^ _Nullable)(void))completionHandler;
- (void)animateTextFieldWithInfo:(NSDictionary *)info;
- (void)calMaskWidth;
- (void)cancelPreviousAnimation;
- (BOOL)layoutTextField;
- (void)reAnimateTextField:(NSDictionary *)userInfo;
- (void)setMaskIfNeeded;
@end

@implementation MLMarqueeLabel

- (instancetype)initWithFrame:(NSRect)frameRect {
    if (self = [super initWithFrame:frameRect]) {
        self.wantsLayer = YES;
        _textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, frameRect.size.width, frameRect.size.height)];
        _textField.bordered = NO;
        _textField.editable = NO;
        _textField.selectable = NO;
        _textField.alignment = NSTextAlignmentLeft;
        _textField.cell.lineBreakMode = NSLineBreakByTruncatingTail;
        _textField.font = [NSFont systemFontOfSize:14];
        _textField.backgroundColor = NSColor.clearColor;
        _textField.textColor = NSColor.labelColor;
        self.layer.masksToBounds = YES;
        [self addSubview:_textField];
    }
    return self;
}

- (void)setFrameSize:(CGSize)frameSize {
    if (!NSEqualSizes(frameSize, self.frame.size)) {
        [super setFrameSize:frameSize];
        [self setMaskIfNeeded];
        [self setStringValue:_stringValue lineDisplayTime:_lineDisplayTime];
    }
}

- (NSFont *)font {
    return _textField.font;
}

- (void)setFont:(NSFont *)font needGradientMask:(BOOL)needGradientMask {
    _textField.font = font;
    _needGradientMask = needGradientMask;
    if (needGradientMask) {
        _layer = [CAGradientLayer layer];
        _layer.colors = @[
            (__bridge id)NSColor.clearColor.CGColor,
            (__bridge id)NSColor.whiteColor.CGColor,
            (__bridge id)NSColor.whiteColor.CGColor,
            (__bridge id)NSColor.clearColor.CGColor,
        ];
        _layer.startPoint = CGPointMake(0.0, 0.5);
        _layer.endPoint = CGPointMake(1.0, 0.5);
        self.layer.mask = _layer;
        [self calMaskWidth];
        [self setMaskIfNeeded];
    } else {
        self.layer.mask = nil;
    }
    [self setStringValue:_stringValue lineDisplayTime:_lineDisplayTime];
}

- (void)setStringValue:(NSString *)stringValue lineDisplayTime:(NSTimeInterval)lineDisplayTime {
    if (stringValue.length) {
        _stringValue = stringValue;
        _lineDisplayTime = lineDisplayTime;
        if (_needGradientMask) {
            _textField.stringValue = [NSString stringWithFormat:@"%@%@%@", _maskString, _stringValue, _maskString];
        } else {
            _textField.stringValue = _stringValue;
        }
        [_textField sizeToFit];
        [self cancelPreviousAnimation];
        if ([self layoutTextField]) {
            if (_lineDisplayTime <= 0.0) {
                _lineDisplayTime = 5.0;
            }
            CGFloat textFieldWidth = _textField.frame.size.width;
            CGFloat width = CGRectGetWidth(self.frame);
            [self animateTextFieldWithBeginStayDuration:(_lineDisplayTime - _lineDisplayTime * ((textFieldWidth - width) / textFieldWidth)) * 0.5
                                        animateDuration:_lineDisplayTime * ((textFieldWidth - width) / textFieldWidth)
                                        endStayDuration:(_lineDisplayTime - _lineDisplayTime * ((textFieldWidth - width) / textFieldWidth)) * 0.5 repeat:NO];
        }
    }
}

- (void)calMaskWidth {
    _maskString = @" ";
    NSString *stringValue = _textField.stringValue;
    _textField.stringValue = _maskString;
    [_textField sizeToFit];
    _maskWidth = _textField.frame.size.width;
    if (_maskWidth <= 30.0) {
        for (NSInteger i = 1;; i++) {
            _maskString = [NSString stringWithFormat:@"%@ ", _maskString];
            _textField.stringValue = _maskString;
            [_textField sizeToFit];
            CGFloat maskWidth = _maskWidth;
            CGFloat textFieldWidth = _textField.frame.size.width;
            if (maskWidth <= 30.0) {
                _maskWidth = _textField.frame.size.width;
                if (textFieldWidth > 30.0 || i >= 10) {
                    break;
                }
            } else {
                _maskWidth = textFieldWidth;
                if (i > 9) {
                    break;
                }
            }
        }
    }
    _textField.stringValue = stringValue;
    [_textField sizeToFit];
}

- (void)setMaskIfNeeded {
    if (_needGradientMask) {
        if (self.frame.size.width > 0.0) {
            _layer.frame = CGRectMake(0.0, 0.0, self.frame.size.width, self.frame.size.height);
            CGFloat location = floor(_maskWidth / self.frame.size.width * 100.0) / 100.0;
            _layer.locations = @[@(0), @(location), @(1.0 - location), @(1)];
        }
    }
}

- (BOOL)layoutTextField {
    CGSize textFieldSize = _textField.frame.size;
    CGRect frame = self.frame;
    CGFloat y = ceil((CGRectGetHeight(frame) - textFieldSize.height) * 0.5);
    CGFloat width = CGRectGetWidth(frame);
    CGFloat x = 0.0;
    if (textFieldSize.width <= width) {
        x = round((CGRectGetWidth(frame) - textFieldSize.width) * 0.5);
    }
    _textField.frame = CGRectMake(x, y, textFieldSize.width, textFieldSize.height);
    if (_needGradientMask) {
        _layer.frame = self.bounds;
        CGFloat location = floor(_maskWidth / frame.size.width * 100.0) / 100.0;
        _layer.locations = @[@(0), @(location), @(1.0 - location), @(1)];
    }
    return textFieldSize.width > frame.size.width;
}

- (void)animateTextFieldWithBeginStayDuration:(NSTimeInterval)beginStayDuration animateDuration:(NSTimeInterval)animateDuration endStayDuration:(NSTimeInterval)endStayDuration repeat:(BOOL)repeat {
    [_animationTimer invalidate];
    _animationTimer = nil;
    if (repeat) {
        NSDictionary *userInfo = @{
            @"delay": @(beginStayDuration),
            @"duration": @(animateDuration),
        };
        _animationTimer = [NSTimer scheduledTimerWithTimeInterval:beginStayDuration + animateDuration + endStayDuration target:self selector:@selector(reAnimateTextField:) userInfo:userInfo repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:_animationTimer forMode:NSRunLoopCommonModes];
        [_animationTimer fire];
    }
    [self animateTextFieldWithDelay:beginStayDuration animationDuration:animateDuration completionHandler:nil];
}

- (void)cancelPreviousAnimation {
    [_animationTimer invalidate];
    _animationTimer = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)reAnimateTextField:(NSDictionary *)userInfo {
    CGFloat delay = [userInfo[@"delay"] doubleValue];
    CGFloat duration = [userInfo[@"duration"] doubleValue];
    [self animateTextFieldWithDelay:delay animationDuration:duration completionHandler:nil];
}

- (void)animateTextFieldWithDelay:(NSTimeInterval)delay animationDuration:(NSTimeInterval)animationDuration completionHandler:(void (^)(void))completionHandler {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    NSDictionary *info = nil;
    if (completionHandler) {
        info = @{
            @"animationDuration": @(animationDuration),
            @"completionHandler": [completionHandler copy],
        };
    } else {
        info = @{
            @"animationDuration": @(animationDuration),
        };
    }
    [self performSelector:@selector(animateTextFieldWithInfo:) withObject:info afterDelay:delay];
}

- (void)animateTextFieldWithInfo:(NSDictionary *)info {
    CGRect textFieldFrame = _textField.frame;
    CGRect frame = self.frame;
    CGFloat animationDuration = [info[@"animationDuration"] doubleValue];
    void (^completionHandler)(void) = info[@"completionHandler"];
    __weak typeof(_textField) weakTextField = _textField;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        context.duration = animationDuration;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        CGFloat x = CGRectGetWidth(frame) - CGRectGetWidth(textFieldFrame);
        CGFloat y = CGRectGetMinY(textFieldFrame);
        CGFloat width = CGRectGetWidth(textFieldFrame);
        CGFloat height = CGRectGetHeight(textFieldFrame);
        weakTextField.animator.frame = CGRectMake(x, y, width, height);
    } completionHandler:completionHandler];
}


@end
