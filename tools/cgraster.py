"""
Общий программный растеризатор для инструментов превью (без GPU): загрузка .cgr/.cgm/.cgt, поза, рендер в RGBA.
Используется tools/build_shop_art.py. Формулы те же, что в preview_character.py / build_menu_art.py.
"""
import struct, os, math
import numpy as np
from PIL import Image


def load_cgm(path):
    b = open(path, 'rb').read(); vc, ic = struct.unpack_from('<II', b, 4)
    return np.frombuffer(b, '<f4', vc * 8, 36).reshape(vc, 8), np.frombuffer(b, '<u2', ic, 36 + vc * 32).reshape(-1, 3)


def load_cgt(path):
    b = open(path, 'rb').read(); w, h, fmt, mips = struct.unpack_from('<4I', b, 4)
    a = np.frombuffer(b, '<u2', w * h, 20).reshape(h, w)
    if fmt == 0: r = ((a >> 11) & 31) * 255 // 31; g = ((a >> 5) & 63) * 255 // 63; bb = (a & 31) * 255 // 31
    else: r = ((a >> 12) & 15) * 17; g = ((a >> 8) & 15) * 17; bb = ((a >> 4) & 15) * 17
    return np.stack([r, g, bb], -1).astype(np.uint8)


class Assets:
    def __init__(self, res):
        self.res = res; self.meshes = {}; self.texs = {}

    def mesh(self, name):
        if name not in self.meshes: self.meshes[name] = load_cgm(os.path.join(self.res, 'meshes', name + '.cgm'))
        return self.meshes[name]

    def tex(self, name):
        if not name: return None
        if name not in self.texs: self.texs[name] = load_cgt(os.path.join(self.res, 'textures', name + '.cgt'))
        return self.texs[name]


def qmat(q):
    x, y, z, w = q / np.linalg.norm(q)
    return np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                     [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                     [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])


class Rig:
    def __init__(self, path):
        d = open(path, 'rb').read(); assert d[:4] == b'CGR1'
        nn, npart, nclip = struct.unpack_from('<3I', d, 4); off = 16
        self.nodes = []; self.parts = []; self.clips = {}
        for i in range(nn):
            par = struct.unpack_from('<i', d, off)[0]
            pos = struct.unpack_from('<3f', d, off + 4); q = struct.unpack_from('<4f', d, off + 16); sc = struct.unpack_from('<3f', d, off + 32)
            name = d[off + 44:off + 64].split(b'\0')[0].decode()
            self.nodes.append(dict(parent=par, pos=np.array(pos), quat=np.array(q), scale=np.array(sc), name=name)); off += 64
        for i in range(npart):
            node, flags = struct.unpack_from('<2I', d, off)
            mesh = d[off + 8:off + 56].split(b'\0')[0].decode(); tex = d[off + 56:off + 104].split(b'\0')[0].decode()
            color = struct.unpack_from('<3f', d, off + 104); uvst = struct.unpack_from('<4f', d, off + 116)
            self.parts.append(dict(node=node, flags=flags, mesh=mesh, tex=tex, color=color, uvst=uvst)); off += 132
        for i in range(nclip):
            name = d[off:off + 24].split(b'\0')[0].decode()
            dur, loop, frames, tracks = struct.unpack_from('<fIII', d, off + 24); off += 40
            tr = []
            for t in range(tracks):
                node = struct.unpack_from('<I', d, off)[0]; off += 4
                data = np.frombuffer(d, '<f4', frames * 7, off).reshape(frames, 7); off += frames * 28
                tr.append((node, data))
            self.clips[name] = dict(dur=dur, loop=loop, frames=frames, tracks=tr)
        assert off == len(d)

    def world(self, spec):
        nodes = self.nodes
        lp = [n['pos'].copy() for n in nodes]; lq = [n['quat'].copy() for n in nodes]
        for name, t in spec:
            c = self.clips[name]; f = t * 30.0; f0 = int(math.floor(f)); fr = f - f0
            for node, data in c['tracks']:
                if c['loop']: a, b = data[f0 % c['frames']], data[(f0 + 1) % c['frames']]
                else: a, b = data[min(f0, c['frames'] - 1)], data[min(f0 + 1, c['frames'] - 1)]
                lp[node] = a[:3] * (1 - fr) + b[:3] * fr
                qa, qb = a[3:], b[3:]
                if np.dot(qa, qb) < 0: qb = -qb
                q = qa * (1 - fr) + qb * fr; lq[node] = q / np.linalg.norm(q)
        world = [None] * len(nodes)
        for i, n in enumerate(nodes):
            L = np.eye(4); L[:3, :3] = qmat(lq[i]) @ np.diag(n['scale']); L[:3, 3] = lp[i]
            world[i] = (world[n['parent']] @ L) if n['parent'] >= 0 else L
        return world


