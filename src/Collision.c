#include "Collision.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>

#define CELL 4.0f
#define MAX_GRID_DIM 1024
#define MAX_TRIS 4000000u

struct CGCollision {
    unsigned triCount;
    float bmin[3], bmax[3];
    float *tris;                 // triCount * 9
    int   nx, nz;                // размер сетки по X и Z
    float ox, oz;                // начало сетки
    uint32_t *cellStart;         // nx*nz + 1
    uint32_t *cellTris;          // индексы треугольников
};

/* ---------- векторы ---------- */
static inline void sub3(const float *a, const float *b, float *o) { o[0] = a[0]-b[0]; o[1] = a[1]-b[1]; o[2] = a[2]-b[2]; }
static inline float dot3(const float *a, const float *b) { return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]; }

/* Ближайшая точка треугольника abc к точке p (Ericson, Real-Time Collision Detection). */
static void closest_on_tri(const float *p, const float *a, const float *b, const float *c, float *out) {
    float ab[3], ac[3], ap[3], bp[3], cp[3];
    sub3(b, a, ab); sub3(c, a, ac); sub3(p, a, ap);
    float d1 = dot3(ab, ap), d2 = dot3(ac, ap);
    if (d1 <= 0 && d2 <= 0) { memcpy(out, a, 12); return; }
    sub3(p, b, bp);
    float d3 = dot3(ab, bp), d4 = dot3(ac, bp);
    if (d3 >= 0 && d4 <= d3) { memcpy(out, b, 12); return; }
    float vc = d1*d4 - d3*d2;
    if (vc <= 0 && d1 >= 0 && d3 <= 0) {
        float v = d1 / (d1 - d3);
        for (int i = 0; i < 3; i++) out[i] = a[i] + v * ab[i];
        return;
    }
    sub3(p, c, cp);
    float d5 = dot3(ab, cp), d6 = dot3(ac, cp);
    if (d6 >= 0 && d5 <= d6) { memcpy(out, c, 12); return; }
    float vb = d5*d2 - d1*d6;
    if (vb <= 0 && d2 >= 0 && d6 <= 0) {
        float w = d2 / (d2 - d6);
        for (int i = 0; i < 3; i++) out[i] = a[i] + w * ac[i];
        return;
    }
    float va = d3*d6 - d5*d4;
    if (va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0) {
        float w = (d4 - d3) / ((d4 - d3) + (d5 - d6));
        for (int i = 0; i < 3; i++) out[i] = b[i] + w * (c[i] - b[i]);
        return;
    }
    float denom = 1.0f / (va + vb + vc);
    float v = vb * denom, w = vc * denom;
    for (int i = 0; i < 3; i++) out[i] = a[i] + ab[i] * v + ac[i] * w;
}

/* ---------- загрузка и сетка ---------- */
static int cell_range(const CGCollision *c, float lo, float hi, float origin, int n, int *i0, int *i1) {
    int a = (int)floorf((lo - origin) / CELL), b = (int)floorf((hi - origin) / CELL);
    if (b < 0 || a >= n) return 0;
    *i0 = a < 0 ? 0 : a;
    *i1 = b >= n ? n - 1 : b;
    (void)c;
    return 1;
}

