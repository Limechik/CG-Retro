#!/usr/bin/env python3
"""
Макет боевого HUD (PIL) с теми же формулами, что в GameView layoutButtons / HUDButton. Это НЕ UIKit и без 3D-сцены
(фон условный): проверка расположения кнопок и джойстика.

    preview_hud.py <Resources> <out.png> [ширина=568] [высота=320] [индекс_оружия=3]
"""
import sys, os, plistlib
from PIL import Image, ImageDraw, ImageFont

res, out = sys.argv[1], sys.argv[2]
W = int(sys.argv[3]) if len(sys.argv) > 3 else 568
H = int(sys.argv[4]) if len(sys.argv) > 4 else 320
wi = int(sys.argv[5]) if len(sys.argv) > 5 else 3
K = 3
u = min(1.6, max(1.0, min(W / 568.0, H / 320.0)))
img = Image.new('RGBA', (W * K, H * K), (96, 150, 190, 255))
d = ImageDraw.Draw(img)
for y in range(H * K):                       # условное небо/земля
    t = y / (H * K); c = (int(110 + 40 * t), int(170 - 20 * t), int(215 - 90 * t)) if t < 0.55 else (int(95 - 20 * t), int(140 + 10 * t), int(60))
    d.line([(0, y), (W * K, y)], fill=c)

def tex(n): return Image.open(os.path.join(res, 'hud', n)).convert('RGBA')
def alpha(im, a): im = im.copy(); im.putalpha(im.getchannel('A').point(lambda v: int(v * a))); return im
def put(im, cx, cy, size_w, size_h=None):
    size_h = size_h or size_w
    im = im.resize((max(1, int(size_w * K)), max(1, int(size_h * K))), Image.LANCZOS)
    img.alpha_composite(im, (int(cx * K - im.width / 2), int(cy * K - im.height / 2)))
def fit(im, box):                              # aspect-fit в квадрат box
    k = min(box / im.width, box / im.height); return im.resize((max(1, int(im.width * k * K / (box / box))) if False else max(1, int(im.width * k * K)), max(1, int(im.height * k * K))), Image.LANCZOS)

ring, disc = tex('ring.png'), tex('disc.png')
weapons = plistlib.load(open(os.path.join(res, 'weapons.plist'), 'rb'))
wicon = Image.open(os.path.join(res, 'shop', 'weapon_%s_s.png' % weapons[wi]['id'])).convert('RGBA')

def hud_button(cx, cy, d_, icon, k, a, pressed=False):
    d_ *= u
    if pressed: put(alpha(disc, .28), cx, cy, d_)
    put(ring, cx, cy, d_)
    s = d_ * k
    ic = icon; r = min(s / ic.width, s / ic.height)
    ic = alpha(ic, a).resize((max(1, int(ic.width * r * K)), max(1, int(ic.height * r * K))), Image.LANCZOS)
    img.alpha_composite(ic, (int(cx * K - ic.width / 2), int(cy * K - ic.height / 2)))

# координаты — как в layoutButtons (центры кнопок), в пунктах
hud_button(W - 54 * u, 78 * u, 58, wicon, 0.80, 1.0)                  # оружие
hud_button(W - 60 * u, H - 60 * u, 68, tex('jump.png'), 0.62, 0.56)   # прыжок
hud_button(W - 60 * u, H - 135 * u, 76, tex('fire.png'), 0.72, 0.68, pressed=True)   # огонь справа (показан нажатым)
hud_button(61 * u, H - 135 * u, 76, tex('fire.png'), 0.72, 0.68)      # огонь слева
hud_button(W - 170 * u, H - 60 * u, 48, tex('reload.png'), 0.58, 0.68)  # перезарядка

# плавающий джойстик: палец на (x, y), ручка отклонена вправо-вверх
sx, sy = 150 * u, H - 95 * u
bs = 96 * u; put(alpha(ring, .9), sx, sy, bs)
kx, ky = sx + 0.6 * bs / 2 * 0.85, sy - 0.5 * bs / 2 * 0.85
put(alpha(disc, .3), kx, ky, 34 * u); put(ring, kx, ky, 34 * u)

# текстовые кнопки Next scene / Menu и подписи (упрощённо)
d = ImageDraw.Draw(img)
f = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', int(13 * u * K))
for (x, y, w_, h_, t) in [(W - 100 * u, 6 * u, 92 * u, 32 * u, 'Next scene'), (10 * u, 98 * u, 82 * u, 28 * u, 'Menu')]:
    d.rounded_rectangle([x * K, y * K, (x + w_) * K, (y + h_) * K], radius=6 * K, fill=(230, 230, 235, 255), outline=(120, 120, 130, 255), width=K)
    d.text(((x + w_ / 2) * K, (y + h_ / 2) * K), t, font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', int(11 * u * K)), fill=(40, 40, 50), anchor='mm')
f2 = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', int(16 * u * K))
d.text((W / 2 * K, (H - 24 * u) * K), '30 / 30  G36', font=f2, fill=(255, 255, 255), anchor='mm')
d.text((12 * u * K, (H - 20 * u) * K), 'HP 100', font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', int(20 * u * K)), fill=(255, 255, 255), anchor='lm')
cx, cy = W / 2 * K, H / 2 * K
d.line([(cx - 8 * K, cy), (cx + 8 * K, cy)], fill=(255, 255, 255), width=K); d.line([(cx, cy - 8 * K), (cx, cy + 8 * K)], fill=(255, 255, 255), width=K)
img.convert('RGB').resize((W, H), Image.LANCZOS).save(out)
print('сохранено', out)
