#include "Bot.h"
#include <math.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

#define PI_F 3.14159265f
#define PLAYER_CHEST 0.8f          // куда целятся боты (над ногами игрока)
#define PLAYER_HIT_Y0 0.30f
#define PLAYER_HIT_Y1 1.15f
#define PLAYER_HIT_R 0.38f

static const CGBotParams P = {
    100.0f,                          // maxHealth
    2.0f, 4.5f, 2.5f,                // walk, run, strafe
    5.0f,                            // turnRate
    45.0f, 7.0f, 1.31f,              // sight, hear, fov (75 градусов)
    22.0f,                           // attackRange
    0.45f,                           // fireInterval
    4.0f, 0.25f,                     // baseSpread, spreadPerMeter (градусы)
    5.0f,                            // damage
    0.35f,                           // reaction
    0.45f, 1.6f                      // bodyRadius, bodyHeight
};

const CGBotParams *cgbot_params(void) { return &P; }

/* ---------- утилиты ---------- */
static float frand(CGBot *b) {
    unsigned x = b->rng ? b->rng : 2463534242u;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    b->rng = x;
    return (float)(x & 0xFFFFFF) / 16777216.0f;
}

static float wrap_pi(float a) {
    while (a > PI_F) a -= 2 * PI_F;
    while (a < -PI_F) a += 2 * PI_F;
    return a;
}

static float yaw_to(float dx, float dz) { return atan2f(-dx, -dz); }

int cg_ray_vcapsule(const float o[3], const float d[3], float cx, float cz, float y0, float y1, float r,
                    float tmax, float *tOut, float *hitY) {
    float best = tmax; int found = 0; float by = 0;
    float dx = o[0] - cx, dz = o[2] - cz;
    // цилиндр
    float a = d[0] * d[0] + d[2] * d[2];
    if (a > 1e-9f) {
        float b = 2.0f * (dx * d[0] + dz * d[2]);
        float c = dx * dx + dz * dz - r * r;
        float disc = b * b - 4 * a * c;
        if (disc >= 0) {
            float t = (-b - sqrtf(disc)) / (2 * a);
            if (t >= 0 && t <= best) {
                float y = o[1] + d[1] * t;
                if (y >= y0 && y <= y1) { best = t; by = y; found = 1; }
            }
        }
    }
    // полусферы на концах
    for (int s = 0; s < 2; s++) {
        float cy = s ? y1 : y0;
        float ox = o[0] - cx, oy = o[1] - cy, oz = o[2] - cz;
        float b = ox * d[0] + oy * d[1] + oz * d[2];
        float c = ox * ox + oy * oy + oz * oz - r * r;
        float disc = b * b - c;
        if (disc < 0) continue;
        float t = -b - sqrtf(disc);
        if (t < 0 || t > best) continue;
        float y = o[1] + d[1] * t;
        if ((s == 0 && y > y0) || (s == 1 && y < y1)) continue;   // эта часть сферы внутри цилиндра
        best = t; by = y; found = 1;
    }
    if (found) { *tOut = best; if (hitY) *hitY = by; }
    return found;
}

// 1, если на шаг вперёд от бота нет опоры (обрыв глубже ~1.2 м).
static int ledge_ahead(const CGCollision *col, const CGBot *b, float yaw) {
    if (!col || !b->body.onGround) return 0;
    float fx = -sinf(yaw), fz = -cosf(yaw);
    float o[3] = { b->body.pos[0] + fx * 1.0f, b->body.pos[1] + 0.6f, b->body.pos[2] + fz * 1.0f };
    float down[3] = { 0, -1, 0 };
    CGHit h;
    return !cgc_raycast(col, o, down, 1.8f, &h);
}

/* ---------- бот ---------- */
void cgbot_init(CGBot *b, const float feet[3], unsigned seed) {
    memset(b, 0, sizeof *b);
    cgplayer_init(&b->body, feet);
    b->body.radius = P.bodyRadius;
    b->body.height = P.bodyHeight;
    b->body.eyeHeight = 1.3f;
    b->body.walkSpeed = P.walkSpeed;
    b->body.jumpSpeed = 6.0f;
    b->rng = seed ? seed : 2463534242u;
    b->health = P.maxHealth;
    b->state = BOT_WANDER;
    b->yaw = frand(b) * 2 * PI_F - PI_F;
    b->wanderYaw = b->yaw;
    b->wanderTimer = 1.0f + frand(b) * 3.0f;
    b->fireTimer = 0.5f;
    b->strafeDir = 1;
    b->lastX = feet[0]; b->lastZ = feet[2];
}

int cgbot_damage(CGBot *b, float damage) {
    if (b->state == BOT_DEAD) return 0;
    b->health -= damage;
    b->hitFlash = 0.15f;
    b->alerted = 1;
    if (b->health <= 0) {
        b->health = 0;
        b->state = BOT_DEAD;
        b->stateTime = 0;
        b->deathT = 0;
        return 1;
    }
    return 0;
}

