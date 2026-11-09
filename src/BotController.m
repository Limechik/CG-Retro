#import "BotController.h"
#import "GameScene.h"
#import "Shaders.h"
#import "Mesh.h"
#import "Texture.h"
#import "Mat4.h"
#import "Rig.h"
#import "Bot.h"
#import "AudioEngine.h"
#import <OpenGLES/ES2/gl.h>
#include <string.h>

#define MAX_BOTS 6
#define RESPAWN_DELAY 4.0f
#define TEAM_BLUE_BOTS 2           // командный бой: игрок + 2 бота против 3 ботов
#define TEAM_RED_BOTS 3
#define SCORE_LIMIT 15
#define OUTFIT_CATEGORIES 3
#define OUTFIT_CHOICES 8
#define OUTFIT_PARTS 128

typedef struct {
    CGMesh mesh;
    unsigned node;
    float color[3];
} CGBotOutfitPart;

typedef struct {
    unsigned first, count;
} CGBotOutfitChoice;

// Цвет оперения по командам (множитель к цвету части): 0 — без команды, 1 — синие, 2 — красные.
static const float kTeamTint[3][3] = { { 1.0f, 1.0f, 1.0f }, { 0.62f, 0.78f, 1.0f }, { 1.0f, 0.58f, 0.52f } };

@implementation BotController {
    CGProgram _P;
    CGRig *_rig;
    int _clipIdle, _clipRun, _clipTopIdle, _clipTopRun, _clipShoot;

    CGMesh *_meshes;      int _meshCount;
    CGTexture *_texs;     int _texCount;
    int *_partMesh, *_partTex;
    BOOL *_partTint;      // части, которые красятся в цвет команды (оперение; клюв и гребень не трогаем)
    int _team[MAX_BOTS];  // 0 — нет, 1 — синие, 2 — красные
    int _blueScore, _redScore, _winner;
    CGGameMode _mode;

    CGBot _bots[MAX_BOTS];
    BOOL _active[MAX_BOTS];
    CGBotOutfitPart _outfitParts[OUTFIT_PARTS];
    CGBotOutfitChoice _outfitChoices[OUTFIT_CATEGORIES][OUTFIT_CHOICES];
    unsigned _outfitPartCount, _outfitChoiceCount[OUTFIT_CATEGORIES];
    unsigned _botOutfit[MAX_BOTS][OUTFIT_CATEGORIES];

    GameScene *_scene;
    float *_spawns;       unsigned _spawnCount;
    unsigned _rng;
    float _fallY;
    BOOL _running;
}

@synthesize aliveCount = _aliveCount, kills = _kills;
@synthesize desiredCount = _desiredCount;
@synthesize mode = _mode;
@synthesize blueScore = _blueScore, redScore = _redScore, winner = _winner;
@synthesize audio = _audio;

- (id)init {
    if ((self = [super init])) {
        _desiredCount = 4;
        _rng = (unsigned)arc4random() | 1u;
    }
    return self;
}

- (void)dealloc {
    for (unsigned i = 0; i < _outfitPartCount; i++) CGMeshFree(&_outfitParts[i].mesh);
    free(_spawns);
    free(_meshes); free(_texs); free(_partMesh); free(_partTex); free(_partTint);
    cgrig_free(_rig);
}

