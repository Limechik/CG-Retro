#import "NewGameView.h"
#import <QuartzCore/QuartzCore.h>

static NSString *const kModeKey = @"ChickenGunGameMode";
static NSString *const kLastMapKey = @"ChickenGunLastMap";

#define DESIGN_W 1170.0f
#define DESIGN_H 500.0f
#define HEADER_H 62.0f           // высота шапки (кнопка «Назад» и заголовок)
#define REGION_A 170.0f          // блок режимов: подпись + карточки (дизайн-единицы)
#define REGION_B 268.0f          // блок карт: подпись + ряд

#define COL_TEXT    [UIColor colorWithRed:0.13f green:0.15f blue:0.09f alpha:1]
#define COL_CARD    [UIColor colorWithRed:0.94f green:0.97f blue:0.88f alpha:0.82f]
#define COL_CARD_HI [UIColor colorWithRed:0.82f green:0.91f blue:0.66f alpha:0.95f]
#define COL_SEL     [UIColor colorWithRed:0.76f green:0.90f blue:0.50f alpha:0.98f]
#define COL_BORDER  [UIColor colorWithRed:0.80f green:0.88f blue:0.66f alpha:1]
#define COL_SELB    [UIColor colorWithRed:0.30f green:0.52f blue:0.10f alpha:1]

static UIImage *NGImage(NSString *dir, NSString *name) {
    NSString *path = [[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:dir] stringByAppendingPathComponent:name];
    return [UIImage imageWithContentsOfFile:path];
}

// ---- карточка режима ----
@interface NGModeCard : UIButton
@property (nonatomic, strong) NSArray *icons;       // UIImageView
@property (nonatomic, strong) UILabel *caption;
@end
@implementation NGModeCard
- (void)refresh {
    BOOL on = self.selected;
    self.backgroundColor = self.highlighted ? COL_CARD_HI : (on ? COL_SEL : COL_CARD);
    self.layer.borderColor = (on ? COL_SELB : COL_BORDER).CGColor;
}
- (void)setSelected:(BOOL)s { [super setSelected:s]; [self refresh]; }
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; [self refresh]; }
@end

// ---- карточка карты ----
@interface NGMapCard : UIButton
@property (nonatomic, copy) NSString *file;
@property (nonatomic, strong) UIImageView *thumb, *dot;
@property (nonatomic, strong) UILabel *caption;
@end
@implementation NGMapCard
- (void)setHighlighted:(BOOL)h {
    [super setHighlighted:h];
    self.backgroundColor = h ? COL_CARD_HI : COL_CARD;
}
@end

@implementation NewGameView {
    CAGradientLayer *_bg;
    UIButton *_back;
    UIImageView *_chevron;
    UILabel *_title, *_modeCaption, *_mapCaption, *_empty;
    NGModeCard *_modes[2];
    UIScrollView *_scroll;
    NSMutableArray *_cards;
    int _mode;
}

+ (int)savedMode {
    int m = (int)[[NSUserDefaults standardUserDefaults] integerForKey:kModeKey];
    return (m == 1) ? 1 : 0;
}

