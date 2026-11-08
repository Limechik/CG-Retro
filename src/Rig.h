// Риг персонажа из жёстких частей (.cgr из tools/build_character.py): иерархия узлов, части (меш + материал),
// запечённые клипы. Чистый C: поза считается на CPU, рисует ObjC-слой.
#ifndef RIG_H
#define RIG_H

#ifdef __cplusplus
extern "C" {
#endif

#define CGRIG_MAX_NODES 64

typedef struct { int parent; float pos[3], quat[4], scale[3]; char name[20]; } CGRigNode;

typedef struct {
    unsigned node, flags;        // flags: бит0 — обратный обход (отрицательный масштаб), бит1 — cutout
    char  mesh[48], tex[48];
    float color[3], uvst[4];
} CGRigPart;

typedef struct {
    char  name[24];
    float duration;
    int   loop;
    unsigned frames, tracks;
    unsigned *trackNode;         // tracks
    float *data;                 // tracks * frames * 7 (pos[3] + quat[4] на кадр)
} CGRigClip;

typedef struct {
    unsigned nodeCount, partCount, clipCount;
    CGRigNode *nodes;
    CGRigPart *parts;
    CGRigClip *clips;
} CGRig;

// Локальные позы узлов (позиция + кватернион x,y,z,w).
typedef struct { float pos[CGRIG_MAX_NODES][3]; float quat[CGRIG_MAX_NODES][4]; } CGRigPose;

CGRig *cgrig_load(const char *path);                    // NULL при ошибке
void cgrig_free(CGRig *r);
int cgrig_find_clip(const CGRig *r, const char *name);  // -1, если нет

void cgrig_rest_pose(const CGRig *r, CGRigPose *pose);

// Накладывает клип в момент time на позу. weight = 1 — заменить, 0..1 — плавно подмешать (кроссфейд).
// Узлы, которых нет в клипе, не трогаются.
void cgrig_apply_clip(const CGRig *r, int clip, float time, float weight, CGRigPose *pose);

// Мировые матрицы узлов (column-major) от корневой матрицы root.
void cgrig_world(const CGRig *r, const float root[16], const CGRigPose *pose, float world[][16]);

#ifdef __cplusplus
}
#endif
#endif