def make_tris(assets, items):
    """items: список (mesh, tex, color, uvst, world4x4, flip)"""
    tris = []
    for mesh, tex, color, uvst, W, flip in items:
        v, idx = assets.mesh(mesh)
        pw = v[:, :3] @ W[:3, :3].T + W[:3, 3]
        nm = np.linalg.inv(W[:3, :3]).T
        nw = v[:, 3:6] @ nm.T; nw /= np.maximum(np.linalg.norm(nw, axis=1, keepdims=True), 1e-9)
        sx, sy, ox, oy = uvst
        uv = v[:, 6:8] * np.array([sx, sy]) + np.array([ox, oy])
        tris.append((pw, nw, uv, idx, assets.tex(tex), np.array(color), flip))
    return tris


def compute_view(tris, w_, h_, yaw=0.0, pitch=0.0, fit=0.9):
    """(центр, масштаб), чтобы все tris влезли в кадр w_ x h_ (в пикселях рендера, т.е. уже с суперсэмплингом)."""
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    R = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]]) @ np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    allq = np.concatenate([(t[0]) @ R.T for t in tris])
    mn, mx = allq.min(0), allq.max(0)
    return ((mn + mx) / 2, fit * min(w_ / max(mx[0] - mn[0], 1e-6), h_ / max(mx[1] - mn[1], 1e-6)))


def render(tris, W, H, yaw=0.0, pitch=0.0, fit=0.9, ss=2, view=None, light=(0.35, 0.75, 0.55), amb=0.45, cull=True, bg=None):
    """RGBA-картинка W x H. view = (центр, масштаб) из прошлого вызова, чтобы кадры совпадали. Возвращает (img, view)."""
    w_, h_ = W * ss, H * ss
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    Ry = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]]); Rx = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
    R = Rx @ Ry
    if view is None: view = compute_view(tris, W * ss, H * ss, yaw, pitch, fit)
    cen, scl = view
    img = np.zeros((h_, w_, 3), np.float32); zb = np.full((h_, w_), -1e9)
    L = np.array(light, float); L /= np.linalg.norm(L)
    for pw, nw, uv, idx, tex, col, flip in tris:
        q = (pw - cen) @ R.T; nq = nw @ R.T
        px = q[:, 0] * scl + w_ / 2; py = -q[:, 1] * scl + h_ / 2; z = q[:, 2]
        th, tw = (tex.shape[:2] if tex is not None else (1, 1))
        for a, b, cc in idx:
            if flip: b, cc = cc, b
            ar = (px[b]-px[a])*(py[cc]-py[a]) - (px[cc]-px[a])*(py[b]-py[a])
            if cull and ar >= 0: continue
            if not cull and abs(ar) < 1e-9: continue
            x0, x1 = int(max(min(px[[a,b,cc]]), 0)), int(min(max(px[[a,b,cc]]), w_-1)); y0, y1 = int(max(min(py[[a,b,cc]]), 0)), int(min(max(py[[a,b,cc]]), h_-1))
            if x1 < x0 or y1 < y0: continue
            X, Y = np.meshgrid(np.arange(x0, x1+1)+.5, np.arange(y0, y1+1)+.5)
            den = ((py[b]-py[cc])*(px[a]-px[cc]) + (px[cc]-px[b])*(py[a]-py[cc]) + 1e-12)
            w0 = ((py[b]-py[cc])*(X-px[cc]) + (px[cc]-px[b])*(Y-py[cc])) / den
            w1 = ((py[cc]-py[a])*(X-px[cc]) + (px[a]-px[cc])*(Y-py[cc])) / den
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
            lit = amb + (1 - amb) * (np.clip(n_ @ L, 0, 1) if cull else np.abs(n_ @ L))
            sub[upd] = zz[upd]; img[y0:y1+1, x0:x1+1][upd] = np.clip(colr * lit[..., None] * 255, 0, 255)[upd]
    cov = (zb > -1e8).astype(np.float32)
    pm = (img * cov[..., None]).reshape(H, ss, W, ss, 3).mean((1, 3)); a = cov.reshape(H, ss, W, ss).mean((1, 3))
    rgb = np.where(a[..., None] > 0, pm / np.maximum(a[..., None], 1e-6), 0)
    return Image.fromarray(np.dstack([np.clip(rgb, 0, 255), a * 255]).astype(np.uint8), 'RGBA'), view


