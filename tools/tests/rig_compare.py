#!/usr/bin/env python3
"""
Сверка C-модуля рига с независимым расчётом на Python (по исходным кривым Unity, без запекания).
    gcc -std=c99 -O2 -Isrc tools/tests/rig_check.c src/Rig.c -o /tmp/rig_check -lm
    /tmp/rig_check Resources/characters/rudy.cgr > /tmp/rig_c.txt
    python3 tools/tests/rig_compare.py <Assets> /tmp/rig_c.txt
"""
import sys, math, os, collections
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import numpy as np
import build_character as bc

A, cfile = sys.argv[1], sys.argv[2]
gos, trs, go2tr, mfs, mrs, cols, npf = bc.bs.parse_scene(os.path.join(A, bc.PREFAB))
children = {}
for tid, t in trs.items():
    children.setdefault(t['father'], []).append(tid)
root = next(tid for tid, t in trs.items() if gos[t['go']]['name'] == bc.ROOT_NAME)
clips = {n: bc.parse_clip(os.path.join(A, 'AnimationClip', n + '.anim')) for n in bc.CLIPS}
TR = 19                                             # C хранит имена узлов до 19 символов


def qm(q):
    x, y, z, w = q
    n = math.sqrt(x*x + y*y + z*z + w*w); x, y, z, w = x/n, y/n, z/n, w/n
    return np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                     [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                     [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])


def expected(spec, t):
    over = {}
    for name in spec:
        cl = clips[name]
        tt = (t % cl['duration']) if cl['loop'] else min(t, cl['duration'])
        for c in cl['curves']:
            over.setdefault(c.path, {})[c.kind] = c.eval(tt)
    res = collections.defaultdict(list)

    def walk(tid, path, trunc, parentW):
        n = trs[tid]; o = over.get(path, {})
        p = o.get('pos', n['p'])
        q = bc.euler_to_quat(*o['euler']) if 'euler' in o else tuple(n['r'])
        L = np.eye(4); L[:3, :3] = qm(q) @ np.diag(n['s']); L[:3, 3] = p
        W = parentW @ L
        res[trunc].append(np.array([-W[0, 3], W[1, 3], W[2, 3]]))      # зеркало X (Unity -> GL)
        for c in children.get(tid, []):
            go = gos[trs[c]['go']]
            if go['active'] or go['name'] in bc.FORCE_ACTIVE:
                walk(c, (path + '/' + go['name']) if path else go['name'],
                     (trunc + '/' + go['name'][:TR]) if trunc else go['name'][:TR], W)
    walk(root, '', '', np.eye(4))
    return res


poses, cur = [], None
for line in open(cfile):
    if line.startswith('POSE'):
        _, spec, t = line.split()
        cur = {'spec': spec.split('+'), 't': float(t), 'nodes': collections.defaultdict(list)}
        poses.append(cur)
    elif line.startswith('N '):
        path, xyz = line[2:].rstrip('\n').rsplit('|', 1)
        cur['nodes'][path].append(np.array([float(v) for v in xyz.split()]))

worst, cnt, skipped, missing = 0.0, 0, 0, 0
for p in poses:
    exp = expected(p['spec'], p['t'])
    for path, plist in p['nodes'].items():
        if len(plist) != 1 or len(exp.get(path, [])) != 1:
            if path not in exp: missing += 1
            else: skipped += 1                      # одинаковые имена (4 ступни) — неоднозначно
            continue
        d = float(np.linalg.norm(plist[0] - exp[path][0])); cnt += 1
        worst = max(worst, d)
print('сверено позиций: %d, пропущено неоднозначных: %d, не найдено в эталоне: %d, макс. расхождение: %.4f м (допуск 0.05)'
      % (cnt, skipped, missing, worst))
ok = worst < 0.05 and missing == 0 and cnt > 100
print('OK' if ok else 'ПРОБЛЕМА')
sys.exit(0 if ok else 1)