- (BOOL)loadOutfitsFrom:(NSString *)resources {
    NSString *dir = [resources stringByAppendingPathComponent:@"bot-outfits"];
    NSArray *categories = [NSArray arrayWithContentsOfFile:[dir stringByAppendingPathComponent:@"outfits.plist"]];
    if (![categories isKindOfClass:[NSArray class]] || [categories count] != OUTFIT_CATEGORIES) return NO;
    for (unsigned c = 0; c < OUTFIT_CATEGORIES; c++) {
        NSDictionary *category = categories[c];
        if (![category isKindOfClass:[NSDictionary class]]) return NO;
        NSArray *items = category[@"items"];
        if (![items isKindOfClass:[NSArray class]] || [items count] >= OUTFIT_CHOICES) return NO;
        _outfitChoiceCount[c] = 1;
        for (NSDictionary *item in items) {
            if (![item isKindOfClass:[NSDictionary class]]) return NO;
            NSArray *parts = item[@"parts"];
            if (![parts isKindOfClass:[NSArray class]] || [parts count] == 0 || [parts count] > OUTFIT_PARTS - _outfitPartCount) return NO;
            CGBotOutfitChoice *choice = &_outfitChoices[c][_outfitChoiceCount[c]];
            choice->first = _outfitPartCount;
            for (NSDictionary *entry in parts) {
                if (![entry isKindOfClass:[NSDictionary class]]) return NO;
                NSString *nodeName = entry[@"node"], *mesh = entry[@"mesh"];
                NSArray *color = entry[@"color"];
                if (![nodeName isKindOfClass:[NSString class]] || ![mesh isKindOfClass:[NSString class]] ||
                    ![mesh isEqualToString:[mesh lastPathComponent]] || ![color isKindOfClass:[NSArray class]] || [color count] != 3) return NO;
                unsigned node = 0;
                while (node < _rig->nodeCount && strcmp(_rig->nodes[node].name, [nodeName UTF8String]) != 0) node++;
                if (node == _rig->nodeCount) return NO;
                CGBotOutfitPart *part = &_outfitParts[_outfitPartCount];
                part->node = node;
                for (int k = 0; k < 3; k++) {
                    if (![color[k] isKindOfClass:[NSNumber class]]) return NO;
                    part->color[k] = [color[k] floatValue];
                }
                if (!CGMeshLoad([dir stringByAppendingPathComponent:mesh], &part->mesh)) return NO;
                _outfitPartCount++;
                choice->count++;
            }
            _outfitChoiceCount[c]++;
        }
    }
    return YES;
}

#pragma mark - Подготовка

- (BOOL)setup {
    if (!CGProgramBuild(&_P)) return NO;
    NSString *res = [[NSBundle mainBundle] resourcePath];
    NSString *rigPath = [[res stringByAppendingPathComponent:@"characters"] stringByAppendingPathComponent:@"rudy.cgr"];
    _rig = cgrig_load([rigPath fileSystemRepresentation]);
    if (!_rig) { NSLog(@"[Bots] не загружен риг %@", rigPath); return NO; }

    _clipIdle    = cgrig_find_clip(_rig, "Idle");
    _clipRun     = cgrig_find_clip(_rig, "Run");
    _clipTopIdle = cgrig_find_clip(_rig, "TopIdle");
    _clipTopRun  = cgrig_find_clip(_rig, "TopRun");
    _clipShoot   = cgrig_find_clip(_rig, "AK47Shoot");

    // уникальные меши и текстуры частей
    NSString *meshDir = [res stringByAppendingPathComponent:@"meshes"];
    NSString *texDir  = [res stringByAppendingPathComponent:@"textures"];
    NSMutableDictionary *mIdx = [NSMutableDictionary dictionary], *tIdx = [NSMutableDictionary dictionary];
    _meshes   = (CGMesh *)calloc(_rig->partCount + 1, sizeof(CGMesh));
    _texs     = (CGTexture *)calloc(_rig->partCount + 1, sizeof(CGTexture));
    _partMesh = (int *)calloc(_rig->partCount + 1, sizeof(int));
    _partTex  = (int *)calloc(_rig->partCount + 1, sizeof(int));
    _partTint = (BOOL *)calloc(_rig->partCount + 1, sizeof(BOOL));
    for (unsigned i = 0; i < _rig->partCount; i++) {
        const CGRigPart *part = &_rig->parts[i];
        NSString *mn = [NSString stringWithUTF8String:part->mesh];
        NSNumber *mi = mIdx[mn];
        if (!mi) {
            NSString *mp = [[meshDir stringByAppendingPathComponent:mn] stringByAppendingPathExtension:@"cgm"];
            if (!CGMeshLoad(mp, &_meshes[_meshCount])) NSLog(@"[Bots] нет меша %@", mp);
            mi = @(_meshCount++);
            mIdx[mn] = mi;
        }
        _partMesh[i] = [mi intValue];
        _partTint[i] = (strcmp(part->mesh, "rudy_SC_Tail") == 0 || strcmp(part->mesh, "rudy_SC_body.001") == 0 ||
                        strcmp(part->mesh, "rudy_SC_body.002") == 0 || strcmp(part->mesh, "rudy_SC_body.003") == 0);

        _partTex[i] = -1;
        if (part->tex[0]) {
            NSString *tn = [NSString stringWithUTF8String:part->tex];
            NSNumber *ti = tIdx[tn];
            if (!ti) {
                NSString *tp = [[texDir stringByAppendingPathComponent:tn] stringByAppendingPathExtension:@"cgt"];
                if (CGTextureLoad(tp, &_texs[_texCount])) { ti = @(_texCount++); tIdx[tn] = ti; }
                else NSLog(@"[Bots] нет текстуры %@", tp);
            }
            if (ti) _partTex[i] = [ti intValue];
        }
    }
    if (![self loadOutfitsFrom:res]) {
        NSLog(@"[Bots] failed to load outfits");
        for (unsigned i = 0; i < _outfitPartCount; i++) CGMeshFree(&_outfitParts[i].mesh);
        _outfitPartCount = 0;
        memset(_outfitChoiceCount, 0, sizeof(_outfitChoiceCount));
    }
    return YES;
}