int cgbot_ray_hit(const CGBot *b, const float origin[3], const float dir[3], float maxDist, float *t, int *head) {
    if (b->state == BOT_DEAD) return 0;
    float hy;
    if (!cg_ray_vcapsule(origin, dir, b->body.pos[0], b->body.pos[2],
                         b->body.pos[1] + CGBOT_HIT_Y0, b->body.pos[1] + CGBOT_HIT_Y1,
                         CGBOT_HIT_RADIUS, maxDist, t, &hy)) return 0;
    if (head) *head = (hy - b->body.pos[1]) > CGBOT_HEAD_Y;
    return 1;
}

static void turn_toward(CGBot *b, float target, float dt) {
    float diff = wrap_pi(target - b->yaw);
    float maxStep = P.turnRate * dt;
    if (diff > maxStep) diff = maxStep;
    if (diff < -maxStep) diff = -maxStep;
    b->yaw = wrap_pi(b->yaw + diff);
}

void cgbot_update(CGBot *b, const CGCollision *col, const float playerFeet[3], int playerAlive,
                  float dt, CGBotEvents *ev) {
    memset(ev, 0, sizeof *ev);
    if (dt <= 0) return;
    if (dt > 0.1f) dt = 0.1f;

    b->stateTime += dt;
    if (b->hitFlash > 0) { b->hitFlash -= dt; if (b->hitFlash < 0) b->hitFlash = 0; }
    if (b->shootAnim > 0) { b->shootAnim -= dt; if (b->shootAnim < 0) b->shootAnim = 0; }

    if (b->state == BOT_DEAD) {
        b->deathT += dt / 0.6f; if (b->deathT > 1) b->deathT = 1;
        b->runBlend += (0 - b->runBlend) * fminf(1.0f, 8.0f * dt);
        return;
    }

    float eye[3] = { b->body.pos[0], b->body.pos[1] + b->body.eyeHeight, b->body.pos[2] };
    float target[3] = { playerFeet[0], playerFeet[1] + PLAYER_CHEST, playerFeet[2] };
    float to[3] = { target[0] - eye[0], target[1] - eye[1], target[2] - eye[2] };
    float dist = sqrtf(to[0]*to[0] + to[1]*to[1] + to[2]*to[2]);
    float dir[3] = { 0, 0, -1 };
    if (dist > 1e-4f) { dir[0] = to[0] / dist; dir[1] = to[1] / dist; dir[2] = to[2] / dist; }
    float yawToPlayer = yaw_to(to[0], to[2]);
    float bearing = fabsf(wrap_pi(yawToPlayer - b->yaw));

    // видимость: дистанция, угол обзора (или слух/тревога) и отсутствие стены на линии
    int see = 0;
    if (playerAlive && dist < P.sightRange && (bearing < P.fov || dist < P.hearRange || b->alerted)) {
        CGHit h;
        see = !(col && cgc_raycast(col, eye, dir, dist - 0.3f, &h));
    }

    // переходы состояний
    switch (b->state) {
    case BOT_WANDER:
        if (see) { b->state = BOT_CHASE; b->stateTime = 0; b->reaction = P.reactionTime; b->loseSightTimer = 0; b->alerted = 0; }
        break;
    case BOT_CHASE:
        if (see) {
            b->loseSightTimer = 0;
            if (dist < P.attackRange * 0.9f) { b->state = BOT_ATTACK; b->stateTime = 0; b->fireTimer = 0.4f + 0.3f * frand(b); }
        } else {
            b->loseSightTimer += dt;
            if (b->loseSightTimer > 4.0f) { b->state = BOT_WANDER; b->stateTime = 0; b->wanderTimer = 0; }
        }
        break;
    case BOT_ATTACK:
        if (!see) { b->state = BOT_CHASE; b->stateTime = 0; b->reaction = 0; }
        else if (dist > P.attackRange * 1.1f) { b->state = BOT_CHASE; b->stateTime = 0; b->reaction = 0; }
        break;
    default: break;
    }

    // решение о движении
    float fwd = 0, strafe = 0; int jump = 0; float desiredYaw = b->yaw; float speed = P.walkSpeed;
    if (b->state == BOT_WANDER) {
        b->wanderTimer -= dt;
        if (b->wanderTimer <= 0) {
            // примерно в половине случаев идём в сторону игрока: так враги рано или поздно находят его
            if (playerAlive && frand(b) < 0.55f) b->wanderYaw = wrap_pi(yawToPlayer + (frand(b) - 0.5f) * 1.2f);
            else b->wanderYaw = frand(b) * 2 * PI_F - PI_F;
            b->wanderTimer = 2.0f + frand(b) * 4.0f;
        }
        desiredYaw = b->wanderYaw;
        fwd = (fabsf(wrap_pi(desiredYaw - b->yaw)) < 1.0f) ? 1.0f : 0.0f;    // сначала разворачиваемся
        if (fwd > 0 && ledge_ahead(col, b, b->yaw)) {                         // не идём за край
            fwd = 0;
            b->wanderYaw = wrap_pi(b->yaw + (frand(b) < 0.5f ? -1 : 1) * (1.5f + frand(b) * 1.4f));
            b->wanderTimer = 2.0f + frand(b) * 2.0f;
        }
        speed = P.walkSpeed;
    } else if (b->state == BOT_CHASE) {
        desiredYaw = see ? yawToPlayer : b->yaw;
        if (b->reaction > 0) b->reaction -= dt;
        else fwd = (fabsf(wrap_pi(desiredYaw - b->yaw)) < 1.2f) ? 1.0f : 0.0f;
        if (fwd > 0 && ledge_ahead(col, b, b->yaw)) fwd = 0;                  // впереди обрыв: стоим, не прыгаем вниз
        speed = P.runSpeed;
    } else if (b->state == BOT_ATTACK) {
        desiredYaw = yawToPlayer;
        b->strafeTimer -= dt;
        if (b->strafeTimer <= 0) { b->strafeDir = (frand(b) < 0.5f) ? -1 : 1; b->strafeTimer = 0.8f + frand(b) * 1.2f; }
        strafe = 0.7f * (float)b->strafeDir;
        speed = P.strafeSpeed;
    }

    // застревание: за полсекунды почти не сдвинулись, хотя большую часть окна пытались идти
    b->stuckTimer += dt;
    if (fwd > 0.1f || fabsf(strafe) > 0.1f) b->intentTimer += dt;
    if (b->stuckTimer >= 0.5f) {
        float mx = b->body.pos[0] - b->lastX, mz = b->body.pos[2] - b->lastZ;
        float moved = sqrtf(mx * mx + mz * mz);
        if (b->intentTimer >= 0.4f && moved < 0.12f) {
            b->stuckCount++;
            if (b->state == BOT_WANDER) {
                b->wanderYaw = wrap_pi(b->yaw + (frand(b) < 0.5f ? -1 : 1) * (1.6f + frand(b) * 1.5f));
                b->wanderTimer = 2.0f + frand(b) * 2.0f;
            } else if (b->state == BOT_CHASE) {
                jump = 1; b->strafeDir = -b->strafeDir;
            } else {
                b->strafeDir = -b->strafeDir; b->strafeTimer = 1.0f;
            }
        } else b->stuckCount = 0;
        b->stuckTimer = 0; b->intentTimer = 0; b->lastX = b->body.pos[0]; b->lastZ = b->body.pos[2];
    }
    if (b->state == BOT_CHASE && b->stuckCount >= 2 && b->body.onGround) { jump = 1; b->stuckCount = 0; }
    if (b->state == BOT_CHASE && b->stuckTimer < 0.15f && b->stuckCount == 1) strafe = 0.8f * (float)b->strafeDir;

    turn_toward(b, desiredYaw, dt);
    b->body.walkSpeed = speed;
    cgplayer_update(&b->body, col, fwd, strafe, b->yaw, jump, dt);

    // стрельба
    if (b->state == BOT_ATTACK && see) {
        b->fireTimer -= dt;
        if (b->fireTimer <= 0 && bearing < 0.25f) {
            b->fireTimer = P.fireInterval * (0.8f + 0.5f * frand(b));
            b->shootAnim = 0.13f;
            float spread = (P.baseSpread + P.spreadPerMeter * dist) * (PI_F / 180.0f);
            float ey = (frand(b) - 0.5f) * spread, ep = (frand(b) - 0.5f) * spread;
            float yaw = yawToPlayer + ey;
            float pitch = asinf(dir[1] > 1 ? 1 : (dir[1] < -1 ? -1 : dir[1])) + ep;
            float cp = cosf(pitch);
            float sd[3] = { -sinf(yaw) * cp, sinf(pitch), -cosf(yaw) * cp };
            memcpy(ev->shotOrigin, eye, sizeof eye);
            memcpy(ev->shotDir, sd, sizeof sd);
            ev->shotFired = 1;
            // попал ли в игрока и не закрыла ли стена
            float t, hy;
            if (cg_ray_vcapsule(eye, sd, playerFeet[0], playerFeet[2], playerFeet[1] + PLAYER_HIT_Y0,
                                playerFeet[1] + PLAYER_HIT_Y1, PLAYER_HIT_R, P.attackRange * 1.3f, &t, &hy)) {
                CGHit h;
                if (!(col && cgc_raycast(col, eye, sd, t, &h))) { ev->playerHit = 1; ev->damage = P.damage; }
            }
        }
    }

    // анимация: бегаем -> run, стоим -> idle
    float vx = b->body.vel[0], vz = b->body.vel[2];
    float sp = sqrtf(vx * vx + vz * vz);
    float tgt = sp > 0.6f ? 1.0f : 0.0f;
    b->runBlend += (tgt - b->runBlend) * fminf(1.0f, 10.0f * dt);
    b->animTime += dt * (tgt > 0 ? fmaxf(0.7f, sp / 4.0f) : 1.0f);
}

