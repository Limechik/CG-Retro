#!/usr/bin/env python3
"""
Собирает персонажа из жёстких частей (курица «Rudy») в файл .cgr: дерево узлов, меши с материалами
и запечённые клипы анимации.

У курицы нет скиннинга: это дерево объектов с обычными мешами, а анимация двигает локальные
трансформы нескольких узлов (ноги, туловище, оружие). Поэтому:
- берётся поддерево корня префаба (только активные объекты; оружие включается принудительно);
- кривые клипа (Эйлер/позиция/кватернион, кубический Эрмит с наклонами Unity) семплируются в
  покадровые позы (30 к/с) для каждого анимируемого узла;
- Unity (левосторонняя) -> GL: X позиции инвертируется, кватернион (x,y,z,w) -> (x,-y,-z,w).

Формат CGR1 (little-endian):
    char   magic[4] = "CGR1"
    uint32 nodeCount, partCount, clipCount
    Node[nodeCount]   (64 байта): int32 parent; float pos[3]; float quat[4]; float scale[3]; char name[20]
    Part[partCount]   (132 байта): uint32 node; uint32 flags (бит0 = обратный обход, бит1 = cutout);
                      char mesh[48]; char tex[48]; float color[3]; float uvst[4]
    Clip[clipCount]:  char name[24]; float duration; uint32 loop; uint32 frames; uint32 tracks;
                      затем tracks раз: uint32 node; float data[frames * 7]  (pos[3] + quat[4] на кадр)

Использование:
    build_character.py <Assets> <Resources>
"""
import os, re, sys, struct, math, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + '.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


bs = _load('build_scene')
ba = bs.ba
cm = bs.cm

PREFAB = 'Resources/P_Player.prefab'
ROOT_NAME = 'RudyContainer'
FORCE_ACTIVE = {'AK47_GunSystem'}              # оружие в руках (в префабе выключено)
CLIPS = ['Idle', 'Run', 'TopIdle', 'TopRun', 'AK47Shoot']
FPS = 30
INF = float('inf')


# ------------------------------------------------------------ кватернионы (Unity: x, y, z, w)

def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def qaxis(axis, deg):
    h = math.radians(deg) * 0.5
    s, c = math.sin(h), math.cos(h)
    v = [0.0, 0.0, 0.0]
    v[axis] = s
    return (v[0], v[1], v[2], c)


def euler_to_quat(x, y, z):
    """Quaternion.Euler в Unity: порядок применения Z, затем X, затем Y."""
    return qmul(qmul(qaxis(1, y), qaxis(0, x)), qaxis(2, z))


def qnorm(q):
    l = math.sqrt(sum(c * c for c in q)) or 1.0
    return tuple(c / l for c in q)


# ------------------------------------------------------------ клипы

NUM = r'([^,}\s]+)'
KEY_RE = re.compile(
    r'time:\s*' + NUM + r'\s*\n\s*value:\s*\{x:\s*' + NUM + r',\s*y:\s*' + NUM + r',\s*z:\s*' + NUM + r'(?:,\s*w:\s*' + NUM + r')?\}\s*\n'
    r'\s*inSlope:\s*\{x:\s*' + NUM + r',\s*y:\s*' + NUM + r',\s*z:\s*' + NUM + r'(?:,\s*w:\s*' + NUM + r')?\}\s*\n'
    r'\s*outSlope:\s*\{x:\s*' + NUM + r',\s*y:\s*' + NUM + r',\s*z:\s*' + NUM + r'(?:,\s*w:\s*' + NUM + r')?\}')


class Curve:
    def __init__(self, kind, path, keys):
        self.kind, self.path, self.keys = kind, path, keys      # keys: [(t, value[], inSlope[], outSlope[])]

    def eval(self, t):
        ks = self.keys
        n = len(ks[0][1])
        if t <= ks[0][0]:
            return list(ks[0][1])
        if t >= ks[-1][0]:
            return list(ks[-1][1])
        for i in range(len(ks) - 1):
            t0, v0, _, o0 = ks[i]
            t1, v1, i1, _ = ks[i + 1]
            if t0 <= t <= t1:
                dt = t1 - t0
                if dt <= 1e-9:
                    return list(v1)
                s = (t - t0) / dt
                out = []
                for c in range(n):
                    if abs(o0[c]) == INF or abs(i1[c]) == INF:
                        out.append(v0[c])                       # ступенчатая кривая
                        continue
                    m0, m1 = o0[c] * dt, i1[c] * dt
                    s2, s3 = s * s, s * s * s
                    out.append((2 * s3 - 3 * s2 + 1) * v0[c] + (s3 - 2 * s2 + s) * m0 +
                               (-2 * s3 + 3 * s2) * v1[c] + (s3 - s2) * m1)
                return out
        return list(ks[-1][1])


