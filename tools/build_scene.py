#!/usr/bin/env python3
"""
Запекает Unity-сцену (.unity) в статические батчи для GLES2 (.cgs).

- разворачивает иерархию Transform, учитывает активность объектов и m_Enabled рендереров
- статически забатченные рендереры (m_StaticBatchInfo) берут свои сабмеши из Combined-мешей
  в мировых координатах (трансформ объекта игнорируется, как в Unity)
- остальные рендереры: вершины умножаются на мировую матрицу, при отрицательном масштабе
  порядок индексов переворачивается
- треугольники группируются по (материал, ячейка сетки XZ), чтобы работало отсечение по
  пирамиде видимости; каждый батч <= 65535 вершин (16-битные индексы)
- Unity (левосторонняя) -> OpenGL: зеркалирование X (меши в .cgm уже отзеркалены так же)

Формат CGS1 (little-endian):
    char   magic[4] = "CGS1"
    uint32 materialCount, batchCount
    float  boundsMin[3], boundsMax[3], spawn[3]
    Material[materialCount]  (80 байт):
        char tex[48]; float color[3]; float uvst[4]; uint32 flags (бит0 = cutout, бит1 = небо)
    Batch[batchCount]        (48 байт):
        uint32 material, vertexCount, indexCount, vertexOffset, indexOffset
        float bmin[3], bmax[3]   -> итого 5*4 + 24 = 44, + uint32 pad = 48
    blob: вершины (8 float: pos, normal, uv) и uint16 индексы; смещения от начала blob
Батчи отсортированы по материалу.

Рядом пишется <Сцена>.cgp: точки появления (все листовые объекты контейнеров «respawn points» и т.п.):
    char   magic[4] = "CGP1";  uint32 count;  float feet[count * 3]     // GL-координаты, ноги

Рядом пишется <Сцена>.cgc: коллизионные треугольники в мировых координатах GL
(MeshCollider и BoxCollider, без триггеров и выключенных объектов):
    char   magic[4] = "CGC1"
    uint32 triangleCount
    float  boundsMin[3], boundsMax[3]
    float  triangles[triangleCount * 9]     // три вершины по x y z

Использование:
    build_scene.py <Assets> <Resources> <Scene.unity> [...]  [--max-tex 256] [--cell 16]
"""
import re, os, sys, struct, collections, importlib.util
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + '.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


cm = _load('convert_meshes')
ba = _load('build_assets')
safe_name = ba.safe_name
read = ba.read

SX = np.diag([-1.0, 1.0, 1.0, 1.0])
MAX_VERTS = 65535
TRI_CHUNK = 20000          # <= 60000 уникальных вершин на кусок


# ------------------------------------------------------------------ мэши

class MeshData:
    pass


