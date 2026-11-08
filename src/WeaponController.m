#import "WeaponController.h"
#import "GameScene.h"
#import "BotController.h"
#import "AudioEngine.h"
#import "Shaders.h"
#import "Mesh.h"
#import "Texture.h"
#import "Mat4.h"
#import "Weapon.h"
#import <OpenGLES/ES2/gl.h>

#define MAX_DECALS 96
#define FLASH_TIME 0.05f
#define DEG2RAD (3.14159265f / 180.0f)

typedef struct {
    CGWeaponDef def;
    char  title[32], mesh[48], tex[48], shotSound[32], reloadSound[32];
    float color[3], uvst[4];
    float viewLength, extentX, muzzle[3];
    int orient;                 // ориентация меши: 0 — как есть, 1 — вверх ногами (Rx 180°), 2 — ствол в -X (Ry 180°)
} WeaponInfo;

// Точка (x,y,z,1) через матрицу column-major.
static void MulPoint(const float *m, const float *p, float *out) {
    for (int r = 0; r < 3; r++) out[r] = m[r] * p[0] + m[4 + r] * p[1] + m[8 + r] * p[2] + m[12 + r];
}

@implementation WeaponController {
    CGProgram _P;
    WeaponInfo *_w;
    CGWeaponState *_st;
    NSUInteger _count, _cur;

    BOOL _fireHeld, _firePressed, _reloadReq;

    CGMesh _vm;      BOOL _vmLoaded;
    CGTexture _vmTex; BOOL _vmTexLoaded;
    CGTexture _flashTex, _holeTex;
    BOOL _flashLoaded, _holeLoaded;
    NSString *_meshDir, *_texDir;

    float _kick, _flashTime, _flashAngle, _raise;
    float _decals[MAX_DECALS * 6 * 8];       // 6 вершин на след, 8 float на вершину
    int _decalCount, _decalHead;
    unsigned _visRng;
    int _hitEvent;
}

@synthesize bots = _bots;
@synthesize audio = _audio;

- (void)dealloc { free(_w); free(_st); }

#pragma mark - Подготовка

- (float)visRand {            // [0,1), только для визуальных эффектов
    unsigned x = _visRng ? _visRng : 88172645u;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    _visRng = x;
    return (float)(x & 0xFFFFFF) / 16777216.0f;
}

- (BOOL)setup {
    if (!CGProgramBuild(&_P)) return NO;
    NSString *res = [[NSBundle mainBundle] resourcePath];
    _meshDir = [res stringByAppendingPathComponent:@"meshes"];
    _texDir  = [res stringByAppendingPathComponent:@"textures"];

    NSArray *list = [NSArray arrayWithContentsOfFile:[res stringByAppendingPathComponent:@"weapons.plist"]];
    if ([list count] == 0) { NSLog(@"[Weapons] weapons.plist не найден или пуст"); return NO; }

    _w  = (WeaponInfo *)calloc([list count], sizeof(WeaponInfo));
    _st = (CGWeaponState *)calloc([list count], sizeof(CGWeaponState));
    for (NSUInteger i = 0; i < [list count]; i++) {
        NSDictionary *d = list[i];
        WeaponInfo *w = &_w[i];
        strncpy(w->def.name, [d[@"id"] UTF8String], sizeof(w->def.name) - 1);
        strncpy(w->title, [d[@"title"] UTF8String], sizeof(w->title) - 1);
        strncpy(w->shotSound, [d[@"shotSound"] UTF8String], sizeof(w->shotSound) - 1);
        strncpy(w->reloadSound, [d[@"reloadSound"] UTF8String], sizeof(w->reloadSound) - 1);
        strncpy(w->mesh, [d[@"mesh"] UTF8String], sizeof(w->mesh) - 1);
        strncpy(w->tex,  [d[@"tex"]  UTF8String], sizeof(w->tex) - 1);
        w->def.damage     = [d[@"damage"] floatValue];
        w->def.interval   = [d[@"interval"] floatValue];
        w->def.spreadX    = [d[@"spreadX"] floatValue];
        w->def.spreadY    = [d[@"spreadY"] floatValue];
        w->def.pellets    = [d[@"pellets"] intValue];
        w->def.magSize    = [d[@"mag"] intValue];
        w->def.reloadTime = [d[@"reload"] floatValue];
        w->def.automatic  = [d[@"automatic"] boolValue] ? 1 : 0;
        w->def.range      = [d[@"range"] floatValue];
        w->def.kickPitch  = [d[@"kick"] floatValue];
        w->viewLength     = [d[@"viewLength"] floatValue];
        w->extentX        = [d[@"extentX"] floatValue];
        w->orient         = [d[@"orient"] intValue];
        NSArray *c = d[@"color"], *u = d[@"uvst"], *m = d[@"muzzle"];
        for (int k = 0; k < 3; k++) { w->color[k] = [c[k] floatValue]; w->muzzle[k] = [m[k] floatValue]; }
        for (int k = 0; k < 4; k++) w->uvst[k] = [u[k] floatValue];
        if (w->def.pellets < 1) w->def.pellets = 1;
        if (w->extentX < 0.01f) w->extentX = 1.0f;
        cgweapon_init(&_st[i], &w->def, 1234567u + (unsigned)i * 7919u);
    }
    _count = [list count];
    _cur = 0;

    NSString *fp = [[_texDir stringByAppendingPathComponent:@"GunFlash"] stringByAppendingPathExtension:@"cgt"];
    NSString *hp = [[_texDir stringByAppendingPathComponent:@"hole2"] stringByAppendingPathExtension:@"cgt"];
    _flashLoaded = CGTextureLoad(fp, &_flashTex);
    _holeLoaded  = CGTextureLoad(hp, &_holeTex);
    if (!_flashLoaded || !_holeLoaded) NSLog(@"[Weapons] нет текстур вспышки/следа (%d/%d)", _flashLoaded, _holeLoaded);

    [self loadViewModel];
    _raise = 1.0f;
    return YES;
}