/* ---------- точки появления ---------- */
float *cgbot_load_spawns(const char *path, unsigned *count) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    uint8_t hdr[8];
    if (fread(hdr, 1, 8, f) != 8 || memcmp(hdr, "CGP1", 4) != 0) { fclose(f); return NULL; }
    uint32_t n; memcpy(&n, hdr + 4, 4);
    if (n == 0 || n > 4096) { fclose(f); return NULL; }
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    if (len < 0 || (size_t)len != 8 + (size_t)n * 12) { fclose(f); return NULL; }
    fseek(f, 8, SEEK_SET);
    float *pts = (float *)malloc((size_t)n * 12);
    if (!pts || fread(pts, 12, n, f) != n) { free(pts); fclose(f); return NULL; }
    fclose(f);
    *count = n;
    return pts;
}

static int capsule_clear(const CGCollision *col, const float feet[3]) {
    float r = P.bodyRadius + 0.05f;
    float ys[3] = { r + 0.02f, P.bodyHeight * 0.5f, P.bodyHeight - r };
    for (int k = 0; k < 3; k++) {
        float c[3] = { feet[0], feet[1] + 0.05f + ys[k], feet[2] };
        if (cgc_sphere_overlaps(col, c, r)) return 0;
    }
    return 1;
}

int cgbot_pick_spawn(const CGCollision *col, const float *points, unsigned count, const float avoid[3],
                     float minDist, float maxDist, unsigned *rng, float out[3]) {
    if (!points || count == 0) return 0;
    unsigned x = *rng ? *rng : 2463534242u;
    for (int attempt = 0; attempt < 64; attempt++) {
        x ^= x << 13; x ^= x >> 17; x ^= x << 5;
        const float *p = points + (size_t)(x % count) * 3;
        float dx = p[0] - avoid[0], dz = p[2] - avoid[2];
        float d = sqrtf(dx * dx + dz * dz);
        if (d < minDist || d > maxDist) continue;
        if (!capsule_clear(col, p)) continue;
        memcpy(out, p, 12);
        *rng = x;
        return 1;
    }
    *rng = x;
    return 0;
}

