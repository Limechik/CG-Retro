// Тест логики оружия.  gcc -std=c99 -O2 -I../../src weapon_check.c ../../src/Weapon.c -o weapon_check -lm
#include <stdio.h>
#include <math.h>
#include "Weapon.h"

static int fails = 0;
#define CHECK(cond, ...) do { if (!(cond)) { fails++; printf("  НЕ ПРОШЛО: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static CGWeaponDef mk(int automatic, float interval, int mag, float reload) {
    CGWeaponDef d = {0}; d.damage = 10; d.interval = interval; d.spreadX = d.spreadY = 0; d.pellets = 1;
    d.magSize = mag; d.reloadTime = reload; d.automatic = automatic; d.range = 100;
    return d;
}

// Симуляция: держим огонь `seconds`, возвращаем число выстрелов.
static int hold(CGWeaponState *s, const CGWeaponDef *d, float seconds, float dt, int *reloads) {
    int shots = 0; float t = 0; int first = 1;
    while (t < seconds) {
        CGWeaponEvents ev;
        cgweapon_update(s, d, 1, first, 0, dt, &ev);
        first = 0; shots += ev.shots; if (reloads) *reloads += ev.reloadFinished; t += dt;
    }
    return shots;
}

int main(void) {
    // 1) темп стрельбы не зависит от fps
    float dts[] = { 1/120.0f, 1/60.0f, 1/30.0f, 1/20.0f, 1/10.0f };
    for (int i = 0; i < 5; i++) {
        CGWeaponDef d = mk(1, 0.1f, 100000, 1); CGWeaponState s; cgweapon_init(&s, &d, 1);
        int shots = hold(&s, &d, 5.0f, dts[i], NULL);
        printf("auto 10 выстр/с, dt=%.4f: %d выстрелов за 5 с\n", dts[i], shots);
        CHECK(shots >= 49 && shots <= 51, "ожидалось ~50, получено %d", shots);
    }
    // 2) патроны и перезарядка: магазин 30, перезарядка 2 с
    {
        CGWeaponDef d = mk(1, 0.1f, 30, 2.0f); CGWeaponState s; cgweapon_init(&s, &d, 1);
        int reloads = 0, shots = hold(&s, &d, 3.0f, 1/60.0f, &reloads);
        printf("магазин 30: за 3 с %d выстрелов, перезарядок завершено %d, патронов %d\n", shots, reloads, s.ammo);
        CHECK(shots == 30, "в первом магазине должно быть ровно 30 выстрелов, а не %d", shots);
        CHECK(reloads == 0, "перезарядка не должна завершиться до 2 с");
        shots += hold(&s, &d, 2.5f, 1/60.0f, &reloads);
        CHECK(reloads == 1, "перезарядка должна завершиться 1 раз, а не %d", reloads);
        CHECK(shots > 30, "после перезарядки стрельба должна продолжиться");
    }
    // 3) во время перезарядки не стреляем; ручная перезарядка не при полном магазине
    {
        CGWeaponDef d = mk(0, 0.2f, 8, 1.5f); CGWeaponState s; cgweapon_init(&s, &d, 1);
        CGWeaponEvents ev; cgweapon_update(&s, &d, 0, 0, 1, 1/60.0f, &ev);
        CHECK(!ev.reloadStarted, "полный магазин: перезарядка не нужна");
        cgweapon_update(&s, &d, 0, 1, 0, 1/60.0f, &ev); CHECK(ev.shots == 1 && s.ammo == 7, "выстрел 1");
        cgweapon_update(&s, &d, 0, 0, 1, 1/60.0f, &ev); CHECK(ev.reloadStarted, "ручная перезарядка");
        for (int i = 0; i < 30; i++) { cgweapon_update(&s, &d, 0, 1, 0, 1/60.0f, &ev); CHECK(ev.shots == 0, "стреляет во время перезарядки"); }
    }
    // 4) одиночные: одно нажатие — один выстрел, удержание не стреляет, буфер нажатия
    {
        CGWeaponDef d = mk(0, 0.5f, 50, 1); CGWeaponState s; cgweapon_init(&s, &d, 1);
        CGWeaponEvents ev; int shots = 0;
        cgweapon_update(&s, &d, 1, 1, 0, 1/60.0f, &ev); shots += ev.shots;
        for (int i = 0; i < 120; i++) { cgweapon_update(&s, &d, 1, 0, 0, 1/60.0f, &ev); shots += ev.shots; }
        printf("одиночное оружие: 1 нажатие + удержание 2 с -> %d выстрел(ов)\n", shots);
        CHECK(shots == 1, "удержание не должно стрелять одиночным оружием (%d)", shots);
        // нажатие за 0.1 с до конца паузы сработает
        CGWeaponState s2; cgweapon_init(&s2, &d, 1); shots = 0;
        cgweapon_update(&s2, &d, 0, 1, 0, 1/60.0f, &ev); shots += ev.shots;
        for (int i = 0; i < 24; i++) { cgweapon_update(&s2, &d, 0, 0, 0, 1/60.0f, &ev); shots += ev.shots; }   // ~0.4 с
        cgweapon_update(&s2, &d, 0, 1, 0, 1/60.0f, &ev); shots += ev.shots;                                      // нажали раньше конца паузы
        for (int i = 0; i < 12; i++) { cgweapon_update(&s2, &d, 0, 0, 0, 1/60.0f, &ev); shots += ev.shots; }
        CHECK(shots == 2, "буферизованное нажатие должно дать второй выстрел (%d)", shots);
        // темп одиночных при спаме нажатий: не быстрее интервала
        CGWeaponState s3; cgweapon_init(&s3, &d, 1); shots = 0;
        for (int i = 0; i < 600; i++) { cgweapon_update(&s3, &d, 1, 1, 0, 1/60.0f, &ev); shots += ev.shots; }
        printf("одиночное оружие, спам нажатий 10 с (интервал 0.5): %d выстрелов\n", shots);
        CHECK(shots <= 21 && shots >= 19, "темп при спаме: %d", shots);
    }
    // 5) разброс: углы в пределах ±spread/2, среднее ~0
    {
        CGWeaponDef d = mk(1, 0.1f, 50, 1); d.spreadX = 3.0f; d.spreadY = 6.0f; CGWeaponState s; cgweapon_init(&s, &d, 7);
        float sumP = 0, sumY = 0, maxP = 0, maxY = 0; int N = 20000;
        for (int i = 0; i < N; i++) {
            float dir[3]; cgweapon_shot_dir(&d, &s, 0.7f, 0.2f, dir);
            float len = sqrtf(dir[0]*dir[0] + dir[1]*dir[1] + dir[2]*dir[2]);
            CHECK(fabsf(len - 1) < 1e-4f, "направление не единичное");
            float p = asinf(dir[1]) - 0.2f, y = atan2f(-dir[0], -dir[2]) - 0.7f;
            sumP += p; sumY += y; if (fabsf(p) > maxP) maxP = fabsf(p); if (fabsf(y) > maxY) maxY = fabsf(y);
        }
        const float DEG = 3.14159265f / 180.0f;
        printf("разброс 3°x6°: макс тангаж %.2f° (лимит 1.5°), макс рыск. %.2f° (лимит 3°), среднее %.3f°/%.3f°\n",
               maxP / DEG, maxY / DEG, sumP / N / DEG, sumY / N / DEG);
        CHECK(maxP <= 1.5f * DEG * 1.001f, "тангаж за пределами");
        CHECK(maxY <= 3.0f * DEG * 1.001f, "рыскание за пределами");
        CHECK(fabsf(sumP / N) < 0.05f * DEG && fabsf(sumY / N) < 0.1f * DEG, "смещённое среднее");
        // нулевой разброс = точное направление камеры
        d.spreadX = d.spreadY = 0; float dir[3]; cgweapon_shot_dir(&d, &s, 0.0f, 0.0f, dir);
        CHECK(fabsf(dir[0]) < 1e-6f && fabsf(dir[1]) < 1e-6f && fabsf(dir[2] + 1) < 1e-6f, "без разброса луч должен идти вдоль -Z");
    }
    printf(fails ? "\nИТОГ: ЕСТЬ ОШИБКИ (%d)\n" : "\nИТОГ: все проверки пройдены\n", fails);
    return fails ? 1 : 0;
}
