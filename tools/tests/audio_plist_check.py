#!/usr/bin/env python3
"""Проверка audio.plist и weapons.plist: все клипы и звуки существуют, значения в разумных пределах.
    python3 tools/tests/audio_plist_check.py Resources"""
import sys, os, plistlib
res = sys.argv[1]
a = plistlib.load(open(os.path.join(res, 'audio.plist'), 'rb'))
w = plistlib.load(open(os.path.join(res, 'weapons.plist'), 'rb'))
errs = []
for name, d in a.items():
    if not d['files']: errs.append('%s: нет клипов' % name)
    for f in d['files']:
        if not os.path.isfile(os.path.join(res, 'audio', f + '.cga')): errs.append('%s: нет файла %s.cga' % (name, f))
    if not (0.05 <= d['gain'] <= 1.5): errs.append('%s: усиление %s' % (name, d['gain']))
    p0, p1 = d['pitch']
    if not (0.5 <= p0 <= p1 <= 2.0): errs.append('%s: высота %s' % (name, d['pitch']))
for x in w:
    for k in ('shotSound', 'reloadSound'):
        if x[k] not in a: errs.append('оружие %s: нет звука %s' % (x['id'], x[k]))
for need in ('step', 'jump', 'land', 'dry', 'impact', 'hit_bot', 'player_hurt', 'player_death', 'bot_death', 'bot_shot'):
    if need not in a: errs.append('нет обязательного звука %s' % need)
print('звуков в таблице %d, оружия %d: %s' % (len(a), len(w), 'OK' if not errs else 'ОШИБКИ'))
for e in errs: print('  ', e)
sys.exit(1 if errs else 0)
