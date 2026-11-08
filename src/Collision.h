// Коллизия и физика игрока на чистом C (без Objective-C, чтобы тестироваться через gcc).
// Данные: .cgc из tools/build_scene.py (треугольники в мировых координатах GL).
#ifndef COLLISION_H
#define COLLISION_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CGCollision CGCollision;

// NULL при ошибке (нет файла, битый заголовок, неверный размер).
CGCollision *cgc_load(const char *path);
void cgc_free(CGCollision *c);
unsigned cgc_triangle_count(const CGCollision *c);
void cgc_bounds(const CGCollision *c, float bmin[3], float bmax[3]);

typedef struct {
    float t;             // расстояние до попадания
    float point[3];      // точка попадания
    float normal[3];     // нормаль поверхности, повёрнутая к стрелку
    unsigned tri;        // индекс треугольника
} CGHit;

// Луч (dir — единичный) на длину maxDist. 1 при попадании (hit заполнен), иначе 0. Обход сетки по XZ (DDA).
int cgc_raycast(const CGCollision *c, const float origin[3], const float dir[3], float maxDist, CGHit *hit);

// 1, если сфера пересекает хоть один треугольник (через сетку, быстро). Для проверки точек появления.
int cgc_sphere_overlaps(const CGCollision *c, const float center[3], float radius);

// Для тестов: тот же луч полным перебором (эталон).
int cgc_debug_raycast_brute(const CGCollision *c, const float origin[3], const float dir[3], float maxDist, CGHit *hit);

// Для тестов: максимальная глубина проникновения сферы (центр c, радиус r) в любой треугольник
// (полный перебор, медленно). 0, если сфера свободна.
float cgc_debug_penetration(const CGCollision *c, const float center[3], float radius);

// Для тестов: число треугольников, которые пересекает отрезок a->b (полный перебор).
int cgc_debug_segment_hits(const CGCollision *c, const float a[3], const float b[3]);

typedef struct {
    float pos[3];        // точка под ногами (центр основания капсулы)
    float vel[3];
    int   onGround;
    // параметры (cgplayer_init ставит значения по умолчанию)
    float radius;        // радиус капсулы
    float height;        // полная высота капсулы
    float eyeHeight;     // высота глаз над ногами
    float walkSpeed;     // м/с
    float jumpSpeed;     // м/с
    float gravity;       // м/с^2
} CGPlayer;

void cgplayer_init(CGPlayer *p, const float feet[3]);

// move: fwd/strafe в [-1, 1]; yaw как у камеры (0 = взгляд вдоль -Z, + = влево); jump != 0 — прыжок.
// col может быть NULL (тогда просто падение без земли).
void cgplayer_update(CGPlayer *p, const CGCollision *col,
                     float fwd, float strafe, float yaw, int jump, float dt);

#ifdef __cplusplus
}
#endif
#endif
