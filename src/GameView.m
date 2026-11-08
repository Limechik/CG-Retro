#import "GameView.h"
#import "Renderer.h"
#import "GameScene.h"
#import "WeaponController.h"
#import "BotController.h"
#import "AudioEngine.h"
#import "MenuView.h"
#import "ShopView.h"
#import "NewGameView.h"
#import "HUDButton.h"
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

#define STICK_RADIUS 70.0f       // пикселей (в пунктах) до полного отклонения
#define LOOK_SENSITIVITY 0.006f  // рад на пункт

@interface GameView () <MenuViewDelegate, ShopViewDelegate, NewGameViewDelegate>
@end

@implementation GameView {
    EAGLContext  *_context;
    CADisplayLink *_link;
    Renderer     *_renderer;
    GameScene    *_scene;
    WeaponController *_weapons;
    BotController *_bots;
    AudioEngine *_audio;

    GLuint _fbo, _colorRB, _depthRB;
    GLint  _bw, _bh;               // размер буфера в пикселях
    CGSize _lastLayoutSize;

    CFTimeInterval _lastTime;
    UIButton *_menuBtn;
    HUDButton *_jumpBtn;
    MenuView *_menu;               // главное меню поверх всего; пока оно видно, цикл отрисовки на паузе
    BOOL _menuVisible;
    ShopView *_shop;              // магазин поверх меню (создаётся при каждом открытии)
    NewGameView *_newGame;        // экран «Новая игра» (режим и карта) поверх меню
    UILabel *_scoreLabel, *_resultLabel;   // командный бой: счёт «Синие 3 : 5 Красные» и итог матча
    BOOL _matchOver;
    float _matchOverTimer;
    HUDButton *_fireBtnR, *_fireBtnL, *_reloadBtn, *_weaponBtn;
    UIImageView *_stickBase, *_stickKnob;   // плавающий джойстик: рисуется, пока палец на левой половине экрана
    NSArray *_weaponIds;                    // id оружия из weapons.plist (для иконки на кнопке оружия)
    UIView *_crosshair;
    UILabel *_ammoLabel;
    NSString *_lastAmmoText;
    int _fireTouches;

    // игрок: здоровье, смерть, счёт
    float _health, _timeSinceDamage, _respawnTimer, _damageFlash, _hitMarkerTime;
    BOOL _playerAlive;
    int _deaths;
    UIView *_damageOverlay, *_hitMarker;
    UIView *_hitBarA, *_hitBarB;
    UILabel *_healthLabel, *_deathLabel;
    float _stepTimer, _airTime, _hurtCooldown;
    NSString *_lastHealthText;
    NSArray *_viewerGestures;
    float _pinchStartZoom;

    // режим сцены
    BOOL _sceneMode;
    NSArray *_sceneNames;
    NSUInteger _sceneIndex;
    UITouch *_moveTouch, *_lookTouch;
    CGPoint _moveStart, _lookLast;
    float _stickX, _stickY;        // [-1, 1], y вниз положителен
}

+ (Class)layerClass { return [CAEAGLLayer class]; }

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = YES;
        // Retina-iPad (2048x1536) для этого рендера тяжеловат: ограничиваем число пикселей (~1.4 млн). На iPhone 4/5
        // это ничего не меняет (до 0.73 млн), iPad рисуется в ~1.33x вместо 2x.
        {
            CGSize sb = [UIScreen mainScreen].bounds.size;
            CGFloat sc = [UIScreen mainScreen].scale;
            const CGFloat kMaxPixels = 1.4e6f;
            if (sb.width * sb.height * sc * sc > kMaxPixels) sc = MAX(1.0f, sqrtf(kMaxPixels / (sb.width * sb.height)));
            self.contentScaleFactor = sc;
        }
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        CAEAGLLayer *layer = (CAEAGLLayer *)self.layer;
        layer.opaque = YES;
        layer.drawableProperties = @{
            kEAGLDrawablePropertyRetainedBacking : @NO,
            kEAGLDrawablePropertyColorFormat     : kEAGLColorFormatRGBA8
        };

        _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        if (!_context || ![EAGLContext setCurrentContext:_context]) {
            NSLog(@"[GameView] не удалось создать GLES2 контекст");
            return self;
        }

        _renderer = [[Renderer alloc] init];
        if (![_renderer setup]) NSLog(@"[GameView] Renderer setup failed");
        _scene = [[GameScene alloc] init];
        _weapons = [[WeaponController alloc] init];
        _bots = [[BotController alloc] init];
        if (![_bots setup]) NSLog(@"[GameView] BotController setup failed");
        _weapons.bots = _bots;
        _audio = [[AudioEngine alloc] init];
        if (![_audio setup]) NSLog(@"[GameView] AudioEngine setup failed");
        _weapons.audio = _audio;
        _bots.audio = _audio;
        _health = 100.0f; _playerAlive = YES;
        if (![_weapons setup]) NSLog(@"[GameView] WeaponController setup failed");
        [self loadSceneList];

        [self setupHUD];
        [self setupButtons];
        [self setupCrosshair];
        [self setupGestures];
        _menuBtn = [self makeButton:@"Menu" action:@selector(onMenuButton) event:UIControlEventTouchUpInside];
        _menuBtn.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
        _menuVisible = YES;
        [self updateUIForMode];

        _menu = [[MenuView alloc] initWithFrame:self.bounds];
        _menu.delegate = self;
        _menu.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_menu];

        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(pause)  name:UIApplicationWillResignActiveNotification object:nil];
        [nc addObserver:self selector:@selector(resume) name:UIApplicationDidBecomeActiveNotification object:nil];

        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(drawFrame:)];
        _link.frameInterval = 1;   // 60 fps; на старых устройствах поставьте 2 (30 fps)
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        _link.paused = _menuVisible;   // в меню GL не рисуем
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_link invalidate];
    if (_context) [EAGLContext setCurrentContext:_context];
    [_bots stop];
    [_scene unload];
    [self destroyBuffers];
}