#pragma mark - Спавн

- (void)resetBot:(int)i scene:(GameScene *)scene {
    const CGCollision *col = [scene collision];
    float feet[3];
    [scene playerFeet:feet];
    float sp[3];
    BOOL ok = NO;
    float pickMin = 12.0f, pickMax = 90.0f, sampMin = 15.0f, sampMax = 70.0f;
    if (_mode == CGGameModeTeam) {
        if (_team[i] == 1) { pickMin = 4.0f;  pickMax = 30.0f; sampMin = 4.0f;  sampMax = 30.0f; }    // свои — рядом с игроком
        else               { pickMin = 25.0f; pickMax = 90.0f; sampMin = 25.0f; sampMax = 80.0f; }    // враги — подальше
    }
    for (int attempt = 0; attempt < 8 && !ok; attempt++) {
        ok = cgbot_pick_spawn(col, _spawns, _spawnCount, feet, pickMin, pickMax, &_rng, sp) ||
             cgbot_sample_spawn(col, feet, sampMin, sampMax, &_rng, sp);
        if (!ok) break;
        for (int j = 0; j < MAX_BOTS; j++) {                   // не накладываемся на других ботов
            if (j == i || !_active[j]) continue;
            float dx = _bots[j].body.pos[0] - sp[0], dz = _bots[j].body.pos[2] - sp[2];
            if (dx * dx + dz * dz < 9.0f) { ok = NO; break; }
        }
    }
    if (!ok) { _active[i] = NO; return; }
    _rng = _rng * 1664525u + 1013904223u;
    cgbot_init(&_bots[i], sp, _rng | 1u);
    for (unsigned c = 0; c < OUTFIT_CATEGORIES; c++)
        _botOutfit[i][c] = _outfitChoiceCount[c] ? arc4random_uniform(_outfitChoiceCount[c]) : 0;
    if (_outfitChoiceCount[0] > 1 && !_botOutfit[i][0] && !_botOutfit[i][1] && !_botOutfit[i][2])
        _botOutfit[i][0] = 1 + arc4random_uniform(_outfitChoiceCount[0] - 1);
    _active[i] = YES;
}

