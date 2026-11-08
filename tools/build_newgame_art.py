#!/usr/bin/env python3
"""
Картинки экрана «Новая игра» (Resources/newgame/): иконки режимов (простая нарисованная птичка трёх цветов:
серая — «Все против всех», синяя и красная — команды), шеврон кнопки «Назад» и зелёная точка выбранной карты
(selection_icon из Unity-проекта оригинала, если указан архив).

    build_newgame_art.py <Resources> [chicken-gun.zip]
"""
import os, sys, zipfile
from PIL import Image, ImageDraw

res = sys.argv[1]; out = os.path.join(res, 'newgame'); os.makedirs(out, exist_ok=True)
S = 4

def bird(body, belly, name, N=128):
    im = Image.new('RGBA', (N * S, N * S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    def P(*v): return [x * S for x in v]
    d.polygon(P(52, 30, 58, 10, 66, 28, 76, 6, 84, 30, 98, 14, 96, 38), fill=(214, 52, 40), outline=(140, 24, 20))     # гребень
    d.ellipse(P(18, 30, 112, 112), fill=body, outline=(70, 70, 70), width=3 * S)                                       # тело
    d.ellipse(P(34, 66, 96, 108), fill=belly)                                                                          # брюшко
    d.polygon(P(18, 62, 4, 68, 18, 76), fill=(244, 160, 30), outline=(150, 90, 10))                                    # клюв
    d.ellipse(P(30, 50, 42, 64), fill=(255, 255, 255), outline=(50, 50, 50), width=S); d.ellipse(P(32, 54, 39, 62), fill=(20, 20, 20))   # глаз
    d.polygon(P(100, 66, 120, 56, 116, 86), fill=body, outline=(70, 70, 70))                                          # хвост
    d.line(P(52, 112, 52, 122, 44, 124), fill=(230, 150, 30), width=4 * S); d.line(P(76, 112, 76, 122, 68, 124), fill=(230, 150, 30), width=4 * S)  # лапки
    im.resize((N, N), Image.LANCZOS).save(os.path.join(out, name), optimize=True)

bird((190, 190, 196), (226, 226, 230), 'bird_gray.png')
bird((96, 140, 235), (170, 200, 250), 'bird_blue.png')
bird((232, 96, 88), (248, 176, 168), 'bird_red.png')

im = Image.new('RGBA', (64 * S, 64 * S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
d.line([(42 * S, 10 * S), (18 * S, 32 * S), (42 * S, 54 * S)], fill=(20, 20, 20, 255), width=8 * S, joint='curve')
for p in ((42, 10), (18, 32), (42, 54)): d.ellipse([(p[0] - 4) * S, (p[1] - 4) * S, (p[0] + 4) * S, (p[1] + 4) * S], fill=(20, 20, 20, 255))
im.resize((64, 64), Image.LANCZOS).save(os.path.join(out, 'chevron.png'), optimize=True)

if len(sys.argv) > 2:
    z = zipfile.ZipFile(sys.argv[2])
    n = next(n for n in z.namelist() if n.endswith('/Assets/Texture2D/selection_icon.png'))
    open(os.path.join(out, 'dot.png'), 'wb').write(z.read(n))
print('готово ->', out)
