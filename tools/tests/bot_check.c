// Тесты врага: луч по капсуле, сценарии ИИ в синтетическом мире, прогон на реальных сценах.
// gcc -std=c99 -O2 -I../../src bot_check.c ../../src/Bot.c ../../src/Collision.c -o bot_check -lm
// ./bot_check synthetic            | ./bot_check scene <Resources/scenes> <Имя> [секунд]
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>
#include "Bot.h"

static int fails = 0;
#define CHECK(cond, ...) do { if (!(cond)) { fails++; printf("  НЕ ПРОШЛО: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static unsigned rs = 88172645u;
static float rnd(void) { rs ^= rs << 13; rs ^= rs >> 17; rs ^= rs << 5; return (rs & 0xFFFFFF) / 16777216.0f; }

/* ---- запись .cgc из треугольников ---- */
static void write_cgc(const char *path, const float *tris, unsigned n) {
    FILE *f = fopen(path, "wb");
    float mn[3] = { 1e30f, 1e30f, 1e30f }, mx[3] = { -1e30f, -1e30f, -1e30f };
    for (unsigned i = 0; i < n * 3; i++) for (int a = 0; a < 3; a++) {
        float v = tris[i * 3 + a]; if (v < mn[a]) mn[a] = v; if (v > mx[a]) mx[a] = v;
    }
    fwrite("CGC1", 1, 4, f); fwrite(&n, 4, 1, f); fwrite(mn, 4, 3, f); fwrite(mx, 4, 3, f);
    fwrite(tris, 36, n, f); fclose(f);
}
static unsigned add_quad(float *t, unsigned n, const float *a, const float *b, const float *c, const float *d) {
    const float *q[6] = { a, b, c, a, c, d };
    for (int i = 0; i < 6; i++) memcpy(t + (n * 3 + i) * 3 - 0 * 0, q[i], 12);
    return n + 2;
}
static unsigned add_box(float *t, unsigned n, float x0, float x1, float y0, float y1, float z0, float z1) {
    float p[8][3] = { {x0,y0,z0},{x1,y0,z0},{x1,y1,z0},{x0,y1,z0},{x0,y0,z1},{x1,y0,z1},{x1,y1,z1},{x0,y1,z1} };
    n = add_quad(t, n, p[0], p[1], p[2], p[3]); n = add_quad(t, n, p[4], p[5], p[6], p[7]);
    n = add_quad(t, n, p[0], p[1], p[5], p[4]); n = add_quad(t, n, p[3], p[2], p[6], p[7]);
    n = add_quad(t, n, p[0], p[3], p[7], p[4]); n = add_quad(t, n, p[1], p[2], p[6], p[5]);
    return n;
}

/* ---- 1) луч против капсулы: аналитика против сэмплирования ---- */
static void test_capsule(void) {
    int mism = 0, hits = 0, total = 20000;
    for (int i = 0; i < total; i++) {
        float o[3] = { (rnd()-0.5f)*8, (rnd()-0.5f)*6, (rnd()-0.5f)*8 }, d[3];
        float l; do { for (int a = 0; a < 3; a++) d[a] = rnd()*2-1; l = sqrtf(d[0]*d[0]+d[1]*d[1]+d[2]*d[2]); } while (l < 0.1f);
        for (int a = 0; a < 3; a++) d[a] /= l;
        float cx = (rnd()-0.5f)*2, cz = (rnd()-0.5f)*2, y0 = 0.5f, y1 = 1.3f, r = 0.55f;
        // начало внутри капсулы не рассматриваем
        float cy = fminf(fmaxf(o[1], y0), y1);
        if ((o[0]-cx)*(o[0]-cx) + (o[1]-cy)*(o[1]-cy) + (o[2]-cz)*(o[2]-cz) < r*r) continue;
        float t = 0, hy;
        int a = cg_ray_vcapsule(o, d, cx, cz, y0, y1, r, 30.0f, &t, &hy);
        // эталон: мелкий шаг по лучу
        int b = 0; float tb = 0;
        for (float s = 0; s < 30.0f; s += 0.004f) {
            float px = o[0]+d[0]*s, py = o[1]+d[1]*s, pz = o[2]+d[2]*s;
            float qy = fminf(fmaxf(py, y0), y1);
            if ((px-cx)*(px-cx) + (py-qy)*(py-qy) + (pz-cz)*(pz-cz) <= r*r) { b = 1; tb = s; break; }
        }
        hits += b;
        if (a != b) mism++;                                       // попал/мимо не совпали
        else if (a && fabsf(t - tb) > 0.02f) mism++;              // совпали, но расстояния разные
    }
    printf("луч-капсула: %d лучей, попаданий %d, расхождений %d\n", total, hits, mism);
    CHECK(mism <= 8, "слишком много расхождений луча с капсулой: %d", mism);    // допуск на касательные лучи
}