#pragma mark - Список сцен

- (void)loadSceneList {
    NSString *res = [[NSBundle mainBundle] resourcePath];
    NSString *txt = [NSString stringWithContentsOfFile:[res stringByAppendingPathComponent:@"scenes.txt"]
                                              encoding:NSUTF8StringEncoding error:nil];
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *line in [txt componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        if ([line length] > 0) [names addObject:line];
    }
    _sceneNames = names;
    // Dust2 первой, если есть
    NSUInteger i = [_sceneNames indexOfObject:@"Dust2.cgs"];
    _sceneIndex = (i == NSNotFound) ? 0 : i;
}

- (BOOL)loadSceneAtIndex:(NSUInteger)i {
    if ([_sceneNames count] == 0) return NO;
    [_bots stop];
    [_weapons clearDecals];
    NSString *file = _sceneNames[i];
    NSString *path = [[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"scenes"]
                      stringByAppendingPathComponent:file];
    [EAGLContext setCurrentContext:_context];
    BOOL ok = [_scene loadFromPath:path name:[file stringByDeletingPathExtension]];
    [_scene resizeWidth:_bw height:_bh];
    if (ok) {
        NSString *cgp = [[path stringByDeletingPathExtension] stringByAppendingPathExtension:@"cgp"];
        [_bots startForScene:_scene spawnFile:cgp];
        [self resetPlayerState];
    }
    return ok;
}

#pragma mark - HUD / кнопки / жесты

- (void)setupHUD {
    // красная вспышка при уроне (под всеми остальными элементами)
    _damageOverlay = [[UIView alloc] initWithFrame:self.bounds];
    _damageOverlay.backgroundColor = [UIColor colorWithRed:0.8 green:0 blue:0 alpha:1.0];
    _damageOverlay.alpha = 0;
    _damageOverlay.userInteractionEnabled = NO;
    _damageOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_damageOverlay];

}

- (UIButton *)makeButton:(NSString *)title action:(SEL)sel event:(UIControlEvents)event {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [b addTarget:self action:sel forControlEvents:event];
    [self addSubview:b];
    return b;
}

- (HUDButton *)makeHUDButton:(NSString *)icon scale:(CGFloat)k alpha:(CGFloat)a action:(SEL)sel event:(UIControlEvents)event {
    HUDButton *b = [HUDButton buttonWithIcon:icon iconScale:k iconAlpha:a];
    [b addTarget:self action:sel forControlEvents:event];
    [self addSubview:b];
    return b;
}