def render_layer(items, occluders, W, H, yaw=0.0, pitch=0.0, ss=3, view=None, light=(0.35, 0.75, 0.55), amb=0.5, extra_top=0):
    """Слой для наложения: рисует только items, но с учётом перекрытия геометрией occluders (в картинку они не попадают,
    только в z-буфер). Двусторонний рендер. Возвращает RGBA W x (H + extra_top); альфа = доля покрытия пикселя предметом.
    extra_top — лишние пиксели сверху (высокие шапки выходят за рамку спрайта): картинка расширяется вверх, а пиксели
    исходной области (W x H, камера view) остаются на тех же местах, сдвинутые вниз на extra_top."""
    H0 = H; H = H + extra_top
    w_, h_ = W * ss, H * ss
    top_shift = extra_top * ss / 2.0
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    R = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]]) @ np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    if view is None: view = compute_view(items, w_, h_, yaw, pitch, 0.9)
    cen, scl = view
    img = np.zeros((h_, w_, 3), np.float32); zb = np.full((h_, w_), -1e9); written = np.zeros((h_, w_), bool)
    L = np.array(light, float); L /= np.linalg.norm(L)

    def raster(tris, depth_only):
        for pw, nw, uv, idx, tex, col, flip in tris:
            q = (pw - cen) @ R.T; nq = nw @ R.T
            px = q[:, 0] * scl + w_ / 2; py = -q[:, 1] * scl + h_ / 2 + top_shift; z = q[:, 2]
            th, tw = (tex.shape[:2] if tex is not None else (1, 1))
            for a, b, cc in idx:
                ar = (px[b]-px[a])*(py[cc]-py[a]) - (px[cc]-px[a])*(py[b]-py[a])
                if abs(ar) < 1e-9: continue
                x0, x1 = int(max(min(px[[a,b,cc]]), 0)), int(min(max(px[[a,b,cc]]), w_-1)); y0, y1 = int(max(min(py[[a,b,cc]]), 0)), int(min(max(py[[a,b,cc]]), h_-1))
                if x1 < x0 or y1 < y0: continue
                X, Y = np.meshgrid(np.arange(x0, x1+1)+.5, np.arange(y0, y1+1)+.5)
                den = ((py[b]-py[cc])*(px[a]-px[cc]) + (px[cc]-px[b])*(py[a]-py[cc]) + 1e-12)
                w0 = ((py[b]-py[cc])*(X-px[cc]) + (px[cc]-px[b])*(Y-py[cc])) / den
                w1 = ((py[cc]-py[a])*(X-px[cc]) + (px[a]-px[cc])*(Y-py[cc])) / den
                w2 = 1 - w0 - w1
                m = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
                if not m.any(): continue
                zz = w0*z[a] + w1*z[b] + w2*z[cc]
                sub = zb[y0:y1+1, x0:x1+1]; upd = m & (zz > sub)
                if not upd.any(): continue
                sub[upd] = zz[upd]
                if depth_only:
                    written[y0:y1+1, x0:x1+1][upd] = False        # предмет, закрытый позже, не виден
                    continue
                written[y0:y1+1, x0:x1+1][upd] = True
                n_ = (w0[..., None]*nq[a] + w1[..., None]*nq[b] + w2[..., None]*nq[cc]); n_ = n_ / np.maximum(np.linalg.norm(n_, axis=2, keepdims=True), 1e-9)
                lit = amb + (1 - amb) * np.abs(n_ @ L)
                if tex is not None:
                    u = w0*uv[a,0] + w1*uv[b,0] + w2*uv[cc,0]; vv = w0*uv[a,1] + w1*uv[b,1] + w2*uv[cc,1]
                    colr = tex[(np.clip(vv % 1, 0, .9999)*th).astype(int), (np.clip(u % 1, 0, .9999)*tw).astype(int)] / 255.0 * col
                else: colr = np.broadcast_to(col, upd.shape + (3,)) * 255.0
                img[y0:y1+1, x0:x1+1][upd] = np.clip(colr * lit[..., None], 0, 255)[upd]

    raster(occluders, True)
    raster(items, False)
    cov = written.astype(np.float32)
    pm = (img * cov[..., None]).reshape(H, ss, W, ss, 3).mean((1, 3)); a = cov.reshape(H, ss, W, ss).mean((1, 3))
    rgb = np.where(a[..., None] > 0, pm / np.maximum(a[..., None], 1e-6), 0)
    return Image.fromarray(np.dstack([np.clip(rgb, 0, 255), a * 255]).astype(np.uint8), 'RGBA')