static int build_grid(CGCollision *c) {
    float w = c->bmax[0] - c->bmin[0], d = c->bmax[2] - c->bmin[2];
    c->ox = c->bmin[0] - 0.5f; c->oz = c->bmin[2] - 0.5f;
    c->nx = (int)ceilf((w + 1.0f) / CELL); c->nz = (int)ceilf((d + 1.0f) / CELL);
    if (c->nx < 1) c->nx = 1;
    if (c->nz < 1) c->nz = 1;
    if (c->nx > MAX_GRID_DIM || c->nz > MAX_GRID_DIM) return 0;
    size_t cells = (size_t)c->nx * c->nz;
    c->cellStart = (uint32_t *)calloc(cells + 1, sizeof(uint32_t));
    if (!c->cellStart) return 0;
    // проход 1: считаем, проход 2: заполняем
    for (int pass = 0; pass < 2; pass++) {
        if (pass == 1) {
            uint32_t sum = 0;
            for (size_t i = 0; i < cells; i++) { uint32_t n = c->cellStart[i]; c->cellStart[i] = sum; sum += n; }
            c->cellStart[cells] = sum;
            c->cellTris = (uint32_t *)malloc((sum ? sum : 1) * sizeof(uint32_t));
            if (!c->cellTris) return 0;
        }
        uint32_t *fill = NULL;
        if (pass == 1) {
            fill = (uint32_t *)calloc(cells, sizeof(uint32_t));
            if (!fill) return 0;
        }
        for (unsigned t = 0; t < c->triCount; t++) {
            const float *v = c->tris + (size_t)t * 9;
            float xmin = fminf(v[0], fminf(v[3], v[6])), xmax = fmaxf(v[0], fmaxf(v[3], v[6]));
            float zmin = fminf(v[2], fminf(v[5], v[8])), zmax = fmaxf(v[2], fmaxf(v[5], v[8]));
            int x0, x1, z0, z1;
            if (!cell_range(c, xmin, xmax, c->ox, c->nx, &x0, &x1)) continue;
            if (!cell_range(c, zmin, zmax, c->oz, c->nz, &z0, &z1)) continue;
            for (int z = z0; z <= z1; z++)
                for (int x = x0; x <= x1; x++) {
                    size_t ci = (size_t)z * c->nx + x;
                    if (pass == 0) c->cellStart[ci]++;
                    else c->cellTris[c->cellStart[ci] + fill[ci]++] = t;
                }
        }
        free(fill);
    }
    return 1;
}

CGCollision *cgc_load(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    uint8_t hdr[32];   // magic(4) + count(4) + bmin(12) + bmax(12)
    CGCollision *c = NULL;
    if (fread(hdr, 1, sizeof hdr, f) != sizeof hdr || memcmp(hdr, "CGC1", 4) != 0) { fclose(f); return NULL; }
    uint32_t n; memcpy(&n, hdr + 4, 4);
    if (n == 0 || n > MAX_TRIS) { fclose(f); return NULL; }
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    if (len < 0 || (size_t)len != sizeof hdr + (size_t)n * 36) { fclose(f); return NULL; }
    fseek(f, (long)sizeof hdr, SEEK_SET);

    c = (CGCollision *)calloc(1, sizeof *c);
    if (!c) { fclose(f); return NULL; }
    c->triCount = n;
    memcpy(c->bmin, hdr + 8, 12);
    memcpy(c->bmax, hdr + 20, 12);
    c->tris = (float *)malloc((size_t)n * 36);
    if (!c->tris || fread(c->tris, 36, n, f) != n) { fclose(f); cgc_free(c); return NULL; }
    fclose(f);
    if (!build_grid(c)) { cgc_free(c); return NULL; }
    return c;
}

void cgc_free(CGCollision *c) {
    if (!c) return;
    free(c->tris); free(c->cellStart); free(c->cellTris); free(c);
}

unsigned cgc_triangle_count(const CGCollision *c) { return c ? c->triCount : 0; }
void cgc_bounds(const CGCollision *c, float bmin[3], float bmax[3]) {
    memcpy(bmin, c->bmin, 12); memcpy(bmax, c->bmax, 12);
}

float cgc_debug_penetration(const CGCollision *c, const float center[3], float radius) {
    float worst = 0;
    for (unsigned t = 0; t < c->triCount; t++) {
        const float *v = c->tris + (size_t)t * 9;
        float cp[3], d[3];
        closest_on_tri(center, v, v + 3, v + 6, cp);
        sub3(center, cp, d);
        float dist = sqrtf(dot3(d, d));
        if (radius - dist > worst) worst = radius - dist;
    }
    return worst;
}

