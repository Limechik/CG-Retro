#import "PauseView.h"
#import <QuartzCore/QuartzCore.h>

@interface CGPauseButton : UIButton
@end

@implementation CGPauseButton
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted ? [UIColor colorWithRed:0.72f green:0.85f blue:0.50f alpha:1] : [UIColor colorWithRed:0.85f green:0.93f blue:0.68f alpha:1];
}
@end

@implementation PauseView {
    UIView *_panel;
    UILabel *_title;
    CGPauseButton *_resume, *_sound, *_leave;
    BOOL _muted;
}

- (CGPauseButton *)button:(NSString *)title action:(SEL)action {
    CGPauseButton *button = [CGPauseButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = [UIColor colorWithRed:0.85f green:0.93f blue:0.68f alpha:1];
    button.layer.borderColor = [UIColor colorWithRed:0.71f green:0.83f blue:0.46f alpha:1].CGColor;
    button.layer.borderWidth = 1;
    button.layer.cornerRadius = 4;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithRed:0.14f green:0.17f blue:0.08f alpha:1] forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:button];
    return button;
}

- (id)initWithFrame:(CGRect)frame muted:(BOOL)muted {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.58f];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _muted = muted;
        _panel = [[UIView alloc] initWithFrame:CGRectZero];
        _panel.backgroundColor = [UIColor colorWithRed:0.40f green:0.72f blue:0.03f alpha:0.98f];
        _panel.layer.cornerRadius = 7;
        _panel.layer.borderWidth = 2;
        _panel.layer.borderColor = [UIColor colorWithRed:0.71f green:0.83f blue:0.46f alpha:1].CGColor;
        [self addSubview:_panel];
        _title = [[UILabel alloc] initWithFrame:CGRectZero];
        _title.backgroundColor = [UIColor clearColor];
        _title.textAlignment = NSTextAlignmentCenter;
        _title.textColor = [UIColor colorWithRed:0.11f green:0.14f blue:0.04f alpha:1];
        _title.text = @"Pause";
        [_panel addSubview:_title];
        _resume = [self button:@"Resume" action:@selector(onResume)];
        _sound = [self button:@"" action:@selector(onSound)];
        _leave = [self button:@"Main menu" action:@selector(onLeave)];
        [self updateSound];
    }
    return self;
}

- (void)updateSound { [_sound setTitle:(_muted ? @"Sound: off" : @"Sound: on") forState:UIControlStateNormal]; }
- (void)onResume { [self.delegate pauseViewDidResume:self]; }
- (void)onLeave { [self.delegate pauseViewDidLeave:self]; }
- (void)onSound {
    _muted = !_muted;
    [self updateSound];
    [self.delegate pauseView:self setMuted:_muted];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = MIN(300, self.bounds.size.width - 24);
    CGFloat height = MIN(250, self.bounds.size.height - 20);
    if (width < 1 || height < 1) return;
    _panel.frame = CGRectMake((self.bounds.size.width - width) * 0.5f, (self.bounds.size.height - height) * 0.5f, width, height);
    CGFloat gap = height * 0.045f;
    CGFloat buttonHeight = height * 0.18f;
    _title.frame = CGRectMake(0, gap, width, height * 0.27f);
    UIFont *font = [UIFont fontWithName:@"07NikumaruFont" size:MAX(14, height * 0.10f)];
    if (!font) font = [UIFont boldSystemFontOfSize:MAX(14, height * 0.10f)];
    _title.font = font;
    NSArray *buttons = @[ _resume, _sound, _leave ];
    for (NSUInteger i = 0; i < [buttons count]; i++) {
        CGPauseButton *button = buttons[i];
        button.frame = CGRectMake(width * 0.1f, height * 0.30f + i * (buttonHeight + gap), width * 0.8f, buttonHeight);
        button.titleLabel.font = font;
    }
}
@end
