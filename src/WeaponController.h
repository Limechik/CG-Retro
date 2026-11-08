#import <Foundation/Foundation.h>

@class GameScene, BotController, AudioEngine;

// Оружие игрока: выбор ствола, стрельба лучом по коллизии сцены (логика в Weapon.c), оружие в руках
// с отдачей и перезарядкой, дульная вспышка, следы попаданий. Все методы — при текущем EAGLContext.
@interface WeaponController : NSObject

@property (nonatomic, readonly) NSString *weaponTitle;
@property (nonatomic, readonly) int ammo;
@property (nonatomic, readonly) int magSize;
@property (nonatomic, readonly) BOOL reloading;
@property (nonatomic, readonly) NSUInteger weaponCount;
@property (nonatomic, readonly) NSUInteger weaponIndex;
@property (nonatomic, assign) BotController *bots;     // кого можно поразить (владелец — GameView)
@property (nonatomic, assign) AudioEngine *audio;      // звук выстрелов, перезарядки, попаданий (владелец — GameView)

- (BOOL)setup;

- (void)selectWeaponAtIndex:(NSUInteger)i;   // выбрать оружие по индексу в weapons.plist (из магазина)
- (void)nextWeapon;
- (void)prevWeapon;
- (void)setFireHeld:(BOOL)held;     // кнопка огня удерживается
- (void)pressFire;                  // нажатие (для одиночных)
- (void)requestReload;

// Логика выстрелов и анимации. Вызывать до [scene draw].
- (void)updateWithScene:(GameScene *)scene dt:(float)dt;
// Следы попаданий, оружие в руках, вспышка. Вызывать после [scene draw].
- (void)drawWithScene:(GameScene *)scene;

// 0 — попаданий не было, 1 — попали во врага, 2 — убили (после вызова событие сбрасывается).
- (int)consumeHitEvent;

- (void)clearDecals;                // при смене сцены

@end
