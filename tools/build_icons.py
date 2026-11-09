#!/usr/bin/env python3
"""build the launcher icons from a square image

usage: build_icons.py [source=tools/icon_source.png] [output=Resources]
"""
import os
import sys
from PIL import Image, ImageDraw

SIZES = {
    'Icon.png': 57,
    'Icon@2x.png': 114,
    'Icon-72.png': 72,
    'Icon-72@2x.png': 144,
    'Icon-60@2x.png': 120,
    'Icon-60@3x.png': 180,
    'Icon-76.png': 76,
    'Icon-76@2x.png': 152,
    'Icon-83.5@2x.png': 167,
    'Icon-Small.png': 29,
    'Icon-Small@2x.png': 58,
    'Icon-Small-50.png': 50,
    'Icon-Small-50@2x.png': 100,
}
LEGACY_HOME = {'Icon.png', 'Icon@2x.png', 'Icon-72.png', 'Icon-72@2x.png'}


def build_icon(source, side, gloss):
    image = source.convert('RGBA')
    edge = image.width
    mask = Image.new('L', image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, edge - 1, edge - 1), radius=round(edge * 0.18), fill=255)
    image.putalpha(mask)
    image = image.resize((side, side), Image.Resampling.LANCZOS)
    image.putalpha(image.getchannel('A').point(lambda value: 0 if value <= 3 else value))
    if gloss:
        scale = 4
        width = side * scale
        highlight = Image.new('L', (width, width), 0)
        draw = ImageDraw.Draw(highlight)
        for y in range(width // 2 + 1):
            for x in range(width):
                boundary = width * (0.52 - 0.10 * ((x - width * 0.5) / (width * 0.5)) ** 2)
                if y <= boundary:
                    alpha = int(65 - 34 * y / (width * 0.52))
                    draw.point((x, y), fill=alpha)
        highlight = highlight.resize((side, side), Image.Resampling.LANCZOS)
        veil = Image.new('RGBA', (side, side), (255, 255, 255, 0))
        veil.putalpha(highlight)
        alpha = image.getchannel('A')
        image = Image.alpha_composite(image, veil)
        image.putalpha(alpha)
    return image


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    source = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, 'icon_source.png')
    output = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, '..', 'Resources')
    with Image.open(source) as image:
        if image.width != image.height or not image.width:
            raise ValueError('icon source must be a nonempty square')
        os.makedirs(output, exist_ok=True)
        for name, side in SIZES.items():
            build_icon(image, side, name in LEGACY_HOME).save(os.path.join(output, name), optimize=True)
            print(name, side)


if __name__ == '__main__':
    main()
