#!/usr/bin/env python3
"""Regenerate the checked-in Web startup subset (requires fonttools==4.59.2).

The normal Web build only copies this verified artifact and does not need
FontTools. Keep the original variable font and the native font manifest intact.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE = "assets/fonts/NotoSansSC-Variable.ttf"
SUBSET = "assets/fonts/NotoSansSC-Startup.ttf"
METADATA = "assets/fonts/web-startup-font.json"


def startup_codepoints(root: Path) -> set[int]:
    # GB2312 level 1: common user names/task text, not only fixed UI labels.
    codepoints = set()
    for high in range(0xB0, 0xD8):
        for low in range(0xA1, 0xFF):
            for character in bytes((high, low)).decode("gb2312", errors="ignore"):
                codepoints.add(ord(character))
    # All Chinese UI copy (including theme-specific copy), plus Latin and
    # punctuation. Unknown/rare characters retain CanvasKit's glyph fallback.
    for path in sorted((root / "lib").rglob("*")):
        if path.suffix in {".dart", ".arb"} and "generated" not in path.parts:
            codepoints.update(
                ord(character) for character in path.read_text(encoding="utf-8")
                if 0x3400 <= ord(character) <= 0x9FFF
            )
    for start, end in ((0x20, 0x7F), (0xA0, 0x100), (0x2000, 0x2070),
                       (0x3000, 0x3040), (0xFF00, 0xFFF0)):
        codepoints.update(range(start, end))
    return codepoints


def main() -> None:
    # Optional developer dependency, never required to build/run the app.
    import fontTools
    from fontTools import subset
    from fontTools.ttLib import TTFont

    source = PROJECT_ROOT / SOURCE
    target = PROJECT_ROOT / SUBSET
    font = TTFont(source, recalcTimestamp=False)
    codepoints = startup_codepoints(PROJECT_ROOT) & set(font.getBestCmap())
    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.notdef_glyph = True
    options.notdef_outline = True
    options.recommended_glyphs = True
    options.recalc_timestamp = False
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=codepoints)
    subsetter.subset(font)
    font.save(target)
    metadata = {
        "source": SOURCE,
        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "subset": SUBSET,
        "subset_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
        "subset_bytes": target.stat().st_size,
        "fonttools_version": fontTools.__version__,
        "coverage": "GB2312 level 1 + application CJK copy + Latin/punctuation",
        "codepoints": sorted(codepoints),
        "variable_axes": [axis.axisTag for axis in font["fvar"].axes],
    }
    (PROJECT_ROOT / METADATA).write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Web startup font: {len(codepoints)} characters, {target.stat().st_size} bytes")


if __name__ == "__main__":
    main()