def load_mesh(path):
    name, idx_fmt, ib, vcount, vb, ch, subs = cm.parse_mesh(path)
    layout = cm.stream_layout(ch, vcount)
    if ch[0][2] != 0 or (ch[1][3] and ch[1][2] != 0):
        raise ValueError('позиции/нормали не float32')
    if max((st + sz * vcount) for st, sz in layout.values()) > len(vb):
        raise ValueError('vertex-буфер меньше, чем следует из каналов')
    buf = np.frombuffer(vb, dtype=np.uint8)

    def view(c, dim, dt):
        start, stride = layout[ch[c][0]]
        isz = np.dtype(dt).itemsize
        return np.ndarray((vcount, dim), dtype=dt, buffer=buf, offset=start + ch[c][1], strides=(stride, isz))

    m = MeshData()
    m.pos = view(0, 3, '<f4').astype(np.float32)
    m.nrm = view(1, 3, '<f4').astype(np.float32) if ch[1][3] else np.tile(
        np.array([0, 1, 0], np.float32), (vcount, 1))
    if ch[4][3]:
        m.uv = view(4, 2, '<f4' if ch[4][2] == 0 else '<f2').astype(np.float32)
    else:
        m.uv = np.zeros((vcount, 2), np.float32)
    idt = '<u2' if idx_fmt == 0 else '<u4'
    iall = np.frombuffer(ib, dtype=idt)
    isz = 2 if idx_fmt == 0 else 4
    m.subs = []       # список массивов треугольников (n,3) по сабмешам; None для не-треугольников
    for first_byte, icount, topo, base_vertex in subs:
        if topo != 0:
            m.subs.append(None)
            continue
        a = iall[first_byte // isz: first_byte // isz + icount].astype(np.int64) + base_vertex
        m.subs.append(a.reshape(-1, 3))
    m.name = name
    return m


# ------------------------------------------------------------------ сцена

def quat_to_mat(x, y, z, w):
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def vec(body, key):
    m = re.search(key + r':\s*\{x:\s*([-\d.eE+]+),\s*y:\s*([-\d.eE+]+),\s*z:\s*([-\d.eE+]+)(?:,\s*w:\s*([-\d.eE+]+))?',
                  body)
    return [float(g) for g in m.groups() if g is not None]


def parse_scene(path):
    txt = read(path)
    parts = re.split(r'(?m)^--- !u!(\d+) &(-?\d+)[^\n]*\n', txt)
    gos, trs, mfs, mrs = {}, {}, {}, {}
    cols = []
    prefab_instances = 0
    for i in range(1, len(parts), 3):
        cls, fid, body = int(parts[i]), parts[i + 1], parts[i + 2]
        if cls == 1:
            nm = re.search(r'm_Name:\s*(.*)', body)
            act = re.search(r'm_IsActive:\s*(\d)', body)
            gos[fid] = {'name': nm.group(1).strip() if nm else '',
                        'active': (act.group(1) == '1') if act else True}
        elif cls in (4, 224):
            go = re.search(r'm_GameObject:\s*\{fileID:\s*(-?\d+)', body)
            fa = re.search(r'm_Father:\s*\{fileID:\s*(-?\d+)', body)
            if not go:
                continue
            try:
                p = vec(body, 'm_LocalPosition')
                r = vec(body, 'm_LocalRotation')
                s = vec(body, 'm_LocalScale')
            except AttributeError:       # RectTransform без этих полей
                continue
            trs[fid] = {'go': go.group(1), 'father': fa.group(1) if fa else '0', 'p': p, 'r': r, 's': s}
        elif cls == 33:
            go = re.search(r'm_GameObject:\s*\{fileID:\s*(-?\d+)', body)
            me = re.search(r'm_Mesh:\s*\{[^}]*?' + ba.GUID, body)
            if go and me:
                mfs[go.group(1)] = me.group(1)
        elif cls == 23:
            go = re.search(r'm_GameObject:\s*\{fileID:\s*(-?\d+)', body)
            if not go:
                continue
            en = re.search(r'm_Enabled:\s*(\d)', body)
            mb = re.search(r'm_Materials:\s*\n((?:\s*-\s*\{[^}]*\}\s*\n)+)', body)
            sb = re.search(r'm_StaticBatchInfo:\s*\n\s*firstSubMesh:\s*(\d+)\s*\n\s*subMeshCount:\s*(\d+)', body)
            mrs[go.group(1)] = {
                'enabled': (en.group(1) == '1') if en else True,
                'mats': re.findall(ba.GUID, mb.group(1)) if mb else [],
                'first': int(sb.group(1)) if sb else 0,
                'count': int(sb.group(2)) if sb else 0}
        elif cls in (64, 65):
            go = re.search(r'm_GameObject:\s*\{fileID:\s*(-?\d+)', body)
            if not go:
                continue
            en = re.search(r'm_Enabled:\s*(\d)', body)
            tg = re.search(r'm_IsTrigger:\s*(\d)', body)
            if (en and en.group(1) == '0') or (tg and tg.group(1) == '1'):
                continue
            if cls == 64:
                me = re.search(r'm_Mesh:\s*\{[^}]*?' + ba.GUID, body)
                if me:
                    cols.append({'go': go.group(1), 'kind': 'mesh', 'mesh': me.group(1)})
            else:
                try:
                    size = vec(body, 'm_Size')
                    center = vec(body, 'm_Center')
                except AttributeError:
                    continue
                cols.append({'go': go.group(1), 'kind': 'box', 'size': size, 'center': center})
        elif cls == 1001:
            prefab_instances += 1
    go2tr = {t['go']: tid for tid, t in trs.items()}
    return gos, trs, go2tr, mfs, mrs, cols, prefab_instances


def world_matrix(tid, trs, cache):
    if tid in cache:
        return cache[tid]
    t = trs[tid]
    R = quat_to_mat(*t['r'])
    S = np.diag(t['s'])
    L = np.eye(4)
    L[:3, :3] = R @ S
    L[:3, 3] = t['p']
    f = t['father']
    M = world_matrix(f, trs, cache) @ L if f in trs else L
    cache[tid] = M
    return M


def active_in_hierarchy(tid, trs, gos):
    seen = 0
    while tid in trs and seen < 256:
        g = gos.get(trs[tid]['go'])
        if g is not None and not g['active']:
            return False
        tid = trs[tid]['father']
        seen += 1
    return True


# ------------------------------------------------------------------ запекание

def group_by_cell(centroids_xz, cell):
    ix = np.floor(centroids_xz[:, 0] / cell).astype(np.int64)
    iz = np.floor(centroids_xz[:, 1] / cell).astype(np.int64)
    return ix * 100003 + iz


def add_piece(buckets, matidx, verts, tris, cell):
    """verts (n,8) float32 в GL/мире, tris (m,3) int64. Делит по ячейкам и кускам."""
    if len(tris) == 0:
        return
    if cell is None:                      # небо и т.п.: без деления по ячейкам
        keys = np.zeros(len(tris), np.int64)
    else:
        cen = (verts[tris[:, 0], :3] + verts[tris[:, 1], :3] + verts[tris[:, 2], :3]) / 3.0
        keys = group_by_cell(cen[:, [0, 2]], cell)
    order = np.argsort(keys, kind='stable')
    keys_s, tris_s = keys[order], tris[order]
    bounds = np.flatnonzero(np.diff(keys_s)) + 1
    for grp_start, grp_end in zip(np.r_[0, bounds], np.r_[bounds, len(keys_s)]):
        key = int(keys_s[grp_start])
        for s in range(grp_start, grp_end, TRI_CHUNK):
            t = tris_s[s:min(s + TRI_CHUNK, grp_end)]
            uniq, inv = np.unique(t.ravel(), return_inverse=True)
            buckets[(matidx, key)].append((verts[uniq], inv.reshape(-1, 3).astype(np.int64)))


def finalize_batches(buckets):
    batches = []
    for (matidx, key) in sorted(buckets):
        cur_v, cur_i, n = [], [], 0
        for v, t in buckets[(matidx, key)]:
            if n + len(v) > MAX_VERTS and cur_v:
                batches.append((matidx, np.concatenate(cur_v), np.concatenate(cur_i)))
                cur_v, cur_i, n = [], [], 0
            cur_v.append(v)
            cur_i.append((t + n).ravel())
            n += len(v)
        if cur_v:
            batches.append((matidx, np.concatenate(cur_v), np.concatenate(cur_i)))
    return batches


BOX_FACES = [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1),
             (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3)]


