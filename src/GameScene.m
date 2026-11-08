#import "GameScene.h"
#import "Shaders.h"
#import "Texture.h"
#import "Mat4.h"
#import "Collision.h"
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

#define CGS_HEADER_SIZE 48
#define CGS_MATERIAL_SIZE 80
#define CGS_BATCH_SIZE 48
#define FLAG_CUTOUT 1u
#define FLAG_SKY    2u

typedef struct {
    int   texIndex;          // -1 = без текстуры
    float color[3];
    float uvst[4];
    BOOL  cutout, sky;
} SceneMat;

typedef struct {
    GLuint  vbo, ibo;
    GLsizei indexCount;
    int     mat;
    float   bmin[3], bmax[3];
} SceneBatch;

@implementation GameScene {
    CGProgram _P;
    BOOL _programReady;

    SceneMat   *_mats;     NSUInteger _matCount;
    SceneBatch *_batches;  NSUInteger _batchCount;
    CGTexture  *_texs;     NSUInteger _texCount;

    float _bmin[3], _bmax[3], _spawn[3];
    float _view[16], _projM[16];   // матрицы последнего кадра (для декалей и оружия)
    float _pos[3];             // положение камеры (в режиме ходьбы = ноги + высота глаз)
    float _near, _far;

    CGCollision *_col;
    CGPlayer _player;
    BOOL _walk;
    BOOL _jumpRequested;
    float _fallY;              // ниже этой высоты игрок считается упавшим за карту
    int   _w, _h;
}

@synthesize name = _name, loaded = _loaded, moveSpeed = _moveSpeed;
@synthesize hasCollision = _hasCollision, onGround = _onGround;

- (void)dealloc { [self unload]; }

- (void)unload {
    for (NSUInteger i = 0; i < _batchCount; i++) {
        if (_batches[i].vbo) glDeleteBuffers(1, &_batches[i].vbo);
        if (_batches[i].ibo) glDeleteBuffers(1, &_batches[i].ibo);
    }
    for (NSUInteger i = 0; i < _texCount; i++) CGTextureFree(&_texs[i]);
    if (_col) { cgc_free(_col); _col = NULL; }
    _hasCollision = NO; _walk = NO; _onGround = NO;
    free(_mats); free(_batches); free(_texs);
    _mats = NULL; _batches = NULL; _texs = NULL;
    _matCount = _batchCount = _texCount = 0;
    _loaded = NO;
}

