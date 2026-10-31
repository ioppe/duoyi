#!/usr/bin/env python3
"""Render the canonical Duoyi logo to every client application icon.

Single source of truth: ``assets/logo/duoyi_app_logo.svg`` — a pure red rounded
tile (``#C85656``) carrying the white ``space_dashboard_rounded`` glyph made of
three geometric blocks, on a ``#F6F7F9`` artboard. Every platform icon PNG is
rendered from that file, so the geometry and palette cannot drift per client.

Usage::

    python3 scripts/sync_app_icons.py            # render and write every icon
    python3 scripts/sync_app_icons.py --check    # verify only, exit 1 on drift

``--check`` never writes: it re-renders in memory, compares pixels with the
files on disk, requires the two 1024 marketing icons to be byte-identical to
``duoyi_app_logo_1024.png``, verifies the audited reference screenshot and the
pubspec / Android adaptive-background declarations.

Dependencies: ``Pillow`` (raster) and ``fontTools`` (SVG path parsing +
cubic sampling). No cairosvg, no native librsvg/Inkscape, no machine-specific
paths: the repository root is derived from this file.

Only the fixed master structure is supported; anything else fails loudly
instead of silently producing a wrong icon.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import struct
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

from fontTools.pens.basePen import BasePen
from fontTools.svgLib.path import parse_path
from PIL import Image, ImageChops, ImageCms, ImageDraw

REPO_ROOT = Path(__file__).resolve().parent.parent
LOGO_DIR = REPO_ROOT / "assets" / "logo"
MASTER_SVG = LOGO_DIR / "duoyi_app_logo.svg"
CANONICAL_PNG = LOGO_DIR / "duoyi_app_logo_1024.png"
FOREGROUND_PNG = LOGO_DIR / "duoyi_app_logo_foreground_1024.png"
REFERENCE_PNG = LOGO_DIR / "duoyi_logo_reference.png"
PUBSPEC = REPO_ROOT / "pubspec.yaml"
ANDROID_COLORS = (
    REPO_ROOT / "android" / "app" / "src" / "main" / "res" / "values" / "colors.xml"
)

# The user-confirmed reference screenshot must stay byte-for-byte untouched.
# It is an audit artefact only: never rendered, never rewritten here.
REFERENCE_SHA256 = "4c3121a2a4612a9753c5175ce1ddd32bcbc8f6cd90f1a1cb69a7972d6dd41c8b"

BACKGROUND_RGB = (0xF6, 0xF7, 0xF9)
BRAND_RED_RGB = (0xC8, 0x56, 0x56)
GLYPH_RGB = (0xFF, 0xFF, 0xFF)
ARTBOARD = 88.0
TILE_RADIUS = 32.0
GLYPH_BBOX = (26.0, 26.0, 62.0, 62.0)
GLYPH_BBOX_TOLERANCE = 0.05

CANONICAL_SIZE = 1024
CANONICAL_RELATIVE = "assets/logo/duoyi_app_logo_1024.png"
FOREGROUND_RELATIVE = "assets/logo/duoyi_app_logo_foreground_1024.png"
BRAND_RED_HEX = "#C85656"


# --------------------------------------------------------------------------- #
# Target tables
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class Target:
    """One platform icon file rendered from the canonical master."""

    relative: str
    size: int
    # Android drawables are plain RGB PNG without colour-management chunks,
    # matching the rest of ``android/app/src/main/res``.
    srgb_profile: bool = True


IOS_ICONS = (
    ("Icon-App-20x20@1x.png", 20),
    ("Icon-App-20x20@2x.png", 40),
    ("Icon-App-20x20@3x.png", 60),
    ("Icon-App-29x29@1x.png", 29),
    ("Icon-App-29x29@2x.png", 58),
    ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@1x.png", 40),
    ("Icon-App-40x40@2x.png", 80),
    ("Icon-App-40x40@3x.png", 120),
    ("Icon-App-50x50@1x.png", 50),
    ("Icon-App-50x50@2x.png", 100),
    ("Icon-App-57x57@1x.png", 57),
    ("Icon-App-57x57@2x.png", 114),
    ("Icon-App-60x60@2x.png", 120),
    ("Icon-App-60x60@3x.png", 180),
    ("Icon-App-72x72@1x.png", 72),
    ("Icon-App-72x72@2x.png", 144),
    ("Icon-App-76x76@1x.png", 76),
    ("Icon-App-76x76@2x.png", 152),
    ("Icon-App-83.5x83.5@2x.png", 167),
    ("Icon-App-1024x1024@1x.png", 1024),
)

MACOS_ICONS = (
    ("app_icon_16.png", 16),
    ("app_icon_32.png", 32),
    ("app_icon_64.png", 64),
    ("app_icon_128.png", 128),
    ("app_icon_256.png", 256),
    ("app_icon_512.png", 512),
    ("app_icon_1024.png", 1024),
)

IOS_1024_RELATIVE = (
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
)
MACOS_1024_RELATIVE = (
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png"
)

# Files that must be byte-identical to the canonical 1024 PNG.
DUPLICATE_OF_CANONICAL = (IOS_1024_RELATIVE, MACOS_1024_RELATIVE)

WEB_ICONS = (
    ("web/icons/Icon-192.png", 192),
    ("web/icons/Icon-512.png", 512),
    ("web/icons/Icon-maskable-192.png", 192),
    ("web/icons/Icon-maskable-512.png", 512),
    ("web/favicon.png", 16),
)

LINUX_ICONS = (("linux/duoyi.png", 512),)

# Legacy (non-adaptive) launcher PNGs: full logo artwork, 48dp..192dp.
ANDROID_LAUNCHER_ICONS = (
    ("android/app/src/main/res/mipmap-mdpi/ic_launcher.png", 48),
    ("android/app/src/main/res/mipmap-hdpi/ic_launcher.png", 72),
    ("android/app/src/main/res/mipmap-xhdpi/ic_launcher.png", 96),
    ("android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png", 144),
    ("android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png", 192),
)

# Adaptive foreground layers: 108dp canvas, transparent outside the glyph so the
# red adaptive background shows through (no grey box behind the white glyph).
ANDROID_FOREGROUND_ICONS = (
    ("android/app/src/main/res/drawable-mdpi/ic_launcher_foreground.png", 108),
    ("android/app/src/main/res/drawable-hdpi/ic_launcher_foreground.png", 162),
    ("android/app/src/main/res/drawable-xhdpi/ic_launcher_foreground.png", 216),
    ("android/app/src/main/res/drawable-xxhdpi/ic_launcher_foreground.png", 324),
    ("android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png", 432),
)


def _artwork_targets() -> list[Target]:
    targets: list[Target] = []
    for name, size in IOS_ICONS:
        targets.append(
            Target(f"ios/Runner/Assets.xcassets/AppIcon.appiconset/{name}", size)
        )
    for name, size in MACOS_ICONS:
        targets.append(
            Target(f"macos/Runner/Assets.xcassets/AppIcon.appiconset/{name}", size)
        )
    for relative, size in WEB_ICONS:
        targets.append(Target(relative, size))
    for relative, size in LINUX_ICONS:
        targets.append(Target(relative, size))
    for relative, size in ANDROID_LAUNCHER_ICONS:
        targets.append(Target(relative, size, srgb_profile=False))
    return targets


ARTWORK_TARGETS = _artwork_targets()
FOREGROUND_TARGETS = [
    Target(relative, size, srgb_profile=False)
    for relative, size in ANDROID_FOREGROUND_ICONS
]


# --------------------------------------------------------------------------- #
# Master parsing (strictly limited to the canonical structure)
# --------------------------------------------------------------------------- #


class MasterError(RuntimeError):
    """The SVG master is not the supported canonical structure."""


@dataclass(frozen=True)
class RectShape:
    x: float
    y: float
    width: float
    height: float
    radius: float
    fill: tuple[int, int, int]


@dataclass(frozen=True)
class PathShape:
    contours: tuple[tuple[tuple[float, float], ...], ...]
    fill: tuple[int, int, int]


@dataclass(frozen=True)
class Master:
    background: RectShape
    tile: RectShape
    glyph: PathShape


_CURVE_SAMPLES = 256
_TRANSFORM_RE = re.compile(
    r"^(?:translate\(\s*(-?\d+(?:\.\d+)?)[\s,]+(-?\d+(?:\.\d+)?)\s*\)\s*)?"
    r"(?:scale\(\s*(-?\d+(?:\.\d+)?)(?:[\s,]+(-?\d+(?:\.\d+)?))?\s*\))?$"
)


def _local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _parse_color(value: str | None, where: str) -> tuple[int, int, int]:
    if value is None:
        raise MasterError(f"{where}: missing fill")
    match = re.fullmatch(r"#([0-9a-fA-F]{6})", value.strip())
    if not match:
        raise MasterError(f"{where}: only #RRGGBB fills are supported, got {value!r}")
    digits = match.group(1)
    return (int(digits[0:2], 16), int(digits[2:4], 16), int(digits[4:6], 16))


def _parse_number(raw: str | None, where: str) -> float:
    if raw is None:
        raise MasterError(f"{where}: missing numeric attribute")
    try:
        return float(raw)
    except ValueError as error:  # pragma: no cover - defensive
        raise MasterError(f"{where}: {raw!r} is not a number") from error


def _reject_unknown(element: ET.Element, allowed: set[str], where: str) -> None:
    for attribute in element.attrib:
        if attribute not in allowed:
            raise MasterError(f"{where}: unsupported attribute {attribute!r}")


class _SamplingPen(BasePen):
    """Collect cubic contours as polylines dense enough for large renders."""

    def __init__(self, glyph_set, samples: int = _CURVE_SAMPLES) -> None:
        super().__init__(glyph_set)
        self._samples = samples
        self.contours: list[list[tuple[float, float]]] = []
        self._current: list[tuple[float, float]] | None = None

    def _moveTo(self, pt) -> None:
        self._finish_contour()
        self._current = [(float(pt[0]), float(pt[1]))]

    def _lineTo(self, pt) -> None:
        self._require_contour()
        self._current.append((float(pt[0]), float(pt[1])))

    def _curveToOne(self, p1, p2, p3) -> None:
        self._require_contour()
        x0, y0 = self._current[-1]
        x1, y1 = float(p1[0]), float(p1[1])
        x2, y2 = float(p2[0]), float(p2[1])
        x3, y3 = float(p3[0]), float(p3[1])
        for index in range(1, self._samples + 1):
            t = index / self._samples
            mt = 1.0 - t
            a = mt * mt * mt
            b = 3.0 * mt * mt * t
            c = 3.0 * mt * t * t
            d = t * t * t
            self._current.append(
                (a * x0 + b * x1 + c * x2 + d * x3, a * y0 + b * y1 + c * y2 + d * y3)
            )

    def _qCurveToOne(self, p1, p2) -> None:
        raise MasterError(
            "quadratic segments are not part of the canonical master glyph"
        )

    def _closePath(self) -> None:
        self._finish_contour()

    def _endPath(self) -> None:
        self._finish_contour()

    def _require_contour(self) -> None:
        if self._current is None:
            raise MasterError("glyph path segment outside a contour")

    def _finish_contour(self) -> None:
        if self._current is not None and len(self._current) >= 3:
            self.contours.append(self._current)
        self._current = None


def _transform_points(
    contours: list[list[tuple[float, float]]], matrix: tuple[float, float, float, float]
) -> tuple[tuple[tuple[float, float], ...], ...]:
    translate_x, translate_y, scale_x, scale_y = matrix
    return tuple(
        tuple(
            (translate_x + scale_x * x, translate_y + scale_y * y) for x, y in contour
        )
        for contour in contours
    )


def _parse_transform(raw: str | None, where: str) -> tuple[float, float, float, float]:
    if raw is None:
        raise MasterError(f"{where}: the glyph needs translate()/scale()")
    match = _TRANSFORM_RE.fullmatch(raw.strip())
    if not match or match.group(0) == "":
        raise MasterError(f"{where}: unsupported transform {raw!r}")
    translate_x = float(match.group(1)) if match.group(1) is not None else 0.0
    translate_y = float(match.group(2)) if match.group(2) is not None else 0.0
    scale_x = float(match.group(3)) if match.group(3) is not None else 1.0
    scale_y = (
        float(match.group(4))
        if match.group(4) is not None
        else (scale_x if match.group(3) is not None else 1.0)
    )
    return (translate_x, translate_y, scale_x, scale_y)


def _parse_rect(element: ET.Element, where: str) -> RectShape:
    _reject_unknown(element, {"x", "y", "width", "height", "rx", "fill"}, where)
    return RectShape(
        x=_parse_number(element.get("x"), f"{where}[x]"),
        y=_parse_number(element.get("y"), f"{where}[y]"),
        width=_parse_number(element.get("width"), f"{where}[width]"),
        height=_parse_number(element.get("height"), f"{where}[height]"),
        radius=_parse_number(element.get("rx", "0"), f"{where}[rx]"),
        fill=_parse_color(element.get("fill"), where),
    )


def _parse_path(element: ET.Element, where: str) -> PathShape:
    _reject_unknown(element, {"d", "fill", "transform"}, where)
    data = element.get("d")
    if not data:
        raise MasterError(f"{where}: missing d")
    pen = _SamplingPen(None)
    parse_path(data, pen)
    if not pen.contours:
        raise MasterError(f"{where}: empty glyph outline")
    contours = _transform_points(pen.contours, _parse_transform(element.get("transform"), where))
    return PathShape(contours=contours, fill=_parse_color(element.get("fill"), where))


def _expect_close(actual: float, expected: float, where: str) -> None:
    if abs(actual - expected) > 1e-6:
        raise MasterError(f"{where}: expected {expected}, got {actual}")


def load_master(path: Path = MASTER_SVG) -> Master:
    """Parse the canonical SVG master, rejecting anything unexpected."""

    if not path.is_file():
        raise MasterError(f"missing canonical master: {path}")
    root = ET.parse(path).getroot()
    if _local_name(root.tag) != "svg":
        raise MasterError(f"{path.name}: root element must be <svg>")
    _reject_unknown(root, {"viewBox", "width", "height", "xmlns"}, "svg")
    view_box = root.get("viewBox")
    if view_box is None:
        raise MasterError("svg: missing viewBox")
    numbers = [float(part) for part in view_box.replace(",", " ").split()]
    if len(numbers) != 4:
        raise MasterError(f"svg: unsupported viewBox {view_box!r}")
    _expect_close(numbers[0], 0.0, "svg[viewBox.x]")
    _expect_close(numbers[1], 0.0, "svg[viewBox.y]")
    _expect_close(numbers[2], ARTBOARD, "svg[viewBox.width]")
    _expect_close(numbers[3], ARTBOARD, "svg[viewBox.height]")

    children = list(root)
    if len(children) != 3:
        raise MasterError(
            f"svg: expected background rect, brand rect and glyph path, "
            f"found {len(children)} child elements"
        )
    for index, child in enumerate(children):
        if _local_name(child.tag) not in {"rect", "path"}:
            raise MasterError(f"svg: unsupported element <{_local_name(child.tag)}>")

    background = _parse_rect(children[0], "svg[0]")
    tile = _parse_rect(children[1], "svg[1]")
    if _local_name(children[2].tag) != "path":
        raise MasterError("svg[2]: the glyph must be a <path>")
    glyph = _parse_path(children[2], "svg[2]")

    for label, shape in (("background", background), ("brand tile", tile)):
        _expect_close(shape.x, 0.0, f"{label}[x]")
        _expect_close(shape.y, 0.0, f"{label}[y]")
        _expect_close(shape.width, ARTBOARD, f"{label}[width]")
        _expect_close(shape.height, ARTBOARD, f"{label}[height]")
    _expect_close(background.radius, 0.0, "background[rx]")
    _expect_close(tile.radius, TILE_RADIUS, "brand tile[rx]")
    if background.fill != BACKGROUND_RGB:
        raise MasterError(
            f"background fill must be #{BACKGROUND_RGB[0]:02X}{BACKGROUND_RGB[1]:02X}"
            f"{BACKGROUND_RGB[2]:02X}, got {background.fill}"
        )
    if tile.fill != BRAND_RED_RGB:
        raise MasterError(f"brand tile fill must be {BRAND_RED_HEX}, got {tile.fill}")
    if glyph.fill != GLYPH_RGB:
        raise MasterError(f"glyph fill must be #FFFFFF, got {glyph.fill}")

    xs = [x for contour in glyph.contours for x, _ in contour]
    ys = [y for contour in glyph.contours for _, y in contour]
    if len(glyph.contours) != 3:
        raise MasterError(
            f"glyph must keep exactly three geometric blocks, found {len(glyph.contours)}"
        )
    for label, found, expected in (
        ("min x", min(xs), GLYPH_BBOX[0]),
        ("min y", min(ys), GLYPH_BBOX[1]),
        ("max x", max(xs), GLYPH_BBOX[2]),
        ("max y", max(ys), GLYPH_BBOX[3]),
    ):
        if abs(found - expected) > GLYPH_BBOX_TOLERANCE:
            raise MasterError(
                f"glyph {label} is {found:.3f}, expected {expected} "
                f"(+/-{GLYPH_BBOX_TOLERANCE})"
            )
    return Master(background=background, tile=tile, glyph=glyph)


# --------------------------------------------------------------------------- #
# Rendering
# --------------------------------------------------------------------------- #


def _supersample(size: int) -> int:
    if size <= 128:
        return 8
    if size <= 512:
        return 6
    return 4


def _glyph_mask(master: Master, pixels: int, scale: float) -> Image.Image:
    mask = Image.new("L", (pixels, pixels), 0)
    for contour in master.glyph.contours:
        contour_mask = Image.new("L", (pixels, pixels), 0)
        ImageDraw.Draw(contour_mask).polygon(
            [(x * scale, y * scale) for x, y in contour], fill=255
        )
        mask = ImageChops.lighter(mask, contour_mask)
    return mask


def render_artwork(master: Master, size: int) -> Image.Image:
    """Full logo (background + red tile + white glyph) as RGB."""

    supersample = _supersample(size)
    pixels = size * supersample
    scale = pixels / ARTBOARD
    image = Image.new("RGB", (pixels, pixels), master.background.fill)
    ImageDraw.Draw(image).rounded_rectangle(
        (0, 0, pixels - 1, pixels - 1),
        radius=master.tile.radius * scale,
        fill=master.tile.fill,
    )
    image.paste(master.glyph.fill, (0, 0), _glyph_mask(master, pixels, scale))
    return image.resize((size, size), Image.Resampling.LANCZOS)


def render_foreground(master: Master, size: int) -> Image.Image:
    """Adaptive-icon foreground: white glyph on transparency, nothing else."""

    supersample = _supersample(size)
    pixels = size * supersample
    scale = pixels / ARTBOARD
    alpha = _glyph_mask(master, pixels, scale).resize(
        (size, size), Image.Resampling.LANCZOS
    )
    image = Image.new("RGBA", (size, size), (*master.glyph.fill, 0))
    image.putalpha(alpha)
    return image


def _srgb_profile_bytes() -> bytes:
    """Byte-stable sRGB ICC profile for the colour-managed PNG outputs.

    lcms stamps the profile header date with the current time, so two renders of
    identical pixels would otherwise produce different PNG bytes and dirty the
    work tree on every run. Pin that header field to a constant.
    """

    profile = bytearray(
        ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    )
    # ICC header date/time: six big-endian uint16 at offsets 24..35.
    profile[24:36] = struct.pack(">6H", 2000, 1, 1, 0, 0, 0)
    return bytes(profile)


def _save_rgb(image: Image.Image, path: Path, *, srgb_profile: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    options = {"format": "PNG", "optimize": False}
    if srgb_profile:
        options["icc_profile"] = _srgb_profile_bytes()
    image.save(path, **options)


def _save_rgba(image: Image.Image, path: Path, *, srgb_profile: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    options = {"format": "PNG", "optimize": False}
    if srgb_profile:
        options["icc_profile"] = _srgb_profile_bytes()
    image.save(path, **options)


# --------------------------------------------------------------------------- #
# Writing
# --------------------------------------------------------------------------- #


def _render_cache(master: Master) -> dict[tuple[str, int], Image.Image]:
    cache: dict[tuple[str, int], Image.Image] = {}
    sizes = {CANONICAL_SIZE} | {target.size for target in ARTWORK_TARGETS}
    for size in sorted(sizes):
        cache[("artwork", size)] = render_artwork(master, size)
    for size in sorted({target.size for target in FOREGROUND_TARGETS} | {CANONICAL_SIZE}):
        cache[("foreground", size)] = render_foreground(master, size)
    return cache


def write_all(master: Master, cache: dict[tuple[str, int], Image.Image]) -> None:
    canonical_path = REPO_ROOT / CANONICAL_RELATIVE
    _save_rgb(
        cache[("artwork", CANONICAL_SIZE)],
        canonical_path,
        srgb_profile=True,
    )
    _save_rgba(
        cache[("foreground", CANONICAL_SIZE)],
        REPO_ROOT / FOREGROUND_RELATIVE,
        srgb_profile=True,
    )
    canonical_bytes = canonical_path.read_bytes()

    for target in ARTWORK_TARGETS:
        destination = REPO_ROOT / target.relative
        if target.relative in DUPLICATE_OF_CANONICAL:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(canonical_bytes)
            continue
        _save_rgb(
            cache[("artwork", target.size)],
            destination,
            srgb_profile=target.srgb_profile,
        )
    for target in FOREGROUND_TARGETS:
        _save_rgba(
            cache[("foreground", target.size)],
            REPO_ROOT / target.relative,
            srgb_profile=target.srgb_profile,
        )


# --------------------------------------------------------------------------- #
# Verification
# --------------------------------------------------------------------------- #


_PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def _png_stream_problem(path: Path) -> str | None:
    """Require a clean PNG chunk stream that stops exactly at IEND."""

    data = path.read_bytes()
    if not data.startswith(_PNG_SIGNATURE):
        return "not a PNG file"
    offset = len(_PNG_SIGNATURE)
    while offset + 8 <= len(data):
        length = int.from_bytes(data[offset : offset + 4], "big")
        chunk_type = data[offset + 4 : offset + 8]
        offset += 12 + length
        if chunk_type == b"IEND":
            if offset != len(data):
                return f"{len(data) - offset} unexpected byte(s) after IEND"
            return None
        if offset > len(data):
            return "truncated PNG chunk stream"
    return "PNG stream has no IEND chunk"


def _compare_pixels(path: Path, expected: Image.Image) -> str | None:
    if not path.is_file():
        return "missing"
    stream_problem = _png_stream_problem(path)
    if stream_problem:
        return stream_problem
    with Image.open(path) as handle:
        handle.load()
        actual = handle.copy()
    if actual.size != expected.size:
        return f"size {actual.size[0]}x{actual.size[1]} != {expected.size[0]}x{expected.size[1]}"
    if actual.mode != expected.mode:
        return f"mode {actual.mode} != {expected.mode}"
    difference = ImageChops.difference(actual, expected)
    box = difference.getbbox()
    if box is None:
        return None
    peak = max(channel[1] for channel in difference.getextrema())
    return f"pixels differ inside {box} (peak channel delta {peak})"


def _reference_problem() -> str | None:
    if not REFERENCE_PNG.is_file():
        return f"missing audited reference {REFERENCE_PNG.relative_to(REPO_ROOT)}"
    digest = hashlib.sha256(REFERENCE_PNG.read_bytes()).hexdigest()
    if digest != REFERENCE_SHA256:
        return (
            f"{REFERENCE_PNG.relative_to(REPO_ROOT)} sha256 is {digest}, "
            f"expected {REFERENCE_SHA256} (reference must stay untouched)"
        )
    return None


def _config_problems() -> list[str]:
    problems: list[str] = []
    if not PUBSPEC.is_file():
        return ["pubspec.yaml is missing"]
    pubspec = PUBSPEC.read_text(encoding="utf-8")
    for expected in (
        f'image_path: "{CANONICAL_RELATIVE}"',
        f'adaptive_icon_foreground: "{FOREGROUND_RELATIVE}"',
        f'adaptive_icon_background: "{BRAND_RED_HEX}"',
    ):
        if expected not in pubspec:
            problems.append(f"pubspec.yaml must declare {expected}")
    if "duoyi_logo_redesign_1024.png" in pubspec:
        problems.append(
            "pubspec.yaml still points flutter_launcher_icons at the retired "
            "duoyi_logo_redesign_1024.png artwork"
        )
    if not ANDROID_COLORS.is_file():
        problems.append("android/app/src/main/res/values/colors.xml is missing")
    else:
        colors = ANDROID_COLORS.read_text(encoding="utf-8")
        try:
            resources = ET.fromstring(colors)
        except ET.ParseError as error:
            problems.append(f"values/colors.xml is invalid XML: {error}")
        else:
            backgrounds = [
                (color.text or "").strip().upper()
                for color in resources.findall("color")
                if color.get("name") == "ic_launcher_background"
            ]
            if backgrounds != [BRAND_RED_HEX]:
                problems.append(
                    f"values/colors.xml must declare one ic_launcher_background {BRAND_RED_HEX}"
                )
        if "#FFC79A" in colors.upper():
            problems.append("values/colors.xml still carries the retired #FFC79A tile")
    return problems


def verify(
    master: Master, cache: dict[tuple[str, int], Image.Image]
) -> list[str]:
    problems: list[str] = []

    reference = _reference_problem()
    if reference:
        problems.append(reference)
    problems.extend(_config_problems())

    canonical_path = REPO_ROOT / CANONICAL_RELATIVE
    problem = _compare_pixels(canonical_path, cache[("artwork", CANONICAL_SIZE)])
    if problem:
        problems.append(f"{CANONICAL_RELATIVE}: {problem}")

    foreground_path = REPO_ROOT / FOREGROUND_RELATIVE
    problem = _compare_pixels(foreground_path, cache[("foreground", CANONICAL_SIZE)])
    if problem:
        problems.append(f"{FOREGROUND_RELATIVE}: {problem}")

    canonical_bytes = canonical_path.read_bytes() if canonical_path.is_file() else None
    for relative in DUPLICATE_OF_CANONICAL:
        path = REPO_ROOT / relative
        if canonical_bytes is None:
            problems.append(f"{relative}: canonical PNG is unavailable")
        elif not path.is_file():
            problems.append(f"{relative}: missing")
        elif path.read_bytes() != canonical_bytes:
            problems.append(f"{relative}: must be byte-identical to {CANONICAL_RELATIVE}")

    for target in ARTWORK_TARGETS:
        if target.relative in DUPLICATE_OF_CANONICAL:
            continue
        problem = _compare_pixels(
            REPO_ROOT / target.relative, cache[("artwork", target.size)]
        )
        if problem:
            problems.append(f"{target.relative}: {problem}")

    for target in FOREGROUND_TARGETS:
        problem = _compare_pixels(
            REPO_ROOT / target.relative, cache[("foreground", target.size)]
        )
        if problem:
            problems.append(f"{target.relative}: {problem}")

    return problems


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify every rendered icon without writing anything",
    )
    arguments = parser.parse_args(argv)

    try:
        master = load_master()
    except MasterError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    cache = _render_cache(master)
    if not arguments.check:
        write_all(master, cache)
        print(f"rendered {len(ARTWORK_TARGETS) + len(FOREGROUND_TARGETS) + 2} icon files")

    problems = verify(master, cache)
    if problems:
        print("icon verification failed:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    canonical = REPO_ROOT / CANONICAL_RELATIVE
    digest = hashlib.sha256(canonical.read_bytes()).hexdigest() if canonical.is_file() else "missing"
    checked = (
        len(ARTWORK_TARGETS)
        + len(FOREGROUND_TARGETS)
        + 2
    )
    print(f"ok: {checked} icon files match {CANONICAL_RELATIVE}")
    print(f"canonical sha256: {digest}")
    print(f"reference sha256: {REFERENCE_SHA256} (unchanged)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
