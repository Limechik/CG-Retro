#import "ShopView.h"
#import "Outfit.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

static NSString *const kShopFontName = @"07NikumaruFont";
static NSString *const kWeaponIndexKey = @"ChickenGunWeaponIndex";
static NSString *const kCoinsKey = @"ChickenGunCoins";

#define DESIGN_W 1000.0f
#define DESIGN_H 590.0f

#define COL_PANEL    [UIColor colorWithRed:0.85f green:0.93f blue:0.68f alpha:1]
#define COL_PRESSED  [UIColor colorWithRed:0.72f green:0.85f blue:0.50f alpha:1]
#define COL_BORDER   [UIColor colorWithRed:0.71f green:0.83f blue:0.46f alpha:1]
#define COL_TEXT     [UIColor colorWithRed:0.14f green:0.17f blue:0.08f alpha:1]
#define COL_TAB      [UIColor colorWithRed:0.82f green:0.76f blue:0.45f alpha:1]
#define COL_TAB_SEL  [UIColor colorWithRed:0.27f green:0.36f blue:0.08f alpha:1]

static UIFont *ShopFont(CGFloat size) {
    UIFont *f = [UIFont fontWithName:kShopFontName size:size];
    return f ? f : [UIFont boldSystemFontOfSize:size];
}

static UIImage *ShopImage(NSString *name) {
    NSString *path = [[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"shop"] stringByAppendingPathComponent:name];
    return [UIImage imageWithContentsOfFile:path];
}

// «Damage» = урон в секунду (урон * дробинки / интервал), «Accuracy» = 100 - 15.4 * разброс (в градусах).
// Для G36 это 53 и 54 — как на скриншоте оригинала. Считается из weapons.plist.
static int ShopDamageStat(NSDictionary *w) {
    float interval = [w[@"interval"] floatValue]; if (interval < 0.01f) interval = 0.01f;
    int pellets = [w[@"pellets"] intValue]; if (pellets < 1) pellets = 1;
    return (int)lroundf([w[@"damage"] floatValue] * pellets / interval);
}
static int ShopAccuracyStat(NSDictionary *w) {
    float sp = ([w[@"spreadX"] floatValue] + [w[@"spreadY"] floatValue]) * 0.5f;
    int a = (int)lroundf(100.0f - 15.4f * sp);
    return a < 1 ? 1 : (a > 100 ? 100 : a);
}
// Доля ширины рамки, которую занимает иконка: пистолеты мельче винтовок.
static CGFloat ShopSizeFactor(NSDictionary *w) {
    CGFloat e = [w[@"extentX"] floatValue] / 2.1f;
    return 0.55f + 0.45f * (e > 1 ? 1 : e);
}

static UIImage *ShopShadowImage(void) {
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

// ---- кнопки ----

@interface ShopPanelButton : UIButton   // светло-зелёная плашка (Back, Free coins)
@end
@implementation ShopPanelButton
- (void)setHighlighted:(BOOL)h {
    [super setHighlighted:h];
    self.backgroundColor = h ? COL_PRESSED : COL_PANEL;
}
@end

@interface ShopTabButton : UIButton     // вкладка: иконка + подпись; выбранная темнее
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *caption;
@end
@implementation ShopTabButton
- (void)setSelected:(BOOL)s {
    [super setSelected:s];
    self.backgroundColor = s ? COL_TAB_SEL : COL_TAB;
    self.caption.textColor = s ? [UIColor whiteColor] : COL_TEXT;
}
@end

@interface ShopCellButton : UIButton    // ячейка оружия в нижнем ряду
@property (nonatomic, strong) UIImageView *icon;
@end
@implementation ShopCellButton
- (void)setSelected:(BOOL)s {
    [super setSelected:s];
    self.backgroundColor = [UIColor colorWithWhite:s ? 1.0f : 0.0f alpha:0.28f];
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.9f].CGColor;
    self.layer.borderWidth = s ? 2 : 0;
}
@end

@interface ShopView () <UIAlertViewDelegate>
@end