def parse_clip(path):
    t = ba.read(path)
    dur = float(re.search(r'm_StopTime:\s*(\S+)', t).group(1))
    loop = re.search(r'm_LoopTime:\s*(\d)', t)
    curves = []
    for tag, kind in (('m_PositionCurves', 'pos'), ('m_EulerCurves', 'euler'),
                      ('m_RotationCurves', 'rot'), ('m_ScaleCurves', 'scale')):
        m = re.search(r'\n  ' + tag + r':(.*?)(?=\n  m_\w+:)', t, flags=re.S)
        if not m or m.group(1).strip() in ('', '[]'):
            continue
        for chunk in m.group(1).split('- curve:')[1:]:
            pm = re.findall(r'\n\s+path:\s*(.*)', chunk)
            keys = []
            for k in KEY_RE.finditer(chunk):
                g = k.groups()
                comps = 4 if g[4] is not None else 3
                tt = float(g[0])
                val = [float(x) for x in (g[1], g[2], g[3], g[4])[:comps]]
                ins = [float(x) for x in (g[5], g[6], g[7], g[8])[:comps]]
                outs = [float(x) for x in (g[9], g[10], g[11], g[12])[:comps]]
                keys.append((tt, val, ins, outs))
            if keys and pm:
                curves.append(Curve(kind, pm[-1].strip(), keys))
    return {'name': re.search(r'm_Name:\s*(.*)', t).group(1).strip(), 'duration': dur,
            'loop': 1 if (loop and loop.group(1) == '1') else 0, 'curves': curves}


# ------------------------------------------------------------ построение

def mirror_pos(p):
    return (-p[0], p[1], p[2])


def mirror_quat(q):
    return (q[0], -q[1], -q[2], q[3])