/* ---- 2) синтетический мир ---- */
static CGCollision *make_world(const char *path, int wall) {
    static float tris[64 * 9];
    unsigned n = 0;
    float a[3] = {-100,0,-100}, b[3] = {100,0,-100}, c[3] = {100,0,100}, d[3] = {-100,0,100};
    n = add_quad(tris, n, a, b, c, d);
    if (wall) n = add_box(tris, n, -30, 30, 0, 4, -12.25f, -11.75f);
    write_cgc(path, tris, n);
    return cgc_load(path);
}

static void test_open_field(void) {
    CGCollision *col = make_world("/tmp/cg_world_open.cgc", 0);
    CHECK(col != NULL, "не загрузился синтетический мир");
    float player[3] = { 0, 0, 0 }, feet[3] = { 0, 0.05f, -25 };
    CGBot bot; cgbot_init(&bot, feet, 777);
    int shots = 0, hits = 0, attackAt = -1, frames = 20 * 60; float totalDmg = 0; float maxY = 0;
    for (int f = 0; f < frames; f++) {
        CGBotEvents ev; cgbot_update(&bot, col, player, 1, 1.0f / 60.0f, &ev);
        shots += ev.shotFired; hits += ev.playerHit; totalDmg += ev.damage;
        if (bot.state == BOT_ATTACK && attackAt < 0) attackAt = f;
        if (bot.body.pos[1] > maxY) maxY = bot.body.pos[1];
    }
    float dx = bot.body.pos[0] - player[0], dz = bot.body.pos[2] - player[2];
    printf("открытое поле: атака с %.1f с, выстрелов %d, попаданий %d (%.0f%%), расстояние %.1f м, состояние %d\n",
           attackAt / 60.0f, shots, hits, shots ? 100.0f * hits / shots : 0, sqrtf(dx*dx + dz*dz), bot.state);
    CHECK(attackAt >= 0 && attackAt < 8 * 60, "бот должен начать атаку за 8 с (%d)", attackAt);
    CHECK(shots >= 10, "должно быть >= 10 выстрелов за 20 с (%d)", shots);
    CHECK(hits >= 1 && hits < shots, "попадания должны быть, но не все (%d из %d)", hits, shots);
    CHECK(maxY < 0.5f, "бот взлетел (y=%.2f)", maxY);
    CHECK(sqrtf(dx*dx + dz*dz) > 6.0f && sqrtf(dx*dx + dz*dz) < 23.0f, "бот должен остановиться на дистанции стрельбы");
    cgc_free(col);
}

