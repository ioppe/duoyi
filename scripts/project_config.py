#!/usr/bin/env python3
"""Inspect/export validated deployment values without starting the application."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import sys
import tempfile

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "backend"))
from deployment_config import ConfigurationError, load_deployment_config  # noqa: E402
LEGACY_ALIASES = {
    "DUOYI_PUBLIC_BASE": "DUOYI_SERVER_URL",
    "WEB_ROOT": "DUOYI_WEB_ROOT",
    "BACKUP_ROOT": "DUOYI_WEB_BACKUP_ROOT",
    "BASE_HREF": "DUOYI_WEB_BASE_HREF",
}


def write_json(path: Path, values: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as handle:
            temporary = Path(handle.name)
            json.dump(values, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def load_toolchain() -> dict[str, str]:
    try:
        values = json.loads((PROJECT_ROOT / "config/toolchain.json").read_text())
    except (OSError, ValueError) as error:
        raise ConfigurationError("config/toolchain.json must be readable JSON") from error
    if not isinstance(values, dict) or set(values) != {"flutter", "java", "python"}:
        raise ConfigurationError("Toolchain configuration requires flutter, java, and python")
    formats = {"flutter": r"[0-9]+\.[0-9]+\.[0-9]+", "java": r"[0-9]+", "python": r"3\.[0-9]+"}
    for key, pattern in formats.items():
        if not isinstance(values[key], str) or not re.fullmatch(pattern, values[key]):
            raise ConfigurationError(f"Invalid toolchain version: {key}")
    return values


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", help="Public JSON profile; defaults to DUOYI_CONFIG_FILE or config/deployment.json")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("validate", help="Validate public deployment and toolchain configuration")
    get = subparsers.add_parser("get", help="Print one normalized public value")
    get.add_argument("key")
    defines = subparsers.add_parser("client-defines", help="Export only allowlisted public Dart defines")
    defines.add_argument("--output", required=True, type=Path)
    subparsers.add_parser("shell", help="Emit safely quoted public exports for deployment scripts")
    workflow = subparsers.add_parser("workflow", help="Write public configuration to GitHub Actions outputs")
    workflow.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args(argv)
    try:
        environment = dict(os.environ)
        for alias, key in LEGACY_ALIASES.items():
            if alias in environment and key not in environment:
                environment[key] = environment[alias]
        config = load_deployment_config(arguments.config, environ=environment)
        if arguments.command == "validate":
            load_toolchain()
            print("Deployment and toolchain configuration are valid")
        elif arguments.command == "get":
            if arguments.key not in config.values:
                raise ConfigurationError("Unknown public configuration key")
            print(config.values[arguments.key])
        elif arguments.command == "client-defines":
            write_json(arguments.output, config.client_defines())
        elif arguments.command == "shell":
            exports = dict(config.values)
            for alias, key in LEGACY_ALIASES.items():
                exports[alias] = config.values[key]
            for key, value in exports.items():
                print(f"export {key}={shlex.quote(str(value))}")
        elif arguments.command == "workflow":
            toolchain = load_toolchain()
            outputs = {
                "profile": json.dumps(dict(config.values), separators=(",", ":")),
                **{f"{key}_version": value for key, value in toolchain.items()},
            }
            with arguments.output.open("a", encoding="utf-8") as handle:
                for key, value in outputs.items():
                    handle.write(f"{key}={value}\n")
        return 0
    except (ConfigurationError, OSError) as error:
        print(f"Configuration error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