- (void)startForScene:(GameScene *)scene spawnFile:(NSString *)path {
    [self stop];
    if (!_rig || !scene.loaded || ![scene collision]) return;
    _scene = scene;
    _spawns = cgbot_load_spawns([path fileSystemRepresentation], &_spawnCount);
    if (!_spawns) _spawnCount = 0;
    float bmin[3], bmax[3];
    cgc_bounds([scene collision], bmin, bmax);
    _fallY = bmin[1] - 40.0f;
    _running = YES;
    _kills = 0;
    _blueScore = _redScore = _winner = 0;
    memset(_team, 0, sizeof(_team));
    int n = _desiredCount < 0 ? 0 : (_desiredCount > MAX_BOTS ? MAX_BOTS : _desiredCount);
    if (_mode == CGGameModeTeam) {
        n = TEAM_BLUE_BOTS + TEAM_RED_BOTS;
        for (int i = 0; i < n; i++) _team[i] = (i < TEAM_BLUE_BOTS) ? 1 : 2;
    }
    for (int i = 0; i < n; i++) [self resetBot:i scene:scene];
}

- (void)stop {
    _running = NO;
    memset(_active, 0, sizeof(_active));
    free(_spawns); _spawns = NULL; _spawnCount = 0;
    _scene = nil;
    _aliveCount = 0;
}

- (void)setDesiredCount:(int)n {
    _desiredCount = n < 0 ? 0 : (n > MAX_BOTS ? MAX_BOTS : n);
    if (_running && _scene && _mode == CGGameModeFFA) {        // перезапуск с новым числом ботов (в командном бою состав фиксирован)
        for (int i = 0; i < MAX_BOTS; i++) _active[i] = NO;
        for (int i = 0; i < _desiredCount; i++) [self resetBot:i scene:_scene];
    }
}

#pragma mark - Логика

- (int)scoreLimit { return SCORE_LIMIT; }

// Убийство (в командном бою — очко команде убийцы).
- (void)registerKillByTeam:(int)team {
    if (_mode != CGGameModeTeam || _winner) return;
    if (team == 1) _blueScore++; else if (team == 2) _redScore++;
    if (_blueScore >= SCORE_LIMIT) _winner = 1;
    else if (_redScore >= SCORE_LIMIT) _winner = 2;
}

- (void)playerDied { [self registerKillByTeam:2]; }

- (float)updateWithScene:(GameScene *)scene playerFeet:(const float *)feet playerAlive:(BOOL)alive dt:(float)dt {
    if (!_running) return 0;
    const CGCollision *col = [scene collision];
    if (!col) return 0;
    BOOL team = (_mode == CGGameModeTeam);
    float damage = 0;
    int alivecount = 0;
    for (int i = 0; i < MAX_BOTS; i++) {
        if (!_active[i]) continue;
        CGBot *b = &_bots[i];
        if (_winner) {                                          // матч окончен: все замирают
            if (b->state != BOT_DEAD) alivecount++;
            continue;
        }

        // Цель бота: в «Все против всех» — игрок. В командном бою — ближайший живой враг: игрок (для красных)
        // или бот другой команды. tIdx: -2 — игрок, >= 0 — индекс бота, -1 — целей нет (бот просто бродит).
        const float *tf = feet;
        int talive = alive ? 1 : 0, tIdx = -2;
        if (team && b->state != BOT_DEAD) {
            float best = 1e30f;
            tIdx = -1; talive = 0;
            if (_team[i] == 2 && alive) {
                float dx = feet[0] - b->body.pos[0], dz = feet[2] - b->body.pos[2];
                best = dx * dx + dz * dz; tIdx = -2; talive = 1;
            }
            for (int j = 0; j < MAX_BOTS; j++) {
                if (j == i || !_active[j] || _bots[j].state == BOT_DEAD || _team[j] == _team[i]) continue;
                float dx = _bots[j].body.pos[0] - b->body.pos[0], dz = _bots[j].body.pos[2] - b->body.pos[2];
                float d2 = dx * dx + dz * dz;
                if (d2 < best) { best = d2; tIdx = j; talive = 1; }
            }
            if (tIdx >= 0) tf = _bots[tIdx].body.pos;
        }

        CGBotEvents ev;
        cgbot_update(b, col, tf, talive, dt, &ev);
        if (ev.shotFired) [_audio play:@"bot_shot" at:ev.shotOrigin];
        if (ev.playerHit) {
            if (tIdx == -2) damage += ev.damage;
            else if (tIdx >= 0 && cgbot_damage(&_bots[tIdx], ev.damage)) {      // бот убил бота
                float at[3] = { _bots[tIdx].body.pos[0], _bots[tIdx].body.pos[1] + 1.0f, _bots[tIdx].body.pos[2] };
                [_audio play:@"bot_death" at:at];
                [self registerKillByTeam:_team[i]];
            }
        }
        if (b->state != BOT_DEAD) alivecount++;

        BOOL fell = b->body.pos[1] < _fallY;
        BOOL gone = (b->state == BOT_DEAD && b->stateTime > RESPAWN_DELAY);
        if (fell || gone) [self resetBot:i scene:scene];
    }
    _aliveCount = alivecount;
    return damage;
}

