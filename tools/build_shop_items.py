#!/usr/bin/env python3
"""
Предметы для вкладок Hats / Shoes / Eyes / Beak магазина (Resources/shop, Resources/menu, Resources/items.plist).

Шапки, очки и ботинки — собственные низкополигональные модели из примитивов (см. ITEMS ниже). Каждый предмет рендерится
тем же программным растеризатором в той же камере, что спрайты курицы, но в виде прозрачного СЛОЯ с учётом перекрытия
курицей (в картинку попадает только предмет). В игре слой накладывается поверх спрайта курицы той же рамкой.
Цвет клюва — слой из частей клюва рига с перекрашенной текстурой (по одному слою на каждое оружие, чтобы ствол
оставался поверх клюва).

  shop/item_<кат>_<id>.png, _s.png    иконки предмета (512x256, 192x96)
  shop/layer_<кат>_<id>.png           слой на спрайт курицы магазина (514x408); клюв: layer_beak_<id>_<оружие>.png
  menu/layer_<кат>_<id>.png           слой на спрайт курицы главного меню (324x370)
  items.plist                         описание категорий и предметов

    build_shop_items.py <Resources> [hats|eyes|shoes|beak ...]
"""
import os, sys, math, plistlib
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cgraster as g

res = sys.argv[1]; only = set(sys.argv[2:])
shop = os.path.join(res, 'shop'); menu = os.path.join(res, 'menu')
A = g.Assets(res)
weapons = plistlib.load(open(os.path.join(res, 'weapons.plist'), 'rb'))
rig = g.Rig(os.path.join(res, 'characters', 'rudy.cgr'))
world = rig.world([('Idle', 0.0), ('TopIdle', 0.0)])

# ---------------- примитивы (мировые координаты рига: +Y вверх, лицо смотрит в +Z, глаза на x = +-0.15) ----------------
def mk(verts, faces, col):
    """Плоское затенение: каждая грань с собственной нормалью. faces — списки индексов (3+; веером)."""
    V = np.asarray(verts, float); P = []; N = []; idx = []
    for f in faces:
        for k in range(1, len(f) - 1):
            a, b, c = V[f[0]], V[f[k]], V[f[k + 1]]
            n = np.cross(b - a, c - a); ln = np.linalg.norm(n); n = n / ln if ln > 1e-12 else np.array([0, 1.0, 0])
            base = len(P); P += [a, b, c]; N += [n, n, n]; idx.append((base, base + 1, base + 2))
    return (np.array(P), np.array(N), np.zeros((len(P), 2)), np.array(idx, dtype=np.int64), None, np.array(col, float), 0)

def xf(t, M):
    pw, nw, uv, idx, tex, col, flip = t
    return (pw @ M[:3, :3].T + M[:3, 3], nw @ M[:3, :3].T, uv, idx, tex, col, flip)
def T(x, y, z): m = np.eye(4); m[:3, 3] = [x, y, z]; return m
def Rx(a): c, s = math.cos(math.radians(a)), math.sin(math.radians(a)); m = np.eye(4); m[1, 1] = c; m[1, 2] = -s; m[2, 1] = s; m[2, 2] = c; return m
def Ry(a): c, s = math.cos(math.radians(a)), math.sin(math.radians(a)); m = np.eye(4); m[0, 0] = c; m[0, 2] = s; m[2, 0] = -s; m[2, 2] = c; return m
def Rz(a): c, s = math.cos(math.radians(a)), math.sin(math.radians(a)); m = np.eye(4); m[0, 0] = c; m[0, 1] = -s; m[1, 0] = s; m[1, 1] = c; return m

def box(cx, cy, cz, sx, sy, sz, col, M=None):
    x, y, z = sx / 2, sy / 2, sz / 2
    v = [(-x, -y, -z), (x, -y, -z), (x, y, -z), (-x, y, -z), (-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z)]
    t = mk(v, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (3, 7, 6, 2), (0, 4, 7, 3), (1, 2, 6, 5)], col)
    return xf(t, (M if M is not None else np.eye(4)) @ np.eye(4) if M is None else M) if False else xf(xf(t, np.eye(4)), (T(cx, cy, cz) if M is None else T(cx, cy, cz) @ M))

