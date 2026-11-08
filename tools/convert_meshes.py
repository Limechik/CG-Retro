#!/usr/bin/env python3
"""
Конвертер Unity-мешей (YAML .asset) -> компактный бинарный формат .cgm для GLES2.

Формат CGM1 (little-endian):
    char     magic[4] = "CGM1"
    uint32   vertexCount
    uint32   indexCount
    float    bmin[3], bmax[3]
    float    vertices[vertexCount * 8]   // px py pz  nx ny nz  u v
    uint16   indices[indexCount]

Unity левосторонняя, OpenGL правосторонняя: инвертируем X у позиций и нормалей.
Зеркалирование переворачивает обход треугольников, поэтому дополнительно меняем
местами 2-й и 3-й индекс каждого треугольника (получаем CCW для glFrontFace(GL_CCW)).
V-координата текстуры переворачивается (1 - v), т.к. в Unity начало UV снизу,
а UIImage/CGImage отдаёт пиксели сверху вниз.

Использование:
    convert_meshes.py <out_dir> <mesh.asset> [<mesh.asset> ...]
"""
import re, struct, sys, os


def parse_mesh(path):
    txt = open(path, 'r', encoding='utf-8', errors='replace').read()

    name = re.search(r'm_Name:\s*(.*)', txt).group(1).strip()
    idx_fmt = int(re.search(r'm_IndexFormat:\s*(\d+)', txt).group(1))
    idx_hex = re.search(r'm_IndexBuffer:\s*([0-9a-fA-F]*)', txt).group(1)
    vcount = int(re.search(
        r'm_VertexData:\s*\n\s*serializedVersion:\s*\d+\s*\n\s*m_VertexCount:\s*(\d+)', txt).group(1))
    vdata_hex = re.search(r'_typelessdata:\s*([0-9a-fA-F]*)', txt).group(1)

    # каналы: 0 pos, 1 normal, 2 tangent, 3 color, 4 uv0, ...
    chan_block = re.search(r'm_Channels:\s*\n((?:\s+-\s+stream:.*\n(?:\s+\w+:.*\n){3})+)', txt)
    channels = []
    for m in re.finditer(
            r'stream:\s*(\d+)\s*\n\s*offset:\s*(\d+)\s*\n\s*format:\s*(\d+)\s*\n\s*dimension:\s*(\d+)',
            chan_block.group(1)):
        channels.append(tuple(int(x) for x in m.groups()))

    subs = []
    for m in re.finditer(
            r'firstByte:\s*(\d+)\s*\n\s*indexCount:\s*(\d+)\s*\n\s*topology:\s*(\d+)\s*\n\s*baseVertex:\s*(\d+)',
            txt):
        subs.append(tuple(int(x) for x in m.groups()))
    return name, idx_fmt, bytes.fromhex(idx_hex), vcount, bytes.fromhex(vdata_hex), channels, subs


FMT_SIZE = {0: 4, 1: 2, 2: 1, 3: 1, 4: 2, 5: 2, 6: 1, 7: 1, 8: 2, 9: 2, 10: 4, 11: 4}


def stream_layout(ch, vcount):
    """{поток: (смещение блока, шаг вершины)}. Блоки потоков идут друг за другом, выравнивание 16 байт."""
    strides = {}
    for stream, off, fmt, dim in ch:
        if dim:
            strides[stream] = max(strides.get(stream, 0), off + dim * FMT_SIZE[fmt])
    layout, pos = {}, 0
    for s in sorted(strides):
        pos = (pos + 15) // 16 * 16
        layout[s] = (pos, strides[s])
        pos += strides[s] * vcount
    return layout


def safe_name(n):
    return re.sub(r'[^A-Za-z0-9_.-]+', '_', n)