@implementation ShopView {
    CAGradientLayer *_bg;
    NSArray *_weapons;
    NSInteger _selected, _tab;
    NSMutableDictionary *_cache;

    ShopPanelButton *_backBtn, *_freeBtn;
    UIImageView *_backArrow, *_freeCoin, *_coinIcon;
    UIView *_coinsPanel;
    UILabel *_coinsLabel;

    UIImageView *_gun, *_chicken, *_shadow;
    UIView *_statPanel;
    UILabel *_dmgName, *_dmgVal, *_accName, *_accVal;

    NSMutableArray *_tabs;
    UIView *_strip;
    UIScrollView *_scroll;
    NSMutableArray *_cells;
    NSMutableDictionary *_itemCells;     // категория (hats/shoes/eyes/beak) -> ячейки предметов
    NSMutableDictionary *_overlays;      // категория -> UIImageView со слоем предмета (подвид _chicken)
    NSMutableDictionary *_overlayKeys;   // что сейчас загружено в слой («id|оружие»), чтобы не читать файл зря
    UILabel *_soon;
}

+ (NSInteger)selectedWeaponIndex {
    return [[NSUserDefaults standardUserDefaults] integerForKey:kWeaponIndexKey];
}

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        self.backgroundColor = [UIColor colorWithRed:0.45f green:0.75f blue:0.03f alpha:1];
        self.multipleTouchEnabled = NO;
        _cache = [NSMutableDictionary dictionary];

        _bg = [CAGradientLayer layer];
        _bg.colors = @[ (id)[UIColor colorWithRed:0.69f green:0.85f blue:0.02f alpha:1].CGColor,
                        (id)[UIColor colorWithRed:0.40f green:0.72f blue:0.03f alpha:1].CGColor ];
        _bg.startPoint = CGPointMake(0.3f, 0);
        _bg.endPoint = CGPointMake(0.6f, 1);
        [self.layer addSublayer:_bg];

        NSString *plist = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"weapons.plist"];
        _weapons = [NSArray arrayWithContentsOfFile:plist];
        if (!_weapons) _weapons = @[];
        _selected = [ShopView selectedWeaponIndex];
        if (_selected < 0 || _selected >= (NSInteger)[_weapons count]) _selected = 0;
        _tab = 0;

        // шапка
        _backBtn = [self panelButton];
        [_backBtn setTitle:@"Back" forState:UIControlStateNormal];
        [_backBtn addTarget:self action:@selector(onBack) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_backBtn];
        _backArrow = [self iconView:@"arrow_back.png" parent:_backBtn];

        _freeBtn = [self panelButton];
        _freeBtn.titleLabel.numberOfLines = 2;
        _freeBtn.titleLabel.textAlignment = NSTextAlignmentCenter;
        [_freeBtn setTitle:@"Free\ncoins" forState:UIControlStateNormal];
        [_freeBtn addTarget:self action:@selector(onFreeCoins) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_freeBtn];
        _freeCoin = [self iconView:@"coin.png" parent:_freeBtn];

        _coinsPanel = [[UIView alloc] initWithFrame:CGRectZero];
        _coinsPanel.backgroundColor = COL_PANEL;
        _coinsPanel.layer.borderColor = COL_BORDER.CGColor;
        [self addSubview:_coinsPanel];
        _coinsLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _coinsLabel.backgroundColor = [UIColor clearColor];
        _coinsLabel.textColor = COL_TEXT;
        _coinsLabel.textAlignment = NSTextAlignmentCenter;
        [_coinsPanel addSubview:_coinsLabel];
        _coinIcon = [self iconView:@"coin.png" parent:_coinsPanel];

        // превью: оружие, тень, курица
        _gun = [[UIImageView alloc] initWithFrame:CGRectZero];
        _gun.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_gun];

        _shadow = [[UIImageView alloc] initWithImage:ShopShadowImage()];
        [self addSubview:_shadow];
        _chicken = [[UIImageView alloc] initWithFrame:CGRectZero];
        _chicken.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_chicken];
        _overlays = [NSMutableDictionary dictionary];                 // надетые предметы: слои поверх курицы той же рамкой
        _overlayKeys = [NSMutableDictionary dictionary];
        for (NSString *key in OutfitLayerOrder()) {
            UIImageView *ov = [[UIImageView alloc] initWithFrame:CGRectZero];
            ov.userInteractionEnabled = NO;
            [_chicken addSubview:ov];
            _overlays[key] = ov;
        }

        // статы
        _statPanel = [[UIView alloc] initWithFrame:CGRectZero];
        _statPanel.backgroundColor = [UIColor colorWithWhite:0.85f alpha:0.88f];
        [self addSubview:_statPanel];
        _dmgName = [self statLabel:NSTextAlignmentLeft];  _dmgVal = [self statLabel:NSTextAlignmentRight];
        _accName = [self statLabel:NSTextAlignmentLeft];  _accVal = [self statLabel:NSTextAlignmentRight];
        _dmgName.text = @"Damage"; _accName.text = @"Accuracy";

        // вкладки
        _tabs = [NSMutableArray array];
        NSArray *names = @[ @"Guns", @"Hats", @"Shoes", @"Eyes", @"Beak" ];
        NSArray *icons = @[ @"tab_guns.png", @"tab_hats.png", @"tab_shoes.png", @"tab_eyes.png", @"tab_beak.png" ];
        for (NSUInteger i = 0; i < [names count]; i++) {
            ShopTabButton *t = [ShopTabButton buttonWithType:UIButtonTypeCustom];
            t.tag = (NSInteger)i;
            t.icon = [self iconView:icons[i] parent:t];
            t.caption = [[UILabel alloc] initWithFrame:CGRectZero];
            t.caption.backgroundColor = [UIColor clearColor];
            t.caption.textAlignment = NSTextAlignmentCenter;
            t.caption.text = names[i];
            t.caption.userInteractionEnabled = NO;
            [t addSubview:t.caption];
            t.selected = (i == 0);
            [t addTarget:self action:@selector(onTab:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:t];
            [_tabs addObject:t];
        }

        // нижний ряд
        _strip = [[UIView alloc] initWithFrame:CGRectZero];
        _strip.backgroundColor = [UIColor colorWithRed:0.12f green:0.28f blue:0.02f alpha:0.35f];
        [self addSubview:_strip];
        _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
        _scroll.showsHorizontalScrollIndicator = NO;
        _scroll.alwaysBounceHorizontal = YES;
        [self addSubview:_scroll];
        _cells = [NSMutableArray array];
        for (NSUInteger i = 0; i < [_weapons count]; i++) {
            ShopCellButton *c = [ShopCellButton buttonWithType:UIButtonTypeCustom];
            c.tag = (NSInteger)i;
            c.icon = [[UIImageView alloc] initWithImage:ShopImage([NSString stringWithFormat:@"weapon_%@_s.png", _weapons[i][@"id"]])];
            c.icon.contentMode = UIViewContentModeScaleAspectFit;
            c.icon.userInteractionEnabled = NO;
            [c addSubview:c.icon];
            c.selected = ((NSInteger)i == _selected);
            [c addTarget:self action:@selector(onCell:) forControlEvents:UIControlEventTouchUpInside];
            [_scroll addSubview:c];
            [_cells addObject:c];
        }
        // ячейки предметов Hats / Shoes / Eyes / Beak (иконки из tools/build_shop_items.py), показываются по вкладке
        _itemCells = [NSMutableDictionary dictionary];
        for (NSDictionary *cat in OutfitCategories()) {
            NSMutableArray *arr = [NSMutableArray array];
            NSArray *items = cat[@"items"];
            for (NSUInteger i = 0; i < [items count]; i++) {
                ShopCellButton *c = [ShopCellButton buttonWithType:UIButtonTypeCustom];
                c.tag = (NSInteger)i;
                c.icon = [[UIImageView alloc] initWithImage:ShopImage([NSString stringWithFormat:@"item_%@_%@_s.png", cat[@"key"], items[i][@"id"]])];
                c.icon.contentMode = UIViewContentModeScaleAspectFit;
                c.icon.userInteractionEnabled = NO;
                [c addSubview:c.icon];
                c.hidden = YES;
                [c addTarget:self action:@selector(onItemCell:) forControlEvents:UIControlEventTouchUpInside];
                [_scroll addSubview:c];
                [arr addObject:c];
            }
            _itemCells[cat[@"key"]] = arr;
        }
        _soon = [[UILabel alloc] initWithFrame:CGRectZero];
        _soon.backgroundColor = [UIColor clearColor];
        _soon.textColor = COL_TEXT;
        _soon.textAlignment = NSTextAlignmentCenter;
        _soon.text = @"Скоро";
        _soon.hidden = YES;
        [self addSubview:_soon];

        [self refresh];
    }
    return self;
}