def cyl(cx, y0, cz, r1, r2, h, col, n=12, M=None):
    """Усечённый конус/цилиндр вдоль Y: основание на y0 (радиус r1), верх на y0+h (радиус r2)."""
    v = []; 
    for i in range(n):
        a = 2 * math.pi * i / n; v.append((r1 * math.cos(a), 0, r1 * math.sin(a)))
    for i in range(n):
        a = 2 * math.pi * i / n; v.append((r2 * math.cos(a), h, r2 * math.sin(a)))
    f = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    for i in range(n): j = (i + 1) % n; f.append((i, j, n + j, n + i))
    t = mk(v, f, col)
    return xf(t, T(cx, y0, cz) @ (M if M is not None else np.eye(4)))

def sphere(cx, cy, cz, r, col, n=10, m=6, top_only=False, sy=1.0):
    lat0 = 0 if top_only else -math.pi / 2
    rows = []
    for j in range(m + 1):
        la = lat0 + (math.pi / 2 - lat0) * j / m
        rows.append([(r * math.cos(la) * math.cos(2 * math.pi * i / n), r * math.sin(la) * sy, r * math.cos(la) * math.sin(2 * math.pi * i / n)) for i in range(n)])
    v = [p for row in rows for p in row]; f = []
    for j in range(m):
        for i in range(n):
            k = (i + 1) % n; a, b, c, d = j * n + i, j * n + k, (j + 1) * n + k, (j + 1) * n + i
            f.append((a, d, c, b) if True else (a, b, c, d))
    if top_only: f.append(tuple(range(n - 1, -1, -1)))
    return xf(mk(v, f, col), T(cx, cy, cz))

def ring_z(cx, cy, cz, R, r, col, n=16, m=5):
    """Тор в плоскости XY (ось вдоль Z) — оправа круглых очков."""
    v = []
    for i in range(n):
        a = 2 * math.pi * i / n
        for j in range(m):
            b = 2 * math.pi * j / m
            rr = R + r * math.cos(b); v.append((rr * math.cos(a), rr * math.sin(a), r * math.sin(b)))
    f = []
    for i in range(n):
        for j in range(m):
            i2, j2 = (i + 1) % n, (j + 1) % m
            f.append((i * m + j, i2 * m + j, i2 * m + j2, i * m + j2))
    return xf(mk(v, f, col), T(cx, cy, cz))

def prism_z(poly, z0, z1, col, cx=0, cy=0, cz=0):
    """Выдавленный по Z многоугольник (звёздчатый относительно центра): очки-сердечки."""
    P = np.asarray(poly, float); c = P.mean(0); n = len(P)
    v = [(p[0], p[1], z0) for p in P] + [(p[0], p[1], z1) for p in P] + [(c[0], c[1], z0), (c[0], c[1], z1)]
    f = []
    for i in range(n): j = (i + 1) % n; f.append((2 * n, j, i)); f.append((2 * n + 1, n + i, n + j)); f.append((i, j, n + j, n + i))
    return xf(mk(v, f, col), T(cx, cy, cz))

def heart(size):
    t = np.linspace(0, 2 * math.pi, 28, endpoint=False)
    x = 16 * np.sin(t) ** 3; y = 13 * np.cos(t) - 5 * np.cos(2 * t) - 2 * np.cos(3 * t) - np.cos(4 * t)
    return np.stack([x, y], 1) * size / 34.0

def cone_ring(cx, y0, cz, R, n, r, h, col, nn=6):
    """n конусов (зубцы короны) по окружности радиуса R."""
    out = []
    for i in range(n):
        a = 2 * math.pi * i / n
        out.append(cyl(cx + R * math.cos(a), y0, cz + R * math.sin(a), r, 0.01, h, col, n=nn))
    return out

