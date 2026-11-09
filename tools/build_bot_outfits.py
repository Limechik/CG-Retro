#!/usr/bin/env python3
import os
import plistlib
import struct
import sys

import numpy as np

if len(sys.argv) != 2:
    raise SystemExit('usage: build_bot_outfits.py Resources')

import build_shop_items as shop

root = sys.argv[1]
out = os.path.join(root, 'bot-outfits')
os.makedirs(out, exist_ok=True)
nodes = {node['name']: i for i, node in enumerate(shop.rig.nodes)}
head = nodes['RudyHead']
right = nodes['RightFoot']
left = nodes['LeftFoot']
world = shop.world
manifest = []

for category in ('hats', 'eyes', 'shoes'):
    choices = []
    for name, _, make_parts in shop.ITEMS[category]:
        groups = {}
        for pos, normal, uv, indices, texture, color, flip in make_parts():
            if texture is not None or flip:
                raise ValueError('unsupported outfit material: ' + name)
            node = head
            if category == 'shoes':
                center = pos.mean(axis=0)
                node = min((left, right), key=lambda i: np.linalg.norm(center - world[i][:3, 3]))
            key = (node, tuple(float(v) for v in color))
            groups.setdefault(key, []).append((pos, normal, uv, indices))
        parts = []
        for index, ((node, color), triangles) in enumerate(groups.items()):
            inv = np.linalg.inv(world[node])
            positions, normals, uvs, faces = [], [], [], []
            count = 0
            for pos, normal, uv, indices in triangles:
                positions.append(pos @ inv[:3, :3].T + inv[:3, 3])
                transformed = normal @ np.linalg.inv(inv[:3, :3])
                transformed /= np.maximum(np.linalg.norm(transformed, axis=1, keepdims=True), 1e-9)
                normals.append(transformed)
                uvs.append(uv)
                faces.append(indices + count)
                count += len(pos)
            if not count or count > 65535:
                raise ValueError('invalid outfit vertex count: ' + name)
            vertices = np.concatenate((np.concatenate(positions), np.concatenate(normals), np.concatenate(uvs)), axis=1).astype('<f4')
            indices = np.concatenate(faces).reshape(-1)
            if len(indices) == 0 or np.any(indices < 0) or np.max(indices) >= count:
                raise ValueError('invalid outfit indices: ' + name)
            filename = '%s_%s_%d.cgm' % (category, name, index)
            with open(os.path.join(out, filename), 'wb') as f:
                f.write(b'CGM1')
                f.write(struct.pack('<II', count, len(indices)))
                f.write(struct.pack('<6f', *vertices[:, :3].min(0), *vertices[:, :3].max(0)))
                f.write(vertices.tobytes())
                f.write(indices.astype('<u2').tobytes())
            parts.append({'mesh': filename, 'node': shop.rig.nodes[node]['name'], 'color': list(color)})
        choices.append({'id': name, 'parts': parts})
    manifest.append({'category': category, 'items': choices})

with open(os.path.join(out, 'outfits.plist'), 'wb') as f:
    plistlib.dump(manifest, f, fmt=plistlib.FMT_XML, sort_keys=False)
print('built', sum(len(item['parts']) for cat in manifest for item in cat['items']), 'outfit meshes')
