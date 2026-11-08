#!/usr/bin/env python3
"""
Текстуры управления из Unity-проекта оригинала (chicken-gun.zip, Assets/Texture2D) -> Resources/hud/.
В оригинале (Dust2.unity, PlayerControlsPanel) это:
  circle-2thin       -> ring.png    кольцо: основание и ручка плавающего джойстика, рамка всех кнопок
  circle-1           -> disc.png    заливка кольца (подсветка при нажатии)
  double_up-512      -> jump.png    иконка прыжка (JetpackJump)
  bullet_318-56069-1 -> fire.png    иконка стрельбы (Shoot)
  refresh            -> reload.png  иконка перезарядки (ReloadBtn)

    import_hud_textures.py <chicken-gun.zip> [Resources]
"""
import sys, os, zipfile
zpath = sys.argv[1]; out = os.path.join(sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Resources'), 'hud')
os.makedirs(out, exist_ok=True)
MAP = {'circle-2thin': 'ring', 'circle-1': 'disc', 'double_up-512': 'jump', 'bullet_318-56069-1': 'fire', 'refresh': 'reload'}
z = zipfile.ZipFile(zpath)
names = {os.path.basename(n): n for n in z.namelist() if '/Assets/Texture2D/' in n and n.endswith('.png')}
for src, dst in MAP.items():
    open(os.path.join(out, dst + '.png'), 'wb').write(z.read(names[src + '.png'])); print(src, '->', dst + '.png')