# ---------------- шапки: голова — шар радиуса ~0.57 с центром (0, 1.0, -0.30); гребень до y=1.94 ----------------
CZ = -0.30
def hat_cap():
    red, dark = (0.86, 0.14, 0.14), (0.62, 0.08, 0.08)
    return [sphere(0, 1.30, CZ, 0.70, red, n=12, m=5, top_only=True),
            xf(box(0, 0, 0, 0.52, 0.035, 0.44, dark), T(0, 1.355, 0.58) @ Rx(14)),
            sphere(0, 1.965, CZ, 0.05, dark, n=8, m=4)]
def hat_tophat():
    return [cyl(0, 1.42, CZ, 0.84, 0.76, 0.07, (0.08, 0.08, 0.1), n=16), cyl(0, 1.46, CZ, 0.47, 0.47, 0.66, (0.1, 0.1, 0.12), n=16),
            cyl(0, 1.47, CZ, 0.485, 0.485, 0.13, (0.78, 0.12, 0.12), n=16)]
def hat_cowboy():
    return [cyl(0, 1.43, CZ, 0.98, 0.76, 0.09, (0.62, 0.40, 0.18), n=16), cyl(0, 1.47, CZ, 0.48, 0.38, 0.52, (0.66, 0.43, 0.2), n=14),
            cyl(0, 1.48, CZ, 0.475, 0.455, 0.09, (0.26, 0.13, 0.06), n=14)]
def hat_party():
    segs = [(0.47, 0.35, 1.40, (0.9, 0.2, 0.25)), (0.35, 0.23, 1.64, (1.0, 0.85, 0.2)), (0.23, 0.12, 1.88, (0.25, 0.5, 0.95)), (0.12, 0.02, 2.12, (0.9, 0.2, 0.25))]
    return [cyl(0, y, CZ, r1, r2, 0.24, c, n=12) for r1, r2, y, c in segs] + [sphere(0, 2.39, CZ, 0.07, (1.0, 0.85, 0.2), n=8, m=4)]
def hat_crown():
    gold = (0.95, 0.76, 0.18)
    out = [cyl(0, 1.50, CZ, 0.40, 0.43, 0.22, gold, n=14)] + cone_ring(0, 1.72, CZ, 0.40, 5, 0.09, 0.20, gold, nn=6)
    for i in range(5):
        a = 2 * math.pi * (i + 0.5) / 5 + math.pi / 2; out.append(sphere(0.43 * math.cos(a), 1.61, CZ + 0.43 * math.sin(a), 0.035, (0.85, 0.1, 0.2), n=6, m=4))
    return out
def hat_helmet():
    olive, dark, yel = (0.36, 0.43, 0.22), (0.24, 0.3, 0.14), (0.95, 0.8, 0.2)
    return [sphere(0, 1.28, CZ, 0.72, olive, n=12, m=5, top_only=True), cyl(0, 1.25, CZ, 0.75, 0.75, 0.06, dark, n=14),
            box(0, 1.55, 0.328, 0.11, 0.11, 0.03, yel), xf(box(0, 0, 0, 0.11, 0.11, 0.03, yel), T(0, 1.55, 0.329) @ Rz(45))]
def hat_beanie():
    return [sphere(0, 1.30, CZ, 0.68, (0.2, 0.36, 0.82), n=12, m=5, top_only=True), cyl(0, 1.22, CZ, 0.715, 0.715, 0.15, (0.92, 0.92, 0.96), n=14),
            sphere(0, 1.93, CZ, 0.12, (0.95, 0.95, 1.0), n=8, m=5)]

