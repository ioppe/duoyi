#!/usr/bin/env python3
"""Compatibility entry point for the single brand-asset generator.

This script used to render every icon from its own second brand source
(``assets/logo/duoyi_unified_logo.svg``) with ``rsvg-convert``. That produced a
different palette (``#C95455``) and approximated geometry, so it has been
retired: ``assets/logo/duoyi_app_logo.svg`` is the only approved master, and
``scripts/sync_app_icons.py`` is the only renderer. This module now just
delegates to it, keeping older tooling and docs that call
``scripts/generate_brand_assets.py`` working with the approved artwork.

Usage::

    python3 scripts/generate_brand_assets.py            # render and write
    python3 scripts/generate_brand_assets.py --check    # verify, exit 1 on drift
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import sync_app_icons  # noqa: E402  (path set up above)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the derived assets without writing anything",
    )
    arguments = parser.parse_args(argv)
    forwarded = ["--check"] if arguments.check else []
    return sync_app_icons.main(forwarded)


if __name__ == "__main__":
    sys.exit(main())
