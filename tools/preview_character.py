#!/usr/bin/env python3
"""
Проверочный рендер персонажа из .cgr (программный, без GPU): несколько ракурсов и поз.
Позу считает независимо от C-кода (по узлам и покадровым трекам из файла).

    preview_character.py <Resources> <out.png> [клип:время ...]     например: Idle:0 Run:0.1 Run:0.3
"""
import struct, sys, os, math
import numpy as np
from PIL import Image, ImageDraw

res, out = sys.argv[1], sys.argv[2]
poses = sys.argv[3:] or ['Idle:0']

d = open(os.path.join(res, 'characters', 'rudy.cgr'), 'rb').read()
assert d[:4] == b'CGR1'
nn, npart, nclip = struct.unpack_from('<3I', d, 4)
off = 16
nodes = []
for i in range(nn):
    par = struct.unpack_from('<i', d, off)[0]
    pos = struct.unpack_from('<3f', d, off + 4); q = struct.unpack_from('<4f', d, off + 16); sc = struct.unpack_from('<3f', d, off + 32)
    name = d[off + 44:off + 64].split(b'\0')[0].decode()
    nodes.append(dict(parent=par, pos=np.array(pos), quat=np.array(q), scale=np.array(sc), name=name)); off += 64
parts = []
for i in range(npart):
    node, flags = struct.unpack_from('<2I', d, off)
    mesh = d[off + 8:off + 56].split(b'\0')[0].decode(); tex = d[off + 56:off + 104].split(b'\0')[0].decode()
    color = struct.unpack_from('<3f', d, off + 104); uvst = struct.unpack_from('<4f', d, off + 116)
    parts.append(dict(node=node, flags=flags, mesh=mesh, tex=tex, color=color, uvst=uvst)); off += 132
clips = {}
for i in range(nclip):
    name = d[off:off + 24].split(b'\0')[0].decode()
    dur, loop, frames, tracks = struct.unpack_from('<fIII', d, off + 24); off += 40
    tr = []
    for t in range(tracks):
        node = struct.unpack_from('<I', d, off)[0]; off += 4
        data = np.frombuffer(d, '<f4', frames * 7, off).reshape(frames, 7); off += frames * 28
        tr.append((node, data))
    clips[name] = dict(dur=dur, loop=loop, frames=frames, tracks=tr)
assert off == len(d), 'лишние/недостающие байты в файле'

def qmat(q):
    x, y, z, w = q / np.linalg.norm(q)
    return np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                     [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                     [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])

def pose_world(spec):
    lp = [n['pos'].copy() for n in nodes]; lq = [n['quat'].copy() for n in nodes]
    for item in spec:
        name, t = item
        c = clips[name]
        f = t * 30.0
        f0 = int(math.floor(f)); fr = f - f0
        for node, data in c['tracks']:
            if c['loop']:
                a, b = data[f0 % c['frames']], data[(f0 + 1) % c['frames']]
            else:
                a, b = data[min(f0, c['frames'] - 1)], data[min(f0 + 1, c['frames'] - 1)]
            lp[node] = a[:3] * (1 - fr) + b[:3] * fr
            qa, qb = a[3:], b[3:]
            if np.dot(qa, qb) < 0: qb = -qb
            q = qa * (1 - fr) + qb * fr
            lq[node] = q / np.linalg.norm(q)
    world = [None] * len(nodes)
    for i, n in enumerate(nodes):
        L = np.eye(4); L[:3, :3] = qmat(lq[i]) @ np.diag(n['scale']); L[:3, 3] = lp[i]
        world[i] = (world[n['parent']] @ L) if n['parent'] >= 0 else L
    return world

def load_cgm(path):
    b = open(path, 'rb').read(); vc, ic = struct.unpack_from('<II', b, 4)
    return np.frombuffer(b, '<f4', vc * 8, 36).reshape(vc, 8), np.frombuffer(b, '<u2', ic, 36 + vc * 32).reshape(-1, 3)

def load_cgt(path):
    b = open(path, 'rb').read(); w, h, fmt, mips = struct.unpack_from('<4I', b, 4)
    a = np.frombuffer(b, '<u2', w * h, 20).reshape(h, w)
    if fmt == 0: r = ((a >> 11) & 31) * 255 // 31; g = ((a >> 5) & 63) * 255 // 63; bb = (a & 31) * 255 // 31
    else: r = ((a >> 12) & 15) * 17; g = ((a >> 8) & 15) * 17; bb = ((a >> 4) & 15) * 17
    return np.stack([r, g, bb], -1).astype(np.uint8)

