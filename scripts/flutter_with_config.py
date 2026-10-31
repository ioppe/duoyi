#!/usr/bin/env python3
"""Run Flutter using validated, public deployment configuration."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

from project_config import PROJECT_ROOT, ConfigurationError, load_deployment_config, write_json


def build_command(flutter: str, arguments: list[str], defines_file: Path, values: dict) -> list[str]:
    if not arguments:
        raise ConfigurationError("A Flutter command is required")
    inject = arguments[0] in {"run", "test", "build"}
    if not inject:
        return [flutter, *arguments]
    prefix = 2 if arguments[0] == "build" else 1
    if len(arguments) < prefix:
        raise ConfigurationError("A Flutter build target is required")
    flags = [f"--dart-define-from-file={defines_file}"]
    if arguments[:2] == ["build", "web"]:
        has_base = any(value == "--base-href" or value.startswith("--base-href=") for value in arguments)
        if not has_base:
            flags.append(f"--base-href={values['DUOYI_WEB_BASE_HREF']}")
    return [flutter, *arguments[:prefix], *flags, *arguments[prefix:]]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", help="Public deployment JSON profile")
    parser.add_argument("--flutter-bin", default=os.environ.get("FLUTTER_BIN", "flutter"))
    parser.add_argument("--dry-run", action="store_true", help="Show the command and public defines without writing or executing")
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    arguments = args.arguments[1:] if args.arguments[:1] == ["--"] else args.arguments
    try:
        config = load_deployment_config(args.config)
        defines_file = PROJECT_ROOT / "build/config/client-defines.json"
        command = build_command(args.flutter_bin, arguments, defines_file, dict(config.values))
        if args.dry_run:
            print(json.dumps({"command": command, "public_defines": config.client_defines()}, ensure_ascii=False))
            return 0
        if shutil.which(args.flutter_bin) is None:
            raise ConfigurationError("Flutter executable not found; install the pinned toolchain or set FLUTTER_BIN")
        if arguments[0] in {"run", "test", "build"}:
            write_json(defines_file, config.client_defines())
        result = subprocess.run(command, cwd=PROJECT_ROOT).returncode
        if result == 0 and arguments[:2] == ["build", "web"]:
            from prepare_web_fonts import prepare_web_fonts, web_output_directory
            prepare_web_fonts(PROJECT_ROOT, web_output_directory(arguments, PROJECT_ROOT))
        return result
    except (ConfigurationError, OSError, ValueError) as error:
        print(f"Configuration error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