- (void)loadViewModel {
    if (_vmLoaded)    { CGMeshFree(&_vm); _vmLoaded = NO; }
    if (_vmTexLoaded) { CGTextureFree(&_vmTex); _vmTexLoaded = NO; }
    if (_count == 0) return;
    WeaponInfo *w = &_w[_cur];
    NSString *mp = [[_meshDir stringByAppendingPathComponent:[NSString stringWithUTF8String:w->mesh]]
                    stringByAppendingPathExtension:@"cgm"];
    NSString *tp = [[_texDir stringByAppendingPathComponent:[NSString stringWithUTF8String:w->tex]]
                    stringByAppendingPathExtension:@"cgt"];
    _vmLoaded = CGMeshLoad(mp, &_vm);
    _vmTexLoaded = CGTextureLoad(tp, &_vmTex);
    if (!_vmLoaded) NSLog(@"[Weapons] не загружен меш %@", mp);
}

#pragma mark - Состояние для HUD

- (NSString *)weaponTitle {
    return _count ? [NSString stringWithUTF8String:_w[_cur].title] : @"";
}
- (int)ammo { return _count ? _st[_cur].ammo : 0; }
- (int)magSize { return _count ? _w[_cur].def.magSize : 0; }
- (BOOL)reloading { return _count && _st[_cur].reloadLeft > 0; }
- (NSUInteger)weaponCount { return _count; }
- (NSUInteger)weaponIndex { return _cur; }

#pragma mark - Управление

- (void)switchTo:(NSUInteger)i {
    if (_count == 0 || i == _cur) return;
    _cur = i;
    _raise = 1.0f;                         // оружие «поднимается»
    _kick = 0; _flashTime = 0;
    _fireHeld = NO; _firePressed = NO; _reloadReq = NO;
    [self loadViewModel];
}
- (void)selectWeaponAtIndex:(NSUInteger)i { if (i < _count) [self switchTo:i]; }
- (void)nextWeapon { if (_count) [self switchTo:(_cur + 1) % _count]; }
- (void)prevWeapon { if (_count) [self switchTo:(_cur + _count - 1) % _count]; }
- (void)setFireHeld:(BOOL)held { _fireHeld = held; }
- (void)pressFire { _firePressed = YES; }
- (void)requestReload { _reloadReq = YES; }

#pragma mark - Выстрелы

