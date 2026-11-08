#!/usr/bin/env python3
"""
Конвертирует нужные звуки из дампа (OGG/WAV) в моно 16-бит PCM (.cga) и пишет Resources/audio.plist.

iOS 6 не читает OGG, а позиционный звук OpenAL работает только с моно-буферами, поэтому:
  ffmpeg: любой вход -> моно, 22050 Гц, s16 -> обрезка тишины по краям -> нормализация пика (до 0.89)
  -> файл .cga:   char magic[4]="CGA1"; uint32 sampleRate; uint32 frames; int16 samples[frames]

audio.plist: логическое имя -> { files: [клипы], gain, pitch: [мин, макс] }. Игра выбирает случайный клип
и случайную высоту из диапазона, поэтому одинаковые выстрелы не звучат монотонно. Привязка звуков к событиям
(таблица SOUNDS ниже) — наша: в дампе она лежит во вложенных префабах, которых нет.

Использование:
    build_audio.py <Assets> <Resources>
Нужен ffmpeg в PATH.
"""
import os, re, sys, struct, subprocess, plistlib

RATE = 22050
PEAK = 0.89
MAX_SECONDS = 3.0

# имя -> (клипы, усиление, (мин. высота, макс. высота))
SOUNDS = {
    # выстрелы игрока и ботов (по оружию)
    'shoot_ak47':     (['M16_shoot'],                          0.90, (0.97, 1.03)),
    'shoot_aug':      (['SG553shoot'],                         0.90, (0.97, 1.03)),
    'shoot_mac10':    (['mp7shoot'],                           0.85, (0.95, 1.05)),
    'shoot_g35':      (['M4A1SDshoot'],                        0.90, (0.97, 1.03)),
    'shoot_lmg':      (['NegevShoot'],                         0.90, (0.97, 1.03)),
    'shoot_revolver': (['Revolver01'],                         1.00, (0.97, 1.03)),
    'shoot_deagle':   (['pist2 shoot'],                        1.00, (0.97, 1.03)),
    'shoot_shotgun':  (['CannonShoot'],                        0.90, (1.15, 1.25)),
    'shoot_sniper':   (['HeavyMaschineGun'],                   1.00, (0.70, 0.80)),
    'bot_shot':       (['M16_shoot'],                          0.75, (0.92, 1.08)),
    # перезарядка и осечка
    'reload_pistol':  (['DesertEagle_reload 3'],               0.80, (1.0, 1.0)),
    'reload_rifle':   (['G35_reload 2'],                       0.80, (1.0, 1.0)),
    'reload_shotgun': (['ICS_190_GLM_reload 1'],               0.80, (1.0, 1.0)),
    'reload_sniper':  (['sniper_reload 1'],                    0.80, (1.0, 1.0)),
    'dry':            (['DryShot', 'DryShot_0'],               0.70, (0.97, 1.03)),
    # движение игрока
    'step':           (['Footstep1'],                          0.45, (0.90, 1.10)),
    'jump':           (['Jump'],                               0.60, (0.95, 1.05)),
    'land':           (['GroundedCSGO'],                       0.70, (0.95, 1.05)),
    # попадания
    'impact':         (['ricochet01'],                         0.60, (0.90, 1.20)),
    'hit_bot':        (['hit02', 'hit04', 'hit07', 'hit08'],   0.70, (0.95, 1.05)),
    'player_hurt':    (['hit07', 'hit08'],                     0.90, (0.80, 0.90)),
    # смерть: у ботов высокий «птичий» тон
    'bot_death':      (['scream7', 'scream8', 'scream9', 'scream10'], 0.90, (1.35, 1.60)),
    'player_death':   (['scream8'],                            1.00, (0.90, 0.95)),
}


def safe(n):
    return re.sub(r'[^A-Za-z0-9_.-]+', '_', n)


def find_source(assets, clip):
    d = os.path.join(assets, 'AudioClip')
    for ext in ('.ogg', '.wav', '.mp3'):
        p = os.path.join(d, clip + ext)
        if os.path.isfile(p):
            return p
    raise FileNotFoundError('нет клипа %r в %s' % (clip, d))


def decode(path):
    cmd = ['ffmpeg', '-v', 'error', '-i', path, '-ac', '1', '-ar', str(RATE), '-f', 's16le', '-']
    raw = subprocess.run(cmd, check=True, stdout=subprocess.PIPE).stdout
    n = len(raw) // 2
    return list(struct.unpack('<%dh' % n, raw[:n * 2]))


def process(samples):
    thr = int(32768 * 0.003)                                  # ~ -50 дБ: тишина по краям
    a, b = 0, len(samples)
    while a < b and abs(samples[a]) < thr:
        a += 1
    while b > a and abs(samples[b - 1]) < thr:
        b -= 1
    s = samples[a:b][:int(MAX_SECONDS * RATE)]
    if not s:
        raise ValueError('клип пуст после обрезки тишины')
    pk = max(abs(x) for x in s)
    k = min(PEAK * 32767.0 / pk, 8.0)                         # не раздуваем шум больше чем в 8 раз
    out = [max(-32768, min(32767, int(round(x * k)))) for x in s]
    # короткое затухание в конце, чтобы не щёлкало
    fade = min(len(out), int(0.004 * RATE))
    for i in range(fade):
        out[len(out) - 1 - i] = int(out[len(out) - 1 - i] * (i / float(fade)))
    return out


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    assets, res = sys.argv[1:]
    out_dir = os.path.join(res, 'audio')
    os.makedirs(out_dir, exist_ok=True)

    clips = sorted({c for files, _, _ in SOUNDS.values() for c in files})
    info = {}
    total = 0
    for c in clips:
        s = process(decode(find_source(assets, c)))
        name = safe(c)
        with open(os.path.join(out_dir, name + '.cga'), 'wb') as f:
            f.write(b'CGA1')
            f.write(struct.pack('<II', RATE, len(s)))
            f.write(struct.pack('<%dh' % len(s), *s))
        size = 12 + len(s) * 2
        total += size
        info[c] = (name, len(s) / float(RATE), max(abs(x) for x in s) / 32767.0, size)

    table = {}
    for sname, (files, gain, (p0, p1)) in sorted(SOUNDS.items()):
        table[sname] = {'files': [safe(f) for f in files], 'gain': gain, 'pitch': [p0, p1]}
    with open(os.path.join(res, 'audio.plist'), 'wb') as f:
        plistlib.dump(table, f, fmt=plistlib.FMT_XML)

    print('%-28s %7s %6s %8s' % ('клип', 'длит.,с', 'пик', 'байт'))
    for c in clips:
        n, d, pk, sz = info[c]
        print('%-28s %7.2f %6.2f %8d' % (n, d, pk, sz))
    print('\nклипов %d, звуков в таблице %d, всего %.2f МБ' % (len(clips), len(table), total / 1048576.0))


if __name__ == '__main__':
    main()