- (void)setupButtons {
    // плавающий джойстик (текстуры из оригинала): большое кольцо-основание и маленькая ручка; прячем, пока нет касания
    _stickBase = [[UIImageView alloc] initWithImage:HUDImage(@"ring.png")];
    _stickBase.alpha = 0.9f;
    _stickKnob = [[UIImageView alloc] initWithImage:HUDImage(@"ring.png")];
    UIImageView *fill = [[UIImageView alloc] initWithImage:HUDImage(@"disc.png")];
    fill.alpha = 0.3f;
    fill.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_stickKnob addSubview:fill];
    _stickBase.hidden = _stickKnob.hidden = YES;
    [self addSubview:_stickBase];
    [self addSubview:_stickKnob];

    // прыжок срабатывает сразу при касании, а не при отпускании
    _jumpBtn = [self makeHUDButton:@"jump.png" scale:0.62f alpha:0.56f action:@selector(onJumpButton) event:UIControlEventTouchDown];
    _jumpBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;

    // огонь: две кнопки (слева и справа), чтобы стрелять любым большим пальцем; держим — автоогонь
    _fireBtnR = [self makeHUDButton:@"fire.png" scale:0.72f alpha:0.68f action:@selector(onFireDown) event:UIControlEventTouchDown];
    _fireBtnL = [self makeHUDButton:@"fire.png" scale:0.72f alpha:0.68f action:@selector(onFireDown) event:UIControlEventTouchDown];
    UIControlEvents up = UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel;
    [_fireBtnR addTarget:self action:@selector(onFireUp) forControlEvents:up];
    [_fireBtnL addTarget:self action:@selector(onFireUp) forControlEvents:up];
    _fireBtnR.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    _fireBtnL.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;

    _reloadBtn = [self makeHUDButton:@"reload.png" scale:0.58f alpha:0.68f action:@selector(onReloadButton) event:UIControlEventTouchUpInside];
    _reloadBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    // оружие: кольцо с иконкой текущего ствола (как WeaponSelectionWidget в оригинале); иконка — updateWeaponIcon
    _weaponBtn = [self makeHUDButton:nil scale:0.80f alpha:1.0f action:@selector(onWeaponButton) event:UIControlEventTouchUpInside];
    _weaponBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;

    _ammoLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _ammoLabel.backgroundColor = [UIColor clearColor];
    _ammoLabel.textColor = [UIColor whiteColor];
    _ammoLabel.shadowColor = [UIColor blackColor];
    _ammoLabel.shadowOffset = CGSizeMake(0, 1);
    _ammoLabel.textAlignment = NSTextAlignmentCenter;
    _ammoLabel.font = [UIFont boldSystemFontOfSize:16];
    _ammoLabel.userInteractionEnabled = NO;
    _ammoLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    [self addSubview:_ammoLabel];

    _healthLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _healthLabel.backgroundColor = [UIColor clearColor];
    _healthLabel.textColor = [UIColor whiteColor];
    _healthLabel.shadowColor = [UIColor blackColor];
    _healthLabel.shadowOffset = CGSizeMake(0, 1);
    _healthLabel.font = [UIFont boldSystemFontOfSize:20];
    _healthLabel.userInteractionEnabled = NO;
    _healthLabel.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    [self addSubview:_healthLabel];

    _deathLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _deathLabel.backgroundColor = [UIColor clearColor];
    _deathLabel.textColor = [UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1];
    _deathLabel.shadowColor = [UIColor blackColor];
    _deathLabel.shadowOffset = CGSizeMake(0, 2);
    _deathLabel.font = [UIFont boldSystemFontOfSize:34];
    _deathLabel.textAlignment = NSTextAlignmentCenter;
    _deathLabel.text = @"YOU DIED";
    _deathLabel.hidden = YES;
    _deathLabel.userInteractionEnabled = NO;
    _deathLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                   UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self addSubview:_deathLabel];

    // командный бой: счёт сверху по центру и итог матча
    _scoreLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _scoreLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35f];
    _scoreLabel.textColor = [UIColor whiteColor];
    _scoreLabel.textAlignment = NSTextAlignmentCenter;
    _scoreLabel.hidden = YES;
    _scoreLabel.userInteractionEnabled = NO;
    [self addSubview:_scoreLabel];
    _resultLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _resultLabel.backgroundColor = [UIColor clearColor];
    _resultLabel.textColor = [UIColor whiteColor];
    _resultLabel.shadowColor = [UIColor blackColor];
    _resultLabel.shadowOffset = CGSizeMake(0, 2);
    _resultLabel.textAlignment = NSTextAlignmentCenter;
    _resultLabel.numberOfLines = 2;
    _resultLabel.hidden = YES;
    _resultLabel.userInteractionEnabled = NO;
    [self addSubview:_resultLabel];

    // маркер попадания: два повёрнутых штриха в центре (белый — попал, красный — убил)
    _hitMarker = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
    _hitMarker.userInteractionEnabled = NO;
    _hitMarker.alpha = 0;
    _hitMarker.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                  UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    _hitBarA = [[UIView alloc] initWithFrame:CGRectMake(14, 2, 2, 26)];
    _hitBarB = [[UIView alloc] initWithFrame:CGRectMake(14, 2, 2, 26)];
    _hitBarA.transform = CGAffineTransformMakeRotation(0.7853982f);
    _hitBarB.transform = CGAffineTransformMakeRotation(-0.7853982f);
    [_hitMarker addSubview:_hitBarA];
    [_hitMarker addSubview:_hitBarB];
    [self addSubview:_hitMarker];
}

