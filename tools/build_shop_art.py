#!/usr/bin/env python3
"""
Картинки для экрана Shop (Resources/shop/), всё рендерится из ресурсов проекта программным растеризатором:
  weapon_<id>.png / weapon_<id>_s.png  — иконка оружия сбоку (512x256 и 192x96), ствол вправо
  chicken_<id>.png                      — курица Rudy с этим оружием в руках (ракурс -50°, как в магазине оригинала)
  tab_guns/hats/shoes/eyes/beak.png     — иконки вкладок (128x128), coin.png, arrow_back.png

    build_shop_art.py <Resources> [<Resources>/shop]
"""
import os, sys, math, plistlib
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cgraster as g

res = sys.argv[1]; out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(res, 'shop')
os.makedirs(out, exist_ok=True)
A = g.Assets(res)
weapons = plistlib.load(open(os.path.join(res, 'weapons.plist'), 'rb'))
rig = g.Rig(os.path.join(res, 'characters', 'rudy.cgr'))


def rx180():
    m = np.eye(4); m[1, 1] = m[2, 2] = -1; return m
def ry180():
    m = np.eye(4); m[0, 0] = m[2, 2] = -1; return m

# Меши оружия в дампе лежат «вверх ногами» (прицел/магазин снизу), у AUG ствол смотрит в -X (поле orient в weapons.plist).
# FIX — поправка «сырая меш -> стойка (ствол +X, верх +Y)»; та же, что применяет WeaponController в руках.
FIX = {w['id']: {1: rx180(), 2: ry180()}.get(w.get('orient', 0), np.eye(4)) for w in weapons}     # orient — из weapons.plist
F_AK = FIX['AK47']

# ---------- иконки оружия ----------
for w in weapons:
    tris = g.make_tris(A, [(w['mesh'], w['tex'], w['color'], w['uvst'], FIX[w['id']], 0)])
    im, _ = g.render(tris, 512, 256, fit=0.92, ss=3)
    im.save(os.path.join(out, 'weapon_%s.png' % w['id'], ), optimize=True)
    im.resize((192, 96), Image.LANCZOS).save(os.path.join(out, 'weapon_%s_s.png' % w['id']), optimize=True)
    print('weapon', w['id'])

# ---------- курица с оружием ----------
POSE = [('Idle', 0.0), ('TopIdle', 0.0)]
world = rig.world(POSE)
ak = next(p for p in rig.parts if p['mesh'] == 'weapon_ak47')
ak_k = 0.62 / [w for w in weapons if w['id'] == 'AK47'][0]['extentX']          # метров на единицу меши у AK

def chicken_tris(wp):
    items = []
    for p in rig.parts:
        if p is ak:
            k = (wp['viewLength'] / wp['extentX']) / ak_k                        # относительно AK
            S = np.diag([k, k, k, 1.0])
            M = world[p['node']] @ np.linalg.inv(F_AK) @ FIX[wp['id']] @ S      # сырая меш -> стойка -> система узла AK
            items.append((wp['mesh'], wp['tex'], wp['color'], wp['uvst'], M, p['flags'] & 1))
        else:
            items.append((p['mesh'], p['tex'], p['color'], p['uvst'], world[p['node']], p['flags'] & 1))
    return g.make_tris(A, items)

CW, CH, YAW = 560, 560, -50.0
all_tris = {w['id']: chicken_tris(w) for w in weapons}
view = g.compute_view([t for v in all_tris.values() for t in v], CW * 3, CH * 3, yaw=YAW, fit=0.95)
imgs = {}
for w in weapons:
    imgs[w['id']], _ = g.render(all_tris[w['id']], CW, CH, yaw=YAW, ss=3, view=view)
    print('chicken', w['id'])
bb = None
for im in imgs.values():
    b = im.getbbox(); bb = b if bb is None else (min(bb[0], b[0]), min(bb[1], b[1]), max(bb[2], b[2]), max(bb[3], b[3]))
