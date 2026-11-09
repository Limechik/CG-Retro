#!/usr/bin/env python3
import os
import plistlib
import sys
import unittest

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../..'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import cgraster


class OutfitTests(unittest.TestCase):
    def test_textured_layer_preserves_color(self):
        pos = np.array([[-1, -1, 0], [1, -1, 0], [0, 1, 0]], float)
        normal = np.array([[0, 0, 1]] * 3, float)
        uv = np.zeros((3, 2))
        indices = np.array([[0, 1, 2]])
        texture = np.array([[[240, 100, 40]]], dtype=np.uint8)
        item = (pos, normal, uv, indices, texture, np.array([0.5, 1, 1]), 0)
        image = cgraster.render_layer([item], [], 16, 16, ss=1, view=(np.zeros(3), 5), amb=1)
        self.assertEqual(image.getpixel((8, 8)), (120, 100, 40, 255))
        self.assertEqual(image.getpixel((0, 0))[3], 0)

    def test_beak_layers_match_selected_color(self):
        resources = os.path.join(ROOT, 'Resources')
        with open(os.path.join(resources, 'items.plist'), 'rb') as f:
            categories = plistlib.load(f)
        with open(os.path.join(resources, 'weapons.plist'), 'rb') as f:
            weapons = plistlib.load(f)
        beaks = next(c['items'] for c in categories if c['key'] == 'beak')
        for item in beaks:
            name = item['id']
            if name == 'none':
                continue
            paths = [os.path.join(resources, 'menu', 'layer_beak_%s.png' % name)]
            paths.extend(os.path.join(resources, 'shop', 'layer_beak_%s_%s.png' % (name, w['id'])) for w in weapons)
            for path in paths:
                with self.subTest(path=path), Image.open(path) as image:
                    pixels = np.asarray(image.convert('RGBA'))
                    rgb = pixels[pixels[:, :, 3] > 240, :3]
                    self.assertGreater(len(rgb), 0)
                    mean = rgb.mean(axis=0)
                    self.assertGreater(float(mean.max()), 5)
                    if name in ('red', 'green', 'blue'):
                        self.assertEqual(int(np.argmax(mean)), {'red': 0, 'green': 1, 'blue': 2}[name])

    def test_bot_outfits_have_valid_meshes_and_nodes(self):
        resources = os.path.join(ROOT, 'Resources')
        with open(os.path.join(resources, 'items.plist'), 'rb') as f:
            items = {c['key']: {item['id'] for item in c['items']} - {'none'} for c in plistlib.load(f)}
        directory = os.path.join(resources, 'bot-outfits')
        with open(os.path.join(directory, 'outfits.plist'), 'rb') as f:
            categories = plistlib.load(f)
        rig = cgraster.Rig(os.path.join(resources, 'characters', 'rudy.cgr'))
        nodes = {node['name'] for node in rig.nodes}
        self.assertEqual([c['category'] for c in categories], ['hats', 'eyes', 'shoes'])
        for category in categories:
            self.assertEqual({item['id'] for item in category['items']}, items[category['category']])
            self.assertLess(len(category['items']), 8)
            for item in category['items']:
                self.assertTrue(item['parts'])
                for part in item['parts']:
                    with self.subTest(item=item['id'], mesh=part['mesh']):
                        self.assertIn(part['node'], nodes)
                        vertices, indices = cgraster.load_cgm(os.path.join(directory, part['mesh']))
                        self.assertTrue(np.isfinite(vertices).all())
                        self.assertGreater(len(indices), 0)
                        self.assertLess(int(indices.max()), len(vertices))
                        self.assertEqual(len(part['color']), 3)


if __name__ == '__main__':
    unittest.main()
