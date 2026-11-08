// Печатает мировые позиции узлов в нескольких позах (для сверки с независимым расчётом на Python).
// gcc -std=c99 -O2 -I../../src rig_check.c ../../src/Rig.c -o rig_check -lm ; ./rig_check Resources/characters/rudy.cgr
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "Rig.h"

static void path_of(const CGRig *r, int i, char *out, size_t cap) {
    char tmp[512] = "";
    int chain[32], n = 0;
    for (int k = i; k >= 0 && n < 32; k = r->nodes[k].parent) chain[n++] = k;
    for (int k = n - 2; k >= 0; k--) {                    // корень (RudyContainer) в путь не входит
        if (tmp[0]) strncat(tmp, "/", sizeof tmp - strlen(tmp) - 1);
        strncat(tmp, r->nodes[chain[k]].name, sizeof tmp - strlen(tmp) - 1);
    }
    snprintf(out, cap, "%s", tmp);
}

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    CGRig *r = cgrig_load(argv[1]);
    if (!r) { fprintf(stderr, "cgrig_load FAILED\n"); return 1; }
    struct { const char *a, *b; float t; } poses[] = {
        { "Idle", "TopIdle", 0.10f }, { "Run", "TopRun", 0.20f }, { "Run", "TopRun", 0.45f },
        { "Idle", "TopIdle", 0.25f }, { "Run", "TopRun", 0.0f }, { "Run", "TopRun", 1.30f } /* зацикливание: 1.30 = 0.20 */
    };
    float root[16] = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 };
    for (unsigned p = 0; p < sizeof poses / sizeof poses[0]; p++) {
        CGRigPose pose; cgrig_rest_pose(r, &pose);
        cgrig_apply_clip(r, cgrig_find_clip(r, poses[p].a), poses[p].t, 1.0f, &pose);
        cgrig_apply_clip(r, cgrig_find_clip(r, poses[p].b), poses[p].t, 1.0f, &pose);
        float world[CGRIG_MAX_NODES][16];
        cgrig_world(r, root, &pose, world);
        printf("POSE %s+%s %.3f\n", poses[p].a, poses[p].b, poses[p].t);
        for (unsigned i = 0; i < r->nodeCount; i++) {
            char path[512]; path_of(r, (int)i, path, sizeof path);
            printf("N %s|%.5f %.5f %.5f\n", path, world[i][12], world[i][13], world[i][14]);
        }
    }
    // кроссфейд: weight 0 не меняет, 1 заменяет, 0.5 — между
    CGRigPose a, b, c; cgrig_rest_pose(r, &a); b = a; c = a;
    int run = cgrig_find_clip(r, "Run");
    cgrig_apply_clip(r, run, 0.2f, 0.0f, &a);
    int same = memcmp(&a, &b, sizeof a) == 0;
    CGRigPose full = b; cgrig_apply_clip(r, run, 0.2f, 1.0f, &full);
    cgrig_apply_clip(r, run, 0.2f, 0.5f, &c);
    int ok = same, between = 1;
    for (unsigned t = 0; t < r->clips[run].tracks; t++) {
        unsigned n = r->clips[run].trackNode[t];
        for (int k = 0; k < 3; k++) {
            float lo = fminf(b.pos[n][k], full.pos[n][k]) - 1e-4f, hi = fmaxf(b.pos[n][k], full.pos[n][k]) + 1e-4f;
            if (c.pos[n][k] < lo || c.pos[n][k] > hi) between = 0;
        }
        float qn = sqrtf(c.quat[n][0]*c.quat[n][0] + c.quat[n][1]*c.quat[n][1] + c.quat[n][2]*c.quat[n][2] + c.quat[n][3]*c.quat[n][3]);
        if (fabsf(qn - 1) > 1e-4f) ok = 0;
    }
    printf("BLEND weight0_unchanged=%d weight_half_between=%d quat_unit=%d\n", same, between, ok);
    cgrig_free(r);
    return 0;
}
