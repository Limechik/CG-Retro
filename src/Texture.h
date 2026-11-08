#import <Foundation/Foundation.h>
#import <OpenGLES/ES2/gl.h>

// Текстура в GPU, загруженная из .cgt (см. tools/build_assets.py).
typedef struct {
    GLuint  name;
    GLsizei width, height;
    BOOL    hasAlpha;     // RGBA4444
} CGTexture;

// Нужен текущий EAGLContext. Грузит все мип-уровни, wrap = REPEAT (размеры — степени двойки).
BOOL CGTextureLoad(NSString *path, CGTexture *out);
void CGTextureFree(CGTexture *t);
