#!/usr/bin/env python3
"""
Макет экрана «Новая игра» (PIL) с теми же формулами вёрстки, что в src/NewGameView.m. Это НЕ UIKit: проверка пропорций.

    preview_newgame.py <Resources> <out.png> [ширина=1170] [высота=500] [режим=1] [последняя_карта=ChaloHouse]
"""
import sys, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

res, out = sys.argv[1], sys.argv[2]
W = int(sys.argv[3]) if len(sys.argv) > 3 else 1170
H = int(sys.argv[4]) if len(sys.argv) > 4 else 500
mode = int(sys.argv[5]) if len(sys.argv) > 5 else 1
last = sys.argv[6] if len(sys.argv) > 6 else 'ChaloHouse'
K = 2; w, h = W * K, H * K
DW, DH, HEADER, RA, RB = 1170.0, 500.0, 62.0, 170.0, 268.0
s = min(W / DW, H / DH); ox = (W - DW * s) / 2; Hd = H / s
k = min(1.45, max(1.0, (Hd - HEADER) / (RA + RB))); gap = max(0.0, (Hd - HEADER - (RA + RB) * k) / 3)
yA = HEADER + gap; yB = yA + RA * k + gap
sans_b = lambda sz: ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', int(round(sz * K)))
sans = lambda sz: ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', int(round(sz * K)))
def X(v): return (ox + v * s) * K
def Y(v): return v * s * K
def img_(*p): return Image.open(os.path.join(res, *p)).convert('RGBA')

yy, xx = np.mgrid[0:h, 0:w].astype(np.float32); dx, dy = 0.3 * w, h
t = np.clip(((xx - 0.3 * w) * dx + yy * dy) / (dx * dx + dy * dy), 0, 1)[..., None]
img = Image.fromarray((np.array([.80, .90, .60]) * 255 * (1 - t) + np.array([.68, .83, .44]) * 255 * t).astype(np.uint8)).convert('RGBA')
ov = Image.new('RGBA', (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(ov)
TEXT = (33, 38, 23, 255); CARD = (240, 247, 224, 209); SEL = (194, 230, 128, 250); BORDER = (204, 224, 168, 255); SELB = (77, 133, 26, 255)
bw = max(1, int(2 * s * K))
def text(cx, cy, t_, f, col=TEXT): d.text((cx, cy), t_, font=f, fill=col, anchor='mm')

# шапка
d.rounded_rectangle([3 * s * K, 5 * s * K, 190 * s * K, 57 * s * K], radius=4 * s * K, fill=(250, 252, 242, 247), outline=(209, 219, 189, 255), width=bw)
text((3 + 120) * s * K, 31 * s * K, 'Назад', sans_b(max(19 * s, 12)))
text(X(585), Y(32), 'Новая игра', sans_b(max(22 * s, 13)))
cap = sans_b(max(22 * k * s, 12))
text(X(585), Y(yA + 36 * k), 'Выбери режим', cap)
cw, ch, cg, cy = 323 * k, 110 * k, 14 * k, yA + 60 * k
cards = []
for i, (label, icons) in enumerate((('Все против всех', ['bird_gray.png']), ('Командный бой', ['bird_blue.png', 'bird_red.png']))):
    cx = 585 + (-(cg / 2 + cw) if i == 0 else cg / 2)
    on = (i == mode)
    d.rounded_rectangle([X(cx), Y(cy), X(cx + cw), Y(cy + ch)], radius=4 * s * K, fill=SEL if on else CARD, outline=SELB if on else BORDER, width=int((3 if on else 1) * max(1, s) * K))
    text(X(cx + cw / 2), Y(cy + 85 * k), label, cap)
    cards.append((cx, icons))
mapcap = (X(585), Y(yB + 10 * k))
text(mapcap[0], mapcap[1], 'Выбери карту', cap)
names = [f[:-4] for f in sorted(os.listdir(os.path.join(res, 'scenes'))) if f.endswith('.cgs')]
mw, mh, mg = 283 * k, 215 * k, 6 * k
tw, th = 205 * k, 130 * k
cardrects = []
for i, n in enumerate(names):
    x0 = 6 * k + i * (mw + mg)
    if X(x0) > w: break
    d.rounded_rectangle([X(x0), Y(yB + 38 * k), X(x0 + mw), min(Y(yB + 38 * k + mh), h + 20)], radius=3 * s * K, fill=CARD, outline=BORDER, width=max(1, int(s * K)))
    text(X(x0 + mw / 2), Y(yB + 38 * k + 163 * k), n, sans(max(21 * k * s, 11)))
    cardrects.append((n, x0))
img.alpha_composite(ov)
for cx, icons in cards:
    n = len(icons); isz = 46 * k
    for j, f in enumerate(icons):
        x0 = cx + (cw - n * isz - (n - 1) * 10 * k) / 2 + j * (isz + 10 * k)
        im = img_('newgame', f).resize((int(isz * s * K), int(isz * s * K)), Image.LANCZOS)
        img.alpha_composite(im, (int(X(x0)), int(Y(cy + 14 * k))))
for n, x0 in cardrects:
    th_img = img_('maps', n + '.png'); tr = th_img.width / th_img.height
    tw_, th_ = tw * s * K, th * s * K
    k2 = max(tw_ / th_img.width, th_ / th_img.height); sc = th_img.resize((int(th_img.width * k2), int(th_img.height * k2)), Image.LANCZOS)
    cl = sc.crop((int((sc.width - tw_) / 2), int((sc.height - th_) / 2), int((sc.width + tw_) / 2), int((sc.height + th_) / 2)))
    px, py = X(x0 + (mw - tw) / 2), Y(yB + 38 * k + 7 * k)
    img.alpha_composite(cl, (int(px), int(py)))
    if n == last:
        dot = img_('newgame', 'dot.png'); ds = 40 * k * s * K; dot = dot.resize((int(ds), int(ds * 0.9)), Image.LANCZOS)
        img.alpha_composite(dot, (int(px + tw_ - ds * 0.75), int(py - ds * 0.1)))
d2 = ImageDraw.Draw(img)
ch_ = img_('newgame', 'chevron.png').resize((int(32 * s * K), int(32 * s * K)), Image.LANCZOS)
img.alpha_composite(ch_, (int(14 * s * K), int(10 * s * K)))
img.convert('RGB').resize((W, H), Image.LANCZOS).save(out)
print('сохранено', out, 'k=%.2f gap=%.1f Hd=%.0f' % (k, gap, Hd))
