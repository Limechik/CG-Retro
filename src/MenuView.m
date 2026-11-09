#import "MenuView.h"
#import "Outfit.h"
#import <QuartzCore/QuartzCore.h>

// Шрифт игры (07nikumaru.ttf), подключается через UIAppFonts в Info.plist. PostScript-имя: 07NikumaruFont.
static NSString *const kMenuFontName = @"07NikumaruFont";
static NSString *const kNameDefaultsKey = @"ChickenGunPlayerName";
static NSString *const kDefaultName = @"General KoKoK";

// Размеры «дизайна» (скриншот оригинала).
#define DESIGN_W 1302.0f
#define DESIGN_H 600.0f

#define COL_TITLE   [UIColor colorWithRed:0.11f green:0.14f blue:0.04f alpha:1]
#define COL_PANEL   [UIColor colorWithRed:0.85f green:0.93f blue:0.68f alpha:1]
#define COL_PRESSED [UIColor colorWithRed:0.72f green:0.85f blue:0.50f alpha:1]
#define COL_BORDER  [UIColor colorWithRed:0.71f green:0.83f blue:0.46f alpha:1]
#define COL_TEXT    [UIColor colorWithRed:0.14f green:0.17f blue:0.08f alpha:1]
#define COL_ORANGE  [UIColor colorWithRed:0.89f green:0.50f blue:0.10f alpha:1]

static UIFont *MenuFont(CGFloat size) {
    UIFont *f = [UIFont fontWithName:kMenuFontName size:size];
    return f ? f : [UIFont boldSystemFontOfSize:size];      // запасной вариант, если шрифт не подключился
}

// Мягкая тень под курицей: радиальный градиент, растягивается в эллипс размером вью.
static UIImage *ShadowImage(void) {
    const CGFloat sz = 128;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(sz, sz), NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat comps[8] = { 0.10f, 0.35f, 0.0f, 0.50f,   0.10f, 0.35f, 0.0f, 0.0f };
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, NULL, 2);
    CGPoint mid = CGPointMake(sz * 0.5f, sz * 0.5f);
    CGContextDrawRadialGradient(c, g, mid, 0, mid, sz * 0.5f, 0);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

// Кнопка меню: плоская плашка, при нажатии темнеет.
@interface MenuButton : UIButton
@end

@implementation MenuButton
- (void)setHighlighted:(BOOL)h {
    [super setHighlighted:h];
    self.backgroundColor = h ? COL_PRESSED : COL_PANEL;
}
@end

@interface MenuView () <UIAlertViewDelegate>
@end

