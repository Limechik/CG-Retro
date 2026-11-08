#import <Foundation/Foundation.h>
#import <OpenGLES/ES2/gl.h>

// Меш в GPU. Формат вершины: pos(3f) normal(3f) uv(2f) = 32 байта.
typedef struct {
    GLuint  vbo, ibo;
    GLsizei vertexCount, indexCount;
    float   center[3];   // центр bounding box
    float   radius;      // половина диагонали bounding box
} CGMesh;

// Грузит .cgm (см. tools/convert_meshes.py). Нужен текущий EAGLContext.
BOOL CGMeshLoad(NSString *path, CGMesh *out);
void CGMeshFree(CGMesh *m);