/* ---------- лучи ---------- */
// Мёллер–Трамбор, двусторонний. 1 и t при пересечении в (tmin, tmax).
static int ray_tri(const float *o, const float *d, const float *v, float tmin, float tmax, float *tOut) {
    float e1[3], e2[3], h[3], s[3], q[3];
    sub3(v + 3, v, e1); sub3(v + 6, v, e2);
    h[0] = d[1]*e2[2] - d[2]*e2[1]; h[1] = d[2]*e2[0] - d[0]*e2[2]; h[2] = d[0]*e2[1] - d[1]*e2[0];
    float det = dot3(e1, h);
    if (fabsf(det) < 1e-9f) return 0;
    float inv = 1.0f / det;
    sub3(o, v, s);
    float u = dot3(s, h) * inv;
    if (u < 0.0f || u > 1.0f) return 0;
    q[0] = s[1]*e1[2] - s[2]*e1[1]; q[1] = s[2]*e1[0] - s[0]*e1[2]; q[2] = s[0]*e1[1] - s[1]*e1[0];
    float w = dot3(d, q) * inv;
    if (w < 0.0f || u + w > 1.0f) return 0;
    float t = dot3(e2, q) * inv;
    if (t <= tmin || t > tmax) return 0;
    *tOut = t;
    return 1;
}

static void fill_hit(const CGCollision *c, const float *o, const float *d, unsigned tri, float t, CGHit *hit) {
    const float *v = c->tris + (size_t)tri * 9;
    float e1[3], e2[3], n[3];
    sub3(v + 3, v, e1); sub3(v + 6, v, e2);
    n[0] = e1[1]*e2[2] - e1[2]*e2[1]; n[1] = e1[2]*e2[0] - e1[0]*e2[2]; n[2] = e1[0]*e2[1] - e1[1]*e2[0];
    float l = sqrtf(dot3(n, n));
    if (l > 1e-12f) { n[0] /= l; n[1] /= l; n[2] /= l; } else { n[0] = 0; n[1] = 1; n[2] = 0; }
    if (dot3(n, d) > 0) { n[0] = -n[0]; n[1] = -n[1]; n[2] = -n[2]; }   // к стрелку
    hit->t = t; hit->tri = tri;
    for (int i = 0; i < 3; i++) { hit->point[i] = o[i] + d[i] * t; hit->normal[i] = n[i]; }
}

int cgc_debug_raycast_brute(const CGCollision *c, const float origin[3], const float dir[3], float maxDist, CGHit *hit) {
    float best = maxDist; int found = 0; unsigned bi = 0;
    for (unsigned t = 0; t < c->triCount; t++) {
        float tt;
        if (ray_tri(origin, dir, c->tris + (size_t)t * 9, 0.0f, best, &tt)) { best = tt; bi = t; found = 1; }
    }
    if (found && hit) fill_hit(c, origin, dir, bi, best, hit);
    return found;
}