- (void)addDecalAtHit:(const CGHit *)hit small:(BOOL)small {
    const float *n = hit->normal;
    float ref[3] = { 0, 1, 0 };
    if (fabsf(n[1]) > 0.9f) { ref[0] = 1; ref[1] = 0; }
    float t[3] = { ref[1]*n[2] - ref[2]*n[1], ref[2]*n[0] - ref[0]*n[2], ref[0]*n[1] - ref[1]*n[0] };
    float tl = sqrtf(t[0]*t[0] + t[1]*t[1] + t[2]*t[2]);
    if (tl < 1e-6f) return;
    for (int i = 0; i < 3; i++) t[i] /= tl;
    float b[3] = { n[1]*t[2] - n[2]*t[1], n[2]*t[0] - n[0]*t[2], n[0]*t[1] - n[1]*t[0] };

    float ang = [self visRand] * 6.2831853f, ca = cosf(ang), sa = sinf(ang);
    float tt[3], bb[3];
    for (int i = 0; i < 3; i++) { tt[i] = t[i] * ca + b[i] * sa; bb[i] = -t[i] * sa + b[i] * ca; }
    float size = (small ? 0.04f : 0.07f) + 0.02f * [self visRand];
    float c[3];
    for (int i = 0; i < 3; i++) c[i] = hit->point[i] + n[i] * 0.012f;      // чуть над поверхностью

    static const float cu[4][2] = { {0, 0}, {1, 0}, {1, 1}, {0, 1} };
    static const float cs[4][2] = { {-1, -1}, {1, -1}, {1, 1}, {-1, 1} };
    float corner[4][8];
    for (int k = 0; k < 4; k++) {
        for (int i = 0; i < 3; i++) corner[k][i] = c[i] + tt[i] * cs[k][0] * size + bb[i] * cs[k][1] * size;
        corner[k][3] = n[0]; corner[k][4] = n[1]; corner[k][5] = n[2];
        corner[k][6] = cu[k][0]; corner[k][7] = cu[k][1];
    }
    static const int tri[6] = { 0, 1, 2, 0, 2, 3 };
    float *dst = &_decals[_decalHead * 6 * 8];
    for (int v = 0; v < 6; v++) memcpy(dst + v * 8, corner[tri[v]], 8 * sizeof(float));
    _decalHead = (_decalHead + 1) % MAX_DECALS;
    if (_decalCount < MAX_DECALS) _decalCount++;
}

- (void)fireFromScene:(GameScene *)scene weapon:(WeaponInfo *)w state:(CGWeaponState *)st {
    float origin[3];
    [scene eyePosition:origin];
    BOOL playedImpact = NO, playedHit = NO;
    for (int p = 0; p < w->def.pellets; p++) {
        float dir[3];
        cgweapon_shot_dir(&w->def, st, scene.yaw, scene.pitch, dir);
        CGHit hit;
        BOOL worldHit = [scene raycastFrom:origin dir:dir maxDist:w->def.range hit:&hit];
        float limit = worldHit ? hit.t : w->def.range;          // враг считается, только если он ближе стены

        BOOL botHit = NO;
        if (_bots) {
            float t; BOOL head = NO, killed = NO;
            botHit = [_bots hitWithOrigin:origin dir:dir maxDist:limit damage:w->def.damage
                                 distance:&t head:&head killed:&killed];
            if (botHit) {
                int e = killed ? 2 : 1; if (e > _hitEvent) _hitEvent = e;
                if (!playedHit) { [_audio play:@"hit_bot"]; playedHit = YES; }
            }
        }
        if (worldHit && !botHit) {
            [self addDecalAtHit:&hit small:(w->def.pellets > 1)];
            if (!playedImpact) { [_audio play:@"impact" at:hit.point]; playedImpact = YES; }
        }
    }
    _kick = 1.0f;
    _flashTime = FLASH_TIME;
    _flashAngle = [self visRand] * 6.2831853f;
    float kick = w->def.kickPitch * DEG2RAD;
    scene.pitch += kick;
    scene.yaw += kick * 0.4f * ([self visRand] - 0.5f) * 2.0f;
}

- (void)updateWithScene:(GameScene *)scene dt:(float)dt {
    if (_count == 0 || !scene.loaded) return;
    WeaponInfo *w = &_w[_cur];
    CGWeaponState *st = &_st[_cur];

    CGWeaponEvents ev;
    cgweapon_update(st, &w->def, _fireHeld, _firePressed, _reloadReq, dt, &ev);
    _firePressed = NO;
    _reloadReq = NO;

    if (ev.dryFire) [_audio play:@"dry"];
    if (ev.reloadStarted) [_audio play:[NSString stringWithUTF8String:w->reloadSound]];
    for (int i = 0; i < ev.shots; i++) {
        [_audio play:[NSString stringWithUTF8String:w->shotSound]];
        [self fireFromScene:scene weapon:w state:st];
    }

    // затухание анимаций
    _kick -= dt * 9.0f;           if (_kick < 0) _kick = 0;
    _flashTime -= dt;             if (_flashTime < 0) _flashTime = 0;
    _raise -= dt * 4.0f;          if (_raise < 0) _raise = 0;
}

