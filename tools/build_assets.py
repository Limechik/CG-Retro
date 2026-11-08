#!/usr/bin/env python3
"""
Строит таблицу материалов и конвертирует текстуры для iOS 6 / GLES2.

1. Через GUID из .meta связывает: меш -> материал -> _MainTex (по префабам и сценам дампа).
2. Конвертирует используемые PNG в .cgt (степень двойки, мипмапы, RGB565 / RGBA4444, дизеринг).
3. Пишет Resources/materials.plist: имя меша -> {tex, color, uvst, cutout}.

Формат CGT1 (little-endian):
    char   magic[4] = "CGT1"
    uint32 width, height
    uint32 format        // 0 = RGB565, 1 = RGBA4444
    uint32 mipCount
    uint16 data[]        // mip 0, mip 1, ... до 1x1; каждый уровень w*h пикселей

Использование:
    build_assets.py <dump>/Assets <проект>/Resources [--max-tex 256]
"""
import re, os, sys, glob, struct, plistlib, collections
import numpy as np
from PIL import Image

GUID = r'guid:\s*([0-9a-f]{32})'
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float32) / 16.0 - 0.5


def safe_name(n):
    return re.sub(r'[^A-Za-z0-9_.-]+', '_', n)


def tex_name(path):
    """Имя файла текстуры без расширения; длинные имена сокращаются (<= 40 символов + хеш)."""
    import hashlib
    stem = safe_name(os.path.splitext(os.path.basename(path))[0])
    if len(stem) > 40:
        stem = stem[:32] + '_' + hashlib.md5(stem.encode('utf-8')).hexdigest()[:7]
    return stem


def read(path, limit=None):
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        return f.read(limit) if limit else f.read()


# ---------------------------------------------------------------- GUID / связи

def build_guid_map(assets):
    g2p = {}
    for root, _, files in os.walk(assets):
        for fn in files:
            if fn.endswith('.meta'):
                m = re.search(GUID, read(os.path.join(root, fn), 600))
                if m:
                    g2p[m.group(1)] = os.path.join(root, fn[:-5])
    return g2p


def collect_mesh_materials(assets):
    """mesh_guid -> Counter{tuple(material_guids): count}"""
    files = (glob.glob(assets + '/Prefab/*.prefab') +
             glob.glob(assets + '/Resources/**/*.prefab', recursive=True) +
             glob.glob(assets + '/Scenes/*.unity') +
             glob.glob(assets + '/Scenes/*/*.unity'))
    result = collections.defaultdict(collections.Counter)
    for f in files:
        parts = re.split(r'(?m)^--- !u!(\d+) &(\d+)[^\n]*\n', read(f))
        objs = collections.defaultdict(dict)
        for i in range(1, len(parts), 3):
            cls, body = int(parts[i]), parts[i + 2]
            if cls not in (33, 23, 137):      # MeshFilter, MeshRenderer, SkinnedMeshRenderer
                continue
            g = re.search(r'm_GameObject:\s*\{fileID:\s*(\d+)', body)
            if not g:
                continue
            e = objs[g.group(1)]
            if cls in (33, 137):
                m = re.search(r'm_Mesh:\s*\{[^}]*?' + GUID, body)
                if m:
                    e['mesh'] = m.group(1)
            if cls in (23, 137):
                mb = re.search(r'm_Materials:\s*\n((?:\s*-\s*\{[^}]*\}\s*\n)+)', body)
                if mb:
                    e['mats'] = tuple(re.findall(GUID, mb.group(1)))
        for e in objs.values():
            if 'mesh' in e and e.get('mats'):
                result[e['mesh']][e['mats']] += 1
    return result


def parse_material(path):
    t = read(path)
    info = {'tex': None, 'color': [1.0, 1.0, 1.0], 'scale': (1.0, 1.0), 'offset': (0.0, 0.0)}
    m = re.search(r'\n\s+_MainTex:\s*\n\s+m_Texture:\s*\{[^}]*?' + GUID + r'[^}]*\}\s*\n'
                  r'\s+m_Scale:\s*\{x:\s*([-\d.eE+]+),\s*y:\s*([-\d.eE+]+)\}\s*\n'
                  r'\s+m_Offset:\s*\{x:\s*([-\d.eE+]+),\s*y:\s*([-\d.eE+]+)\}', t)
    if m:
        info['tex'] = m.group(1)
        info['scale'] = (float(m.group(2)), float(m.group(3)))
        info['offset'] = (float(m.group(4)), float(m.group(5)))
    c = re.search(r'\n\s+_Color:\s*\{r:\s*([-\d.eE+]+),\s*g:\s*([-\d.eE+]+),\s*b:\s*([-\d.eE+]+)', t)
    if c:
        info['color'] = [float(c.group(i)) for i in (1, 2, 3)]
    return info


# ---------------------------------------------------------------- текстуры

def pot_size(n, cap):
    """Ближайшая степень двойки (не больше cap)."""
    n = max(1, min(n, cap if n > cap else n))
    lo = 1
    while lo * 2 <= n:
        lo *= 2
    hi = lo * 2
    p = lo if (n - lo) < (hi - n) else hi
    return max(1, min(p, cap))


