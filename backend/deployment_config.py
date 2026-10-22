"""Validated public deployment configuration shared by build tools and backend.

This module has no application/database side effects and never loads secrets.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
import os
import posixpath
from pathlib import Path
import re
from types import MappingProxyType
from typing import Any, Mapping
from urllib.parse import urlsplit


class ConfigurationError(ValueError):
    """A configuration key is missing, unknown, or has an invalid value."""


DEFAULT_CONFIG_FILE = Path(__file__).resolve().parents[1] / "config" / "deployment.json"
DEFAULTS: dict[str, str | int] = {
    "DUOYI_SERVER_URL": "",
    "DUOYI_UPDATE_REPOSITORY": "",
    "DUOYI_HTTP_TIMEOUT_SECONDS": 12,
    "DUOYI_AI_TIMEOUT_SECONDS": 180,
    "DUOYI_UPDATE_TIMEOUT_SECONDS": 8,
    "DUOYI_WEB_TARGET": "responsive",
    "DUOYI_WEB_BASE_HREF": "/",
    "DUOYI_FILE_TIMEOUT_SECONDS": 30,
    "DUOYI_BACKEND_SERVICE": "",
    "DUOYI_BACKEND_RUNNER": "systemd",
    "DUOYI_LOCAL_BASE": "",
    "DUOYI_WEB_ROOT": "",
    "DUOYI_WEB_BACKUP_ROOT": "",
}
CLIENT_KEYS = (
    "DUOYI_SERVER_URL",
    "DUOYI_UPDATE_REPOSITORY",
    "DUOYI_HTTP_TIMEOUT_SECONDS",
    "DUOYI_FILE_TIMEOUT_SECONDS",
    "DUOYI_AI_TIMEOUT_SECONDS",
    "DUOYI_UPDATE_TIMEOUT_SECONDS",
    "DUOYI_WEB_TARGET",
)
TIMEOUT_KEYS = frozenset(key for key in DEFAULTS if key.endswith("_TIMEOUT_SECONDS"))


def _string(key: str, value: Any) -> str:
    if not isinstance(value, str):
        raise ConfigurationError(f"{key} must be a string")
    return value.strip()


def _url(key: str, value: Any) -> str:
    text = _string(key, value)
    if not text:
        return ""
    try:
        parsed = urlsplit(text)
        port = parsed.port
        valid = (
            parsed.scheme in {"http", "https"}
            and parsed.hostname
            and not parsed.username
            and not parsed.password
            and "?" not in text
            and "#" not in text
            and not parsed.query
            and not parsed.fragment
            and not re.search(r"\s", text)
            and (port is None or 1 <= port <= 65535)
        )
    except ValueError:
        valid = False
    if not valid:
        raise ConfigurationError(f"{key} must be an HTTP(S) URL without credentials, query, or fragment")
    return text.rstrip("/")


def _positive_seconds(key: str, value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, str)):
        raise ConfigurationError(f"{key} must be an integer between 1 and 3600")
    if isinstance(value, str) and not re.fullmatch(r"[0-9]+", value.strip()):
        raise ConfigurationError(f"{key} must be an integer between 1 and 3600")
    number = int(value)
    if not 1 <= number <= 3600:
        raise ConfigurationError(f"{key} must be an integer between 1 and 3600")
    return number


def _normalize(key: str, value: Any) -> str | int:
    if key in TIMEOUT_KEYS:
        return _positive_seconds(key, value)
    if key in {"DUOYI_SERVER_URL", "DUOYI_LOCAL_BASE"}:
        return _url(key, value)
    text = _string(key, value)
    if key == "DUOYI_UPDATE_REPOSITORY":
        if text and (not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", text) or any(part in {".", ".."} for part in text.split("/"))):
            raise ConfigurationError(f"{key} must use owner/repository")
    elif key == "DUOYI_WEB_TARGET":
        if text not in {"responsive", "desktop", "mobile"}:
            raise ConfigurationError(f"{key} must be responsive, desktop, or mobile")
    elif key == "DUOYI_WEB_BASE_HREF":
        if not text.startswith("/") or not text.endswith("/") or any(char in text for char in ("?", "#", "\\")) or re.search(r"\s", text) or any(part in {".", ".."} for part in text.split("/")):
            raise ConfigurationError(f"{key} must be an absolute URL path starting and ending with /")
    elif key == "DUOYI_BACKEND_SERVICE":
        if text and not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9@_.-]*", text):
            raise ConfigurationError(f"{key} must be a backend service or container name")
    elif key == "DUOYI_BACKEND_RUNNER":
        if text not in {"systemd", "docker"}:
            raise ConfigurationError(f"{key} must be systemd or docker")
    elif key in {"DUOYI_WEB_ROOT", "DUOYI_WEB_BACKUP_ROOT"}:
        if text and (not text.startswith("/") or ".." in text.split("/") or "\x00" in text):
            raise ConfigurationError(f"{key} must be an absolute deployment path")
        if text:
            text = "/" + posixpath.normpath(text).lstrip("/")
        if text in {"/", "/var", "/var/www", "/opt", "/home"}:
            raise ConfigurationError(f"{key} must name a dedicated application directory")
    return text


def _unique_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ConfigurationError(f"Duplicate configuration key: {key}")
        result[key] = value
    return result


@dataclass(frozen=True)
class DeploymentConfig:
    values: Mapping[str, str | int]
    source: Path | None

    def client_defines(self) -> dict[str, str]:
        return {key: str(self.values[key]) for key in CLIENT_KEYS}

    def backend_defaults(self) -> dict[str, str]:
        result = {}
        repository = str(self.values["DUOYI_UPDATE_REPOSITORY"])
        server_url = str(self.values["DUOYI_SERVER_URL"])
        if repository:
            result["APP_UPDATE_REPOSITORY"] = repository
        if server_url:
            parsed = urlsplit(server_url)
            result["CORS_ORIGINS"] = f"{parsed.scheme}://{parsed.netloc}"
        return result


def load_deployment_config(
    path: str | Path | None = None,
    environ: Mapping[str, str] | None = None,
) -> DeploymentConfig:
    """Load neutral defaults < selected JSON profile < explicit public env keys.

    An explicitly selected missing profile is an error. An absent conventional
    profile is allowed for standalone backends and unconfigured offline builds.
    """
    environment = os.environ if environ is None else environ
    explicit = path is not None or "DUOYI_CONFIG_FILE" in environment
    selected = path if path is not None else environment.get("DUOYI_CONFIG_FILE", DEFAULT_CONFIG_FILE)
    if not str(selected).strip():
        raise ConfigurationError("DUOYI_CONFIG_FILE must name a JSON file")
    source = Path(selected).expanduser().resolve()
    raw: dict[str, Any] = dict(DEFAULTS)
    if source.is_file():
        try:
            if source.stat().st_size > 1024 * 1024:
                raise ConfigurationError("DUOYI_CONFIG_FILE exceeds the configuration size limit")
            loaded = json.loads(source.read_text(encoding="utf-8"), object_pairs_hook=_unique_keys)
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            raise ConfigurationError("DUOYI_CONFIG_FILE must be a readable UTF-8 JSON object") from error
        if not isinstance(loaded, dict):
            raise ConfigurationError("DUOYI_CONFIG_FILE must contain a JSON object")
        unknown = set(loaded) - set(DEFAULTS)
        if unknown:
            raise ConfigurationError("Unknown public configuration key(s); secrets belong in the backend environment: " + ", ".join(sorted(unknown)))
        raw.update(loaded)
    elif explicit:
        raise ConfigurationError("DUOYI_CONFIG_FILE does not exist or is not a regular file")
    else:
        source = None
    for key in DEFAULTS:
        if key in environment:
            raw[key] = environment[key]
    normalized = {key: _normalize(key, value) for key, value in raw.items()}
    return DeploymentConfig(MappingProxyType(normalized), source)