meshcache, texcache = {}, {}
S = 300
sheet = Image.new('RGB', (S * len(poses), S * 2), (110, 155, 215))
for pi, p in enumerate(poses):
    spec = [(s.split(':')[0], float(s.split(':')[1])) for s in p.split('+')]
    world = pose_world(spec)
    # собираем треугольники в мировых координатах
    tris = []
    for part in parts:
        if part['mesh'] not in meshcache: meshcache[part['mesh']] = load_cgm(os.path.join(res, 'meshes', part['mesh'] + '.cgm'))
        if part['tex'] and part['tex'] not in texcache: texcache[part['tex']] = load_cgt(os.path.join(res, 'textures', part['tex'] + '.cgt'))
        v, idx = meshcache[part['mesh']]
        W = world[part['node']]
        pw = v[:, :3] @ W[:3, :3].T + W[:3, 3]
        nm = np.linalg.inv(W[:3, :3]).T
        nw = v[:, 3:6] @ nm.T; nw /= np.maximum(np.linalg.norm(nw, axis=1, keepdims=True), 1e-9)
        tex = texcache.get(part['tex'])
        sx, sy, ox, oy = part['uvst']
        uv = v[:, 6:8] * np.array([sx, sy]) + np.array([ox, oy])
        tris.append((pw, nw, uv, idx, tex, np.array(part['color']), part['flags'] & 1))
    allp = np.concatenate([t[0] for t in tris]); bmin, bmax = allp.min(0), allp.max(0)
    if pi == 0: print('габариты в позе %s: X[%.2f..%.2f] Y[%.2f..%.2f] Z[%.2f..%.2f]  высота %.2f' % (p, bmin[0], bmax[0], bmin[1], bmax[1], bmin[2], bmax[2], bmax[1] - bmin[1]))
    for row, yaw in enumerate((0.0, 90.0)):
        c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        R = np.array([[c, 0, s], [-0, 1, 0], [-s, 0, c]])
        cen = (bmin + bmax) / 2
        img = np.full((S, S, 3), (110, 155, 215), np.float32); zb = np.full((S, S), -1e9)
        scl = 0.85 * S / (bmax[1] - bmin[1])
        L = np.array([0.4, 0.8, 0.6]); L /= np.linalg.norm(L)
        for pw, nw, uv, idx, tex, col, flip in tris:
            q = (pw - cen) @ R.T; nq = nw @ R.T
            px = q[:, 0] * scl + S / 2; py = -q[:, 1] * scl + S / 2; z = q[:, 2]
            th, tw = (tex.shape[:2] if tex is not None else (1, 1))
            for a, b, cc in idx:
                if flip: b, cc = cc, b
                ar = (px[b]-px[a])*(py[cc]-py[a]) - (px[cc]-px[a])*(py[b]-py[a])
                if ar >= 0: continue        # CCW -> лицевая (y вниз)
                x0, x1 = int(max(min(px[[a,b,cc]]), 0)), int(min(max(px[[a,b,cc]]), S-1)); y0, y1 = int(max(min(py[[a,b,cc]]), 0)), int(min(max(py[[a,b,cc]]), S-1))
                if x1 < x0 or y1 < y0: continue
                X, Y = np.meshgrid(np.arange(x0, x1+1)+.5, np.arange(y0, y1+1)+.5)
                w0 = ((py[b]-py[cc])*(X-px[cc]) + (px[cc]-px[b])*(Y-py[cc])) / ((py[b]-py[cc])*(px[a]-px[cc]) + (px[cc]-px[b])*(py[a]-py[cc]) + 1e-12)
                w1 = ((py[cc]-py[a])*(X-px[cc]) + (px[a]-px[cc])*(Y-py[cc])) / ((py[b]-py[cc])*(px[a]-px[cc]) + (px[cc]-px[b])*(py[a]-py[cc]) + 1e-12)
                w2 = 1 - w0 - w1
                m = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
                if not m.any(): continue
                zz = w0*z[a] + w1*z[b] + w2*z[cc]
                sub = zb[y0:y1+1, x0:x1+1]; upd = m & (zz > sub)
                if not upd.any(): continue
                u = w0*uv[a,0] + w1*uv[b,0] + w2*uv[cc,0]; vv = w0*uv[a,1] + w1*uv[b,1] + w2*uv[cc,1]
                if tex is not None:
                    colr = tex[(np.clip(vv % 1, 0, .9999)*th).astype(int), (np.clip(u % 1, 0, .9999)*tw).astype(int)] / 255.0 * col
                else: colr = np.broadcast_to(col, u.shape + (3,))
                n_ = (w0[..., None]*nq[a] + w1[..., None]*nq[b] + w2[..., None]*nq[cc]); n_ = n_ / np.maximum(np.linalg.norm(n_, axis=2, keepdims=True), 1e-9)
                lit = 0.35 + 0.65 * np.clip(n_ @ L, 0, 1)
                sub[upd] = zz[upd]; img[y0:y1+1, x0:x1+1][upd] = np.clip(colr * lit[..., None] * 255, 0, 255)[upd]
        sheet.paste(Image.fromarray(img.astype(np.uint8)), (pi * S, row * S))
    ImageDraw.Draw(sheet).text((pi * S + 6, 4), p, fill=(255, 255, 255))
sheet.save(out)
print('сохранено', out)