def build(assets, res):
    prefab = os.path.join(assets, PREFAB)
    gos, trs, go2tr, mfs, mrs, _cols, _n = bs.parse_scene(prefab)
    g2p = ba.build_guid_map(assets)

    children = {}
    for tid, t in trs.items():
        children.setdefault(t['father'], []).append(tid)
    root = next(tid for tid, t in trs.items() if gos[t['go']]['name'] == ROOT_NAME)

    # ---- клипы (нужны сначала: по ним решаем, какие узлы оставить)
    clip_dir = os.path.join(assets, 'AnimationClip')
    clips = [parse_clip(os.path.join(clip_dir, n + '.anim')) for n in CLIPS]
    animated_paths = {c.path for cl in clips for c in cl['curves']}

    # ---- дерево активных узлов
    nodes = []          # dict(tid, parent, name, path)

    def collect(tid, parent, path):
        go = gos[trs[tid]['go']]
        name = go['name']
        if tid != root and not (go['active'] or name in FORCE_ACTIVE):
            return
        idx = len(nodes)
        nodes.append({'tid': tid, 'parent': parent, 'name': name, 'path': path})
        for c in children.get(tid, []):
            cn = gos[trs[c]['go']]['name']
            collect(c, idx, (path + '/' + cn) if path else cn)

    collect(root, -1, '')

    def mesh_asset(go):
        guid = mfs.get(go)
        p = g2p.get(guid) if guid else None
        return p if p and os.path.isfile(p) else None

    def has_mesh(n):
        go = trs[n['tid']]['go']
        mr = mrs.get(go)
        return bool(mr and mr['enabled'] and mr['mats'] and mesh_asset(go))

    keep = set()
    path_to_idx = {}
    for i, n in enumerate(nodes):
        path_to_idx.setdefault(n['path'], i)
    for i, n in enumerate(nodes):
        if has_mesh(n) or n['path'] in animated_paths:
            j = i
            while j >= 0 and j not in keep:
                keep.add(j)
                j = nodes[j]['parent']
    order = sorted(keep)
    remap = {old: new for new, old in enumerate(order)}
    final = []
    for old in order:
        n = dict(nodes[old])
        n['parent'] = remap[n['parent']] if n['parent'] >= 0 else -1
        final.append(n)
    path_to_final = {}
    for i, n in enumerate(final):
        path_to_final.setdefault(n['path'], i)

    # ---- части (меш + материал)
    mesh_dir = os.path.join(res, 'meshes')
    tex_dir = os.path.join(res, 'textures')
    os.makedirs(tex_dir, exist_ok=True)
    parts, missing = [], []
    sign_cache = {}

    def det_sign(i):
        if i < 0:
            return 1
        if i in sign_cache:
            return sign_cache[i]
        s = trs[final[i]['tid']]['s']
        sg = 1 if (s[0] * s[1] * s[2]) >= 0 else -1
        sign_cache[i] = sg * det_sign(final[i]['parent'])
        return sign_cache[i]

    for i, n in enumerate(final):
        if not has_mesh(n):
            continue
        go = trs[n['tid']]['go']
        mp = mesh_asset(go)
        nm = re.search(r'm_Name:\s*(.*)', ba.read(mp, 2000))
        mname = ba.safe_name(nm.group(1).strip()) if nm else ba.safe_name(os.path.splitext(os.path.basename(mp))[0])
        if not os.path.isfile(os.path.join(mesh_dir, mname + '.cgm')):
            missing.append(mname)
            continue
        mats = mrs[go]['mats']
        mi = None
        for g in mats:
            p = g2p.get(g)
            if p and os.path.isfile(p):
                cand = ba.parse_material(p)
                if mi is None or (mi['tex'] is None and cand['tex']):
                    mi = cand
        if mi is None:
            missing.append(mname + ' (нет материала)')
            continue
        tname, cutout = '', False
        tp = g2p.get(mi['tex']) if mi['tex'] else None
        if tp and os.path.isfile(tp) and tp.lower().endswith('.png'):
            tname = ba.tex_name(tp)
            w, h, fmt, cut, sz = ba.convert_texture(tp, os.path.join(tex_dir, tname + '.cgt'), 256)
            cutout = bool(cut)
        sx, sy = mi['scale']
        ox, oy = mi['offset']
        flags = (1 if det_sign(i) < 0 else 0) | (2 if cutout else 0)
        parts.append({'node': i, 'flags': flags, 'mesh': mname, 'tex': tname,
                      'color': mi['color'], 'uvst': (sx, sy, ox, 1.0 - sy - oy)})
    if missing:
        raise SystemExit('нет .cgm для мешей: %s' % sorted(set(missing)))

    # ---- запись клипов: покадровые позы анимируемых узлов
    baked = []
    unresolved = set()
    for cl in clips:
        by_node = {}
        for c in cl['curves']:
            idx = path_to_final.get(c.path)
            if idx is None:
                unresolved.add((cl['name'], c.path))
                continue
            by_node.setdefault(idx, []).append(c)
        frames = max(2, int(math.ceil(cl['duration'] * FPS)))
        tracks = []
        for idx, cs in sorted(by_node.items()):
            t = trs[final[idx]['tid']]
            rest_p, rest_q = tuple(t['p']), tuple(t['r'])
            data = []
            for f in range(frames):
                tm = f / float(FPS) if cl['loop'] else min(f / float(FPS), cl['duration'])
                p, q = rest_p, rest_q
                for c in cs:
                    v = c.eval(tm)
                    if c.kind == 'pos':
                        p = tuple(v)
                    elif c.kind == 'euler':
                        q = euler_to_quat(*v)
                    elif c.kind == 'rot':
                        q = qnorm(tuple(v))
                gp, gq = mirror_pos(p), mirror_quat(qnorm(q))
                data.extend([gp[0], gp[1], gp[2], gq[0], gq[1], gq[2], gq[3]])
            tracks.append((idx, data))
        baked.append((cl['name'], cl['duration'], cl['loop'], frames, tracks))

    # ---- запись файла
    out_dir = os.path.join(res, 'characters')
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, 'rudy.cgr')

    def cstr(s, n):
        b = s.encode('ascii', 'replace')[:n - 1]
        return b + b'\0' * (n - len(b))

    with open(out, 'wb') as f:
        f.write(b'CGR1')
        f.write(struct.pack('<3I', len(final), len(parts), len(baked)))
        for n in final:
            t = trs[n['tid']]
            gp, gq = mirror_pos(t['p']), mirror_quat(qnorm(tuple(t['r'])))
            f.write(struct.pack('<i3f4f3f', n['parent'], *gp, *gq, *t['s']))
            f.write(cstr(n['name'], 20))
        for p in parts:
            f.write(struct.pack('<2I', p['node'], p['flags']))
            f.write(cstr(p['mesh'], 48))
            f.write(cstr(p['tex'], 48))
            f.write(struct.pack('<3f4f', *p['color'], *p['uvst']))
        for name, dur, loop, frames, tracks in baked:
            f.write(cstr(name, 24))
            f.write(struct.pack('<fIII', dur, loop, frames, len(tracks)))
            for idx, data in tracks:
                f.write(struct.pack('<I', idx))
                f.write(struct.pack('<%df' % len(data), *data))

    print('узлов %d, частей %d, клипов %d -> %s (%.1f КБ)' % (len(final), len(parts), len(baked), out, os.path.getsize(out) / 1024.0))
    for n in baked:
        print('  клип %-10s %.2f с, %s, кадров %d, треков %d' % (n[0], n[1], 'цикл' if n[2] else 'один раз', n[3], len(n[4])))
    for p in parts:
        print('  часть %-28s узел %-22s tex=%-18s flip=%d' % (p['mesh'], final[p['node']]['path'] or '(корень)', p['tex'] or '-', p['flags'] & 1))
    if unresolved:
        print('  ! пути клипов без узла:', sorted(unresolved))
    return out


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    build(sys.argv[1], sys.argv[2])