#pragma mark - Помощники

- (ShopPanelButton *)panelButton {
    ShopPanelButton *b = [ShopPanelButton buttonWithType:UIButtonTypeCustom];
    b.backgroundColor = COL_PANEL;
    b.layer.borderColor = COL_BORDER.CGColor;
    [b setTitleColor:COL_TEXT forState:UIControlStateNormal];
    return b;
}

- (UIImageView *)iconView:(NSString *)file parent:(UIView *)parent {
    UIImageView *v = [[UIImageView alloc] initWithImage:ShopImage(file)];
    v.contentMode = UIViewContentModeScaleAspectFit;
    v.userInteractionEnabled = NO;
    [parent addSubview:v];
    return v;
}

- (UILabel *)statLabel:(NSTextAlignment)al {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.backgroundColor = [UIColor clearColor];
    l.textColor = [UIColor colorWithWhite:0.15f alpha:1];
    l.textAlignment = al;
    [_statPanel addSubview:l];
    return l;
}

- (UIImage *)cachedImage:(NSString *)name {
    UIImage *img = _cache[name];
    if (!img) { img = ShopImage(name); if (img) _cache[name] = img; }
    return img;
}

#pragma mark - Состояние

// Перерисовывает всё, что зависит от выбранной вкладки и оружия.
- (void)refresh {
    NSDictionary *w = [_weapons count] ? _weapons[_selected] : nil;
    NSArray *cats = OutfitCategories();
    NSDictionary *cat = (_tab >= 1 && _tab <= (NSInteger)[cats count]) ? cats[_tab - 1] : nil;   // вкладки Hats..Beak = категории
    BOOL guns = (_tab == 0) && w != nil;
    BOOL showSoon = !guns && cat == nil;                       // нет ни оружия, ни items.plist

    _gun.hidden = showSoon; _statPanel.hidden = showSoon; _scroll.hidden = showSoon; _soon.hidden = !showSoon;
    for (ShopCellButton *c in _cells) c.hidden = !guns;
    for (NSString *k in _itemCells) for (ShopCellButton *c in _itemCells[k]) c.hidden = YES;
    if (w) _chicken.image = [self cachedImage:[NSString stringWithFormat:@"chicken_%@.png", w[@"id"]]];
    if (guns) {
        _gun.image = [self cachedImage:[NSString stringWithFormat:@"weapon_%@.png", w[@"id"]]];
        _dmgName.text = @"Damage"; _accName.text = @"Accuracy";
        _dmgVal.text = [NSString stringWithFormat:@"%d", ShopDamageStat(w)];
        _accVal.text = [NSString stringWithFormat:@"%d", ShopAccuracyStat(w)];
    } else if (cat) {
        NSString *key = cat[@"key"], *sel = OutfitSelectedID(key), *name = @"";
        for (NSDictionary *it in cat[@"items"]) if ([it[@"id"] isEqualToString:sel]) name = it[@"name"];
        _gun.image = [self cachedImage:[NSString stringWithFormat:@"item_%@_%@.png", key, sel]];   // слева крупно выбранный предмет
        _dmgName.text = name; _dmgVal.text = @"";
        _accName.text = @"Price"; _accVal.text = @"Free";
        for (ShopCellButton *c in _itemCells[key]) c.hidden = NO;
    }
    for (ShopCellButton *c in _cells) c.selected = (c.tag == _selected);
    for (NSDictionary *ct in cats) {                           // подсветка надетых предметов
        NSString *key = ct[@"key"], *sel = OutfitSelectedID(key); NSArray *items = ct[@"items"];
        for (ShopCellButton *c in _itemCells[key]) c.selected = [items[c.tag][@"id"] isEqualToString:sel];
    }
    // слои надетых предметов на курице (при смене оружия клюв перерисовывается: ствол должен остаться поверх него)
    for (NSString *key in OutfitLayerOrder()) {
        NSString *sel = OutfitSelectedID(key), *wid = w ? w[@"id"] : @"";
        NSString *tag = [NSString stringWithFormat:@"%@|%@", sel, [key isEqualToString:@"beak"] ? wid : @""];
        if ([_overlayKeys[key] isEqualToString:tag]) continue;
        _overlayKeys[key] = tag;
        ((UIImageView *)_overlays[key]).image = OutfitLayerImage(NO, key, sel, wid);
    }
    for (ShopTabButton *t in _tabs) t.selected = (t.tag == _tab);
    _coinsLabel.text = [NSString stringWithFormat:@"%d", (int)[[NSUserDefaults standardUserDefaults] integerForKey:kCoinsKey]];
    [self setNeedsLayout];
}