- (UILabel *)label:(NSString *)text {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.backgroundColor = [UIColor clearColor];
    l.textColor = COL_TEXT;
    l.textAlignment = NSTextAlignmentCenter;
    l.text = text;
    l.userInteractionEnabled = NO;
    return l;
}

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        self.backgroundColor = [UIColor colorWithRed:0.72f green:0.86f blue:0.50f alpha:1];
        _bg = [CAGradientLayer layer];
        _bg.colors = @[ (id)[UIColor colorWithRed:0.80f green:0.90f blue:0.60f alpha:1].CGColor,
                        (id)[UIColor colorWithRed:0.68f green:0.83f blue:0.44f alpha:1].CGColor ];
        _bg.startPoint = CGPointMake(0.3f, 0);
        _bg.endPoint = CGPointMake(0.6f, 1);
        [self.layer addSublayer:_bg];
        _mode = [NewGameView savedMode];

        // шапка
        _back = [UIButton buttonWithType:UIButtonTypeCustom];
        _back.backgroundColor = [UIColor colorWithRed:0.98f green:0.99f blue:0.95f alpha:0.97f];
        _back.layer.borderColor = [UIColor colorWithRed:0.82f green:0.86f blue:0.74f alpha:1].CGColor;
        [_back setTitle:@"Назад" forState:UIControlStateNormal];
        [_back setTitleColor:COL_TEXT forState:UIControlStateNormal];
        [_back addTarget:self action:@selector(onBack) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_back];
        _chevron = [[UIImageView alloc] initWithImage:NGImage(@"newgame", @"chevron.png")];
        _chevron.contentMode = UIViewContentModeScaleAspectFit;
        [_back addSubview:_chevron];

        _title = [self label:@"Новая игра"];
        _modeCaption = [self label:@"Выбери режим"];
        _mapCaption = [self label:@"Выбери карту"];
        [self addSubview:_title]; [self addSubview:_modeCaption]; [self addSubview:_mapCaption];

        // режимы: одна серая птичка / синяя и красная команды
        NSArray *caps = @[ @"Все против всех", @"Командный бой" ];
        NSArray *icons = @[ @[ @"bird_gray.png" ], @[ @"bird_blue.png", @"bird_red.png" ] ];
        for (int i = 0; i < 2; i++) {
            NGModeCard *c = [NGModeCard buttonWithType:UIButtonTypeCustom];
            c.tag = i;
            NSMutableArray *ivs = [NSMutableArray array];
            for (NSString *f in icons[i]) {
                UIImageView *iv = [[UIImageView alloc] initWithImage:NGImage(@"newgame", f)];
                iv.contentMode = UIViewContentModeScaleAspectFit;
                iv.userInteractionEnabled = NO;
                [c addSubview:iv]; [ivs addObject:iv];
            }
            c.icons = ivs;
            c.caption = [self label:caps[i]];
            [c addSubview:c.caption];
            c.selected = (i == _mode);
            [c addTarget:self action:@selector(onMode:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:c];
            _modes[i] = c;
        }

        // карты из scenes.txt
        _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
        _scroll.showsHorizontalScrollIndicator = NO;
        _scroll.alwaysBounceHorizontal = YES;
        [self addSubview:_scroll];
        _cards = [NSMutableArray array];
        NSString *res = [[NSBundle mainBundle] resourcePath];
        NSString *txt = [NSString stringWithContentsOfFile:[res stringByAppendingPathComponent:@"scenes.txt"] encoding:NSUTF8StringEncoding error:nil];
        NSString *last = [[NSUserDefaults standardUserDefaults] stringForKey:kLastMapKey];
        for (NSString *line in [txt componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
            if ([line length] == 0) continue;
            NSString *name = [line stringByDeletingPathExtension];
            NGMapCard *c = [NGMapCard buttonWithType:UIButtonTypeCustom];
            c.file = line;
            c.backgroundColor = COL_CARD;
            c.layer.borderColor = COL_BORDER.CGColor;
            c.thumb = [[UIImageView alloc] initWithImage:NGImage(@"maps", [name stringByAppendingString:@".png"])];
            c.thumb.contentMode = UIViewContentModeScaleAspectFill;
            c.thumb.clipsToBounds = YES;
            c.thumb.userInteractionEnabled = NO;
            [c addSubview:c.thumb];
            c.caption = [self label:name];
            [c addSubview:c.caption];
            c.dot = [[UIImageView alloc] initWithImage:NGImage(@"newgame", @"dot.png")];
            c.dot.contentMode = UIViewContentModeScaleAspectFit;
            c.dot.userInteractionEnabled = NO;
            c.dot.hidden = ![line isEqualToString:last];                // зелёная точка — карта, в которую играли в прошлый раз
            [c addSubview:c.dot];
            [c addTarget:self action:@selector(onMap:) forControlEvents:UIControlEventTouchUpInside];
            [_scroll addSubview:c];
            [_cards addObject:c];
        }
        if ([_cards count] == 0) {
            _empty = [self label:@"Нет карт"];
            [self addSubview:_empty];
        }
    }
    return self;
}

#pragma mark - Действия

- (void)onBack {
    id<NewGameViewDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(newGameViewDidPressBack:)]) [d newGameViewDidPressBack:self];
}

- (void)onMode:(NGModeCard *)c {
    _mode = (int)c.tag;
    [[NSUserDefaults standardUserDefaults] setInteger:_mode forKey:kModeKey];
    for (int i = 0; i < 2; i++) _modes[i].selected = (i == _mode);
}

- (void)onMap:(NGMapCard *)c {
    [[NSUserDefaults standardUserDefaults] setObject:c.file forKey:kLastMapKey];
    id<NewGameViewDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(newGameView:didSelectMap:mode:)]) [d newGameView:self didSelectMap:c.file mode:_mode];
}