- (BOOL)hitWithOrigin:(const float *)origin dir:(const float *)dir maxDist:(float)maxDist damage:(float)damage
             distance:(float *)distance head:(BOOL *)head killed:(BOOL *)killed {
    if (!_running || _winner) return NO;
    int best = -1; float bestT = maxDist; int bestHead = 0;
    for (int i = 0; i < MAX_BOTS; i++) {
        if (!_active[i]) continue;
        if (_mode == CGGameModeTeam && _team[i] == 1) continue;          // по своим не попадаем
        float t; int h;
        if (cgbot_ray_hit(&_bots[i], origin, dir, bestT, &t, &h) && t < bestT) { best = i; bestT = t; bestHead = h; }
    }
    if (best < 0) return NO;
    int died = cgbot_damage(&_bots[best], bestHead ? damage * 2.0f : damage);
    if (died) {
        _kills++;
        [self registerKillByTeam:1];
        float at[3] = { _bots[best].body.pos[0], _bots[best].body.pos[1] + 1.0f, _bots[best].body.pos[2] };
        [_audio play:@"bot_death" at:at];
    }
    if (distance) *distance = bestT;
    if (head) *head = bestHead ? YES : NO;
    if (killed) *killed = died ? YES : NO;
    return YES;
}

#pragma mark - Отрисовка

