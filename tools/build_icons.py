#!/usr/bin/env python3
"""
Иконки приложения из tools/icon_source.png (квадрат, лучше 512x512 и больше, без прозрачности) -> Resources/Icon*.png.
iOS не принимает прозрачность в иконках, поэтому сохраняем RGB. Список файлов прописан в Info.plist (CFBundleIcons).

    build_icons.py [исходник=tools/icon_source.png] [Resources]
"""
import os, sys
from PIL import Image

here = os.path.dirname(os.path.abspath(__file__))
src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, 'icon_source.png')
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, '..', 'Resources')
im = Image.open(src)
if im.mode == 'RGBA':                       # на всякий случай: подложим под прозрачность зелёный фон иконки
    bg = Image.new('RGB', im.size, (140, 200, 20)); bg.paste(im, mask=im.getchannel('A')); im = bg
im = im.convert('RGB')
assert im.width == im.height, 'иконка должна быть квадратной'

SIZES = {                                   # файл -> пикселей
    'Icon.png': 57, 'Icon@2x.png': 114,                    # iPhone, домашний экран
    'Icon-72.png': 72, 'Icon-72@2x.png': 144,              # iPad, домашний экран
    'Icon-Small.png': 29, 'Icon-Small@2x.png': 58,         # Settings
    'Icon-Small-50.png': 50, 'Icon-Small-50@2x.png': 100,  # Spotlight (iPad)
}
for name, px in SIZES.items():
    im.resize((px, px), Image.LANCZOS).save(os.path.join(out, name), optimize=True)
    print(name, px)