int cgc_raycast(const CGCollision *c, const float origin[3], const float dir[3], float maxDist, CGHit *hit) {
    // 1) отрезок луча внутри сетки (слэбы по X и Z)
    float gx0 = c->ox, gx1 = c->ox + c->nx * CELL, gz0 = c->oz, gz1 = c->oz + c->nz * CELL;
    float tEnter = 0.0f, tExit = maxDist;
    const float lo[2] = { gx0, gz0 }, hi[2] = { gx1, gz1 };
    const float o2[2] = { origin[0], origin[2] }, d2[2] = { dir[0], dir[2] };
    for (int a = 0; a < 2; a++) {
        if (fabsf(d2[a]) < 1e-9f) {
            if (o2[a] < lo[a] || o2[a] > hi[a]) return 0;
        } else {
            float t0 = (lo[a] - o2[a]) / d2[a], t1 = (hi[a] - o2[a]) / d2[a];
            if (t0 > t1) { float tmp = t0; t0 = t1; t1 = tmp; }
            if (t0 > tEnter) tEnter = t0;
            if (t1 < tExit) tExit = t1;
            if (tEnter > tExit) return 0;
        }
    }
    // 2) обход клеток (Amanatides–Woo)
    float px = origin[0] + dir[0] * tEnter, pz = origin[2] + dir[2] * tEnter;
    int ix = (int)floorf((px - c->ox) / CELL), iz = (int)floorf((pz - c->oz) / CELL);
    if (ix < 0) ix = 0;
    if (ix >= c->nx) ix = c->nx - 1;
    if (iz < 0) iz = 0;
    if (iz >= c->nz) iz = c->nz - 1;
    int stepX = dir[0] > 0 ? 1 : -1, stepZ = dir[2] > 0 ? 1 : -1;
    const float INF = 1e30f;
    float tMaxX = INF, tMaxZ = INF, tDeltaX = INF, tDeltaZ = INF;
    if (fabsf(dir[0]) > 1e-9f) {
        float bx = c->ox + (ix + (stepX > 0 ? 1 : 0)) * CELL;
        tMaxX = (bx - origin[0]) / dir[0]; tDeltaX = CELL / fabsf(dir[0]);
    }
    if (fabsf(dir[2]) > 1e-9f) {
        float bz = c->oz + (iz + (stepZ > 0 ? 1 : 0)) * CELL;
        tMaxZ = (bz - origin[2]) / dir[2]; tDeltaZ = CELL / fabsf(dir[2]);
    }
    float best = maxDist; int found = 0; unsigned bi = 0;
    for (;;) {
        size_t ci = (size_t)iz * c->nx + ix;
        for (uint32_t k = c->cellStart[ci]; k < c->cellStart[ci + 1]; k++) {
            unsigned tri = c->cellTris[k];
            float tt;
            if (ray_tri(origin, dir, c->tris + (size_t)tri * 9, 0.0f, best, &tt)) { best = tt; bi = tri; found = 1; }
        }
        float tNext = tMaxX < tMaxZ ? tMaxX : tMaxZ;
        if (found && best <= tNext) break;            // ближе попадания в следующих клетках быть не может
        if (tNext > tExit) break;
        if (tMaxX < tMaxZ) { ix += stepX; tMaxX += tDeltaX; } else { iz += stepZ; tMaxZ += tDeltaZ; }
        if (ix < 0 || ix >= c->nx || iz < 0 || iz >= c->nz) break;
    }
    if (found && hit) fill_hit(c, origin, dir, bi, best, hit);
    return found;
}

int cgc_debug_segment_hits(const CGCollision *c, const float a[3], const float b[3]) {
    float dir[3] = { b[0]-a[0], b[1]-a[1], b[2]-a[2] };
    int hits = 0;
    for (unsigned t = 0; t < c->triCount; t++) {              // Мёллер–Трамбор, двусторонний
        const float *v = c->tris + (size_t)t * 9;
        float e1[3], e2[3], h[3], s[3], q[3];
        sub3(v + 3, v, e1); sub3(v + 6, v, e2);
        h[0] = dir[1]*e2[2] - dir[2]*e2[1]; h[1] = dir[2]*e2[0] - dir[0]*e2[2]; h[2] = dir[0]*e2[1] - dir[1]*e2[0];
        float det = dot3(e1, h);
        if (fabsf(det) < 1e-9f) continue;
        float inv = 1.0f / det;
        sub3(a, v, s);
        float u = dot3(s, h) * inv;
        if (u < 0 || u > 1) continue;
        q[0] = s[1]*e1[2] - s[2]*e1[1]; q[1] = s[2]*e1[0] - s[0]*e1[2]; q[2] = s[0]*e1[1] - s[1]*e1[0];
        float w = dot3(dir, q) * inv;
        if (w < 0 || u + w > 1) continue;
        float tt = dot3(e2, q) * inv;
        if (tt >= 0 && tt <= 1) hits++;
    }
    return hits;
}