// Прицел: четыре короткие полоски вокруг центра экрана.
- (void)setupCrosshair {
    _crosshair = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 28, 28)];
    _crosshair.userInteractionEnabled = NO;
    _crosshair.backgroundColor = [UIColor clearColor];
    _crosshair.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                  UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    CGRect bars[4] = { CGRectMake(13, 0, 2, 9), CGRectMake(13, 19, 2, 9), CGRectMake(0, 13, 9, 2), CGRectMake(19, 13, 9, 2) };
    for (int i = 0; i < 4; i++) {
        UIView *b = [[UIView alloc] initWithFrame:bars[i]];
        b.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.9];
        b.layer.borderColor = [UIColor colorWithWhite:0 alpha:0.6].CGColor;
        b.layer.borderWidth = 0.5;
        [_crosshair addSubview:b];
    }
    [self addSubview:_crosshair];
}

// HUD рассчитан на 568x320 (iPhone 5; на iPhone 4 такой же u = 1). На iPad кнопки, шрифты и прицел растут до 1.6x.
- (void)layoutButtons {
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat u = [self uiScale];

    UIFont *small = [UIFont boldSystemFontOfSize:13 * u], *big = [UIFont boldSystemFontOfSize:16 * u];
    _menuBtn.titleLabel.font = small;
    _ammoLabel.font = big;
    _healthLabel.font = [UIFont boldSystemFontOfSize:20 * u];
    _deathLabel.font = [UIFont boldSystemFontOfSize:34 * u];

    // круглые кнопки (диаметры в пунктах при u = 1; пропорции — из PlayerControlsPanel оригинала)
    _weaponBtn.frame = HUDCircle(w - 54 * u, 78 * u, 58 * u);
    _jumpBtn.frame = HUDCircle(w - 60 * u, h - 60 * u, 68 * u);
    _fireBtnR.frame = HUDCircle(w - 60 * u, h - 135 * u, 76 * u);
    _fireBtnL.frame = HUDCircle(61 * u, h - 135 * u, 76 * u);
    _reloadBtn.frame = HUDCircle(w - 170 * u, h - 60 * u, 48 * u);
    _stickBase.bounds = CGRectMake(0, 0, 96 * u, 96 * u);     // 80 * 3.75 / 1920 * 568 ≈ 89, чуть крупнее для пальца
    _stickKnob.bounds = CGRectMake(0, 0, 34 * u, 34 * u);
    _ammoLabel.frame = CGRectMake(w * 0.5f - 130 * u, h - 38 * u, 260 * u, 28 * u);
    _menuBtn.frame = CGRectMake(10 * u, 6 * u, 82 * u, 28 * u);        // слева сверху (отладочного текста больше нет)
    _healthLabel.frame = CGRectMake(12 * u, h - 34 * u, 130 * u, 28 * u);
    _deathLabel.frame = CGRectMake(w * 0.5f - 160 * u, h * 0.5f - 60 * u, 320 * u, 44 * u);
    _scoreLabel.font = [UIFont boldSystemFontOfSize:15 * u];
    _scoreLabel.frame = CGRectMake(w * 0.5f - 110 * u, 4 * u, 220 * u, 22 * u);
    _scoreLabel.layer.cornerRadius = 6 * u;
    _resultLabel.font = [UIFont boldSystemFontOfSize:30 * u];
    _resultLabel.frame = CGRectMake(w * 0.5f - 200 * u, h * 0.5f - 110 * u, 400 * u, 84 * u);
    _crosshair.transform = CGAffineTransformMakeScale(u, u);
    _hitMarker.transform = CGAffineTransformMakeScale(u, u);
    _crosshair.center = CGPointMake(w * 0.5f, h * 0.5f);
    _hitMarker.center = CGPointMake(w * 0.5f, h * 0.5f);
}