- (void)drawBot:(const CGBot *)b index:(int)botIndex team:(int)team view:(const float *)view {
    // поза: idle, поверх бег (кроссфейд), поверх отдача при выстреле
    CGRigPose pose;
    cgrig_rest_pose(_rig, &pose);
    cgrig_apply_clip(_rig, _clipIdle, b->animTime, 1.0f, &pose);
    cgrig_apply_clip(_rig, _clipTopIdle, b->animTime, 1.0f, &pose);
    if (b->runBlend > 0.01f) {
        cgrig_apply_clip(_rig, _clipRun, b->animTime, b->runBlend, &pose);
        cgrig_apply_clip(_rig, _clipTopRun, b->animTime, b->runBlend, &pose);
    }
    if (b->shootAnim > 0 && _clipShoot >= 0) cgrig_apply_clip(_rig, _clipShoot, 0.13f - b->shootAnim, 1.0f, &pose);

    // корень: позиция, поворот лицом по yaw (модель смотрит в +Z, у бота yaw=0 — в -Z), падение при смерти
    float fall = b->deathT * b->deathT * (3.0f - 2.0f * b->deathT);          // сглаженное 0..1
    float t[16], ry[16], rx[16], a[16], root[16];
    mat4_translate(t, b->body.pos[0], b->body.pos[1] + 0.25f * fall, b->body.pos[2]);
    mat4_rotate_y(ry, b->yaw + 3.14159265f);
    mat4_rotate_x(rx, -1.5707963f * fall);                                    // заваливается на спину
    mat4_mul(a, ry, rx);
    mat4_mul(root, t, a);

    float world[CGRIG_MAX_NODES][16];
    cgrig_world(_rig, root, &pose, world);

    float tintG = b->hitFlash > 0 ? 0.35f : 1.0f;                             // красная вспышка при попадании
    for (unsigned i = 0; i < _rig->partCount; i++) {
        const CGRigPart *part = &_rig->parts[i];
        const float *W = world[part->node];
        float mv[16], nm[9];
        mat4_mul(mv, view, W);
        mat3_from_mat4(nm, W);                                                // нормали в мировых координатах
        glUniformMatrix4fv(_P.uMV, 1, GL_FALSE, mv);
        glUniformMatrix3fv(_P.uNormalMat, 1, GL_FALSE, nm);
        const float *tc = (team > 0 && _partTint[i]) ? kTeamTint[team] : kTeamTint[0];       // оперение — в цвет команды
        glUniform3f(_P.uColor, part->color[0] * tc[0], part->color[1] * tc[1] * tintG, part->color[2] * tc[2] * tintG);
        glUniform4f(_P.uUVST, part->uvst[0], part->uvst[1], part->uvst[2], part->uvst[3]);
        int ti = _partTex[i];
        glUniform1f(_P.uHasTex, ti >= 0 ? 1.0f : 0.0f);
        glUniform1f(_P.uCutout, (ti >= 0 && (part->flags & 2)) ? 1.0f : 0.0f);
        glBindTexture(GL_TEXTURE_2D, ti >= 0 ? _texs[ti].name : 0);
        glFrontFace((part->flags & 1) ? GL_CW : GL_CCW);                       // отрицательный масштаб переворачивает обход
        const CGMesh *m = &_meshes[_partMesh[i]];
        if (!m->vbo) continue;
        CGBindVertexLayout(m->vbo, m->ibo);
        glDrawElements(GL_TRIANGLES, m->indexCount, GL_UNSIGNED_SHORT, (const void *)0);
    }
    glFrontFace(GL_CCW);
    glDisable(GL_CULL_FACE);
    glUniform1f(_P.uHasTex, 0.0f);
    glUniform1f(_P.uCutout, 0.0f);
    for (unsigned c = 0; c < OUTFIT_CATEGORIES; c++) {
        if (!_outfitChoiceCount[c]) continue;
        CGBotOutfitChoice choice = _outfitChoices[c][_botOutfit[botIndex][c]];
        for (unsigned i = choice.first; i < choice.first + choice.count; i++) {
            CGBotOutfitPart *part = &_outfitParts[i];
            const float *W = world[part->node];
            float mv[16], nm[9];
            mat4_mul(mv, view, W);
            mat3_from_mat4(nm, W);
            glUniformMatrix4fv(_P.uMV, 1, GL_FALSE, mv);
            glUniformMatrix3fv(_P.uNormalMat, 1, GL_FALSE, nm);
            glUniform3f(_P.uColor, part->color[0], part->color[1] * tintG, part->color[2] * tintG);
            CGBindVertexLayout(part->mesh.vbo, part->mesh.ibo);
            glDrawElements(GL_TRIANGLES, part->mesh.indexCount, GL_UNSIGNED_SHORT, (const void *)0);
        }
    }
    glEnable(GL_CULL_FACE);
}

- (void)drawWithScene:(GameScene *)scene {
    if (!_running || !_rig || !scene.loaded) return;
    BOOL any = NO;
    for (int i = 0; i < MAX_BOTS; i++) if (_active[i]) { any = YES; break; }
    if (!any) return;

    float view[16], proj[16];
    [scene getView:view proj:proj];
    glUseProgram(_P.prog);
    CGProgramSetDefaults(&_P);
    glUniformMatrix4fv(_P.uProj, 1, GL_FALSE, proj);
    glUniform3f(_P.uLightDir, 0.4f, 0.8f, 0.6f);
    glActiveTexture(GL_TEXTURE0);
    glUniform1i(_P.uTex, 0);
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);
    for (int i = 0; i < MAX_BOTS; i++) {
        if (_active[i]) [self drawBot:&_bots[i] index:i team:(_mode == CGGameModeTeam ? _team[i] : 0) view:view];
    }
}

@end