# ---------------- очки: глаза в (+-0.15, 1.255), поверхность лица z ~ 0.19, линзы ставим на z = 0.285 ----------------
def head_arc(y, phi0, phi1, n, rr=0.60, col=(0.1, 0.1, 0.1), h=0.06, th=0.025):
    """Ремешок по поверхности головы на высоте y от угла phi0 до phi1 (градусы от +Z вокруг оси Y), по сегментам-коробкам."""
    out = []; rxz = math.sqrt(max(rr * rr - (y - 1.0) ** 2, 1e-6))
    pts = [(rxz * math.sin(math.radians(p)), CZ + rxz * math.cos(math.radians(p))) for p in np.linspace(phi0, phi1, n)]
    for (x0, z0), (x1, z1) in zip(pts[:-1], pts[1:]):
        L = math.hypot(x1 - x0, z1 - z0) + 0.01; ang = math.degrees(math.atan2(x1 - x0, z1 - z0))
        out.append(xf(box(0, 0, 0, th, h, L, col), T((x0 + x1) / 2, y, (z0 + z1) / 2) @ Ry(ang)))
    return out
def eyes_sunglasses():
    blk, frame = (0.06, 0.06, 0.08), (0.02, 0.02, 0.03)
    out = [box(s * 0.15, 1.26, 0.296, 0.22, 0.15, 0.035, blk) for s in (1, -1)] + [box(s * 0.15, 1.26, 0.283, 0.25, 0.18, 0.03, frame) for s in (1, -1)]
    out += [box(0, 1.30, 0.3, 0.10, 0.03, 0.03, frame)] + head_arc(1.28, 26, 100, 6, col=frame, h=0.03) + head_arc(1.28, -26, -100, 6, col=frame, h=0.03)
    return out
def eyes_round():
    gold = (0.9, 0.74, 0.18); out = [ring_z(s * 0.15, 1.255, 0.30, 0.115, 0.02, gold) for s in (1, -1)]
    out += [box(0, 1.285, 0.30, 0.09, 0.025, 0.025, gold)] + head_arc(1.27, 28, 100, 6, col=gold, h=0.025, th=0.02) + head_arc(1.27, -28, -100, 6, col=gold, h=0.025, th=0.02)
    return out
def eyes_heart():
    pink = (0.95, 0.25, 0.45); out = [prism_z(heart(0.24), 0.28, 0.32, pink, s * 0.15, 1.262, 0) for s in (1, -1)]
    out += [box(0, 1.29, 0.30, 0.07, 0.025, 0.025, pink)] + head_arc(1.27, 30, 100, 6, col=pink, h=0.025, th=0.02) + head_arc(1.27, -30, -100, 6, col=pink, h=0.025, th=0.02)
    return out
def eyes_goggles():
    rim, lens, band = (0.25, 0.27, 0.3), (1.0, 0.58, 0.1), (0.12, 0.13, 0.16)
    out = [cyl(0, 0, 0, 0.14, 0.14, 0.07, rim, n=14, M=Rx(90)) for _ in range(0)]
    for s in (1, -1):
        out.append(xf(cyl(0, 0, 0, 0.14, 0.14, 0.07, rim, n=14), T(s * 0.15, 1.255, 0.26) @ Rx(90)))
        out.append(xf(cyl(0, 0, 0, 0.115, 0.115, 0.02, lens, n=14), T(s * 0.15, 1.255, 0.33) @ Rx(90)))
    out += [box(0, 1.255, 0.285, 0.06, 0.05, 0.05, rim)] + head_arc(1.255, 32, 105, 7, col=band, h=0.09, th=0.03) + head_arc(1.255, -32, -105, 7, col=band, h=0.09, th=0.03)
    return out
def eyes_patch():
    blk = (0.05, 0.05, 0.06); out = [xf(cyl(0, 0, 0, 0.14, 0.14, 0.035, blk, n=14), T(0.15, 1.255, 0.285) @ Rx(90))]
    pts = []
    for t in np.linspace(0, 1, 9):                                    # ремешок по лбу на другую сторону
        x = 0.15 + (-0.55 - 0.15) * t; y = 1.30 + (1.48 - 1.30) * t
        z = CZ + math.sqrt(max(0.60 ** 2 - x * x - (y - 1.0) ** 2, 1e-4)); pts.append((x, y, z))
    for p0, p1 in zip(pts[:-1], pts[1:]):
        d = np.array(p1) - np.array(p0); L = np.linalg.norm(d) + 0.01
        yaw = math.degrees(math.atan2(d[0], d[2])); pitch = -math.degrees(math.asin(d[1] / L))
        out.append(xf(box(0, 0, 0, 0.025, 0.05, L, blk), T(*((np.array(p0) + np.array(p1)) / 2)) @ Ry(yaw) @ Rx(pitch)))
    return out

