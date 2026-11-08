// Тест физики игрока на реальных сценах.
// gcc -std=c99 -O2 -I../../src player_check.c ../../src/Collision.c -o player_check -lm
// ./player_check <Resources/scenes> <Имя>   (без .cgs/.cgc)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>
#include "Collision.h"

// Сколько треугольников пересекает отрезок a->b (туннелирование центра сферы).
static int segment_hits(const CGCollision *c, const float *a, const float *b) {
    return cgc_debug_segment_hits(c, a, b);
}

static float frand(void) { return (float)rand() / (float)RAND_MAX; }

static float worst_penetration(const CGCollision *c, const CGPlayer *p) {
    float r = p->radius, worst = 0;
    float ys[3] = { r, p->height * 0.5f, p->height - r };
    for (int i = 0; i < 3; i++) {
        float ctr[3] = { p->pos[0], p->pos[1] + ys[i], p->pos[2] };
        float d = cgc_debug_penetration(c, ctr, r);
        if (d > worst) worst = d;
    }
    return worst;
}

int main(int argc, char **argv) {
    if (argc < 3) return 2;
    char pc[512], ps[512];
    snprintf(pc, sizeof pc, "%s/%s.cgc", argv[1], argv[2]);
    snprintf(ps, sizeof ps, "%s/%s.cgs", argv[1], argv[2]);
    CGCollision *col = cgc_load(pc);
    if (!col) { printf("%s: cgc_load FAILED\n", argv[2]); return 1; }
    FILE *f = fopen(ps, "rb");
    uint8_t hdr[48]; if (fread(hdr, 1, 48, f) != 48) return 2; fclose(f);
    float h9[9]; memcpy(h9, hdr + 12, 36);
    float bmin[3], bmax[3]; cgc_bounds(col, bmin, bmax);

    // начальная точка: спавн из .cgs (ноги = спавн - 1.7 м вверх)
    float feet[3] = { h9[6], h9[7] - 1.7f, h9[8] };
    CGPlayer p; cgplayer_init(&p, feet);

    // 1) падение и стояние
    float startY = p.pos[1];
    int landedFrame = -1;
    for (int i = 0; i < 600; i++) {
        cgplayer_update(&p, col, 0, 0, 0, 0, 1.0f / 60.0f);
        if (p.onGround && landedFrame < 0) landedFrame = i;
        if (p.pos[1] < bmin[1] - 50) break;
    }
    float y1 = p.pos[1];
    for (int i = 0; i < 60; i++) cgplayer_update(&p, col, 0, 0, 0, 0, 1.0f / 60.0f);
    float jitter = fabsf(p.pos[1] - y1);
    printf("%-12s tris=%-6u старт y=%.2f -> y=%.2f (посадка на кадре %d), onGround=%d, дрожь стоя=%.4f\n",
           argv[2], cgc_triangle_count(col), startY, p.pos[1], landedFrame, p.onGround, jitter);
    if (!p.onGround || p.pos[1] < bmin[1] - 40) { printf("  ПРОВАЛ: игрок не приземлился\n"); return 1; }

    // 2) случайная ходьба 60 с с прыжками, смена dt
    float yaw = 0, in_f = 0, in_s = 0;
    int tunnels = 0, spikes = 0;
    float worst = 0; int fell __attribute__((unused)) = 0, checks = 0, jumps = 0, groundedFrames = 0, frames = 0;
    float minY = p.pos[1], maxSpeed = 0;
    srand(12345);
    for (int fr = 0; fr < 3600; fr++) {
        if (fr % 60 == 0) { in_f = frand() * 2 - 1; in_s = frand() * 2 - 1; yaw += (frand() - 0.5f) * 3.0f; }
        int jump = (rand() % 90) == 0; jumps += jump;
        float dt = (fr % 7 == 0) ? 1.0f / 30.0f : 1.0f / 60.0f;      // неровный dt
        float before[3] = { p.pos[0], p.pos[1], p.pos[2] };
        float velBefore[3] = { p.vel[0], p.vel[1], p.vel[2] };
        int groundBefore = p.onGround;
        cgplayer_update(&p, col, in_f, in_s, yaw, jump, dt);
        {   // туннелирование: траектория центров трёх сфер не должна пересекать геометрию
            float r = p.radius, ys[3] = { r, p.height * 0.5f, p.height - r };
            for (int i = 0; i < 3; i++) {
                float a[3] = { before[0], before[1] + ys[i], before[2] };
                float b[3] = { p.pos[0], p.pos[1] + ys[i], p.pos[2] };
                if (segment_hits(col, a, b)) { tunnels++; break; }
            }
        }
        float dx = p.pos[0]-before[0], dz = p.pos[2]-before[2];
        float sp = sqrtf(dx*dx + dz*dz) / dt; if (sp > maxSpeed) maxSpeed = sp;
        if (sp > 8.0f) {
            spikes++;
            if (getenv("SPIKES") && spikes <= 6)
                printf("    скачок кадр %d: %.1f м/с dt=%.3f вход(%.2f,%.2f) земля %d->%d  pos (%.2f,%.2f,%.2f)->(%.2f,%.2f,%.2f)  vel(%.1f,%.1f,%.1f)->(%.1f,%.1f,%.1f)\n",
                       fr, sp, dt, in_f, in_s, groundBefore, p.onGround, before[0], before[1], before[2],
                       p.pos[0], p.pos[1], p.pos[2], velBefore[0], velBefore[1], velBefore[2], p.vel[0], p.vel[1], p.vel[2]);
        }
        frames++; groundedFrames += p.onGround;
        if (p.pos[1] < minY) minY = p.pos[1];
        if (p.pos[1] < bmin[1] - 30) { fell = 1; printf("  (упал с края на кадре %d, x=%.1f z=%.1f)\n", fr, p.pos[0], p.pos[2]); break; }
        if (fr % 10 == 0) { float w = worst_penetration(col, &p); if (w > worst) worst = w; checks++; }
    }
    printf("  ходьба: %d кадров, прыжков %d, на земле %.0f%%, макс. гориз. скорость %.1f м/с, мин. y %.2f\n",
           frames, jumps, 100.0f * groundedFrames / frames, maxSpeed, minY);
    printf("  макс. проникновение: %.4f м (проверок %d), туннелирований: %d, кадров со скоростью >8 м/с: %d  %s\n",
           worst, checks, tunnels, spikes, (worst < 0.10f && tunnels == 0) ? "OK" : "ПРОБЛЕМА");

    // 3) стена: бежим в 8 направлениях по 4 с от точки посадки; не должны улететь за границы
    float base[3] = { p.pos[0], p.pos[1], p.pos[2] };
    int escaped = 0;
    for (int d = 0; d < 8; d++) {
        CGPlayer q; cgplayer_init(&q, base);
        float ang = d * 3.14159265f / 4;
        for (int i = 0; i < 240; i++) cgplayer_update(&q, col, 1, 0, ang, 0, 1.0f / 60.0f);
        float w = worst_penetration(col, &q);
        if (q.pos[0] < bmin[0] - 5 || q.pos[0] > bmax[0] + 5 || q.pos[2] < bmin[2] - 5 || q.pos[2] > bmax[2] + 5 || w > 0.05f) escaped++;
    }
    printf("  бег в 8 направлениях: вышли за карту/провалились: %d из 8\n", escaped);
    cgc_free(col);
    return (worst < 0.10f && tunnels == 0) ? 0 : 1;
}
