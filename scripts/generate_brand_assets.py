#!/usr/bin/env python3
"""Generate raster app icons from the unified editable SVG brand source.

Requires Pillow and rsvg-convert on the developer machine. Does not change
application settings, generated UI source, historical evidence, or user data.
"""
from __future__ import annotations

import argparse
from io import BytesIO
import json
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET

from PIL import Image

REPO = Path(__file__).resolve().parents[1]
SVG_NS = '{http://www.w3.org/2000/svg}'
SOURCE = REPO / 'assets/logo/duoyi_unified_logo.svg'


def render(svg_bytes: bytes, side: int, renderer: str) -> Image.Image:
    result = subprocess.run(
        [renderer, '--format=png', '--width', str(side), '--height', str(side)],
        input=svg_bytes, check=True, capture_output=True,
    )
    return Image.open(BytesIO(result.stdout)).convert('RGBA')


def generate(*, check: bool = False) -> list[str]:
    renderer = shutil.which('rsvg-convert')
    if renderer is None:
        raise RuntimeError('rsvg-convert is required to render the canonical SVG')
    svg = SOURCE.read_bytes()
    root = ET.fromstring(svg)
    shapes = list(root.findall(SVG_NS + 'rect'))
    if len(shapes) != 4 or any(e.tag in {SVG_NS + 'image', SVG_NS + 'use'} for e in root.iter()):
        raise RuntimeError('Expected the canonical tile and three explicit white rectangles')
    red = shapes[0].get('fill')
    if not red or any(shape.get('fill') != '#FFFFFF' for shape in shapes[1:]):
        raise RuntimeError('Expected one red tile and three white mark rectangles')
    mark_root = ET.fromstring(svg)
    mark_root.remove(mark_root.find(SVG_NS + 'rect'))
    mark_svg = ET.tostring(mark_root, encoding='utf-8')
    base = render(svg, 1024, renderer)
    mark = render(mark_svg, 1024, renderer)
    solid = Image.new('RGBA', base.size, red)
    solid.alpha_composite(mark)
    # Android adaptive-icon foreground uses a 108dp canvas behind a roughly
    # 72dp system mask. Scale the mark by 2/3 so its apparent proportions agree
    # with the legacy icon's visible tile, independent of mask corner shape.
    adaptive = Image.new('RGBA', base.size, (0, 0, 0, 0))
    adaptive_mark = mark.resize((682, 682), Image.Resampling.LANCZOS)
    adaptive.alpha_composite(adaptive_mark, (171, 171))
    outputs: dict[Path, tuple[Image.Image, tuple[int, int], bool]] = {}

    def add(path: str | Path, image: Image.Image, size: int | tuple[int, int], opaque: bool = False) -> None:
        target = REPO / path
        dimensions = (size, size) if isinstance(size, int) else size
        outputs[target] = image, dimensions, opaque

    for name, side in {
        'duoyi_logo_redesign_1024.png': 1024,
        'duoyi_logo_1024.png': 1024,
        'duoyi_logo_512.png': 512,
        'duoyi_logo_192.png': 192,
        'duoyi_web_logo_512.png': 512,
    }.items():
        add('assets/logo/' + name, base, side)
    add('assets/logo/duoyi_logo_ios_1024.png', solid, 1024, True)
    add('assets/logo/duoyi_launcher_foreground_512.png', adaptive, 512)
    for side in (192, 512):
        add(f'web/icons/Icon-{side}.png', base, side)
        add(f'web/icons/Icon-maskable-{side}.png', solid, side, True)
    add('web/favicon.png', base, 32)
    add('linux/duoyi.png', base, 512)
    resource_root = REPO / 'android/app/src/main/res'
    for path in sorted(resource_root.glob('mipmap-*/ic_launcher.png')):
        with Image.open(path) as image:
            dimensions = image.size
        add(path, base, dimensions)
    for path in sorted(resource_root.glob('drawable-*/ic_launcher_foreground.png')):
        with Image.open(path) as image:
            dimensions = image.size
        add(path, adaptive, dimensions)
    contents = REPO / 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json'
    if contents.is_file():
        for entry in json.loads(contents.read_text())['images']:
            filename = entry.get('filename')
            if not filename:
                continue
            width, height = (float(value) for value in entry['size'].split('x'))
            scale = float(entry['scale'].removesuffix('x'))
            add(contents.parent / filename, solid, (round(width * scale), round(height * scale)), True)
    changed: list[str] = []
    for target, (image, dimensions, opaque) in outputs.items():
        resized = image.resize(dimensions, Image.Resampling.LANCZOS)
        if opaque:
            resized = resized.convert('RGB')
        buffer = BytesIO()
        resized.save(buffer, format='PNG', optimize=False)
        encoded = buffer.getvalue()
        if not target.is_file() or target.read_bytes() != encoded:
            changed.append(str(target.relative_to(REPO)))
            if not check:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(encoded)
    return changed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Check raster assets without writing')
    args = parser.parse_args()
    changed = generate(check=args.check)
    print(json.dumps({'check': args.check, 'changed_assets': changed}, ensure_ascii=False, indent=2))
    if args.check and changed:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
