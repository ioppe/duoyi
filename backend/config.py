"""Typed backend configuration. Importing this module never opens a database.

Precedence is process environment, private .env, public deployment defaults, then
schema defaults. Alias order is preserved within each source. Values from .env
are data only: they are never executed, interpolated, or added to os.environ.
"""

from dataclasses import dataclass, field, replace
from contextlib import closing
import base64
import os
from pathlib import Path
import re
import sqlite3
from types import MappingProxyType
from typing import Mapping
from urllib.parse import urlsplit

if __package__:
    from .deployment_config import ConfigurationError, load_deployment_config
else:
    from deployment_config import ConfigurationError, load_deployment_config


# Existing password hashes depend on this value. Deployments must keep their
# original PASSWORD_HASH_SALT across upgrades; changing it invalidates passwords.
LEGACY_PASSWORD_HASH_SALT = "duoyi_2026"


def _invalid(key: str, requirement: str) -> ConfigurationError:
    # Never include raw values, file contents, or underlying exception messages.
    return ConfigurationError(f"{key}: {requirement}")


def read_env_file(path: Path) -> dict[str, str]:
    """Read strict KEY=value lines, optionally enclosed in matching quotes."""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError):
        raise _invalid("DUOYI_ENV_FILE", "cannot read environment file") from None
    values = {}
    for line_number, line in enumerate(lines, 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, raw = line.partition("=")
        key = key.strip()
        if not separator or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
            raise _invalid("DUOYI_ENV_FILE", f"invalid assignment on line {line_number}")
        if key in values:
            raise _invalid(key, f"duplicate assignment on line {line_number}")
        value = raw.strip()
        if value.startswith(("'", '"')):
            if len(value) < 2 or value[-1] != value[0] or value[0] in value[1:-1]:
                raise _invalid(key, f"invalid quoted value on line {line_number}")
            value = value[1:-1]
        if "\x00" in value:
            raise _invalid(key, "must not contain a NUL character")
        values[key] = value
    return values


@dataclass(frozen=True, repr=False)
class Environment:
    """A private snapshot with source precedence before alias precedence."""

    layers: tuple[Mapping[str, object], ...] = field(repr=False)

    def _select(self, names: tuple[str, ...], default: object) -> tuple[str, object]:
        for layer in self.layers:
            for name in names:
                if name in layer:
                    return name, layer[name]
        return names[0], default

    def present(self, *names: str) -> bool:
        return any(name in layer for layer in self.layers for name in names)

    def text(self, *names: str, default: str = "") -> str:
        key, value = self._select(names, default)
        if not isinstance(value, str) or "\x00" in value or "\r" in value or "\n" in value:
            raise _invalid(key, "expected a single line string")
        return value

    def boolean(self, *names: str, default: bool = False) -> bool:
        key, raw = self._select(names, default)
        if isinstance(raw, bool):
            return raw
        value = str(raw).strip().lower()
        if value in {"1", "true", "yes", "on"}:
            return True
        if value in {"0", "false", "no", "off"}:
            return False
        raise _invalid(key, "expected a boolean")

    def integer(
        self, *names: str, default: int, minimum: int = 0, maximum: int = 2147483647
    ) -> int:
        key, raw = self._select(names, default)
        if isinstance(raw, bool) or not re.fullmatch(r"[+-]?\d+", str(raw).strip()):
            raise _invalid(key, "expected an integer")
        try:
            value = int(raw)
        except (TypeError, ValueError, OverflowError):
            raise _invalid(key, "expected an integer") from None
        if not minimum <= value <= maximum:
            raise _invalid(key, f"must be between {minimum} and {maximum}")
        return value

    def smtp_use_ssl(self, port: int, *names: str) -> bool:
        return self.boolean(*names, default=port == 465)

    def choice(self, *names: str, default: str, choices: set[str]) -> str:
        key, _ = self._select(names, default)
        value = self.text(*names, default=default).strip().lower()
        if value not in choices:
            raise _invalid(key, "unsupported choice")
        return value

    def url(self, *names: str, default: str = "") -> str:
        key, _ = self._select(names, default)
        value = self.text(*names, default=default).strip()
        if value:
            _validate_http_url(key, value)
        return value.rstrip("/")


def _validate_http_url(key: str, value: str, *, origin: bool = False) -> None:
    try:
        parsed = urlsplit(value)
        valid = (
            parsed.scheme in {"http", "https"}
            and parsed.hostname
            and parsed.username is None
            and parsed.password is None
            and not parsed.query
            and not parsed.fragment
            and not any(character.isspace() for character in value)
            and (not origin or parsed.path in {"", "/"})
        )
        port = parsed.port
        if not valid or (port is not None and not 1 <= port <= 65535):
            raise ValueError
    except ValueError:
        raise _invalid(key, "expected an HTTP(S) origin" if origin else "expected an HTTP(S) URL") from None


def _cors_origins(environment: Environment) -> tuple[str, ...]:
    key, raw = environment._select(("CORS_ORIGINS",), "")
    if isinstance(raw, (list, tuple)):
        origins = list(raw)
    elif isinstance(raw, str):
        origins = [] if not raw.strip() else raw.split(",")
    else:
        raise _invalid(key, "expected comma separated origins")
    normalized = []
    for item in origins:
        if not isinstance(item, str) or not item.strip():
            raise _invalid(key, "expected HTTP(S) origins")
        item = item.strip()
        if item != "*":
            _validate_http_url(key, item, origin=True)
            item = item.rstrip("/")
        if item not in normalized:
            normalized.append(item)
    if "*" in normalized and len(normalized) > 1:
        raise _invalid(key, "wildcard must be used alone")
    return tuple(normalized)


def _legacy_db_filename() -> str:
    return base64.b64decode("ZmluZ2VydGlwX3RpbWUuZGI=").decode()


def _db_counts(path: str) -> tuple[int, int]:
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        return (0, 0)
    try:
        # Read only: selecting the legacy database must never create a file.
        with closing(sqlite3.connect(Path(path).resolve().as_uri() + "?mode=ro", uri=True)) as conn:
            tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            return tuple(
                int(conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0])
                if table in tables else 0
                for table in ("users", "feedback")
            )
    except sqlite3.DatabaseError:
        return (0, 0)


