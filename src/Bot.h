// Враг-курица: физика, ИИ (патруль, погоня, стрельба), попадания, смерть. Чистый C, без графики.
// Направление камеры/тела: yaw = 0 — лицом к -Z, положительный yaw поворачивает влево (как у игрока).
#ifndef BOT_H
#define BOT_H

#include "Collision.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum { BOT_WANDER = 0, BOT_CHASE, BOT_ATTACK, BOT_DEAD } CGBotState;

typedef struct {
    CGPlayer body;           // ноги, скорость, земля (та же физика, что у игрока)
    float yaw;
    int   state;
    float health;
    float stateTime;
    float wanderYaw, wanderTimer;
    float reaction;          // задержка реакции перед погоней
    float fireTimer;
    float loseSightTimer;
    float animTime, runBlend, deathT;   // для рендера
    float stuckTimer, intentTimer, lastX, lastZ;   // intentTimer: сколько из окна проверки бот пытался идти
    int   stuckCount, strafeDir;
    float strafeTimer;
    float hitFlash;          // красная вспышка после попадания (секунды)
    float shootAnim;         // отдача оружия после выстрела (секунды)
    int   alerted;           // получил урон: знает, где игрок
    unsigned rng;
} CGBot;

typedef struct {
    int   shotFired;         // бот выстрелил в этом кадре
    float shotOrigin[3];     // откуда (дуло ~ уровень глаз)
    float shotDir[3];        // куда (единичный, с разбросом)
    int   playerHit;         // пуля попала в игрока
    float damage;            // урон по игроку
    int   died;              // умер в этом кадре
} CGBotEvents;

typedef struct {
    float maxHealth;
    float walkSpeed, runSpeed, strafeSpeed;
    float turnRate;          // рад/с
    float sightRange, hearRange, fov;   // fov — половина угла обзора, рад
    float attackRange;
    float fireInterval;      // с между выстрелами
    float baseSpread, spreadPerMeter;   // градусы
    float damage;            // за попадание
    float reactionTime;
    float bodyRadius, bodyHeight;       // физика
} CGBotParams;

const CGBotParams *cgbot_params(void);

// Попадания по боту
#define CGBOT_HIT_RADIUS 0.55f
#define CGBOT_HIT_Y0 0.55f       // нижний центр капсулы над ногами
#define CGBOT_HIT_Y1 1.25f       // верхний центр
#define CGBOT_HEAD_Y 1.35f       // выше — попадание в голову

void cgbot_init(CGBot *b, const float feet[3], unsigned seed);

// Один шаг. playerFeet — точка под ногами игрока; playerAlive — жив ли игрок.
void cgbot_update(CGBot *b, const CGCollision *col, const float playerFeet[3], int playerAlive,
                  float dt, CGBotEvents *ev);

// Луч по боту (живому). 1 при попадании: t — расстояние, head — попали в голову.
int cgbot_ray_hit(const CGBot *b, const float origin[3], const float dir[3], float maxDist, float *t, int *head);

// Урон от игрока. Возвращает 1, если бот умер от этого удара.
int cgbot_damage(CGBot *b, float damage);

// Луч против вертикальной капсулы (ось вдоль Y). Для тестов и попаданий по игроку.
int cg_ray_vcapsule(const float o[3], const float d[3], float cx, float cz, float y0, float y1, float r,
                    float tmax, float *t, float *hitY);

// Точки появления из .cgp (tools/build_scene.py): массив float[count*3] (ноги, GL-координаты). NULL при ошибке.
// Освободить через free().
float *cgbot_load_spawns(const char *path, unsigned *count);

// Выбор точки из списка: расстояние до avoid в [minDist, maxDist] и свободная капсула. 1 при успехе.
// Если список пуст или ничего не подошло — вызывающий может взять cgbot_sample_spawn.
int cgbot_pick_spawn(const CGCollision *col, const float *points, unsigned count, const float avoid[3],
                     float minDist, float maxDist, unsigned *rng, float out[3]);

// Случайная точка появления на ходибельной поверхности вдали от avoid: [minDist, maxDist].
// 1 при успехе. Пол ищется лучом сверху вниз, проверяются нормаль и запас по высоте.
int cgbot_sample_spawn(const CGCollision *col, const float avoid[3], float minDist, float maxDist,
                       unsigned *rng, float out[3]);

#ifdef __cplusplus
}
#endif
#endif