int cgc_sphere_overlaps(const CGCollision *col, const float center[3], float r) {
    int x0, x1, z0, z1;
    if (!cell_range(col, center[0] - r, center[0] + r, col->ox, col->nx, &x0, &x1)) return 0;
    if (!cell_range(col, center[2] - r, center[2] + r, col->oz, col->nz, &z0, &z1)) return 0;
    for (int z = z0; z <= z1; z++)
        for (int x = x0; x <= x1; x++) {
            size_t ci = (size_t)z * col->nx + x;
            for (uint32_t k = col->cellStart[ci]; k < col->cellStart[ci + 1]; k++) {
                const float *v = col->tris + (size_t)col->cellTris[k] * 9;
                float cp[3], d[3];
                closest_on_tri(center, v, v + 3, v + 6, cp);
                sub3(center, cp, d);
                if (dot3(d, d) < r * r) return 1;
            }
        }
    return 0;
}

/* ---------- сфера против сцены ---------- */
// Выталкивает сферу из треугольников; смещает *center на вектор выталкивания.
// Возвращает 1, если был контакт; в normal — нормаль самого «приземляющего» контакта (наибольший n.y).
static int push_sphere(const CGCollision *col, float *center, float r, float *bestNormal, float *wallN, int *hitWall) {
    int hit = 0;
    int x0, x1, z0, z1;
    if (!cell_range(col, center[0] - r, center[0] + r, col->ox, col->nx, &x0, &x1)) return 0;
    if (!cell_range(col, center[2] - r, center[2] + r, col->oz, col->nz, &z0, &z1)) return 0;
    for (int z = z0; z <= z1; z++)
        for (int x = x0; x <= x1; x++) {
            size_t ci = (size_t)z * col->nx + x;
            for (uint32_t k = col->cellStart[ci]; k < col->cellStart[ci + 1]; k++) {
                const float *v = col->tris + (size_t)col->cellTris[k] * 9;
                float cp[3], d[3];
                closest_on_tri(center, v, v + 3, v + 6, cp);
                sub3(center, cp, d);
                float d2 = dot3(d, d);
                if (d2 >= r * r) continue;
                float dist = sqrtf(d2), n[3];
                if (dist > 1e-6f) {
                    n[0] = d[0] / dist; n[1] = d[1] / dist; n[2] = d[2] / dist;
                } else {                       // центр лежит на поверхности: берём нормаль треугольника
                    float e1[3], e2[3];
                    sub3(v + 3, v, e1); sub3(v + 6, v, e2);
                    n[0] = e1[1]*e2[2] - e1[2]*e2[1];
                    n[1] = e1[2]*e2[0] - e1[0]*e2[2];
                    n[2] = e1[0]*e2[1] - e1[1]*e2[0];
                    float l = sqrtf(dot3(n, n));
                    if (l < 1e-12f) { n[0] = 0; n[1] = 1; n[2] = 0; } else { n[0] /= l; n[1] /= l; n[2] /= l; }
                    if (n[1] < 0) { n[0] = -n[0]; n[1] = -n[1]; n[2] = -n[2]; }
                }
                float depth = r - dist;
                for (int i = 0; i < 3; i++) center[i] += n[i] * depth;
                hit = 1;
                if (n[1] > bestNormal[1]) memcpy(bestNormal, n, 12);
                if (n[1] <= 0.6f) { *hitWall = 1; memcpy(wallN, n, 12); }
            }
        }
    return hit;
}