def bake_collision(cols, trs, go2tr, gos, g2p, mesh_cache, matrix_cache):
    """-> (треугольники float32 (n,9), статистика)"""
    out, st = [], collections.Counter()
    for c in cols:
        tid = go2tr.get(c['go'])
        if tid is None or not active_in_hierarchy(tid, trs, gos):
            st['неактивен'] += 1
            continue
        W = world_matrix(tid, trs, matrix_cache)           # Unity-пространство
        if c['kind'] == 'box':
            sx, sy, sz = c['size']
            cx, cy, cz = c['center']
            corners = np.array([[cx + dx * sx / 2, cy + dy * sy / 2, cz + dz * sz / 2, 1.0]
                                for dx in (-1, 1) for dy in (-1, 1) for dz in (-1, 1)])
            # порядок (dx,dy,dz): индекс = dx*4 + dy*2 + dz при -1->0, 1->1 — совпадает с BOX_FACES
            wp = (corners @ W.T)[:, :3] * np.array([-1.0, 1.0, 1.0])
            out.append(np.array([wp[list(f)].ravel() for f in BOX_FACES], np.float32))
            st['box'] += 1
            continue
        mpath = g2p.get(c['mesh'])
        if not mpath or not os.path.isfile(mpath):
            st['нет меша'] += 1
            continue
        if mpath not in mesh_cache:
            try:
                mesh_cache[mpath] = load_mesh(mpath)
            except Exception:
                mesh_cache[mpath] = None
        md = mesh_cache[mpath]
        if md is None:
            st['меш не читается'] += 1
            continue
        M = SX @ W @ SX
        M3 = M[:3, :3]
        wpos = (md.pos * np.array([-1, 1, 1], np.float32)) @ M3.T.astype(np.float32) + M[:3, 3].astype(np.float32)
        for tr in md.subs:
            if tr is None or len(tr) == 0:
                continue
            out.append(wpos[tr].reshape(-1, 9).astype(np.float32))
        st['mesh'] += 1
    if not out:
        return np.zeros((0, 9), np.float32), st
    tris = np.concatenate(out)
    a = tris[:, 0:3]; b = tris[:, 3:6]; c = tris[:, 6:9]
    area2 = np.linalg.norm(np.cross(b - a, c - a), axis=1)
    keep = area2 > 1e-8
    st['вырожденных'] = int((~keep).sum())
    return tris[keep], st


