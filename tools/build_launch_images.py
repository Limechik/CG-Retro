#!/usr/bin/env python3
"""
Launch-картинки (Resources/Default*.png) в стиле главного меню: зелёный градиент, заголовок, курица.
Без Default-568h@2x.png iPhone 5 запускает приложение в режиме 3.5" (чёрные полосы), без iPad-картинок — в режиме
совместимости. Игра только горизонтальная: для iPhone файлы портретных размеров, картинка в них повёрнута на 90°
по часовой стрелке (так система показывает её при UIInterfaceOrientationLandscapeRight); для iPad — 1024x768 / 2048x1536.

    build_launch_images.py <Resources>
"""
import os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

res = sys.argv[1]
chicken = Image.open(os.path.join(res, 'menu', 'chicken.png')).convert('RGBA')

def art(W, H):
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    dx, dy = 0.3 * W, H
    t = np.clip(((xx - 0.3 * W) * dx + yy * dy) / (dx * dx + dy * dy), 0, 1)[..., None]
    img = Image.fromarray((np.array([.69, .85, .02]) * 255 * (1 - t) + np.array([.40, .72, .03]) * 255 * t).astype(np.uint8)).convert('RGBA')
    u = H / 320.0                                                     # единица = 1 pt на iPhone 5
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(os.path.join(res, '07nikumaru.ttf'), int(round(30 * u)))
    for i, line in enumerate(('ChickenGun', 'Rooster Rudy')):
        d.text((W / 2, (38 + 34 * i) * u), line, font=f, fill=(28, 36, 10, 255), anchor='mm')
    ch = int(H * 0.50); cw = int(ch * chicken.width / chicken.height)
    sh = np.clip(1 - np.hypot(*(np.mgrid[0:128, 0:128] - 64)) / 64, 0, 1) * .5
    shim = Image.fromarray(np.dstack([np.full((128, 128), 25), np.full((128, 128), 89), np.zeros((128, 128)), sh * 255]).astype(np.uint8), 'RGBA')
    shw, shh = int(cw * 0.8), int(ch * 0.13)
    top = int(H * 0.30)
    img.alpha_composite(shim.resize((shw, shh), Image.LANCZOS), (int(W / 2 - shw / 2), top + ch - shh // 2))
    img.alpha_composite(chicken.resize((cw, ch), Image.LANCZOS), (int(W / 2 - cw / 2), top))
    return img.convert('RGB')

jobs = [  # имя файла, ширина x высота ландшафтной картинки, повернуть ли в портрет
    ('Default.png',                   480,  320, True),
    ('Default@2x.png',                960,  640, True),
    ('Default-568h@2x.png',          1136,  640, True),
    ('Default-Landscape~ipad.png',   1024,  768, False),
    ('Default-Landscape@2x~ipad.png', 2048, 1536, False),
]
for name, W, H, rot in jobs:
    im = art(W, H)
    if rot: im = im.rotate(-90, expand=True)        # по часовой: верх картинки -> правый край файла
    im.save(os.path.join(res, name), optimize=True)
    print(name, im.size)
