// Логика оружия на чистом C: темп стрельбы, патроны, перезарядка, разброс. Без графики и звука.
#ifndef WEAPON_H
#define WEAPON_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char  name[24];        // идентификатор оружия
    float damage;          // урон одной пули/дробинки
    float interval;        // секунд между выстрелами
    float spreadX, spreadY;// разброс в градусах (полный размах по тангажу и рысканью), как errorDelta в игре
    int   pellets;         // пуль за выстрел (дробовики > 1)
    int   magSize;         // патронов в магазине
    float reloadTime;      // секунд
    int   automatic;       // 1 — стрельба очередью при зажатой кнопке, 0 — по одному нажатию
    float range;           // максимальная дальность, м
    float kickPitch;       // подброс камеры за выстрел, градусов
} CGWeaponDef;

typedef struct {
    int   ammo;
    float cooldown;        // секунд до следующего выстрела
    float reloadLeft;      // > 0 — идёт перезарядка
    float pressBuffer;     // нажатие, дождавшееся конца паузы (для одиночных)
    unsigned rng;          // состояние генератора разброса
} CGWeaponState;

typedef struct {
    int shots;             // выстрелов за этот кадр (может быть > 1 при низком fps)
    int dryFire;           // нажали, а патронов нет
    int reloadStarted;
    int reloadFinished;
} CGWeaponEvents;

void cgweapon_init(CGWeaponState *s, const CGWeaponDef *d, unsigned seed);

// fireHeld — кнопка удерживается; firePressed — нажатие произошло с прошлого вызова; reload — запрос перезарядки.
void cgweapon_update(CGWeaponState *s, const CGWeaponDef *d,
                     int fireHeld, int firePressed, int reload, float dt, CGWeaponEvents *ev);

// Единичный вектор выстрела: направление камеры (yaw, pitch) + разброс. Как в BaseWeaponScript:
// угол += errorDelta * (random - 0.5).
void cgweapon_shot_dir(const CGWeaponDef *d, CGWeaponState *s, float yaw, float pitch, float dir[3]);

#ifdef __cplusplus
}
#endif
#endif
