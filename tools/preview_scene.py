#!/usr/bin/env python3
"""
Проверочный рендер .cgs (вид сверху, программная растеризация, без GPU).
Читает файл так же, как это делает C-код, проверяет обход треугольников.

    preview_scene.py <Resources> <Имя.cgs> <out.png> [--ext 190]
Небо (флаг материала бит1) не рисуется. Жёлтое кольцо — точка появления.
"""
import struct, sys, os
import numpy as np
from PIL import Image, ImageDraw

res, name, out = sys.argv[1:4]
ext = float(sys.argv[sys.argv.index('--ext') + 1]) if '--ext' in sys.argv else 190.0
d = open(os.path.join(res, 'scenes', name), 'rb').read()
assert d[:4] == b'CGS1', 'не CGS1'
mc, bc = struct.unpack_from('<II', d, 4)
vals = struct.unpack_from('<9f', d, 12)
bmin, bmax, spawn = vals[:3], vals[3:6], vals[6:]
off = 48
mats = []
for i in range(mc):
    tex = struct.unpack_from('<48s', d, off)[0].split(b'\0')[0].decode()
    col = struct.unpack_from('<3f', d, off + 48)
    flags = struct.unpack_from('<I', d, off + 76)[0]
    mats.append((tex, col, flags)); off += 80
hdr = []
for i in range(bc):
    hdr.append(struct.unpack_from('<5I6fI', d, off)); off += 48
blob = off


def avg(tex):
    if not tex:
        return np.array([200.0, 200.0, 200.0])
    t = open(os.path.join(res, 'textures', tex + '.cgt'), 'rb').read()
    w, h, fmt, mips = struct.unpack_from('<4I', t, 4)
    sz = sum(max(w >> l, 1) * max(h >> l, 1) * 2 for l in range(mips - 1))
    a = struct.unpack_from('<H', t, 20 + sz)[0]
    if fmt == 0:
        return np.array([((a >> 11) & 31) * 255 / 31, ((a >> 5) & 63) * 255 / 63, (a & 31) * 255 / 31])
    return np.array([((a >> 12) & 15) * 17.0, ((a >> 8) & 15) * 17.0, ((a >> 4) & 15) * 17.0])


mcol = [avg(m[0]) * np.array(m[1]) for m in mats]
S = 900
img = np.full((S, S, 3), (110, 155, 215), np.float32)
zb = np.full((S, S), -1e9)
L = np.array([0.4, 0.8, 0.6]); L /= np.linalg.norm(L)
ntri = wrong = skipped_sky = 0
for mi, vc, ic, vo, io, *rest in hdr:
    if mats[mi][2] & 2:
        skipped_sky += 1
        continue
    v = np.frombuffer(d, '<f4', vc * 8, blob + vo).reshape(vc, 8)
    idx = np.frombuffer(d, '<u2', ic, blob + io).reshape(-1, 3)
    c = np.clip(mcol[mi], 0, 255)
    px = (v[:, 0] + ext) / (2 * ext) * S
    pz = (v[:, 2] + ext) / (2 * ext) * S
    for a, b, cc in idx:
        ntri += 1
        n = np.cross(v[b, :3] - v[a, :3], v[cc, :3] - v[a, :3])
        if n @ (v[a, 3:6] + v[b, 3:6] + v[cc, 3:6]) < 0:
            wrong += 1
        x0, x1 = int(max(min(px[[a, b, cc]]), 0)), int(min(max(px[[a, b, cc]]), S - 1))
        z0, z1 = int(max(min(pz[[a, b, cc]]), 0)), int(min(max(pz[[a, b, cc]]), S - 1))
        if x1 < x0 or z1 < z0 or (x1 - x0) * (z1 - z0) > 250000:
            continue
        X, Z = np.meshgrid(np.arange(x0, x1 + 1) + .5, np.arange(z0, z1 + 1) + .5)
        den = (pz[b] - pz[cc]) * (px[a] - px[cc]) + (px[cc] - px[b]) * (pz[a] - pz[cc])
        if abs(den) < 1e-9:
            continue
        w0 = ((pz[b] - pz[cc]) * (X - px[cc]) + (px[cc] - px[b]) * (Z - pz[cc])) / den
        w1 = ((pz[cc] - pz[a]) * (X - px[cc]) + (px[a] - px[cc]) * (Z - pz[cc])) / den
        w2 = 1 - w0 - w1
        m = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not m.any():
            continue
        y = w0 * v[a, 1] + w1 * v[b, 1] + w2 * v[cc, 1]
        sub = zb[z0:z1 + 1, x0:x1 + 1]
        upd = m & (y > sub)
        if not upd.any():
            continue
        nn = v[a, 3:6] + v[b, 3:6] + v[cc, 3:6]
        nn = nn / (np.linalg.norm(nn) + 1e-9)
        sub[upd] = y[upd]
        img[z0:z1 + 1, x0:x1 + 1][upd] = c * (0.35 + 0.65 * max(nn @ L, 0))
print('батчей неба пропущено: %d; треугольников: %d; несовпадений обхода: %d (%.2f%%)'
      % (skipped_sky, ntri, wrong, 100.0 * wrong / max(ntri, 1)))
im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
sx_ = (spawn[0] + ext) / (2 * ext) * S
sz_ = (spawn[2] + ext) / (2 * ext) * S
ImageDraw.Draw(im).ellipse([sx_ - 7, sz_ - 7, sx_ + 7, sz_ + 7], outline=(255, 255, 0), width=3)
im.save(out)
