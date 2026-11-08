#import "Mesh.h"
#import <math.h>

#define CGM_HEADER_SIZE 36   // magic(4) + vcount(4) + icount(4) + bmin(12) + bmax(12)

BOOL CGMeshLoad(NSString *path, CGMesh *out) {
    memset(out, 0, sizeof(*out));
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data || [data length] < CGM_HEADER_SIZE) return NO;

    const uint8_t *p = (const uint8_t *)[data bytes];
    if (memcmp(p, "CGM1", 4) != 0) return NO;

    uint32_t vcount, icount;
    float bounds[6];
    memcpy(&vcount, p + 4, 4);
    memcpy(&icount, p + 8, 4);
    memcpy(bounds, p + 12, sizeof(bounds));

    size_t vbytes = (size_t)vcount * 32;
    size_t ibytes = (size_t)icount * 2;
    if ([data length] < CGM_HEADER_SIZE + vbytes + ibytes) return NO;

    glGenBuffers(1, &out->vbo);
    glBindBuffer(GL_ARRAY_BUFFER, out->vbo);
    glBufferData(GL_ARRAY_BUFFER, vbytes, p + CGM_HEADER_SIZE, GL_STATIC_DRAW);

    glGenBuffers(1, &out->ibo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, out->ibo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, ibytes, p + CGM_HEADER_SIZE + vbytes, GL_STATIC_DRAW);

    out->vertexCount = (GLsizei)vcount;
    out->indexCount  = (GLsizei)icount;
    for (int i = 0; i < 3; i++) out->center[i] = 0.5f * (bounds[i] + bounds[3 + i]);
    float dx = bounds[3] - bounds[0], dy = bounds[4] - bounds[1], dz = bounds[5] - bounds[2];
    out->radius = 0.5f * sqrtf(dx * dx + dy * dy + dz * dz);
    if (out->radius < 1e-4f) out->radius = 1.0f;
    return YES;
}

void CGMeshFree(CGMesh *m) {
    if (m->vbo) glDeleteBuffers(1, &m->vbo);
    if (m->ibo) glDeleteBuffers(1, &m->ibo);
    memset(m, 0, sizeof(*m));
}