- (void)clearDecals { _decalCount = 0; _decalHead = 0; }

- (int)consumeHitEvent { int e = _hitEvent; _hitEvent = 0; return e; }

#pragma mark - Отрисовка

- (void)bindClientVertices:(const float *)v {
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    glEnableVertexAttribArray(ATTR_POS);
    glEnableVertexAttribArray(ATTR_NORMAL);
    glEnableVertexAttribArray(ATTR_UV);
    glVertexAttribPointer(ATTR_POS,    3, GL_FLOAT, GL_FALSE, 32, v);
    glVertexAttribPointer(ATTR_NORMAL, 3, GL_FLOAT, GL_FALSE, 32, v + 3);
    glVertexAttribPointer(ATTR_UV,     2, GL_FLOAT, GL_FALSE, 32, v + 6);
}

- (void)drawDecalsWithView:(const float *)view proj:(const float *)proj {
    if (_decalCount == 0 || !_holeLoaded) return;
    float nm[9] = { 1, 0, 0, 0, 1, 0, 0, 0, 1 };
    glUseProgram(_P.prog);
    CGProgramSetDefaults(&_P);
    glUniformMatrix4fv(_P.uMV, 1, GL_FALSE, view);
    glUniformMatrix4fv(_P.uProj, 1, GL_FALSE, proj);
    glUniformMatrix3fv(_P.uNormalMat, 1, GL_FALSE, nm);
    glUniform3f(_P.uColor, 1, 1, 1);
    glUniform4f(_P.uUVST, 1, 1, 0, 0);
    glUniform1f(_P.uHasTex, 1.0f);
    glUniform1f(_P.uCutout, 0.0f);
    glUniform1f(_P.uUnlit, 1.0f);
    glUniform1f(_P.uTexAlpha, 1.0f);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, _holeTex.name);
    glUniform1i(_P.uTex, 0);

    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glDepthMask(GL_FALSE);
    glDisable(GL_CULL_FACE);
    glEnable(GL_POLYGON_OFFSET_FILL);
    glPolygonOffset(-1.0f, -1.0f);

    [self bindClientVertices:_decals];
    glDrawArrays(GL_TRIANGLES, 0, _decalCount * 6);

    glDisable(GL_POLYGON_OFFSET_FILL);
    glEnable(GL_CULL_FACE);
    glDepthMask(GL_TRUE);
    glDisable(GL_BLEND);
}

