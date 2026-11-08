#import "Texture.h"

#define CGT_HEADER_SIZE 20   // magic(4) + width, height, format, mipCount (4*4)

BOOL CGTextureLoad(NSString *path, CGTexture *out) {
    memset(out, 0, sizeof(*out));
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data || [data length] < CGT_HEADER_SIZE) return NO;

    const uint8_t *p = (const uint8_t *)[data bytes];
    if (memcmp(p, "CGT1", 4) != 0) return NO;

    uint32_t hdr[4];
    memcpy(hdr, p + 4, sizeof(hdr));
    uint32_t w = hdr[0], h = hdr[1], fmt = hdr[2], mips = hdr[3];
    if (w == 0 || h == 0 || mips == 0 || fmt > 1) return NO;

    // Проверяем, что файл содержит все уровни, до того как трогать GL.
    size_t need = CGT_HEADER_SIZE;
    for (uint32_t l = 0; l < mips; l++) {
        uint32_t lw = w >> l; if (lw < 1) lw = 1;
        uint32_t lh = h >> l; if (lh < 1) lh = 1;
        need += (size_t)lw * lh * 2;
    }
    if ([data length] < need) return NO;

    GLenum glFormat = (fmt == 0) ? GL_RGB  : GL_RGBA;
    GLenum glType   = (fmt == 0) ? GL_UNSIGNED_SHORT_5_6_5 : GL_UNSIGNED_SHORT_4_4_4_4;

    glGenTextures(1, &out->name);
    glBindTexture(GL_TEXTURE_2D, out->name);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);   // строки мипов 1xN иначе читаются со сдвигом

    size_t off = CGT_HEADER_SIZE;
    for (uint32_t l = 0; l < mips; l++) {
        uint32_t lw = w >> l; if (lw < 1) lw = 1;
        uint32_t lh = h >> l; if (lh < 1) lh = 1;
        glTexImage2D(GL_TEXTURE_2D, (GLint)l, glFormat, lw, lh, 0, glFormat, glType, p + off);
        off += (size_t)lw * lh * 2;
    }

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, mips > 1 ? GL_LINEAR_MIPMAP_LINEAR : GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);

    out->width = (GLsizei)w;
    out->height = (GLsizei)h;
    out->hasAlpha = (fmt == 1);
    return YES;
}

void CGTextureFree(CGTexture *t) {
    if (t->name) glDeleteTextures(1, &t->name);
    memset(t, 0, sizeof(*t));
}