- (void)onTab:(ShopTabButton *)b { _tab = b.tag; [self refresh]; }

- (void)onCell:(ShopCellButton *)b {
    _selected = b.tag;
    [[NSUserDefaults standardUserDefaults] setInteger:_selected forKey:kWeaponIndexKey];
    [self refresh];
}

// Предмет кастомизации: тап надевает его (первый в списке — «без предмета»).
- (void)onItemCell:(ShopCellButton *)b {
    NSArray *cats = OutfitCategories();
    if (_tab < 1 || _tab > (NSInteger)[cats count]) return;
    NSDictionary *cat = cats[_tab - 1];
    OutfitSelect(cat[@"key"], cat[@"items"][b.tag][@"id"]);
    [self refresh];
}

- (void)onBack {
    id<ShopViewDelegate> d = self.delegate;
    if ([d respondsToSelector:@selector(shopViewDidPressBack:)]) [d shopViewDidPressBack:self];
}

- (void)onFreeCoins {
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Free coins" message:@"Rewards are not available. Items can be selected without coins." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [a show];
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
    // На iPad (4:3) и iPhone 4 (3:2) экран выше дизайна 1000x590: лишнюю высоту (extra, дизайн-единицы) делим так:
    // средний блок (оружие, курица, статы, вкладки) опускаем на 55% и немного (до 1.25x) увеличиваем курицу и оружие.
    // На iPhone 5 (16:9) extra = 0, вёрстка как в оригинале.
    CGFloat extra = MAX(0.0f, h / s - DESIGN_H);
    CGFloat shift = extra * 0.55f;
    CGFloat km = 1.0f + MIN(0.25f, extra / DESIGN_H * 0.45f);

    // ax: 0 — от левого края, 1 — по центру, 2 — от правого края. ay: 0 — от верха, 1 — средний блок (со сдвигом).
#define R(ax, ay, x, y, dw, dh) CGRectMake(((ax) == 0 ? 0 : ((ax) == 1 ? ox : w - DESIGN_W * s)) + (x) * s, ((y) + ((ay) == 0 ? 0 : shift)) * s, (dw) * s, (dh) * s)
    CGFloat bw = MAX(1.0f, 2 * s);

    // шапка
    _backBtn.frame = R(0, 0, 9, 12, 149, 61);
    _backBtn.titleLabel.font = [UIFont systemFontOfSize:MAX(26 * s, 11)];
    _backBtn.titleEdgeInsets = UIEdgeInsetsMake(0, 36 * s, 0, 0);
    _backBtn.layer.borderWidth = bw; _backBtn.layer.cornerRadius = 5 * s;
    _backArrow.frame = CGRectMake(20 * s, (61 - 34) * 0.5f * s, 30 * s, 34 * s);

    _freeBtn.frame = R(2, 0, 555, 12, 187, 61);
    _freeBtn.titleLabel.font = [UIFont systemFontOfSize:MAX(23 * s, 10)];
    _freeBtn.titleEdgeInsets = UIEdgeInsetsMake(0, 50 * s, 0, 0);
    _freeBtn.layer.borderWidth = bw; _freeBtn.layer.cornerRadius = 5 * s;
    _freeCoin.frame = CGRectMake(14 * s, (61 - 46) * 0.5f * s, 46 * s, 46 * s);

    _coinsPanel.frame = R(2, 0, 760, 12, 195, 61);
    _coinsPanel.layer.borderWidth = bw; _coinsPanel.layer.cornerRadius = 5 * s;
    _coinsLabel.font = [UIFont systemFontOfSize:MAX(26 * s, 11)];
    _coinsLabel.frame = CGRectMake(8 * s, 0, 120 * s, 61 * s);
    _coinIcon.frame = CGRectMake(135 * s, (61 - 46) * 0.5f * s, 46 * s, 46 * s);

    // превью оружия (рамка 334x180 вокруг (303,195)); пистолеты мельче винтовок
    NSDictionary *wd = [_weapons count] ? _weapons[_selected] : nil;
    CGFloat f = (_tab == 0 && wd) ? ShopSizeFactor(wd) : (_tab == 0 ? 1 : 0.72f);          // предметы рисуем помельче оружия
    CGFloat gw = 334 * f * km, gh = gw * 0.5f;
    CGFloat gcy = 327 + shift - 138 * km;                      // центр оружия — над плашкой статов
    _gun.frame = CGRectMake(ox + (303 - gw * 0.5f) * s, (gcy - gh * 0.5f) * s, gw * s, gh * s);

    // курица: высота 303, тело правее центра картинки (ствол торчит влево)
    UIImage *ci = _chicken.image;
    CGFloat ch = 303 * km, cw = ci ? ch * ci.size.width / ci.size.height : 382 * km;
    CGFloat feet = 440 + shift;                                // низ курицы
    _chicken.frame = CGRectMake(ox + (660 - 0.66f * cw) * s, (feet - ch) * s, cw * s, ch * s);
    // слои предметов: та же рамка, но выше на запас сверху (шапки) — размер слоя считаем по его картинке
    CGFloat kk = ci ? (ch * s) / ci.size.height : 1;
    for (NSString *key in _overlays) {
        UIImageView *ov = _overlays[key];
        UIImage *oi = ov.image;
        ov.frame = (oi && ci) ? CGRectMake(0, -(oi.size.height - ci.size.height) * kk, oi.size.width * kk, oi.size.height * kk) : CGRectZero;
    }
    _shadow.frame = CGRectMake(ox + (655 - 125 * km) * s, (feet + 15 - 20 * km) * s, 250 * km * s, 40 * km * s);

    // статы
    _statPanel.frame = R(1, 1, 200, 327, 248, 67);
    _statPanel.layer.cornerRadius = 4 * s;
    UIFont *sf = [UIFont systemFontOfSize:MAX(21 * s, 9)];
    for (UILabel *l in @[ _dmgName, _dmgVal, _accName, _accVal ]) l.font = sf;
    CGFloat pw = 248 * s;
    _dmgName.frame = CGRectMake(10 * s, 6 * s, pw * 0.6f, 26 * s);
    _dmgVal.frame  = CGRectMake(pw - 10 * s - 80 * s, 6 * s, 80 * s, 26 * s);
    _accName.frame = CGRectMake(10 * s, 35 * s, pw * 0.6f, 26 * s);
    _accVal.frame  = CGRectMake(pw - 10 * s - 80 * s, 35 * s, 80 * s, 26 * s);

    // вкладки
    for (ShopTabButton *t in _tabs) {
        t.frame = R(1, 1, 9 + 87 * t.tag, 394, 86, 85);
        t.icon.frame = CGRectMake(12 * s, 4 * s, 62 * s, 56 * s);
        t.caption.font = ShopFont(MAX(21 * s, 9));
        t.caption.frame = CGRectMake(0, 58 * s, 86 * s, 24 * s);
    }

    // нижний ряд (на всю ширину, прижат к низу)
    CGRect sr = CGRectMake(0, h - 90 * s, w, 90 * s);
    _strip.frame = sr;
    _scroll.frame = sr;
    CGFloat cellW = 108 * s, gap = 4 * s;
    for (ShopCellButton *c in _cells) {
        c.frame = CGRectMake(8 * s + c.tag * (cellW + gap), 3 * s, cellW, 84 * s);
        c.layer.cornerRadius = 4 * s;
        CGFloat k = ShopSizeFactor(_weapons[c.tag]);
        CGFloat iw = (cellW - 8 * s) * k, ih = iw * 0.5f;
        if (ih > 76 * s) { ih = 76 * s; iw = ih * 2; }
        c.icon.frame = CGRectMake((cellW - iw) * 0.5f, (84 * s - ih) * 0.5f, iw, ih);
    }
    for (NSString *key in _itemCells) {
        for (ShopCellButton *c in _itemCells[key]) {
            c.frame = CGRectMake(8 * s + c.tag * (cellW + gap), 3 * s, cellW, 84 * s);
            c.layer.cornerRadius = 4 * s;
            CGFloat iw = (cellW - 8 * s) * 0.8f, ih = iw * 0.5f;
            c.icon.frame = CGRectMake((cellW - iw) * 0.5f, (84 * s - ih) * 0.5f, iw, ih);
        }
    }
    NSArray *catsL = OutfitCategories();
    NSUInteger cellCount = (_tab == 0) ? [_cells count] : ((_tab <= (NSInteger)[catsL count]) ? [catsL[_tab - 1][@"items"] count] : 0);
    _scroll.contentSize = CGSizeMake(8 * s * 2 + cellCount * (cellW + gap), sr.size.height);
    _soon.font = ShopFont(MAX(36 * s, 14));
    _soon.frame = sr;
#undef R
}

@end
