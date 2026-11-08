#!/usr/bin/env python3
"""
Макет экрана Shop (PIL) с теми же координатами, что в src/ShopView.m. Это НЕ UIKit: проверка пропорций.

    preview_shop.py <Resources> <out.png> [ширина=1000] [высота=590] [индекс_оружия=3] [вкладка=0]
"""
import sys, os, plistlib
import numpy as np
from PIL import Image, ImageDraw, ImageFont

res, out = sys.argv[1], sys.argv[2]
W = int(sys.argv[3]) if len(sys.argv) > 3 else 1000
H = int(sys.argv[4]) if len(sys.argv) > 4 else 590
sel = int(sys.argv[5]) if len(sys.argv) > 5 else 3
tab = int(sys.argv[6]) if len(sys.argv) > 6 else 0
K = 2; w, h = W * K, H * K
DW, DH = 1000.0, 590.0
s = min(W / DW, H / DH); ox = (W - DW * s) / 2
extra = max(0.0, H / s - DH); shift = extra * 0.55; km = 1 + min(0.25, extra / DH * 0.45)
weapons = plistlib.load(open(os.path.join(res, 'weapons.plist'), 'rb'))
wd = weapons[sel]

def nik(sz): return ImageFont.truetype(os.path.join(res, '07nikumaru.ttf'), int(round(sz * K)))
def sans(sz): return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', int(round(sz * K)))
def R(ax, ay, x, y, dw, dh):
    X = (0 if ax == 0 else (ox if ax == 1 else W - DW * s)) + x * s; Y = (y + (0 if ay == 0 else shift)) * s
    return [X * K, Y * K, (X + dw * s) * K, (Y + dh * s) * K]
def shop(n): return Image.open(os.path.join(res, 'shop', n)).convert('RGBA')

yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
dx, dy = 0.3 * w, h
t = np.clip(((xx - 0.3 * w) * dx + yy * dy) / (dx * dx + dy * dy), 0, 1)[..., None]
img = Image.fromarray((np.array([.69, .85, .02]) * 255 * (1 - t) + np.array([.40, .72, .03]) * 255 * t).astype(np.uint8)).convert('RGBA')

def paste(im, box, fit=True):
    x0, y0, x1, y1 = [int(v) for v in box]
    im = im.resize((max(1, x1 - x0), max(1, y1 - y0)), Image.LANCZOS)
    img.alpha_composite(im, (x0, y0))
def paste_fit(im, box):   # aspect-fit
    x0, y0, x1, y1 = box; bw, bh = x1 - x0, y1 - y0
    k = min(bw / im.width, bh / im.height); nw, nh = int(im.width * k), int(im.height * k)
    img.alpha_composite(im.resize((nw, nh), Image.LANCZOS), (int(x0 + (bw - nw) / 2), int(y0 + (bh - nh) / 2)))

PANEL = (217, 237, 173, 255); BORDER = (181, 212, 117, 255); TEXT = (36, 43, 20, 255)
bw = max(1, int(2 * s * K))
ov = Image.new('RGBA', (w, h), (0, 0, 0, 0)); od = ImageDraw.Draw(ov)
def box(b, fill, outline=None, r=5):
    od.rounded_rectangle(b, radius=r * s * K, fill=fill, outline=outline, width=bw if outline else 0)
def text_c(b, txt, f, col, off=0):
    od.multiline_text(((b[0] + b[2]) / 2 + off * s * K, (b[1] + b[3]) / 2), txt, font=f, fill=col, anchor='mm', align='center', spacing=2)

# шапка
b = R(0, 0, 9, 12, 149, 61); box(b, PANEL, BORDER); text_c(b, 'Back', sans(max(26 * s, 11)), TEXT, 18)
b = R(2, 0, 555, 12, 187, 61); box(b, PANEL, BORDER); text_c(b, 'Free\ncoins', sans(max(23 * s, 10)), TEXT, 25)
b = R(2, 0, 760, 12, 195, 61); box(b, PANEL, BORDER)
od.text((b[0] + 68 * s * K, (b[1] + b[3]) / 2), '0', font=sans(max(26 * s, 11)), fill=TEXT, anchor='mm')
img.alpha_composite(ov)

arrow = shop('arrow_back.png'); coin = shop('coin.png')
bb = R(0, 0, 9, 12, 149, 61); paste(arrow, [bb[0] + 20 * s * K, bb[1] + 13.5 * s * K, bb[0] + 50 * s * K, bb[1] + 47.5 * s * K])
bb = R(2, 0, 555, 12, 187, 61); paste(coin, [bb[0] + 14 * s * K, bb[1] + 7.5 * s * K, bb[0] + 60 * s * K, bb[1] + 53.5 * s * K])
bb = R(2, 0, 760, 12, 195, 61); paste(coin, [bb[0] + 135 * s * K, bb[1] + 7.5 * s * K, bb[0] + 181 * s * K, bb[1] + 53.5 * s * K])