- (BOOL)loadFromPath:(NSString *)path name:(NSString *)name {
    [self unload];
    if (!_programReady) _programReady = CGProgramBuild(&_P);
    if (!_programReady) return NO;

    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data || [data length] < CGS_HEADER_SIZE) { NSLog(@"[Scene] не прочитан %@", path); return NO; }
    const uint8_t *p = (const uint8_t *)[data bytes];
    if (memcmp(p, "CGS1", 4) != 0) { NSLog(@"[Scene] не CGS1: %@", path); return NO; }

    uint32_t mc, bc;
    memcpy(&mc, p + 4, 4);
    memcpy(&bc, p + 8, 4);
    float hdr[9];
    memcpy(hdr, p + 12, sizeof(hdr));
    for (int i = 0; i < 3; i++) { _bmin[i] = hdr[i]; _bmax[i] = hdr[3 + i]; _spawn[i] = hdr[6 + i]; }

    size_t blobStart = CGS_HEADER_SIZE + (size_t)mc * CGS_MATERIAL_SIZE + (size_t)bc * CGS_BATCH_SIZE;
    if (mc > 4096 || bc > 65536 || [data length] < blobStart) { NSLog(@"[Scene] битый заголовок"); return NO; }
    size_t blobLen = [data length] - blobStart;
    const uint8_t *blob = p + blobStart;

    // --- материалы и текстуры (каждая уникальная текстура грузится один раз)
    _mats = (SceneMat *)calloc(mc ? mc : 1, sizeof(SceneMat));
    _texs = (CGTexture *)calloc(mc ? mc : 1, sizeof(CGTexture));
    _matCount = mc;
    NSMutableDictionary *texIndexByName = [NSMutableDictionary dictionary];
    NSString *texDir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"textures"];

    for (uint32_t i = 0; i < mc; i++) {
        const uint8_t *m = p + CGS_HEADER_SIZE + (size_t)i * CGS_MATERIAL_SIZE;
        char tn[49]; memcpy(tn, m, 48); tn[48] = 0;
        uint32_t flags;
        memcpy(_mats[i].color, m + 48, 12);
        memcpy(_mats[i].uvst,  m + 60, 16);
        memcpy(&flags, m + 76, 4);
        _mats[i].cutout = (flags & FLAG_CUTOUT) != 0;
        _mats[i].sky    = (flags & FLAG_SKY) != 0;
        _mats[i].texIndex = -1;
        if (tn[0]) {
            NSString *key = [NSString stringWithUTF8String:tn];
            NSNumber *known = texIndexByName[key];
            if (known) {
                _mats[i].texIndex = [known intValue];
            } else {
                NSString *tp = [[texDir stringByAppendingPathComponent:key] stringByAppendingPathExtension:@"cgt"];
                CGTexture t;
                if (CGTextureLoad(tp, &t)) {
                    _texs[_texCount] = t;
                    texIndexByName[key] = @(_texCount);
                    _mats[i].texIndex = (int)_texCount++;
                } else {
                    NSLog(@"[Scene] нет текстуры %@", tp);
                }
            }
        }
    }

    // --- батчи
    _batches = (SceneBatch *)calloc(bc ? bc : 1, sizeof(SceneBatch));
    NSUInteger tris = 0;
    for (uint32_t i = 0; i < bc; i++) {
        const uint8_t *b = p + CGS_HEADER_SIZE + (size_t)mc * CGS_MATERIAL_SIZE + (size_t)i * CGS_BATCH_SIZE;
        uint32_t mat, vc, ic, voff, ioff;
        memcpy(&mat, b, 4); memcpy(&vc, b + 4, 4); memcpy(&ic, b + 8, 4);
        memcpy(&voff, b + 12, 4); memcpy(&ioff, b + 16, 4);
        if (mat >= mc || vc > 65535 || (size_t)voff + (size_t)vc * 32 > blobLen ||
            (size_t)ioff + (size_t)ic * 2 > blobLen) {
            NSLog(@"[Scene] батч %u повреждён, сцена отклонена", i);
            [self unload];
            return NO;
        }
        SceneBatch *sb = &_batches[i];
        sb->mat = (int)mat;
        sb->indexCount = (GLsizei)ic;
        memcpy(sb->bmin, b + 20, 12);
        memcpy(sb->bmax, b + 32, 12);

        glGenBuffers(1, &sb->vbo);
        glBindBuffer(GL_ARRAY_BUFFER, sb->vbo);
        glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)vc * 32, blob + voff, GL_STATIC_DRAW);
        glGenBuffers(1, &sb->ibo);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, sb->ibo);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, (GLsizeiptr)ic * 2, blob + ioff, GL_STATIC_DRAW);
        if (!_mats[mat].sky) tris += ic / 3;
    }
    _batchCount = bc;
    _triangleTotal = tris;
    _batchTotal = bc;

    // параметры камеры от размера сцены
    float dx = _bmax[0] - _bmin[0], dy = _bmax[1] - _bmin[1], dz = _bmax[2] - _bmin[2];
    float diag = sqrtf(dx * dx + dy * dy + dz * dz);
    _near = 0.3f;
    _far = fminf(fmaxf(diag * 1.1f, 300.0f), 3000.0f);
    _moveSpeed = fminf(fmaxf(diag / 40.0f, 6.0f), 40.0f);

    // коллизия лежит рядом: Имя.cgc
    NSString *cgcPath = [[path stringByDeletingPathExtension] stringByAppendingPathExtension:@"cgc"];
    _col = cgc_load([cgcPath fileSystemRepresentation]);
    _hasCollision = (_col != NULL);
    _fallY = -1.0e9f;
    if (_col) { float cmin[3], cmax[3]; cgc_bounds(_col, cmin, cmax); _fallY = cmin[1] - 40.0f; }
    if (!_hasCollision) NSLog(@"[Scene] нет коллизии %@ — доступен только полёт", cgcPath);

    _name = name;
    _loaded = YES;
    _walk = _hasCollision;                 // по умолчанию ходим, если есть коллизия
    [self resetCamera];
    NSLog(@"[Scene] %@: %u батчей, %u материалов, %lu текстур, %lu треугольников",
          name, bc, mc, (unsigned long)_texCount, (unsigned long)tris);
    return YES;
}