- (void)updateUIForMode {
    _fireBtnR.hidden = _fireBtnL.hidden = _reloadBtn.hidden = _weaponBtn.hidden = !_sceneMode;
    _crosshair.hidden = _ammoLabel.hidden = !_sceneMode;
    _healthLabel.hidden = !_sceneMode;
    if (!_sceneMode) { _deathLabel.hidden = YES; _damageOverlay.alpha = 0; _hitMarker.alpha = 0; _scoreLabel.hidden = YES; _resultLabel.hidden = YES; _matchOver = NO; }
    _fireTouches = 0;
    [_weapons setFireHeld:NO];
    _jumpBtn.hidden = !(_sceneMode && _scene.hasCollision && _scene.walkMode);
    for (UIGestureRecognizer *g in _viewerGestures) g.enabled = !_sceneMode && !_menuVisible;
    _moveTouch = _lookTouch = nil;
    _stickX = _stickY = 0;
    _stickBase.hidden = _stickKnob.hidden = YES;
    if (_sceneMode) [self updateWeaponIcon];
}

- (void)onModeButton {
    if (!_sceneMode) {
        if (![self loadSceneAtIndex:_sceneIndex]) return;
        _sceneMode = YES;
    } else {
        [EAGLContext setCurrentContext:_context];
        [_bots stop];
        [_scene unload];                      // освобождаем память
        [_weapons clearDecals];
        _sceneMode = NO;
    }
    _lastTime = 0;
    [self updateUIForMode];
}

#pragma mark - Главное меню

// «Play»: открываем экран «Новая игра» (режим и карта) поверх меню.
- (void)menuViewDidPressPlay:(MenuView *)menu {
    if (_newGame) return;
    _newGame = [[NewGameView alloc] initWithFrame:self.bounds];
    _newGame.delegate = self;
    _newGame.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _newGame.alpha = 0;
    [self addSubview:_newGame];
    [UIView animateWithDuration:0.18 animations:^{ _newGame.alpha = 1; }];
}

- (void)newGameViewDidPressBack:(NewGameView *)v {
    NewGameView *n = _newGame;
    _newGame = nil;
    [UIView animateWithDuration:0.15 animations:^{ n.alpha = 0; } completion:^(BOOL done) { [n removeFromSuperview]; }];
}

// Выбрана карта: запоминаем режим и входим в игру.
- (void)newGameView:(NewGameView *)v didSelectMap:(NSString *)sceneFile mode:(int)mode {
    NSUInteger idx = [_sceneNames indexOfObject:sceneFile];
    if (idx == NSNotFound) return;
    _sceneIndex = idx;
    _bots.mode = (mode == 1) ? CGGameModeTeam : CGGameModeFFA;     // до загрузки сцены: от режима зависит состав ботов
    NewGameView *n = _newGame;
    _newGame = nil;
    [n removeFromSuperview];
    [self startGame];
}

// Убираем меню, загружаем выбранную арену и входим в игру.
- (void)startGame {
    [EAGLContext setCurrentContext:_context];
    if (_sceneMode) [self onModeButton];      // выгрузить прежнюю сцену (если была)
    [self onModeButton];                      // загрузить выбранную; если не вышло — останемся в просмотрщике
    [_weapons selectWeaponAtIndex:(NSUInteger)MAX((NSInteger)0, [ShopView selectedWeaponIndex])];   // оружие, выбранное в магазине
    [self updateWeaponIcon];
    _menuVisible = NO;
    [_menu removeFromSuperview];
    _lastTime = 0;
    _link.paused = NO;
    [self updateUIForMode];
}

// «Shop»: открываем магазин поверх меню; «Back» возвращает в меню.
- (void)menuViewDidPressShop:(MenuView *)menu {
    if (_shop) return;
    _shop = [[ShopView alloc] initWithFrame:self.bounds];
    _shop.delegate = self;
    _shop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _shop.alpha = 0;
    [self addSubview:_shop];
    [UIView animateWithDuration:0.18 animations:^{ _shop.alpha = 1; }];
}

- (void)shopViewDidPressBack:(ShopView *)shop {
    ShopView *s = _shop;
    _shop = nil;
    [_menu refreshOutfit];                    // надетые в магазине предметы — на курице в главном меню
    [UIView animateWithDuration:0.15 animations:^{ s.alpha = 0; } completion:^(BOOL done) { [s removeFromSuperview]; }];
}

// Кнопка «Menu» в HUD: выгружаем сцену и возвращаемся в меню.
- (void)onMenuButton {
    if (_sceneMode) [self onModeButton];      // стоп боты, выгрузка сцены, _sceneMode = NO
    _menuVisible = YES;
    _link.paused = YES;
    [self updateUIForMode];
    _menu.frame = self.bounds;
    [self addSubview:_menu];                  // последним — поверх всех кнопок
    [_menu startAnimations];
}

- (void)onJumpButton {
    if (_playerAlive && _scene.onGround) [_audio play:@"jump"];
    [_scene jump];
}

- (void)onFireDown {
    _fireTouches++;
    [_weapons pressFire];
    [_weapons setFireHeld:YES];
}