print('общий bbox курицы', bb)
for k, im in imgs.items(): im.crop(bb).save(os.path.join(out, 'chicken_%s.png' % k), optimize=True)

# ---------- иконки вкладок ----------
def part_icon(idxs, yaw, pitch, name, W=128):
    items = [(rig.parts[i]['mesh'], rig.parts[i]['tex'], rig.parts[i]['color'], rig.parts[i]['uvst'], world[rig.parts[i]['node']], rig.parts[i]['flags'] & 1) for i in idxs]
    im, _ = g.render(g.make_tris(A, items), W, W, yaw=yaw, pitch=pitch, fit=0.86, ss=4)
    im.save(os.path.join(out, name), optimize=True)

part_icon([10, 11, 12, 13, 14, 15, 16, 17], 35, 20, 'tab_shoes.png')      # ноги
Image.open(os.path.join(out, 'weapon_G35.png')).resize((128, 64), Image.LANCZOS).save(os.path.join(out, 'tab_guns.png'))

# шапка и монета рисуем сами (в дампе шапок нет)
S = 4
def canvas(n=128): return Image.new('RGBA', (n * S, n * S), (0, 0, 0, 0))
im = canvas(); d = ImageDraw.Draw(im)
d.pieslice([22*S, 32*S, 106*S, 116*S], 180, 360, fill=(36, 74, 160), outline=(18, 40, 100), width=2*S)      # околыш-купол
d.rectangle([22*S, 74*S, 106*S, 92*S], fill=(26, 56, 130), outline=(18, 40, 100), width=2*S)
d.ellipse([54*S, 56*S, 74*S, 76*S], fill=(236, 200, 70), outline=(150, 120, 20), width=S)                 # кокарда
d.chord([30*S, 82*S, 110*S, 112*S], 0, 180, fill=(14, 28, 70))                                            # козырёк
im.resize((128, 128), Image.LANCZOS).save(os.path.join(out, 'tab_hats.png'), optimize=True)

# глаза и клюв — рисованные (модель из дампа в иконке читается плохо)
im = canvas(); d = ImageDraw.Draw(im)
for cx in (38, 90):
    d.ellipse([(cx-19)*S, 46*S, (cx+19)*S, 84*S], fill=(255, 255, 255), outline=(60, 60, 50), width=2*S)
    d.ellipse([(cx-8)*S, 56*S, (cx+8)*S, 76*S], fill=(20, 24, 30))
im.resize((128, 128), Image.LANCZOS).save(os.path.join(out, 'tab_eyes.png'), optimize=True)

im = canvas(); d = ImageDraw.Draw(im)
d.polygon([(18*S, 56*S), (110*S, 56*S), (64*S, 22*S)], fill=(246, 168, 30), outline=(170, 100, 10))      # верхняя половина
d.polygon([(26*S, 60*S), (102*S, 60*S), (64*S, 100*S)], fill=(214, 124, 14), outline=(150, 80, 6))        # нижняя
im.resize((128, 128), Image.LANCZOS).save(os.path.join(out, 'tab_beak.png'), optimize=True)

im = canvas(96); d = ImageDraw.Draw(im)
d.ellipse([4*S, 4*S, 92*S, 92*S], fill=(214, 150, 10), outline=(150, 96, 0), width=3*S)
d.ellipse([16*S, 16*S, 80*S, 80*S], fill=(250, 200, 40), outline=(190, 130, 10), width=2*S)
d.rectangle([42*S, 28*S, 54*S, 68*S], fill=(214, 150, 10))
im.resize((96, 96), Image.LANCZOS).save(os.path.join(out, 'coin.png'), optimize=True)

im = canvas(64); d = ImageDraw.Draw(im)
d.polygon([(44*S, 8*S), (14*S, 32*S), (44*S, 56*S)], fill=(40, 60, 20))
im.resize((64, 64), Image.LANCZOS).save(os.path.join(out, 'arrow_back.png'), optimize=True)
print('готово ->', out)