#pragma mark - Камера

- (void)resetCamera {
    for (int i = 0; i < 3; i++) _pos[i] = _spawn[i];
    // смотрим в центр сцены
    float cx = 0.5f * (_bmin[0] + _bmax[0]) - _pos[0];
    float cy = 0.5f * (_bmin[1] + _bmax[1]) - _pos[1];
    float cz = 0.5f * (_bmin[2] + _bmax[2]) - _pos[2];
    float horiz = sqrtf(cx * cx + cz * cz);
    self.yaw = (horiz > 1e-3f) ? atan2f(-cx, -cz) : 0.0f;
    float pitch = atan2f(cy, fmaxf(horiz, 1.0f));
    self.pitch = fminf(fmaxf(pitch, -0.6f), 0.3f);

    [self respawnPlayer];
}

// Игрок встаёт в точку появления (в .cgs спавн хранится на высоте глаз 1.7 м над точкой).
- (void)respawnPlayer {
    float feet[3] = { _spawn[0], _spawn[1] - 1.7f, _spawn[2] };
    cgplayer_init(&_player, feet);
    _jumpRequested = NO;
    if (_walk && _col) {
        _pos[0] = _player.pos[0];
        _pos[1] = _player.pos[1] + _player.eyeHeight;
        _pos[2] = _player.pos[2];
    }
}

- (BOOL)walkMode { return _walk && _hasCollision; }

- (void)setWalkMode:(BOOL)walk {
    if (walk && !_hasCollision) return;
    if (walk && !_walk) {                  // из полёта: встаём там, где камера, и падаем
        float feet[3] = { _pos[0], _pos[1] - 1.25f, _pos[2] };
        cgplayer_init(&_player, feet);
    }
    _walk = walk;
}

- (void)jump { _jumpRequested = YES; }

- (void)moveForward:(float)fwd strafe:(float)strafe dt:(float)dt {
    if (_pitch > 1.5f) _pitch = 1.5f;
    if (_pitch < -1.5f) _pitch = -1.5f;

    if (_walk && _col) {
        cgplayer_update(&_player, _col, fwd, strafe, _yaw, _jumpRequested ? 1 : 0, dt);
        _jumpRequested = NO;
        _onGround = _player.onGround != 0;
        if (_player.pos[1] < _fallY) [self respawnPlayer];   // упали за карту
        _pos[0] = _player.pos[0];
        _pos[1] = _player.pos[1] + _player.eyeHeight;
        _pos[2] = _player.pos[2];
        return;
    }

    float sy = sinf(_yaw), cy = cosf(_yaw), sp = sinf(_pitch), cp = cosf(_pitch);
    float f[3] = { -sy * cp, sp, -cy * cp };      // взгляд
    float r[3] = { cy, 0.0f, -sy };               // вправо
    float k = _moveSpeed * dt;
    for (int i = 0; i < 3; i++) _pos[i] += (f[i] * fwd + r[i] * strafe) * k;
}

- (void)resizeWidth:(int)w height:(int)h { _w = w; _h = h; }

#pragma mark - Для оружия

- (const CGCollision *)collision { return _col; }

- (void)playerFeet:(float *)out {
    if (_walk && _col) { out[0] = _player.pos[0]; out[1] = _player.pos[1]; out[2] = _player.pos[2]; }
    else               { out[0] = _pos[0]; out[1] = _pos[1] - 1.25f; out[2] = _pos[2]; }   // в полёте: под камерой
}

- (float)aspect { return (_h > 0) ? (float)_w / (float)_h : 1.5f; }

- (void)eyePosition:(float *)out { out[0] = _pos[0]; out[1] = _pos[1]; out[2] = _pos[2]; }