- (void)onFireUp {
    if (_fireTouches > 0) _fireTouches--;
    if (_fireTouches == 0) [_weapons setFireHeld:NO];
}

- (void)onReloadButton { [_weapons requestReload]; }

- (void)resetPlayerState {
    _health = 100.0f;
    _playerAlive = YES;
    _respawnTimer = 0;
    _timeSinceDamage = 0;
    _damageFlash = 0;
    _deathLabel.hidden = YES;
}
- (void)onWeaponButton {
    [_weapons nextWeapon];
    [self updateWeaponIcon];
}

// Иконка текущего оружия на кнопке (из Resources/shop, те же картинки, что в магазине).
- (void)updateWeaponIcon {
    if (!_weaponIds) {
        NSString *plist = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"weapons.plist"];
        NSMutableArray *ids = [NSMutableArray array];
        for (NSDictionary *w in [NSArray arrayWithContentsOfFile:plist]) [ids addObject:w[@"id"] ? w[@"id"] : @""];
        _weaponIds = ids;
    }
    NSUInteger i = _weapons.weaponIndex;
    if (i >= [_weaponIds count]) return;
    NSString *path = [[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"shop"] stringByAppendingPathComponent:[NSString stringWithFormat:@"weapon_%@_s.png", _weaponIds[i]]];
    _weaponBtn.iconImage = [UIImage imageWithContentsOfFile:path];
}

// HUD рассчитан на 568x320 (iPhone 5; на iPhone 4 тоже 1.0); на iPad растёт до 1.6x.
- (CGFloat)uiScale {
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    return MIN(1.6f, MAX(1.0f, MIN(w / 568.0f, h / 320.0f)));
}

- (void)showStickAt:(CGPoint)p {
    _stickBase.center = p;
    _stickKnob.center = p;
    _stickBase.hidden = _stickKnob.hidden = NO;
}

- (void)moveStickKnob {
    CGFloat r = _stickBase.bounds.size.width * 0.5f * 0.85f;       // ручка доходит почти до края кольца
    _stickKnob.center = CGPointMake(_stickBase.center.x + _stickX * r, _stickBase.center.y + _stickY * r);
}

- (void)setupGestures {
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    pan.maximumNumberOfTouches = 1;
    [self addGestureRecognizer:pan];

    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(onPinch:)];
    [self addGestureRecognizer:pinch];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap:)];
    [self addGestureRecognizer:tap];

    _viewerGestures = @[ pan, pinch, tap ];
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) _renderer.autoSpin = NO;
    CGPoint d = [g translationInView:self];
    [g setTranslation:CGPointZero inView:self];
    _renderer.yaw   += d.x * 0.01f;
    _renderer.pitch += d.y * 0.01f;
}

- (void)onPinch:(UIPinchGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) _pinchStartZoom = _renderer.zoom;
    if (g.scale > 0.01f) _renderer.zoom = _pinchStartZoom / (float)g.scale;
}

// Тап по правой половине — следующий меш, по левой — предыдущий.
- (void)onTap:(UITapGestureRecognizer *)g {
    CGPoint p = [g locationInView:self];
    if (p.x > self.bounds.size.width * 0.5f) [_renderer nextMesh];
    else                                      [_renderer prevMesh];
}

#pragma mark - Управление в сцене (левая половина — движение, правая — взгляд)

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!_sceneMode) { [super touchesBegan:touches withEvent:event]; return; }
    for (UITouch *t in touches) {
        CGPoint p = [t locationInView:self];
        if (p.x < self.bounds.size.width * 0.5f) {
            if (!_moveTouch) { _moveTouch = t; _moveStart = p; [self showStickAt:p]; }
        } else {
            if (!_lookTouch) { _lookTouch = t; _lookLast = p; }
        }
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!_sceneMode) { [super touchesMoved:touches withEvent:event]; return; }
    for (UITouch *t in touches) {
        CGPoint p = [t locationInView:self];
        if (t == _moveTouch) {
            float sr = STICK_RADIUS * [self uiScale];          // на iPad палец проходит больше
            float dx = (float)(p.x - _moveStart.x) / sr;
            float dy = (float)(p.y - _moveStart.y) / sr;
            float len = sqrtf(dx * dx + dy * dy);
            if (len > 1.0f) { dx /= len; dy /= len; }
            _stickX = dx; _stickY = dy;
            [self moveStickKnob];
        } else if (t == _lookTouch) {
            _scene.yaw   -= (float)(p.x - _lookLast.x) * LOOK_SENSITIVITY;
            _scene.pitch -= (float)(p.y - _lookLast.y) * LOOK_SENSITIVITY;
            _lookLast = p;
        }
    }
}