#pragma mark - Вёрстка

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _bg.frame = self.bounds;
    [CATransaction commit];

    CGFloat s = MIN(w / DESIGN_W, h / DESIGN_H);
    CGFloat ox = (w - DESIGN_W * s) * 0.5f;
    CGFloat Hd = h / s;                                               // высота экрана в дизайн-единицах (>= 500)
    // Высокий экран (iPhone 5 16:9, iPad 4:3): карточки растут (до 1.45x), остаток делится на три равных зазора.
    CGFloat k = MIN(1.45f, MAX(1.0f, (Hd - HEADER_H) / (REGION_A + REGION_B)));
    CGFloat gap = MAX(0.0f, (Hd - HEADER_H - (REGION_A + REGION_B) * k) / 3.0f);
    CGFloat yA = HEADER_H + gap;                                      // верх блока режимов
    CGFloat yB = yA + REGION_A * k + gap;                             // верх блока карт
    CGFloat bw = MAX(1.0f, 2 * s);

#define X(v) (ox + (v) * s)
#define Y(v) ((v) * s)

    // шапка
    _back.frame = CGRectMake(3 * s, 5 * s, 187 * s, 52 * s);
    _back.layer.borderWidth = bw; _back.layer.cornerRadius = 4 * s;
    _back.titleLabel.font = [UIFont boldSystemFontOfSize:MAX(19 * s, 12)];
    _back.titleEdgeInsets = UIEdgeInsetsMake(0, 40 * s, 0, 0);
    _chevron.frame = CGRectMake(14 * s, 10 * s, 32 * s, 32 * s);
    _title.font = [UIFont boldSystemFontOfSize:MAX(22 * s, 13)];
    _title.frame = CGRectMake(X(385), Y(12), 400 * s, 40 * s);

    // режимы
    UIFont *cap = [UIFont boldSystemFontOfSize:MAX(22 * k * s, 12)];
    _modeCaption.font = cap;
    _modeCaption.frame = CGRectMake(X(385), Y(yA + 36 * k - 14 * k), 400 * s, 28 * k * s);
    CGFloat cw = 323 * k, ch = 110 * k, cgap = 14 * k, cy = yA + 60 * k;
    for (int i = 0; i < 2; i++) {
        NGModeCard *c = _modes[i];
        CGFloat cx = 585 + (i == 0 ? -(cgap / 2 + cw) : cgap / 2);
        c.frame = CGRectMake(X(cx), Y(cy), cw * s, ch * s);
        c.layer.borderWidth = (i == _mode ? 3 : 1) * MAX(1.0f, s); c.layer.cornerRadius = 4 * s;
        CGFloat isz = 46 * k * s;
        NSUInteger n = [c.icons count];
        for (NSUInteger j = 0; j < n; j++) {
            UIImageView *iv = c.icons[j];
            CGFloat x0 = (cw * s - n * isz - (n - 1) * 10 * k * s) * 0.5f + j * (isz + 10 * k * s);
            iv.frame = CGRectMake(x0, 14 * k * s, isz, isz);
        }
        c.caption.font = cap;
        c.caption.frame = CGRectMake(0, 70 * k * s, cw * s, 30 * k * s);
        c.layer.borderWidth = (c.selected ? 3 : 1) * MAX(1.0f, s);
    }

    // карты
    _mapCaption.font = cap;
    _mapCaption.frame = CGRectMake(X(385), Y(yB + 10 * k - 14 * k), 400 * s, 28 * k * s);
    CGFloat mw = 283 * k, mh = 215 * k, mgap = 6 * k;
    CGRect sr = CGRectMake(0, Y(yB + 38 * k), w, MIN(mh * s, h - Y(yB + 38 * k)));
    _scroll.frame = sr;
    CGFloat tw = 205 * k * s, th = 130 * k * s;
    UIFont *nf = [UIFont systemFontOfSize:MAX(21 * k * s, 11)];
    for (NSUInteger i = 0; i < [_cards count]; i++) {
        NGMapCard *c = _cards[i];
        c.frame = CGRectMake(ox + 6 * k * s + i * (mw + mgap) * s, 0, mw * s, mh * s);
        c.layer.borderWidth = MAX(1.0f, s); c.layer.cornerRadius = 3 * s;
        c.thumb.frame = CGRectMake((mw * s - tw) * 0.5f, 7 * k * s, tw, th);
        c.caption.font = nf;
        c.caption.frame = CGRectMake(0, 150 * k * s, mw * s, 26 * k * s);
        CGFloat dsz = 40 * k * s;
        c.dot.frame = CGRectMake(c.thumb.frame.origin.x + tw - dsz * 0.75f, c.thumb.frame.origin.y - dsz * 0.1f, dsz, dsz * 0.9f);
    }
    _scroll.contentSize = CGSizeMake(ox + 12 * k * s + [_cards count] * (mw + mgap) * s, sr.size.height);
    _empty.frame = CGRectMake(0, Y(yB + 100 * k), w, 40 * s);
    _empty.font = cap;
#undef X
#undef Y
}

@end