- (void)getView:(float *)view proj:(float *)proj {
    memcpy(view, _view, sizeof(_view));
    memcpy(proj, _projM, sizeof(_projM));
}

- (BOOL)raycastFrom:(const float *)origin dir:(const float *)dir maxDist:(float)maxDist hit:(CGHit *)hit {
    if (!_col) return NO;
    return cgc_raycast(_col, origin, dir, maxDist, hit) != 0;
}

#pragma mark - Отрисовка

- (void)applyMaterial:(const SceneMat *)m {
    glUniform3f(_P.uColor, m->color[0], m->color[1], m->color[2]);
    glUniform4f(_P.uUVST, m->uvst[0], m->uvst[1], m->uvst[2], m->uvst[3]);
    BOOL hasTex = (m->texIndex >= 0);
    glUniform1f(_P.uHasTex, hasTex ? 1.0f : 0.0f);
    glUniform1f(_P.uCutout, (hasTex && m->cutout) ? 1.0f : 0.0f);
    glBindTexture(GL_TEXTURE_2D, hasTex ? _texs[m->texIndex].name : 0);
}

- (void)draw {
    glClearColor(0.45f, 0.62f, 0.85f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    _batchesDrawn = 0; _trianglesDrawn = 0;
    if (!_loaded || _w == 0 || _h == 0) return;

    float rx[16], ry[16], tp[16], t1[16], view[16], proj[16], vp[16];
    mat4_rotate_x(rx, -_pitch);
    mat4_rotate_y(ry, -_yaw);
    mat4_translate(tp, -_pos[0], -_pos[1], -_pos[2]);
    mat4_mul(t1, ry, tp);
    mat4_mul(view, rx, t1);
    mat4_perspective(proj, 60.0f * (float)M_PI / 180.0f, (float)_w / (float)_h, _near, _far);
    mat4_mul(vp, proj, view);
    memcpy(_view, view, sizeof(view));
    memcpy(_projM, proj, sizeof(proj));

    float planes[6][4];
    mat4_frustum_planes(planes, vp);

    float nm[9] = { 1, 0, 0, 0, 1, 0, 0, 0, 1 };      // нормали уже в мировых координатах

    glUseProgram(_P.prog);
    CGProgramSetDefaults(&_P);
    glUniformMatrix4fv(_P.uMV, 1, GL_FALSE, view);
    glUniformMatrix4fv(_P.uProj, 1, GL_FALSE, proj);
    glUniformMatrix3fv(_P.uNormalMat, 1, GL_FALSE, nm);
    glUniform3f(_P.uLightDir, 0.4f, 0.8f, 0.6f);
    glActiveTexture(GL_TEXTURE0);
    glUniform1i(_P.uTex, 0);

    // 1) небо: без глубины и освещения, обе стороны
    glUniform1f(_P.uUnlit, 1.0f);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    int last = -1;
    for (NSUInteger i = 0; i < _batchCount; i++) {
        const SceneBatch *b = &_batches[i];
        if (!_mats[b->mat].sky) continue;
        if (b->mat != last) { [self applyMaterial:&_mats[b->mat]]; last = b->mat; }
        CGBindVertexLayout(b->vbo, b->ibo);
        glDrawElements(GL_TRIANGLES, b->indexCount, GL_UNSIGNED_SHORT, (const void *)0);
    }

    // 2) геометрия с отсечением
    glUniform1f(_P.uUnlit, 0.0f);
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);
    last = -1;
    for (NSUInteger i = 0; i < _batchCount; i++) {
        const SceneBatch *b = &_batches[i];
        if (_mats[b->mat].sky) continue;
        if (!aabb_in_frustum((const float (*)[4])planes, b->bmin, b->bmax)) continue;
        if (b->mat != last) { [self applyMaterial:&_mats[b->mat]]; last = b->mat; }
        CGBindVertexLayout(b->vbo, b->ibo);
        glDrawElements(GL_TRIANGLES, b->indexCount, GL_UNSIGNED_SHORT, (const void *)0);
        _batchesDrawn++;
        _trianglesDrawn += b->indexCount / 3;
    }
}

@end
