#!/usr/bin/env python3
"""
Макет главного меню (PIL) с теми же координатами и цветами, что в src/MenuView.m. Это НЕ UIKit: проверка пропорций.

    preview_menu.py <Resources> <out.png> [ширина=1302] [высота=600]
"""
import sys, os
from PIL import Image, ImageDraw, ImageFont

res, out = sys.argv[1], sys.argv[2]
W = int(sys.argv[3]) if len(sys.argv) > 3 else 1302
H = int(sys.argv[4]) if len(sys.argv) > 4 else 600
K = 2                                  # суперсэмплинг
w, h = W * K, H * K
DW, DH = 1302.0, 600.0
s = min(W / DW, H / DH)
ox = (W - DW * s) / 2; oyT = 0; oyM = (H - DH * s) / 2; oyB = H - DH * s

def sans(sz): return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', int(round(sz * K)))   # вместо системного шрифта iOS
def font(sz): return ImageFont.truetype(os.path.join(res, '07nikumaru.ttf'), int(round(sz * K)))
def rgb(r, g, b): return (int(r * 255), int(g * 255), int(b * 255))
def R(ax, ay, x, y, dw, dh):
    oy = (oyT, oyM, oyB)[ay]
    X = (ox if ax else 0) + x * s; Y = oy + y * s
    return [X * K, Y * K, (X + dw * s) * K, (Y + dh * s) * K]

# фон: градиент (start (0.3,0) -> end (0.6,1))
import numpy as np
yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
dx, dy = (0.6 - 0.3) * w, h
t = ((xx - 0.3 * w) * dx + yy * dy) / (dx * dx + dy * dy); t = np.clip(t, 0, 1)[..., None]
c0 = np.array([0.69, 0.85, 0.02]) * 255; c1 = np.array([0.40, 0.72, 0.03]) * 255
img = Image.fromarray((c0 * (1 - t) + c1 * t).astype(np.uint8)).convert('RGBA')
d = ImageDraw.Draw(img)

TITLE = rgb(.11, .14, .04); PANEL = rgb(.85, .93, .68); BORDER = rgb(.71, .83, .46); TEXT = rgb(.14, .17, .08); ORANGE = rgb(.89, .50, .10)
def text_c(box, txt, f, col):
    cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
    d.text((cx, cy), txt, font=f, fill=col, anchor='mm')

# профиль
b = R(0, 0, 8, 8, 74, 74)
d.ellipse(b, fill=(255, 255, 255), outline=rgb(.33, .45, .12), width=max(1, int(3 * s * K)))
text_c(R(0, 0, 8, 20, 74, 36), '1', font(max(30 * s, 14)), ORANGE)
text_c(R(0, 0, 8, 56, 74, 22), 'lvl', font(max(17 * s, 8)), ORANGE)
bw = max(1, int(2 * s * K))
d.rounded_rectangle(R(0, 0, 90, 22, 235, 36), radius=5 * s * K, fill=PANEL, outline=BORDER, width=bw)
text_c(R(0, 0, 90, 22, 235, 36), 'General KoKoK', sans(max(21 * s, 11)), TEXT)
d.rounded_rectangle(R(0, 0, 90, 64, 235, 15), radius=4 * s * K, fill=PANEL, outline=BORDER, width=bw)
f = sans(max(17 * s, 9)); bx = R(0, 0, 10, 102, 220, 24)
d.text((bx[0], (bx[1] + bx[3]) / 2), 'Privacy Policy', font=f, fill=rgb(.25, .32, .15), anchor='lm')

# заголовок
text_c(R(1, 0, 600, 24, 500, 48), 'ChickenGun', font(max(50 * s, 22)), TITLE)
text_c(R(1, 0, 600, 80, 500, 48), 'Rooster Rudy', font(max(50 * s, 22)), TITLE)

# тень и курица
sh = Image.new('RGBA', (128, 128)); a = np.zeros((128, 128), np.float32)
Y_, X_ = np.mgrid[0:128, 0:128]; r = np.hypot(X_ - 64, Y_ - 64) / 64; a = np.clip(1 - r, 0, 1) * 0.5
sh = Image.fromarray(np.dstack([np.full((128, 128), 25), np.full((128, 128), 89), np.zeros((128, 128)), a * 255]).astype(np.uint8), 'RGBA')
Hd = H / s; _gb = Hd - 103 - 14; _avail = _gb - 135; _chD = min(_avail * 0.85, 480); _chTop = 135 + (_avail - _chD) * 0.45; kk = _chD / 300
sb = [ox + (655 - 125 * kk) * s, (_chTop + _chD + 15 - 20 * kk) * s, 250 * kk * s, 40 * kk * s]
sh = sh.resize((int(sb[2] * K), int(sb[3] * K)), Image.BILINEAR)
img.alpha_composite(sh, (int(sb[0] * K), int(sb[1] * K)))
ch = Image.open(os.path.join(res, 'menu', 'chicken.png'))
Hd = H / s; gapTop = 135; gapBot = Hd - 103 - 14; avail = gapBot - gapTop
chD = min(avail * 0.85, 300 * 1.6); chTop = gapTop + (avail - chD) * 0.45; cwD = chD * ch.width / ch.height
ch = ch.resize((int(cwD * s * K), int(chD * s * K)), Image.LANCZOS)
img.alpha_composite(ch, (int((ox + (660 - cwD / 2) * s) * K), int(chTop * s * K)))

# кнопки
d = ImageDraw.Draw(img)
for x, name in ((191, 'Shop'), (499, 'Play'), (807, 'Servers')):
    bb = R(1, 2, x, 497, 303, 89)
    d.rounded_rectangle(bb, radius=4 * s * K, fill=PANEL, outline=BORDER, width=bw)
    text_c(bb, name, font(max(36 * s, 15)), TEXT)
bx = R(0, 2, 22, 560, 160, 30)
d.text((bx[0], (bx[1] + bx[3]) / 2), 'v 1.3.6', font=sans(max(20 * s, 10)), fill=TEXT, anchor='lm')

img.convert('RGB').resize((W, H), Image.LANCZOS).save(out)
print('сохранено', out)