static void test_wall(void) {
    CGCollision *col = make_world("/tmp/cg_world_wall.cgc", 1);
    float player[3] = { 0, 0, 0 }, feet[3] = { 0, 0.05f, -25 };
    CGBot bot; cgbot_init(&bot, feet, 4242);
    int shots = 0, attacked = 0; float maxZ = -1e9f;
    for (int f = 0; f < 15 * 60; f++) {
        CGBotEvents ev; cgbot_update(&bot, col, player, 1, 1.0f / 60.0f, &ev);
        shots += ev.shotFired; if (bot.state == BOT_ATTACK) attacked = 1;
        if (bot.body.pos[2] > maxZ) maxZ = bot.body.pos[2];
    }
    printf("стена между ними: выстрелов %d, атаковал: %d, ближайшая точка к стене z=%.2f (стена на z=-12.25)\n", shots, attacked, maxZ);
    CHECK(shots == 0, "через стену стрелять нельзя (%d)", shots);
    CHECK(!attacked, "через стену атаковать нельзя");
    CHECK(maxZ < -12.25f, "бот прошёл сквозь стену (z=%.2f)", maxZ);
    cgc_free(col);
}

static void test_damage(void) {
    float feet[3] = { 0, 0, 0 }; CGBot b; cgbot_init(&b, feet, 1);
    float o[3] = { 0, 1.35f, 5 }, d[3] = { 0, 0, -1 }, t; int head;
    CHECK(cgbot_ray_hit(&b, o, d, 20, &t, &head) && !head && fabsf(t - (5 - CGBOT_HIT_RADIUS)) < 0.01f, "попадание в корпус t=%.3f", t);
    float o2[3] = { 0, 1.6f, 5 };
    CHECK(cgbot_ray_hit(&b, o2, d, 20, &t, &head) && head, "попадание в голову");
    float o3[3] = { 2, 1.0f, 5 };
    CHECK(!cgbot_ray_hit(&b, o3, d, 20, &t, &head), "промах мимо");
    int died = 0, n = 0;
    while (!died && n < 20) { died = cgbot_damage(&b, 16); n++; }
    printf("урон 16 за удар: бот умер на %d-м ударе (здоровье 100)\n", n);
    CHECK(n == 7 && b.state == BOT_DEAD, "должно хватить 7 ударов (%d)", n);
    CHECK(!cgbot_ray_hit(&b, o, d, 20, &t, &head), "по мёртвому попадать нельзя");
    CHECK(cgbot_damage(&b, 50) == 0, "повторная смерть");
    float p[3] = { 0, 0, 0 }; CGBotEvents ev;
    for (int i = 0; i < 60; i++) cgbot_update(&b, NULL, p, 1, 1.0f / 60.0f, &ev);
    CHECK(b.deathT >= 0.99f && !ev.shotFired, "анимация смерти завершена (%.2f)", b.deathT);
}

