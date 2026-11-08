#include "Rig.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>

#define NODE_SIZE 64
#define PART_SIZE 132

static int rd(FILE *f, void *dst, size_t n) { return fread(dst, 1, n, f) == n; }

void cgrig_free(CGRig *r) {
    if (!r) return;
    if (r->clips) for (unsigned i = 0; i < r->clipCount; i++) { free(r->clips[i].trackNode); free(r->clips[i].data); }
    free(r->nodes); free(r->parts); free(r->clips); free(r);
}

CGRig *cgrig_load(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    uint8_t hdr[16];
    if (!rd(f, hdr, 16) || memcmp(hdr, "CGR1", 4) != 0) { fclose(f); return NULL; }
    uint32_t nn, np, nc;
    memcpy(&nn, hdr + 4, 4); memcpy(&np, hdr + 8, 4); memcpy(&nc, hdr + 12, 4);
    if (nn == 0 || nn > CGRIG_MAX_NODES || np > 256 || nc > 64) { fclose(f); return NULL; }

    CGRig *r = (CGRig *)calloc(1, sizeof *r);
    if (!r) { fclose(f); return NULL; }
    r->nodeCount = nn; r->partCount = np; r->clipCount = nc;
    r->nodes = (CGRigNode *)calloc(nn, sizeof(CGRigNode));
    r->parts = (CGRigPart *)calloc(np ? np : 1, sizeof(CGRigPart));
    r->clips = (CGRigClip *)calloc(nc ? nc : 1, sizeof(CGRigClip));
    if (!r->nodes || !r->parts || !r->clips) goto fail;

    for (uint32_t i = 0; i < nn; i++) {
        uint8_t b[NODE_SIZE];
        if (!rd(f, b, NODE_SIZE)) goto fail;
        CGRigNode *n = &r->nodes[i];
        int32_t par; memcpy(&par, b, 4); n->parent = par;
        memcpy(n->pos, b + 4, 12); memcpy(n->quat, b + 16, 16); memcpy(n->scale, b + 32, 12);
        memcpy(n->name, b + 44, 19); n->name[19] = 0;
        if (n->parent >= (int)i) goto fail;                    // родитель обязан идти раньше потомка
    }
    for (uint32_t i = 0; i < np; i++) {
        uint8_t b[PART_SIZE];
        if (!rd(f, b, PART_SIZE)) goto fail;
        CGRigPart *p = &r->parts[i];
        memcpy(&p->node, b, 4); memcpy(&p->flags, b + 4, 4);
        memcpy(p->mesh, b + 8, 47); p->mesh[47] = 0;
        memcpy(p->tex, b + 56, 47); p->tex[47] = 0;
        memcpy(p->color, b + 104, 12); memcpy(p->uvst, b + 116, 16);
        if (p->node >= nn) goto fail;
    }
    for (uint32_t i = 0; i < nc; i++) {
        uint8_t b[40];
        if (!rd(f, b, 40)) goto fail;
        CGRigClip *c = &r->clips[i];
        memcpy(c->name, b, 23); c->name[23] = 0;
        uint32_t loop; memcpy(&c->duration, b + 24, 4); memcpy(&loop, b + 28, 4);
        memcpy(&c->frames, b + 32, 4); memcpy(&c->tracks, b + 36, 4);
        c->loop = (int)loop;
        if (c->frames < 1 || c->frames > 4096 || c->tracks > nn) goto fail;
        c->trackNode = (unsigned *)calloc(c->tracks ? c->tracks : 1, sizeof(unsigned));
        c->data = (float *)malloc((size_t)(c->tracks ? c->tracks : 1) * c->frames * 7 * sizeof(float));
        if (!c->trackNode || !c->data) goto fail;
        for (uint32_t t = 0; t < c->tracks; t++) {
            if (!rd(f, &c->trackNode[t], 4) || c->trackNode[t] >= nn) goto fail;
            if (!rd(f, c->data + (size_t)t * c->frames * 7, (size_t)c->frames * 28)) goto fail;
        }
    }
    {   // в файле не должно быть лишних данных
        int extra = fgetc(f);
        if (extra != EOF) goto fail;
    }
    fclose(f);
    return r;
fail:
    fclose(f);
    cgrig_free(r);
    return NULL;
}

int cgrig_find_clip(const CGRig *r, const char *name) {
    for (unsigned i = 0; i < r->clipCount; i++) if (strcmp(r->clips[i].name, name) == 0) return (int)i;
    return -1;
}

void cgrig_rest_pose(const CGRig *r, CGRigPose *pose) {
    for (unsigned i = 0; i < r->nodeCount; i++) {
        memcpy(pose->pos[i], r->nodes[i].pos, 12);
        memcpy(pose->quat[i], r->nodes[i].quat, 16);
    }
}