def convert(path, out_dir):
    name, idx_fmt, ib, vcount, vb, ch, subs = parse_mesh(path)

    for i in (0, 1, 4):
        if ch[i][3] and ch[i][2] not in (0, 1):
            raise ValueError("канал %d: формат %d не поддерживается (нужен float32/float16)" % (i, ch[i][2]))
    if ch[0][2] != 0 or (ch[1][3] and ch[1][2] != 0):
        raise ValueError("позиции/нормали не float32")
    layout = stream_layout(ch, vcount)
    if max((st + sz * vcount) for st, sz in layout.values()) > len(vb):
        raise ValueError("размер vertex-буфера меньше, чем следует из каналов")

    def base_of(c):                  # смещение первой вершины канала и шаг
        start, stride = layout[ch[c][0]]
        return start + ch[c][1], stride

    p_off, p_stride = base_of(0)
    n_off, n_stride = base_of(1) if ch[1][3] else (None, 0)
    uv_off, uv_stride = base_of(4) if ch[4][3] else (None, 0)

    verts = []
    bmin = [1e30] * 3
    bmax = [-1e30] * 3
    for v in range(vcount):
        px, py, pz = struct.unpack_from('<3f', vb, p_off + v * p_stride)
        px = -px  # Unity -> GL
        if n_off is not None:
            nx, ny, nz = struct.unpack_from('<3f', vb, n_off + v * n_stride)
            nx = -nx
        else:
            nx, ny, nz = 0.0, 1.0, 0.0
        if uv_off is not None:
            if ch[4][2] == 0:
                u, tv = struct.unpack_from('<2f', vb, uv_off + v * uv_stride)
            else:
                u, tv = struct.unpack_from('<2e', vb, uv_off + v * uv_stride)
            tv = 1.0 - tv
        else:
            u = tv = 0.0
        verts.append((px, py, pz, nx, ny, nz, u, tv))
        for k, val in enumerate((px, py, pz)):
            bmin[k] = min(bmin[k], val)
            bmax[k] = max(bmax[k], val)

    isz = 2 if idx_fmt == 0 else 4
    indices = []
    for first_byte, icount, topo, base_vertex in subs:
        if topo != 0:  # только треугольники
            continue
        for k in range(icount):
            (ix,) = struct.unpack_from('<H' if isz == 2 else '<I', ib, first_byte + k * isz)
            indices.append(ix + base_vertex)
    if not indices:
        raise ValueError("нет треугольников")
    for t in range(0, len(indices) - 2, 3):
        indices[t + 1], indices[t + 2] = indices[t + 2], indices[t + 1]
    if vcount > 65535 or max(indices) > 65535:
        raise ValueError("больше 65535 вершин (на iOS 6 берём 16-битные индексы)")

    out = os.path.join(out_dir, safe_name(name) + '.cgm')
    with open(out, 'wb') as f:
        f.write(b'CGM1')
        f.write(struct.pack('<II', vcount, len(indices)))
        f.write(struct.pack('<6f', *bmin, *bmax))
        for v in verts:
            f.write(struct.pack('<8f', *v))
        f.write(struct.pack('<%dH' % len(indices), *indices))
    return out, vcount, len(indices), verts, indices


def check_winding(verts, indices):
    """Сколько треугольников имеют геометрическую нормаль, совпадающую с вершинной (после отражения X)."""
    ok = tot = 0
    for t in range(0, len(indices) - 2, 3):
        a, b, c = (verts[indices[t + k]] for k in range(3))
        e1 = [b[i] - a[i] for i in range(3)]
        e2 = [c[i] - a[i] for i in range(3)]
        n = [e1[1] * e2[2] - e1[2] * e2[1],
             e1[2] * e2[0] - e1[0] * e2[2],
             e1[0] * e2[1] - e1[1] * e2[0]]
        vn = [sum(v[3 + i] for v in (a, b, c)) for i in range(3)]
        d = sum(n[i] * vn[i] for i in range(3))
        if abs(d) > 1e-12:
            tot += 1
            ok += d > 0
    return ok, tot


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    done, skipped = [], []
    for p in sys.argv[2:]:
        try:
            out, vc, ic, verts, idx = convert(p, out_dir)
            ok, tot = check_winding(verts, idx)
            done.append((os.path.basename(out), vc, ic, ok, tot))
        except Exception as e:
            skipped.append((os.path.basename(p), str(e)))
    for n, vc, ic, ok, tot in done:
        pct = 100.0 * ok / tot if tot else 0
        print("OK   %-40s v=%-6d i=%-6d winding=%.0f%%" % (n, vc, ic, pct))
    for n, why in skipped:
        print("SKIP %-40s %s" % (n, why))
