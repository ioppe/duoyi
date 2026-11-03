#!/usr/bin/env python3
"""Prepare a non-blocking Web font manifest after a successful Flutter build."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct

FULL_ASSET = "assets/fonts/NotoSansSC-Variable.ttf"
STARTUP_ASSET = "assets/fonts/NotoSansSC-Startup.ttf"
LICENSE_ASSET = "assets/fonts/NotoSansSC-OFL.txt"
METADATA = "assets/fonts/web-startup-font.json"
FAMILY = "NotoSansSC"


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _require_variable_font(path: Path) -> None:
    data = path.read_bytes()
    if len(data) < 12:
        raise ValueError(f"Invalid font: {path.name}")
    table_count = struct.unpack_from(">H", data, 4)[0]
    tags = {data[12 + i * 16:16 + i * 16] for i in range(table_count)}
    if b"fvar" not in tags or not ({b"glyf", b"CFF2"} & tags):
        raise ValueError(f"Startup font must retain variable outlines: {path.name}")


def prepare_web_fonts(project_root: Path, build_dir: Path) -> dict:
    """Keep native pubspec registrations intact; change only generated Web assets.

    The original full font remains available to rootBundle for the one-shot
    post-frame loader, but never appears in the startup FontManifest.
    """
    metadata = json.loads((project_root / METADATA).read_text(encoding="utf-8"))
    source = project_root / FULL_ASSET
    startup = project_root / STARTUP_ASSET
    if _sha(source) != metadata["source_sha256"]:
        raise ValueError("Full font changed; regenerate the Web startup font")
    if _sha(startup) != metadata["subset_sha256"]:
        raise ValueError("Web startup font does not match its checked-in hash")
    if startup.stat().st_size > 3_000_000:
        raise ValueError("Web startup font exceeds the 3 MB uncompressed budget")
    _require_variable_font(startup)

    assets = build_dir / "assets"
    manifest_path = assets / "FontManifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    matches = [entry for entry in manifest if entry.get("family") == FAMILY]
    if len(matches) != 1:
        raise ValueError("Expected exactly one NotoSansSC family in the Web manifest")
    family = matches[0]
    registered = family.get("fonts", [])
    if not registered or any(font.get("asset") not in {FULL_ASSET, STARTUP_ASSET}
                             for font in registered):
        raise ValueError("Unexpected NotoSansSC registration; review Web font policy")
    if _sha(assets / FULL_ASSET) != metadata["source_sha256"]:
        raise ValueError("Web build is missing the expected complete font asset")

    (assets / STARTUP_ASSET).parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(startup, assets / STARTUP_ASSET)
    shutil.copyfile(project_root / LICENSE_ASSET, assets / LICENSE_ASSET)
    # CanvasKit derives wght from TextStyle.fontWeight for a variable font. A
    # single entry avoids fetching the same complete file for each weight.
    family["fonts"] = [{"asset": STARTUP_ASSET}]
    manifest_path.write_text(json.dumps(manifest, separators=(",", ":")) + "\n",
                             encoding="utf-8")
    result = {
        "family": FAMILY,
        "startup_asset": STARTUP_ASSET,
        "startup_bytes": startup.stat().st_size,
        "startup_sha256": metadata["subset_sha256"],
        "complete_asset": FULL_ASSET,
        "complete_bytes": source.stat().st_size,
        "complete_loading": "post-first-frame-idle",
        "native_font_manifest_changed": False,
    }
    (assets / "web-font-policy.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Web font startup: {result['startup_bytes']} bytes (complete font deferred)")
    return result


def web_output_directory(arguments: list[str], project_root: Path) -> Path:
    for index, argument in enumerate(arguments):
        if argument.startswith(("--output=", "-o=")):
            output = argument.split("=", 1)[1]
            return (project_root / output).resolve()
        if argument in {"--output", "-o"}:
            if index + 1 == len(arguments):
                raise ValueError("Missing Web output directory")
            return (project_root / arguments[index + 1]).resolve()
    return (project_root / "build/web").resolve()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build_dir", type=Path, nargs="?", default=Path("build/web"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    prepare_web_fonts(root, root / args.build_dir)


if __name__ == "__main__":
    main()