/* ---- 3) реальные сцены ---- */
static int run_scene(const char *dir, const char *name, float seconds) {
    char pc[512], ps[512];
    snprintf(pc, sizeof pc, "%s/%s.cgc", dir, name); snprintf(ps, sizeof ps, "%s/%s.cgs", dir, name);
    CGCollision *col = cgc_load(pc);
    if (!col) { printf("%s: cgc_load FAILED\n", name); return 1; }
    FILE *f = fopen(ps, "rb");
    uint8_t hdr[48];
    if (!f || fread(hdr, 1, 48, f) != 48) return 2;
    fclose(f);
    float h9[9]; memcpy(h9, hdr + 12, 36);
    float bmin[3], bmax[3]; cgc_bounds(col, bmin, bmax);

    // игрок встаёт на землю у точки появления
    CGPlayer pl; float pf[3] = { h9[6], h9[7] - 1.7f, h9[8] }; cgplayer_init(&pl, pf);
    for (int i = 0; i < 300; i++) cgplayer_update(&pl, col, 0, 0, 0, 0, 1.0f / 60.0f);

    char pp[512]; snprintf(pp, sizeof pp, "%s/%s.cgp", dir, name);
    unsigned npts = 0; float *pts = cgbot_load_spawns(pp, &npts);
    int nb = 4; CGBot bots[4]; int spawned = 0, fromList = 0; unsigned rng = 99991;
    for (int i = 0; i < nb; i++) {
        float sp[3]; int ok = cgbot_pick_spawn(col, pts, npts, pl.pos, 12.0f, 90.0f, &rng, sp);
        if (ok) fromList++;
        else ok = cgbot_sample_spawn(col, pl.pos, 15.0f, 70.0f, &rng, sp);
        if (ok) { cgbot_init(&bots[spawned], sp, 1000 + i * 37); spawned++; }
    }
    printf("  точек в .cgp: %u, ботов из списка: %d из %d\n", npts, fromList, spawned);
    free(pts);
    float worstPen = 0; int tunnels = 0, fell = 0, shots = 0, hits = 0; int stateFrames[4] = { 0 };
    int frames = (int)(seconds * 60);
    for (int fr = 0; fr < frames; fr++) {
        for (int i = 0; i < spawned; i++) {
            CGBot *b = &bots[i];
            float before[3] = { b->body.pos[0], b->body.pos[1], b->body.pos[2] };
            CGBotEvents ev; cgbot_update(b, col, pl.pos, 1, 1.0f / 60.0f, &ev);
            shots += ev.shotFired; hits += ev.playerHit; stateFrames[b->state]++;
            if (b->body.pos[1] < bmin[1] - 40) fell++;
            if (fr % 2 == 0) {
                float r = b->body.radius, ys[3] = { r, b->body.height * 0.5f, b->body.height - r };
                for (int s = 0; s < 3; s++) {
                    float a[3] = { before[0], before[1] + ys[s], before[2] }, c[3] = { b->body.pos[0], b->body.pos[1] + ys[s], b->body.pos[2] };
                    if (cgc_debug_segment_hits(col, a, c)) {
                        tunnels++;
                        if (getenv("TUNNELS"))
                            printf("    туннель: кадр %d бот %d сфера %d state=%d (%.2f,%.2f,%.2f)->(%.2f,%.2f,%.2f) vel(%.1f,%.1f,%.1f) ground=%d\n",
                                   fr, i, s, b->state, a[0], a[1], a[2], c[0], c[1], c[2], b->body.vel[0], b->body.vel[1], b->body.vel[2], b->body.onGround);
                        break;
                    }
                }
            }
            if (fr % 30 == 0) {
                float r = b->body.radius, ys[3] = { r, b->body.height * 0.5f, b->body.height - r };
                for (int s = 0; s < 3; s++) {
                    float ctr[3] = { b->body.pos[0], b->body.pos[1] + ys[s], b->body.pos[2] };
                    float d = cgc_debug_penetration(col, ctr, r); if (d > worstPen) worstPen = d;
                }
            }
        }
    }
    float tot = (float)(frames * (spawned ? spawned : 1));
    printf("%-11s ботов %d, %.0f с: туннелирований %d, упало %d, макс. проникновение %.3f м; патруль %.0f%% погоня %.0f%% атака %.0f%%, выстрелов %d (попаданий %d)  %s\n",
           name, spawned, seconds, tunnels, fell, worstPen, 100*stateFrames[0]/tot, 100*stateFrames[1]/tot, 100*stateFrames[2]/tot, shots, hits,
           (tunnels == 0 && worstPen < 0.12f && spawned > 0) ? "OK" : "ПРОБЛЕМА");
    int ok = (tunnels == 0 && worstPen < 0.12f && spawned > 0);
    cgc_free(col);
    return ok ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc >= 2 && strcmp(argv[1], "synthetic") == 0) {
        test_capsule(); test_open_field(); test_wall(); test_damage();
        printf(fails ? "ИТОГ: ЕСТЬ ОШИБКИ (%d)\n" : "ИТОГ: синтетические тесты пройдены\n", fails);
        return fails ? 1 : 0;
    }
    if (argc >= 4 && strcmp(argv[1], "scene") == 0) return run_scene(argv[2], argv[3], argc > 4 ? (float)atof(argv[4]) : 60.0f);
    return 2;
}