# тень + курица + оружие
sh = np.clip(1 - np.hypot(*(np.mgrid[0:128, 0:128] - 64)) / 64, 0, 1) * .5
shim = Image.fromarray(np.dstack([np.full((128, 128), 25), np.full((128, 128), 89), np.zeros((128, 128)), sh * 255]).astype(np.uint8), 'RGBA')
feet = 440 + shift
paste(shim, [(ox + (655 - 125 * km) * s) * K, (feet + 15 - 20 * km) * s * K, (ox + (655 + 125 * km) * s) * K, (feet + 15 + 20 * km) * s * K])
ci = shop('chicken_%s.png' % wd['id']); chh = 303 * km; chw = chh * ci.width / ci.height
paste(ci, [(ox + (660 - 0.66 * chw) * s) * K, (feet - chh) * s * K, (ox + (660 - 0.66 * chw + chw) * s) * K, feet * s * K])
if tab == 0:
    f = 0.55 + 0.45 * min(wd['extentX'] / 2.1, 1); gw = 334 * f * km; gh = gw / 2; gcy = 327 + shift - 138 * km
    paste(shop('weapon_%s.png' % wd['id']), [(ox + (303 - gw / 2) * s) * K, (gcy - gh / 2) * s * K, (ox + (303 + gw / 2) * s) * K, (gcy + gh / 2) * s * K])

# статы
ov = Image.new('RGBA', (w, h), (0, 0, 0, 0)); od = ImageDraw.Draw(ov)
if tab == 0:
    b = R(1, 1, 200, 327, 248, 67); box(b, (217, 217, 217, 224), None, 4)
    interval = max(wd['interval'], .01); dmg = round(wd['damage'] * max(wd['pellets'], 1) / interval)
    acc = min(100, max(1, round(100 - 15.4 * (wd['spreadX'] + wd['spreadY']) / 2)))
    f = sans(max(21 * s, 9))
    od.text((b[0] + 10 * s * K, b[1] + 19 * s * K), 'Damage', font=f, fill=(38, 38, 38), anchor='lm'); od.text((b[2] - 10 * s * K, b[1] + 19 * s * K), str(dmg), font=f, fill=(38, 38, 38), anchor='rm')
    od.text((b[0] + 10 * s * K, b[1] + 48 * s * K), 'Accuracy', font=f, fill=(38, 38, 38), anchor='lm'); od.text((b[2] - 10 * s * K, b[1] + 48 * s * K), str(acc), font=f, fill=(38, 38, 38), anchor='rm')
# вкладки
names = ['Guns', 'Hats', 'Shoes', 'Eyes', 'Beak']
for i, n in enumerate(names):
    b = R(1, 1, 9 + 87 * i, 394, 86, 85)
    od.rectangle(b, fill=(69, 92, 20, 255) if i == tab else (209, 194, 115, 255))
    text_c([b[0], b[1] + 58 * s * K, b[2], b[1] + 82 * s * K], n, nik(max(21 * s, 9)), (255, 255, 255, 255) if i == tab else TEXT)
# нижний ряд
od.rectangle([0, (H - 90 * s) * K, w, h], fill=(31, 71, 5, 90))
img.alpha_composite(ov)
for i, n in enumerate(names):
    b = R(1, 1, 9 + 87 * i, 394, 86, 85)
    paste_fit(shop('tab_%s.png' % n.lower()), [b[0] + 12 * s * K, b[1] + 4 * s * K, b[0] + 74 * s * K, b[1] + 60 * s * K])
ov = Image.new('RGBA', (w, h), (0, 0, 0, 0)); od = ImageDraw.Draw(ov)
if tab == 0:
    cellW = 108 * s
    for i, x in enumerate(weapons):
        X = (8 + i * 112) * s; Y = h / K - 90 * s + 3 * s
        if X > W: break
        od.rounded_rectangle([X * K, Y * K, (X + cellW) * K, (Y + 84 * s) * K], radius=4 * s * K, fill=(255, 255, 255, 72) if i == sel else (0, 0, 0, 72), outline=(255, 255, 255, 230) if i == sel else None, width=bw)
    img.alpha_composite(ov)
    for i, x in enumerate(weapons):
        X = (8 + i * 112) * s; Y = H - 90 * s + 3 * s
        if X > W: break
        k = 0.55 + 0.45 * min(x['extentX'] / 2.1, 1); iw = (cellW - 8 * s) * k; ih = iw / 2
        if ih > 76 * s: ih = 76 * s; iw = ih * 2
        im = shop('weapon_%s_s.png' % x['id']).resize((int(iw * K), int(ih * K)), Image.LANCZOS)
        img.alpha_composite(im, (int((X + (cellW - iw) / 2) * K), int((Y + (84 * s - ih) / 2) * K)))
else:
    d = ImageDraw.Draw(img); d.text((w / 2, (H - 45 * s) * K), 'Скоро', font=nik(max(36 * s, 14)), fill=TEXT, anchor='mm')
img.convert('RGB').resize((W, H), Image.LANCZOS).save(out)
print('сохранено', out)
