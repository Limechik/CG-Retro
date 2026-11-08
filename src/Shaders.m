#import "Shaders.h"

static NSString *const kVS =
    @"attribute vec3 aPos;\n"
    @"attribute vec3 aNormal;\n"
    @"attribute vec2 aUV;\n"
    @"uniform mat4 uMV;\n"
    @"uniform mat4 uProj;\n"
    @"uniform mat3 uNormalMat;\n"
    @"uniform vec4 uUVST;\n"            // scale.xy, offset.zw
    @"varying vec3 vN;\n"
    @"varying vec2 vUV;\n"
    @"void main() {\n"
    @"  vN = uNormalMat * aNormal;\n"
    @"  vUV = aUV * uUVST.xy + uUVST.zw;\n"
    @"  gl_Position = uProj * uMV * vec4(aPos, 1.0);\n"
    @"}\n";

static NSString *const kFS =
    @"precision mediump float;\n"
    @"varying vec3 vN;\n"
    @"varying vec2 vUV;\n"
    @"uniform sampler2D uTex;\n"
    @"uniform vec3 uLightDir;\n"
    @"uniform vec3 uColor;\n"
    @"uniform float uHasTex;\n"
    @"uniform float uCutout;\n"
    @"uniform float uUnlit;\n"
    @"uniform float uAlpha;\n"
    @"uniform float uTexAlpha;\n"
    @"void main() {\n"
    @"  vec4 t = texture2D(uTex, vUV);\n"
    @"  if (uCutout > 0.5 && t.a < 0.5) discard;\n"
    @"  vec3 base = uColor * mix(vec3(1.0), t.rgb, uHasTex);\n"
    @"  vec3 n = normalize(vN);\n"
    @"  float d = max(dot(n, normalize(uLightDir)), 0.0);\n"
    @"  float light = mix(0.35 + 0.65 * d, 1.0, uUnlit);\n"
    @"  gl_FragColor = vec4(base * light, uAlpha * mix(1.0, t.a, uTexAlpha));\n"
    @"}\n";

static GLuint Compile(GLenum type, NSString *src) {
    GLuint s = glCreateShader(type);
    const char *c = [src UTF8String];
    glShaderSource(s, 1, &c, NULL);
    glCompileShader(s);
    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[1024];
        glGetShaderInfoLog(s, sizeof(log), NULL, log);
        NSLog(@"[Shaders] ошибка компиляции: %s", log);
        glDeleteShader(s);
        return 0;
    }
    return s;
}

BOOL CGProgramBuild(CGProgram *p) {
    memset(p, 0, sizeof(*p));
    GLuint vs = Compile(GL_VERTEX_SHADER, kVS);
    GLuint fs = Compile(GL_FRAGMENT_SHADER, kFS);
    if (!vs || !fs) return NO;

    GLuint prog = glCreateProgram();
    glAttachShader(prog, vs);
    glAttachShader(prog, fs);
    glBindAttribLocation(prog, ATTR_POS, "aPos");
    glBindAttribLocation(prog, ATTR_NORMAL, "aNormal");
    glBindAttribLocation(prog, ATTR_UV, "aUV");
    glLinkProgram(prog);
    GLint ok = 0;
    glGetProgramiv(prog, GL_LINK_STATUS, &ok);
    glDeleteShader(vs);
    glDeleteShader(fs);
    if (!ok) {
        char log[1024];
        glGetProgramInfoLog(prog, sizeof(log), NULL, log);
        NSLog(@"[Shaders] ошибка линковки: %s", log);
        glDeleteProgram(prog);
        return NO;
    }
    p->prog       = prog;
    p->uMV        = glGetUniformLocation(prog, "uMV");
    p->uProj      = glGetUniformLocation(prog, "uProj");
    p->uNormalMat = glGetUniformLocation(prog, "uNormalMat");
    p->uLightDir  = glGetUniformLocation(prog, "uLightDir");
    p->uColor     = glGetUniformLocation(prog, "uColor");
    p->uTex       = glGetUniformLocation(prog, "uTex");
    p->uUVST      = glGetUniformLocation(prog, "uUVST");
    p->uHasTex    = glGetUniformLocation(prog, "uHasTex");
    p->uCutout    = glGetUniformLocation(prog, "uCutout");
    p->uUnlit     = glGetUniformLocation(prog, "uUnlit");
    p->uAlpha     = glGetUniformLocation(prog, "uAlpha");
    p->uTexAlpha  = glGetUniformLocation(prog, "uTexAlpha");
    return YES;
}

void CGProgramSetDefaults(const CGProgram *p) {
    glUniform1f(p->uUnlit, 0.0f);
    glUniform1f(p->uAlpha, 1.0f);
    glUniform1f(p->uTexAlpha, 0.0f);
}

void CGBindVertexLayout(GLuint vbo, GLuint ibo) {
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
    glEnableVertexAttribArray(ATTR_POS);
    glEnableVertexAttribArray(ATTR_NORMAL);
    glEnableVertexAttribArray(ATTR_UV);
    glVertexAttribPointer(ATTR_POS,    3, GL_FLOAT, GL_FALSE, 32, (const void *)0);
    glVertexAttribPointer(ATTR_NORMAL, 3, GL_FLOAT, GL_FALSE, 32, (const void *)12);
    glVertexAttribPointer(ATTR_UV,     2, GL_FLOAT, GL_FALSE, 32, (const void *)24);
}
