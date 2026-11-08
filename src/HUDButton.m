#import "HUDButton.h"

UIImage *HUDImage(NSString *name) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    UIImage *img = cache[name];
    if (!img) {
        NSString *path = [[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"hud"] stringByAppendingPathComponent:name];
        img = [UIImage imageWithContentsOfFile:path];
        if (img) cache[name] = img;
    }
    return img;
}

@implementation HUDButton {
    UIImageView *_ring, *_disc, *_icon;
    CGFloat _iconScale, _iconAlpha;
}

+ (HUDButton *)buttonWithIcon:(NSString *)iconFile iconScale:(CGFloat)k iconAlpha:(CGFloat)a {
    HUDButton *b = [HUDButton buttonWithType:UIButtonTypeCustom];
    b->_iconScale = k;
    b->_iconAlpha = a;
    b->_disc = [[UIImageView alloc] initWithImage:HUDImage(@"disc.png")];
    b->_disc.alpha = 0.28f;
    b->_disc.hidden = YES;
    b->_ring = [[UIImageView alloc] initWithImage:HUDImage(@"ring.png")];
    b->_icon = [[UIImageView alloc] initWithImage:iconFile ? HUDImage(iconFile) : nil];
    b->_icon.contentMode = UIViewContentModeScaleAspectFit;
    b->_icon.alpha = a;
    for (UIImageView *v in @[ b->_disc, b->_ring, b->_icon ]) { v.userInteractionEnabled = NO; [b addSubview:v]; }
    return b;
}

- (void)setIconImage:(UIImage *)iconImage { _icon.image = iconImage; }
- (UIImage *)iconImage { return _icon.image; }

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    _disc.frame = b;
    _ring.frame = b;
    CGFloat s = b.size.width * _iconScale;
    _icon.frame = CGRectMake((b.size.width - s) * 0.5f, (b.size.height - s) * 0.5f, s, s);
}

- (void)setHighlighted:(BOOL)h {
    [super setHighlighted:h];
    _disc.hidden = !h;
    _icon.alpha = h ? MIN(1.0f, _iconAlpha + 0.3f) : _iconAlpha;
}

@end
