#import <Foundation/Foundation.h>

@class GameScene, AudioEngine;

// Режимы игры: «Все против всех» — боты охотятся только на игрока; «Командный бой» — синие (игрок и 2 бота) против
// красных (3 бота), боты стреляют друг в друга, у каждой команды счёт убийств до scoreLimit.
typedef enum { CGGameModeFFA = 0, CGGameModeTeam = 1 } CGGameMode;

// Враги-курицы: спавн по точкам сцены, обновление ИИ (Bot.c), рендер риг-модели с анимацией (Rig.c),
// смерть и возрождение, попадания лучом игрока. Все методы — при текущем EAGLContext.
@interface BotController : NSObject

@property (nonatomic) int desiredCount;               // 0...6; при смене боты пересоздаются (только в режиме «Все против всех»)
@property (nonatomic) CGGameMode mode;                // задаётся до startForScene:
@property (nonatomic, readonly) int blueScore, redScore;   // убийства команд (командный бой)
@property (nonatomic, readonly) int winner;           // 0 — матч идёт, 1 — победили синие (команда игрока), 2 — красные
@property (nonatomic, readonly) int scoreLimit;       // до скольких убийств идёт матч
@property (nonatomic, readonly) int aliveCount;
@property (nonatomic, readonly) int kills;
@property (nonatomic, assign) AudioEngine *audio;    // звук выстрелов и смерти врагов (владелец — GameView)

- (BOOL)setup;                                         // программа, риг, меши, текстуры
- (void)startForScene:(GameScene *)scene spawnFile:(NSString *)path;
- (void)stop;                                          // убрать всех (перед выгрузкой сцены)
- (void)playerDied;                                    // игрока убили: очко красным (командный бой)

// Возвращает суммарный урон по игроку за кадр.
- (float)updateWithScene:(GameScene *)scene playerFeet:(const float *)feet playerAlive:(BOOL)alive dt:(float)dt;
- (void)drawWithScene:(GameScene *)scene;

// Попадание луча игрока по ближайшему боту ближе maxDist. YES — попал (урон уже применён).
- (BOOL)hitWithOrigin:(const float *)origin dir:(const float *)dir maxDist:(float)maxDist damage:(float)damage
             distance:(float *)distance head:(BOOL *)head killed:(BOOL *)killed;

@end
