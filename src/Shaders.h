#import <Foundation/Foundation.h>
#import <OpenGLES/ES2/gl.h>

// Атрибуты вершины: pos(3f) normal(3f) uv(2f), шаг 32 байта.
enum { ATTR_POS = 0, ATTR_NORMAL = 1, ATTR_UV = 2 };

typedef struct {
    GLuint prog;
    GLint  uMV, uProj, uNormalMat, uLightDir, uColor;
    GLint  uTex, uUVST, uHasTex, uCutout, uUnlit, uAlpha, uTexAlpha;
} CGProgram;

// Единая шейдерная программа: текстура * цвет, направленный свет + ambient,
// альфа-тест (uCutout), режим без освещения (uUnlit, для неба). Нужен текущий EAGLContext.
BOOL CGProgramBuild(CGProgram *p);

// Значения по умолчанию для обычной непрозрачной отрисовки (uUnlit 0, uAlpha 1, uTexAlpha 0).
// Вызывать сразу после glUseProgram.
void CGProgramSetDefaults(const CGProgram *p);

// Привязывает атрибуты к VBO с вершинами формата pos/normal/uv (шаг 32).
void CGBindVertexLayout(GLuint vbo, GLuint ibo);