// Разрешает проникновения капсулы (3 сферы). Возвращает 1, если стоим на земле.
static int resolve(const CGCollision *col, CGPlayer *p) {
    float r = p->radius;
    int nsph = (p->height > 2.0f * r + 1e-4f) ? 3 : 1;
    float ys[3];
    if (nsph == 3) { ys[0] = r; ys[1] = p->height * 0.5f; ys[2] = p->height - r; }
    else           { ys[0] = p->height * 0.5f; }
    int grounded = 0;
    for (int iter = 0; iter < 4; iter++) {
        int any = 0;
        for (int s = 0; s < nsph; s++) {
            float c[3] = { p->pos[0], p->pos[1] + ys[s], p->pos[2] };
            float groundN[3] = { 0, -1, 0 }, wallN[3] = { 0, 0, 0 };
            int wall = 0;
            if (push_sphere(col, c, r, groundN, wallN, &wall)) {
                any = 1;
                p->pos[0] = c[0]; p->pos[1] = c[1] - ys[s]; p->pos[2] = c[2];
                if (groundN[1] > 0.6f) {                   // ходибельная поверхность
                    grounded = 1;
                    if (p->vel[1] < 0) p->vel[1] = 0;
                }
                if (wall) {                                // стена/потолок: гасим скорость внутрь
                    float vn = dot3(p->vel, wallN);
                    if (vn < 0) for (int i = 0; i < 3; i++) p->vel[i] -= wallN[i] * vn;
                }
            }
        }
        if (!any) break;
    }
    return grounded;
}

/* ---------- игрок ---------- */
void cgplayer_init(CGPlayer *p, const float feet[3]) {
    memset(p, 0, sizeof *p);
    memcpy(p->pos, feet, 12);
    p->radius = 0.35f;
    p->height = 1.4f;
    p->eyeHeight = 1.25f;
    p->walkSpeed = 5.0f;
    p->jumpSpeed = 6.5f;
    p->gravity = 20.0f;
}

void cgplayer_update(CGPlayer *p, const CGCollision *col,
                     float fwd, float strafe, float yaw, int jump, float dt) {
    if (dt <= 0) return;
    if (dt > 0.1f) dt = 0.1f;

    float len = sqrtf(fwd * fwd + strafe * strafe);
    if (len > 1.0f) { fwd /= len; strafe /= len; }
    float sy = sinf(yaw), cy = cosf(yaw);
    float tx = (-sy * fwd + cy * strafe) * p->walkSpeed;
    float tz = (-cy * fwd - sy * strafe) * p->walkSpeed;

    int wasGround = p->onGround;
    float k = wasGround ? 25.0f : 4.0f;                    // в воздухе управление слабее
    float a = k * dt; if (a > 1.0f) a = 1.0f;
    p->vel[0] += (tx - p->vel[0]) * a;
    p->vel[2] += (tz - p->vel[2]) * a;

    int jumped = 0;
    if (jump && wasGround) { p->vel[1] = p->jumpSpeed; jumped = 1; }
    p->vel[1] -= p->gravity * dt;
    if (p->vel[1] < -40.0f) p->vel[1] = -40.0f;

    p->onGround = 0;
    if (!col) {
        for (int i = 0; i < 3; i++) p->pos[i] += p->vel[i] * dt;
        return;
    }

    // подшаги: не больше полрадиуса за раз, чтобы не пролетать сквозь тонкие стены
    float dist = sqrtf(dot3(p->vel, p->vel)) * dt;
    int steps = (int)ceilf(dist / (p->radius * 0.5f));
    if (steps < 1) steps = 1;
    if (steps > 24) steps = 24;
    float sdt = dt / (float)steps;
    int grounded = 0;
    for (int s = 0; s < steps; s++) {
        for (int i = 0; i < 3; i++) p->pos[i] += p->vel[i] * sdt;
        if (resolve(col, p)) grounded = 1;
    }
    p->onGround = grounded;

    // прилипание к земле на спусках и ступеньках: опускаемся шагами по 2 см до первого контакта
    // с ходибельной поверхностью (так погружение, а значит и боковой сдвиг при выталкивании, <= 2 см)
    if (!grounded && wasGround && !jumped && p->vel[1] <= 0.0f) {
        for (float d = 0.02f; d <= 0.30f + 1e-4f; d += 0.02f) {
            CGPlayer probe = *p;
            probe.pos[1] -= d;
            if (resolve(col, &probe)) {
                *p = probe;
                p->onGround = 1;
                p->vel[1] = 0.0f;
                break;
            }
        }
    }
}