void cgrig_apply_clip(const CGRig *r, int clip, float time, float weight, CGRigPose *pose) {
    if (clip < 0 || (unsigned)clip >= r->clipCount || weight <= 0) return;
    if (weight > 1) weight = 1;
    const CGRigClip *c = &r->clips[clip];
    float f = time * 30.0f;                                  // клипы запечены с частотой 30 к/с
    if (c->loop && c->duration > 1e-4f) {
        float tl = fmodf(time, c->duration);
        if (tl < 0) tl += c->duration;
        f = tl * 30.0f;
    }
    int f0 = (int)floorf(f);
    float fr = f - (float)f0;
    int i0, i1;
    if (c->loop) { i0 = ((f0 % (int)c->frames) + (int)c->frames) % (int)c->frames; i1 = (i0 + 1) % (int)c->frames; }
    else {
        i0 = f0 < 0 ? 0 : (f0 >= (int)c->frames ? (int)c->frames - 1 : f0);
        i1 = i0 + 1 >= (int)c->frames ? (int)c->frames - 1 : i0 + 1;
    }
    for (unsigned t = 0; t < c->tracks; t++) {
        const float *a = c->data + ((size_t)t * c->frames + i0) * 7;
        const float *b = c->data + ((size_t)t * c->frames + i1) * 7;
        unsigned n = c->trackNode[t];
        float p[3], q[4];
        for (int k = 0; k < 3; k++) p[k] = a[k] * (1 - fr) + b[k] * fr;
        float sign = (a[3]*b[3] + a[4]*b[4] + a[5]*b[5] + a[6]*b[6]) < 0 ? -1.0f : 1.0f;
        for (int k = 0; k < 4; k++) q[k] = a[3 + k] * (1 - fr) + sign * b[3 + k] * fr;
        float ql = sqrtf(q[0]*q[0] + q[1]*q[1] + q[2]*q[2] + q[3]*q[3]);
        if (ql < 1e-8f) continue;
        for (int k = 0; k < 4; k++) q[k] /= ql;
        if (weight >= 1.0f) {
            memcpy(pose->pos[n], p, 12);
            memcpy(pose->quat[n], q, 16);
        } else {
            float *cq = pose->quat[n];
            float s2 = (cq[0]*q[0] + cq[1]*q[1] + cq[2]*q[2] + cq[3]*q[3]) < 0 ? -1.0f : 1.0f;
            float nq[4], nl = 0;
            for (int k = 0; k < 4; k++) { nq[k] = cq[k] * (1 - weight) + s2 * q[k] * weight; nl += nq[k] * nq[k]; }
            nl = sqrtf(nl);
            for (int k = 0; k < 4; k++) cq[k] = nq[k] / (nl > 1e-8f ? nl : 1.0f);
            for (int k = 0; k < 3; k++) pose->pos[n][k] = pose->pos[n][k] * (1 - weight) + p[k] * weight;
        }
    }
}

// local = T * R * S  (column-major), затем world = parent * local
static void local_matrix(const float *pos, const float *q, const float *s, float *m) {
    float x = q[0], y = q[1], z = q[2], w = q[3];
    float xx = x*x, yy = y*y, zz = z*z, xy = x*y, xz = x*z, yz = y*z, wx = w*x, wy = w*y, wz = w*z;
    float r00 = 1 - 2*(yy + zz), r01 = 2*(xy - wz), r02 = 2*(xz + wy);
    float r10 = 2*(xy + wz), r11 = 1 - 2*(xx + zz), r12 = 2*(yz - wx);
    float r20 = 2*(xz - wy), r21 = 2*(yz + wx), r22 = 1 - 2*(xx + yy);
    m[0] = r00 * s[0]; m[1] = r10 * s[0]; m[2] = r20 * s[0]; m[3] = 0;
    m[4] = r01 * s[1]; m[5] = r11 * s[1]; m[6] = r21 * s[1]; m[7] = 0;
    m[8] = r02 * s[2]; m[9] = r12 * s[2]; m[10] = r22 * s[2]; m[11] = 0;
    m[12] = pos[0]; m[13] = pos[1]; m[14] = pos[2]; m[15] = 1;
}

static void mul44(const float *a, const float *b, float *out) {
    for (int c = 0; c < 4; c++)
        for (int r = 0; r < 4; r++) {
            float s = 0;
            for (int k = 0; k < 4; k++) s += a[k * 4 + r] * b[c * 4 + k];
            out[c * 4 + r] = s;
        }
}

void cgrig_world(const CGRig *r, const float root[16], const CGRigPose *pose, float world[][16]) {
    for (unsigned i = 0; i < r->nodeCount; i++) {
        float local[16];
        local_matrix(pose->pos[i], pose->quat[i], r->nodes[i].scale, local);
        const float *parent = r->nodes[i].parent >= 0 ? world[r->nodes[i].parent] : root;
        mul44(parent, local, world[i]);
    }
}