SPAWN_PATTERNS = [r'team\s*_?a.*(resp|point|spawn)', r'general.*(resp|point|spawn)',
                  r'(resp|spawn)\w*\s*_?points?', r'resp']
SPAWN_EXCLUDE = r'hidden|bonus|light|seat|pivot'


def find_spawns(trs, gos, matrix_cache):
    """Мировые позиции (GL) всех листовых точек появления из подходящих контейнеров.
    Первая — основная (для игрока): берётся из самой приоритетной группы."""
    children = collections.defaultdict(list)
    for tid, t in trs.items():
        children[t['father']].append(tid)

    def leaves(tid, depth=0):
        kids = children.get(tid, [])
        if not kids or depth > 8:
            return [tid] if depth > 0 else []
        out = []
        for k in kids:
            out.extend(leaves(k, depth + 1))
        return out

    found, seen = [], set()
    for pat in SPAWN_PATTERNS:
        for tid, t in trs.items():
            g = gos.get(t['go'])
            if not g or re.search(SPAWN_EXCLUDE, g['name'], re.I) or not re.search(pat, g['name'], re.I):
                continue
            for leaf in leaves(tid):
                M = SX @ world_matrix(leaf, trs, matrix_cache) @ SX
                key = tuple(np.round(M[:3, 3], 2))
                if key not in seen:
                    seen.add(key)
                    found.append(M[:3, 3].copy())
    return found


def find_spawn(trs, gos, matrix_cache):
    sp = find_spawns(trs, gos, matrix_cache)
    return sp[0] if sp else None