# ---------------- ботинки: накрывают ступни (x: левая -0.33..0.0, правая 0.10..0.32; z -0.40..-0.13; ноги до y=0.22) ----------------
def shoe_pair(body, sole, toe, h=0.17, boot=0.0, cuff=None):
    out = []
    for cx in (-0.165, 0.205):
        L, Wd, z0 = 0.34, 0.33, -0.255
        out.append(box(cx, 0.03, z0, Wd, 0.06, L, sole))                                           # подошва
        out.append(box(cx, 0.03 + h / 2 + 0.01, z0 - 0.02, Wd - 0.03, h, L - 0.05, body))           # корпус
        out.append(box(cx, 0.075, z0 + L / 2 - 0.03, Wd - 0.02, 0.09, 0.09, toe))                    # носок
        if boot > 0:
            out.append(box(cx, 0.03 + h + boot / 2, z0 - 0.07, Wd - 0.10, boot, 0.20, body))          # голенище
            if cuff: out.append(box(cx, 0.03 + h + boot, z0 - 0.07, Wd - 0.07, 0.04, 0.23, cuff))
    return out
def shoes_sneakers_red(): return shoe_pair((0.86, 0.12, 0.14), (0.95, 0.95, 0.95), (0.95, 0.95, 0.95))
def shoes_sneakers_blue(): return shoe_pair((0.18, 0.4, 0.9), (0.95, 0.95, 0.95), (0.95, 0.95, 0.95))
def shoes_boots_brown(): return shoe_pair((0.45, 0.27, 0.12), (0.2, 0.12, 0.06), (0.35, 0.2, 0.09), h=0.16, boot=0.12, cuff=(0.3, 0.18, 0.08))
def shoes_boots_black(): return shoe_pair((0.1, 0.1, 0.12), (0.03, 0.03, 0.04), (0.18, 0.18, 0.2), h=0.16, boot=0.12, cuff=(0.7, 0.7, 0.75))
def shoes_gold(): return shoe_pair((0.95, 0.76, 0.2), (0.65, 0.5, 0.1), (1.0, 0.88, 0.4))

ITEMS = {
    'hats':  [('cap', 'Cap', hat_cap), ('tophat', 'Top hat', hat_tophat), ('cowboy', 'Cowboy', hat_cowboy), ('party', 'Party', hat_party),
              ('crown', 'Crown', hat_crown), ('helmet', 'Helmet', hat_helmet), ('beanie', 'Beanie', hat_beanie)],
    'eyes':  [('sunglasses', 'Sunglasses', eyes_sunglasses), ('round', 'Round', eyes_round), ('heart', 'Heart', eyes_heart),
              ('goggles', 'Goggles', eyes_goggles), ('patch', 'Eye patch', eyes_patch)],
    'shoes': [('sneakers_red', 'Red sneakers', shoes_sneakers_red), ('sneakers_blue', 'Blue sneakers', shoes_sneakers_blue),
              ('boots_brown', 'Brown boots', shoes_boots_brown), ('boots_black', 'Black boots', shoes_boots_black), ('gold', 'Golden shoes', shoes_gold)],
    'beak':  [('gold', 'Gold', (1.0, 0.78, 0.16)), ('red', 'Red', (0.9, 0.15, 0.12)), ('blue', 'Blue', (0.22, 0.48, 0.96)),
              ('green', 'Green', (0.2, 0.74, 0.26)), ('black', 'Black', (0.13, 0.13, 0.15))],
}
TITLES = {'hats': 'Hats', 'shoes': 'Shoes', 'eyes': 'Eyes', 'beak': 'Beak'}
ORDER = ['hats', 'shoes', 'eyes', 'beak']
NONE_NAME = {'hats': 'No hat', 'shoes': 'No shoes', 'eyes': 'No glasses', 'beak': 'Default'}