def quantize(rgba, fmt):
    h, w, _ = rgba.shape
    d = np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w]
    a = rgba.astype(np.float32) / 255.0
    if fmt == 0:  # RGB565
        r = np.clip(np.floor(a[..., 0] * 31 + 0.5 + d), 0, 31).astype(np.uint16)
        g = np.clip(np.floor(a[..., 1] * 63 + 0.5 + d), 0, 63).astype(np.uint16)
        b = np.clip(np.floor(a[..., 2] * 31 + 0.5 + d), 0, 31).astype(np.uint16)
        return (r << 11) | (g << 5) | b
    r = np.clip(np.floor(a[..., 0] * 15 + 0.5 + d), 0, 15).astype(np.uint16)
    g = np.clip(np.floor(a[..., 1] * 15 + 0.5 + d), 0, 15).astype(np.uint16)
    b = np.clip(np.floor(a[..., 2] * 15 + 0.5 + d), 0, 15).astype(np.uint16)
    al = np.clip(np.floor(a[..., 3] * 15 + 0.5 + d), 0, 15).astype(np.uint16)
    return (r << 12) | (g << 8) | (b << 4) | al


def convert_texture(src, dst, max_size):
    im = Image.open(src).convert('RGBA')
    w, h = im.size
    nw, nh = pot_size(w, max_size), pot_size(h, max_size)
    if (nw, nh) != (w, h):
        im = im.resize((nw, nh), Image.LANCZOS)
    alpha = np.asarray(im)[..., 3]
    cutout = float((alpha < 128).mean()) > 0.02      # настоящая прозрачность (листва, сетка...)
    fmt = 1 if (alpha < 250).any() else 0            # 4444 только если альфа реально используется
    levels = []
    cur = im
    while True:
        levels.append(quantize(np.asarray(cur), fmt))
        cw, ch = cur.size
        if cw == 1 and ch == 1:
            break
        cur = cur.resize((max(cw // 2, 1), max(ch // 2, 1)), Image.BOX)
    with open(dst, 'wb') as f:
        f.write(b'CGT1')
        f.write(struct.pack('<4I', nw, nh, fmt, len(levels)))
        for lv in levels:
            f.write(lv.astype('<u2').tobytes())
    return nw, nh, fmt, cutout, os.path.getsize(dst)


# ---------------------------------------------------------------- main

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    max_tex = 256
    if '--max-tex' in sys.argv:
        max_tex = int(sys.argv[sys.argv.index('--max-tex') + 1])
        args = [a for a in args if a != str(max_tex)]
    if len(args) != 2:
        print(__doc__)
        sys.exit(1)
    assets, res = args
    mesh_dir = os.path.join(res, 'meshes')
    tex_dir = os.path.join(res, 'textures')
    os.makedirs(tex_dir, exist_ok=True)

    print('GUID-карта...')
    g2p = build_guid_map(assets)
    print('  записей:', len(g2p))
    print('Связи меш -> материал (префабы и сцены)...')
    mm = collect_mesh_materials(assets)
    print('  мешей с материалами:', len(mm))

    mat_cache, tex_done, plist = {}, {}, {}
    total_bytes = 0
    missing_tex = 0

    for mesh_guid, variants in mm.items():
        mpath = g2p.get(mesh_guid)
        if not mpath or not os.path.isfile(mpath) or '/Mesh/' not in mpath.replace('\\', '/'):
            continue
        nm = re.search(r'm_Name:\s*(.*)', read(mpath, 2000))
        name = safe_name(nm.group(1).strip()) if nm else safe_name(os.path.splitext(os.path.basename(mpath))[0])
        if not os.path.isfile(os.path.join(mesh_dir, name + '.cgm')):
            continue

        # самый частый набор материалов; из него — первый слот с текстурой, иначе первый
        mats = variants.most_common(1)[0][0]
        chosen = None
        for g in mats:
            p = g2p.get(g)
            if p and os.path.isfile(p):
                if g not in mat_cache:
                    mat_cache[g] = parse_material(p)
                if chosen is None or (mat_cache[chosen]['tex'] is None and mat_cache[g]['tex']):
                    chosen = g
        if chosen is None:
            continue
        mi = mat_cache[chosen]

        entry = {'color': mi['color']}
        sx, sy = mi['scale']
        ox, oy = mi['offset']
        # меши конвертированы с V' = 1 - V, пересчитываем смещение
        entry['uvst'] = [sx, sy, ox, 1.0 - sy - oy]
        entry['cutout'] = False

        tg = mi['tex']
        tpath = g2p.get(tg) if tg else None
        if tpath and os.path.isfile(tpath) and tpath.lower().endswith('.png'):
            tname = tex_name(tpath)
            if tname not in tex_done:
                try:
                    w, h, fmt, cut, size = convert_texture(tpath, os.path.join(tex_dir, tname + '.cgt'), max_tex)
                    tex_done[tname] = (w, h, fmt, cut, size)
                    total_bytes += size
                except Exception as e:
                    print('  ! текстура', tpath, e)
                    tex_done[tname] = None
            if tex_done.get(tname):
                entry['tex'] = tname
                entry['cutout'] = bool(tex_done[tname][3])
        elif tg and tg != '0' * 32:
            missing_tex += 1
        plist[name] = entry

    with open(os.path.join(res, 'materials.plist'), 'wb') as f:
        plistlib.dump(plist, f, fmt=plistlib.FMT_XML)

    ok = {k: v for k, v in tex_done.items() if v}
    n565 = sum(1 for v in ok.values() if v[2] == 0)
    print('\nМатериалов в таблице: %d  (с текстурой: %d)' % (len(plist), sum(1 for e in plist.values() if 'tex' in e)))
    print('Текстур: %d  (RGB565: %d, RGBA4444: %d, cutout: %d)' %
          (len(ok), n565, len(ok) - n565, sum(1 for v in ok.values() if v[3])))
    print('Размер текстур: %.1f МБ (max-tex %d)' % (total_bytes / 1048576.0, max_tex))
    if missing_tex:
        print('Текстур не найдено или не PNG: %d' % missing_tex)


if __name__ == '__main__':
    main()
