#include "Weapon.h"
#include <math.h>
#include <string.h>

static float frand01(CGWeaponState *s) {
    unsigned x = s->rng ? s->rng : 2463534242u;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    s->rng = x;
    return (float)(x & 0xFFFFFF) / 16777216.0f;
}

void cgweapon_init(CGWeaponState *s, const CGWeaponDef *d, unsigned seed) {
    memset(s, 0, sizeof *s);
    s->ammo = d->magSize;
    s->rng = seed ? seed : 2463534242u;
}

static void start_reload(CGWeaponState *s, const CGWeaponDef *d, CGWeaponEvents *ev) {
    if (s->reloadLeft > 0 || s->ammo >= d->magSize) return;
    s->reloadLeft = d->reloadTime > 0 ? d->reloadTime : 0.001f;
    ev->reloadStarted = 1;
}

void cgweapon_update(CGWeaponState *s, const CGWeaponDef *d,
                     int fireHeld, int firePressed, int reload, float dt, CGWeaponEvents *ev) {
    memset(ev, 0, sizeof *ev);
    if (dt < 0) dt = 0;
    if (dt > 0.25f) dt = 0.25f;

    // перезарядка
    if (s->reloadLeft > 0) {
        s->reloadLeft -= dt;
        if (s->reloadLeft <= 0) {
            s->reloadLeft = 0;
            s->ammo = d->magSize;
            ev->reloadFinished = 1;
        }
    } else if (reload) {
        start_reload(s, d, ev);
    }

    if (firePressed) s->pressBuffer = 0.15f;            // одиночный выстрел не теряется, если нажали чуть раньше конца паузы
    else if (s->pressBuffer > 0) { s->pressBuffer -= dt; if (s->pressBuffer < 0) s->pressBuffer = 0; }

    // в простое кредита времени нет (иначе первый кадр стреляет дважды); во время ожидания остаток переносится
    float cd = (s->cooldown > 0) ? s->cooldown - dt : 0.0f;
    int wants = d->automatic ? (fireHeld || firePressed) : (s->pressBuffer > 0);
    int fired = 0;

    if (s->reloadLeft > 0) {                            // во время перезарядки не стреляем
        s->cooldown = cd > 0 ? cd : 0;
        return;
    }
    while (wants && cd <= 0 && fired < 4) {
        if (s->ammo <= 0) {                             // сухой выстрел -> автоперезарядка
            if (firePressed || s->pressBuffer > 0 || fireHeld) ev->dryFire = 1;
            start_reload(s, d, ev);
            s->pressBuffer = 0;
            break;
        }
        s->ammo--;
        fired++;
        cd += d->interval;
        if (!d->automatic) { s->pressBuffer = 0; wants = 0; }
    }
    ev->shots = fired;
    if (fired && s->ammo <= 0) start_reload(s, d, ev);  // опустел магазин — перезаряжаемся сами
    s->cooldown = cd > 0 ? cd : 0;
}

void cgweapon_shot_dir(const CGWeaponDef *d, CGWeaponState *s, float yaw, float pitch, float dir[3]) {
    const float DEG = 3.14159265f / 180.0f;
    float p = pitch + d->spreadX * (frand01(s) - 0.5f) * DEG;
    float y = yaw   + d->spreadY * (frand01(s) - 0.5f) * DEG;
    float cp = cosf(p);
    dir[0] = -sinf(y) * cp;
    dir[1] = sinf(p);
    dir[2] = -cosf(y) * cp;
}