@implementation MenuView {
    CAGradientLayer *_bg;
    UIView  *_badge;
    UILabel *_levelLabel, *_lvlCaption;
    MenuButton *_nameBtn;
    UIView  *_xpBar, *_xpFill;
    UILabel *_privacy, *_version;
    UILabel *_title1, *_title2;
    UIImageView *_shadow, *_chicken;
    NSMutableDictionary *_outfit;     // слои предметов (подвиды _chicken, дышат вместе с ней)
    MenuButton *_shopBtn, *_playBtn, *_serversBtn;
    CGSize _chickenPx;
}

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithRed:0.45f green:0.75f blue:0.03f alpha:1];
        self.multipleTouchEnabled = NO;
        self.clipsToBounds = YES;

        _bg = [CAGradientLayer layer];
        _bg.colors = @[ (id)[UIColor colorWithRed:0.69f green:0.85f blue:0.02f alpha:1].CGColor,
                        (id)[UIColor colorWithRed:0.40f green:0.72f blue:0.03f alpha:1].CGColor ];
        _bg.startPoint = CGPointMake(0.3f, 0);
        _bg.endPoint = CGPointMake(0.6f, 1);
        [self.layer addSublayer:_bg];

        _level = 1;
        _progress = 0;
        NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        _versionString = [NSString stringWithFormat:@"v %@", version ? version : @""];
        NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kNameDefaultsKey];
        _playerName = [saved length] ? [saved copy] : kDefaultName;

        // профиль
        _badge = [[UIView alloc] initWithFrame:CGRectZero];
        _badge.backgroundColor = [UIColor whiteColor];
        _badge.layer.borderColor = [UIColor colorWithRed:0.33f green:0.45f blue:0.12f alpha:1].CGColor;
        _badge.userInteractionEnabled = NO;
        [self addSubview:_badge];
        _levelLabel = [self labelWithColor:COL_ORANGE];
        _lvlCaption = [self labelWithColor:COL_ORANGE];
        _lvlCaption.text = @"lvl";
        [self addSubview:_levelLabel];
        [self addSubview:_lvlCaption];

        _nameBtn = [self panelButton];
        [_nameBtn addTarget:self action:@selector(onNameTap) forControlEvents:UIControlEventTouchUpInside];
        _nameBtn.titleLabel.adjustsFontSizeToFitWidth = YES;
        _nameBtn.titleLabel.minimumScaleFactor = 0.4f;   // длинное имя сжимается до 40% (iOS 6+)
        [self addSubview:_nameBtn];

        _xpBar = [[UIView alloc] initWithFrame:CGRectZero];
        _xpBar.backgroundColor = COL_PANEL;
        _xpBar.layer.borderColor = COL_BORDER.CGColor;
        _xpBar.userInteractionEnabled = NO;
        [self addSubview:_xpBar];
        _xpFill = [[UIView alloc] initWithFrame:CGRectZero];
        _xpFill.backgroundColor = [UIColor colorWithRed:0.45f green:0.72f blue:0.15f alpha:1];
        [_xpBar addSubview:_xpFill];

        _privacy = [self labelWithColor:[UIColor colorWithRed:0.25f green:0.32f blue:0.15f alpha:1]];
        _privacy.text = @"Privacy Policy";
        _privacy.textAlignment = NSTextAlignmentLeft;
        [self addSubview:_privacy];

        _version = [self labelWithColor:COL_TEXT];
        _version.textAlignment = NSTextAlignmentLeft;
        [self addSubview:_version];

        // заголовок в две строки
        _title1 = [self labelWithColor:COL_TITLE];
        _title1.text = @"ChickenGun";
        _title2 = [self labelWithColor:COL_TITLE];
        _title2.text = @"by lime and sqmrak :3";
        [self addSubview:_title1];
        [self addSubview:_title2];

        // курица: тень + спрайт (tools/build_menu_art.py)
        _shadow = [[UIImageView alloc] initWithImage:ShadowImage()];
        _shadow.userInteractionEnabled = NO;
        [self addSubview:_shadow];

        NSString *path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"menu/chicken.png"];
        UIImage *img = [UIImage imageWithContentsOfFile:path];
        _chickenPx = img ? img.size : CGSizeMake(324, 370);
        _chicken = [[UIImageView alloc] initWithImage:img];
        _chicken.userInteractionEnabled = NO;
        _chicken.layer.anchorPoint = CGPointMake(0.5f, 1.0f);   // «дышит» от земли, ноги не уезжают
        [self addSubview:_chicken];
        _outfit = [NSMutableDictionary dictionary];
        for (NSString *key in OutfitLayerOrder()) {
            UIImageView *ov = [[UIImageView alloc] initWithFrame:CGRectZero];
            ov.userInteractionEnabled = NO;
            [_chicken addSubview:ov];
            _outfit[key] = ov;
        }

        // кнопки
        _shopBtn    = [self panelButton];
        _playBtn    = [self panelButton];
        _serversBtn = [self panelButton];
        [_shopBtn    setTitle:@"Shop"    forState:UIControlStateNormal];
        [_playBtn    setTitle:@"Play"    forState:UIControlStateNormal];
        [_serversBtn setTitle:@"Servers" forState:UIControlStateNormal];
        [_shopBtn    addTarget:self action:@selector(onShop)    forControlEvents:UIControlEventTouchUpInside];
        [_playBtn    addTarget:self action:@selector(onPlay)    forControlEvents:UIControlEventTouchUpInside];
        [_serversBtn addTarget:self action:@selector(onServers) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_shopBtn];
        [self addSubview:_playBtn];
        [self addSubview:_serversBtn];

        [self applyContent];
        [self refreshOutfit];
    }
    return self;
}

#pragma mark - Помощники

- (UILabel *)labelWithColor:(UIColor *)color {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.backgroundColor = [UIColor clearColor];
    l.textColor = color;
    l.textAlignment = NSTextAlignmentCenter;
    l.userInteractionEnabled = NO;
    return l;
}

- (MenuButton *)panelButton {
    MenuButton *b = [MenuButton buttonWithType:UIButtonTypeCustom];
    b.backgroundColor = COL_PANEL;
    b.layer.borderColor = COL_BORDER.CGColor;
    [b setTitleColor:COL_TEXT forState:UIControlStateNormal];
    return b;
}

