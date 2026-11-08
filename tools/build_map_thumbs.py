#!/usr/bin/env python3
"""
Миниатюры карт для экрана «Новая игра» (Resources/maps/<Имя>.png): 3D-рендер .cgs под углом, с текстурами,
программной растеризацией (tools/cgraster.py). Небо (флаг материала бит 1) не рисуется.

    build_map_thumbs.py <Resources> [Resources/maps] [имя ...]
"""
import os, sys, struct
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cgraster as g

res = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(res, 'maps')
only = set(sys.argv[3:])
os.makedirs(out, exist_ok=True)
A = g.Assets(res)
W, H, SS = 420, 266, 2
YAW, PITCH = 25.0, 50.0
FIT = 1.0
PCT = {'Proto07': (0.5, 99.5)}     # у этой карты плотное ядро — одна плита, берём всю геометрию
SKY = (150, 195, 235)


def scene_tris(path):
    d = open(path, 'rb').read(); assert d[:4] == b'CGS1'
    mc, bc = struct.unpack_from('<II', d, 4)
    off = 48; mats = []
    for _ in range(mc):
        tex = struct.unpack_from('<48s', d, off)[0].split(b'\0')[0].decode()
        col = struct.unpack_from('<3f', d, off + 48); flags = struct.unpack_from('<I', d, off + 76)[0]
        mats.append((tex, col, flags)); off += 80
    hdr = []
    for _ in range(bc): hdr.append(struct.unpack_from('<5I6fI', d, off)); off += 48
    blob = off; tris = []
    for mi, vc, ic, vo, io, *rest in hdr:
        tex, col, flags = mats[mi]
        if flags & 2: continue
        v = np.frombuffer(d, '<f4', vc * 8, blob + vo).reshape(vc, 8)
        idx = np.frombuffer(d, '<u2', ic, blob + io).reshape(-1, 3)
        try: t = A.tex(tex) if tex else None
        except Exception: t = None
        tris.append((v[:, :3].astype(np.float64), v[:, 3:6].astype(np.float64), v[:, 6:8].astype(np.float64), idx, t, np.array(col, float), 0))
    return tris


for fn in sorted(os.listdir(os.path.join(res, 'scenes'))):
    if not fn.endswith('.cgs'): continue
    name = fn[:-4]
    if only and name not in only: continue
    tris = scene_tris(os.path.join(res, 'scenes', fn))
    # кадр по плотному ядру геометрии (8...92% проекций вершин), чтобы одинокие далёкие объекты не сжимали карту
    c, sn = np.cos(np.radians(YAW)), np.sin(np.radians(YAW)); cp, sp = np.cos(np.radians(PITCH)), np.sin(np.radians(PITCH))
    R = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]]) @ np.array([[c, 0, sn], [0, 1, 0], [-sn, 0, c]])
    pts = np.concatenate([t[0][::3] for t in tris]) @ R.T
    lo_p, hi_p = PCT.get(name, (8, 92))
    x0, x1 = np.percentile(pts[:, 0], [lo_p, hi_p]); y0, y1 = np.percentile(pts[:, 1], [lo_p, hi_p])
    scl = FIT * min(W * SS / max(x1 - x0, 1e-6), H * SS / max(y1 - y0, 1e-6))
    cen = np.array([(x0 + x1) / 2, (y0 + y1) / 2, 0.0]) @ R
    im, _ = g.render(tris, W, H, yaw=YAW, pitch=PITCH, ss=SS, cull=False, amb=0.55, view=(cen, scl))
    bg = Image.new('RGBA', (W, H), SKY + (255,))
    # мягкий градиент неба
    px = np.array(bg); t = np.linspace(0, 1, H)[:, None, None]
    px[..., :3] = (np.array(SKY) * (1 - t * 0.35) + np.array([225, 238, 250]) * (t * 0.35)).astype(np.uint8)
    bg = Image.fromarray(px, 'RGBA'); bg.alpha_composite(im)
    bg.convert('RGB').save(os.path.join(out, name + '.png'), optimize=True)
    print(name, len(tris), 'батчей', flush=True)