int cgbot_sample_spawn(const CGCollision *col, const float avoid[3], float minDist, float maxDist,
                       unsigned *rng, float out[3]) {
    float bmin[3], bmax[3];
    cgc_bounds(col, bmin, bmax);
    unsigned x = *rng ? *rng : 2463534242u;
#define RND() (x ^= x << 13, x ^= x >> 17, x ^= x << 5, (float)(x & 0xFFFFFF) / 16777216.0f)
    for (int attempt = 0; attempt < 200; attempt++) {
        float px = bmin[0] + RND() * (bmax[0] - bmin[0]);
        float pz = bmin[2] + RND() * (bmax[2] - bmin[2]);
        float dx = px - avoid[0], dz = pz - avoid[2];
        float d = sqrtf(dx * dx + dz * dz);
        if (d < minDist || d > maxDist) continue;
        float o[3] = { px, bmax[1] + 1.0f, pz }, down[3] = { 0, -1, 0 };
        CGHit h;
        if (!cgc_raycast(col, o, down, (bmax[1] - bmin[1]) + 2.0f, &h)) continue;
        if (h.normal[1] < 0.8f) continue;                           // только пологие поверхности
        float up[3] = { 0, 1, 0 }, o2[3] = { h.point[0], h.point[1] + 0.1f, h.point[2] };
        CGHit h2;
        if (cgc_raycast(col, o2, up, 2.2f, &h2)) continue;          // есть запас по высоте
        {   // капсула бота целиком свободна (с небольшим запасом)
            float r = P.bodyRadius + 0.05f, fy = h.point[1] + 0.05f;
            float ys[3] = { r + 0.02f, P.bodyHeight * 0.5f, P.bodyHeight - r };
            int clear = 1;
            for (int k = 0; k < 3 && clear; k++) {
                float c[3] = { h.point[0], fy + ys[k], h.point[2] };
                if (cgc_sphere_overlaps(col, c, r)) clear = 0;
            }
            if (!clear) continue;
        }
        out[0] = h.point[0]; out[1] = h.point[1] + 0.05f; out[2] = h.point[2];
        *rng = x;
        return 1;
    }
    *rng = x;
#undef RND
    return 0;
}