# ---------------- камеры, совпадающие со спрайтами ----------------
FIX = {w['id']: {1: np.diag([1.0, -1, -1, 1]), 2: np.diag([-1.0, 1, -1, 1])}.get(w.get('orient', 0), np.eye(4)) for w in weapons}
F_AK = FIX['AK47']
ak = next(p for p in rig.parts if p['mesh'] == 'weapon_ak47')
ak_k = 0.62 / [w for w in weapons if w['id'] == 'AK47'][0]['extentX']

def chicken_tris(wp, skip=(), beak_tint=None):
    items = []
    for i, p in enumerate(rig.parts):
        if i in skip: continue
        if p is ak:
            k = (wp['viewLength'] / wp['extentX']) / ak_k
            items.append((wp['mesh'], wp['tex'], wp['color'], wp['uvst'], world[p['node']] @ np.linalg.inv(F_AK) @ FIX[wp['id']] @ np.diag([k, k, k, 1.0]), p['flags'] & 1))
        else:
            items.append((p['mesh'], p['tex'], p['color'], p['uvst'], world[p['node']], p['flags'] & 1))
    return g.make_tris(A, items)

SHOP_W, SHOP_H, SHOP_YAW, SS = 560, 560, -50.0, 3
TOP = 130                                           # слои выше рамки спрайта на TOP пикселей (шапки); в ObjC: kLayerTop
SHOP_CROP = (0, 76, 514, 484 + TOP)                  # bbox спрайтов chicken_*.png (tools/build_shop_art.py) + запас сверху
by_id = {w['id']: w for w in weapons}
shop_view = g.compute_view([t for w in weapons for t in chicken_tris(w)], SHOP_W * SS, SHOP_H * SS, yaw=SHOP_YAW, fit=0.95)
# камера меню — как в tools/build_menu_art.py (ракурс 50°, спрайт обрезан по bbox)
MENU_N, MENU_YAW, MENU_CROP = 512, 50.0, (73, 71, 397, 441 + TOP)
_ak_tris = chicken_tris(by_id['AK47'])
_pts = np.concatenate([t[0] for t in _ak_tris]); _mn, _mx = _pts.min(0), _pts.max(0)
menu_view = ((_mn + _mx) / 2, 0.92 * MENU_N * SS / max(_mx[1] - _mn[1], _mx[0] - _mn[0], _mx[2] - _mn[2]))

def save_crop(im, path, crop):
    im.crop(crop).save(path, optimize=True)

def icon_pair(tris, key, name):
    im, _ = g.render(tris, 512, 256, yaw=-28, pitch=14, fit=0.82, ss=3, cull=False, amb=0.5)
    im.save(os.path.join(shop, 'item_%s_%s.png' % (key, name)), optimize=True)
    im.resize((192, 96), Image.LANCZOS).save(os.path.join(shop, 'item_%s_%s_s.png' % (key, name)), optimize=True)