def _default_db_path(base_dir: Path | None = None) -> str:
    base_dir = Path(base_dir) if base_dir is not None else Path(__file__).resolve().parent
    current = base_dir / "duoyi.db"
    legacy = base_dir / _legacy_db_filename()
    if current.exists() and legacy.exists():
        current_users, current_feedback = _db_counts(str(current))
        legacy_users, legacy_feedback = _db_counts(str(legacy))
        if legacy_feedback > current_feedback or (current_users <= 1 and legacy_users > current_users):
            return str(legacy)
        return str(current)
    return str(current if current.exists() or not legacy.exists() else legacy)


def _pubspec_app_version(path: Path | None = None) -> tuple[str, int]:
    path = path if path is not None else Path(__file__).resolve().parents[1] / "pubspec.yaml"
    try:
        match = re.search(r"^version:\s*([^\s+]+)(?:\+(\d+))?", path.read_text(encoding="utf-8"), re.M)
        if match:
            return match.group(1), int(match.group(2) or "0")
    except (OSError, UnicodeError, ValueError):
        pass
    return "0.0.0", 0


@dataclass(frozen=True)
class BackendSettings:
    environment: Environment = field(repr=False)
    env_file: Path | None
    public_source: Path | None
    db_path: str
    backup_dir: str
    avatar_upload_dir: str
    cors_origins: tuple[str, ...]
    admin_bootstrap_user: str
    admin_bootstrap_password: str = field(repr=False)
    password_hash_salt: str = field(repr=False)
    session_online_seconds: int
    focus_room_online_seconds: int
    focus_room_max_weekly_seconds: int
    focus_room_max_session_count: int
    focus_room_heartbeat_throttle_seconds: int
    focus_room_session_jump_window_seconds: int
    focus_room_max_session_count_jump: int
    focus_friend_request_limit_per_day: int
    email_title: str
    email_sender_name: str
    resend_from: str
    app_current_version: str
    app_current_version_code: int
    app_package_name: str
    app_update_repository: str
    app_update_default_notes: str
    mobile_apk_dir: str
    openclaw_mail_script: str
    openclaw_node_bin: str
    reminder_email_poll_seconds: int
    build_git_sha: str
    build_time: str
    initial_settings: Mapping[str, object] = field(default_factory=dict, repr=False)


