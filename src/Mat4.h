// Минимальная математика: матрицы 4x4, column-major (как ждёт OpenGL).
#ifndef MAT4_H
#define MAT4_H
#include <math.h>
#include <string.h>

static inline void mat4_identity(float *m) {
    memset(m, 0, 16 * sizeof(float));
    m[0] = m[5] = m[10] = m[15] = 1.0f;
}

// out = a * b  (out не должен совпадать с a или b)
static inline void mat4_mul(float *out, const float *a, const float *b) {
    for (int c = 0; c < 4; c++)
        for (int r = 0; r < 4; r++) {
            float s = 0;
            for (int k = 0; k < 4; k++) s += a[k * 4 + r] * b[c * 4 + k];
            out[c * 4 + r] = s;
        }
}

static inline void mat4_translate(float *m, float x, float y, float z) {
    mat4_identity(m);
    m[12] = x; m[13] = y; m[14] = z;
}

static inline void mat4_scale(float *m, float s) {
    mat4_identity(m);
    m[0] = m[5] = m[10] = s;
}

static inline void mat4_rotate_x(float *m, float a) {
    float c = cosf(a), s = sinf(a);
    mat4_identity(m);
    m[5] = c; m[9] = -s; m[6] = s; m[10] = c;
}

static inline void mat4_rotate_y(float *m, float a) {
    float c = cosf(a), s = sinf(a);
    mat4_identity(m);
    m[0] = c; m[8] = s; m[2] = -s; m[10] = c;
}

// fovy в радианах
static inline void mat4_perspective(float *m, float fovy, float aspect, float zn, float zf) {
    float f = 1.0f / tanf(fovy * 0.5f);
    memset(m, 0, 16 * sizeof(float));
    m[0] = f / aspect;
    m[5] = f;
    m[10] = (zf + zn) / (zn - zf);
    m[11] = -1.0f;
    m[14] = (2.0f * zf * zn) / (zn - zf);
}

// верхний левый 3x3 блок (для нормалей при вращении + равномерном масштабе)
static inline void mat3_from_mat4(float *out, const float *m) {
    out[0] = m[0]; out[1] = m[1]; out[2] = m[2];
    out[3] = m[4]; out[4] = m[5]; out[5] = m[6];
    out[6] = m[8]; out[7] = m[9]; out[8] = m[10];
}

// 6 плоскостей пирамиды видимости (left, right, bottom, top, near, far) из матрицы vp = proj * view.
// Нормали смотрят внутрь, плоскость: a*x + b*y + c*z + d >= 0.
static inline void mat4_frustum_planes(float planes[6][4], const float *m) {
    for (int i = 0; i < 4; i++) {
        float r3 = m[4 * i + 3];
        planes[0][i] = r3 + m[4 * i + 0];   // left
        planes[1][i] = r3 - m[4 * i + 0];   // right
        planes[2][i] = r3 + m[4 * i + 1];   // bottom
        planes[3][i] = r3 - m[4 * i + 1];   // top
        planes[4][i] = r3 + m[4 * i + 2];   // near
        planes[5][i] = r3 - m[4 * i + 2];   // far
    }
}

// 1, если AABB хотя бы частично внутри пирамиды.
static inline int aabb_in_frustum(const float planes[6][4], const float *bmin, const float *bmax) {
    for (int i = 0; i < 6; i++) {
        float px = planes[i][0] >= 0 ? bmax[0] : bmin[0];
        float py = planes[i][1] >= 0 ? bmax[1] : bmin[1];
        float pz = planes[i][2] >= 0 ? bmax[2] : bmin[2];
        if (planes[i][0] * px + planes[i][1] * py + planes[i][2] * pz + planes[i][3] < 0) return 0;
    }
    return 1;
}
#endif
