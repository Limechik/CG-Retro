#!/usr/bin/env python3
"""
Собирает Resources/weapons.plist (оружие для стрельбы) и конвертирует текстуры вспышки и следа.

Из префабов игры берутся: урон, DPS (темп = урон / DPS, как в характеристиках игры) и разброс
(errorDelta). Остальное — наши параметры (размер магазина, время перезарядки, число дробинок,
положение в руках), они заданы в таблице ниже и легко правятся.

Положение дула считается по меши: средняя точка вершин на конце ствола (ствол смотрит в +X).

Использование:
    build_weapons.py <Assets> <Resources>
"""
import os, re, sys, struct, plistlib, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('build_assets', os.path.join(HERE, 'build_assets.py'))
ba = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ba)

# id, префаб, меш, название, автомат?, магазин, перезарядка с, длина в руках (м), подброс °, дробинок, интервал (None = из данных игры), дальность
WEAPONS = [
    ('AK47',        'AK47',        'weapon_ak47',            'AK-47',        True,  30, 2.2, 0.62, 0.7, 1, None, 200),
    ('AUG',         'AUG',         'Weapon_AssultRifle01',   'AUG',          True,  30, 2.2, 0.60, 0.6, 1, None, 200),
    ('Mac10',       'Mac10',       'weapon_mac10',           'MAC-10',       True,  32, 1.8, 0.38, 0.5, 1, None, 120),
    ('G35',         'G35',         'weapon_g36',             'G36',          True,  30, 2.2, 0.58, 0.6, 1, None, 200),
    ('LMchGun',     'LMchGun',     'weapon_light_machinegun', 'LMG',         True, 100, 4.0, 0.70, 0.5, 1, None, 200),
    ('BigRevolver', 'BigRevolver', 'weapon_revolver',        'Revolver',     False,  6, 2.2, 0.34, 1.6, 1, None, 150),
    ('DesertEagle', 'DesertEagle', 'weapon_deserteagle',     'Desert Eagle', False,  9, 1.8, 0.34, 1.4, 1, None, 150),
    ('CopSG',       'CopSG',       'weapon_shotgun',         'Shotgun',      False,  8, 2.6, 0.58, 2.5, 6, 0.9,  60),
    ('3S',          '3S',          'weapon_spas',            'SPAS-12',      False,  8, 2.6, 0.56, 2.5, 6, 0.9,  60),
    ('SSG3000',     'SSG3000',     'weapon_ssg3000',         'SSG 3000',     False,  5, 3.0, 0.74, 2.0, 1, None, 400),
    ('1SN',         '1SN',         'weapon_sniper_rifle',    'Sniper Rifle', False,  5, 3.0, 0.76, 2.0, 1, None, 400),
]


# звуки (имена из tools/build_audio.py): id оружия -> (выстрел, перезарядка)
SOUND_MAP = {
    'AK47': ('shoot_ak47', 'reload_rifle'), 'AUG': ('shoot_aug', 'reload_rifle'),
    'Mac10': ('shoot_mac10', 'reload_rifle'), 'G35': ('shoot_g35', 'reload_rifle'),
    'LMchGun': ('shoot_lmg', 'reload_rifle'),
    'BigRevolver': ('shoot_revolver', 'reload_pistol'), 'DesertEagle': ('shoot_deagle', 'reload_pistol'),
    'CopSG': ('shoot_shotgun', 'reload_shotgun'), '3S': ('shoot_shotgun', 'reload_shotgun'),
    'SSG3000': ('shoot_sniper', 'reload_sniper'), '1SN': ('shoot_sniper', 'reload_sniper'),
}


def prefab_stats(assets, prefab):
    path = None
    for d in ('Prefab', 'Resources'):
        p = os.path.join(assets, d, prefab + '.prefab')
        if os.path.isfile(p):
            path = p
            break
    if not path:
        raise FileNotFoundError('нет префаба ' + prefab)
    t = ba.read(path)
    m = re.search(r'gunParams:\s*\n\s*-\s*damage:\s*([-\d.]+)\s*\n\s*damagePerSecond:\s*([-\d.]+)\s*\n'
                  r'\s*firerate:\s*([-\d.]+)\s*\n\s*accurancy:\s*([-\d.]+)', t)
    e = re.search(r'errorDelta:\s*\{x:\s*([-\d.]+),\s*y:\s*([-\d.]+)', t)
    if not m or not e:
        raise ValueError('не нашли gunParams/errorDelta в ' + prefab)
    return float(m.group(1)), float(m.group(2)), float(e.group(1)), float(e.group(2))