- (void)applyContent {
    _levelLabel.text = [NSString stringWithFormat:@"%d", _level];
    [_nameBtn setTitle:_playerName forState:UIControlStateNormal];
    _version.text = _versionString;
    float p = _progress < 0 ? 0 : (_progress > 1 ? 1 : _progress);
    _xpFill.hidden = (p <= 0);
    [self setNeedsLayout];
}

- (void)setLevel:(int)level { _level = level; [self applyContent]; }
- (void)setProgress:(float)progress { _progress = progress; [self applyContent]; }
- (void)setVersionString:(NSString *)v { _versionString = [v copy]; [self applyContent]; }
- (void)setPlayerName:(NSString *)n {
    _playerName = [n copy];
    [[NSUserDefaults standardUserDefaults] setObject:_playerName forKey:kNameDefaultsKey];
    [self applyContent];
}

#pragma mark - Вёрстка

// Масштаб дизайна на экран и три якоря по вертикали: верх (профиль), центр (заголовок, курица), низ (кнопки).
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _bg.frame = self.bounds;
    [CATransaction commit];

    CGFloat s = MIN(w / DESIGN_W, h / DESIGN_H);
    CGFloat ox = (w - DESIGN_W * s) * 0.5f;      // по центру
    CGFloat oyTop = 0;
    CGFloat oyMid = (h - DESIGN_H * s) * 0.5f;
    CGFloat oyBot = h - DESIGN_H * s;

    // Прямоугольник дизайна -> экран. ax: 0 — прижато к левому краю, иначе центрируется. ay: 0 верх, 1 центр, 2 низ.
#define R(ax, ay, x, y, dw, dh) CGRectMake(((ax) ? ox : 0) + (x) * s, ((ay) == 0 ? oyTop : ((ay) == 1 ? oyMid : oyBot)) + (y) * s, (dw) * s, (dh) * s)

    // профиль
    _badge.frame = R(0, 0, 8, 8, 74, 74);
    _badge.layer.cornerRadius = _badge.bounds.size.width * 0.5f;
    _badge.layer.borderWidth = MAX(1.0f, 3 * s);
    _levelLabel.font = MenuFont(MAX(30 * s, 14));
    _levelLabel.frame = R(0, 0, 8, 20, 74, 36);
    _lvlCaption.font = MenuFont(MAX(17 * s, 8));
    _lvlCaption.frame = R(0, 0, 8, 56, 74, 22);

    _nameBtn.frame = R(0, 0, 90, 22, 235, 36);
    _nameBtn.titleLabel.font = [UIFont systemFontOfSize:MAX(21 * s, 11)];   // как в оригинале: имя, Privacy и версия — обычным шрифтом
    _nameBtn.layer.borderWidth = MAX(1.0f, 2 * s);
    _nameBtn.layer.cornerRadius = 5 * s;

    _xpBar.frame = R(0, 0, 90, 64, 235, 15);
    _xpBar.layer.borderWidth = MAX(1.0f, 2 * s);
    _xpBar.layer.cornerRadius = 4 * s;
    CGFloat p = _progress < 0 ? 0 : (_progress > 1 ? 1 : _progress);
    _xpFill.frame = CGRectMake(0, 0, _xpBar.bounds.size.width * p, _xpBar.bounds.size.height);

    _privacy.font = [UIFont systemFontOfSize:MAX(17 * s, 9)];
    _privacy.frame = R(0, 0, 10, 102, 220, 24);

    // заголовок
    _title1.font = MenuFont(MAX(50 * s, 22));
    _title2.font = MenuFont(MAX(30 * s, 14));
    _title2.adjustsFontSizeToFitWidth = YES;
    _title1.frame = R(1, 0, 600, 24, 500, 48);
    _title2.frame = R(1, 0, 600, 80, 500, 48);

    // курица: занимает место между заголовком и кнопками. На iPhone 5 (16:9) и iPad (4:3) экран выше, чем дизайн 1302x600
    // (Hd — высота экрана в дизайн-единицах), поэтому курица растёт вместе со свободным местом, но не больше 1.6x.
    CGFloat Hd = h / s;
    CGFloat gapTop = 135, gapBot = Hd - 103 - 14;             // 103 — высота низа дизайна под верхом кнопок
    CGFloat avail = gapBot - gapTop;
    CGFloat chD = MIN(avail * 0.85f, 300 * 1.6f);             // высота курицы, дизайн-единицы
    CGFloat chTop = gapTop + (avail - chD) * 0.45f;
    CGFloat cwD = chD * (_chickenPx.width / _chickenPx.height);
    _chicken.frame = CGRectMake(ox + (660 - cwD * 0.5f) * s, chTop * s, cwD * s, chD * s);   // с anchorPoint (0.5,1) frame считается корректно
    // слои предметов: рамка спрайта, но выше на запас сверху (шапки)
    CGFloat ok = (chD * s) / _chickenPx.height;
    for (NSString *key in _outfit) {
        UIImageView *ov = _outfit[key];
        UIImage *oi = ov.image;
        ov.frame = oi ? CGRectMake(0, -(oi.size.height - _chickenPx.height) * ok, oi.size.width * ok, oi.size.height * ok) : CGRectZero;
    }
    CGFloat kk = chD / 300;
    _shadow.frame = CGRectMake(ox + (655 - 125 * kk) * s, (chTop + chD + 15 - 20 * kk) * s, 250 * kk * s, 40 * kk * s);

    // кнопки
    CGFloat bf = MAX(36 * s, 15);
    _shopBtn.frame    = R(1, 2, 191, 497, 303, 89);
    _playBtn.frame    = R(1, 2, 499, 497, 303, 89);
    _serversBtn.frame = R(1, 2, 807, 497, 303, 89);
    for (MenuButton *b in @[ _shopBtn, _playBtn, _serversBtn ]) {
        b.titleLabel.font = MenuFont(bf);
        b.layer.borderWidth = MAX(1.0f, 2 * s);
        b.layer.cornerRadius = 4 * s;
    }

    _version.font = [UIFont systemFontOfSize:MAX(20 * s, 10)];
    _version.frame = R(0, 2, 22, 560, 160, 30);