- (void)drawViewModelWithScene:(GameScene *)scene {
    if (!_vmLoaded) return;
    WeaponInfo *w = &_w[_cur];
    CGWeaponState *st = &_st[_cur];

    float proj[16];
    mat4_perspective(proj, 60.0f * DEG2RAD, [scene aspect], 0.03f, 10.0f);

    // анимации: отдача, перезарядка (оружие уходит вниз и наклоняется), появление
    float dip = 0, tilt = 0;
    if (st->reloadLeft > 0 && w->def.reloadTime > 0) {
        float prog = 1.0f - st->reloadLeft / w->def.reloadTime;
        float k = sinf(prog * 3.14159265f);
        dip = 0.20f * k;
        tilt = 0.55f * k;
    }
    float ox = 0.20f;
    float oy = -0.20f - dip - _raise * 0.35f;
    float oz = -0.34f + _kick * 0.06f;
    float pitchUp = _kick * 0.07f - tilt;

    float s = w->viewLength / w->extentX;
    float tr[16], rx[16], ry[16], sc[16], b[16], model[16], rot[16];
    mat4_translate(tr, ox, oy, oz);
    mat4_rotate_x(rx, pitchUp);
    mat4_rotate_y(ry, 93.0f * DEG2RAD);        // ствол (+X в меши) -> вперёд (-Z), чуть к центру экрана
    mat4_scale(sc, s);
    // Меши оружия в дампе повёрнуты: у большинства прицел и магазин снизу (orient 1), у AUG ствол в -X (orient 2).
    // fx приводит меш к стойке «ствол +X, верх +Y» до остальных поворотов.
    float fx[16], rot0[16];
    mat4_identity(fx);
    if (w->orient == 1)      { fx[5] = -1.0f; fx[10] = -1.0f; }    // (x, y, z) -> (x, -y, -z)
    else if (w->orient == 2) { fx[0] = -1.0f; fx[10] = -1.0f; }    // (x, y, z) -> (-x, y, -z)
    mat4_mul(rot0, rx, ry);
    mat4_mul(rot, rot0, fx);                   // вращение (для нормалей)
    mat4_mul(b, rot, sc);
    mat4_mul(model, tr, b);

    float nm[9];
    mat3_from_mat4(nm, rot);

    glClear(GL_DEPTH_BUFFER_BIT);              // оружие не должно уходить в стены
    glUseProgram(_P.prog);
    CGProgramSetDefaults(&_P);
    glUniformMatrix4fv(_P.uMV, 1, GL_FALSE, model);
    glUniformMatrix4fv(_P.uProj, 1, GL_FALSE, proj);
    glUniformMatrix3fv(_P.uNormalMat, 1, GL_FALSE, nm);
    glUniform3f(_P.uLightDir, 0.3f, 0.7f, 0.6f);
    glUniform3f(_P.uColor, w->color[0], w->color[1], w->color[2]);
    glUniform4f(_P.uUVST, w->uvst[0], w->uvst[1], w->uvst[2], w->uvst[3]);
    glUniform1f(_P.uHasTex, _vmTexLoaded ? 1.0f : 0.0f);
    glUniform1f(_P.uCutout, 0.0f);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, _vmTexLoaded ? _vmTex.name : 0);
    glUniform1i(_P.uTex, 0);
    CGBindVertexLayout(_vm.vbo, _vm.ibo);
    glDrawElements(GL_TRIANGLES, _vm.indexCount, GL_UNSIGNED_SHORT, (const void *)0);

    // дульная вспышка: билборд на конце ствола
    if (_flashTime > 0 && _flashLoaded) {
        float local[3] = { w->muzzle[0] + (w->orient == 2 ? -0.05f : 0.05f), w->muzzle[1], w->muzzle[2] };   // чуть дальше конца ствола
        float c[3];
        MulPoint(model, local, c);
        float half = 0.11f * (w->viewLength / 0.6f);
        float ca = cosf(_flashAngle) * half, sa = sinf(_flashAngle) * half;
        static const float cs[4][2] = { {-1, -1}, {1, -1}, {1, 1}, {-1, 1} };
        static const float cu[4][2] = { {0, 0}, {1, 0}, {1, 1}, {0, 1} };
        static const int tri[6] = { 0, 1, 2, 0, 2, 3 };
        float corner[4][8], verts[6 * 8];
        for (int k = 0; k < 4; k++) {
            float x = cs[k][0], y = cs[k][1];
            corner[k][0] = c[0] + x * ca - y * sa;
            corner[k][1] = c[1] + x * sa + y * ca;
            corner[k][2] = c[2];
            corner[k][3] = 0; corner[k][4] = 0; corner[k][5] = 1;
            corner[k][6] = cu[k][0]; corner[k][7] = cu[k][1];
        }
        for (int v = 0; v < 6; v++) memcpy(verts + v * 8, corner[tri[v]], 8 * sizeof(float));

        float ident[16], identNm[9] = { 1, 0, 0, 0, 1, 0, 0, 0, 1 };
        mat4_identity(ident);
        glUniformMatrix4fv(_P.uMV, 1, GL_FALSE, ident);
        glUniformMatrix3fv(_P.uNormalMat, 1, GL_FALSE, identNm);
        glUniform3f(_P.uColor, 1, 1, 1);
        glUniform4f(_P.uUVST, 1, 1, 0, 0);
        glUniform1f(_P.uHasTex, 1.0f);
        glUniform1f(_P.uUnlit, 1.0f);
        glUniform1f(_P.uTexAlpha, 1.0f);
        glUniform1f(_P.uAlpha, _flashTime / FLASH_TIME);
        glBindTexture(GL_TEXTURE_2D, _flashTex.name);

        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE);     // аддитивно: огонь светится
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_CULL_FACE);
        glDepthMask(GL_FALSE);
        [self bindClientVertices:verts];
        glDrawArrays(GL_TRIANGLES, 0, 6);
        glDepthMask(GL_TRUE);
        glEnable(GL_CULL_FACE);
        glEnable(GL_DEPTH_TEST);
        glDisable(GL_BLEND);
    }
}

- (void)drawWithScene:(GameScene *)scene {
    if (_count == 0 || !scene.loaded) return;
    float view[16], proj[16];
    [scene getView:view proj:proj];
    [self drawDecalsWithView:view proj:proj];
    [self drawViewModelWithScene:scene];
}

@end
