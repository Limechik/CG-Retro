// Тест формата .cgs и отсечения. Повторяет разбор из src/GameScene.m и использует src/Mat4.h.
// gcc -std=c99 -Wall -I../../src cgs_check.c -o cgs_check -lm && ./cgs_check <file.cgs> > flags.txt
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "Mat4.h"

#define HDR 48
#define MATSZ 80
#define BATSZ 48

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    FILE *f = fopen(argv[1], "rb");
    if (!f) { fprintf(stderr, "нет файла\n"); return 2; }
    fseek(f, 0, SEEK_END); long len = ftell(f); fseek(f, 0, SEEK_SET);
    uint8_t *p = malloc(len); fread(p, 1, len, f); fclose(f);

    if (memcmp(p, "CGS1", 4)) { fprintf(stderr, "не CGS1\n"); return 1; }
    uint32_t mc, bc; memcpy(&mc, p + 4, 4); memcpy(&bc, p + 8, 4);
    float hdr[9]; memcpy(hdr, p + 12, sizeof hdr);
    size_t blobStart = HDR + (size_t)mc * MATSZ + (size_t)bc * BATSZ;
    size_t blobLen = len - blobStart;
    fprintf(stderr, "materials=%u batches=%u blob=%zu spawn=(%.1f,%.1f,%.1f)\n", mc, bc, blobLen, hdr[6], hdr[7], hdr[8]);

    int bad = 0; unsigned long tris = 0, sky = 0;
    uint32_t skyMat[4096] = {0};
    for (uint32_t i = 0; i < mc; i++) {
        uint32_t flags; memcpy(&flags, p + HDR + (size_t)i * MATSZ + 76, 4);
        skyMat[i] = (flags & 2) != 0;
    }
    // камера как в GameScene -resetCamera
    float pos[3] = { hdr[6], hdr[7], hdr[8] };
    float cx = 0.5f * (hdr[0] + hdr[3]) - pos[0], cy = 0.5f * (hdr[1] + hdr[4]) - pos[1], cz = 0.5f * (hdr[2] + hdr[5]) - pos[2];
    float horiz = sqrtf(cx * cx + cz * cz);
    float yaw = atan2f(-cx, -cz), pitch = atan2f(cy, fmaxf(horiz, 1.0f));
    pitch = fminf(fmaxf(pitch, -0.6f), 0.3f);
    float dx = hdr[3] - hdr[0], dy = hdr[4] - hdr[1], dz = hdr[5] - hdr[2];
    float diag = sqrtf(dx * dx + dy * dy + dz * dz);
    float far = fminf(fmaxf(diag * 1.1f, 300.0f), 3000.0f);

    float rx[16], ry[16], tp[16], t1[16], view[16], proj[16], vp[16], planes[6][4];
    mat4_rotate_x(rx, -pitch); mat4_rotate_y(ry, -yaw); mat4_translate(tp, -pos[0], -pos[1], -pos[2]);
    mat4_mul(t1, ry, tp); mat4_mul(view, rx, t1);
    mat4_perspective(proj, 60.0f * 3.14159265f / 180.0f, 1.5f, 0.3f, far);
    mat4_mul(vp, proj, view);
    mat4_frustum_planes(planes, vp);
    printf("CAM %f %f %f %f %f %f\n", pos[0], pos[1], pos[2], yaw, pitch, far);

    int passed = 0;
    for (uint32_t i = 0; i < bc; i++) {
        const uint8_t *b = p + HDR + (size_t)mc * MATSZ + (size_t)i * BATSZ;
        uint32_t mat, vc, ic, voff, ioff;
        memcpy(&mat, b, 4); memcpy(&vc, b + 4, 4); memcpy(&ic, b + 8, 4); memcpy(&voff, b + 12, 4); memcpy(&ioff, b + 16, 4);
        float bmin[3], bmax[3]; memcpy(bmin, b + 20, 12); memcpy(bmax, b + 32, 12);
        if (mat >= mc || vc > 65535 || (size_t)voff + (size_t)vc * 32 > blobLen || (size_t)ioff + (size_t)ic * 2 > blobLen || ic % 3) { bad++; continue; }
        // индексы должны ссылаться на существующие вершины
        const uint16_t *idx = (const uint16_t *)(p + blobStart + ioff);
        for (uint32_t k = 0; k < ic; k++) if (idx[k] >= vc) { bad++; break; }
        // bbox батча должен совпадать с вершинами
        const float *v = (const float *)(p + blobStart + voff);
        float mn[3] = {1e30f,1e30f,1e30f}, mx[3] = {-1e30f,-1e30f,-1e30f};
        for (uint32_t k = 0; k < vc; k++) for (int a = 0; a < 3; a++) { float x = v[k*8+a]; if (x < mn[a]) mn[a] = x; if (x > mx[a]) mx[a] = x; }
        for (int a = 0; a < 3; a++) if (fabsf(mn[a]-bmin[a]) > 1e-3f || fabsf(mx[a]-bmax[a]) > 1e-3f) { bad++; break; }
        if (skyMat[mat]) { sky++; printf("B %u 1 -1\n", i); continue; }
        tris += ic / 3;
        int in = aabb_in_frustum((const float (*)[4])planes, bmin, bmax);
        passed += in;
        printf("B %u 0 %d\n", i, in);
    }
    fprintf(stderr, "батчей с ошибками: %d; треугольников (без неба): %lu; батчей неба: %lu; прошло отсечение: %d из %u\n", bad, tris, sky, passed, bc - (uint32_t)sky);
    float vpm[16]; memcpy(vpm, vp, sizeof vpm);
    printf("VP"); for (int i = 0; i < 16; i++) printf(" %f", vpm[i]); printf("\n");
    return bad ? 1 : 0;
}