- (void)endSceneTouches:(NSSet *)touches {
    for (UITouch *t in touches) {
        if (t == _moveTouch) { _moveTouch = nil; _stickX = _stickY = 0; _stickBase.hidden = _stickKnob.hidden = YES; }
        if (t == _lookTouch) { _lookTouch = nil; }
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!_sceneMode) { [super touchesEnded:touches withEvent:event]; return; }
    [self endSceneTouches:touches];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!_sceneMode) { [super touchesCancelled:touches withEvent:event]; return; }
    [self endSceneTouches:touches];
}

#pragma mark - Framebuffer

- (void)createBuffers {
    glGenFramebuffers(1, &_fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, _fbo);

    glGenRenderbuffers(1, &_colorRB);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorRB);
    [_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorRB);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH,  &_bw);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_bh);

    // 24 бита глубины (GL_OES_depth24 есть на всех устройствах с GLES2 под iOS 6): сцены большие,
    // 16 бит дают z-fighting при far в сотни метров.
    glGenRenderbuffers(1, &_depthRB);
    glBindRenderbuffer(GL_RENDERBUFFER, _depthRB);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24_OES, _bw, _bh);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _depthRB);

    GLenum st = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (st != GL_FRAMEBUFFER_COMPLETE) NSLog(@"[GameView] framebuffer incomplete: 0x%x", st);

    glBindRenderbuffer(GL_RENDERBUFFER, _colorRB);
    [_renderer resizeWidth:_bw height:_bh];
    [_scene resizeWidth:_bw height:_bh];
}

- (void)destroyBuffers {
    if (!_context) return;
    [EAGLContext setCurrentContext:_context];
    if (_fbo)     { glDeleteFramebuffers(1, &_fbo);     _fbo = 0; }
    if (_colorRB) { glDeleteRenderbuffers(1, &_colorRB); _colorRB = 0; }
    if (_depthRB) { glDeleteRenderbuffers(1, &_depthRB); _depthRB = 0; }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self layoutButtons];
    if (!_context) return;
    if (_fbo && CGSizeEqualToSize(_lastLayoutSize, self.bounds.size)) return;
    _lastLayoutSize = self.bounds.size;
    [EAGLContext setCurrentContext:_context];
    [self destroyBuffers];
    [self createBuffers];
}

#pragma mark - Цикл

- (void)pause  { _link.paused = YES; glFinish(); [_audio suspend]; }   // GL и звук в фоне запрещены
- (void)resume { _lastTime = 0; _link.paused = _menuVisible; [_audio resume]; }