# Ориентация мешей оружия в дампе (в системе координат .cgm): у большинства прицел/магазин снизу, т.е. меш «вверх ногами»
# (orient 1 = повернуть на 180° вокруг X), у AUG ствол смотрит в -X (orient 2 = на 180° вокруг Y). Поправку применяет
# WeaponController при отрисовке оружия в руках, а дульная точка (muzzle) считается в системе самой меши.
ORIENT = {'AUG': 2}
DEFAULT_ORIENT = 1


def mesh_info(res, mesh, orient=1):
    d = open(os.path.join(res, 'meshes', mesh + '.cgm'), 'rb').read()
    vc, ic = struct.unpack_from('<II', d, 4)
    b = struct.unpack_from('<6f', d, 12)
    ext = b[3] - b[0]
    # вершины на конце ствола: последние 4% длины по +X (при orient 2 ствол в -X — по -X)
    sel = []
    for i in range(vc):
        x, y, z = struct.unpack_from('<3f', d, 36 + i * 32)
        if (x <= b[0] + 0.04 * ext) if orient == 2 else (x >= b[3] - 0.04 * ext):
            sel.append((x, y, z))
    n = max(len(sel), 1)
    muzzle = (b[0] if orient == 2 else b[3], sum(v[1] for v in sel) / n, sum(v[2] for v in sel) / n)
    return ext, muzzle


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    assets, res = sys.argv[1:]
    mats = plistlib.load(open(os.path.join(res, 'materials.plist'), 'rb'))

    # текстуры вспышки и следа попадания
    tex_dir = os.path.join(res, 'textures')
    os.makedirs(tex_dir, exist_ok=True)
    for name, size in (('GunFlash', 128), ('hole2', 64)):
        src = os.path.join(assets, 'Texture2D', name + '.png')
        w, h, fmt, cut, sz = ba.convert_texture(src, os.path.join(tex_dir, name + '.cgt'), size)
        print('текстура %-9s %dx%d, %s, %.0f КБ' % (name, w, h, 'RGBA4444' if fmt else 'RGB565', sz / 1024.0))

    out = []
    print('\n%-12s %-9s %6s %8s %7s %7s %5s %5s %5s' % ('id', 'авто', 'урон', 'темп/с', 'разбр.X', 'разбр.Y', 'маг.', 'дроб.', 'дул.x'))
    for wid, prefab, mesh, title, auto, mag, reload_t, view_len, kick, pellets, interval, rng in WEAPONS:
        dmg, dps, ex, ey = prefab_stats(assets, prefab)
        if interval is None:
            interval = dmg / dps if dps > 0 else 0.1          # темп из характеристик игры
        mat = mats.get(mesh)
        if not mat or 'tex' not in mat:
            raise ValueError('нет материала у меша ' + mesh)
        orient = ORIENT.get(wid, DEFAULT_ORIENT)
        ext, muzzle = mesh_info(res, mesh, orient)
        out.append({
            'id': wid, 'title': title, 'mesh': mesh, 'tex': mat['tex'], 'color': mat['color'], 'uvst': mat['uvst'],
            'damage': dmg, 'interval': round(interval, 4), 'spreadX': ex, 'spreadY': ey,
            'pellets': pellets, 'mag': mag, 'reload': reload_t, 'automatic': auto, 'range': float(rng),
            'shotSound': SOUND_MAP[wid][0], 'reloadSound': SOUND_MAP[wid][1],
            'kick': kick, 'viewLength': view_len, 'extentX': ext, 'muzzle': list(muzzle), 'orient': orient,
        })
        print('%-12s %-9s %6.0f %8.2f %7.1f %7.1f %5d %5d %5.2f' %
              (wid, 'да' if auto else 'нет', dmg, 1.0 / interval, ex, ey, mag, pellets, muzzle[0]))

    with open(os.path.join(res, 'weapons.plist'), 'wb') as f:
        plistlib.dump(out, f, fmt=plistlib.FMT_XML)
    print('\nweapons.plist: %d видов оружия' % len(out))


if __name__ == '__main__':
    main()