#undef R
}

- (void)refreshOutfit {
    for (NSString *key in OutfitLayerOrder()) ((UIImageView *)_outfit[key]).image = OutfitLayerImage(YES, key, OutfitSelectedID(key), nil);
    [self setNeedsLayout];
}

#pragma mark - Анимация

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self startAnimations];
}

- (void)startAnimations {
    [_chicken.layer removeAnimationForKey:@"breathY"];
    [_chicken.layer removeAnimationForKey:@"breathX"];
    CAMediaTimingFunction *ease = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

    CABasicAnimation *y = [CABasicAnimation animationWithKeyPath:@"transform.scale.y"];
    y.fromValue = @1.0f; y.toValue = @1.03f;
    y.duration = 1.1; y.autoreverses = YES; y.repeatCount = HUGE_VALF; y.timingFunction = ease;
    [_chicken.layer addAnimation:y forKey:@"breathY"];

    CABasicAnimation *x = [CABasicAnimation animationWithKeyPath:@"transform.scale.x"];
    x.fromValue = @1.0f; x.toValue = @0.99f;
    x.duration = 1.1; x.autoreverses = YES; x.repeatCount = HUGE_VALF; x.timingFunction = ease;
    [_chicken.layer addAnimation:x forKey:@"breathX"];
}

#pragma mark - Кнопки

- (void)onPlay {
    id<MenuViewDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(menuViewDidPressPlay:)]) [d menuViewDidPressPlay:self];
}

- (void)onShop {
    id<MenuViewDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(menuViewDidPressShop:)]) [d menuViewDidPressShop:self];
    else NSLog(@"[Menu] shop delegate unavailable");
}

- (void)onServers {
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Servers"
                                                message:@"Online multiplayer is not available. Choose Play to play with bots."
                                               delegate:nil
                                      cancelButtonTitle:@"OK"
                                      otherButtonTitles:nil];
    [a show];
}

- (void)onNameTap {
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Player name"
                                                message:nil
                                               delegate:self
                                      cancelButtonTitle:@"Cancel"
                                      otherButtonTitles:@"OK", nil];
    a.alertViewStyle = UIAlertViewStylePlainTextInput;
    a.tag = 1;
    [a textFieldAtIndex:0].text = _playerName;
    [a show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag != 1 || buttonIndex != 1) return;
    NSString *t = [[alertView textFieldAtIndex:0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([t length] > 16) t = [t substringToIndex:16];
    if ([t length]) self.playerName = t;
}

@end
