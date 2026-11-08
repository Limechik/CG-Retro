#import <Foundation/Foundation.h>
#import "Collision.h"

// Статическая сцена из .cgs (см. tools/build_scene.py): батчи по материалам и ячейкам сетки,
// небо отдельным проходом, отсечение по пирамиде видимости, свободная камера.
// Все методы вызывать при текущем EAGLContext.
@interface GameScene : NSObject

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) BOOL loaded;

// камера
@property (nonatomic) float yaw;      // радианы, 0 = взгляд вдоль -Z, + = влево
@property (nonatomic) float pitch;    // радианы, + = вверх
@property (nonatomic, readonly) float moveSpeed;   // м/с при полном отклонении стика (полёт)

// режим ходьбы: гравитация, прыжок, коллизии (нужен файл <сцена>.cgc рядом с .cgs)
@property (nonatomic, readonly) BOOL hasCollision;
@property (nonatomic) BOOL walkMode;                // включить можно, только если hasCollision
@property (nonatomic, readonly) BOOL onGround;

// статистика последнего кадра
@property (nonatomic, readonly) NSUInteger batchTotal, batchesDrawn;
@property (nonatomic, readonly) NSUInteger triangleTotal, trianglesDrawn;

- (BOOL)loadFromPath:(NSString *)path name:(NSString *)name;
- (void)unload;
- (void)resetCamera;                  // камера и игрок возвращаются в точку появления
- (void)jump;                         // запрос прыжка (выполнится в ближайшем кадре, если стоим на земле)
- (void)moveForward:(float)fwd strafe:(float)strafe dt:(float)dt;   // fwd/strafe в [-1, 1]
- (void)resizeWidth:(int)w height:(int)h;
- (void)draw;

// --- для оружия и ботов
- (const CGCollision *)collision;                                   // NULL, если коллизии нет
- (void)playerFeet:(float *)out;                                   // точка под ногами игрока (3 float)
- (float)aspect;
- (void)eyePosition:(float *)out;                                   // 3 float
- (void)getView:(float *)view proj:(float *)proj;                   // матрицы последнего кадра (16 float)
- (BOOL)raycastFrom:(const float *)origin dir:(const float *)dir maxDist:(float)maxDist hit:(CGHit *)hit;

@end