def load_settings(
    environ: Mapping[str, str] | None = None,
    *,
    env_file: str | Path | None = None,
    deployment_file: str | Path | None = None,
    backend_dir: Path | None = None,
    pubspec_path: Path | None = None,
) -> BackendSettings:
    base_dir = Path(backend_dir) if backend_dir is not None else Path(__file__).resolve().parent
    process = dict(os.environ if environ is None else environ)
    explicit_env_file = env_file is not None or "DUOYI_ENV_FILE" in process
    selected_env_file = env_file if env_file is not None else process.get("DUOYI_ENV_FILE", base_dir / ".env")
    private_path = Path(selected_env_file) if selected_env_file else None
    if private_path is not None and not private_path.is_file():
        if explicit_env_file:
            raise _invalid("DUOYI_ENV_FILE", "environment file does not exist")
        private_path = None
    private = read_env_file(private_path) if private_path is not None else {}
    merged = {**private, **process}
    public = load_deployment_config(path=deployment_file, environ=merged)
    environment = Environment(tuple(MappingProxyType(layer) for layer in (process, private, public.backend_defaults())))
    text = environment.text

    def required(*names: str, default: str = "") -> str:
        value = text(*names, default=default).strip()
        if not value:
            raise _invalid(names[0], "must not be empty")
        return value

    default_version, default_code = _pubspec_app_version(pubspec_path)
    version = required("APP_CURRENT_VERSION", "DUOYI_APP_VERSION", default=default_version)
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?", version):
        raise _invalid("APP_CURRENT_VERSION", "expected a semantic version")
    repository = text("APP_UPDATE_REPOSITORY", "DUOYI_UPDATE_REPOSITORY").strip()
    if repository and (
        not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository)
        or any(part in {".", ".."} for part in repository.split("/"))
    ):
        raise _invalid("APP_UPDATE_REPOSITORY", "expected owner/repository")
    title = text("DUOYI_TITLE", "EMAIL_TITLE", "APP_TITLE", default="多仪") or "多仪"
    salt = text("PASSWORD_HASH_SALT", default=LEGACY_PASSWORD_HASH_SALT)
    if not salt:
        raise _invalid("PASSWORD_HASH_SALT", "must not be empty")
    settings = BackendSettings(
        environment=environment,
        env_file=private_path,
        public_source=public.source,
        db_path=required("DUOYI_DB_PATH", default=_default_db_path(base_dir) if not environment.present("DUOYI_DB_PATH") else ""),
        backup_dir=required("SERVER_BACKUP_DIR", default=str(base_dir / "backups")),
        avatar_upload_dir=required("DUOYI_AVATAR_UPLOAD_DIR", default=str(base_dir / "uploads" / "avatars")),
        cors_origins=_cors_origins(environment),
        admin_bootstrap_user=required("ADMIN_BOOTSTRAP_USER", default="admin"),
        admin_bootstrap_password=text("ADMIN_BOOTSTRAP_PASSWORD"),
        password_hash_salt=salt,
        session_online_seconds=environment.integer("SESSION_ONLINE_SECONDS", default=300, minimum=1, maximum=604800),
        focus_room_online_seconds=environment.integer("FOCUS_ROOM_ONLINE_SECONDS", default=180, minimum=1, maximum=604800),
        focus_room_max_weekly_seconds=environment.integer("FOCUS_ROOM_MAX_WEEKLY_SECONDS", default=12 * 60 * 60 * 7, minimum=1, maximum=604800),
        focus_room_max_session_count=environment.integer("FOCUS_ROOM_MAX_SESSION_COUNT", default=1000, minimum=1, maximum=1000000),
        focus_room_heartbeat_throttle_seconds=environment.integer("FOCUS_ROOM_HEARTBEAT_THROTTLE_SECONDS", default=10, minimum=1, maximum=3600),
        focus_room_session_jump_window_seconds=environment.integer("FOCUS_ROOM_SESSION_JUMP_WINDOW_SECONDS", default=5 * 60, minimum=1, maximum=86400),
        focus_room_max_session_count_jump=environment.integer("FOCUS_ROOM_MAX_SESSION_COUNT_JUMP", default=20, minimum=1, maximum=1000000),
        focus_friend_request_limit_per_day=environment.integer("FOCUS_FRIEND_REQUEST_LIMIT_PER_DAY", default=20, minimum=1, maximum=1000000),
        email_title=title,
        email_sender_name=text("EMAIL_SENDER_NAME", "EMAIL_FROM_NAME", "MAIL_FROM_NAME", "SENDER_NAME", default=title),
        resend_from=text("RESEND_FROM", "EMAIL_FROM", "MAIL_FROM"),
        app_current_version=version,
        app_current_version_code=environment.integer("APP_CURRENT_VERSION_CODE", "DUOYI_APP_VERSION_CODE", default=default_code),
        app_package_name=required("APP_PACKAGE_NAME", default="com.duoyi.duoyi"),
        app_update_repository=repository,
        app_update_default_notes=text("APP_UPDATE_DEFAULT_NOTES", default="包含最新修复与体验优化。"),
        mobile_apk_dir=required("DUOYI_MOBILE_APK_DIR", default=str(base_dir / "mobile_apps")),
        openclaw_mail_script=text("OPENCLAW_MAIL_SCRIPT"),
        openclaw_node_bin=required("OPENCLAW_MAIL_NODE", "OPENCLAW_NODE_BIN", "NODE_BIN", default="node"),
        reminder_email_poll_seconds=environment.integer("REMINDER_EMAIL_POLL_SECONDS", default=60, minimum=1, maximum=86400),
        build_git_sha=text("GIT_SHA", "BUILD_GIT_SHA"),
        build_time=text("BUILD_TIME"),
    )
    # Validate the first-run defaults at the same boundary as startup settings.
    if __package__:
        from .settings_defaults import build_settings_defaults
    else:
        from settings_defaults import build_settings_defaults
    return replace(settings, initial_settings=MappingProxyType(build_settings_defaults(settings)))
