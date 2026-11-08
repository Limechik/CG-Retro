#import "Renderer.h"
#import "Mesh.h"
#import "Texture.h"
#import "Shaders.h"
#import "Mat4.h"
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

@implementation Renderer {
    CGProgram _P;

    NSDictionary *_materials;  // имя меша -> {tex, color, uvst, cutout}
    NSString *_texDir;
    CGTexture _tex;
    BOOL _texLoaded;
    NSString *_texName;
    float _color[3];
    float _uvst[4];
    BOOL _cutout;

    NSArray *_names;          // имена файлов .cgm
    NSString *_meshDir;
    NSUInteger _index;
    CGMesh _mesh;
    BOOL _meshLoaded;

    int _w, _h;
}

- (BOOL)setup {
    if (!CGProgramBuild(&_P)) return NO;

    NSString *res = [[NSBundle mainBundle] resourcePath];
    _meshDir = [res stringByAppendingPathComponent:@"meshes"];
    _texDir  = [res stringByAppendingPathComponent:@"textures"];
    _materials = [NSDictionary dictionaryWithContentsOfFile:[res stringByAppendingPathComponent:@"materials.plist"]];
    if (!_materials) NSLog(@"[Renderer] materials.plist не найден — всё будет без текстур");
    NSString *manifest = [res stringByAppendingPathComponent:@"meshes.txt"];
    NSString *txt = [NSString stringWithContentsOfFile:manifest encoding:NSUTF8StringEncoding error:nil];
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *line in [txt componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        if ([line length] > 0) [names addObject:line];
    }
    _names = names;
    if ([_names count] == 0) NSLog(@"[Renderer] meshes.txt пуст или не найден: %@", manifest);

    _yaw = 0.6f; _pitch = 0.25f; _zoom = 1.0f; _autoSpin = YES;

    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);
    glFrontFace(GL_CCW);

    [self loadCurrentMesh];
    return YES;
}

#pragma mark - Meshes

- (void)loadCurrentMesh {
    if (_meshLoaded) { CGMeshFree(&_mesh); _meshLoaded = NO; }
    if ([_names count] == 0) return;
    NSString *path = [_meshDir stringByAppendingPathComponent:_names[_index]];
    _meshLoaded = CGMeshLoad(path, &_mesh);
    if (!_meshLoaded) NSLog(@"[Renderer] не удалось загрузить %@", path);
    [self loadMaterialForCurrentMesh];
}

- (void)loadMaterialForCurrentMesh {
    if (_texLoaded) { CGTextureFree(&_tex); _texLoaded = NO; }
    _texName = nil;
    _color[0] = 1.0f; _color[1] = 0.78f; _color[2] = 0.3f;     // без материала — жёлтый
    _uvst[0] = 1; _uvst[1] = 1; _uvst[2] = 0; _uvst[3] = 0;
    _cutout = NO;
    if ([_names count] == 0) return;

    NSDictionary *m = _materials[[_names[_index] stringByDeletingPathExtension]];
    if (![m isKindOfClass:[NSDictionary class]]) return;

    NSArray *c = m[@"color"];
    if ([c count] >= 3) for (int i = 0; i < 3; i++) _color[i] = [c[i] floatValue];
    NSArray *u = m[@"uvst"];
    if ([u count] >= 4) for (int i = 0; i < 4; i++) _uvst[i] = [u[i] floatValue];
    _cutout = [m[@"cutout"] boolValue];

    NSString *tn = m[@"tex"];
    if ([tn length] > 0) {
        NSString *tp = [[_texDir stringByAppendingPathComponent:tn] stringByAppendingPathExtension:@"cgt"];
        if (CGTextureLoad(tp, &_tex)) { _texLoaded = YES; _texName = tn; }
        else NSLog(@"[Renderer] не удалось загрузить текстуру %@", tp);
    }
}

- (NSString *)textureName { return _texName; }

- (NSUInteger)meshCount { return [_names count]; }
- (NSUInteger)meshIndex { return _index; }
- (NSString *)meshName {
    if ([_names count] == 0) return @"(нет мешей)";
    return [_names[_index] stringByDeletingPathExtension];
}
- (NSUInteger)triangleCount { return _meshLoaded ? (NSUInteger)(_mesh.indexCount / 3) : 0; }

- (void)nextMesh {
    if ([_names count] == 0) return;
    _index = (_index + 1) % [_names count];
    [self loadCurrentMesh];
}

- (void)prevMesh {
    if ([_names count] == 0) return;
    _index = (_index + [_names count] - 1) % [_names count];
    [self loadCurrentMesh];
}

#pragma mark - Frame

- (void)resizeWidth:(int)w height:(int)h { _w = w; _h = h; }

- (void)updateWithDelta:(float)dt {
    if (_autoSpin) _yaw += dt * 0.5f;
    if (_pitch > 1.4f) _pitch = 1.4f;
    if (_pitch < -1.4f) _pitch = -1.4f;
    if (_zoom < 0.3f) _zoom = 0.3f;
    if (_zoom > 4.0f) _zoom = 4.0f;
}

- (void)draw {
    glClearColor(0.45f, 0.62f, 0.85f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    if (!_meshLoaded || _w == 0 || _h == 0) return;

    // Модель нормируется в сферу радиуса 1 вокруг начала координат.
    float s = 1.0f / _mesh.radius;
    float tCenter[16], rx[16], ry[16], tmp1[16], tmp2[16], tCam[16], sc[16];
    float model[16], mv[16], proj[16], nm[9];

    mat4_translate(tCenter, -_mesh.center[0], -_mesh.center[1], -_mesh.center[2]);
    mat4_scale(sc, s);
    mat4_rotate_y(ry, _yaw);
    mat4_rotate_x(rx, _pitch);

    mat4_mul(tmp1, sc, tCenter);      // масштаб * центрирование
    mat4_mul(tmp2, ry, tmp1);         // вращение по Y
    mat4_mul(model, rx, tmp2);        // вращение по X

    mat4_translate(tCam, 0, 0, -3.0f * _zoom);
    mat4_mul(mv, tCam, model);
    mat4_perspective(proj, 45.0f * (float)M_PI / 180.0f, (float)_w / (float)_h, 0.1f, 50.0f);

    // нормали вращаются только вращением (масштаб равномерный, normalize в шейдере)
    float rot[16];
    mat4_mul(rot, rx, ry);
    mat3_from_mat4(nm, rot);

    glUseProgram(_P.prog);
    CGProgramSetDefaults(&_P);
    glUniformMatrix4fv(_P.uMV, 1, GL_FALSE, mv);
    glUniformMatrix4fv(_P.uProj, 1, GL_FALSE, proj);
    glUniformMatrix3fv(_P.uNormalMat, 1, GL_FALSE, nm);
    glUniform3f(_P.uLightDir, 0.4f, 0.8f, 0.6f);
    glUniform3f(_P.uColor, _color[0], _color[1], _color[2]);
    glUniform4f(_P.uUVST, _uvst[0], _uvst[1], _uvst[2], _uvst[3]);
    glUniform1f(_P.uHasTex, _texLoaded ? 1.0f : 0.0f);
    glUniform1f(_P.uCutout, (_texLoaded && _cutout) ? 1.0f : 0.0f);
    glUniform1f(_P.uUnlit, 0.0f);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, _texLoaded ? _tex.name : 0);
    glUniform1i(_P.uTex, 0);

    CGBindVertexLayout(_mesh.vbo, _mesh.ibo);
    glDrawElements(GL_TRIANGLES, _mesh.indexCount, GL_UNSIGNED_SHORT, (const void *)0);
}

@end