- (void)drawFrame:(CADisplayLink *)link {
    if (!_context || !_fbo) return;
    [EAGLContext setCurrentContext:_context];

    CFTimeInterval now = link.timestamp;
    float dt = (_lastTime > 0) ? (float)(now - _lastTime) : 0.016f;
    if (dt > 0.1f) dt = 0.1f;
    _lastTime = now;

    glBindFramebuffer(GL_FRAMEBUFFER, _fbo);
    glViewport(0, 0, _bw, _bh);

    if (_sceneMode) {
        if (_playerAlive) [_scene moveForward:-_stickY strafe:_stickX dt:dt];
        {   // слушатель на камере, шаги и приземление
            float eye[3];
            [_scene eyePosition:eye];
            [_audio setListenerPosition:eye yaw:_scene.yaw pitch:_scene.pitch];
            if (_playerAlive && _scene.walkMode) {
                if (_scene.onGround) {
                    float s = sqrtf(_stickX * _stickX + _stickY * _stickY);
                    if (s > 0.2f) {
                        _stepTimer += dt * (0.55f + 0.45f * s);
                        if (_stepTimer > 0.42f) { _stepTimer = 0; [_audio play:@"step"]; }
                    } else _stepTimer = 0.3f;
                    if (_airTime > 0.35f) [_audio play:@"land"];
                    _airTime = 0;
                } else _airTime += dt;
            }
        }
        if (_playerAlive) [_weapons updateWithScene:_scene dt:dt];     // выстрелы по текущему направлению камеры
        else [_weapons setFireHeld:NO];

        // враги: урон по игроку
        float feet[3];
        [_scene playerFeet:feet];
        float dmg = [_bots updateWithScene:_scene playerFeet:feet playerAlive:_playerAlive dt:dt];
        if (_playerAlive && dmg > 0) {
            _health -= dmg;
            _timeSinceDamage = 0;
            _damageFlash = 0.55f;
            if (_hurtCooldown <= 0 && _health > 0) { [_audio play:@"player_hurt"]; _hurtCooldown = 0.35f; }
            if (_health <= 0) {                      // смерть: через 3 с возрождение в точке появления
                _health = 0;
                _playerAlive = NO;
                _deaths++;
                [_bots playerDied];                  // командный бой: очко красным
                _respawnTimer = 3.0f;
                _deathLabel.hidden = NO;
                [_audio play:@"player_death"];
                [_weapons setFireHeld:NO];
            }
        }
        if (_hurtCooldown > 0) _hurtCooldown -= dt;
        if (_playerAlive) {
            _timeSinceDamage += dt;
            if (_timeSinceDamage > 5.0f && _health < 100.0f) _health = fminf(100.0f, _health + 8.0f * dt);   // медленная регенерация
        } else {
            _respawnTimer -= dt;
            if (_respawnTimer <= 0) { [_scene resetCamera]; [self resetPlayerState]; }
        }

        // отклик на попадания игрока
        int hitEvent = [_weapons consumeHitEvent];
        if (hitEvent > 0) {
            _hitMarkerTime = 0.25f;
            UIColor *c = (hitEvent == 2) ? [UIColor colorWithRed:1 green:0.2 blue:0.2 alpha:1] : [UIColor whiteColor];
            _hitBarA.backgroundColor = c; _hitBarB.backgroundColor = c;
        }
        if (_hitMarkerTime > 0) { _hitMarkerTime -= dt; _hitMarker.alpha = fmaxf(0, _hitMarkerTime / 0.25f); }
        else _hitMarker.alpha = 0;
        if (_damageFlash > 0) { _damageFlash -= dt * 1.5f; if (_damageFlash < 0) _damageFlash = 0; }
        _damageOverlay.alpha = _playerAlive ? _damageFlash : 0.45f;       // мёртвым — красный фон

        [_scene draw];
        [_bots drawWithScene:_scene];                // враги (с глубиной сцены)
        [_weapons drawWithScene:_scene];             // следы попаданий, оружие в руках, вспышка

        // командный бой: счёт и конец матча (при достижении лимита боты замирают, через 6 с — возврат в меню)
        BOOL teamMode = (_bots.mode == CGGameModeTeam);
        _scoreLabel.hidden = !teamMode;
        if (teamMode) {
            NSString *sc = [NSString stringWithFormat:@"Синие %d : %d Красные", _bots.blueScore, _bots.redScore];
            if (![sc isEqualToString:_scoreLabel.text]) _scoreLabel.text = sc;
            if (_bots.winner && !_matchOver) {
                _matchOver = YES;
                _matchOverTimer = 6.0f;
                BOOL win = (_bots.winner == 1);
                _resultLabel.text = win ? @"ПОБЕДА!\nСиние победили" : @"ПОРАЖЕНИЕ\nКрасные победили";
                _resultLabel.textColor = win ? [UIColor colorWithRed:0.5f green:1 blue:0.5f alpha:1] : [UIColor colorWithRed:1 green:0.45f blue:0.4f alpha:1];
                _resultLabel.hidden = NO;
                [_weapons setFireHeld:NO];
            }
            if (_matchOver && _matchOverTimer > 0) {
                _matchOverTimer -= dt;
                if (_matchOverTimer <= 0) dispatch_async(dispatch_get_main_queue(), ^{ if (_matchOver) [self onMenuButton]; });
            }
        }

        NSString *healthText = [NSString stringWithFormat:@"HP %d", (int)ceilf(_health)];
        if (![healthText isEqualToString:_lastHealthText]) {
            _healthLabel.text = healthText; _lastHealthText = healthText;
            _healthLabel.textColor = _health > 60 ? [UIColor whiteColor]
                                    : (_health > 30 ? [UIColor colorWithRed:1 green:0.8 blue:0.2 alpha:1]
                                                    : [UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1]);
        }

        NSString *ammoText = _weapons.reloading
            ? [NSString stringWithFormat:@"%@   reloading...", _weapons.weaponTitle]
            : [NSString stringWithFormat:@"%@   %d / %d", _weapons.weaponTitle, _weapons.ammo, _weapons.magSize];
        if (![ammoText isEqualToString:_lastAmmoText]) { _ammoLabel.text = ammoText; _lastAmmoText = ammoText; }
    } else {
        [_renderer updateWithDelta:dt];
        [_renderer draw];
    }

    glBindRenderbuffer(GL_RENDERBUFFER, _colorRB);
    [_context presentRenderbuffer:GL_RENDERBUFFER];
}

@end
