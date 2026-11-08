// Тест хитскана: cgc_raycast (DDA по сетке) должен совпадать с полным перебором.
// gcc -std=c99 -O2 -I../../src ray_check.c ../../src/Collision.c -o ray_check -lm
// ./ray_check <Resources/scenes> <Имя> [число лучей]
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "Collision.h"

static unsigned rng = 2463534242u;
static float frand(void) { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return (rng & 0xFFFFFF) / 16777216.0f; }

int main(int argc, char **argv) {
    if (argc < 3) return 2;
    char path[512]; snprintf(path, sizeof path, "%s/%s.cgc", argv[1], argv[2]);
    int n = argc > 3 ? atoi(argv[3]) : 20000;
    CGCollision *c = cgc_load(path);
    if (!c) { printf("%s: load failed\n", argv[2]); return 1; }
    float bmin[3], bmax[3]; cgc_bounds(c, bmin, bmax);
    int hits = 0, mismatchHit = 0, mismatchT = 0, badNormal = 0;
    float worstDt = 0;
    for (int i = 0; i < n; i++) {
        float o[3], d[3];
        // начало: внутри (80%) или чуть снаружи габаритов (20%)
        float m = (i % 5 == 0) ? 30.0f : 0.0f;
        for (int a = 0; a < 3; a++) o[a] = bmin[a] - m + frand() * (bmax[a] - bmin[a] + 2 * m);
        float l;
        do { for (int a = 0; a < 3; a++) d[a] = frand() * 2 - 1; l = sqrtf(d[0]*d[0] + d[1]*d[1] + d[2]*d[2]); } while (l < 0.1f);
        for (int a = 0; a < 3; a++) d[a] /= l;
        if (i % 7 == 0) { d[0] = d[2] = 0; d[1] = (i % 2) ? 1.0f : -1.0f; }        // строго вертикальные лучи
        if (i % 11 == 0) { d[1] = 0; l = sqrtf(d[0]*d[0] + d[2]*d[2]); if (l > 1e-3f) { d[0] /= l; d[2] /= l; } }   // горизонтальные
        float maxd = (i % 3 == 0) ? 40.0f : 400.0f;
        CGHit a, b;
        int ha = cgc_raycast(c, o, d, maxd, &a);
        int hb = cgc_debug_raycast_brute(c, o, d, maxd, &b);
        hits += hb;
        if (ha != hb) { mismatchHit++; continue; }
        if (ha) {
            float dt = fabsf(a.t - b.t);
            if (dt > worstDt) worstDt = dt;
            if (dt > 1e-3f) mismatchT++;
            float dn = a.normal[0]*d[0] + a.normal[1]*d[1] + a.normal[2]*d[2];
            if (dn > 1e-4f) badNormal++;                                    // нормаль должна смотреть к стрелку
        }
    }
    printf("%-12s лучей=%d попаданий=%d  расхождений попал/мимо=%d  расхождений по t=%d (макс %.5f)  нормали не к стрелку=%d  %s\n",
           argv[2], n, hits, mismatchHit, mismatchT, worstDt, badNormal,
           (mismatchHit == 0 && mismatchT == 0 && badNormal == 0) ? "OK" : "ПРОБЛЕМА");
    cgc_free(c);
    return (mismatchHit == 0 && mismatchT == 0 && badNormal == 0) ? 0 : 1;
}