def none_icon(key):
    S4 = 4; im = Image.new('RGBA', (512 * S4 // 2, 256 * S4 // 2), (0, 0, 0, 0)); d = ImageDraw.Draw(im); cx, cy, r = 256 * S4 // 2 * 1.0, 128 * S4 // 2 * 1.0, 80 * S4 / 2 * 1.0
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(30, 30, 30, 230), width=8 * S4 // 2); d.line([cx - r * .7, cy + r * .7, cx + r * .7, cy - r * .7], fill=(30, 30, 30, 230), width=8 * S4 // 2)
    big = im.resize((512, 256), Image.LANCZOS); big.save(os.path.join(shop, 'item_%s_none.png' % key), optimize=True)
    big.resize((192, 96), Image.LANCZOS).save(os.path.join(shop, 'item_%s_none_s.png' % key), optimize=True)

def beak_icon(col, name):
    S4 = 4; im = Image.new('RGBA', (512 * S4 // 2, 256 * S4 // 2), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    c = tuple(int(v * 255) for v in col); dk = tuple(int(v * 200) for v in col); cx, cy = 256 * S4 // 2, 128 * S4 // 2; s_ = S4 / 2
    d.polygon([(cx - 90 * s_, cy - 10 * s_), (cx + 90 * s_, cy + 8 * s_), (cx - 70 * s_, cy - 80 * s_)], fill=c, outline=(40, 40, 40, 255))
    d.polygon([(cx - 90 * s_, cy - 6 * s_), (cx + 90 * s_, cy + 8 * s_), (cx - 70 * s_, cy + 70 * s_)], fill=dk, outline=(40, 40, 40, 255))
    big = im.resize((512, 256), Image.LANCZOS); big.save(os.path.join(shop, 'item_beak_%s.png' % name), optimize=True)
    big.resize((192, 96), Image.LANCZOS).save(os.path.join(shop, 'item_beak_%s_s.png' % name), optimize=True)

def gray_tex(t):
    """Текстура клюва в градациях яркости (форма и тени сохраняются, цвет потом задаёт множитель)."""
    gray = t.astype(np.float32).mean(2, keepdims=True)
    return np.repeat(gray, 3, axis=2).astype(np.uint8)

def beak_layer(wp, col, view, W, H, yaw, ss=SS):
    tint = np.array(col) * 1.9
    items = []
    for i in (0, 1):
        p = rig.parts[i]; v, idx = A.mesh(p['mesh']); Wm = world[p['node']]
        t = g.make_tris(A, [(p['mesh'], p['tex'], p['color'], p['uvst'], Wm, p['flags'] & 1)])[0]
        pw, nw, uv, ix, tex, c_, fl = t
        items.append((pw, nw, uv, ix, gray_tex(tex) if tex is not None else None, tint, fl))
    return g.render_layer(items, chicken_tris(wp, skip=(0, 1)), W, H, yaw=yaw, ss=ss, view=view, extra_top=TOP)

if __name__ == '__main__':
    os.makedirs(shop, exist_ok=True)
    cats = [c for c in ORDER if not only or c in only]
    ak_occ = chicken_tris(by_id['AK47'])
    for key in cats:
        none_icon(key)
        for item in ITEMS[key]:
            name = item[0]
            if os.environ.get('ITEM_ONLY') and name not in os.environ['ITEM_ONLY'].split(','): continue      # ITEM_ONLY=blue,green — пересобрать только эти предметы
            if key == 'beak':
                col = item[2]; beak_icon(col, name)
                for wp in weapons:
                    im = beak_layer(wp, col, shop_view, SHOP_W, SHOP_H, SHOP_YAW)
                    save_crop(im, os.path.join(shop, 'layer_beak_%s_%s.png' % (name, wp['id'])), SHOP_CROP)
                im = beak_layer(by_id['AK47'], col, menu_view, MENU_N, MENU_N, MENU_YAW)
                save_crop(im, os.path.join(menu, 'layer_beak_%s.png' % name), MENU_CROP)
                print(key, name, flush=True); continue
            tris = item[2]()
            icon_pair(tris, key, name)
            im = g.render_layer(tris, ak_occ, SHOP_W, SHOP_H, yaw=SHOP_YAW, ss=SS, view=shop_view, extra_top=TOP)
            save_crop(im, os.path.join(shop, 'layer_%s_%s.png' % (key, name)), SHOP_CROP)
            im = g.render_layer(tris, _ak_tris, MENU_N, MENU_N, yaw=MENU_YAW, ss=SS, view=menu_view, extra_top=TOP)
            save_crop(im, os.path.join(menu, 'layer_%s_%s.png' % (key, name)), MENU_CROP)
            print(key, name, flush=True)
    cats_out = []
    for key in ORDER:
        its = [{'id': 'none', 'name': NONE_NAME[key]}] + [{'id': it[0], 'name': it[1]} for it in ITEMS[key]]
        cats_out.append({'key': key, 'title': TITLES[key], 'items': its})
    plistlib.dump(cats_out, open(os.path.join(res, 'items.plist'), 'wb'), fmt=plistlib.FMT_XML)
    print('items.plist записан')