def build_scene(assets, res, scene_path, max_tex, cell):
    mesh_dir = os.path.join(res, 'meshes')
    tex_dir = os.path.join(res, 'textures')
    os.makedirs(tex_dir, exist_ok=True)
    g2p = ba.build_guid_map(assets)
    gos, trs, go2tr, mfs, mrs, cols, n_prefab = parse_scene(scene_path)
    if n_prefab:
        print('  ! PrefabInstance: %d (вложенные префабы не раскрываются)' % n_prefab)

    mesh_cache, mat_cache, tex_info = {}, {}, {}
    matkeys, mat_table = {}, []
    buckets = collections.defaultdict(list)
    matrix_cache = {}
    stats = collections.Counter()
    warned = set()

    def material_index(guid):
        if guid in mat_cache:
            return mat_cache[guid]
        p = g2p.get(guid)
        if not p or not os.path.isfile(p):
            mat_cache[guid] = None
            return None
        mname = re.search(r'm_Name:\s*(.*)', read(p, 800))
        if mname and re.search(r'collider|trigger|invisible', mname.group(1), re.I):
            mat_cache[guid] = None
            return None
        mi = ba.parse_material(p)
        tname, cutout = '', False
        tp = g2p.get(mi['tex']) if mi['tex'] else None
        if tp and os.path.isfile(tp) and tp.lower().endswith('.png'):
            tname = ba.tex_name(tp)
            if tname not in tex_info:
                try:
                    tex_info[tname] = ba.convert_texture(tp, os.path.join(tex_dir, tname + '.cgt'), max_tex)
                except Exception as e:
                    print('  ! текстура', tp, e)
                    tex_info[tname] = None
            if tex_info[tname]:
                cutout = bool(tex_info[tname][3])
            else:
                tname = ''
        if len(tname) > 47:
            raise ValueError('слишком длинное имя текстуры: ' + tname)
        sx, sy = mi['scale']
        ox, oy = mi['offset']
        uvst = (sx, sy, ox, 1.0 - sy - oy)
        is_sky = bool(re.search(r'sky', tname + ' ' + (mname.group(1) if mname else ''), re.I))
        key = (tname, tuple(round(c, 4) for c in mi['color']), tuple(round(u, 5) for u in uvst),
               (1 if cutout else 0) | (2 if is_sky else 0))
        if key not in matkeys:
            matkeys[key] = len(mat_table)
            mat_table.append(key)
        mat_cache[guid] = matkeys[key]
        return mat_cache[guid]

    for go, mguid in mfs.items():
        mr = mrs.get(go)
        if not mr or not mr['enabled'] or not mr['mats']:
            stats['без рендерера/выключен'] += 1
            continue
        tid = go2tr.get(go)
        if tid is None or not active_in_hierarchy(tid, trs, gos):
            stats['неактивен'] += 1
            continue
        mpath = g2p.get(mguid)
        if not mpath or not os.path.isfile(mpath):
            stats['нет меша в дампе'] += 1
            continue
        if mpath not in mesh_cache:
            try:
                mesh_cache[mpath] = load_mesh(mpath)
            except Exception as e:
                mesh_cache[mpath] = None
                if mpath not in warned:
                    warned.add(mpath)
                    print('  ! меш %s пропущен: %s' % (os.path.basename(mpath), e))
        md = mesh_cache[mpath]
        if md is None:
            stats['меш не читается'] += 1
            continue

        batched = mr['count'] > 0
        if batched:
            M = np.eye(4)                        # Combined-меш уже в мировых координатах
            sub_range = range(mr['first'], mr['first'] + mr['count'])
        else:
            M = SX @ world_matrix(tid, trs, matrix_cache) @ SX
            sub_range = range(len(mr['mats']))
        M3 = M[:3, :3]
        det = np.linalg.det(M3)
        if abs(det) < 1e-12:
            stats['вырожденный масштаб'] += 1
            continue
        NM = np.linalg.inv(M3).T
        pos = md.pos * np.array([-1, 1, 1], np.float32)          # как в .cgm
        nrm = md.nrm * np.array([-1, 1, 1], np.float32)
        wpos = pos @ M3.T.astype(np.float32) + M[:3, 3].astype(np.float32)
        wnrm = nrm @ NM.T.astype(np.float32)
        ln = np.linalg.norm(wnrm, axis=1, keepdims=True)
        wnrm = wnrm / np.maximum(ln, 1e-12)
        uv = md.uv.copy()
        uv[:, 1] = 1.0 - uv[:, 1]
        verts = np.concatenate([wpos, wnrm, uv], axis=1).astype(np.float32)

        for k, sm in enumerate(sub_range):
            mat_slot = k if batched else sm
            if sm >= len(md.subs) or md.subs[sm] is None or mat_slot >= len(mr['mats']):
                continue
            mi = material_index(mr['mats'][mat_slot])
            if mi is None:
                stats['материал пропущен'] += 1
                continue
            tris = md.subs[sm]
            # зеркалирование X (меш) инвертирует обход -> всегда меняем; отрицательный det — ещё раз
            tris = tris[:, [0, 2, 1]]
            if det < 0:
                tris = tris[:, [0, 2, 1]]
            add_piece(buckets, mi, verts, tris, None if (mat_table[mi][3] & 2) else cell)
            stats['сабмешей'] += 1
        stats['рендереров'] += 1

    batches = finalize_batches(buckets)
    if not batches:
        print('  в сцене нет геометрии (UI/меню), пропущена')
        return None

    spawns = find_spawns(trs, gos, matrix_cache)
    spawn = spawns[0] if spawns else None

    all_v = np.concatenate([b[1][:, :3] for b in batches]) if batches else np.zeros((1, 3), np.float32)
    bmin, bmax = all_v.min(0), all_v.max(0)
    if spawn is None:
        spawn = np.array([(bmin[0] + bmax[0]) / 2, bmax[1] + 2.0, (bmin[2] + bmax[2]) / 2])
    else:
        spawn = spawn + np.array([0, 1.7, 0])

    # ---- запись
    out_dir = os.path.join(res, 'scenes')
    os.makedirs(out_dir, exist_ok=True)
    name = os.path.splitext(os.path.basename(scene_path))[0]
    out = os.path.join(out_dir, safe_name(name) + '.cgs')

    blob = bytearray()
    headers = []
    for matidx, v, idx in batches:
        voff = len(blob)
        blob += v.astype('<f4').tobytes()
        ioff = len(blob)
        blob += idx.astype('<u2').tobytes()
        while len(blob) % 4:
            blob += b'\0'
        headers.append((matidx, len(v), len(idx), voff, ioff, v[:, :3].min(0), v[:, :3].max(0)))

    with open(out, 'wb') as f:
        f.write(b'CGS1')
        f.write(struct.pack('<II', len(mat_table), len(headers)))
        f.write(struct.pack('<9f', *bmin, *bmax, *spawn))
        for tname, color, uvst, flags in mat_table:
            f.write(struct.pack('<48s3f4fI', tname.encode('ascii'), *color, *uvst, flags))
        for matidx, vc, ic, voff, ioff, bn, bx in headers:
            f.write(struct.pack('<5I6fI', matidx, vc, ic, voff, ioff, *bn, *bx, 0))
        f.write(blob)

    cgp = os.path.join(out_dir, safe_name(name) + '.cgp')
    with open(cgp, 'wb') as f:
        f.write(b'CGP1')
        f.write(struct.pack('<I', len(spawns)))
        for sp in spawns:
            f.write(struct.pack('<3f', *[float(x) for x in sp]))
    print('  точек появления: %d' % len(spawns))

    ctris, cst = bake_collision(cols, trs, go2tr, gos, g2p, mesh_cache, matrix_cache)
    cgc = os.path.join(out_dir, safe_name(name) + '.cgc')
    if len(ctris):
        cv = ctris.reshape(-1, 3)
        cmin, cmax = cv.min(0), cv.max(0)
    else:
        cmin = cmax = np.zeros(3, np.float32)
    with open(cgc, 'wb') as f:
        f.write(b'CGC1')
        f.write(struct.pack('<I', len(ctris)))
        f.write(struct.pack('<6f', *cmin, *cmax))
        f.write(ctris.astype('<f4').tobytes())
    print('  коллизия: %d треугольников (%.1f МБ), %s' % (len(ctris), os.path.getsize(cgc) / 1048576.0, dict(cst)))

    tris_total = sum(h[2] for h in headers) // 3
    verts_total = sum(h[1] for h in headers)
    print('  %s: батчей %d, материалов %d, треугольников %d, вершин %d, размер %.1f МБ'
          % (name, len(headers), len(mat_table), tris_total, verts_total, os.path.getsize(out) / 1048576.0))
    print('  границы X[%.0f..%.0f] Y[%.0f..%.0f] Z[%.0f..%.0f]  spawn (%.1f, %.1f, %.1f)'
          % (bmin[0], bmax[0], bmin[1], bmax[1], bmin[2], bmax[2], *spawn))
    print('  ', dict(stats))
    return out, batches, bmin, bmax, spawn


def main():
    argv = sys.argv[1:]
    max_tex, cell = 256, 16.0
    if '--max-tex' in argv:
        i = argv.index('--max-tex'); max_tex = int(argv[i + 1]); del argv[i:i + 2]
    if '--cell' in argv:
        i = argv.index('--cell'); cell = float(argv[i + 1]); del argv[i:i + 2]
    if len(argv) < 3:
        print(__doc__)
        sys.exit(1)
    assets, res, scenes = argv[0], argv[1], argv[2:]
    for s in scenes:
        print('Сцена', s)
        build_scene(assets, res, s, max_tex, cell)
    sc_dir = os.path.join(res, 'scenes')
    with open(os.path.join(res, 'scenes.txt'), 'w') as f:
        f.write('\n'.join(sorted(x for x in os.listdir(sc_dir) if x.endswith('.cgs'))) + '\n')


if __name__ == '__main__':
    main()
