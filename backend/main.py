from fastapi import FastAPI, HTTPException, Depends, Header, Query, WebSocket, WebSocketDisconnect, UploadFile, File, Request, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, FileResponse
from pydantic import AliasChoices, BaseModel, ConfigDict, Field, field_validator
from typing import Iterable, Optional
import asyncio
import base64
import csv
import io
import sqlite3
import hashlib
import html
import secrets
import json
import os
import re
import shutil
import smtplib
import subprocess
import urllib.parse
import urllib.error
import urllib.request
import zipfile
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage
from email.utils import formataddr
from pathlib import Path

if __package__:
    from .config import (
        ConfigurationError, load_settings, _db_counts, _default_db_path,
        _legacy_db_filename, _pubspec_app_version,
    )
    from .settings_defaults import DEFAULT_AI_BASE_URL, DEFAULT_AI_MODEL, build_settings_defaults
else:
    from config import (
        ConfigurationError, load_settings, _db_counts, _default_db_path,
        _legacy_db_filename, _pubspec_app_version,
    )
    from settings_defaults import DEFAULT_AI_BASE_URL, DEFAULT_AI_MODEL, build_settings_defaults

SETTINGS = load_settings()
BUILD_GIT_SHA = SETTINGS.build_git_sha
BUILD_TIME = SETTINGS.build_time
OPENCLAW_MAIL_SCRIPT = SETTINGS.openclaw_mail_script
OPENCLAW_NODE_BIN = SETTINGS.openclaw_node_bin
REMINDER_EMAIL_POLL_SECONDS = SETTINGS.reminder_email_poll_seconds

app = FastAPI(title="多仪 Sync API", version="3.1.0")

API_CONTRACT_VERSION = "2026-06-01.7"
API_CONTRACT_FEATURES = {
    "email_code": True,
    "email_code_login_gating": True,
    "email_bind": True,
    "registration_email_availability": True,
    "avatar_upload": True,
    "avatar_read": True,
    "profile_update": True,
    "password_change": True,
    "auth_session": True,
    "persistent_login_sessions": True,
    "access_tokens": True,
    "admin_coins": True,
    "admin_groups": True,
    "admin_ai_healthcheck": True,
    "mobile_update": True,
    "focus_rooms": True,
    "focus_room_realtime": True,
    "theme_shop": True,
    "list_groups": True,
}
API_CONTRACT_REQUIRED_ROUTES = [
    "GET /api/config",
    "GET /api/health",
    "POST /api/auth/register",
    "POST /api/auth/login",
    "GET /api/auth/me",
    "GET /api/me",
    "POST /api/auth/logout",
    "GET /api/auth/tokens",
    "POST /api/auth/tokens",
    "DELETE /api/auth/tokens/{token_id}",
    "GET /api/mobile/apps/duoyi/update",
    "POST /api/auth/email-code",
    "POST /api/auth/email-login",
    "PATCH /api/me/profile",
    "POST /api/me/avatar",
    "GET /api/uploads/avatars/{filename}",
    "POST /api/me/email-code",
    "POST /api/me/email",
    "PATCH /api/me/email",
    "POST /api/me/password",
    "POST /api/auth/change-password",
    "POST /api/theme-shop/apply",
    "POST /api/admin/users/{user_id}/coins",
    "PATCH /api/admin/users/{user_id}/coins",
    "GET /api/admin/users",
    "POST /api/admin/users",
    "PATCH /api/admin/users/{user_id}",
    "PUT /api/admin/users/{user_id}",
    "DELETE /api/admin/users/{user_id}",
    "GET /api/admin/groups",
    "POST /api/admin/groups",
    "PATCH /api/admin/groups/{group_id}",
    "DELETE /api/admin/groups/{group_id}",
    "GET /api/admin/userGroups",
    "POST /api/admin/userGroups",
    "PATCH /api/admin/userGroups/{group_id}",
    "DELETE /api/admin/userGroups/{group_id}",
    "GET /api/admin/feedback",
    "GET /api/admin/feedback/{fb_id}",
    "POST /api/admin/feedback/reply",
    "POST /api/admin/feedback/bulk-status",
    "DELETE /api/admin/feedback/{fb_id}",
    "POST /api/admin/provider-healthcheck",
    "POST /api/focus-rooms/{room_id}/heartbeat",
    "GET /api/focus-rooms/{room_id}/ranking",
    "GET /api/focus-rooms/{room_id}/events",
    "WS /ws/focus-rooms/{room_id}/events",
    "POST /api/focus-rooms/{room_id}/leave",
    "POST /api/focus-rooms/{room_id}/invites",
    "GET /api/focus-rooms/{room_id}/invites",
    "DELETE /api/focus-room-invites/{invite_id}",
    "POST /api/focus-room-invites/{code}/accept",
    "GET /api/focus-friends",
    "GET /api/focus-friends/requests",
    "POST /api/focus-friends",
    "DELETE /api/focus-friends/{friend_user_id}",
    "POST /api/focus-friend-requests/{requester_user_id}/accept",
    "POST /api/focus-friend-requests/{requester_user_id}/reject",
    "DELETE /api/focus-friend-requests/{friend_user_id}",
    "GET /api/focus-leaderboard/friends",
    "GET /api/focus-leaderboard/global",
    "GET /api/focus-leaderboard/global/events",
    "WS /ws/focus-leaderboard/global/events",
]
API_CONTRACT_ROUTES_HASH = hashlib.sha256(
    "\n".join(API_CONTRACT_REQUIRED_ROUTES).encode("utf-8")
).hexdigest()[:16]


def _api_contract_payload() -> dict:
    return {
        "api_contract_version": API_CONTRACT_VERSION,
        "build_git_sha": BUILD_GIT_SHA,
        "build_time": BUILD_TIME,
        "required_routes_hash": API_CONTRACT_ROUTES_HASH,
        "required_routes": API_CONTRACT_REQUIRED_ROUTES,
        "features": API_CONTRACT_FEATURES,
    }


app.add_middleware(
    CORSMiddleware,
    allow_origins=list(SETTINGS.cors_origins),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Keep these aliases mutable: integrations and tests override the module globals.
DB_PATH = SETTINGS.db_path
BACKUP_DIR = SETTINGS.backup_dir
AVATAR_UPLOAD_DIR = SETTINGS.avatar_upload_dir
SERVER_BACKUP_TASK: Optional[asyncio.Task] = None
REMINDER_EMAIL_TASK: Optional[asyncio.Task] = None
ADMIN_BOOTSTRAP_USER = SETTINGS.admin_bootstrap_user
ADMIN_BOOTSTRAP_PASSWORD = SETTINGS.admin_bootstrap_password

TOKENS: dict[str, str] = {}  # user_id -> token
TOKEN_LAST_ACTIVE: dict[str, datetime] = {}
ACCESS_TOKEN_LIMIT = 50  # Active, unexpired tokens per account.
LOGIN_SESSION_TTL = timedelta(days=30)  # Fixed lifetime of a login session.
SESSION_ONLINE_SECONDS = SETTINGS.session_online_seconds
FOCUS_ROOM_ONLINE_SECONDS = SETTINGS.focus_room_online_seconds
FOCUS_ROOM_MAX_WEEKLY_SECONDS = SETTINGS.focus_room_max_weekly_seconds
FOCUS_ROOM_MAX_SESSION_COUNT = SETTINGS.focus_room_max_session_count
FOCUS_ROOM_HEARTBEAT_THROTTLE_SECONDS = SETTINGS.focus_room_heartbeat_throttle_seconds
FOCUS_ROOM_SESSION_JUMP_WINDOW_SECONDS = SETTINGS.focus_room_session_jump_window_seconds
FOCUS_ROOM_MAX_SESSION_COUNT_JUMP = SETTINGS.focus_room_max_session_count_jump
FOCUS_FRIEND_REQUEST_LIMIT_PER_DAY = SETTINGS.focus_friend_request_limit_per_day
EMAIL_CODE_PROVIDERS = {
    "claw163",
    "openclaw",
    "openclaw_mail",
    "resend",
    "smtp",
    "hermes",
    "none",
}
EMAIL_CODE_SLOTS = {"primary", "backup"}
DEFAULT_EMAIL_TITLE = SETTINGS.email_title
DEFAULT_EMAIL_SENDER_NAME = SETTINGS.email_sender_name
DEFAULT_RESEND_FROM = SETTINGS.resend_from
APP_CURRENT_VERSION = SETTINGS.app_current_version
APP_CURRENT_VERSION_CODE = SETTINGS.app_current_version_code
APP_PACKAGE_NAME = SETTINGS.app_package_name
APP_UPDATE_REPOSITORY = SETTINGS.app_update_repository
APP_UPDATE_DEFAULT_NOTES = SETTINGS.app_update_default_notes
MOBILE_APK_DIR = SETTINGS.mobile_apk_dir
ADMIN_ALL_PERMISSION = "*"
ADMIN_NO_PERMISSION = "__none__"
ADMIN_PERMISSION_KEYS = {
    "settings",
    "users",
    "coins",
    "backup",
    "ai",
    "announcements",
    "feedback",
    "invites",
    "audit",
    "groups",
    "roles",
    "permissions",
}
ADMIN_PERMISSION_LABELS = {
    "settings": "系统设置",
    "users": "用户管理",
    "coins": "时光币",
    "backup": "备份",
    "ai": "AI",
    "announcements": "公告",
    "feedback": "反馈",
    "invites": "邀请码",
    "audit": "审计日志",
    "groups": "用户组",
    "roles": "角色",
    "permissions": "权限字典",
}
ADMIN_PERMISSION_DESCRIPTIONS = {
    "settings": "查看和修改基础系统设置",
    "users": "查看用户列表并修改账号状态",
    "coins": "调整用户时光币额度",
    "backup": "管理服务器和用户备份",
    "ai": "管理 AI 服务配置和诊断",
    "announcements": "发布和维护公告",
    "feedback": "处理用户反馈",
    "invites": "生成和删除邀请码",
    "audit": "查看管理审计日志",
    "groups": "管理默认用户组和额度模板",
    "roles": "管理管理员角色模板",
    "permissions": "查看权限字典",
}


_env_any = SETTINGS.environment.text
_env_bool = SETTINGS.environment.boolean
_env_present = SETTINGS.environment.present
_env_smtp_use_ssl = SETTINGS.environment.smtp_use_ssl


def _env_int(*names: str | int, default: Optional[int] = None) -> int:
    # Support both historic forms: (name, default) and (*aliases, default=N).
    if default is None and names and isinstance(names[-1], int):
        *names, default = names
    if default is None or not names or not all(isinstance(name, str) for name in names):
        raise TypeError("_env_int requires environment keys and an integer default")
    return SETTINGS.environment.integer(*names, default=default)


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _format_utc(value: Optional[datetime]) -> Optional[str]:
    if value is None:
        return None
    return value.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace(
        "+00:00", "Z"
    )


def _utc_now_text() -> str:
    return _format_utc(_utc_now()) or ""


def _touch_session(user_id: str) -> None:
    now = _utc_now()
    TOKEN_LAST_ACTIVE[user_id] = now
    db = get_db()
    try:
        db.execute(
            "UPDATE users SET last_active_at=? WHERE id=?",
            (_format_utc(now), user_id),
        )
        db.commit()
    finally:
        db.close()


def _hash_login_session_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _clear_session_cache(user_id: str) -> None:
    """Drop the compatibility cache alias; the database row stays authoritative."""
    TOKENS.pop(user_id, None)
    TOKEN_LAST_ACTIVE.pop(user_id, None)


def _forget_cached_token(token: str) -> None:
    """Forget a cached credential the database no longer accepts."""
    for user_id, cached in list(TOKENS.items()):
        if isinstance(cached, str) and secrets.compare_digest(cached, token):
            _clear_session_cache(user_id)


def _drop_session(user_id: str, db=None) -> None:
    """Revoke the account's persistent login session and its cache alias."""
    _clear_session_cache(user_id)
    own_connection = db is None
    if own_connection:
        db = get_db()
    try:
        db.execute("DELETE FROM login_sessions WHERE user_id=?", (user_id,))
        if own_connection:
            db.commit()
    finally:
        if own_connection:
            db.close()


def _hash_access_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _revoke_user_token(user_id: str, db=None) -> None:
    """Invalidate all credentials for account security changes, in one transaction."""
    _clear_session_cache(user_id)
    own_connection = db is None
    if own_connection:
        db = get_db()
    try:
        db.execute("DELETE FROM login_sessions WHERE user_id=?", (user_id,))
        db.execute(
            "UPDATE access_tokens SET revoked_at=? WHERE user_id=? AND revoked_at IS NULL",
            (_utc_now_text(), user_id),
        )
        if own_connection:
            db.commit()
    finally:
        if own_connection:
            db.close()


def _online_user_ids(
    candidate_ids: Optional[Iterable[str]] = None, *, db=None
) -> set[str]:
    now = _utc_now()
    cutoff = now - timedelta(seconds=SESSION_ONLINE_SECONDS)
    ids = set(candidate_ids) if candidate_ids is not None else None
    if ids == set():
        return set()
    own_connection = db is None
    if own_connection:
        db = get_db()
    try:
        params = [_format_utc(cutoff)]
        user_filter = ""
        if ids is not None:
            user_filter = "AND u.id IN (" + ",".join("?" for _ in ids) + ")"
            params.extend(ids)
        # One batch for enabled users, their recent login session and recent PATs.
        rows = db.execute(
            "SELECT u.id, t.last_used_at, t.expires_at, "
            "s.last_used_at AS session_last_used_at, s.expires_at AS session_expires_at "
            "FROM users u "
            "LEFT JOIN access_tokens t ON t.user_id=u.id AND t.revoked_at IS NULL "
            "AND t.last_used_at>=? "
            "LEFT JOIN login_sessions s ON s.user_id=u.id "
            "WHERE u.is_disabled=0 " + user_filter,
            params,
        ).fetchall()
        online = set()
        for row in rows:
            user_id = row["id"]
            session_activity = TOKEN_LAST_ACTIVE.get(user_id)
            if user_id in TOKENS:
                # A cached alias stays authoritative for this process' live session.
                if session_activity is not None and session_activity >= cutoff:
                    online.add(user_id)
                    continue
            else:
                # After a restart the persisted session carries recent activity.
                session_last_used = _parse_server_time(row["session_last_used_at"])
                session_expires = _parse_server_time(row["session_expires_at"])
                if (
                    session_last_used is not None
                    and session_last_used >= cutoff
                    and session_expires is not None
                    and session_expires > now
                ):
                    online.add(user_id)
                    continue
            last_used = _parse_server_time(row["last_used_at"])
            expires_at = _parse_server_time(row["expires_at"])
            if last_used is not None and last_used >= cutoff and (
                row["expires_at"] is None or (expires_at is not None and expires_at > now)
            ):
                online.add(user_id)
        return online
    finally:
        if own_connection:
            db.close()


def _parse_server_time(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    text = str(value).strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    elif "T" not in text:
        text = text.replace(" ", "T") + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _has_recent_user_activity(row, cutoff: datetime) -> bool:
    return any(
        parsed is not None and parsed >= cutoff
        for parsed in (
            _parse_server_time(row["last_active_at"]),
            _parse_server_time(row["last_login_at"]),
        )
    )


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def _admin_page_window(limit, offset, default_limit: int = 50, max_limit: int = 500) -> tuple[int, int]:
    try:
        next_limit = int(limit)
    except (TypeError, ValueError):
        next_limit = default_limit
    try:
        next_offset = int(offset)
    except (TypeError, ValueError):
        next_offset = 0
    next_limit = max(1, min(next_limit, max_limit))
    next_offset = max(0, next_offset)
    return next_limit, next_offset


def _admin_page_response(items: list, total: int, limit: int, offset: int) -> dict:
    return {
        "items": items,
        "total": int(total or 0),
        "limit": limit,
        "offset": offset,
        "has_more": offset + len(items) < int(total or 0),
    }


def _version_parts(value: str) -> list[int]:
    normalized = (
        str(value or "")
        .strip()
        .removeprefix("v")
        .split("-", 1)[0]
        .split("+", 1)[0]
    )
    parts = []
    for item in normalized.split("."):
        try:
            parts.append(int(item))
        except ValueError:
            parts.append(0)
    return parts


def _version_gt(left: str, right: str) -> bool:
    left_parts = _version_parts(left)
    right_parts = _version_parts(right)
    for index in range(3):
        a = left_parts[index] if index < len(left_parts) else 0
        b = right_parts[index] if index < len(right_parts) else 0
        if a != b:
            return a > b
    return False


def _has_effective_update_policy(
    *,
    latest_version: str,
    minimum_supported_version: str,
    update_download_url: str,
    update_notes: str,
    force_update_required: bool,
) -> bool:
    return bool(
        force_update_required
        or update_download_url
        or update_notes
        or _version_gt(latest_version, APP_CURRENT_VERSION)
        or _version_gt(minimum_supported_version, APP_CURRENT_VERSION)
    )


def _normalize_update_version_floor(value: str) -> str:
    """规范化更新版本号，自动将低于当前版本的设置提升到当前版本。

    这确保了客户端看到的版本号始终 >= 当前服务器版本，避免配置错误。
    """
    normalized = str(value or "").strip()
    if normalized and _version_gt(APP_CURRENT_VERSION, normalized):
        return APP_CURRENT_VERSION
    return normalized


def _version_to_code(value: str) -> int:
    parts = _version_parts(value)
    major = parts[0] if len(parts) > 0 else 0
    minor = parts[1] if len(parts) > 1 else 0
    patch = parts[2] if len(parts) > 2 else 0
    return major * 100000 + minor * 10000 + patch


def _app_version_code(value: str) -> int:
    normalized = str(value or "").strip().removeprefix("v")
    current = str(APP_CURRENT_VERSION or "").strip().removeprefix("v")
    if normalized == current:
        return APP_CURRENT_VERSION_CODE
    computed = _version_to_code(normalized)
    if _version_gt(normalized, current) and computed <= APP_CURRENT_VERSION_CODE:
        current_computed = _version_to_code(current)
        return APP_CURRENT_VERSION_CODE + max(1, computed - current_computed)
    return computed


def _next_patch_version(value: str) -> str:
    parts = _version_parts(value)
    while len(parts) < 3:
        parts.append(0)
    parts[2] += 1
    return f"{parts[0]}.{parts[1]}.{parts[2]}"


def _next_minor_version(value: str) -> str:
    parts = _version_parts(value)
    while len(parts) < 2:
        parts.append(0)
    return f"{parts[0]}.{parts[1] + 1}.0"


def _update_version_options(
    latest_version: str,
    minimum_supported_version: str,
) -> list[dict]:
    current = APP_CURRENT_VERSION
    next_patch = _next_patch_version(current)
    next_minor = _next_minor_version(current)
    options = [
        {
            "key": "current",
            "label": "当前版本",
            "latest_version": current,
            "minimum_supported_version": current,
        },
        {
            "key": "next_patch",
            "label": "下一补丁",
            "latest_version": next_patch,
            "minimum_supported_version": current,
        },
        {
            "key": "next_minor",
            "label": "下一小版本",
            "latest_version": next_minor,
            "minimum_supported_version": current,
        },
        {
            "key": "minimum_next_patch",
            "label": "强制低于下一补丁",
            "latest_version": next_patch,
            "minimum_supported_version": next_patch,
        },
    ]
    configured = {
        "key": "configured",
        "label": "已有配置",
        "latest_version": (latest_version or current).strip() or current,
        "minimum_supported_version": (
            minimum_supported_version or current
        ).strip() or current,
    }
    if not any(
        item["latest_version"] == configured["latest_version"]
        and item["minimum_supported_version"] == configured["minimum_supported_version"]
        for item in options
    ):
        options.append(configured)
    return options


def _as_bool(value) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    return str(value or "").strip().lower() in {"1", "true", "yes", "on"}


def _update_release_defaults(db) -> dict:
    latest_version = str(
        _setting_get(db, "latest_version", "")
        or _setting_get(db, "latest_version_name", "")
        or ""
    ).strip()
    minimum_supported_version = str(
        _setting_get(db, "minimum_supported_version", "") or ""
    ).strip()
    update_notes = str(
        _setting_get(db, "update_notes", "")
        or _setting_get(db, "release_notes", "")
        or ""
    ).strip()
    update_download_url = str(
        _setting_get(db, "update_download_url", "")
        or _setting_get(db, "download_url", "")
        or ""
    ).strip()
    force_update_required = _as_bool(
        _setting_get(db, "force_update_required", False)
    ) or _as_bool(_setting_get(db, "force_app_update_enabled", False))
    latest_version = (
        _normalize_update_version_floor(latest_version) or APP_CURRENT_VERSION
    )
    minimum_supported_version = (
        _normalize_update_version_floor(minimum_supported_version)
        or APP_CURRENT_VERSION
    )
    if _download_url_looks_stale_for_version(update_download_url, latest_version):
        update_download_url = ""
    if force_update_required:
        if not update_notes:
            update_notes = APP_UPDATE_DEFAULT_NOTES
    return {
        "current_version": APP_CURRENT_VERSION,
        "current_version_name": APP_CURRENT_VERSION,
        "current_version_code": APP_CURRENT_VERSION_CODE,
        "app_package_name": APP_PACKAGE_NAME,
        "version_options": _update_version_options(
            latest_version,
            minimum_supported_version,
        ),
        "force_update_required": force_update_required,
        "force_app_update_enabled": force_update_required,
        "latest_version": latest_version,
        "latest_version_name": latest_version,
        "latest_version_code": _app_version_code(
            latest_version or APP_CURRENT_VERSION
        ),
        "minimum_supported_version": minimum_supported_version,
        "update_notes": update_notes,
        "release_notes": update_notes,
        "update_download_url": update_download_url,
        "download_url": update_download_url,
    }


# RE0 config aliases accepted here include TITLE, EMAIL_ADDRESS,
# EMAIL_PASSWORD, EMAIL_SMTP_HOST, EMAIL_SMTP_PORT and SMTP_HOST.
_RE0_EMAIL_SETTING_ALIASES = {
    "title": "email_title",
    "app_title": "email_title",
    "duoyi_title": "email_title",
    "email_title": "email_title",
    "email_sender_name": "email_sender_name",
    "email_from_name": "email_sender_name",
    "mail_from_name": "email_sender_name",
    "sender_name": "email_sender_name",
    "email_address": "email_smtp_username",
    "email_smtp_username": "email_smtp_username",
    "smtp_username": "email_smtp_username",
    "smtp_user": "email_smtp_username",
    "mail_username": "email_smtp_username",
    "mail_user": "email_smtp_username",
    "mail_address": "email_smtp_username",
    "email_password": "email_smtp_password",
    "email_smtp_password": "email_smtp_password",
    "smtp_password": "email_smtp_password",
    "smtp_pass": "email_smtp_password",
    "mail_password": "email_smtp_password",
    "mail_pass": "email_smtp_password",
    "email_smtp_host": "email_smtp_host",
    "smtp_host": "email_smtp_host",
    "mail_smtp_host": "email_smtp_host",
    "mail_host": "email_smtp_host",
    "email_smtp_port": "email_smtp_port",
    "smtp_port": "email_smtp_port",
    "mail_smtp_port": "email_smtp_port",
    "mail_port": "email_smtp_port",
    "email_smtp_from": "email_smtp_from",
    "email_from": "email_smtp_from",
    "mail_from": "email_smtp_from",
    "smtp_from": "email_smtp_from",
    "email_smtp_use_ssl": "email_smtp_use_ssl",
    "smtp_use_ssl": "email_smtp_use_ssl",
    "mail_smtp_use_ssl": "email_smtp_use_ssl",
    "mail_use_ssl": "email_smtp_use_ssl",
    "email_home_address": "system_notice_email_to",
    "email_home_channel": "system_notice_email_to",
    "system_notice_email_to": "system_notice_email_to",
}


def _normalize_email_setting_aliases(update_items: dict) -> None:
    for key in list(update_items.keys()):
        normalized = str(key).strip()
        canonical = _RE0_EMAIL_SETTING_ALIASES.get(normalized.lower())
        if not canonical:
            continue
        value = update_items.pop(key)
        if canonical not in update_items:
            update_items[canonical] = value
    if (
        "email_smtp_username" in update_items
        and "email_smtp_from" not in update_items
    ):
        update_items["email_smtp_from"] = update_items["email_smtp_username"]
    if (
        "email_smtp_port" in update_items
        and "email_smtp_use_ssl" not in update_items
    ):
        try:
            update_items["email_smtp_use_ssl"] = int(update_items["email_smtp_port"]) == 465
        except Exception:
            pass


def _coerce_update_settings(db, update_items: dict) -> None:
    _normalize_email_setting_aliases(update_items)
    if "email_code_login_enabled" in update_items:
        update_items["email_code_login_enabled"] = _as_bool(
            update_items["email_code_login_enabled"]
        )
    if "force_app_update_enabled" in update_items:
        update_items["force_update_required"] = _as_bool(
            update_items["force_app_update_enabled"]
        )
    if "force_update_required" in update_items:
        update_items["force_app_update_enabled"] = _as_bool(
            update_items["force_update_required"]
        )
    if "latest_version_name" in update_items and "latest_version" not in update_items:
        update_items["latest_version"] = update_items["latest_version_name"]
    if "latest_version" in update_items and "latest_version_name" not in update_items:
        update_items["latest_version_name"] = update_items["latest_version"]
    if "download_url" in update_items and "update_download_url" not in update_items:
        update_items["update_download_url"] = update_items["download_url"]
    if "update_download_url" in update_items and "download_url" not in update_items:
        update_items["download_url"] = update_items["update_download_url"]
    if "release_notes" in update_items and "update_notes" not in update_items:
        update_items["update_notes"] = update_items["release_notes"]
    if "update_notes" in update_items and "release_notes" not in update_items:
        update_items["release_notes"] = update_items["update_notes"]
    if "force_relogin_enabled" in update_items and _as_bool(
        update_items["force_relogin_enabled"]
    ):
        current = _as_bool(_setting_get(db, "force_relogin_enabled", False))
        if not current and "force_relogin_issued_at" not in update_items:
            update_items["force_relogin_issued_at"] = _utc_now_text()

    policy_keys = {
        "latest_version",
        "latest_version_name",
        "minimum_supported_version",
        "update_notes",
        "release_notes",
        "update_download_url",
        "download_url",
        "force_update_required",
        "force_app_update_enabled",
    }
    if not any(key in update_items for key in policy_keys):
        return

    existing = _update_release_defaults(db)
    force_update_required = _as_bool(
        update_items.get(
            "force_update_required",
            update_items.get(
                "force_app_update_enabled",
                existing["force_update_required"],
            ),
        )
    )
    latest_version = str(
        update_items.get(
            "latest_version",
            update_items.get("latest_version_name", existing["latest_version"]),
        )
        or ""
    ).strip()
    normalized_latest_version = _normalize_update_version_floor(latest_version)
    if latest_version and normalized_latest_version != latest_version:
        latest_version = normalized_latest_version
        update_items["latest_version"] = latest_version
        update_items["latest_version_name"] = latest_version
    minimum_supported_version = str(
        update_items.get(
            "minimum_supported_version",
            existing["minimum_supported_version"],
        )
        or ""
    ).strip()
    normalized_minimum_supported_version = _normalize_update_version_floor(
        minimum_supported_version
    )
    if (
        minimum_supported_version
        and normalized_minimum_supported_version != minimum_supported_version
    ):
        minimum_supported_version = normalized_minimum_supported_version
        update_items["minimum_supported_version"] = minimum_supported_version
    update_notes = str(
        update_items.get(
            "update_notes",
            update_items.get("release_notes", existing["update_notes"]),
        )
        or ""
    ).strip()

    if force_update_required:
        if not latest_version:
            latest_version = APP_CURRENT_VERSION
            update_items["latest_version"] = latest_version
            update_items["latest_version_name"] = latest_version
        if not minimum_supported_version:
            minimum_supported_version = APP_CURRENT_VERSION
            update_items["minimum_supported_version"] = minimum_supported_version
    if (
        _has_effective_update_policy(
            latest_version=latest_version,
            minimum_supported_version=minimum_supported_version,
            update_download_url=str(
                update_items.get(
                    "update_download_url",
                    update_items.get("download_url", existing["update_download_url"]),
                )
                or ""
            ).strip(),
            update_notes=update_notes,
            force_update_required=force_update_required,
        )
        and not update_notes
    ):
        update_items["update_notes"] = APP_UPDATE_DEFAULT_NOTES
        update_items["release_notes"] = APP_UPDATE_DEFAULT_NOTES


def _github_latest_mobile_release() -> Optional[dict]:
    repository = APP_UPDATE_REPOSITORY.strip()
    if not repository:
        return None
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}/releases/latest",
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "duoyi-sync-api",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            release = json.loads(response.read().decode("utf-8"))
    except Exception:
        return None
    if not isinstance(release, dict):
        return None
    assets = release.get("assets") if isinstance(release.get("assets"), list) else []
    apk_asset = None
    version_name = str(release.get("tag_name") or "").strip().removeprefix("v")
    for asset in assets:
        if not isinstance(asset, dict):
            continue
        name = str(asset.get("name") or "").lower()
        if not name.endswith(".apk"):
            continue
        if version_name and name == f"duoyi-v{version_name}.apk":
            apk_asset = asset
            break
        if version_name and name == f"duoyi-{version_name}.apk":
            apk_asset = asset
            break
        if "universal" in name and ("duoyi" in name or apk_asset is None):
            apk_asset = asset
            continue
        if not re.search(r"-(armeabi-v7a|arm64-v8a|x86_64)\.apk$", name):
            apk_asset = apk_asset or asset
            continue
        if apk_asset is None and "duoyi" in name:
            apk_asset = asset
    if not version_name:
        return None
    return {
        "latest_version_name": version_name,
        "latest_version_code": _app_version_code(version_name),
        "download_url": str((apk_asset or {}).get("browser_download_url") or ""),
        "file_size": int((apk_asset or {}).get("size") or 0),
        "release_notes": str(release.get("body") or APP_UPDATE_DEFAULT_NOTES),
        "release_url": str(release.get("html_url") or ""),
        "updated_at": str(release.get("published_at") or release.get("created_at") or ""),
    }


def _local_mobile_release(request: Request, app_id: str) -> Optional[dict]:
    resolved = _resolve_local_mobile_apk(app_id)
    if resolved is None:
        return None
    apk_path, manifest = resolved
    stat = apk_path.stat()
    version_name = str(manifest.get("version_name") or APP_CURRENT_VERSION)
    download_path = f"/api/mobile/apps/{app_id}/download"
    return {
        "latest_version_name": version_name,
        "latest_version_code": int(
            manifest.get("version_code") or _app_version_code(version_name)
        ),
        "download_url": str(request.base_url).rstrip("/") + download_path,
        "download_path": download_path,
        "file_size": stat.st_size,
        "sha256": _file_sha256(apk_path),
        "updated_at": _format_utc(datetime.fromtimestamp(stat.st_mtime, timezone.utc)),
        "release_notes": str(manifest.get("release_notes") or APP_UPDATE_DEFAULT_NOTES),
    }


def _resolve_local_mobile_apk(app_id: str) -> Optional[tuple[Path, dict]]:
    app_dir = (Path(MOBILE_APK_DIR) / app_id).resolve()
    try:
        app_dir.relative_to(Path(MOBILE_APK_DIR).resolve())
    except ValueError:
        return None
    manifest_path = app_dir / "manifest.json"
    manifest = {}
    if manifest_path.is_file():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except Exception:
            manifest = {}
    apk_name = str(manifest.get("apk_name") or "app-release.apk")
    apk_path = (app_dir / apk_name).resolve()
    try:
        apk_path.relative_to(app_dir)
    except ValueError:
        return None
    if not apk_path.is_file():
        return None
    return apk_path, manifest


def _is_local_mobile_download_url(value: str, app_id: str) -> bool:
    clean = str(value or "").strip()
    if not clean:
        return False
    parsed = urllib.parse.urlparse(clean)
    path = parsed.path if parsed.scheme or parsed.netloc else clean.split("?", 1)[0]
    normalized = path.rstrip("/")
    return normalized == f"/api/mobile/apps/{app_id}/download"


def _download_url_matches_version(value: str, version: str) -> bool:
    clean = str(value or "").strip().lower()
    normalized_version = str(version or "").strip().lower().removeprefix("v")
    if not clean or not normalized_version:
        return False
    return normalized_version in urllib.parse.unquote(clean)


def _download_url_has_version(value: str) -> bool:
    clean = urllib.parse.unquote(str(value or "").strip().lower())
    pattern = r"(?:^|[^0-9])v?([0-9]+\.[0-9]+\.[0-9]+)(?:[^0-9]|$)"
    return bool(re.search(pattern, clean))


def _download_url_looks_stale_for_version(value: str, version: str) -> bool:
    clean = urllib.parse.unquote(str(value or "").strip().lower())
    normalized_version = str(version or "").strip().lower().removeprefix("v")
    if not clean or not normalized_version:
        return False
    if normalized_version in clean:
        return False
    pattern = r"(?:^|[^0-9])v?([0-9]+\.[0-9]+\.[0-9]+)(?:[^0-9]|$)"
    for match in re.finditer(pattern, clean):
        found = str(match.group(1) or "").strip()
        if found and _version_gt(normalized_version, found):
            return True
    return False


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _mobile_update_response(
    request: Request,
    app_id: str,
    current_version_code: int,
    current_version: str = "",
) -> dict:
    normalized_app_id = (app_id or "").strip().lower()
    allowed_ids = {"duoyi", APP_PACKAGE_NAME.lower()}
    if normalized_app_id not in allowed_ids:
        raise HTTPException(status_code=404, detail="Mobile app not found")

    db = get_db()
    try:
        settings_payload = _update_release_defaults(db)
    finally:
        db.close()

    release = _local_mobile_release(request, normalized_app_id)
    if release is None:
        release = _github_latest_mobile_release()
    if release is None:
        release = {}

    configured_version_name = str(
        settings_payload["latest_version_name"]
        or settings_payload["minimum_supported_version"]
        or ""
    ).strip()
    if configured_version_name and _version_gt(APP_CURRENT_VERSION, configured_version_name):
        configured_version_name = ""
    release_version_name = str(release.get("latest_version_name") or "").strip()
    release_version_is_current_or_newer = bool(
        release_version_name
        and not _version_gt(APP_CURRENT_VERSION, release_version_name)
    )
    if release and not release_version_is_current_or_newer:
        release = {}
        release_version_name = ""
    configured_version_is_newer = bool(
        configured_version_name
        and _version_gt(configured_version_name, APP_CURRENT_VERSION)
    )
    # 管理后台默认展示“当前版本”只是为了让开关能直接保存；它不能压掉
    # GitHub/本地发布通道里的新安装包，否则强制更新开关打开后仍会显示无更新。
    effective_release_version = (
        "" if configured_version_is_newer else release_version_name
    )
    latest_version_name = str(
        configured_version_name
        if configured_version_is_newer
        else effective_release_version or configured_version_name or APP_CURRENT_VERSION
    ).strip()
    latest_version_code = (
        _app_version_code(latest_version_name)
        if configured_version_is_newer or not effective_release_version
        else int(
            release.get("latest_version_code") or _app_version_code(latest_version_name)
        )
    )
    minimum_supported_version = str(
        settings_payload["minimum_supported_version"] or APP_CURRENT_VERSION
    ).strip()
    minimum_supported_version_code = _app_version_code(minimum_supported_version)
    if _version_gt(minimum_supported_version, latest_version_name):
        latest_version_name = minimum_supported_version
        latest_version_code = minimum_supported_version_code
    configured_download_url = str(settings_payload["download_url"] or "").strip()
    release_download_url = str(release.get("download_url") or "").strip()
    configured_download_is_local = _is_local_mobile_download_url(
        configured_download_url,
        normalized_app_id,
    )
    release_download_is_local = _is_local_mobile_download_url(
        release_download_url,
        normalized_app_id,
    )
    configured_download_matches_version = _download_url_matches_version(
        configured_download_url,
        latest_version_name,
    )
    configured_download_has_version = _download_url_has_version(configured_download_url)
    configured_download_allowed = bool(
        configured_download_url
        and (
            (
                configured_download_is_local
                and release_download_url
                and release_download_is_local
            )
            or configured_download_matches_version
            or (
                configured_version_is_newer
                and not release_download_url
                and not configured_download_has_version
            )
        )
    )
    download_url = (
        configured_download_url if configured_download_allowed else release_download_url
    )
    if (
        _is_local_mobile_download_url(download_url, normalized_app_id)
        and _resolve_local_mobile_apk(normalized_app_id) is None
    ):
        download_url = ""
    configured_release_notes = str(settings_payload["release_notes"] or "").strip()
    channel_release_notes = str(release.get("release_notes") or "").strip()
    release_notes = (
        configured_release_notes
        if configured_release_notes
        and configured_release_notes != APP_UPDATE_DEFAULT_NOTES
        else channel_release_notes or configured_release_notes or APP_UPDATE_DEFAULT_NOTES
    )
    client_version_name = str(current_version or "").strip()
    effective_current_version_code = int(current_version_code or 0)
    if effective_current_version_code <= 0 and client_version_name:
        effective_current_version_code = _app_version_code(client_version_name)
    below_minimum = minimum_supported_version_code > effective_current_version_code
    available = latest_version_code > effective_current_version_code
    force_update_required = bool(
        settings_payload.get("force_update_required")
        or settings_payload["force_app_update_enabled"]
    )
    force_update = force_update_required and (available or below_minimum)
    payload = {
        "app_id": normalized_app_id,
        "app_name": "多仪",
        "package_name": APP_PACKAGE_NAME,
        "current_version_code": effective_current_version_code,
        "current_version_name": client_version_name or APP_CURRENT_VERSION,
        "latest_version_code": latest_version_code,
        "latest_version_name": latest_version_name,
        "minimum_supported_version": minimum_supported_version,
        "minimum_supported_version_code": minimum_supported_version_code,
        "available": available,
        "force_update": force_update,
        "force_update_required": force_update_required,
        "force_app_update_enabled": force_update_required,
        "force_update_blocked_reason": (
            "missing_download_url"
            if force_update and not download_url
            else ""
        ),
        "download_url": download_url,
        "download_path": str(release.get("download_path") or ""),
        "file_size": int(release.get("file_size") or 0),
        "sha256": str(release.get("sha256") or ""),
        "updated_at": str(release.get("updated_at") or ""),
        "release_notes": release_notes,
        "release_url": str(release.get("release_url") or download_url),
    }
    payload.update(_api_contract_payload())
    return payload


def _feedback_admin_filters(
    status: Optional[str] = None,
    q: Optional[str] = None,
    category: Optional[str] = None,
    feedback_type: Optional[str] = None,
    start_at: Optional[str] = None,
    end_at: Optional[str] = None,
) -> tuple[str, list]:
    where_parts: list[str] = []
    params: list = []
    if status:
        status = FEEDBACK_STATUS_ALIASES.get(status, status)
        where_parts.append("f.status=?")
        params.append(status)
    if category:
        category = _clean_feedback_category(category, feedback_type)
        where_parts.append("f.category=?")
        params.append(category)
    elif feedback_type == "wish":
        where_parts.append("f.category=?")
        params.append("wish")
    if q:
        where_parts.append(
            "(f.content LIKE ? OR f.admin_reply LIKE ? OR u.username LIKE ?)"
        )
        like = f"%{q}%"
        params.extend([like, like, like])
    if start_at:
        where_parts.append("f.created_at>=?")
        params.append(start_at)
    if end_at:
        where_parts.append("f.created_at<=?")
        params.append(end_at)
    where = f"WHERE {' AND '.join(where_parts)}" if where_parts else ""
    return where, params


def _feedback_admin_order_by(sort: str) -> str:
    return {
        "created_desc": "f.id DESC",
        "updated_desc": "f.updated_at DESC, f.id DESC",
        "status_asc": (
            "CASE f.status WHEN 'open' THEN 0 WHEN 'in_progress' THEN 1 "
            "WHEN 'resolved' THEN 2 ELSE 3 END, f.id DESC"
        ),
        "user_asc": "lower(u.username) ASC, f.id DESC",
    }.get(sort, "f.id DESC")


def _csv_safe(value) -> str:
    text = "" if value is None else str(value)
    if text and text[0] in ("=", "+", "-", "@", "\t", "\r", "\n"):
        return "'" + text
    return text


_BACKUP_BYTES_SQL = """
(length(sd.todos) + length(sd.habits) + length(sd.pomodoro_sessions)
 + length(sd.focus_penalties)
 + length(sd.pomodoro_config) + length(sd.user_profile)
 + length(sd.notes) + length(sd.countdowns) + length(sd.anniversaries)
 + length(sd.diaries) + length(sd.goals) + length(sd.calendar_events)
 + length(sd.courses) + length(sd.time_entries) + length(sd.location_reminders)
 + length(sd.course_settings)
 + length(sd.achievement_states) + length(sd.virtual_rewards)
 + length(sd.focus_rooms) + length(sd.theme_shop_state)
 + length(sd.preferences) + length(sd.quick_capture_templates) + length(sd.list_groups))
"""


def _backup_admin_filters(
    q: Optional[str] = None,
    status: Optional[str] = None,
) -> tuple[str, list]:
    where_parts: list[str] = []
    params: list = []
    if q:
        where_parts.append(
            "(u.username LIKE ? OR u.email LIKE ? OR u.display_name LIKE ? OR u.id LIKE ?)"
        )
        like = f"%{q}%"
        params.extend([like, like, like, like])
    if status == "synced":
        where_parts.append("sd.sync_version > 0")
    elif status == "empty":
        where_parts.append("(sd.user_id IS NULL OR sd.sync_version=0)")
    where = f"WHERE {' AND '.join(where_parts)}" if where_parts else ""
    return where, params


def _backup_admin_order_by(sort: str) -> str:
    return {
        "updated_desc": "sd.updated_at IS NULL, sd.updated_at DESC, u.created_at DESC",
        "username_asc": "lower(u.username) ASC",
        "size_desc": "bytes DESC, sd.updated_at DESC",
        "size_asc": "bytes ASC, sd.updated_at DESC",
        "version_desc": "sd.sync_version DESC, sd.updated_at DESC",
    }.get(sort, "sd.updated_at IS NULL, sd.updated_at DESC, u.created_at DESC")


def _server_backup_admin_filters(
    q: Optional[str] = None,
    status: Optional[str] = None,
) -> tuple[str, list]:
    where_parts: list[str] = []
    params: list = []
    if q:
        where_parts.append(
            "(filename LIKE ? OR status LIKE ? OR detail LIKE ? OR remote_url LIKE ? OR local_path LIKE ?)"
        )
        like = f"%{q}%"
        params.extend([like, like, like, like, like])
    if status:
        where_parts.append("status=?")
        params.append(status)
    where = f"WHERE {' AND '.join(where_parts)}" if where_parts else ""
    return where, params


def _server_backup_admin_order_by(sort: str) -> str:
    return {
        "created_desc": "created_at DESC, id DESC",
        "size_desc": "size_bytes DESC, created_at DESC",
        "size_asc": "size_bytes ASC, created_at DESC",
        "status_asc": "status ASC, created_at DESC",
        "filename_asc": "lower(filename) ASC, created_at DESC",
    }.get(sort, "created_at DESC, id DESC")


def _user_admin_filters(
    q: Optional[str] = None,
    status: Optional[str] = None,
) -> tuple[str, list]:
    where_parts: list[str] = []
    params: list = []
    if q:
        where_parts.append(
            "(u.username LIKE ? OR u.email LIKE ? OR u.display_name LIKE ? OR u.id LIKE ?)"
        )
        like = f"%{q}%"
        params.extend([like, like, like, like])
    if status == "admin":
        where_parts.append("u.is_admin=1")
    elif status == "disabled":
        where_parts.append("u.is_disabled=1")
    elif status == "active":
        where_parts.append("u.is_disabled=0")
    elif status == "normal":
        where_parts.append("u.is_admin=0 AND u.is_disabled=0")
    elif status == "unverified_email":
        where_parts.append("u.email<>'' AND u.email_verified=0")
    elif status == "verified_email":
        where_parts.append("u.email<>'' AND u.email_verified=1")
    elif status == "no_email":
        where_parts.append("u.email=''")
    elif status == "has_feedback":
        where_parts.append(
            "EXISTS (SELECT 1 FROM feedback f_filter WHERE f_filter.user_id=u.id)"
        )
    where = f"WHERE {' AND '.join(where_parts)}" if where_parts else ""
    return where, params


def _user_admin_order_by(sort: str) -> str:
    return {
        "created_desc": "u.created_at DESC",
        "last_active_desc": "u.last_active_at IS NULL, u.last_active_at DESC",
        "last_login_desc": "u.last_login_at IS NULL, u.last_login_at DESC",
        "feedback_desc": "fb_count DESC, u.created_at DESC",
        "username_asc": "lower(u.username) ASC",
        "email_asc": "u.email='', lower(u.email) ASC, lower(u.username) ASC",
    }.get(sort, "u.created_at DESC")


def _write_bootstrap_credentials(credentials: dict[str, str]) -> Path:
    db_path = Path(DB_PATH).resolve()
    path = db_path.with_name(db_path.name + ".bootstrap-admin.json")
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except OSError:
        raise ConfigurationError(
            "Bootstrap credentials: cannot exclusively create <DUOYI_DB_PATH>.bootstrap-admin.json; "
            "check directory permissions and any existing credentials file"
        ) from None
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            os.fchmod(handle.fileno(), 0o600)
            json.dump(credentials, handle, ensure_ascii=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        # Persist the directory entry before committing an account that needs it.
        directory_descriptor = os.open(path.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    except BaseException as error:
        try:
            path.unlink()
        except OSError:
            raise ConfigurationError(
                "Bootstrap credentials: writing failed; remove the local credentials file before retrying"
            ) from None
        if isinstance(error, (OSError, UnicodeError)):
            raise ConfigurationError("Bootstrap credentials: cannot write private credentials file") from None
        raise
    return path


def init_db():
    conn = get_db()
    credentials_path = None
    try:
        # Serialize first-run detection, schema changes and bootstrap across workers.
        conn.execute("BEGIN IMMEDIATE")
        fresh_database = conn.execute("SELECT 1 FROM sqlite_master LIMIT 1").fetchone() is None
        credentials = _initialize_database(conn, fresh_database)
        # Finish all DB work before persisting a generated secret, then commit only
        # after its private file is durable. Explicit credentials need no file.
        if credentials is not None:
            credentials_path = _write_bootstrap_credentials(credentials)
        conn.commit()
    except BaseException:
        try:
            if credentials_path is not None:
                credentials_path.unlink()
        except OSError:
            raise ConfigurationError(
                "Bootstrap failed; remove the local bootstrap credentials file before retrying"
            ) from None
        finally:
            conn.rollback()
        raise
    finally:
        conn.close()


def _initialize_database(conn, fresh_database: bool):
    schema = """
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            username TEXT UNIQUE NOT NULL,
            email TEXT DEFAULT '',
            email_verified INTEGER DEFAULT 0,
            password_hash TEXT NOT NULL,
            avatar TEXT DEFAULT '',
            display_name TEXT DEFAULT '',
            bio TEXT DEFAULT '',
            group_id TEXT DEFAULT 'group_default',
            role_id TEXT DEFAULT '',
            is_admin INTEGER DEFAULT 0,
            admin_permissions TEXT DEFAULT '[]',
            is_disabled INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now')),
            last_login_at TEXT,
            last_active_at TEXT
        );
        CREATE TABLE IF NOT EXISTS access_tokens (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            name TEXT NOT NULL CHECK(length(name) BETWEEN 1 AND 80),
            prefix TEXT NOT NULL,
            token_hash TEXT UNIQUE NOT NULL,
            created_at TEXT NOT NULL,
            last_used_at TEXT,
            expires_at TEXT,
            revoked_at TEXT,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_access_tokens_user ON access_tokens(user_id);
        CREATE TABLE IF NOT EXISTS sync_data (
            user_id TEXT PRIMARY KEY,
            todos TEXT DEFAULT '[]',
            habits TEXT DEFAULT '[]',
            pomodoro_sessions TEXT DEFAULT '[]',
            focus_penalties TEXT DEFAULT '[]',
            pomodoro_config TEXT DEFAULT '{}',
            user_profile TEXT DEFAULT '{}',
            notes TEXT DEFAULT '[]',
            countdowns TEXT DEFAULT '[]',
            anniversaries TEXT DEFAULT '[]',
            diaries TEXT DEFAULT '[]',
            goals TEXT DEFAULT '[]',
            calendar_events TEXT DEFAULT '[]',
            courses TEXT DEFAULT '[]',
            time_entries TEXT DEFAULT '[]',
            location_reminders TEXT DEFAULT '[]',
            course_settings TEXT DEFAULT '{}',
            achievement_states TEXT DEFAULT '{}',
            virtual_rewards TEXT DEFAULT '{}',
            focus_rooms TEXT DEFAULT '{}',
            theme_shop_state TEXT DEFAULT '{}',
            preferences TEXT DEFAULT '{}',
            quick_capture_templates TEXT DEFAULT '{}',
            list_groups TEXT DEFAULT '[]',
            deleted_items TEXT DEFAULT '{}',
            sync_version INTEGER DEFAULT 0,
            updated_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS workspaces (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            owner_user_id TEXT NOT NULL,
            is_private INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS workspace_members (
            workspace_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'viewer',
            joined_at TEXT DEFAULT (datetime('now')),
            PRIMARY KEY(workspace_id, user_id),
            FOREIGN KEY(workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS workspace_invites (
            id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            code TEXT UNIQUE NOT NULL,
            role TEXT NOT NULL DEFAULT 'viewer',
            created_by TEXT NOT NULL,
            expires_at TEXT,
            revoked INTEGER DEFAULT 0,
            used_by TEXT,
            used_at TEXT,
            created_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
            FOREIGN KEY(created_by) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY(used_by) REFERENCES users(id) ON DELETE SET NULL
        );
        CREATE TABLE IF NOT EXISTS workspace_data (
            workspace_id TEXT PRIMARY KEY,
            todos TEXT DEFAULT '[]',
            goals TEXT DEFAULT '[]',
            courses TEXT DEFAULT '[]',
            time_entries TEXT DEFAULT '[]',
            calendar_events TEXT DEFAULT '[]',
            updated_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS workspace_comments (
            id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            target_id TEXT DEFAULT '',
            author_user_id TEXT NOT NULL,
            body TEXT NOT NULL,
            created_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
            FOREIGN KEY(author_user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS workspace_mentions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            workspace_id TEXT NOT NULL,
            comment_id TEXT NOT NULL,
            target_user_id TEXT NOT NULL,
            mentioned_by_user_id TEXT NOT NULL,
            read_at TEXT,
            created_at TEXT DEFAULT (datetime('now')),
            UNIQUE(comment_id, target_user_id),
            FOREIGN KEY(workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
            FOREIGN KEY(comment_id) REFERENCES workspace_comments(id) ON DELETE CASCADE,
            FOREIGN KEY(target_user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY(mentioned_by_user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS workspace_activity (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            workspace_id TEXT NOT NULL,
            actor_user_id TEXT NOT NULL,
            actor_name TEXT NOT NULL,
            action TEXT NOT NULL,
            detail TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
            FOREIGN KEY(actor_user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS invite_codes (
            code TEXT PRIMARY KEY,
            used_by TEXT,
            used_at TEXT,
            created_at TEXT DEFAULT (datetime('now')),
            note TEXT DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS announcements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            level TEXT DEFAULT 'info',
            published INTEGER DEFAULT 1,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS feedback (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            category TEXT DEFAULT 'feature',
            content TEXT NOT NULL,
            status TEXT DEFAULT 'open',
            admin_reply TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS admin_groups (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT DEFAULT '',
            default_time_coins INTEGER DEFAULT 100,
            default_generate_quota INTEGER DEFAULT 100,
            default_edit_quota INTEGER DEFAULT 100,
            default_generate_history_retention INTEGER DEFAULT 50,
            default_edit_history_retention INTEGER DEFAULT 20,
            image_mode TEXT DEFAULT 'vip',
            is_active INTEGER DEFAULT 1,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS admin_roles (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT DEFAULT '',
            permissions TEXT DEFAULT '[]',
            is_active INTEGER DEFAULT 1,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS audit_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            actor_id TEXT,
            actor_name TEXT,
            action TEXT NOT NULL,
            target TEXT DEFAULT '',
            detail TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS ai_usage (
            user_id TEXT NOT NULL,
            day TEXT NOT NULL,
            calls INTEGER DEFAULT 0,
            PRIMARY KEY(user_id, day)
        );
        CREATE TABLE IF NOT EXISTS server_backups (
            id TEXT PRIMARY KEY,
            filename TEXT NOT NULL,
            size_bytes INTEGER DEFAULT 0,
            status TEXT DEFAULT 'created',
            detail TEXT DEFAULT '',
            local_path TEXT DEFAULT '',
            remote_url TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS reminder_email_jobs (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            reminder_id INTEGER NOT NULL,
            schedule_kind TEXT NOT NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            payload TEXT DEFAULT '',
            when_at TEXT,
            hour INTEGER,
            minute INTEGER,
            weekdays_json TEXT DEFAULT '[]',
            next_send_at TEXT,
            sent_at TEXT,
            cancelled INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS password_reset_tokens (
            token_hash TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            used_at TEXT,
            created_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS email_verification_codes (
            id TEXT PRIMARY KEY,
            user_id TEXT,
            email TEXT NOT NULL,
            purpose TEXT NOT NULL,
            code_hash TEXT NOT NULL,
            failure_count INTEGER DEFAULT 0,
            expires_at TEXT NOT NULL,
            consumed_at TEXT,
            locked_until TEXT,
            ip_address TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS focus_room_presence (
            room_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            display_name TEXT DEFAULT '',
            raw_weekly_seconds INTEGER DEFAULT 0,
            weekly_seconds INTEGER DEFAULT 0,
            session_count INTEGER DEFAULT 0,
            active INTEGER DEFAULT 1,
            started_at TEXT,
            last_seen_at TEXT,
            risk_flags TEXT DEFAULT '[]',
            risk_summary TEXT DEFAULT '',
            updated_at TEXT DEFAULT (datetime('now')),
            PRIMARY KEY(room_id, user_id),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS focus_room_invites (
            id TEXT PRIMARY KEY,
            room_id TEXT NOT NULL,
            code TEXT UNIQUE NOT NULL,
            room_name TEXT NOT NULL,
            description TEXT DEFAULT '',
            weekly_target_seconds INTEGER DEFAULT 18000,
            accent_color INTEGER DEFAULT 3762608,
            created_by TEXT NOT NULL,
            expires_at TEXT,
            max_uses INTEGER DEFAULT 0,
            used_count INTEGER DEFAULT 0,
            last_used_at TEXT,
            revoked INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(created_by) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS focus_friends (
            user_id TEXT NOT NULL,
            friend_user_id TEXT NOT NULL,
            status TEXT DEFAULT 'accepted',
            created_at TEXT DEFAULT (datetime('now')),
            PRIMARY KEY(user_id, friend_user_id),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY(friend_user_id) REFERENCES users(id) ON DELETE CASCADE,
            CHECK(user_id <> friend_user_id)
        );
        CREATE TABLE IF NOT EXISTS focus_friend_request_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            friend_user_id TEXT NOT NULL,
            created_at TEXT DEFAULT (datetime('now')),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY(friend_user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS login_sessions (
            user_id TEXT PRIMARY KEY,
            token_hash TEXT UNIQUE NOT NULL,
            created_at TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            last_used_at TEXT,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_login_sessions_expires
            ON login_sessions(expires_at);
        """
    # This static schema contains only table/index definitions. Execute each
    # statement in the caller's transaction; executescript would commit it first.
    for statement in schema.split(";"):
        if statement.strip():
            conn.execute(statement)

    # Schema migrations
    for table, col, default in [
        ("sync_data", "pomodoro_sessions", "'[]'"),
        ("sync_data", "focus_penalties", "'[]'"),
        ("sync_data", "pomodoro_config", "'{}'"),
        ("sync_data", "user_profile", "'{}'"),
        ("sync_data", "notes", "'[]'"),
        ("sync_data", "countdowns", "'[]'"),
        ("sync_data", "anniversaries", "'[]'"),
        ("sync_data", "diaries", "'[]'"),
        ("sync_data", "goals", "'[]'"),
        ("sync_data", "calendar_events", "'[]'"),
        ("sync_data", "courses", "'[]'"),
        ("sync_data", "time_entries", "'[]'"),
        ("sync_data", "location_reminders", "'[]'"),
        ("sync_data", "course_settings", "'{}'"),
        ("sync_data", "achievement_states", "'{}'"),
        ("sync_data", "virtual_rewards", "'{}'"),
        ("sync_data", "focus_rooms", "'{}'"),
        ("sync_data", "theme_shop_state", "'{}'"),
        ("sync_data", "preferences", "'{}'"),
        ("sync_data", "quick_capture_templates", "'{}'"),
        ("sync_data", "list_groups", "'[]'"),
        ("sync_data", "deleted_items", "'{}'"),
        ("sync_data", "sync_version", "0"),
        ("workspace_data", "calendar_events", "'[]'"),
        ("users", "is_disabled", "0"),
        ("users", "last_login_at", "NULL"),
        ("users", "last_active_at", "NULL"),
        ("users", "email", "''"),
        ("users", "email_verified", "0"),
        ("users", "avatar", "''"),
        ("users", "display_name", "''"),
        ("users", "bio", "''"),
        ("users", "group_id", "'group_default'"),
        ("users", "role_id", "''"),
        ("users", "admin_permissions", "'[]'"),
        ("invite_codes", "note", "''"),
        ("announcements", "updated_at", "datetime('now')"),
        ("admin_groups", "default_time_coins", "100"),
        ("admin_groups", "default_generate_quota", "100"),
        ("admin_groups", "default_edit_quota", "100"),
        ("admin_groups", "default_generate_history_retention", "50"),
        ("admin_groups", "default_edit_history_retention", "20"),
        ("admin_groups", "image_mode", "'vip'"),
        ("admin_groups", "is_active", "1"),
        ("admin_groups", "created_at", "datetime('now')"),
        ("admin_groups", "updated_at", "datetime('now')"),
        ("admin_roles", "permissions", "'[]'"),
        ("admin_roles", "is_active", "1"),
        ("admin_roles", "created_at", "datetime('now')"),
        ("admin_roles", "updated_at", "datetime('now')"),
        ("focus_room_presence", "display_name", "''"),
        ("focus_room_presence", "raw_weekly_seconds", "0"),
        ("focus_room_presence", "weekly_seconds", "0"),
        ("focus_room_presence", "session_count", "0"),
        ("focus_room_presence", "active", "1"),
        ("focus_room_presence", "started_at", "NULL"),
        ("focus_room_presence", "last_seen_at", "NULL"),
        ("focus_room_presence", "risk_flags", "'[]'"),
        ("focus_room_presence", "risk_summary", "''"),
        ("focus_room_presence", "updated_at", "datetime('now')"),
        ("focus_room_invites", "description", "''"),
        ("focus_room_invites", "weekly_target_seconds", "18000"),
        ("focus_room_invites", "accent_color", "3762608"),
        ("focus_room_invites", "expires_at", "NULL"),
        ("focus_room_invites", "max_uses", "0"),
        ("focus_room_invites", "used_count", "0"),
        ("focus_room_invites", "last_used_at", "NULL"),
        ("focus_room_invites", "revoked", "0"),
        ("focus_friends", "status", "'accepted'"),
        ("focus_friends", "created_at", "datetime('now')"),
    ]:
        cur = conn.execute(f"PRAGMA table_info({table})")
        cols = {r["name"] for r in cur.fetchall()}
        if col not in cols:
            column_type = (
                "INTEGER"
                if isinstance(default, str) and default.isdigit()
                else "TEXT"
            )
            if default == "datetime('now')":
                conn.execute(f"ALTER TABLE {table} ADD COLUMN {col} {column_type}")
                conn.execute(
                    f"UPDATE {table} SET {col}=datetime('now') WHERE {col} IS NULL"
                )
            else:
                conn.execute(
                    f"ALTER TABLE {table} ADD COLUMN {col} {column_type} DEFAULT {default}"
                )

    conn.execute(
        "UPDATE users SET email=username WHERE email='' AND username LIKE '%@%'"
    )
    conn.execute(
        "UPDATE users SET email_verified=1 WHERE email<>'' AND username=email AND email_verified=0"
    )
    conn.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_nonempty "
        "ON users(email) WHERE email <> ''"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_email_verification_codes_email_purpose "
        "ON email_verification_codes(email, purpose, created_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_email_verification_codes_user_purpose "
        "ON email_verification_codes(user_id, purpose, created_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_users_created_at "
        "ON users(created_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_users_admin_disabled_created "
        "ON users(is_admin, is_disabled, created_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_users_last_login_at "
        "ON users(last_login_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_users_last_active_at "
        "ON users(last_active_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_feedback_status_category_id "
        "ON feedback(status, category, id)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_feedback_user_id "
        "ON feedback(user_id)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_feedback_user_created_status "
        "ON feedback(user_id, created_at, status)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_feedback_created_at "
        "ON feedback(created_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_announcements_published_level_id "
        "ON announcements(published, level, id)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_announcements_created_at "
        "ON announcements(created_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_invite_codes_used_created "
        "ON invite_codes(used_by, created_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_invite_codes_created_at "
        "ON invite_codes(created_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_invite_codes_used_at "
        "ON invite_codes(used_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_audit_log_action_id "
        "ON audit_log(action, id)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_server_backups_status_created "
        "ON server_backups(status, created_at)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_sync_data_updated_at "
        "ON sync_data(updated_at)"
    )

    existing_registration = {
        row["key"]: row["value"]
        for row in conn.execute(
            "SELECT key, value FROM settings WHERE key IN (?, ?)",
            ("registration_enabled", "invite_code_required"),
        ).fetchall()
    }
    default_settings = build_settings_defaults(SETTINGS, existing_registration)
    for k, v in default_settings.items():
        conn.execute(
            "INSERT OR IGNORE INTO settings(key, value) VALUES(?, ?)",
            (k, json.dumps(v)),
        )
    registration_coins_row = conn.execute(
        "SELECT value FROM settings WHERE key=?",
        ("default_registration_coins",),
    ).fetchone()
    try:
        registration_coins_value = int(json.loads(registration_coins_row["value"]))
    except Exception:
        registration_coins_value = 100
    if registration_coins_value < 0:
        registration_coins_value = 100
        conn.execute(
            "INSERT INTO settings(key, value) VALUES(?, ?) "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            ("default_registration_coins", json.dumps(100)),
        )
    default_group_time_coins = max(0, min(registration_coins_value, 1000000))
    conn.execute(
        "UPDATE users SET admin_permissions=? WHERE is_admin=0",
        (json.dumps([], ensure_ascii=False),),
    )
    conn.execute(
        """
        INSERT OR IGNORE INTO admin_groups(
            id, name, description, default_time_coins, default_generate_quota,
            default_edit_quota, default_generate_history_retention,
            default_edit_history_retention, image_mode, is_active
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            "group_default",
            "默认用户",
            "新注册用户默认分组。",
            default_group_time_coins,
            100,
            100,
            50,
            20,
            "vip",
            1,
        ),
    )
    conn.execute(
        """
        UPDATE admin_groups
        SET default_time_coins=?, updated_at=datetime('now')
        WHERE id='group_default'
          AND (default_time_coins IS NULL OR default_time_coins < 0)
        """,
        (default_group_time_coins,),
    )
    conn.execute(
        """
        INSERT OR IGNORE INTO admin_roles(id, name, description, permissions, is_active)
        VALUES(?, ?, ?, ?, ?)
        """,
        (
            "role_admin",
            "超级管理员",
            "拥有所有管理权限。",
            json.dumps([ADMIN_ALL_PERMISSION], ensure_ascii=False),
            1,
        ),
    )
    conn.execute(
        """
        UPDATE admin_roles
        SET permissions=?, updated_at=datetime('now')
        WHERE id='role_admin'
          AND (permissions IS NULL OR permissions='' OR permissions NOT LIKE ?)
        """,
        (
            json.dumps([ADMIN_ALL_PERMISSION], ensure_ascii=False),
            f'%"{ADMIN_ALL_PERMISSION}"%',
        ),
    )
    conn.execute(
        """
        INSERT OR IGNORE INTO admin_roles(id, name, description, permissions, is_active)
        VALUES(?, ?, ?, ?, ?)
        """,
        (
            "role_user",
            "普通用户",
            "无后台管理权限。",
            json.dumps([], ensure_ascii=False),
            1,
        ),
    )
    conn.execute(
        """
        UPDATE admin_roles
        SET permissions=?, updated_at=datetime('now')
        WHERE id='role_user'
        """,
        (json.dumps([], ensure_ascii=False),),
    )
    conn.execute(
        "UPDATE users SET group_id='group_default' WHERE group_id IS NULL OR group_id=''"
    )
    conn.execute(
        "UPDATE users SET role_id='role_admin' WHERE is_admin=1 AND (role_id IS NULL OR role_id='')"
    )
    conn.execute(
        """
        UPDATE users
        SET role_id='role_user'
        WHERE is_admin=0
          AND (
            role_id IS NULL OR role_id='' OR role_id='role_admin'
            OR role_id NOT IN (SELECT id FROM admin_roles WHERE is_active=1)
          )
        """
    )

    # Only a database with no pre-existing schema may receive a bootstrap admin.
    # Missing/renamed/deleted bootstrap users on an installation are never recreated.
    credentials = None
    if fresh_database:
        password = ADMIN_BOOTSTRAP_PASSWORD
        if not password.strip():
            password = secrets.token_urlsafe(32)
            credentials = {"username": ADMIN_BOOTSTRAP_USER, "password": password}
        admin_id = secrets.token_hex(16)
        conn.execute(
            "INSERT INTO users(id, username, password_hash, is_admin, admin_permissions, role_id) "
            "VALUES(?,?,?,?,?,?)",
            (
                admin_id,
                ADMIN_BOOTSTRAP_USER,
                _hash_password(password),
                1,
                json.dumps([ADMIN_ALL_PERMISSION]),
                "role_admin",
            ),
        )
        conn.execute("INSERT INTO sync_data(user_id) VALUES(?)", (admin_id,))
    for row in conn.execute("SELECT id FROM users").fetchall():
        _ensure_private_workspace(conn, row["id"])
    return credentials


def _private_workspace_id(user_id: str) -> str:
    return f"private:{user_id}"


def _ensure_private_workspace(db, user_id: str) -> None:
    workspace_id = _private_workspace_id(user_id)
    db.execute(
        "INSERT OR IGNORE INTO workspaces(id, name, owner_user_id, is_private) "
        "VALUES(?, '个人空间', ?, 1)",
        (workspace_id, user_id),
    )
    db.execute(
        "INSERT OR IGNORE INTO workspace_members(workspace_id, user_id, role) "
        "VALUES(?, ?, 'owner')",
        (workspace_id, user_id),
    )
    db.execute(
        "INSERT OR IGNORE INTO workspace_data(workspace_id) VALUES(?)",
        (workspace_id,),
    )


PASSWORD_HASH_SALT = SETTINGS.password_hash_salt


def _legacy_password_salt() -> str:
    return base64.b64decode("ZmluZ2VydGlwX3RpbWVfMjAyNg==").decode()


def _hash_password(password: str, salt: str = PASSWORD_HASH_SALT) -> str:
    return hashlib.sha256((salt + password).encode()).hexdigest()


def _legacy_hash_password(password: str) -> str:
    return _hash_password(password, _legacy_password_salt())


def _hash_reset_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _hash_email_code(code: str) -> str:
    return _hash_reset_token((code or "").strip())


def _normalize_email_code_provider(value: Optional[str]) -> str:
    provider = (value or "none").strip().lower()
    if provider == "openclaw":
        provider = "claw163"
    if provider == "openclaw_mail":
        provider = "claw163"
    return provider if provider in EMAIL_CODE_PROVIDERS else "none"


def _normalize_email_code_slot(value: Optional[str]) -> str:
    slot = (value or "primary").strip().lower()
    return slot if slot in EMAIL_CODE_SLOTS else "primary"


def _registration_enabled(db) -> bool:
    return bool(
        _setting_get(
            db,
            "allow_public_registration",
            _setting_get(db, "registration_enabled", True),
        )
    )


def _registration_invite_required(db) -> bool:
    return bool(
        _setting_get(
            db,
            "registration_invite_required",
            _setting_get(db, "invite_code_required", False),
        )
    )


def _looks_like_email(value: str) -> bool:
    return bool(re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", value.strip()))


def _clean_username(value: str) -> str:
    username = (value or "").strip()
    if not 3 <= len(username) <= 64:
        raise HTTPException(status_code=400, detail="用户名需为 3-64 个字符")
    if re.search(r"\s", username):
        raise HTTPException(status_code=400, detail="用户名不能包含空白字符")
    return username


def _clean_password(value: str) -> str:
    password = value or ""
    if len(password) < 6:
        raise HTTPException(status_code=400, detail="密码至少 6 位")
    if len(password) > 128:
        raise HTTPException(status_code=400, detail="密码过长")
    return password


def _clean_email(value: Optional[str]) -> str:
    email = (value or "").strip().lower()
    if not email:
        return ""
    if not _looks_like_email(email):
        raise HTTPException(status_code=400, detail="邮箱格式不正确")
    if len(email) > 128:
        raise HTTPException(status_code=400, detail="邮箱过长")
    return email


def _clean_short_text(value: Optional[str], max_len: int, field: str) -> str:
    text = (value or "").strip()
    if len(text) > max_len:
        raise HTTPException(status_code=400, detail=f"{field}不能超过 {max_len} 字")
    return text


def _find_user_by_identifier(db, identifier: str):
    value = (identifier or "").strip()
    if not value:
        return None
    lowered = value.lower()
    return db.execute(
        "SELECT * FROM users WHERE username=? OR lower(username)=? OR lower(email)=?",
        (value, lowered, lowered),
    ).fetchone()


def _ensure_account_unique(
    db,
    *,
    username: Optional[str] = None,
    email: Optional[str] = None,
    exclude_user_id: Optional[str] = None,
) -> None:
    checks = []
    params: list = []
    if username:
        checks.append("lower(username)=?")
        params.append(username.lower())
        checks.append("lower(email)=?")
        params.append(username.lower())
    if email:
        checks.append("lower(email)=?")
        params.append(email.lower())
        checks.append("lower(username)=?")
        params.append(email.lower())
    if not checks:
        return
    sql = "SELECT id FROM users WHERE (" + " OR ".join(checks) + ")"
    if exclude_user_id:
        sql += " AND id<>?"
        params.append(exclude_user_id)
    row = db.execute(sql, params).fetchone()
    if row is not None:
        raise HTTPException(status_code=409, detail="用户名或邮箱已被使用")


def _admin_permissions_from_text(raw) -> list[str]:
    try:
        decoded = json.loads(raw or "[]")
    except Exception:
        decoded = []
    if not isinstance(decoded, list):
        return []
    permissions: list[str] = []
    for item in decoded:
        text = str(item).strip()
        if not text:
            continue
        if text in {ADMIN_ALL_PERMISSION, ADMIN_NO_PERMISSION}:
            if text not in permissions:
                permissions.append(text)
            continue
        if text in ADMIN_PERMISSION_KEYS and text not in permissions:
            permissions.append(text)
    return permissions


def _normalize_admin_permissions(values: Optional[list[str]]) -> list[str]:
    if values is None:
        return []
    normalized: list[str] = []
    for item in values:
        text = str(item).strip()
        if not text:
            continue
        if text == ADMIN_NO_PERMISSION:
            return [ADMIN_NO_PERMISSION]
        if text == ADMIN_ALL_PERMISSION:
            return [ADMIN_ALL_PERMISSION]
        if text in ADMIN_PERMISSION_KEYS and text not in normalized:
            normalized.append(text)
    return normalized


def _admin_role_permissions(db, role_id: Optional[str]) -> list[str]:
    if not role_id:
        return []
    row = db.execute(
        "SELECT permissions FROM admin_roles WHERE id=? AND is_active=1",
        (role_id,),
    ).fetchone()
    if row is None:
        return []
    return _admin_permissions_from_text(row["permissions"])


def _merged_admin_permissions(row, db=None) -> list[str]:
    if row is None or not bool(row["is_admin"]) or bool(row["is_disabled"]):
        return []
    direct = _admin_permissions_for_response(
        row["admin_permissions"], is_admin=bool(row["is_admin"])
    )
    if ADMIN_ALL_PERMISSION in direct:
        return [ADMIN_ALL_PERMISSION]
    merged = list(direct)
    if db is not None:
        for permission in _admin_role_permissions(db, _row_get(row, "role_id", "")):
            if permission == ADMIN_ALL_PERMISSION:
                return [ADMIN_ALL_PERMISSION]
            if permission not in merged:
                merged.append(permission)
    return merged


def _admin_permission_catalog() -> list[dict]:
    return [
        {
            "code": key,
            "id": key,
            "name": ADMIN_PERMISSION_LABELS.get(key, key),
            "description": ADMIN_PERMISSION_DESCRIPTIONS.get(key, ""),
            "category": "后台管理",
        }
        for key in sorted(ADMIN_PERMISSION_KEYS)
    ]


def _admin_permissions_for_response(raw, *, is_admin: bool) -> list[str]:
    permissions = _admin_permissions_from_text(raw)
    if ADMIN_NO_PERMISSION in permissions:
        return []
    return permissions


def _admin_has_permission(row, permission: str, db=None) -> bool:
    if row is None or not row["is_admin"] or row["is_disabled"]:
        return False
    permissions = _admin_permissions_from_text(row["admin_permissions"])
    if not permissions and db is not None:
        permissions = _admin_role_permissions(db, _row_get(row, "role_id", ""))
    if not permissions:
        return False
    if ADMIN_NO_PERMISSION in permissions:
        return False
    return ADMIN_ALL_PERMISSION in permissions or permission in permissions


def _ensure_admin_permission(db, user_id: str, permission: str) -> None:
    row = db.execute(
        "SELECT is_admin, is_disabled, admin_permissions, role_id FROM users WHERE id=?",
        (user_id,),
    ).fetchone()
    if not _admin_has_permission(row, permission, db=db):
        raise HTTPException(status_code=403, detail="Admin permission required")


def _ensure_admin_any_permission(db, user_id: str, permissions: tuple[str, ...]) -> None:
    row = db.execute(
        "SELECT is_admin, is_disabled, admin_permissions, role_id FROM users WHERE id=?",
        (user_id,),
    ).fetchone()
    if not any(_admin_has_permission(row, permission, db=db) for permission in permissions):
        raise HTTPException(status_code=403, detail="Admin permission required")


def _ensure_admin_management_permission(db, user_id: str) -> None:
    _ensure_admin_any_permission(db, user_id, ("roles", "permissions"))


def _admin_has_all_permissions(db, user_id: str) -> bool:
    row = db.execute(
        "SELECT is_admin, is_disabled, admin_permissions, role_id FROM users WHERE id=?",
        (user_id,),
    ).fetchone()
    return ADMIN_ALL_PERMISSION in _merged_admin_permissions(row, db=db)


def _ensure_admin_can_assign_permissions(
    db, actor: str, permissions: list[str]
) -> None:
    if ADMIN_ALL_PERMISSION not in permissions:
        return
    if _admin_has_all_permissions(db, actor):
        return
    raise HTTPException(status_code=403, detail="Admin permission required")


def _ensure_admin_can_assign_role(db, actor: str, role_id: str) -> None:
    if ADMIN_ALL_PERMISSION not in _admin_role_permissions(db, role_id):
        return
    if _admin_has_all_permissions(db, actor):
        return
    raise HTTPException(status_code=403, detail="Admin permission required")


def _json_object(raw) -> dict:
    try:
        value = json.loads(raw or "{}")
    except Exception:
        return {}
    return value if isinstance(value, dict) else {}


def _virtual_rewards_summary(raw) -> tuple[int, int]:
    rewards = _json_object(raw)
    balance = (rewards.get("balance") if isinstance(rewards, dict) else 0)
    lifetime = (rewards.get("lifetime") if isinstance(rewards, dict) else balance)
    return (
        int(balance) if isinstance(balance, (int, float)) else 0,
        int(lifetime) if isinstance(lifetime, (int, float)) else 0,
    )


THEME_SHOP_CATALOG = {
    "brand": {
        "defaultBrand": 0,
        "re0": 140,
        "genshin": 160,
        "starRail": 180,
        "wuthering": 200,
        "zzz": 220,
        "yanyun": 240,
        "botw": 260,
        # Keep every client theme ID available to legacy apply/sync routes.
        "liquidGlass": 280,
    },
    "focus_backdrop": {
        "classic_focus": 0,
        "morning_focus": 80,
        "forest_focus": 100,
        "ocean_focus": 100,
        "night_focus": 120,
    },
    "avatar_frame": {
        "simple_frame": 0,
        "golden_frame": 90,
        "forest_frame": 100,
        "aurora_frame": 120,
    },
    "card_skin": {
        "plain_card": 0,
        "paper_card": 90,
        "mint_card": 100,
        "starlight_card": 120,
    },
}

THEME_SHOP_TYPE_ALIASES = {
    "brand": "brand",
    "theme": "brand",
    "app_brand": "brand",
    "appBrand": "brand",
    "focus": "focus_backdrop",
    "focus_backdrop": "focus_backdrop",
    "focusBackdrop": "focus_backdrop",
    "focus-backdrop": "focus_backdrop",
    "avatar": "avatar_frame",
    "avatar_frame": "avatar_frame",
    "avatarFrame": "avatar_frame",
    "avatar-frame": "avatar_frame",
    "card": "card_skin",
    "card_skin": "card_skin",
    "cardSkin": "card_skin",
    "card-skin": "card_skin",
}

THEME_SHOP_DEFAULTS = {
    "brand": "defaultBrand",
    "focus_backdrop": "classic_focus",
    "avatar_frame": "simple_frame",
    "card_skin": "plain_card",
}

THEME_SHOP_FIELDS = {
    "brand": ("activeBrand", "unlockedBrandIds"),
    "focus_backdrop": ("activeFocusBackdropId", "unlockedFocusBackdropIds"),
    "avatar_frame": ("activeAvatarFrameId", "unlockedAvatarFrameIds"),
    "card_skin": ("activeCardSkinId", "unlockedCardSkinIds"),
}


def _theme_shop_type(raw: Optional[str]) -> str:
    text = str(raw or "").strip()
    normalized = THEME_SHOP_TYPE_ALIASES.get(text)
    if not normalized:
        raise HTTPException(status_code=400, detail="主题商店类型无效")
    return normalized


def _theme_shop_cost(item_type: str, item_id: str) -> int:
    catalog = THEME_SHOP_CATALOG.get(item_type) or {}
    if item_id not in catalog:
        raise HTTPException(status_code=400, detail="主题商店物品不存在")
    return 0


def _theme_shop_list(value) -> list[str]:
    if not isinstance(value, list):
        return []
    result: list[str] = []
    for item in value:
        text = str(item or "").strip()
        if text and text not in result:
            result.append(text)
    return result


def _normalize_theme_shop_state(raw: dict) -> dict:
    state = dict(raw if isinstance(raw, dict) else {})
    for item_type, default_id in THEME_SHOP_DEFAULTS.items():
        active_key, unlocked_key = THEME_SHOP_FIELDS[item_type]
        catalog = THEME_SHOP_CATALOG[item_type]
        unlocked = _theme_shop_list(state.get(unlocked_key))
        for item_id in catalog:
            if item_id not in unlocked:
                unlocked.append(item_id)
        active = str(state.get(active_key) or "").strip()
        if active not in catalog:
            active = default_id
        state[active_key] = active
        state[unlocked_key] = unlocked
    try:
        state["switchCount"] = max(0, int(state.get("switchCount") or 0))
    except Exception:
        state["switchCount"] = 0
    updated_at = str(state.get("updatedAt") or state.get("updated_at") or "").strip()
    if updated_at:
        state["updatedAt"] = updated_at
    state.pop("updated_at", None)
    return state


def _quota_aliases_from_rewards(raw) -> dict:
    # 生图/改图能力当前没有真实端到端实现，旧 rewards 字段仅保留数据兼容，
    # 不再通过管理接口暴露为可配置能力。
    return {}


# Cloudflare/WAF 会以 "error code: 1010" 拦截默认的 Python-urllib UA，
# 因此 AI 上游请求必须带一个稳定的客户端标识。
AI_UPSTREAM_USER_AGENT = "duoyi-backend/1.1"
AI_CHAT_TIMEOUT_SECONDS = 150  # Long reports can include hidden reasoning first.


def _ai_chat_completions_url(base_url: str) -> str:
    base = (base_url or "https://api.openai.com").strip().rstrip("/")
    if base.endswith("/chat/completions"):
        return base
    if base.endswith("/v1"):
        return f"{base}/chat/completions"
    return f"{base}/v1/chat/completions"


def _ai_chat_text_from_parts(value) -> str:
    """Normalize string / content-part responses into plain assistant text."""
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        chunks: list[str] = []
        for part in value:
            if isinstance(part, str):
                chunks.append(part)
                continue
            if not isinstance(part, dict):
                continue
            if part.get("type") not in {None, "text", "output_text"}:
                continue
            text = part.get("text")
            if isinstance(text, str):
                chunks.append(text)
            elif isinstance(text, dict) and isinstance(text.get("value"), str):
                chunks.append(text["value"])
        return "".join(chunks)
    return str(value)


def _ai_chat_response_from_sse(body: str) -> Optional[dict]:
    """Buffer a completed OpenAI/Anthropic stream without exposing reasoning."""
    payloads: list[dict] = []
    data_lines: list[str] = []
    event_name = ""
    saw_sse = False
    completed = False

    def flush_data() -> None:
        nonlocal completed
        if not data_lines:
            return
        raw = "\n".join(data_lines).strip()
        data_lines.clear()
        if raw == "[DONE]":
            completed = True
            return
        try:
            value = json.loads(raw)
        except ValueError:
            raise ValueError("SSE 数据帧不是有效 JSON") from None
        if not isinstance(value, dict):
            raise ValueError("SSE 数据帧不是 JSON 对象")
        if event_name:
            value.setdefault("type", event_name)
        payloads.append(value)

    for line in body.lstrip("\ufeff").splitlines():
        if not line.strip():
            flush_data()
            event_name = ""
        elif line.startswith(":"):
            saw_sse = True
        elif line.startswith("event:"):
            saw_sse = True
            event_name = line[len("event:") :].strip()
        elif line.startswith("data:"):
            saw_sse = True
            data_lines.append(line[len("data:") :].lstrip())
    flush_data()
    if not saw_sse:
        return None

    chunks: list[str] = []
    finish_reason = ""
    usage: dict = {}
    for event in payloads:
        event_type = event.get("type")
        if event_type == "error" or event.get("error"):
            return {"error": event.get("error") or {"message": "上游流返回错误"}}
        if event_type == "message_stop":
            completed = True
        elif event_type == "message_start":
            message = event.get("message") or {}
            if isinstance(message, dict):
                text = _ai_chat_content_from_response(message)
                if text:
                    chunks.append(text)
                if isinstance(message.get("usage"), dict):
                    usage.update(message["usage"])
        elif event_type == "content_block_start":
            block = event.get("content_block") or {}
            if isinstance(block, dict) and block.get("type") == "text":
                chunks.append(_ai_chat_text_from_parts([block]))
        elif event_type == "content_block_delta":
            delta = event.get("delta") or {}
            if isinstance(delta, dict) and delta.get("type") == "text_delta":
                text = delta.get("text")
                if isinstance(text, str):
                    chunks.append(text)
        elif event_type == "message_delta":
            delta = event.get("delta") or {}
            if isinstance(delta, dict) and delta.get("stop_reason"):
                finish_reason = str(delta["stop_reason"])

        choices = event.get("choices") or []
        if not isinstance(choices, list):
            raise ValueError("SSE choices 不是列表")
        for choice in choices:
            if not isinstance(choice, dict) or choice.get("index", 0) != 0:
                continue
            delta = choice.get("delta") or {}
            text = ""
            if isinstance(delta, dict):
                text = _ai_chat_text_from_parts(delta.get("content"))
            if not text:
                text = _ai_chat_content_from_response({"choices": [choice]})
            if text:
                chunks.append(text)
            if choice.get("finish_reason"):
                finish_reason = str(choice["finish_reason"])
        if isinstance(event.get("usage"), dict):
            usage.update(event["usage"])

    if not completed and not finish_reason:
        raise ValueError("SSE 流未完整结束，请重试")
    return {
        "choices": [
            {
                "message": {"content": "".join(chunks)},
                "finish_reason": finish_reason,
            }
        ],
        "usage": usage,
    }


def _ai_chat_content_from_response(data: dict) -> str:
    """Return only the assistant answer; reasoning text is never user content."""
    choices = data.get("choices") or []
    if choices:
        choice = choices[0] if isinstance(choices[0], dict) else {}
        message = choice.get("message") or {}
        if isinstance(message, dict):
            text = _ai_chat_text_from_parts(message.get("content")).strip()
            if text:
                return text
        # Legacy completions shape used by some compatible gateways.
        text = _ai_chat_text_from_parts(choice.get("text")).strip()
        if text:
            return text

    # Anthropic Messages responses put visible text at the top level.
    text = _ai_chat_text_from_parts(data.get("content")).strip()
    if text:
        return text
    message = data.get("message")
    if isinstance(message, dict):
        text = _ai_chat_text_from_parts(message.get("content")).strip()
        if text:
            return text

    output_text = data.get("output_text")
    if output_text is not None:
        return _ai_chat_text_from_parts(output_text).strip()
    return ""


def _ai_chat_reply_meta(data: dict) -> dict:
    """Diagnostics needed to explain an empty reply without leaking content."""
    choices = data.get("choices") or []
    choice = choices[0] if choices and isinstance(choices[0], dict) else {}
    message = choice.get("message") or {}
    if not isinstance(message, dict):
        message = {}
    usage = data.get("usage")
    if not isinstance(usage, dict):
        usage = {}
    details = usage.get("completion_tokens_details")
    if not isinstance(details, dict):
        details = {}
    raw_reasoning = details.get(
        "reasoning_tokens",
        usage.get("reasoning_tokens", usage.get("thinking_tokens")),
    )
    try:
        reasoning_tokens = int(raw_reasoning or 0)
    except (TypeError, ValueError):
        reasoning_tokens = 0
    raw_completion = usage.get("completion_tokens", usage.get("output_tokens"))
    try:
        completion_tokens = int(raw_completion or 0)
    except (TypeError, ValueError):
        completion_tokens = 0
    reasoning_text = message.get("reasoning_content")
    return {
        "finish_reason": str(
            choice.get("finish_reason")
            or data.get("stop_reason")
            or data.get("finish_reason")
            or ""
        ),
        "reasoning_tokens": reasoning_tokens,
        "completion_tokens": completion_tokens,
        "has_reasoning_text": isinstance(reasoning_text, str)
        and bool(reasoning_text.strip()),
    }


def _ai_chat_empty_content_detail(meta: dict) -> str:
    finish_reason = meta.get("finish_reason") or "未知"
    reasoning_tokens = int(meta.get("reasoning_tokens") or 0)
    completion_tokens = int(meta.get("completion_tokens") or 0)
    reasoning_detail = (
        f"，思考 {reasoning_tokens} tokens"
        if reasoning_tokens > 0
        else "，检测到思考内容" if meta.get("has_reasoning_text") else ""
    )
    if finish_reason in {"length", "max_tokens"}:
        return (
            "模型已达到输出上限，正文为空"
            f"（finish_reason={finish_reason}，输出 {completion_tokens} tokens{reasoning_detail}）。"
            "请调大 max_tokens 或改用非推理模型。"
        )
    if reasoning_detail:
        return (
            f"模型仅返回思考，正文为空（finish_reason={finish_reason}{reasoning_detail}），"
            "请检查模型与网关的正文输出配置。"
        )
    return (
        f"上游返回空内容（finish_reason={finish_reason}），"
        "请检查模型名称、请求参数与网关配置。"
    )


def _call_ai_chat_upstream(
    *,
    base_url: str,
    api_key: str,
    model: str,
    messages: list[dict],
    temperature: float,
    max_tokens: int,
    timeout: int,
    require_content: bool = True,
) -> tuple[str, dict]:
    import urllib.request
    import urllib.error

    payload = json.dumps(
        {
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "stream": False,
        },
        ensure_ascii=False,
    ).encode("utf-8")

    upstream = urllib.request.Request(
        _ai_chat_completions_url(base_url),
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
            # Some gateways sit behind Cloudflare/WAF rules that reject the
            # default Python-urllib UA with "error code: 1010".
            "User-Agent": AI_UPSTREAM_USER_AGENT,
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(upstream, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        text = e.read().decode("utf-8", errors="replace")
        raise HTTPException(status_code=e.code, detail=f"上游错误: {text[:200]}")
    except urllib.error.URLError as e:
        if isinstance(e.reason, TimeoutError):
            raise HTTPException(status_code=504, detail=f"AI 上游响应超时（等待 {timeout} 秒），请稍后重试")
        raise HTTPException(status_code=502, detail=f"上游不可达: {e}")
    except TimeoutError:
        raise HTTPException(status_code=504, detail=f"AI 上游响应超时（等待 {timeout} 秒），请稍后重试")
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"上游不可达: {e}")

    try:
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            data = _ai_chat_response_from_sse(body)
            if data is None:
                raise
        if not isinstance(data, dict):
            raise ValueError("上游响应不是 JSON 对象")
        content = _ai_chat_content_from_response(data)
    except (ValueError, TypeError, AttributeError) as e:
        raise HTTPException(status_code=502, detail=f"上游响应格式错误（预期 JSON 或 SSE）：{e}")

    upstream_error = data.get("error")
    if upstream_error:
        if isinstance(upstream_error, dict):
            detail = str(upstream_error.get("message") or upstream_error.get("type") or "未知错误")
        else:
            detail = str(upstream_error)
        raise HTTPException(status_code=502, detail=f"上游错误: {detail[:200]}")

    if require_content and not content:
        # Reasoning models spend the whole max_tokens budget on thinking and
        # then return an empty answer; surface it instead of a blank reply.
        raise HTTPException(
            status_code=502,
            detail=_ai_chat_empty_content_detail(_ai_chat_reply_meta(data)),
        )
    return content, data


def _merge_virtual_rewards(server: dict, client: dict) -> dict:
    if not isinstance(server, dict):
        server = {}
    if not isinstance(client, dict):
        client = {}
    if not server:
        return client
    if not client:
        return server

    def _num(value, fallback=0) -> int:
        return int(value) if isinstance(value, (int, float)) else fallback

    def _ledger_items(value) -> list[dict]:
        if not isinstance(value, list):
            return []
        return [dict(item) for item in value if isinstance(item, dict)]

    server_ledger = _ledger_items(server.get("ledger"))
    client_ledger = _ledger_items(client.get("ledger"))
    server_ids = {str(item.get("id") or "") for item in server_ledger}
    client_ids = {str(item.get("id") or "") for item in client_ledger}
    server_unique = [
        item for item in server_ledger if str(item.get("id") or "") not in client_ids
    ]
    client_unique = [
        item for item in client_ledger if str(item.get("id") or "") not in server_ids
    ]

    server_balance = _num(server.get("balance"))
    client_balance = _num(client.get("balance"))
    if server_balance >= client_balance:
        balance = server_balance + sum(_num(item.get("coins")) for item in client_unique)
    else:
        balance = client_balance + sum(_num(item.get("coins")) for item in server_unique)
    balance = max(0, balance)

    server_lifetime = _num(server.get("lifetime"), server_balance)
    client_lifetime = _num(client.get("lifetime"), client_balance)
    if server_lifetime >= client_lifetime:
        lifetime = server_lifetime + sum(
            max(0, _num(item.get("coins"))) for item in client_unique
        )
    else:
        lifetime = client_lifetime + sum(
            max(0, _num(item.get("coins"))) for item in server_unique
        )
    lifetime = max(lifetime, balance)

    grant_ids = [
        str(v)
        for v in [*(server.get("grantIds") or []), *(client.get("grantIds") or [])]
        if str(v)
    ]
    combined_ledger = []
    seen = set()
    for item in [*server_ledger, *client_ledger]:
        item_id = str(item.get("id") or "")
        if item_id and item_id in seen:
            continue
        if item_id:
            seen.add(item_id)
        combined_ledger.append(item)
    combined_ledger.sort(
        key=lambda item: str(item.get("awardedAt") or item.get("createdAt") or ""),
        reverse=True,
    )

    server_ts = _item_updated_at(server)
    client_ts = _item_updated_at(client)
    updated_at = client_ts if _timestamp_gt(client_ts, server_ts) else server_ts
    result = dict(server if not _timestamp_gt(client_ts, server_ts) else client)
    result.update(
        {
            "balance": balance,
            "lifetime": lifetime,
            "grantIds": list(dict.fromkeys(grant_ids)),
            "ledger": combined_ledger[:50],
        }
    )
    if updated_at:
        result["updatedAt"] = updated_at
    return result


def _user_response(
    row,
    *,
    token: Optional[str] = None,
    db=None,
) -> dict:
    permissions = _merged_admin_permissions(row, db=db)
    role_id = _row_get(row, "role_id", "") or ("role_admin" if row["is_admin"] else "role_user")
    group_id = _row_get(row, "group_id", "") or "group_default"
    result = {
        "id": row["id"],
        "user_id": row["id"],
        "username": row["username"],
        "identifier": row["username"],
        "can_edit_username": False,
        "email": row["email"] or "",
        "email_verified": bool(row["email_verified"]),
        "avatar": row["avatar"] or "",
        "avatar_url": row["avatar"] or "",
        "display_name": row["display_name"] or "",
        "bio": row["bio"] or "",
        "is_admin": bool(row["is_admin"]),
        "admin_permissions": permissions,
        "permissions": permissions,
        "group_id": group_id,
        "role_id": role_id,
        "group": {"id": group_id},
        "role": {"id": role_id},
        "is_disabled": bool(row["is_disabled"]),
        "is_active": not bool(row["is_disabled"]),
        "created_at": row["created_at"],
        "last_login_at": row["last_login_at"],
    }
    if db is not None:
        sync_row = db.execute(
            "SELECT virtual_rewards, theme_shop_state FROM sync_data WHERE user_id=?",
            (row["id"],),
        ).fetchone()
        coin_balance, lifetime_coins = _virtual_rewards_summary(
            sync_row["virtual_rewards"] if sync_row else "{}"
        )
        result["coin_balance"] = coin_balance
        result["lifetime_coins"] = lifetime_coins
        result["virtual_rewards"] = _json_object(
            sync_row["virtual_rewards"] if sync_row else "{}"
        )
        theme_shop_state = _normalize_theme_shop_state(
            _json_object(sync_row["theme_shop_state"] if sync_row else "{}")
        )
        result["theme_shop_state"] = theme_shop_state
        result["themeShopState"] = theme_shop_state
        result["active_brand"] = theme_shop_state.get("activeBrand")
        result["activeBrand"] = theme_shop_state.get("activeBrand")
        result.update(
            _quota_aliases_from_rewards(
                sync_row["virtual_rewards"] if sync_row else "{}"
            )
        )
    if token is not None:
        result["token"] = token
    result.update(_quota_aliases_from_rewards(_row_get(row, "virtual_rewards", "{}")))
    return result


def _row_get(row, key: str, default=None):
    try:
        return row[key]
    except Exception:
        return default


def _setting_get(db, key: str, default=None):
    row = db.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
    if row is None:
        return default
    try:
        return json.loads(row["value"])
    except Exception:
        return row["value"]


def _setting_set(db, key: str, value) -> None:
    db.execute(
        "INSERT INTO settings(key, value) VALUES(?, ?) "
        "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        (key, json.dumps(value)),
    )


def _first_setting(db, keys: list[str], default=""):
    for key in keys:
        value = _setting_get(db, key, None)
        if value is not None and str(value).strip() != "":
            return value
    return default


def _account_mail_runtime(db) -> dict:
    smtp_host = _first_setting(
        db,
        [
            "email_smtp_host",
            "EMAIL_SMTP_HOST",
            "SMTP_HOST",
            "MAIL_SMTP_HOST",
            "MAIL_HOST",
            "reminder_email_smtp_host",
            "backup_email_smtp_host",
        ],
        "",
    )
    smtp_port = _first_setting(
        db,
        [
            "email_smtp_port",
            "EMAIL_SMTP_PORT",
            "SMTP_PORT",
            "MAIL_SMTP_PORT",
            "MAIL_PORT",
            "reminder_email_smtp_port",
            "backup_email_smtp_port",
        ],
        465,
    )
    smtp_username = _first_setting(
        db,
        [
            "email_smtp_username",
            "EMAIL_SMTP_USERNAME",
            "EMAIL_ADDRESS",
            "SMTP_USERNAME",
            "SMTP_USER",
            "MAIL_SMTP_USERNAME",
            "MAIL_USERNAME",
            "MAIL_USER",
            "MAIL_ADDRESS",
            "reminder_email_smtp_username",
            "backup_email_smtp_username",
        ],
        "",
    )
    smtp_password = _first_setting(
        db,
        [
            "email_smtp_password",
            "EMAIL_SMTP_PASSWORD",
            "EMAIL_PASSWORD",
            "SMTP_PASSWORD",
            "SMTP_PASS",
            "MAIL_SMTP_PASSWORD",
            "MAIL_PASSWORD",
            "MAIL_PASS",
            "reminder_email_smtp_password",
            "backup_email_smtp_password",
        ],
        "",
    )
    smtp_use_ssl = _setting_get(db, "email_smtp_use_ssl", None)
    if smtp_use_ssl is None:
        smtp_use_ssl = _setting_get(db, "reminder_email_smtp_use_ssl", None)
    if smtp_use_ssl is None:
        smtp_use_ssl = _setting_get(db, "backup_email_smtp_use_ssl", None)
    if smtp_use_ssl is None:
        smtp_use_ssl = int(smtp_port or 465) == 465
    return {
        "email_service_enabled": bool(
            _setting_get(db, "email_service_enabled", True)
        ),
        "email_title": str(
            _first_setting(
                db,
                [
                    "email_title",
                    "EMAIL_TITLE",
                    "APP_TITLE",
                    "TITLE",
                    "DUOYI_TITLE",
                ],
                DEFAULT_EMAIL_TITLE,
            )
            or DEFAULT_EMAIL_TITLE
        ),
        "email_sender_name": str(
            _first_setting(
                db,
                [
                    "email_sender_name",
                    "EMAIL_SENDER_NAME",
                    "EMAIL_FROM_NAME",
                    "MAIL_FROM_NAME",
                    "SENDER_NAME",
                ],
                DEFAULT_EMAIL_SENDER_NAME,
            )
            or DEFAULT_EMAIL_SENDER_NAME
        ),
        "email_code_primary_provider": _normalize_email_code_provider(
            _setting_get(db, "email_code_primary_provider", "claw163")
        ),
        "email_code_backup_provider": _normalize_email_code_provider(
            _setting_get(db, "email_code_backup_provider", "resend")
        ),
        "email_code_active_slot": _normalize_email_code_slot(
            _setting_get(db, "email_code_active_slot", "primary")
        ),
        "email_auto_switch_enabled": bool(
            _setting_get(db, "email_auto_switch_enabled", False)
        ),
        "openclaw_mail_enabled": bool(_setting_get(db, "openclaw_mail_enabled", False)),
        "openclaw_mail_user": str(_setting_get(db, "openclaw_mail_user", "") or "").strip(),
        "openclaw_mail_api_key": str(_setting_get(db, "openclaw_mail_api_key", "") or "").strip(),
        "resend_base_url": str(
            _setting_get(db, "resend_base_url", "https://api.resend.com")
            or "https://api.resend.com"
        ).strip().rstrip("/"),
        "resend_api_key": str(_setting_get(db, "resend_api_key", "") or "").strip(),
        "resend_from": str(_setting_get(db, "resend_from", DEFAULT_RESEND_FROM) or "").strip(),
        "hermes_base_url": str(_setting_get(db, "hermes_base_url", "") or "").strip().rstrip("/"),
        "hermes_api_key": str(_setting_get(db, "hermes_api_key", "") or "").strip(),
        "system_notice_email_to": str(_setting_get(db, "system_notice_email_to", "") or ""),
        "email_smtp_host": str(smtp_host or "").strip(),
        "email_smtp_port": int(smtp_port or 465),
        "email_smtp_username": str(smtp_username or "").strip(),
        "email_smtp_password": str(smtp_password or ""),
        "email_smtp_use_ssl": bool(smtp_use_ssl),
        "email_smtp_from": str(
            _first_setting(
                db,
                [
                    "email_smtp_from",
                    "EMAIL_SMTP_FROM",
                    "EMAIL_FROM",
                    "MAIL_FROM",
                    "SMTP_FROM",
                    "reminder_email_from",
                    "backup_email_from",
                ],
                "",
            )
            or smtp_username
            or ""
        ).strip(),
    }


def _audit(db, actor_id: Optional[str], actor_name: Optional[str], action: str,
           target: str = "", detail: str = "") -> None:
    db.execute(
        "INSERT INTO audit_log(actor_id, actor_name, action, target, detail) VALUES(?,?,?,?,?)",
        (actor_id, actor_name, action, target, detail),
    )


def _workspace_activity(
    db,
    actor_id: str,
    action: str,
    workspace_id: str,
    detail: str = "",
) -> None:
    db.execute(
        """
        INSERT INTO workspace_activity(workspace_id, actor_user_id, actor_name, action, detail)
        VALUES(?,?,?,?,?)
        """,
        (workspace_id, actor_id, _get_username(db, actor_id), action, detail),
    )


def _verify_token(authorization: Optional[str] = Header(None)) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing token")
    return _verify_token_value(authorization[7:])


def _verify_token_in_db(db, token: Optional[str], *, expected_user_id: Optional[str] = None):
    """Validate the original credential using the caller's write transaction."""
    if not token:
        raise HTTPException(status_code=401, detail="Missing token")
    session = db.execute(
        "SELECT * FROM login_sessions WHERE token_hash=?",
        (_hash_login_session_token(token),),
    ).fetchone()
    access_token = None
    if session is not None:
        # The persisted session row is authoritative; never trust the cache alone.
        expires_at = _parse_server_time(session["expires_at"])
        if expires_at is None or expires_at <= _utc_now():
            _forget_cached_token(token)
            raise HTTPException(status_code=401, detail="Invalid or expired token")
        user_id = session["user_id"]
    else:
        access_token = db.execute(
            "SELECT * FROM access_tokens WHERE token_hash=?",
            (_hash_access_token(token),),
        ).fetchone()
        if access_token is None or access_token["revoked_at"] is not None:
            _forget_cached_token(token)
            raise HTTPException(status_code=401, detail="Invalid or expired token")
        expires_at = _parse_server_time(access_token["expires_at"])
        if access_token["expires_at"] is not None and (
            expires_at is None or expires_at <= _utc_now()
        ):
            raise HTTPException(status_code=401, detail="Invalid or expired token")
        user_id = access_token["user_id"]
    if expected_user_id is not None and user_id != expected_user_id:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    row = db.execute("SELECT is_disabled FROM users WHERE id=?", (user_id,)).fetchone()
    if row is None:
        _drop_session(user_id, db)
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    if row["is_disabled"]:
        _revoke_user_token(user_id, db)
        db.commit()
        raise HTTPException(status_code=403, detail="Account disabled")
    return user_id, access_token


def _verify_token_value(token: Optional[str]) -> str:
    db = get_db()
    try:
        # Serialize validation and activity writes with revocation; never cache PATs.
        db.execute("BEGIN IMMEDIATE")
        user_id, access_token = _verify_token_in_db(db, token)
        now = _utc_now()
        now_text = _format_utc(now)
        if access_token is not None:
            db.execute(
                "UPDATE access_tokens SET last_used_at=? WHERE id=?",
                (now_text, access_token["id"]),
            )
        else:
            db.execute(
                "UPDATE login_sessions SET last_used_at=? WHERE user_id=? AND token_hash=?",
                (now_text, user_id, _hash_login_session_token(token or "")),
            )
        db.execute("UPDATE users SET last_active_at=? WHERE id=?", (now_text, user_id))
        db.commit()
    finally:
        db.close()
    if access_token is None:
        TOKEN_LAST_ACTIVE[user_id] = now
    return user_id


def _require_admin(user_id: str = Depends(_verify_token)) -> str:
    db = get_db()
    try:
        row = db.execute(
            "SELECT is_admin, is_disabled, username FROM users WHERE id=?", (user_id,)
        ).fetchone()
        if row is None or not row["is_admin"]:
            raise HTTPException(status_code=403, detail="Admin only")
        if row["is_disabled"]:
            raise HTTPException(status_code=403, detail="Account disabled")
        return user_id
    finally:
        db.close()


def _get_username(db, user_id: str) -> str:
    row = db.execute("SELECT username FROM users WHERE id=?", (user_id,)).fetchone()
    return row["username"] if row else "?"


init_db()


# ---- Schemas ----


class RegisterRequest(BaseModel):
    username: str
    password: str
    email: Optional[str] = None
    email_code: Optional[str] = None
    display_name: Optional[str] = None
    invite_code: Optional[str] = None
    invitation_code: Optional[str] = None


class LoginRequest(BaseModel):
    username: Optional[str] = None
    account: Optional[str] = None
    email: Optional[str] = None
    password: str


class AccessTokenCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=80, strict=True)
    expires_in_days: Optional[int] = Field(default=None, ge=1, le=3650, strict=True)

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Token name must not be blank")
        return value


class ProfileUpdate(BaseModel):
    username: Optional[str] = None
    email: Optional[str] = None
    code: Optional[str] = None
    email_code: Optional[str] = None
    emailCode: Optional[str] = None
    display_name: Optional[str] = None
    displayName: Optional[str] = None
    avatar: Optional[str] = None
    avatar_url: Optional[str] = None
    avatarUrl: Optional[str] = None
    bio: Optional[str] = None


class EmailCodeRequest(BaseModel):
    email: str
    purpose: str = "login"


class EmailLoginRequest(BaseModel):
    email: str
    code: Optional[str] = None
    email_code: Optional[str] = None
    emailCode: Optional[str] = None


class ChangePasswordRequest(BaseModel):
    current_password: Optional[str] = None
    currentPassword: Optional[str] = None
    old_password: Optional[str] = None
    new_password: Optional[str] = None
    newPassword: Optional[str] = None
    password: Optional[str] = None


class PasswordResetRequest(BaseModel):
    username: Optional[str] = None
    identifier: Optional[str] = None
    account: Optional[str] = None
    email: Optional[str] = None


class PasswordResetConfirm(BaseModel):
    token: Optional[str] = None
    code: Optional[str] = None
    username: Optional[str] = None
    identifier: Optional[str] = None
    account: Optional[str] = None
    email: Optional[str] = None
    password: Optional[str] = None
    new_password: Optional[str] = None


class SyncRequest(BaseModel):
    todos: list = []
    habits: list = []
    pomodoro_sessions: list = []
    focus_penalties: list = []
    pomodoro_config: dict = {}
    user_profile: dict = {}
    # —— 对齐竞品能力所需的新数据类型 ——
    notes: list = []
    countdowns: list = []
    anniversaries: list = []
    diaries: list = []
    goals: list = []
    calendar_events: list = []
    courses: list = []
    time_entries: list = []
    location_reminders: list = []
    course_settings: dict = {}
    achievement_states: dict = {}
    virtual_rewards: dict = {}
    focus_rooms: dict = {}
    theme_shop_state: dict = {}
    preferences: dict = {}
    quick_capture_templates: dict = {}
    list_groups: list = []
    deleted_items: dict = {}
    workspace_payloads: dict = {}


class ThemeShopApplyRequest(BaseModel):
    item_type: Optional[str] = None
    itemType: Optional[str] = None
    type: Optional[str] = None
    item_id: Optional[str] = None
    itemId: Optional[str] = None
    id: Optional[str] = None
    title: Optional[str] = None
    name: Optional[str] = None
    activate: Optional[bool] = None
    enabled: Optional[bool] = None


class SyncPullRequest(BaseModel):
    collection_hashes: dict = {}


class SyncDeltaRequest(BaseModel):
    collections: dict = {}
    collection_hashes: dict = {}


class SyncItemDeltaRequest(BaseModel):
    items: dict = {}
    objects: dict = {}
    deleted_items: dict = {}
    collection_hashes: dict = {}


class _FocusRoomAliasModel(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="ignore")


class FocusRoomHeartbeatRequest(_FocusRoomAliasModel):
    display_name: Optional[str] = Field(
        default=None,
        validation_alias=AliasChoices("display_name", "displayName"),
    )
    weekly_seconds: int = Field(
        default=0,
        validation_alias=AliasChoices("weekly_seconds", "weeklySeconds"),
    )
    session_count: int = Field(
        default=0,
        validation_alias=AliasChoices("session_count", "sessionCount"),
    )
    active: bool = True
    started_at: Optional[str] = Field(
        default=None,
        validation_alias=AliasChoices("started_at", "startedAt"),
    )


class FocusRoomInviteCreate(_FocusRoomAliasModel):
    room_name: str = Field(
        default="",
        validation_alias=AliasChoices("room_name", "roomName", "name"),
    )
    description: str = ""
    weekly_target_seconds: int = Field(
        default=18000,
        validation_alias=AliasChoices(
            "weekly_target_seconds",
            "weeklyTargetSeconds",
        ),
    )
    accent_color: int = Field(
        default=0xFF3949AB,
        validation_alias=AliasChoices("accent_color", "accentColor"),
    )
    expires_at: Optional[str] = Field(
        default=None,
        validation_alias=AliasChoices("expires_at", "expiresAt"),
    )
    max_uses: Optional[int] = Field(
        default=None,
        validation_alias=AliasChoices("max_uses", "maxUses"),
    )


class FocusRoomInviteAccept(_FocusRoomAliasModel):
    display_name: Optional[str] = Field(
        default=None,
        validation_alias=AliasChoices("display_name", "displayName"),
    )


class FocusFriendCreate(BaseModel):
    username: Optional[str] = None
    user_id: Optional[str] = None


class WorkspaceCreate(BaseModel):
    name: str


class WorkspaceUpdate(BaseModel):
    name: Optional[str] = None


class WorkspaceInviteCreate(BaseModel):
    role: str = "viewer"
    expires_at: Optional[str] = None


class WorkspaceMemberUpdate(BaseModel):
    role: str


class WorkspaceCommentCreate(BaseModel):
    body: str
    target_id: Optional[str] = None


class FeedbackCreate(BaseModel):
    category: Optional[str] = None
    type: Optional[str] = None
    title: Optional[str] = None
    content: Optional[str] = None


class FeedbackReply(BaseModel):
    feedback_id: Optional[int] = None
    feedbackId: Optional[int] = None
    id: Optional[int] = None
    reply: Optional[str] = ""
    note: Optional[str] = None
    message: Optional[str] = None
    content: Optional[str] = None
    status: Optional[str] = "resolved"


class FeedbackBulkStatus(BaseModel):
    feedback_ids: Optional[list[int]] = None
    feedbackIds: Optional[list[int]] = None
    ids: Optional[list[int]] = None
    id: Optional[int] = None
    reply: Optional[str] = ""
    note: Optional[str] = None
    message: Optional[str] = None
    content: Optional[str] = None
    status: Optional[str] = "in_progress"


FEEDBACK_CATEGORIES = {
    "feature",
    "bug",
    "wish",
    "other",
    "gallery",
    "generate",
    "edit",
    "system",
    "account",
}
FEEDBACK_STATUSES = {"open", "in_progress", "resolved", "closed"}
FEEDBACK_STATUS_ALIASES = {
    "collected": "open",
    "accepted": "in_progress",
    "rejected": "closed",
}


def _clean_feedback_category(value: Optional[str], feedback_type: Optional[str] = None) -> str:
    raw_category = (value or "").strip()
    raw_type = (feedback_type or "").strip()
    category = raw_category or ("wish" if raw_type == "wish" else "feature")
    if category not in FEEDBACK_CATEGORIES:
        category = "other"
    return category


def _clean_feedback_content(value: Optional[str], title: Optional[str] = None) -> str:
    content = (value or "").strip()
    clean_title = (title or "").strip()
    if clean_title and not content:
        content = clean_title
    if not content:
        raise HTTPException(status_code=400, detail="反馈内容不能为空")
    if len(content) > 2000:
        raise HTTPException(status_code=400, detail="反馈内容不能超过 2000 字")
    return content


def _clean_feedback_status(value: str) -> str:
    status = (value or "resolved").strip()
    status = FEEDBACK_STATUS_ALIASES.get(status, status)
    if status not in FEEDBACK_STATUSES:
        raise HTTPException(status_code=400, detail="无效的反馈状态")
    return status


def _feedback_reply_id(req: FeedbackReply) -> int:
    raw = req.feedback_id or req.feedbackId or req.id
    try:
        feedback_id = int(raw)
    except Exception:
        feedback_id = 0
    if feedback_id <= 0:
        raise HTTPException(status_code=400, detail="反馈不存在")
    return feedback_id


def _feedback_reply_text(req: FeedbackReply) -> str:
    return (req.reply or req.note or req.message or req.content or "").strip()


def _feedback_bulk_ids(req: FeedbackBulkStatus) -> list[int]:
    values = req.feedback_ids or req.feedbackIds or req.ids or []
    if req.id is not None:
        values = [*values, req.id]
    ids: set[int] = set()
    for value in values:
        try:
            clean = int(value)
        except Exception:
            continue
        if clean > 0:
            ids.add(clean)
    return sorted(ids)


def _feedback_bulk_text(req: FeedbackBulkStatus) -> str:
    return (req.reply or req.note or req.message or req.content or "").strip()


class AnnouncementCreate(BaseModel):
    title: str
    body: str
    level: str = "info"
    published: bool = True


class AnnouncementUpdate(BaseModel):
    title: Optional[str] = None
    body: Optional[str] = None
    level: Optional[str] = None
    published: Optional[bool] = None


class WelfareGrantCreate(BaseModel):
    title: str = "全员福利"
    body: Optional[str] = ""
    generate_bonus: int = 0
    edit_bonus: int = 0
    notify: bool = True


class InviteCodeCreate(BaseModel):
    count: int = 1
    note: Optional[str] = ""


class UserUpdate(BaseModel):
    is_admin: Optional[bool] = None
    isAdmin: Optional[bool] = None
    is_disabled: Optional[bool] = None
    isDisabled: Optional[bool] = None
    new_password: Optional[str] = None
    newPassword: Optional[str] = None
    password: Optional[str] = None
    admin_permissions: Optional[list[str]] = None
    adminPermissions: Optional[list[str]] = None
    group_id: Optional[str] = None
    groupId: Optional[str] = None
    role_id: Optional[str] = None
    roleId: Optional[str] = None
    delta: Optional[int] = None
    reason: Optional[str] = None
    coins: Optional[int] = None
    amount: Optional[int] = None
    balance: Optional[int] = None
    coin_balance: Optional[int] = None
    target_balance: Optional[int] = None
    targetBalance: Optional[int] = None
    quota: Optional[int] = None
    time_coins: Optional[int] = None
    time_coin_balance: Optional[int] = None
    timeCoins: Optional[int] = None
    timeCoinBalance: Optional[int] = None
    credit_balance: Optional[int] = None
    creditBalance: Optional[int] = None
    credits: Optional[int] = None
    coin_delta: Optional[int] = None
    coinDelta: Optional[int] = None
    coinBalance: Optional[int] = None
    time_coin_delta: Optional[int] = None
    timeCoinDelta: Optional[int] = None


class UserCreate(BaseModel):
    username: str
    password: Optional[str] = None
    display_name: Optional[str] = None
    displayName: Optional[str] = None
    email: Optional[str] = None
    group_id: Optional[str] = None
    groupId: Optional[str] = None
    role_id: Optional[str] = None
    roleId: Optional[str] = None
    is_admin: Optional[bool] = None
    isAdmin: Optional[bool] = None
    is_disabled: Optional[bool] = None
    isDisabled: Optional[bool] = None
    admin_permissions: Optional[list[str]] = None
    adminPermissions: Optional[list[str]] = None


class UserCoinAdjustment(BaseModel):
    delta: Optional[int] = None
    reason: Optional[str] = None
    coins: Optional[int] = None
    amount: Optional[int] = None
    balance: Optional[int] = None
    coin_balance: Optional[int] = None
    target_balance: Optional[int] = None
    targetBalance: Optional[int] = None
    quota: Optional[int] = None
    time_coins: Optional[int] = None
    time_coin_balance: Optional[int] = None
    timeCoins: Optional[int] = None
    timeCoinBalance: Optional[int] = None
    credit_balance: Optional[int] = None
    creditBalance: Optional[int] = None
    credits: Optional[int] = None
    coin_delta: Optional[int] = None
    coinDelta: Optional[int] = None
    coinBalance: Optional[int] = None
    time_coin_delta: Optional[int] = None
    timeCoinDelta: Optional[int] = None


class AdminGroupUpsert(BaseModel):
    name: str
    description: Optional[str] = ""
    default_time_coins: Optional[int] = None
    defaultTimeCoins: Optional[int] = None
    is_active: Optional[bool] = None
    isActive: Optional[bool] = None


class AdminRoleUpsert(BaseModel):
    name: str
    description: Optional[str] = ""
    permissions: Optional[list[str]] = None
    permission_codes: Optional[list[str]] = None
    is_active: Optional[bool] = True


class UserBulkStatus(BaseModel):
    user_ids: Optional[list[str]] = None
    userIds: Optional[list[str]] = None
    ids: Optional[list[str]] = None
    id: Optional[str] = None
    is_disabled: Optional[bool] = None
    isDisabled: Optional[bool] = None
    disabled: Optional[bool] = None
    is_active: Optional[bool] = None
    isActive: Optional[bool] = None


class BackupBulkWipe(BaseModel):
    user_ids: list[str]


class SettingsUpdate(BaseModel):
    model_config = ConfigDict(extra="allow")

    invite_code_required: Optional[bool] = None
    allow_public_registration: Optional[bool] = None
    registration_invite_required: Optional[bool] = None
    registration_enabled: Optional[bool] = None
    registration_email_required: Optional[bool] = None
    email_code_login_enabled: Optional[bool] = None
    maintenance_mode: Optional[bool] = None
    maintenance_message: Optional[str] = None
    # App update policy
    force_update_required: Optional[bool] = None
    force_app_update_enabled: Optional[bool] = None
    force_relogin_enabled: Optional[bool] = None
    force_relogin_issued_at: Optional[str] = None
    latest_version: Optional[str] = None
    latest_version_name: Optional[str] = None
    minimum_supported_version: Optional[str] = None
    update_notes: Optional[str] = None
    release_notes: Optional[str] = None
    update_download_url: Optional[str] = None
    download_url: Optional[str] = None
    default_registration_coins: Optional[int] = None
    # AI
    ai_enabled: Optional[bool] = None
    ai_base_url: Optional[str] = None
    ai_api_key: Optional[str] = None
    ai_model: Optional[str] = None
    ai_daily_quota: Optional[int] = None
    # 云端备份
    backup_enabled: Optional[bool] = None
    backup_max_size_kb: Optional[int] = None
    backup_interval_minutes: Optional[int] = None
    backup_retain_days: Optional[int] = None
    # 服务器备份 / OpenList / 邮件通知
    server_backup_enabled: Optional[bool] = None
    server_backup_interval_minutes: Optional[int] = None
    server_backup_retain_days: Optional[int] = None
    openlist_backup_enabled: Optional[bool] = None
    openlist_webdav_url: Optional[str] = None
    openlist_public_url: Optional[str] = None
    openlist_username: Optional[str] = None
    openlist_password: Optional[str] = None
    openlist_backup_path: Optional[str] = None
    backup_email_enabled: Optional[bool] = None
    backup_email_to: Optional[str] = None
    backup_email_from: Optional[str] = None
    backup_email_smtp_host: Optional[str] = None
    backup_email_smtp_port: Optional[int] = None
    backup_email_smtp_username: Optional[str] = None
    backup_email_smtp_password: Optional[str] = None
    backup_email_smtp_use_ssl: Optional[bool] = None
    # 邮件提醒
    reminder_email_enabled: Optional[bool] = None
    reminder_email_to: Optional[str] = None
    reminder_email_from: Optional[str] = None
    reminder_email_smtp_host: Optional[str] = None
    reminder_email_smtp_port: Optional[int] = None
    reminder_email_smtp_username: Optional[str] = None
    reminder_email_smtp_password: Optional[str] = None
    reminder_email_smtp_use_ssl: Optional[bool] = None
    # 账号邮箱验证码邮件通道，兼容 RE0/boxying-image-gateway 字段
    email_service_enabled: Optional[bool] = None
    email_title: Optional[str] = None
    email_sender_name: Optional[str] = None
    email_code_primary_provider: Optional[str] = None
    email_code_backup_provider: Optional[str] = None
    email_code_active_slot: Optional[str] = None
    email_auto_switch_enabled: Optional[bool] = None
    openclaw_mail_enabled: Optional[bool] = None
    openclaw_mail_user: Optional[str] = None
    openclaw_mail_api_key: Optional[str] = None
    resend_base_url: Optional[str] = None
    resend_api_key: Optional[str] = None
    resend_from: Optional[str] = None
    hermes_base_url: Optional[str] = None
    hermes_api_key: Optional[str] = None
    system_notice_email_to: Optional[str] = None
    email_smtp_host: Optional[str] = None
    email_smtp_port: Optional[int] = None
    email_smtp_username: Optional[str] = None
    email_smtp_password: Optional[str] = None
    email_smtp_from: Optional[str] = None
    email_smtp_use_ssl: Optional[bool] = None


AI_SETTING_KEYS = {
    "ai_enabled",
    "ai_base_url",
    "ai_api_key",
    "ai_model",
    "ai_daily_quota",
}

BACKUP_SETTING_KEYS = {
    "backup_enabled",
    "backup_max_size_kb",
    "backup_interval_minutes",
    "backup_retain_days",
    "server_backup_enabled",
    "server_backup_interval_minutes",
    "server_backup_retain_days",
    "openlist_backup_enabled",
    "openlist_webdav_url",
    "openlist_public_url",
    "openlist_username",
    "openlist_password",
    "openlist_backup_path",
    "backup_email_enabled",
    "backup_email_to",
    "backup_email_from",
    "backup_email_smtp_host",
    "backup_email_smtp_port",
    "backup_email_smtp_username",
    "backup_email_smtp_password",
    "backup_email_smtp_use_ssl",
}

EMAIL_SETTING_KEYS = {
    "reminder_email_enabled",
    "reminder_email_to",
    "reminder_email_from",
    "reminder_email_smtp_host",
    "reminder_email_smtp_port",
    "reminder_email_smtp_username",
    "reminder_email_smtp_password",
    "email_service_enabled",
    "email_title",
    "email_sender_name",
    "email_code_primary_provider",
    "email_code_backup_provider",
    "email_code_active_slot",
    "email_auto_switch_enabled",
    "openclaw_mail_enabled",
    "openclaw_mail_user",
    "openclaw_mail_api_key",
    "resend_base_url",
    "resend_api_key",
    "resend_from",
    "system_notice_email_to",
    "email_smtp_host",
    "email_smtp_port",
    "email_smtp_username",
    "email_smtp_password",
    "email_smtp_from",
    "email_smtp_use_ssl",
}

BACKUP_ADMIN_SETTING_KEYS = BACKUP_SETTING_KEYS | EMAIL_SETTING_KEYS

ADMIN_SETTINGS_SCOPES = {
    "ai": AI_SETTING_KEYS,
    "backup": BACKUP_ADMIN_SETTING_KEYS,
}


class AiChatRequest(BaseModel):
    system: str = ""
    user: str
    temperature: float = 0.4
    max_tokens: int = 512


class AdminAiTestRequest(BaseModel):
    ai_enabled: Optional[bool] = None
    ai_base_url: Optional[str] = None
    ai_api_key: Optional[str] = None
    ai_model: Optional[str] = None
    apply_switch: Optional[bool] = None


class ReminderEmailOnceRequest(BaseModel):
    id: int
    title: str
    body: str
    when: str
    payload: Optional[str] = None


class ReminderEmailRepeatingRequest(BaseModel):
    id: int
    title: str
    body: str
    hour: int
    minute: int
    weekdays: Optional[list[int]] = None
    payload: Optional[str] = None


# ---- Public ----


@app.get("/api/health")
def health():
    db = get_db()
    try:
        payload = {
            "status": "ok",
            "version": "3.1.0",
            "invite_required": _registration_invite_required(db),
            "maintenance": _setting_get(db, "maintenance_mode", False),
            "time": datetime.now(timezone.utc).isoformat(),
        }
        payload.update(_api_contract_payload())
        return payload
    finally:
        db.close()


@app.get("/api/config")
def public_config():
    db = get_db()
    try:
        registration_enabled = _registration_enabled(db)
        invite_required = _registration_invite_required(db)
        update_policy = _update_release_defaults(db)
        payload = {
            "invite_code_required": invite_required,
            "registration_invite_required": invite_required,
            "registration_enabled": registration_enabled,
            "allow_public_registration": registration_enabled,
            "registration_email_required": _setting_get(db, "registration_email_required", False),
            "registration_email_available": _account_email_available(db),
            "email_code_login_enabled": _email_code_login_enabled(db),
            "maintenance_mode": _setting_get(db, "maintenance_mode", False),
            "maintenance_message": _setting_get(db, "maintenance_message", ""),
            "force_update_required": update_policy["force_update_required"],
            "force_app_update_enabled": update_policy["force_app_update_enabled"],
            "force_relogin_enabled": _setting_get(db, "force_relogin_enabled", False),
            "force_relogin_issued_at": _setting_get(db, "force_relogin_issued_at", ""),
            "current_version": update_policy["current_version"],
            "current_version_name": update_policy["current_version_name"],
            "current_version_code": update_policy["current_version_code"],
            "app_package_name": update_policy["app_package_name"],
            "version_options": update_policy["version_options"],
            "latest_version": update_policy["latest_version"],
            "latest_version_name": update_policy["latest_version_name"],
            "latest_version_code": update_policy["latest_version_code"],
            "minimum_supported_version": update_policy["minimum_supported_version"],
            "update_notes": update_policy["update_notes"],
            "release_notes": update_policy["release_notes"],
            "update_download_url": update_policy["update_download_url"],
            "download_url": update_policy["download_url"],
            "app_update": update_policy,
            "ai_enabled": bool(
                _setting_get(db, "ai_enabled", False)
                and str(_setting_get(db, "ai_api_key", "")).strip() != ""
            ),
            "ai_model": _setting_get(db, "ai_model", ""),
        }
        payload.update(_api_contract_payload())
        return payload
    finally:
        db.close()


@app.get("/api/bootstrap")
def bootstrap_config():
    cfg = public_config()
    return {
        "app_name": "多仪",
        "ui_title": "多仪",
        **cfg,
    }


@app.get("/api/mobile/apps/{app_id}/update")
def mobile_app_update(
    request: Request,
    app_id: str,
    current_version_code: int = Query(0, ge=0),
    current_version: str = "",
):
    return _mobile_update_response(request, app_id, current_version_code, current_version)


@app.get("/api/mobile/apps/{app_id}/download")
def mobile_app_download(app_id: str):
    normalized_app_id = (app_id or "").strip().lower()
    if normalized_app_id not in {"duoyi", APP_PACKAGE_NAME.lower()}:
        raise HTTPException(status_code=404, detail="Mobile app not found")
    resolved = _resolve_local_mobile_apk(normalized_app_id)
    if resolved is None:
        raise HTTPException(status_code=404, detail="Mobile app not found")
    apk_path, _manifest = resolved
    return FileResponse(
        apk_path,
        media_type="application/vnd.android.package-archive",
        filename=apk_path.name,
    )


# ---- AI proxy ----


def _today_str():
    return datetime.now().strftime("%Y-%m-%d")


@app.post("/api/ai/chat")
def ai_chat(req: AiChatRequest, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        if not _setting_get(db, "ai_enabled", False):
            raise HTTPException(status_code=503, detail="AI 功能未启用")
        api_key = str(_setting_get(db, "ai_api_key", "")).strip()
        if not api_key:
            raise HTTPException(status_code=503, detail="管理员尚未配置 AI API Key")

        # 配额限制
        quota = int(_setting_get(db, "ai_daily_quota", 0) or 0)
        if quota > 0:
            today = _today_str()
            row = db.execute(
                "SELECT calls FROM ai_usage WHERE user_id=? AND day=?",
                (user_id, today),
            ).fetchone()
            used = row["calls"] if row else 0
            if used >= quota:
                raise HTTPException(status_code=429, detail=f"今日 AI 额度已用尽 ({used}/{quota})")

        base_url = str(
            _setting_get(db, "ai_base_url", DEFAULT_AI_BASE_URL)
        ).rstrip("/")
        model = str(_setting_get(db, "ai_model", DEFAULT_AI_MODEL))

        messages = []
        if req.system:
            messages.append({"role": "system", "content": req.system})
        messages.append({"role": "user", "content": req.user})

        content, reply = _call_ai_chat_upstream(
            base_url=base_url,
            api_key=api_key,
            model=model,
            messages=messages,
            temperature=req.temperature,
            max_tokens=req.max_tokens,
            timeout=AI_CHAT_TIMEOUT_SECONDS,
        )
        if not content.strip():
            # Defensive: never hand an empty answer to clients that render it.
            raise HTTPException(
                status_code=502,
                detail=_ai_chat_empty_content_detail(_ai_chat_reply_meta(reply)),
            )

        # 记录额度
        today = _today_str()
        db.execute(
            "INSERT INTO ai_usage(user_id, day, calls) VALUES(?, ?, 1) "
            "ON CONFLICT(user_id, day) DO UPDATE SET calls=calls+1",
            (user_id, today),
        )
        db.commit()

        return {"content": content, "model": model}
    finally:
        db.close()


@app.get("/api/ai/usage")
def ai_usage(user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        today = _today_str()
        row = db.execute(
            "SELECT calls FROM ai_usage WHERE user_id=? AND day=?",
            (user_id, today),
        ).fetchone()
        quota = int(_setting_get(db, "ai_daily_quota", 0) or 0)
        return {
            "used": row["calls"] if row else 0,
            "quota": quota,
            "day": today,
        }
    finally:
        db.close()


@app.post("/api/admin/ai/test")
@app.post("/api/admin/provider-healthcheck")
def admin_ai_test(
    payload: Optional[AdminAiTestRequest] = None,
    actor: str = Depends(_require_admin),
):
    """调一个极短 prompt 验证 AI 配置连通。支持用未保存的表单配置临时测试。"""
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "ai")
        ai_enabled = (
            bool(payload.ai_enabled)
            if payload is not None and payload.ai_enabled is not None
            else bool(_setting_get(db, "ai_enabled", False))
        )
        base_url = (
            str(payload.ai_base_url).strip()
            if payload is not None
            and payload.ai_base_url is not None
            and str(payload.ai_base_url).strip()
            else str(_setting_get(db, "ai_base_url", DEFAULT_AI_BASE_URL))
        ).rstrip("/")
        model = (
            str(payload.ai_model).strip()
            if payload is not None
            and payload.ai_model is not None
            and str(payload.ai_model).strip()
            else str(_setting_get(db, "ai_model", DEFAULT_AI_MODEL))
        )
        if not ai_enabled:
            return {
                "ok": False,
                "enabled": False,
                "skipped": True,
                "model": model,
                "message": "AI 未启用，未测试上游连接。",
                "sample": "",
            }
        saved_api_key = str(_setting_get(db, "ai_api_key", "")).strip()
        submitted_key = (
            str(payload.ai_api_key).strip()
            if payload is not None and payload.ai_api_key is not None
            else ""
        )
        api_key = (
            submitted_key
            if submitted_key and "***" not in submitted_key
            else saved_api_key
        )
        if not api_key:
            raise HTTPException(status_code=503, detail="尚未配置 API Key")
        content, reply = _call_ai_chat_upstream(
            base_url=base_url,
            api_key=api_key,
            model=model,
            messages=[
                {"role": "user", "content": "回复一个 'ok' 即可"},
            ],
            temperature=0,
            # Reasoning models spend budget on hidden thinking first; 8 tokens
            # can never produce an answer and used to look like a healthy test.
            max_tokens=256,
            timeout=30,
            require_content=False,
        )
        sample = content.strip()
        meta = _ai_chat_reply_meta(reply)
        result = {
            "ok": bool(sample),
            "enabled": True,
            "model": model,
            "sample": content,
            "finish_reason": meta["finish_reason"],
            "reasoning_tokens": meta["reasoning_tokens"],
        }
        if not sample:
            result["message"] = _ai_chat_empty_content_detail(meta)
        return result
    finally:
        db.close()


@app.post("/api/admin/reminders/email/test")
def admin_reminder_email_test(actor: str = Depends(_require_admin)):
    """发送一封极短测试邮件，验证邮件提醒 SMTP 配置可用。"""
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "settings")
        title = _account_email_title(_account_mail_runtime(db))
        _send_reminder_email(
            db,
            actor,
            f"{title}邮件提醒测试",
            f"如果你收到这封邮件，说明{title}邮件提醒 SMTP 投递配置可用。",
        )
        return {"ok": True, "recipient": _reminder_email_recipient(db, actor)}
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"邮件提醒测试失败: {e}")
    finally:
        db.close()


@app.post("/api/admin/account-email/test")
def admin_account_email_test(actor: str = Depends(_require_admin)):
    """发送一封极短测试邮件，验证账号验证码邮件主备通道可用。"""
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "settings")
        recipient = _account_email_test_recipient(db, actor)
        if not recipient:
            raise HTTPException(
                status_code=503,
                detail="管理员账号未绑定邮箱，也未配置系统通知收件人",
            )
        runtime = _account_mail_runtime(db)
        title = _account_email_title(runtime)
        result = _send_account_email(
            db,
            to_addr=recipient,
            subject=f"{title}账号邮件测试",
            body=f"如果你收到这封邮件，说明{title}账号验证码邮件通道可用。",
            html=f"<p>如果你收到这封邮件，说明{html.escape(title)}账号验证码邮件通道可用。</p>",
            runtime=runtime,
        )
        if not result.get("sent"):
            raise HTTPException(
                status_code=503,
                detail=str(
                    result.get("detail")
                    or result.get("message")
                    or "账号邮件测试失败",
                ),
            )
        _audit(
            db,
            actor,
            _get_username(db, actor),
            "account_email.test",
            target=recipient,
            detail=f"{result.get('slot') or ''}/{result.get('provider') or ''}",
        )
        db.commit()
        return {
            "ok": True,
            "recipient": recipient,
            "provider": result.get("provider") or "",
            "slot": result.get("slot") or "",
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"账号邮件测试失败: {e}")
    finally:
        db.close()


@app.get("/api/admin/backups")
def admin_backups(
    _: str = Depends(_require_admin),
    q: Optional[str] = None,
    status: Optional[str] = None,
    sort: str = "updated_desc",
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    """列出每个用户最近一次备份的时间 + 估算大小。"""
    limit, offset = _admin_page_window(limit, offset)
    db = get_db()
    try:
        actor = _
        _ensure_admin_permission(db, actor, "backup")
        where, params = _backup_admin_filters(q=q, status=status)
        order_by = _backup_admin_order_by(sort)
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM users u LEFT JOIN sync_data sd ON sd.user_id = u.id {where}",
            params,
        ).fetchone()["c"]
        rows = db.execute(
            f"""
            SELECT u.id, u.username, u.email, u.display_name,
                   sd.updated_at, COALESCE(sd.sync_version, 0) AS sync_version,
                   {_BACKUP_BYTES_SQL} AS bytes
            FROM users u LEFT JOIN sync_data sd ON sd.user_id = u.id
            {where}
            ORDER BY {order_by}
            LIMIT ? OFFSET ?
            """
            ,
            (*params, limit, offset),
        ).fetchall()
        items = [
            {
                "user_id": r["id"],
                "username": r["username"],
                "email": r["email"],
                "display_name": r["display_name"],
                "updated_at": r["updated_at"],
                "sync_version": r["sync_version"],
                "has_snapshot": int(r["sync_version"] or 0) > 0,
                "size_kb": ((r["bytes"] or 0) + 1023) // 1024,
            }
            for r in rows
        ]
        return _admin_page_response(items, total, limit, offset)
    finally:
        db.close()


@app.get("/api/admin/backups/export.csv")
def export_backups_csv(
    actor: str = Depends(_require_admin),
    q: Optional[str] = None,
    status: Optional[str] = None,
    sort: str = "updated_desc",
    limit: int = Query(5000, ge=1, le=20000),
):
    """导出当前筛选下的用户云端备份索引，便于大量用户离线审计。"""
    limit, _offset = _admin_page_window(limit, 0, default_limit=5000, max_limit=20000)
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "backup")
        where, params = _backup_admin_filters(q=q, status=status)
        order_by = _backup_admin_order_by(sort)
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM users u LEFT JOIN sync_data sd ON sd.user_id = u.id {where}",
            params,
        ).fetchone()["c"]
        rows = db.execute(
            f"""
            SELECT u.id, u.username, u.email, u.display_name,
                   sd.updated_at, COALESCE(sd.sync_version, 0) AS sync_version,
                   {_BACKUP_BYTES_SQL} AS bytes
            FROM users u LEFT JOIN sync_data sd ON sd.user_id = u.id
            {where}
            ORDER BY {order_by}
            LIMIT ?
            """,
            (*params, limit),
        ).fetchall()
        buffer = io.StringIO()
        writer = csv.writer(buffer)
        writer.writerow(
            [
                "user_id",
                "username",
                "email",
                "display_name",
                "updated_at",
                "sync_version",
                "has_snapshot",
                "size_kb",
            ]
        )
        for row in rows:
            sync_version = int(row["sync_version"] or 0)
            size_kb = ((row["bytes"] or 0) + 1023) // 1024
            writer.writerow(
                [
                    _csv_safe(row["id"]),
                    _csv_safe(row["username"]),
                    _csv_safe(row["email"]),
                    _csv_safe(row["display_name"]),
                    _csv_safe(row["updated_at"]),
                    sync_version,
                    int(sync_version > 0),
                    size_kb,
                ]
            )
        _audit(
            db,
            actor,
            _get_username(db, actor),
            "backup.export",
            detail=json.dumps(
                {
                    "status": status or "",
                    "q": q or "",
                    "sort": sort,
                    "rows": len(rows),
                    "total": int(total or 0),
                },
                ensure_ascii=False,
            ),
        )
        db.commit()
        content = "\ufeff" + buffer.getvalue()
        filename = f"duoyi_backups_{_utc_now().strftime('%Y%m%d_%H%M%S')}.csv"
        headers = {
            "Content-Disposition": f'attachment; filename="{filename}"',
            "X-Total-Count": str(int(total or 0)),
            "X-Exported-Count": str(len(rows)),
        }
        return StreamingResponse(
            iter([content]),
            media_type="text/csv; charset=utf-8",
            headers=headers,
        )
    finally:
        db.close()


@app.delete("/api/admin/backups/{user_id}")
def admin_backup_wipe(user_id: str, actor: str = Depends(_require_admin)):
    """清空某用户的所有云端备份(账号保留)。"""
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "backup")
        db.execute(
            "UPDATE sync_data SET todos='[]', habits='[]', pomodoro_sessions='[]', "
            "focus_penalties='[]', pomodoro_config='{}', user_profile='{}', "
            "notes='[]', countdowns='[]', "
            "anniversaries='[]', diaries='[]', goals='[]', calendar_events='[]', "
            "courses='[]', time_entries='[]', course_settings='{}', achievement_states='{}', "
            "location_reminders='[]', "
            "virtual_rewards='{}', focus_rooms='{}', theme_shop_state='{}', "
            "preferences='{}', quick_capture_templates='{}', list_groups='[]', deleted_items='{}', "
            "updated_at=datetime('now') WHERE user_id=?",
            (user_id,),
        )
        _audit(
            db, actor, _get_username(db, actor),
            "backup.wipe", target=user_id,
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


# ---- Server backup / OpenList / email notice ----


def _setting_bool(db, key: str, default: bool = False) -> bool:
    return bool(_setting_get(db, key, default))


def _smtp_send(
    *,
    host: str,
    port: int,
    username: str,
    password: str,
    use_ssl: bool,
    from_addr: str,
    to_addr: str,
    subject: str,
    body: str,
) -> None:
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = from_addr
    msg["To"] = to_addr
    msg.set_content(body)
    if use_ssl:
        with smtplib.SMTP_SSL(host, port, timeout=30) as smtp:
            smtp.login(username, password)
            smtp.send_message(msg)
    else:
        with smtplib.SMTP(host, port, timeout=30) as smtp:
            smtp.starttls()
            smtp.login(username, password)
            smtp.send_message(msg)


def _email_smtp_send(
    *,
    runtime: dict,
    to_addr: str,
    subject: str,
    body: str,
    html: str = "",
) -> dict:
    host = str(runtime.get("email_smtp_host") or "").strip()
    username = str(runtime.get("email_smtp_username") or "").strip()
    password = str(runtime.get("email_smtp_password") or "")
    if not (host and username and password):
        return {"sent": False, "detail": "SMTP 未完整配置"}
    from_addr = str(runtime.get("email_smtp_from") or "").strip() or username
    sender_name = str(runtime.get("email_sender_name") or "").strip()
    _smtp_send(
        host=host,
        port=int(runtime.get("email_smtp_port") or 465),
        username=username,
        password=password,
        use_ssl=bool(runtime.get("email_smtp_use_ssl", True)),
        from_addr=formataddr((sender_name, from_addr)) if sender_name else from_addr,
        to_addr=to_addr,
        subject=subject,
        body=body,
    )
    return {"sent": True, "provider": "smtp"}


def _hermes_send_email(
    *,
    runtime: dict,
    to_addr: str,
    subject: str,
    body: str,
    html: str = "",
) -> dict:
    base_url = str(runtime.get("hermes_base_url") or "").strip().rstrip("/")
    api_key = str(runtime.get("hermes_api_key") or "").strip()
    if not (base_url and api_key):
        return {"sent": False, "detail": "Hermes 未完整配置"}
    parsed = urllib.parse.urlparse(base_url)
    if parsed.path.rstrip("/").endswith(
        ("/send", "/email/send", "/api/send", "/api/email/send", "/api/notifications/email")
    ):
        urls = [base_url]
    elif parsed.path and parsed.path != "/":
        urls = [
            base_url,
            f"{base_url}/send",
            f"{base_url}/email/send",
            f"{base_url}/api/send",
            f"{base_url}/api/email/send",
            f"{base_url}/api/notifications/email",
        ]
    else:
        urls = [
            f"{base_url}/send",
            f"{base_url}/email/send",
            f"{base_url}/api/send",
            f"{base_url}/api/email/send",
            f"{base_url}/api/notifications/email",
            base_url,
        ]
    headers = {"Content-Type": "application/json"}
    if ":" in api_key and not api_key.lower().startswith("bearer "):
        headers["Authorization"] = "Basic " + base64.b64encode(
            api_key.encode("utf-8")
        ).decode("ascii")
    else:
        token = api_key[7:].strip() if api_key.lower().startswith("bearer ") else api_key
        headers["Authorization"] = f"Bearer {token}"
    payload = json.dumps(
        {
            "to": to_addr,
            "email": to_addr,
            "subject": subject,
            "title": subject,
            "text": body,
            "body": body,
            "html": html or body,
        },
        ensure_ascii=False,
    ).encode("utf-8")
    errors: list[str] = []
    for url in dict.fromkeys(urls):
        req = urllib.request.Request(
            url,
            data=payload,
            headers=headers,
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                if 200 <= resp.status < 300:
                    return {"sent": True, "provider": "hermes"}
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", errors="replace")[:500]
            errors.append(f"{url}: HTTP {e.code}: {detail}")
            if e.code not in {404, 405}:
                break
        except Exception as e:
            errors.append(f"{url}: {e}")
    return {"sent": False, "detail": "; ".join(errors)}


def _resend_send_email(
    *,
    runtime: dict,
    to_addr: str,
    subject: str,
    body: str,
    html: str = "",
) -> dict:
    base_url = str(runtime.get("resend_base_url") or "https://api.resend.com").strip().rstrip("/")
    api_key = str(runtime.get("resend_api_key") or "").strip()
    from_addr = str(runtime.get("resend_from") or "").strip()
    if not (base_url and api_key and from_addr):
        return {"sent": False, "detail": "Resend 未完整配置"}
    if "<" not in from_addr and "@" in from_addr:
        sender_name = str(runtime.get("email_sender_name") or "").strip()
        if sender_name:
            from_addr = f"{sender_name} <{from_addr}>"
    payload = json.dumps(
        {
            "from": from_addr,
            "to": [to_addr],
            "subject": subject,
            "text": body,
            "html": html or body,
        },
        ensure_ascii=False,
    ).encode("utf-8")
    req = urllib.request.Request(
        f"{base_url}/emails",
        data=payload,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            data = json.loads(raw) if raw else {}
            return {"sent": True, "provider": "resend", "message_id": data.get("id")}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")[:500]
        return {"sent": False, "detail": f"Resend HTTP {e.code}: {detail}"}


def _openclaw_mail_send_email(
    *,
    runtime: dict,
    to_addr: str,
    subject: str,
    body: str,
    html: str = "",
) -> dict:
    if not bool(runtime.get("openclaw_mail_enabled", False)):
        return {"sent": False, "detail": "OpenClaw 邮件通道未启用"}
    user = str(runtime.get("openclaw_mail_user") or "").strip()
    api_key = str(runtime.get("openclaw_mail_api_key") or "").strip()
    if not (user and api_key):
        return {"sent": False, "detail": "OpenClaw 邮件未完整配置"}
    if not OPENCLAW_MAIL_SCRIPT.strip():
        return {"sent": False, "detail": "OpenClaw 邮件脚本未配置，请设置 OPENCLAW_MAIL_SCRIPT"}
    script = Path(OPENCLAW_MAIL_SCRIPT)
    if not script.is_file():
        return {"sent": False, "detail": "OpenClaw 邮件脚本不存在，请检查 OPENCLAW_MAIL_SCRIPT"}
    if not shutil.which(OPENCLAW_NODE_BIN):
        return {"sent": False, "detail": "OpenClaw Node 不可用，请检查 OPENCLAW_MAIL_NODE"}
    env = {
        **os.environ,
        "OPENCLAW_MAIL_USER": user,
        "OPENCLAW_MAIL_API_KEY": api_key,
        "OPENCLAW_MAIL_FROM_NAME": str(runtime.get("email_sender_name") or "").strip(),
        "OPENCLAW_MAIL_TO": to_addr,
        "OPENCLAW_MAIL_SUBJECT": subject,
        "OPENCLAW_MAIL_TEXT": body,
        "OPENCLAW_MAIL_HTML": html,
        "NODE_OPTIONS": "--dns-result-order=ipv4first",
    }
    try:
        completed = subprocess.run(
            [OPENCLAW_NODE_BIN, str(script)],
            check=False,
            capture_output=True,
            text=True,
            timeout=60,
            env=env,
        )
    except Exception as e:
        return {"sent": False, "detail": f"OpenClaw 邮件执行失败: {e}"}
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or "").strip()[:500]
        return {"sent": False, "detail": f"OpenClaw 邮件失败: {detail}"}
    try:
        data = json.loads(completed.stdout or "{}")
    except json.JSONDecodeError:
        data = {}
    if data.get("ok") is True or str(data.get("status") or "").lower() == "sent":
        return {
            "sent": True,
            "provider": "claw163",
            "message_id": data.get("messageId"),
        }
    return {"sent": False, "detail": str(data.get("error") or "OpenClaw 邮件未返回 sent")}


def _account_email_title(runtime: Optional[dict] = None) -> str:
    title = str((runtime or {}).get("email_title") or DEFAULT_EMAIL_TITLE).strip()
    return title or DEFAULT_EMAIL_TITLE


def _email_code_payload(
    code: str,
    purpose: str,
    title: str = DEFAULT_EMAIL_TITLE,
) -> tuple[str, str, str]:
    title = (title or DEFAULT_EMAIL_TITLE).strip() or DEFAULT_EMAIL_TITLE
    label = {
        "bind": "绑定邮箱",
        "login": "邮箱验证码登录",
        "reset": "找回密码",
    }.get(purpose, "邮箱验证")
    subject = f"{title}账号{label}验证码"
    body = f"你的 {title} 验证码是 {code}，5 分钟内有效。若不是本人操作，请忽略本邮件。"
    escaped_title = html.escape(title)
    html_body = (
        "<p>你好，</p>"
        f"<p>你的 {escaped_title} 验证码是 <strong>{code}</strong>，5 分钟内有效。</p>"
        "<p>若不是本人操作，请忽略本邮件。</p>"
    )
    return subject, body, html_body


def _reset_email_payload(
    code: str,
    title: str = DEFAULT_EMAIL_TITLE,
) -> tuple[str, str, str]:
    title = (title or DEFAULT_EMAIL_TITLE).strip() or DEFAULT_EMAIL_TITLE
    subject = f"{title}账号找回密码验证码"
    body = (
        f"{title} 重置验证码：{code}\n"
        "验证码 30 分钟内有效。如非本人操作，请忽略本邮件。"
    )
    escaped_title = html.escape(title)
    html_body = (
        "<p>你好，</p>"
        f"<p>{escaped_title} 重置验证码：<strong>{code}</strong></p>"
        "<p>验证码 30 分钟内有效。如非本人操作，请忽略本邮件。</p>"
    )
    return subject, body, html_body


def _email_code_provider_configured(runtime: dict, provider: str) -> bool:
    provider = _normalize_email_code_provider(provider)

    def configured(*keys: str) -> bool:
        return all(str(runtime.get(key) or "").strip() for key in keys)

    if provider == "claw163":
        return bool(
            runtime.get("openclaw_mail_enabled")
            and configured("openclaw_mail_user", "openclaw_mail_api_key")
        )
    if provider == "resend":
        return configured("resend_api_key", "resend_from")
    if provider == "smtp":
        return configured(
            "email_smtp_host", "email_smtp_username", "email_smtp_password"
        )
    if provider == "hermes":
        return configured("hermes_base_url", "hermes_api_key")
    return False


def _account_email_available(db) -> bool:
    runtime = _account_mail_runtime(db)
    if not runtime["email_service_enabled"]:
        return False
    active_slot = _normalize_email_code_slot(runtime.get("email_code_active_slot"))
    other_slot = "backup" if active_slot == "primary" else "primary"
    # Dispatch always tries both slots, then SMTP/Hermes fallbacks. Auto-switch
    # only persists the successful slot; it does not disable fallback delivery.
    return any(
        _email_code_provider_configured(runtime, provider)
        for provider in (
            runtime.get(f"email_code_{active_slot}_provider", "none"),
            runtime.get(f"email_code_{other_slot}_provider", "none"),
            "smtp",
            "hermes",
        )
    )


def _email_code_login_enabled(db) -> bool:
    return (
        _setting_get(db, "email_code_login_enabled", False) is True
        and _account_email_available(db)
    )


def _require_email_code_login_enabled(db) -> None:
    if not _email_code_login_enabled(db):
        raise HTTPException(status_code=403, detail="邮箱验证码登录未启用，请使用账号密码登录")


def _account_email_runtime_status(runtime: dict) -> dict:
    primary_provider = _normalize_email_code_provider(
        runtime.get("email_code_primary_provider", "none")
    )
    backup_provider = _normalize_email_code_provider(
        runtime.get("email_code_backup_provider", "none")
    )
    active_slot = _normalize_email_code_slot(runtime.get("email_code_active_slot"))
    effective_provider = primary_provider if active_slot == "primary" else backup_provider
    return {
        "email_service_enabled": bool(runtime.get("email_service_enabled", True)),
        "email_title": _account_email_title(runtime),
        "email_sender_name": runtime.get("email_sender_name", DEFAULT_EMAIL_SENDER_NAME),
        "email_code_primary_provider": primary_provider,
        "email_code_backup_provider": backup_provider,
        "email_code_active_slot": active_slot,
        "email_code_effective_provider": effective_provider,
        "email_auto_switch_enabled": bool(runtime.get("email_auto_switch_enabled", False)),
        "openclaw_mail_configured": _email_code_provider_configured(runtime, "claw163"),
        "resend_configured": _email_code_provider_configured(runtime, "resend"),
        "smtp_configured": _email_code_provider_configured(runtime, "smtp"),
        "hermes_configured": _email_code_provider_configured(runtime, "hermes"),
    }


def _any_account_email_provider_configured(runtime: dict) -> bool:
    configured_provider = any(
        _email_code_provider_configured(runtime, provider)
        for provider in ("claw163", "resend", "smtp", "hermes")
    )
    configured_slot = any(
        _email_code_provider_configured(
            runtime,
            runtime.get(f"email_code_{slot}_provider", "none"),
        )
        for slot in ("primary", "backup")
    )
    return configured_provider or configured_slot


def _send_account_email(
    db,
    *,
    to_addr: str,
    subject: str,
    body: str,
    html: str = "",
    runtime: Optional[dict] = None,
) -> dict:
    runtime = runtime or _account_mail_runtime(db)
    if not runtime.get("email_service_enabled", True):
        return {"sent": False, "provider": "none", "detail": "账号邮件服务未启用"}
    active_slot = _normalize_email_code_slot(runtime.get("email_code_active_slot"))
    slots = [active_slot, "backup" if active_slot == "primary" else "primary"]
    errors: list[str] = []
    attempted_providers: set[str] = set()
    for slot in dict.fromkeys(slots):
        provider = _normalize_email_code_provider(
            runtime.get(f"email_code_{slot}_provider", "none")
        )
        if provider != "none":
            attempted_providers.add(provider)
        if provider == "none":
            errors.append(f"{slot}: 邮件通道关闭")
            continue
        if not _email_code_provider_configured(runtime, provider):
            errors.append(f"{slot}/{provider}: 未配置")
            continue
        try:
            if provider == "claw163":
                result = _openclaw_mail_send_email(
                    runtime=runtime,
                    to_addr=to_addr,
                    subject=subject,
                    body=body,
                    html=html,
                )
            elif provider == "resend":
                result = _resend_send_email(
                    runtime=runtime,
                    to_addr=to_addr,
                    subject=subject,
                    body=body,
                    html=html,
                )
            elif provider == "smtp":
                result = _email_smtp_send(
                    runtime=runtime,
                    to_addr=to_addr,
                    subject=subject,
                    body=body,
                    html=html,
                )
            elif provider == "hermes":
                result = _hermes_send_email(
                    runtime=runtime,
                    to_addr=to_addr,
                    subject=subject,
                    body=body,
                    html=html,
                )
            else:
                result = {"sent": False, "detail": "邮件通道关闭"}
        except Exception as e:
            result = {"sent": False, "detail": str(e)}
        if result.get("sent"):
            if slot != active_slot and runtime.get("email_auto_switch_enabled"):
                _setting_set(db, "email_code_active_slot", slot)
            result["slot"] = slot
            result["provider"] = provider
            result.setdefault("message", "验证码已发送，请查看邮箱。")
            return result
        errors.append(str(result.get("detail") or result.get("message") or f"{provider} 发送失败"))
    if (
        "smtp" not in attempted_providers
        and _email_code_provider_configured(runtime, "smtp")
    ):
        try:
            result = _email_smtp_send(
                runtime=runtime,
                to_addr=to_addr,
                subject=subject,
                body=body,
                html=html,
            )
        except Exception as e:
            result = {"sent": False, "detail": str(e)}
        if result.get("sent"):
            result["slot"] = "smtp_fallback"
            result["provider"] = "smtp"
            result.setdefault("message", "验证码已发送，请查看邮箱。")
            return result
        errors.append(str(result.get("detail") or result.get("message") or "smtp 兜底发送失败"))
    if _email_code_provider_configured(runtime, "hermes"):
        try:
            result = _hermes_send_email(
                runtime=runtime,
                to_addr=to_addr,
                subject=subject,
                body=body,
                html=html,
            )
        except Exception as e:
            result = {"sent": False, "detail": str(e)}
        if result.get("sent"):
            result["slot"] = "hermes_fallback"
            result["provider"] = "hermes"
            result.setdefault("message", "验证码已发送，请查看邮箱。")
            return result
        errors.append(str(result.get("detail") or result.get("message") or "Hermes 兜底发送失败"))
    return {
        "sent": False,
        "provider": "none",
        "message": "验证码已生成，但邮件服务暂不可用。",
        "detail": "; ".join(errors),
    }


def _reminder_email_recipient(db, user_id: str) -> str:
    row = db.execute(
        "SELECT username, email FROM users WHERE id=?", (user_id,)
    ).fetchone()
    email = str(row["email"] if row else "").strip()
    if email:
        return email
    username = str(row["username"] if row else "").strip()
    if _looks_like_email(username):
        return username
    return str(_setting_get(db, "reminder_email_to", "") or "").strip()


def _send_reminder_email(db, user_id: str, subject: str, body: str) -> None:
    if not _setting_bool(db, "reminder_email_enabled", False):
        raise RuntimeError("邮件提醒未启用")
    to_addr = _reminder_email_recipient(db, user_id)
    host = str(_setting_get(db, "reminder_email_smtp_host", "") or "").strip()
    username = str(_setting_get(db, "reminder_email_smtp_username", "") or "").strip()
    password = str(_setting_get(db, "reminder_email_smtp_password", "") or "")
    if not (to_addr and host and username and password):
        raise RuntimeError("邮件提醒 SMTP 未完整配置")
    from_addr = str(_setting_get(db, "reminder_email_from", "") or "").strip() or username
    _smtp_send(
        host=host,
        port=int(_setting_get(db, "reminder_email_smtp_port", 465) or 465),
        username=username,
        password=password,
        use_ssl=_setting_bool(db, "reminder_email_smtp_use_ssl", True),
        from_addr=from_addr,
        to_addr=to_addr,
        subject=subject,
        body=body,
    )


def _account_email_recipient(row) -> str:
    email = str(row["email"] or "").strip()
    if email:
        return email
    username = str(row["username"] or "").strip()
    return username if _looks_like_email(username) else ""


def _user_account_email_recipient(db, user_id: str) -> str:
    row = db.execute(
        "SELECT username, email FROM users WHERE id=?",
        (user_id,),
    ).fetchone()
    return _account_email_recipient(row) if row else ""


def _account_email_test_recipient(db, actor: str) -> str:
    row = db.execute(
        "SELECT username, email FROM users WHERE id=?",
        (actor,),
    ).fetchone()
    recipient = _account_email_recipient(row) if row else ""
    if recipient:
        return recipient
    configured = str(_setting_get(db, "system_notice_email_to", "") or "")
    for part in re.split(r"[,;\s]+", configured):
        candidate = part.strip()
        if _looks_like_email(candidate):
            return candidate
    return ""


def _send_password_reset_email(db, row, token: str) -> None:
    to_addr = _account_email_recipient(row)
    if not to_addr:
        raise RuntimeError("账号未绑定邮箱")
    runtime = _account_mail_runtime(db)
    subject, body, html = _reset_email_payload(
        token,
        _account_email_title(runtime),
    )
    result = _send_account_email(
        db,
        to_addr=to_addr,
        subject=subject,
        body=body,
        html=html,
        runtime=runtime,
    )
    if not result.get("sent"):
        raise RuntimeError(str(result.get("detail") or "账号邮件 SMTP 未完整配置"))


def _send_workspace_mention_email(
    db,
    *,
    target_user_id: str,
    author_name: str,
    workspace_name: str,
    target_id: str,
    body: str,
) -> None:
    to_addr = _user_account_email_recipient(db, target_user_id)
    if not to_addr:
        raise RuntimeError("被提及成员未绑定邮箱")
    comment = body.strip()
    if len(comment) > 600:
        comment = comment[:600] + "..."
    runtime = _account_mail_runtime(db)
    title = _account_email_title(runtime)
    location = f"任务/对象：{target_id}\n" if target_id else ""
    text_body = (
        f"{author_name} 在「{workspace_name}」中 @ 了你。\n\n"
        f"{location}"
        f"评论：{comment}\n\n"
        f"打开{title}的共享空间可查看并标记已读。"
    )
    html_body = (
        f"<p>{html.escape(author_name)} 在「{html.escape(workspace_name)}」中 @ 了你。</p>"
        + (f"<p>任务/对象：{html.escape(target_id)}</p>" if target_id else "")
        + f"<p>评论：{html.escape(comment)}</p>"
        + f"<p>打开{html.escape(title)}的共享空间可查看并标记已读。</p>"
    )
    result = _send_account_email(
        db,
        to_addr=to_addr,
        subject=f"{title}共享空间提及：{workspace_name}",
        body=text_body,
        html=html_body,
        runtime=runtime,
    )
    if not result.get("sent"):
        raise RuntimeError(str(result.get("detail") or "账号邮件 SMTP 未完整配置"))


def _next_repeating_email_time(
    *,
    hour: int,
    minute: int,
    weekdays: list[int],
    after: Optional[datetime] = None,
) -> datetime:
    now = after or _utc_now()
    for day_offset in range(0, 8):
        candidate_date = now + timedelta(days=day_offset)
        candidate = candidate_date.replace(
            hour=hour,
            minute=minute,
            second=0,
            microsecond=0,
        )
        if candidate <= now:
            continue
        if weekdays and candidate.isoweekday() not in weekdays:
            continue
        return candidate
    return now + timedelta(days=1)


def _reminder_email_job_id(user_id: str, reminder_id: int) -> str:
    digest = hashlib.sha1(f"{user_id}:{reminder_id}".encode()).hexdigest()[:16]
    return f"reminder-email:{digest}"


def _upsert_reminder_email_job(
    db,
    *,
    user_id: str,
    reminder_id: int,
    schedule_kind: str,
    title: str,
    body: str,
    payload: str,
    when_at: Optional[datetime] = None,
    hour: Optional[int] = None,
    minute: Optional[int] = None,
    weekdays: Optional[list[int]] = None,
) -> dict:
    if schedule_kind not in {"once", "repeating"}:
        raise HTTPException(status_code=400, detail="Invalid schedule kind")
    if schedule_kind == "once":
        if when_at is None:
            raise HTTPException(status_code=400, detail="when is required")
        next_send_at = when_at
    else:
        if hour is None or minute is None or hour < 0 or hour > 23 or minute < 0 or minute > 59:
            raise HTTPException(status_code=400, detail="Invalid time")
        next_send_at = _next_repeating_email_time(
            hour=hour,
            minute=minute,
            weekdays=weekdays or [],
        )
    job_id = _reminder_email_job_id(user_id, reminder_id)
    db.execute(
        """
        INSERT INTO reminder_email_jobs(
            id, user_id, reminder_id, schedule_kind, title, body, payload,
            when_at, hour, minute, weekdays_json, next_send_at, sent_at,
            cancelled, updated_at
        )
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,0,?)
        ON CONFLICT(id) DO UPDATE SET
            schedule_kind=excluded.schedule_kind,
            title=excluded.title,
            body=excluded.body,
            payload=excluded.payload,
            when_at=excluded.when_at,
            hour=excluded.hour,
            minute=excluded.minute,
            weekdays_json=excluded.weekdays_json,
            next_send_at=excluded.next_send_at,
            sent_at=NULL,
            cancelled=0,
            updated_at=excluded.updated_at
        """,
        (
            job_id,
            user_id,
            reminder_id,
            schedule_kind,
            title,
            body,
            payload,
            _format_utc(when_at) if when_at else None,
            hour,
            minute,
            json.dumps(weekdays or []),
            _format_utc(next_send_at),
            None,
            _utc_now_text(),
        ),
    )
    return {
        "id": job_id,
        "reminder_id": reminder_id,
        "schedule_kind": schedule_kind,
        "next_send_at": _format_utc(next_send_at),
    }


def dispatch_due_reminder_emails(limit: int = 50) -> int:
    db = get_db()
    sent = 0
    try:
        if not _setting_bool(db, "reminder_email_enabled", False):
            return 0
        rows = db.execute(
            """
            SELECT * FROM reminder_email_jobs
            WHERE cancelled=0
              AND next_send_at IS NOT NULL
              AND next_send_at <= ?
            ORDER BY next_send_at ASC
            LIMIT ?
            """,
            (_utc_now_text(), limit),
        ).fetchall()
        for row in rows:
            try:
                _send_reminder_email(db, row["user_id"], row["title"], row["body"])
            except Exception as e:
                db.execute(
                    "UPDATE reminder_email_jobs SET updated_at=? WHERE id=?",
                    (_utc_now_text(), row["id"]),
                )
                _audit(
                    db,
                    row["user_id"],
                    _get_username(db, row["user_id"]),
                    "reminder_email.failed",
                    target=row["id"],
                    detail=str(e),
                )
                continue
            sent += 1
            if row["schedule_kind"] == "repeating":
                weekdays = json.loads(row["weekdays_json"] or "[]")
                next_send_at = _next_repeating_email_time(
                    hour=int(row["hour"]),
                    minute=int(row["minute"]),
                    weekdays=[int(v) for v in weekdays],
                    after=_utc_now(),
                )
                db.execute(
                    "UPDATE reminder_email_jobs SET sent_at=?, next_send_at=?, updated_at=? WHERE id=?",
                    (_utc_now_text(), _format_utc(next_send_at), _utc_now_text(), row["id"]),
                )
            else:
                db.execute(
                    "UPDATE reminder_email_jobs SET sent_at=?, next_send_at=NULL, updated_at=? WHERE id=?",
                    (_utc_now_text(), _utc_now_text(), row["id"]),
                )
            _audit(
                db,
                row["user_id"],
                _get_username(db, row["user_id"]),
                "reminder_email.sent",
                target=row["id"],
            )
        db.commit()
        return sent
    finally:
        db.close()


def _backup_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")


def _backup_filename(stamp: str) -> str:
    return f"duoyi_backup_{stamp}.zip"


def _backup_zip(stamp: str) -> tuple[Path, int]:
    backup_dir = Path(BACKUP_DIR)
    backup_dir.mkdir(parents=True, exist_ok=True)
    filename = _backup_filename(stamp)
    zip_path = backup_dir / filename
    db_path = Path(DB_PATH)
    snapshot_path = backup_dir / f"duoyi_snapshot_{stamp}.db"
    shutil.copy2(db_path, snapshot_path)
    try:
        metadata = {
            "app": "duoyi",
            "created_at": datetime.now(timezone.utc).isoformat(),
            "source_db": str(db_path),
            "filename": filename,
        }
        with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.write(snapshot_path, "duoyi.db")
            zf.writestr(
                "metadata.json",
                json.dumps(metadata, ensure_ascii=False, indent=2),
            )
    finally:
        try:
            snapshot_path.unlink()
        except FileNotFoundError:
            pass
    return zip_path, zip_path.stat().st_size


def _openlist_headers(username: str, password: str) -> dict[str, str]:
    headers = {"Content-Type": "application/zip"}
    if username or password:
        token = base64.b64encode(f"{username}:{password}".encode()).decode()
        headers["Authorization"] = f"Basic {token}"
    return headers


def _openlist_url(base_url: str, remote_path: str, filename: str) -> str:
    clean_base = base_url.rstrip("/")
    parts = [p.strip("/") for p in [remote_path, filename] if p.strip("/")]
    return clean_base + "/" + "/".join(parts)


def _openlist_mkcol(base_url: str, remote_path: str, headers: dict[str, str]) -> None:
    clean_base = base_url.rstrip("/")
    current = clean_base
    for part in [p for p in remote_path.strip("/").split("/") if p]:
        current = f"{current}/{part}"
        req = urllib.request.Request(current, headers=headers, method="MKCOL")
        try:
            urllib.request.urlopen(req, timeout=15).close()
        except urllib.error.HTTPError as e:
            if e.code not in {405, 409}:
                raise


def _upload_openlist(db, zip_path: Path) -> str:
    if not _setting_bool(db, "openlist_backup_enabled", False):
        return ""
    base_url = str(_setting_get(db, "openlist_webdav_url", "") or "").rstrip("/")
    if not base_url:
        raise RuntimeError("OpenList WebDAV URL 未配置")
    remote_path = str(_setting_get(db, "openlist_backup_path", "/duoyi-backups") or "")
    username = str(_setting_get(db, "openlist_username", "") or "")
    password = str(_setting_get(db, "openlist_password", "") or "")
    headers = _openlist_headers(username, password)
    _openlist_mkcol(base_url, remote_path, headers)
    upload_url = _openlist_url(base_url, remote_path, zip_path.name)
    with zip_path.open("rb") as fh:
        req = urllib.request.Request(
            upload_url,
            data=fh.read(),
            headers=headers,
            method="PUT",
        )
        urllib.request.urlopen(req, timeout=60).close()
    public = str(_setting_get(db, "openlist_public_url", "") or "").rstrip("/")
    return _openlist_url(public or base_url, remote_path, zip_path.name)


def _send_backup_email(db, subject: str, body: str) -> None:
    if not _setting_bool(db, "backup_email_enabled", False):
        return
    to_addr = str(_setting_get(db, "backup_email_to", "") or "").strip()
    host = str(_setting_get(db, "backup_email_smtp_host", "") or "").strip()
    username = str(_setting_get(db, "backup_email_smtp_username", "") or "").strip()
    password = str(_setting_get(db, "backup_email_smtp_password", "") or "")
    if not (to_addr and host and username and password):
        raise RuntimeError("邮件通知 SMTP 未完整配置")
    from_addr = str(_setting_get(db, "backup_email_from", "") or "").strip() or username
    _smtp_send(
        host=host,
        port=int(_setting_get(db, "backup_email_smtp_port", 465) or 465),
        username=username,
        password=password,
        use_ssl=_setting_bool(db, "backup_email_smtp_use_ssl", True),
        from_addr=from_addr,
        to_addr=to_addr,
        subject=subject,
        body=body,
    )


def _cleanup_old_backups(db) -> None:
    retain_days = int(_setting_get(db, "server_backup_retain_days", 14) or 0)
    if retain_days <= 0:
        return
    cutoff = datetime.now(timezone.utc).timestamp() - retain_days * 86400
    for path in Path(BACKUP_DIR).glob("duoyi_backup_*.zip"):
        if path.stat().st_mtime < cutoff:
            try:
                path.unlink()
            except FileNotFoundError:
                pass


def run_server_backup(actor: Optional[str] = None) -> dict:
    stamp = _backup_stamp()
    backup_id = f"server:{stamp}"
    db = get_db()
    remote_url = ""
    detail = ""
    status = "created"
    try:
        zip_path, size_bytes = _backup_zip(stamp)
        try:
            remote_url = _upload_openlist(db, zip_path)
            status = "uploaded" if remote_url else "local_only"
        except Exception as e:
            status = "local_created_remote_failed"
            detail = f"OpenList 上传失败: {e}"
        db.execute(
            "INSERT INTO server_backups(id, filename, size_bytes, status, detail, local_path, remote_url) "
            "VALUES(?,?,?,?,?,?,?)",
            (
                backup_id,
                zip_path.name,
                size_bytes,
                status,
                detail,
                str(zip_path),
                remote_url,
            ),
        )
        _audit(
            db,
            actor,
            _get_username(db, actor) if actor else "system",
            "server_backup.run",
            target=backup_id,
            detail=detail or remote_url,
        )
        db.commit()
        _cleanup_old_backups(db)
        try:
            _send_backup_email(
                db,
                f"多仪服务器备份: {status}",
                f"文件: {zip_path.name}\n大小: {size_bytes} bytes\n状态: {status}\n远端: {remote_url or '-'}\n详情: {detail or '-'}",
            )
        except Exception as e:
            detail = f"{detail}; 邮件通知失败: {e}" if detail else f"邮件通知失败: {e}"
            db.execute(
                "UPDATE server_backups SET detail=? WHERE id=?",
                (detail, backup_id),
            )
            db.commit()
        return {
            "id": backup_id,
            "filename": zip_path.name,
            "size_bytes": size_bytes,
            "status": status,
            "detail": detail,
            "local_path": str(zip_path),
            "remote_url": remote_url,
        }
    finally:
        db.close()


async def _server_backup_loop() -> None:
    while True:
        db = get_db()
        try:
            enabled = _setting_bool(db, "server_backup_enabled", True)
            interval = int(_setting_get(db, "server_backup_interval_minutes", 720) or 720)
        finally:
            db.close()
        await asyncio.sleep(max(interval, 10) * 60)
        if not enabled:
            continue
        try:
            await asyncio.to_thread(run_server_backup, None)
        except Exception:
            pass


async def _reminder_email_loop() -> None:
    while True:
        await asyncio.sleep(REMINDER_EMAIL_POLL_SECONDS)
        try:
            await asyncio.to_thread(dispatch_due_reminder_emails)
        except Exception:
            pass


@app.on_event("startup")
async def _start_server_backup_loop():
    global SERVER_BACKUP_TASK, REMINDER_EMAIL_TASK
    if SERVER_BACKUP_TASK is None or SERVER_BACKUP_TASK.done():
        SERVER_BACKUP_TASK = asyncio.create_task(_server_backup_loop())
    if REMINDER_EMAIL_TASK is None or REMINDER_EMAIL_TASK.done():
        REMINDER_EMAIL_TASK = asyncio.create_task(_reminder_email_loop())


@app.on_event("shutdown")
async def _stop_server_backup_loop():
    global SERVER_BACKUP_TASK, REMINDER_EMAIL_TASK
    if SERVER_BACKUP_TASK is not None:
        SERVER_BACKUP_TASK.cancel()
        SERVER_BACKUP_TASK = None
    if REMINDER_EMAIL_TASK is not None:
        REMINDER_EMAIL_TASK.cancel()
        REMINDER_EMAIL_TASK = None


@app.get("/api/admin/local-backups")
@app.get("/api/admin/server-backups")
def admin_server_backups(
    _: str = Depends(_require_admin),
    q: Optional[str] = None,
    status: Optional[str] = None,
    sort: str = "created_desc",
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    limit, offset = _admin_page_window(limit, offset)
    db = get_db()
    try:
        actor = _
        _ensure_admin_permission(db, actor, "backup")
        where, params = _server_backup_admin_filters(q=q, status=status)
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM server_backups {where}", params
        ).fetchone()["c"]
        order_by = _server_backup_admin_order_by(sort)
        rows = db.execute(
            f"SELECT * FROM server_backups {where} ORDER BY {order_by} LIMIT ? OFFSET ?",
            (*params, limit, offset),
        ).fetchall()
        return _admin_page_response([dict(r) for r in rows], total, limit, offset)
    finally:
        db.close()


@app.get("/api/admin/server-backups/export.csv")
def export_server_backups_csv(
    actor: str = Depends(_require_admin),
    q: Optional[str] = None,
    status: Optional[str] = None,
    sort: str = "created_desc",
    limit: int = Query(5000, ge=1, le=20000),
):
    """导出当前筛选下的服务器备份记录。"""
    limit, _offset = _admin_page_window(limit, 0, default_limit=5000, max_limit=20000)
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "backup")
        where, params = _server_backup_admin_filters(q=q, status=status)
        order_by = _server_backup_admin_order_by(sort)
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM server_backups {where}", params
        ).fetchone()["c"]
        rows = db.execute(
            f"SELECT * FROM server_backups {where} ORDER BY {order_by} LIMIT ?",
            (*params, limit),
        ).fetchall()
        buffer = io.StringIO()
        writer = csv.writer(buffer)
        writer.writerow(
            [
                "id",
                "filename",
                "size_bytes",
                "status",
                "created_at",
                "local_path",
                "remote_url",
                "detail",
            ]
        )
        for row in rows:
            writer.writerow(
                [
                    _csv_safe(row["id"]),
                    _csv_safe(row["filename"]),
                    int(row["size_bytes"] or 0),
                    _csv_safe(row["status"]),
                    _csv_safe(row["created_at"]),
                    _csv_safe(row["local_path"]),
                    _csv_safe(row["remote_url"]),
                    _csv_safe(row["detail"]),
                ]
            )
        _audit(
            db,
            actor,
            _get_username(db, actor),
            "server_backup.export",
            detail=json.dumps(
                {
                    "status": status or "",
                    "q": q or "",
                    "sort": sort,
                    "rows": len(rows),
                    "total": int(total or 0),
                },
                ensure_ascii=False,
            ),
        )
        db.commit()
        content = "\ufeff" + buffer.getvalue()
        filename = (
            f"duoyi_server_backups_{_utc_now().strftime('%Y%m%d_%H%M%S')}.csv"
        )
        headers = {
            "Content-Disposition": f'attachment; filename="{filename}"',
            "X-Total-Count": str(int(total or 0)),
            "X-Exported-Count": str(len(rows)),
        }
        return StreamingResponse(
            iter([content]),
            media_type="text/csv; charset=utf-8",
            headers=headers,
        )
    finally:
        db.close()


@app.post("/api/admin/local-backups/run")
@app.post("/api/admin/server-backups/run")
def admin_run_server_backup(actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "backup")
    finally:
        db.close()
    return run_server_backup(actor)


@app.post("/api/reminders/email/once")
def schedule_email_reminder_once(
    req: ReminderEmailOnceRequest,
    user_id: str = Depends(_verify_token),
):
    when_at = _parse_server_time(req.when)
    if when_at is None:
        raise HTTPException(status_code=400, detail="Invalid when")
    db = get_db()
    try:
        result = _upsert_reminder_email_job(
            db,
            user_id=user_id,
            reminder_id=req.id,
            schedule_kind="once",
            title=req.title,
            body=req.body,
            payload=req.payload or "",
            when_at=when_at,
        )
        db.commit()
        return result
    finally:
        db.close()


@app.post("/api/reminders/email/repeating")
def schedule_email_reminder_repeating(
    req: ReminderEmailRepeatingRequest,
    user_id: str = Depends(_verify_token),
):
    weekdays = [int(v) for v in (req.weekdays or []) if 1 <= int(v) <= 7]
    db = get_db()
    try:
        result = _upsert_reminder_email_job(
            db,
            user_id=user_id,
            reminder_id=req.id,
            schedule_kind="repeating",
            title=req.title,
            body=req.body,
            payload=req.payload or "",
            hour=req.hour,
            minute=req.minute,
            weekdays=weekdays,
        )
        db.commit()
        return result
    finally:
        db.close()


@app.delete("/api/reminders/email/{reminder_id}")
def cancel_email_reminder(reminder_id: int, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        job_id = _reminder_email_job_id(user_id, reminder_id)
        db.execute(
            "UPDATE reminder_email_jobs SET cancelled=1, next_send_at=NULL, updated_at=? WHERE id=? AND user_id=?",
            (_utc_now_text(), job_id, user_id),
        )
        db.commit()
        return {"ok": True, "id": job_id}
    finally:
        db.close()


# ---- Auth ----


def _client_ip(request: Optional[Request]) -> str:
    if request is None:
        return ""
    forwarded = request.headers.get("x-forwarded-for", "")
    if forwarded:
        return forwarded.split(",", 1)[0].strip()
    return request.client.host if request.client else ""


def _create_email_code(
    db,
    *,
    email: str,
    purpose: str,
    user_id: Optional[str] = None,
    ip_address: str = "",
) -> dict:
    purpose = (purpose or "login").strip().lower()
    if purpose in {"register", "registration", "signup", "sign_up"}:
        purpose = "bind"
    if purpose not in {"bind", "login", "reset"}:
        raise HTTPException(status_code=400, detail="验证码用途不受支持")
    if purpose == "login":
        _require_email_code_login_enabled(db)
    normalized_email = _clean_email(email)
    if not normalized_email:
        raise HTTPException(status_code=400, detail="邮箱不能为空")
    now = _utc_now()
    latest = db.execute(
        """
        SELECT locked_until, created_at
        FROM email_verification_codes
        WHERE email=? AND purpose=? AND consumed_at IS NULL
        ORDER BY created_at DESC
        LIMIT 1
        """,
        (normalized_email, purpose),
    ).fetchone()
    if latest is not None:
        locked_until = _parse_server_time(latest["locked_until"])
        if locked_until is not None and locked_until > now:
            raise HTTPException(status_code=429, detail="验证码错误次数过多，请稍后再试")
        created_at = _parse_server_time(latest["created_at"])
        if created_at is not None and (now - created_at).total_seconds() < 60:
            raise HTTPException(status_code=429, detail="验证码发送过于频繁，请稍后再试")

    if purpose == "login":
        row = db.execute(
            """
            SELECT id FROM users
            WHERE lower(email)=? AND email_verified=1 AND is_disabled=0
            """,
            (normalized_email,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="该邮箱还没有绑定可用账号")
        user_id = row["id"]
    elif purpose == "reset":
        row = db.execute(
            """
            SELECT id FROM users
            WHERE lower(email)=? AND is_disabled=0
            """,
            (normalized_email,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="该邮箱还没有绑定可用账号")
        user_id = row["id"]
    elif user_id is not None:
        _ensure_account_unique(db, email=normalized_email, exclude_user_id=user_id)
    else:
        _ensure_account_unique(db, email=normalized_email)

    code = f"{secrets.randbelow(1_000_000):06d}"
    expires_at = _format_utc(now + timedelta(minutes=5))
    code_id = secrets.token_hex(16)
    db.execute(
        """
        INSERT INTO email_verification_codes(
            id, user_id, email, purpose, code_hash, expires_at, ip_address, created_at
        ) VALUES(?,?,?,?,?,?,?,?)
        """,
        (
            code_id,
            user_id,
            normalized_email,
            purpose,
            _hash_email_code(code),
            expires_at,
            ip_address[:128],
            _format_utc(now),
        ),
    )
    return {
        "id": code_id,
        "user_id": user_id,
        "email": normalized_email,
        "purpose": purpose,
        "code": code,
        "expires_at": expires_at,
    }


def _consume_email_code(
    db,
    *,
    email: str,
    purpose: str,
    code: str,
    user_id: Optional[str] = None,
) -> None:
    normalized_email = _clean_email(email)
    normalized_code = (code or "").strip()
    if not normalized_email or not normalized_code:
        raise HTTPException(status_code=400, detail="验证码无效或已过期")
    row = db.execute(
        """
        SELECT *
        FROM email_verification_codes
        WHERE email=? AND purpose=? AND consumed_at IS NULL
          AND (? IS NULL OR user_id IS NULL OR user_id=?)
        ORDER BY created_at DESC
        LIMIT 1
        """,
        (normalized_email, purpose, user_id, user_id),
    ).fetchone()
    now = _utc_now()
    if row is None:
        raise HTTPException(status_code=400, detail="验证码无效或已过期")
    locked_until = _parse_server_time(row["locked_until"])
    if locked_until is not None and locked_until > now:
        raise HTTPException(status_code=429, detail="验证码错误次数过多，请稍后再试")
    expires_at = _parse_server_time(row["expires_at"])
    if expires_at is None or expires_at < now:
        raise HTTPException(status_code=400, detail="验证码已过期")
    if _hash_email_code(normalized_code) != row["code_hash"]:
        failures = int(row["failure_count"] or 0) + 1
        locked = _format_utc(now + timedelta(hours=1)) if failures >= 5 else None
        db.execute(
            "UPDATE email_verification_codes SET failure_count=?, locked_until=? WHERE id=?",
            (failures, locked, row["id"]),
        )
        if locked:
            raise HTTPException(status_code=429, detail="验证码错误次数过多，请稍后再试")
        raise HTTPException(status_code=400, detail="验证码不正确")
    db.execute(
        "UPDATE email_verification_codes SET consumed_at=? WHERE id=?",
        (_format_utc(now), row["id"]),
    )


def _send_email_code_result(db, code_result: dict) -> dict:
    runtime = _account_mail_runtime(db)
    subject, body, html = _email_code_payload(
        code_result["code"],
        code_result["purpose"],
        _account_email_title(runtime),
    )
    sent = _send_account_email(
        db,
        to_addr=code_result["email"],
        subject=subject,
        body=body,
        html=html,
        runtime=runtime,
    )
    payload = {
        "ok": True,
        "email": code_result["email"],
        "purpose": code_result["purpose"],
        "expires_at": code_result["expires_at"],
        "sent": bool(sent.get("sent")),
        "provider": sent.get("provider", "none"),
        "message": sent.get("message", "验证码已发送，请查看邮箱。"),
    }
    if sent.get("detail"):
        payload["detail"] = sent.get("detail")
    if not sent.get("sent") and not _any_account_email_provider_configured(runtime):
        payload["dev_code"] = code_result["code"]
    return payload


def _auth_payload(data: dict) -> dict:
    return {"user": data, **data}


def _issue_login_session(db, row, *, action: str, audit: bool = True) -> dict:
    """Persist the account's single login session, then refresh the cache alias."""
    token = secrets.token_hex(32)
    now = _utc_now()
    now_text = _format_utc(now)
    db.execute(
        "INSERT OR REPLACE INTO login_sessions(user_id, token_hash, created_at, expires_at, last_used_at) "
        "VALUES(?,?,?,?,NULL)",
        (
            row["id"],
            _hash_login_session_token(token),
            now_text,
            _format_utc(now + LOGIN_SESSION_TTL),
        ),
    )
    db.execute(
        "UPDATE users SET last_login_at=?, last_active_at=? WHERE id=?",
        (now_text, now_text, row["id"]),
    )
    if audit:
        _audit(db, row["id"], row["username"], action)
    db.commit()
    # Only a committed session may enter the compatibility cache.
    TOKENS[row["id"]] = token
    TOKEN_LAST_ACTIVE[row["id"]] = now
    fresh = db.execute("SELECT * FROM users WHERE id=?", (row["id"],)).fetchone()
    return _auth_payload(_user_response(fresh, token=token, db=db))


def _public_avatar_url(filename: str) -> str:
    return f"/api/uploads/avatars/{filename}"


def _external_avatar_url(request: Request, filename: str) -> str:
    return str(request.base_url).rstrip("/") + _public_avatar_url(filename)


def _avatar_file_path_from_url(value: str) -> Optional[Path]:
    text = (value or "").strip()
    marker = "/api/uploads/avatars/"
    if marker not in text:
        return None
    filename = text.rsplit(marker, 1)[-1].split("?", 1)[0].split("#", 1)[0]
    if not filename or filename != os.path.basename(filename):
        return None
    return Path(AVATAR_UPLOAD_DIR) / filename


def _avatar_bytes_match_suffix(raw: bytes, suffix: str) -> bool:
    if suffix == ".png":
        return raw.startswith(b"\x89PNG\r\n\x1a\n")
    if suffix in {".jpg", ".jpeg"}:
        return raw.startswith(b"\xff\xd8\xff")
    if suffix == ".gif":
        return raw.startswith((b"GIF87a", b"GIF89a"))
    if suffix == ".webp":
        return len(raw) >= 12 and raw[:4] == b"RIFF" and raw[8:12] == b"WEBP"
    return False


def _avatar_suffix_from_bytes(raw: bytes) -> str:
    if raw.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if raw.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    if raw.startswith((b"GIF87a", b"GIF89a")):
        return ".gif"
    if len(raw) >= 12 and raw[:4] == b"RIFF" and raw[8:12] == b"WEBP":
        return ".webp"
    return ""


@app.post("/api/auth/register")
def register(req: RegisterRequest):
    db = get_db()
    try:
        if not _registration_enabled(db):
            raise HTTPException(status_code=403, detail="Registration disabled")

        username = _clean_username(req.username)
        password = _clean_password(req.password)
        email = _clean_email(req.email)
        if not email and _looks_like_email(username):
            email = username.lower()
        if _setting_get(db, "registration_email_required", False) and not email:
            raise HTTPException(status_code=400, detail="注册需要绑定邮箱")
        email_verified = 0
        if email and req.email_code:
            _consume_email_code(
                db,
                email=email,
                purpose="bind",
                code=req.email_code,
                user_id=None,
            )
            email_verified = 1
        if _setting_get(db, "registration_email_required", False) and not email_verified:
            raise HTTPException(status_code=400, detail="注册需要邮箱验证码")
        display_name = _clean_short_text(req.display_name, 64, "昵称") or username
        _ensure_account_unique(db, username=username, email=email)

        if _registration_invite_required(db):
            code = (req.invite_code or req.invitation_code or "").strip()
            if not code:
                raise HTTPException(status_code=400, detail="Invite code required")
            row = db.execute(
                "SELECT used_by FROM invite_codes WHERE code=?", (code,)
            ).fetchone()
            if row is None:
                raise HTTPException(status_code=400, detail="Invalid invite code")
            if row["used_by"]:
                raise HTTPException(status_code=400, detail="Invite code already used")

        user_id = secrets.token_hex(16)
        now_text = _utc_now_text()
        try:
            db.execute(
                "INSERT INTO users(id, username, email, email_verified, password_hash, display_name, group_id, role_id, last_login_at, last_active_at) "
                "VALUES(?,?,?,?,?,?,?,?,?,?)",
                (
                    user_id,
                    username,
                    email,
                    email_verified,
                    _hash_password(password),
                    display_name,
                    "group_default",
                    "role_user",
                    now_text,
                    now_text,
                ),
            )
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=409, detail="用户名或邮箱已被使用")

        db.execute("INSERT INTO sync_data(user_id) VALUES(?)", (user_id,))
        _grant_registration_coins(
            db,
            user_id,
            _group_default_time_coins(db, "group_default"),
        )
        _ensure_private_workspace(db, user_id)

        if _registration_invite_required(db):
            db.execute(
                "UPDATE invite_codes SET used_by=?, used_at=datetime('now') WHERE code=?",
                (user_id, (req.invite_code or req.invitation_code or "").strip()),
            )

        _audit(db, user_id, username, "register", user_id)
        row = db.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        # Same transaction: the registration audit and the initial session commit together.
        return _issue_login_session(db, row, action="register", audit=False)
    finally:
        db.close()


@app.post("/api/me/profile")
@app.patch("/api/me/profile")
@app.put("/api/me/profile")
@app.post("/api/profile")
@app.patch("/api/profile")
@app.put("/api/profile")
@app.post("/api/user/profile")
@app.patch("/api/user/profile")
@app.put("/api/user/profile")
@app.post("/api/account/profile")
@app.patch("/api/account/profile")
@app.put("/api/account/profile")
def update_my_profile(req: ProfileUpdate, user_id: str = Depends(_verify_token)):
    return _auth_payload(update_profile(req, user_id=user_id))


@app.post("/api/me/email")
@app.patch("/api/me/email")
@app.put("/api/me/email")
@app.post("/api/me/email/bind")
@app.patch("/api/me/email/bind")
@app.put("/api/me/email/bind")
@app.post("/api/me/bind-email")
@app.patch("/api/me/bind-email")
@app.put("/api/me/bind-email")
@app.post("/api/email")
@app.patch("/api/email")
@app.put("/api/email")
@app.post("/api/email/bind")
@app.patch("/api/email/bind")
@app.put("/api/email/bind")
@app.post("/api/bind-email")
@app.patch("/api/bind-email")
@app.put("/api/bind-email")
@app.post("/api/auth/email")
@app.patch("/api/auth/email")
@app.put("/api/auth/email")
@app.post("/api/auth/bind-email")
@app.patch("/api/auth/bind-email")
@app.put("/api/auth/bind-email")
@app.post("/api/auth/email/bind")
@app.patch("/api/auth/email/bind")
@app.put("/api/auth/email/bind")
@app.post("/api/user/email")
@app.patch("/api/user/email")
@app.put("/api/user/email")
@app.post("/api/user/email/bind")
@app.patch("/api/user/email/bind")
@app.put("/api/user/email/bind")
@app.post("/api/user/bind-email")
@app.patch("/api/user/bind-email")
@app.put("/api/user/bind-email")
@app.post("/api/account/email")
@app.patch("/api/account/email")
@app.put("/api/account/email")
@app.post("/api/account/email/bind")
@app.patch("/api/account/email/bind")
@app.put("/api/account/email/bind")
def bind_my_email(req: EmailLoginRequest, user_id: str = Depends(_verify_token)):
    return _auth_payload(
        update_profile(
            ProfileUpdate(
                email=req.email,
                email_code=req.code or req.email_code or req.emailCode,
            ),
            user_id=user_id,
        )
    )


@app.post("/api/auth/login")
def login(req: LoginRequest):
    db = get_db()
    try:
        identifier = req.username or req.account or req.email or ""
        row = _find_user_by_identifier(db, identifier)
        password_hash = _hash_password(req.password)
        legacy_hash = _legacy_hash_password(req.password)
        if row is None or row["password_hash"] not in {password_hash, legacy_hash}:
            raise HTTPException(status_code=401, detail="Invalid credentials")
        if row["is_disabled"]:
            raise HTTPException(status_code=403, detail="Account disabled")
        if row["password_hash"] == legacy_hash:
            db.execute(
                "UPDATE users SET password_hash=? WHERE id=?",
                (password_hash, row["id"]),
            )
        return _issue_login_session(db, row, action="login")
    finally:
        db.close()


@app.post("/api/auth/email-code")
@app.post("/api/auth/email-code/send")
@app.post("/api/auth/email_code")
@app.post("/api/auth/email_code/send")
@app.post("/api/auth/email/send")
@app.post("/api/auth/email/send-code")
@app.post("/api/auth/send-email-code")
@app.post("/api/auth/send-email_code")
@app.post("/api/me/email-code")
@app.post("/api/me/email-code/send")
@app.post("/api/me/email_code")
@app.post("/api/me/email_code/send")
@app.post("/api/me/email/send")
@app.post("/api/me/email/send-code")
@app.post("/api/email-code")
@app.post("/api/email-code/send")
@app.post("/api/email_code")
@app.post("/api/email_code/send")
@app.post("/api/email/send")
@app.post("/api/email/send-code")
@app.post("/api/send-email-code")
@app.post("/api/send-email_code")
@app.post("/api/user/email-code")
@app.post("/api/user/email-code/send")
@app.post("/api/user/email_code")
@app.post("/api/user/email_code/send")
@app.post("/api/user/email/send")
@app.post("/api/user/email/send-code")
@app.post("/api/account/email-code")
@app.post("/api/account/email-code/send")
@app.post("/api/account/email_code")
@app.post("/api/account/email_code/send")
@app.post("/api/account/email/send")
@app.post("/api/account/email/send-code")
def auth_email_code(
    req: EmailCodeRequest,
    request: Request,
    authorization: Optional[str] = Header(None),
):
    user_id: Optional[str] = None
    if authorization and authorization.startswith("Bearer "):
        user_id = _verify_token_value(authorization[7:])
    db = get_db()
    try:
        result = _create_email_code(
            db,
            email=req.email,
            purpose=req.purpose,
            user_id=user_id,
            ip_address=_client_ip(request),
        )
        payload = _send_email_code_result(db, result)
        if payload.get("sent") is False and not payload.get("dev_code"):
            db.execute(
                "DELETE FROM email_verification_codes WHERE id=?",
                (result["id"],),
            )
            db.rollback()
            raise HTTPException(
                status_code=503,
                detail=payload.get("message")
                or payload.get("detail")
                or "验证码邮件发送失败，请稍后重试或联系管理员检查邮箱服务。",
            )
        _audit(
            db,
            result.get("user_id"),
            _get_username(db, result["user_id"]) if result.get("user_id") else None,
            f"email_code.{result['purpose']}.request",
            target=result["email"],
            detail=str(payload.get("provider") or ""),
        )
        db.commit()
        return payload
    finally:
        db.close()


@app.post("/api/auth/email-login")
@app.post("/api/auth/email/login")
@app.post("/api/auth/login/email")
@app.post("/api/auth/email-code-login")
@app.post("/api/auth/login/email-code")
@app.post("/api/auth/email_code_login")
@app.post("/api/auth/login/email_code")
@app.post("/api/user/email-login")
@app.post("/api/user/login/email-code")
@app.post("/api/user/email_code_login")
@app.post("/api/user/login/email_code")
@app.post("/api/account/email-login")
@app.post("/api/account/email_code_login")
@app.post("/api/email-login")
@app.post("/api/email/login")
@app.post("/api/login/email")
@app.post("/api/email-code-login")
@app.post("/api/login/email-code")
@app.post("/api/email_code_login")
@app.post("/api/login/email_code")
def email_login(req: EmailLoginRequest):
    email = _clean_email(req.email)
    code = req.code or req.email_code or req.emailCode or ""
    db = get_db()
    try:
        _require_email_code_login_enabled(db)
        row = db.execute(
            """
            SELECT * FROM users
            WHERE lower(email)=? AND email_verified=1 AND is_disabled=0
            """,
            (email,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=401, detail="邮箱验证码无效或已过期")
        _consume_email_code(
            db,
            email=email,
            purpose="login",
            code=code,
            user_id=row["id"],
        )
        return _issue_login_session(db, row, action="email_login")
    finally:
        db.close()


@app.get("/api/auth/me")
def me(user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        row = db.execute(
            "SELECT * FROM users WHERE id=?",
            (user_id,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="User not found")
        return _user_response(row, db=db)
    finally:
        db.close()


def _access_token_metadata(row, *, current: bool = False) -> dict:
    return {
        key: row[key]
        for key in (
            "id", "name", "prefix", "created_at", "last_used_at", "expires_at", "revoked_at"
        )
    } | {"current": current}


@app.get("/api/auth/tokens")
def list_access_tokens(
    user_id: str = Depends(_verify_token),
    authorization: Optional[str] = Header(None),
):
    current_hash = _hash_access_token(authorization[7:]) if isinstance(authorization, str) else ""
    db = get_db()
    try:
        rows = db.execute(
            "SELECT * FROM access_tokens WHERE user_id=? ORDER BY created_at DESC, id",
            (user_id,),
        ).fetchall()
        return {"tokens": [
            _access_token_metadata(row, current=secrets.compare_digest(row["token_hash"], current_hash))
            for row in rows
        ]}
    finally:
        db.close()


@app.post("/api/auth/tokens")
def create_access_token(
    req: AccessTokenCreate,
    user_id: str = Depends(_verify_token),
    authorization: Optional[str] = Header(None),
):
    if not isinstance(authorization, str) or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing token")
    db = get_db()
    try:
        # Recheck the credential under the same lock as the quota check and insert.
        db.execute("BEGIN IMMEDIATE")
        _verify_token_in_db(db, authorization[7:], expected_user_id=user_id)
        now = _utc_now()
        now_text = _format_utc(now)
        count = db.execute(
            "SELECT COUNT(*) FROM access_tokens WHERE user_id=? AND revoked_at IS NULL "
            "AND (expires_at IS NULL OR expires_at>?)",
            (user_id, now_text),
        ).fetchone()[0]
        if count >= ACCESS_TOKEN_LIMIT:
            raise HTTPException(status_code=400, detail="Access token limit reached")
        raw_token = "duoyi_pat_" + secrets.token_urlsafe(32)
        token_id = secrets.token_hex(16)
        expires_at = (
            _format_utc(now + timedelta(days=req.expires_in_days))
            if req.expires_in_days is not None else None
        )
        db.execute(
            "INSERT INTO access_tokens(id, user_id, name, prefix, token_hash, created_at, expires_at) "
            "VALUES(?,?,?,?,?,?,?)",
            (token_id, user_id, req.name, raw_token[:18], _hash_access_token(raw_token), now_text, expires_at),
        )
        row = db.execute("SELECT * FROM access_tokens WHERE id=?", (token_id,)).fetchone()
        db.commit()
        return {"token": raw_token, **_access_token_metadata(row)}
    finally:
        db.close()


@app.delete("/api/auth/tokens/{token_id}")
def revoke_access_token(token_id: str, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        result = db.execute(
            "UPDATE access_tokens SET revoked_at=COALESCE(revoked_at, ?) WHERE id=? AND user_id=?",
            (_utc_now_text(), token_id, user_id),
        )
        if result.rowcount == 0:
            raise HTTPException(status_code=404, detail="Token not found")
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


@app.get("/api/me")
def me_alias(user_id: str = Depends(_verify_token)):
    return me(user_id=user_id)


@app.post("/api/theme-shop/apply")
@app.post("/api/me/theme-shop/apply")
def apply_theme_shop_item(
    req: ThemeShopApplyRequest, user_id: str = Depends(_verify_token)
):
    item_type = _theme_shop_type(req.item_type or req.itemType or req.type)
    item_id = str(req.item_id or req.itemId or req.id or "").strip()
    if not item_id:
        raise HTTPException(status_code=400, detail="主题商店物品不能为空")
    _theme_shop_cost(item_type, item_id)  # Validate the catalog ID.
    activate = req.activate if req.activate is not None else req.enabled
    activate = True if activate is None else bool(activate)

    db = get_db()
    try:
        user = db.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        if user is None:
            raise HTTPException(status_code=404, detail="User not found")
        db.execute("INSERT OR IGNORE INTO sync_data(user_id) VALUES(?)", (user_id,))
        row = db.execute(
            "SELECT virtual_rewards, theme_shop_state, sync_version FROM sync_data WHERE user_id=?",
            (user_id,),
        ).fetchone()
        rewards = _json_object(row["virtual_rewards"] if row else "{}")
        raw_theme_state = _json_object(row["theme_shop_state"] if row else "{}")
        theme_state = _normalize_theme_shop_state(raw_theme_state)

        def _num(value, fallback=0) -> int:
            try:
                return int(value)
            except Exception:
                return fallback

        active_key, unlocked_key = THEME_SHOP_FIELDS[item_type]
        unlocked = _theme_shop_list(theme_state.get(unlocked_key))
        default_id = THEME_SHOP_DEFAULTS[item_type]
        if default_id not in unlocked:
            unlocked.insert(0, default_id)
        already_unlocked = item_id in unlocked
        old_active = str(theme_state.get(active_key) or default_id)
        charged = 0
        ledger_entry = None
        now = _utc_now_text()

        balance = _num(rewards.get("balance"))
        lifetime = max(_num(rewards.get("lifetime"), balance), balance)
        if "balance" not in rewards or "lifetime" not in rewards:
            rewards.update(
                {
                    "balance": balance,
                    "lifetime": lifetime,
                    "updatedAt": str(rewards.get("updatedAt") or now),
                }
            )

        changed = theme_state != raw_theme_state
        if not already_unlocked:
            unlocked.append(item_id)
            changed = True
        theme_state[unlocked_key] = unlocked
        if activate and theme_state.get(active_key) != item_id:
            theme_state[active_key] = item_id
            changed = True
            if item_type == "brand" and old_active != item_id:
                theme_state["switchCount"] = int(theme_state.get("switchCount") or 0) + 1
        if changed or charged:
            theme_state["updatedAt"] = now
            next_sync_version = int(row["sync_version"] or 0) + 1 if row else 1
            db.execute(
                """
                UPDATE sync_data
                SET virtual_rewards=?, theme_shop_state=?, sync_version=?, updated_at=?
                WHERE user_id=?
                """,
                (
                    json.dumps(rewards, ensure_ascii=False),
                    json.dumps(theme_state, ensure_ascii=False),
                    next_sync_version,
                    now,
                    user_id,
                ),
            )
            _audit(
                db,
                user_id,
                user["username"],
                "theme_shop.apply",
                target=item_id,
                detail=json.dumps(
                    {
                        "item_type": item_type,
                        "item_id": item_id,
                        "charged": charged,
                        "activate": activate,
                    },
                    ensure_ascii=False,
                ),
            )
            db.commit()
        else:
            next_sync_version = int(row["sync_version"] or 0) if row else 0

        fresh = db.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        user_payload = _user_response(fresh, db=db)
        return {
            "status": "ok",
            "item_type": item_type,
            "item_id": item_id,
            "activated": activate,
            "unlocked": True,
            "charged": charged,
            "coin_balance": balance,
            "lifetime_coins": lifetime,
            "virtual_rewards": rewards,
            "theme_shop_state": theme_state,
            "ledger_entry": ledger_entry,
            "server_version": next_sync_version,
            "user": user_payload,
        }
    finally:
        db.close()


@app.post("/api/auth/profile")
@app.patch("/api/auth/profile")
@app.put("/api/auth/profile")
def update_profile(req: ProfileUpdate, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        current = db.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        if current is None:
            raise HTTPException(status_code=404, detail="User not found")
        username = current["username"]
        email = (
            _clean_email(req.email)
            if req.email is not None
            else (current["email"] or "")
        )
        email_code = req.email_code or req.emailCode or req.code
        email_verified = int(current["email_verified"] or 0)
        if req.email is not None and email != (current["email"] or ""):
            email_verified = 0
            if email and email_code:
                _consume_email_code(
                    db,
                    email=email,
                    purpose="bind",
                    code=email_code,
                    user_id=user_id,
                )
                email_verified = 1
        elif email_code and email:
            _consume_email_code(
                db,
                email=email,
                purpose="bind",
                code=email_code,
                user_id=user_id,
            )
            email_verified = 1
        display_name_value = req.display_name
        if display_name_value is None:
            display_name_value = req.displayName
        display_name = (
            _clean_short_text(display_name_value, 64, "昵称")
            if display_name_value is not None
            else (current["display_name"] or "")
        )
        # Avatar changes must go through the multipart avatar upload endpoints.
        # Profile PATCH ignores legacy avatar strings so old clients cannot
        # reintroduce URL/text avatar editing.
        avatar = current["avatar"] or ""
        bio = (
            _clean_short_text(req.bio, 280, "简介")
            if req.bio is not None
            else (current["bio"] or "")
        )
        _ensure_account_unique(
            db,
            email=email,
            exclude_user_id=user_id,
        )
        db.execute(
            "UPDATE users SET username=?, email=?, email_verified=?, display_name=?, avatar=?, bio=? WHERE id=?",
            (username, email, email_verified, display_name, avatar, bio, user_id),
        )
        _audit(db, user_id, username, "profile.update", user_id)
        db.commit()
        row = db.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        return _user_response(row, db=db)
    finally:
        db.close()


@app.post("/api/auth/password-reset")
@app.post("/api/auth/password-reset/request")
@app.post("/api/auth/reset-password")
@app.post("/api/auth/reset-password/request")
@app.post("/api/auth/forgot-password")
@app.post("/api/auth/forgot-password/request")
@app.post("/api/password-reset")
@app.post("/api/password-reset/request")
def request_password_reset(req: PasswordResetRequest):
    identifier = (req.email or req.identifier or req.account or req.username or "").strip()
    payload = {"ok": True}
    db = get_db()
    try:
        row = _find_user_by_identifier(db, identifier)
        if row is not None and not row["is_disabled"]:
            raw_token = f"{secrets.randbelow(1_000_000):06d}"
            expires_at = _format_utc(_utc_now() + timedelta(minutes=30))
            recipient = _account_email_recipient(row)
            if not recipient:
                raise HTTPException(status_code=400, detail="账号未绑定邮箱，无法找回密码")
            db.execute(
                "INSERT INTO password_reset_tokens(token_hash, user_id, expires_at) VALUES(?,?,?)",
                (_hash_reset_token(raw_token), row["id"], expires_at),
            )
            db.execute(
                """
                INSERT INTO email_verification_codes(
                    id, user_id, email, purpose, code_hash, expires_at, ip_address, created_at
                ) VALUES(?,?,?,?,?,?,?,?)
                """,
                (
                    secrets.token_hex(16),
                    row["id"],
                    _clean_email(recipient),
                    "reset",
                    _hash_email_code(raw_token),
                    expires_at,
                    "",
                    _utc_now_text(),
                ),
            )
            try:
                _send_password_reset_email(db, row, raw_token)
                _audit(db, row["id"], row["username"], "password_reset.request")
            except Exception as e:
                _audit(
                    db,
                    row["id"],
                    row["username"],
                    "password_reset.email_failed",
                    detail=str(e),
                )
                runtime = _account_mail_runtime(db)
                if not _any_account_email_provider_configured(runtime):
                    payload["dev_code"] = raw_token
            db.commit()
        return payload
    finally:
        db.close()


@app.post("/api/auth/password-reset/confirm")
@app.post("/api/auth/reset-password/confirm")
@app.post("/api/auth/forgot-password/confirm")
@app.post("/api/password-reset/confirm")
def confirm_password_reset(req: PasswordResetConfirm):
    password = _clean_password(req.new_password or req.password or "")
    db = get_db()
    try:
        identifier = (req.email or req.identifier or req.account or req.username or "").strip()
        if identifier and req.code:
            user = _find_user_by_identifier(db, identifier)
            if user is None:
                raise HTTPException(status_code=400, detail="验证码无效或已过期")
            if user["is_disabled"]:
                raise HTTPException(status_code=400, detail="验证码无效或已过期")
            recipient = _account_email_recipient(user)
            if not recipient:
                raise HTTPException(status_code=400, detail="验证码无效或已过期")
            _consume_email_code(
                db,
                email=recipient,
                purpose="reset",
                code=req.code,
                user_id=user["id"],
            )
            token_hash = _hash_reset_token(req.code.strip())
            token_row = db.execute(
                """
                SELECT *
                FROM password_reset_tokens
                WHERE token_hash=? AND user_id=?
                """,
                (token_hash, user["id"]),
            ).fetchone()
            if token_row is None or token_row["used_at"] is not None:
                raise HTTPException(status_code=400, detail="验证码无效或已使用")
            expires_at = _parse_server_time(token_row["expires_at"])
            if expires_at is None or expires_at < _utc_now():
                raise HTTPException(status_code=400, detail="验证码已过期")
            db.execute(
                """
                UPDATE password_reset_tokens
                SET used_at=?
                WHERE token_hash=? AND user_id=? AND used_at IS NULL
                """,
                (_utc_now_text(), token_hash, user["id"]),
            )
            db.execute(
                "UPDATE users SET password_hash=?, email_verified=1 WHERE id=?",
                (_hash_password(password), user["id"]),
            )
            _revoke_user_token(user["id"], db)
            _audit(db, user["id"], user["username"], "password_reset.confirm")
            db.commit()
            return {"ok": True}

        token_hash = _hash_reset_token((req.token or req.code or "").strip())
        row = db.execute(
            """
            SELECT prt.*, u.username
            FROM password_reset_tokens prt
            JOIN users u ON u.id=prt.user_id
            WHERE prt.token_hash=?
            """,
            (token_hash,),
        ).fetchone()
        if row is None or row["used_at"] is not None:
            raise HTTPException(status_code=400, detail="验证码无效或已使用")
        expires_at = _parse_server_time(row["expires_at"])
        if expires_at is None or expires_at < _utc_now():
            raise HTTPException(status_code=400, detail="验证码已过期")
        db.execute(
            "UPDATE users SET password_hash=? WHERE id=?",
            (_hash_password(password), row["user_id"]),
        )
        db.execute(
            "UPDATE password_reset_tokens SET used_at=? WHERE token_hash=?",
            (_utc_now_text(), token_hash),
        )
        _revoke_user_token(row["user_id"], db)
        _audit(db, row["user_id"], row["username"], "password_reset.confirm")
        db.commit()
        return {"ok": True}
    finally:
        db.close()


@app.post("/api/auth/change-password")
@app.post("/api/me/password")
def change_password(req: ChangePasswordRequest, user_id: str = Depends(_verify_token)):
    current_password = req.current_password or req.currentPassword or req.old_password or ""
    new_password = _clean_password(req.new_password or req.newPassword or req.password or "")
    db = get_db()
    try:
        row = db.execute(
            "SELECT * FROM users WHERE id=?",
            (user_id,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="User not found")
        password_hash = _hash_password(current_password)
        legacy_hash = _legacy_hash_password(current_password)
        if row["password_hash"] not in {password_hash, legacy_hash}:
            raise HTTPException(status_code=403, detail="当前密码不正确")
        db.execute(
            "UPDATE users SET password_hash=? WHERE id=?",
            (_hash_password(new_password), user_id),
        )
        _revoke_user_token(user_id, db)
        _audit(db, user_id, row["username"], "password.change")
        db.commit()
        return {"ok": True}
    finally:
        db.close()


@app.post("/api/auth/avatar")
@app.patch("/api/auth/avatar")
@app.put("/api/auth/avatar")
@app.post("/api/auth/profile/avatar")
@app.patch("/api/auth/profile/avatar")
@app.put("/api/auth/profile/avatar")
@app.post("/api/me/avatar")
@app.patch("/api/me/avatar")
@app.put("/api/me/avatar")
@app.post("/api/me/profile/avatar")
@app.patch("/api/me/profile/avatar")
@app.put("/api/me/profile/avatar")
@app.post("/api/avatar")
@app.patch("/api/avatar")
@app.put("/api/avatar")
@app.post("/api/profile/avatar")
@app.patch("/api/profile/avatar")
@app.put("/api/profile/avatar")
@app.post("/api/user/avatar")
@app.patch("/api/user/avatar")
@app.put("/api/user/avatar")
@app.post("/api/user/profile/avatar")
@app.patch("/api/user/profile/avatar")
@app.put("/api/user/profile/avatar")
@app.post("/api/account/avatar")
@app.patch("/api/account/avatar")
@app.put("/api/account/avatar")
@app.post("/api/account/profile/avatar")
@app.patch("/api/account/profile/avatar")
@app.put("/api/account/profile/avatar")
async def upload_avatar(
    request: Request,
    avatar: Optional[UploadFile] = File(None),
    file: Optional[UploadFile] = File(None),
    image: Optional[UploadFile] = File(None),
    user_id: str = Depends(_verify_token),
):
    avatar = avatar or file or image
    if avatar is None:
        raise HTTPException(status_code=400, detail="头像文件不能为空")
    raw = await avatar.read()
    if not raw:
        raise HTTPException(status_code=400, detail="头像文件不能为空")
    if len(raw) > 3 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="头像不能超过 3MB")
    content_type = (avatar.content_type or "").lower()
    suffix = Path(avatar.filename or "").suffix.lower()
    detected_suffix = _avatar_suffix_from_bytes(raw)
    if suffix not in {".jpg", ".jpeg", ".png", ".webp", ".gif"}:
        if "png" in content_type:
            suffix = ".png"
        elif "jpeg" in content_type or "jpg" in content_type:
            suffix = ".jpg"
        elif "webp" in content_type:
            suffix = ".webp"
        elif "gif" in content_type:
            suffix = ".gif"
        elif detected_suffix:
            suffix = detected_suffix
        else:
            raise HTTPException(status_code=400, detail="仅支持 jpg/png/webp/gif 头像")
    if not _avatar_bytes_match_suffix(raw, suffix):
        if not detected_suffix:
            raise HTTPException(status_code=400, detail="头像文件内容与格式不匹配")
        suffix = detected_suffix
    upload_dir = Path(AVATAR_UPLOAD_DIR)
    upload_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{user_id}_{secrets.token_hex(12)}{suffix}"
    path = upload_dir / filename
    path.write_bytes(raw)
    avatar_url = _public_avatar_url(filename)
    db = get_db()
    try:
        row = db.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        if row is None:
            try:
                path.unlink()
            except FileNotFoundError:
                pass
            raise HTTPException(status_code=404, detail="User not found")
        previous_path = _avatar_file_path_from_url(row["avatar"] or "")
        db.execute("UPDATE users SET avatar=? WHERE id=?", (avatar_url, user_id))
        _audit(db, user_id, row["username"], "profile.avatar_upload", user_id)
        db.commit()
        if previous_path and previous_path != path:
            try:
                previous_path.unlink()
            except FileNotFoundError:
                pass
        fresh = db.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        return _auth_payload(_user_response(fresh, db=db))
    finally:
        db.close()


@app.get("/api/uploads/avatars/{filename}")
def get_avatar_upload(filename: str):
    if filename != os.path.basename(filename):
        raise HTTPException(status_code=404, detail="Not found")
    path = Path(AVATAR_UPLOAD_DIR) / filename
    if not path.exists() or not path.is_file():
        raise HTTPException(status_code=404, detail="Not found")
    return FileResponse(path)


@app.post("/api/auth/logout")
@app.post("/api/auth/signout")
@app.post("/api/auth/sign-out")
@app.post("/api/logout")
@app.post("/api/me/logout")
@app.post("/api/user/logout")
@app.post("/api/account/logout")
def logout(
    user_id: str = Depends(_verify_token),
    authorization: Optional[str] = Header(None),
):
    db = get_db()
    try:
        revoked_pat = False
        if isinstance(authorization, str):
            result = db.execute(
                "UPDATE access_tokens SET revoked_at=COALESCE(revoked_at, ?) "
                "WHERE user_id=? AND token_hash=?",
                (_utc_now_text(), user_id, _hash_access_token(authorization[7:])),
            )
            revoked_pat = bool(result.rowcount)
        if not revoked_pat:
            # A request authenticated before a new login must not revoke the new session.
            if isinstance(authorization, str):
                token = authorization[7:]
                db.execute(
                    "DELETE FROM login_sessions WHERE user_id=? AND token_hash=?",
                    (user_id, _hash_login_session_token(token)),
                )
                _forget_cached_token(token)
            else:
                _drop_session(user_id, db)
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


# ---- Focus Rooms ----


def _clean_focus_room_id(room_id: str) -> str:
    clean = (room_id or "").strip()
    if not clean or len(clean) > 128:
        raise HTTPException(status_code=400, detail="Invalid focus room id")
    return clean


def _clean_focus_display_name(value: Optional[str], fallback: str) -> str:
    clean = (value or "").strip()
    if not clean:
        clean = fallback
    return clean[:32]


def _clean_focus_metric(value: int, upper: int) -> int:
    try:
        number = int(value)
    except Exception:
        number = 0
    return max(0, min(number, upper))


def _parse_focus_risk_flags(value: Optional[str]) -> list[str]:
    if not value:
        return []
    try:
        parsed = json.loads(value)
    except Exception:
        return []
    if not isinstance(parsed, list):
        return []
    return [str(item)[:64] for item in parsed if str(item).strip()]


def _focus_risk_summary(flags: list[str]) -> str:
    labels = {
        "weekly_seconds_capped": "weekly focus seconds exceeded server cap",
        "session_count_capped": "session count exceeded server cap",
        "session_count_jump_capped": "session count jumped too quickly and was capped",
        "heartbeat_throttled": "heartbeat arrived too soon and was throttled",
    }
    return "; ".join(labels.get(flag, flag) for flag in flags)


def _focus_risk_payload(flags: list[str]) -> tuple[str, str]:
    ordered = list(dict.fromkeys(flags))
    return json.dumps(ordered, ensure_ascii=False), _focus_risk_summary(ordered)


def _merge_focus_risk_flags(value: Optional[str]) -> list[str]:
    merged: list[str] = []
    for raw in (value or "").split("|"):
        merged.extend(_parse_focus_risk_flags(raw))
    return list(dict.fromkeys(merged))


def _clean_focus_room_name(value: str) -> str:
    clean = (value or "").strip()
    if not clean:
        raise HTTPException(status_code=400, detail="Focus room name required")
    return clean[:64]


def _focus_room_payload(
    room_id: str,
    room_name: str,
    description: str,
    weekly_target_seconds: int,
    accent_color: int,
) -> dict:
    return {
        "id": room_id,
        "name": room_name,
        "description": (description or "")[:200],
        "weekly_target_seconds": _clean_focus_metric(
            weekly_target_seconds,
            10080 * 60,
        )
        or 18000,
        "accent_color": int(accent_color or 0xFF3949AB),
    }


def _clean_focus_invite_max_uses(value: Optional[int]) -> int:
    if value is None:
        return 0
    return _clean_focus_metric(value, 9999)


def _focus_room_invite_payload(row) -> dict:
    return {
        "id": row["id"],
        "code": row["code"],
        "room": _focus_room_payload(
            row["room_id"],
            row["room_name"],
            row["description"],
            row["weekly_target_seconds"],
            row["accent_color"],
        ),
        "expires_at": row["expires_at"],
        "max_uses": int(row["max_uses"] or 0),
        "used_count": int(row["used_count"] or 0),
        "last_used_at": row["last_used_at"],
        "revoked": bool(row["revoked"]),
        "created_at": row["created_at"],
    }


def _focus_room_ranking(db, room_id: str, current_user_id: str) -> dict:
    cutoff = _utc_now() - timedelta(seconds=FOCUS_ROOM_ONLINE_SECONDS)
    rows = db.execute(
        """
        SELECT p.room_id, p.user_id, p.display_name, p.raw_weekly_seconds,
               p.weekly_seconds, p.session_count, p.active, p.started_at,
               p.last_seen_at, p.risk_flags, p.risk_summary, u.username
        FROM focus_room_presence p
        JOIN users u ON u.id = p.user_id
        WHERE p.room_id=?
        """,
        (room_id,),
    ).fetchall()
    online_user_ids = _online_user_ids((row["user_id"] for row in rows), db=db)
    entries = []
    for row in rows:
        last_seen = _parse_server_time(row["last_seen_at"])
        online = (
            bool(row["active"])
            and last_seen is not None
            and last_seen >= cutoff
            and row["user_id"] in online_user_ids
        )
        entries.append(
            {
        "room_id": row["room_id"],
        "user_id": row["user_id"],
        "display_name": row["display_name"] or row["username"],
                "raw_weekly_seconds": int(row["raw_weekly_seconds"] or 0),
                "weekly_seconds": int(row["weekly_seconds"] or 0),
                "session_count": int(row["session_count"] or 0),
                "online": online,
                "active": bool(row["active"]),
                "is_current_user": row["user_id"] == current_user_id,
                "started_at": row["started_at"],
                "last_seen_at": row["last_seen_at"],
                "risk_flags": _parse_focus_risk_flags(row["risk_flags"]),
                "risk_summary": row["risk_summary"] or "",
                "rank": 0,
            }
        )

    entries.sort(
        key=lambda item: (
            -item["weekly_seconds"],
            -item["session_count"],
            item["display_name"],
            item["user_id"],
        )
    )
    for idx, item in enumerate(entries):
        item["rank"] = idx + 1
    return {
        "room_id": room_id,
        "online_count": sum(1 for item in entries if item["online"]),
        "updated_at": _utc_now_text(),
        "entries": entries,
    }


def _is_user_online(row, online_user_ids: Optional[set[str]] = None) -> bool:
    parsed = _parse_server_time(row["last_active_at"])
    cutoff = _utc_now() - timedelta(seconds=SESSION_ONLINE_SECONDS)
    if online_user_ids is None:
        online_user_ids = _online_user_ids([row["id"]])
    return parsed is not None and parsed >= cutoff and row["id"] in online_user_ids


def _focus_friend_payload(row, online_user_ids: Optional[set[str]] = None) -> dict:
    return {
        "user_id": row["id"],
        "username": row["username"],
        "status": _row_get(row, "status", "accepted"),
        "online": _is_user_online(row, online_user_ids),
        "last_active_at": row["last_active_at"],
        "created_at": row["created_at"],
    }


def _focus_friend_request_payload(
    row, current_user_id: str, online_user_ids: Optional[set[str]] = None
) -> dict:
    direction = "incoming" if row["friend_user_id"] == current_user_id else "outgoing"
    other_id = row["user_id"] if direction == "incoming" else row["friend_user_id"]
    other_username = (
        row["requester_username"]
        if direction == "incoming"
        else row["addressee_username"]
    )
    other_last_active_at = (
        row["requester_last_active_at"]
        if direction == "incoming"
        else row["addressee_last_active_at"]
    )
    return {
        "id": f"{row['user_id']}:{row['friend_user_id']}",
        "user_id": other_id,
        "username": other_username,
        "direction": direction,
        "status": row["status"],
        "online": _is_user_online(
            {
                "id": other_id,
                "last_active_at": other_last_active_at,
            },
            online_user_ids,
        ),
        "created_at": row["created_at"],
    }


def _focus_friend_request_rows(db, current_user_id: str):
    return db.execute(
        """
        SELECT ff.user_id, ff.friend_user_id, ff.status, ff.created_at,
               requester.username AS requester_username,
               requester.last_active_at AS requester_last_active_at,
               addressee.username AS addressee_username,
               addressee.last_active_at AS addressee_last_active_at
        FROM focus_friends ff
        JOIN users requester ON requester.id = ff.user_id
        JOIN users addressee ON addressee.id = ff.friend_user_id
        WHERE ff.status='pending'
          AND (ff.user_id=? OR ff.friend_user_id=?)
        ORDER BY ff.created_at DESC
        """,
        (current_user_id, current_user_id),
    ).fetchall()


def _focus_friend_recent_request_count(db, user_id: str) -> int:
    since = _format_utc(_utc_now() - timedelta(days=1))
    row = db.execute(
        """
        SELECT COUNT(*) AS c
        FROM focus_friend_request_log
        WHERE user_id=? AND created_at>=?
        """,
        (user_id, since),
    ).fetchone()
    return int(row["c"] if row else 0)


def _focus_friend_ranking(db, current_user_id: str) -> dict:
    friend_rows = db.execute(
        """
        SELECT u.id, u.username, u.last_active_at, ff.created_at
        FROM focus_friends ff
        JOIN users u ON u.id = ff.friend_user_id
        WHERE ff.user_id=? AND ff.status='accepted'
        ORDER BY u.username COLLATE NOCASE ASC
        """,
        (current_user_id,),
    ).fetchall()
    current = db.execute(
        """
        SELECT id, username, last_active_at, created_at
        FROM users
        WHERE id=?
        """,
        (current_user_id,),
    ).fetchone()

    users = []
    if current is not None:
        users.append(current)
    users.extend(friend_rows)
    user_ids = [row["id"] for row in users]
    online_user_ids = _online_user_ids(user_ids, db=db)

    stats = {
        user_id: {
            "raw_weekly_seconds": 0,
            "weekly_seconds": 0,
            "session_count": 0,
        }
        for user_id in user_ids
    }
    if user_ids:
        placeholders = ",".join("?" for _ in user_ids)
        rows = db.execute(
            f"""
            SELECT user_id,
                   SUM(raw_weekly_seconds) AS raw_weekly_seconds,
                   SUM(weekly_seconds) AS weekly_seconds,
                   SUM(session_count) AS session_count,
                   GROUP_CONCAT(risk_flags, '|') AS risk_flags
            FROM focus_room_presence
            WHERE user_id IN ({placeholders})
            GROUP BY user_id
            """,
            tuple(user_ids),
        ).fetchall()
        for row in rows:
            stats[row["user_id"]] = {
                "raw_weekly_seconds": int(row["raw_weekly_seconds"] or 0),
                "weekly_seconds": min(
                    int(row["weekly_seconds"] or 0),
                    FOCUS_ROOM_MAX_WEEKLY_SECONDS,
                ),
                "session_count": min(
                    int(row["session_count"] or 0),
                    FOCUS_ROOM_MAX_SESSION_COUNT,
                ),
                "risk_flags": _merge_focus_risk_flags(row["risk_flags"]),
            }

    entries = []
    for row in users:
        score = stats.get(row["id"]) or {}
        weekly_seconds = int(score.get("weekly_seconds") or 0)
        raw_weekly_seconds = int(score.get("raw_weekly_seconds") or 0)
        session_count = int(score.get("session_count") or 0)
        risk_flags = score.get("risk_flags") or []
        entries.append(
            {
                "user_id": row["id"],
                "display_name": row["username"],
                "raw_weekly_seconds": raw_weekly_seconds,
                "weekly_seconds": weekly_seconds,
                "session_count": session_count,
                "online": _is_user_online(row, online_user_ids),
                "active": True,
                "is_current_user": row["id"] == current_user_id,
                "last_seen_at": row["last_active_at"],
                "risk_flags": risk_flags,
                "risk_summary": _focus_risk_summary(risk_flags),
                "rank": 0,
            }
        )

    entries.sort(
        key=lambda item: (
            -item["weekly_seconds"],
            -item["session_count"],
            item["display_name"],
            item["user_id"],
        )
    )
    for idx, item in enumerate(entries):
        item["rank"] = idx + 1
    return {
        "scope": "friends",
        "online_count": sum(1 for item in entries if item["online"]),
        "updated_at": _utc_now_text(),
        "entries": entries,
    }


def _focus_global_ranking(db, current_user_id: str) -> dict:
    rows = db.execute(
        """
        SELECT u.id, u.username, u.last_active_at,
               COALESCE(SUM(p.raw_weekly_seconds), 0) AS raw_weekly_seconds,
               COALESCE(SUM(p.weekly_seconds), 0) AS weekly_seconds,
               COALESCE(SUM(p.session_count), 0) AS session_count,
               GROUP_CONCAT(p.risk_flags, '|') AS risk_flags
        FROM users u
        LEFT JOIN focus_room_presence p ON p.user_id = u.id
        WHERE u.is_disabled=0
          AND (p.user_id IS NOT NULL OR u.id=?)
        GROUP BY u.id, u.username, u.last_active_at
        """,
        (current_user_id,),
    ).fetchall()
    online_user_ids = _online_user_ids((row["id"] for row in rows), db=db)

    entries = []
    for row in rows:
        raw_weekly_seconds = int(row["raw_weekly_seconds"] or 0)
        weekly_seconds = min(
            int(row["weekly_seconds"] or 0),
            FOCUS_ROOM_MAX_WEEKLY_SECONDS,
        )
        session_count = min(
            int(row["session_count"] or 0),
            FOCUS_ROOM_MAX_SESSION_COUNT,
        )
        risk_flags = _merge_focus_risk_flags(row["risk_flags"])
        entries.append(
            {
                "user_id": row["id"],
                "display_name": row["username"],
                "raw_weekly_seconds": raw_weekly_seconds,
                "weekly_seconds": weekly_seconds,
                "session_count": session_count,
                "online": _is_user_online(row, online_user_ids),
                "active": True,
                "is_current_user": row["id"] == current_user_id,
                "last_seen_at": row["last_active_at"],
                "risk_flags": risk_flags,
                "risk_summary": _focus_risk_summary(risk_flags),
                "rank": 0,
            }
        )

    entries.sort(
        key=lambda item: (
            -item["weekly_seconds"],
            -item["session_count"],
            item["display_name"],
            item["user_id"],
        )
    )
    for idx, item in enumerate(entries):
        item["rank"] = idx + 1
    return {
        "scope": "global",
        "online_count": sum(1 for item in entries if item["online"]),
        "updated_at": _utc_now_text(),
        "entries": entries,
    }


def _verify_focus_websocket(websocket: WebSocket) -> str:
    token = (websocket.query_params.get("token") or "").strip()
    if not token:
        authorization = (websocket.headers.get("authorization") or "").strip()
        if authorization.lower().startswith("bearer "):
            token = authorization[7:].strip()
    return _verify_token_value(token)


@app.get("/api/focus-friends")
def list_focus_friends(user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        rows = db.execute(
            """
            SELECT u.id, u.username, u.last_active_at, ff.status, ff.created_at
            FROM focus_friends ff
            JOIN users u ON u.id = ff.friend_user_id
            WHERE ff.user_id=? AND ff.status='accepted'
            ORDER BY u.username COLLATE NOCASE ASC
            """,
            (user_id,),
        ).fetchall()
        online_user_ids = _online_user_ids((row["id"] for row in rows), db=db)
        return {"items": [_focus_friend_payload(row, online_user_ids) for row in rows]}
    finally:
        db.close()


@app.get("/api/focus-friends/requests")
def list_focus_friend_requests(user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        rows = _focus_friend_request_rows(db, user_id)
        online_user_ids = _online_user_ids(
            {other_id for row in rows for other_id in (row["user_id"], row["friend_user_id"])},
            db=db,
        )
        items = [
            _focus_friend_request_payload(row, user_id, online_user_ids)
            for row in rows
        ]
        return {
            "items": items,
            "incoming": [item for item in items if item["direction"] == "incoming"],
            "outgoing": [item for item in items if item["direction"] == "outgoing"],
        }
    finally:
        db.close()


@app.post("/api/focus-friends")
def add_focus_friend(
    req: FocusFriendCreate,
    user_id: str = Depends(_verify_token),
):
    username = (req.username or "").strip()
    requested_user_id = (req.user_id or "").strip()
    if not username and not requested_user_id:
        raise HTTPException(status_code=400, detail="Friend username required")
    db = get_db()
    try:
        if requested_user_id:
            friend = db.execute(
                """
                SELECT id, username, last_active_at, created_at
                FROM users
                WHERE id=?
                """,
                (requested_user_id,),
            ).fetchone()
        else:
            friend = db.execute(
                """
                SELECT id, username, last_active_at, created_at
                FROM users
                WHERE lower(username)=lower(?)
                """,
                (username,),
            ).fetchone()
        if friend is None:
            raise HTTPException(status_code=404, detail="Friend user not found")
        if friend["id"] == user_id:
            raise HTTPException(status_code=400, detail="Cannot add yourself")
        existing = db.execute(
            """
            SELECT status
            FROM focus_friends
            WHERE user_id=? AND friend_user_id=?
            """,
            (user_id, friend["id"]),
        ).fetchone()
        if existing is not None and existing["status"] == "accepted":
            created = db.execute(
                """
                SELECT u.id, u.username, u.last_active_at, ff.status, ff.created_at
                FROM focus_friends ff
                JOIN users u ON u.id = ff.friend_user_id
                WHERE ff.user_id=? AND ff.friend_user_id=?
                """,
                (user_id, friend["id"]),
            ).fetchone()
            return _focus_friend_payload(created or friend)

        incoming = db.execute(
            """
            SELECT status
            FROM focus_friends
            WHERE user_id=? AND friend_user_id=? AND status='pending'
            """,
            (friend["id"], user_id),
        ).fetchone()
        now_text = _utc_now_text()
        if incoming is not None:
            db.execute(
                """
                UPDATE focus_friends
                SET status='accepted'
                WHERE user_id=? AND friend_user_id=?
                """,
                (friend["id"], user_id),
            )
            db.execute(
                """
                INSERT INTO focus_friends(user_id, friend_user_id, status, created_at)
                VALUES(?,?,?,?)
                ON CONFLICT(user_id, friend_user_id) DO UPDATE SET
                    status='accepted'
                """,
                (user_id, friend["id"], "accepted", now_text),
            )
            db.commit()
            created = db.execute(
                """
                SELECT u.id, u.username, u.last_active_at, ff.status, ff.created_at
                FROM focus_friends ff
                JOIN users u ON u.id = ff.friend_user_id
                WHERE ff.user_id=? AND ff.friend_user_id=?
                """,
                (user_id, friend["id"]),
            ).fetchone()
            return _focus_friend_payload(created or friend)

        if (
            existing is None
            and _focus_friend_recent_request_count(db, user_id)
            >= FOCUS_FRIEND_REQUEST_LIMIT_PER_DAY
        ):
            raise HTTPException(
                status_code=429,
                detail="Focus friend request limit reached",
            )
        db.execute(
            """
            INSERT INTO focus_friends(user_id, friend_user_id, status, created_at)
            VALUES(?,?,?,?)
            ON CONFLICT(user_id, friend_user_id) DO UPDATE SET
                status='pending'
            """,
            (user_id, friend["id"], "pending", now_text),
        )
        if existing is None:
            db.execute(
                """
                INSERT INTO focus_friend_request_log(user_id, friend_user_id, created_at)
                VALUES(?,?,?)
                """,
                (user_id, friend["id"], now_text),
            )
        db.commit()
        created = db.execute(
            """
            SELECT u.id, u.username, u.last_active_at, ff.status, ff.created_at
            FROM focus_friends ff
            JOIN users u ON u.id = ff.friend_user_id
            WHERE ff.user_id=? AND ff.friend_user_id=?
            """,
            (user_id, friend["id"]),
        ).fetchone()
        return _focus_friend_payload(created or friend)
    finally:
        db.close()


@app.post("/api/focus-friend-requests/{requester_user_id}/accept")
def accept_focus_friend_request(
    requester_user_id: str,
    user_id: str = Depends(_verify_token),
):
    clean_requester_id = (requester_user_id or "").strip()
    if not clean_requester_id:
        raise HTTPException(status_code=400, detail="Invalid requester user id")
    db = get_db()
    try:
        row = db.execute(
            """
            SELECT 1 FROM focus_friends
            WHERE user_id=? AND friend_user_id=? AND status='pending'
            """,
            (clean_requester_id, user_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Focus friend request not found")
        now_text = _utc_now_text()
        db.execute(
            """
            UPDATE focus_friends SET status='accepted'
            WHERE user_id=? AND friend_user_id=?
            """,
            (clean_requester_id, user_id),
        )
        db.execute(
            """
            INSERT INTO focus_friends(user_id, friend_user_id, status, created_at)
            VALUES(?,?,?,?)
            ON CONFLICT(user_id, friend_user_id) DO UPDATE SET
                status='accepted'
            """,
            (user_id, clean_requester_id, "accepted", now_text),
        )
        db.commit()
        accepted = db.execute(
            """
            SELECT u.id, u.username, u.last_active_at, ff.status, ff.created_at
            FROM focus_friends ff
            JOIN users u ON u.id = ff.friend_user_id
            WHERE ff.user_id=? AND ff.friend_user_id=?
            """,
            (user_id, clean_requester_id),
        ).fetchone()
        return _focus_friend_payload(accepted)
    finally:
        db.close()


@app.post("/api/focus-friend-requests/{requester_user_id}/reject")
def reject_focus_friend_request(
    requester_user_id: str,
    user_id: str = Depends(_verify_token),
):
    clean_requester_id = (requester_user_id or "").strip()
    if not clean_requester_id:
        raise HTTPException(status_code=400, detail="Invalid requester user id")
    db = get_db()
    try:
        db.execute(
            """
            DELETE FROM focus_friends
            WHERE user_id=? AND friend_user_id=? AND status='pending'
            """,
            (clean_requester_id, user_id),
        )
        db.commit()
        return {"status": "ok", "user_id": clean_requester_id}
    finally:
        db.close()


@app.delete("/api/focus-friend-requests/{friend_user_id}")
def cancel_focus_friend_request(
    friend_user_id: str,
    user_id: str = Depends(_verify_token),
):
    clean_friend_user_id = (friend_user_id or "").strip()
    if not clean_friend_user_id:
        raise HTTPException(status_code=400, detail="Invalid friend user id")
    db = get_db()
    try:
        db.execute(
            """
            DELETE FROM focus_friends
            WHERE user_id=? AND friend_user_id=? AND status='pending'
            """,
            (user_id, clean_friend_user_id),
        )
        db.commit()
        return {"status": "ok", "user_id": clean_friend_user_id}
    finally:
        db.close()


@app.delete("/api/focus-friends/{friend_user_id}")
def remove_focus_friend(
    friend_user_id: str,
    user_id: str = Depends(_verify_token),
):
    clean_friend_user_id = (friend_user_id or "").strip()
    if not clean_friend_user_id:
        raise HTTPException(status_code=400, detail="Invalid friend user id")
    db = get_db()
    try:
        db.execute(
            """
            DELETE FROM focus_friends
            WHERE (user_id=? AND friend_user_id=?)
               OR (user_id=? AND friend_user_id=?)
            """,
            (user_id, clean_friend_user_id, clean_friend_user_id, user_id),
        )
        db.commit()
        return {"status": "ok", "user_id": clean_friend_user_id}
    finally:
        db.close()


@app.get("/api/focus-leaderboard/friends")
def focus_friend_leaderboard(user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        return _focus_friend_ranking(db, user_id)
    finally:
        db.close()


@app.get("/api/focus-leaderboard/global")
def focus_global_leaderboard(user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        return _focus_global_ranking(db, user_id)
    finally:
        db.close()


@app.get("/api/focus-leaderboard/global/events")
async def focus_global_leaderboard_events(
    interval_seconds: int = Query(15, ge=2, le=60),
    user_id: str = Depends(_verify_token),
    authorization: Optional[str] = Header(None),
):
    async def event_stream():
        while True:
            db = get_db()
            try:
                payload = _focus_global_ranking(db, user_id)
            finally:
                db.close()
            try:
                if _verify_token(authorization) != user_id:
                    return
            except HTTPException:
                return
            yield (
                "event: ranking\n"
                f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"
            )
            await asyncio.sleep(interval_seconds)

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


@app.post("/api/focus-rooms/{room_id:path}/invites", include_in_schema=False)
@app.post("/api/focus-rooms/{room_id}/invites")
def create_focus_room_invite(
    room_id: str,
    req: FocusRoomInviteCreate,
    user_id: str = Depends(_verify_token),
):
    clean_room_id = _clean_focus_room_id(room_id)
    expires_at = _parse_server_time(req.expires_at)
    expires_at_text = _format_utc(expires_at) if expires_at is not None else None
    max_uses = _clean_focus_invite_max_uses(req.max_uses)
    room = _focus_room_payload(
        clean_room_id,
        _clean_focus_room_name(req.room_name),
        req.description,
        req.weekly_target_seconds,
        req.accent_color,
    )
    db = get_db()
    try:
        invite_id = secrets.token_hex(12)
        code = secrets.token_urlsafe(8).replace("-", "").replace("_", "")[:10]
        db.execute(
            """
            INSERT INTO focus_room_invites(
                id, room_id, code, room_name, description,
                weekly_target_seconds, accent_color, created_by, expires_at, max_uses
            ) VALUES(?,?,?,?,?,?,?,?,?,?)
            """,
            (
                invite_id,
                room["id"],
                code,
                room["name"],
                room["description"],
                room["weekly_target_seconds"],
                room["accent_color"],
                user_id,
                expires_at_text,
                max_uses,
            ),
        )
        db.commit()
        row = db.execute(
            "SELECT * FROM focus_room_invites WHERE id=?",
            (invite_id,),
        ).fetchone()
        return _focus_room_invite_payload(row)
    finally:
        db.close()


@app.get("/api/focus-rooms/{room_id:path}/invites", include_in_schema=False)
@app.get("/api/focus-rooms/{room_id}/invites")
def list_focus_room_invites(
    room_id: str,
    user_id: str = Depends(_verify_token),
):
    clean_room_id = _clean_focus_room_id(room_id)
    db = get_db()
    try:
        rows = db.execute(
            """
            SELECT *
            FROM focus_room_invites
            WHERE room_id=? AND created_by=?
            ORDER BY revoked ASC, created_at DESC, id DESC
            """,
            (clean_room_id, user_id),
        ).fetchall()
        return {"items": [_focus_room_invite_payload(row) for row in rows]}
    finally:
        db.close()


@app.delete("/api/focus-room-invites/{invite_id:path}", include_in_schema=False)
@app.delete("/api/focus-room-invites/{invite_id}")
def revoke_focus_room_invite(
    invite_id: str,
    user_id: str = Depends(_verify_token),
):
    clean_invite_id = (invite_id or "").strip()
    if not clean_invite_id:
        raise HTTPException(status_code=400, detail="Invalid focus room invite id")
    db = get_db()
    try:
        row = db.execute(
            "SELECT id FROM focus_room_invites WHERE id=? AND created_by=?",
            (clean_invite_id, user_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Focus room invite not found")
        db.execute(
            "UPDATE focus_room_invites SET revoked=1 WHERE id=?",
            (clean_invite_id,),
        )
        db.commit()
        return {"status": "ok", "id": clean_invite_id}
    finally:
        db.close()


@app.post("/api/focus-room-invites/{code:path}/accept", include_in_schema=False)
@app.post("/api/focus-room-invites/{code}/accept")
def accept_focus_room_invite(
    code: str,
    req: FocusRoomInviteAccept,
    user_id: str = Depends(_verify_token),
):
    clean_code = (code or "").strip()
    db = get_db()
    try:
        row = db.execute(
            """
            SELECT id, room_id, room_name, description, weekly_target_seconds,
                   accent_color, expires_at, max_uses, used_count, revoked
            FROM focus_room_invites
            WHERE code=?
            """,
            (clean_code,),
        ).fetchone()
        if row is None or row["revoked"]:
            raise HTTPException(status_code=404, detail="Focus room invite not found")
        expires_at = _parse_server_time(row["expires_at"])
        if expires_at is not None and expires_at < _utc_now():
            raise HTTPException(status_code=400, detail="Focus room invite expired")
        existing_presence = db.execute(
            "SELECT 1 FROM focus_room_presence WHERE room_id=? AND user_id=?",
            (row["room_id"], user_id),
        ).fetchone()
        first_join = existing_presence is None
        max_uses = int(row["max_uses"] or 0)
        used_count = int(row["used_count"] or 0)
        if first_join and max_uses > 0 and used_count >= max_uses:
            raise HTTPException(
                status_code=400,
                detail="Focus room invite usage limit reached",
            )
        now_text = _utc_now_text()
        display_name = _clean_focus_display_name(
            req.display_name,
            _get_username(db, user_id),
        )
        if first_join:
            if max_uses > 0:
                cursor = db.execute(
                    """
                    UPDATE focus_room_invites
                    SET used_count=used_count+1, last_used_at=?
                    WHERE id=? AND used_count < max_uses
                    """,
                    (now_text, row["id"]),
                )
                if cursor.rowcount != 1:
                    raise HTTPException(
                        status_code=400,
                        detail="Focus room invite usage limit reached",
                    )
            else:
                db.execute(
                    """
                    UPDATE focus_room_invites
                    SET used_count=used_count+1, last_used_at=?
                    WHERE id=?
                    """,
                    (now_text, row["id"]),
                )
        db.execute(
            """
            INSERT INTO focus_room_presence(
                room_id, user_id, display_name, raw_weekly_seconds,
                weekly_seconds, session_count, active, started_at,
                last_seen_at, updated_at
            )
            VALUES(?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(room_id, user_id) DO UPDATE SET
                display_name=excluded.display_name,
                active=1,
                started_at=excluded.started_at,
                last_seen_at=excluded.last_seen_at,
                updated_at=excluded.updated_at
            """,
            (
                row["room_id"],
                user_id,
                display_name,
                0,
                0,
                0,
                1,
                now_text,
                now_text,
                now_text,
            ),
        )
        db.commit()
        room = _focus_room_payload(
            row["room_id"],
            row["room_name"],
            row["description"],
            row["weekly_target_seconds"],
            row["accent_color"],
        )
        return {
            "code": clean_code,
            "room": room,
            "ranking": _focus_room_ranking(db, row["room_id"], user_id),
        }
    finally:
        db.close()


@app.post("/api/focus-rooms/{room_id:path}/heartbeat", include_in_schema=False)
@app.post("/api/focus-rooms/{room_id}/heartbeat")
def focus_room_heartbeat(
    room_id: str,
    req: FocusRoomHeartbeatRequest,
    user_id: str = Depends(_verify_token),
):
    clean_room_id = _clean_focus_room_id(room_id)
    raw_weekly_seconds = _clean_focus_metric(
        req.weekly_seconds,
        FOCUS_ROOM_MAX_WEEKLY_SECONDS * 4,
    )
    weekly_seconds = min(raw_weekly_seconds, FOCUS_ROOM_MAX_WEEKLY_SECONDS)
    session_count = _clean_focus_metric(req.session_count, FOCUS_ROOM_MAX_SESSION_COUNT)
    now_text = _utc_now_text()
    started_at = _parse_server_time(req.started_at)
    started_at_text = _format_utc(started_at) if started_at is not None else now_text

    db = get_db()
    try:
        display_name = _clean_focus_display_name(
            req.display_name,
            _get_username(db, user_id),
        )
        existing = db.execute(
            """
            SELECT session_count, last_seen_at, risk_flags
            FROM focus_room_presence
            WHERE room_id=? AND user_id=?
            """,
            (clean_room_id, user_id),
        ).fetchone()
        risk_flags = (
            _parse_focus_risk_flags(existing["risk_flags"])
            if existing is not None
            else []
        )
        if raw_weekly_seconds > FOCUS_ROOM_MAX_WEEKLY_SECONDS:
            risk_flags.append("weekly_seconds_capped")
        if int(req.session_count or 0) > FOCUS_ROOM_MAX_SESSION_COUNT:
            risk_flags.append("session_count_capped")
        if existing is not None:
            previous_seen = _parse_server_time(existing["last_seen_at"])
            previous_session_count = int(existing["session_count"] or 0)
            if previous_seen is not None:
                seconds_since_seen = (_utc_now() - previous_seen).total_seconds()
                if seconds_since_seen < FOCUS_ROOM_HEARTBEAT_THROTTLE_SECONDS:
                    risk_flags.append("heartbeat_throttled")
                    now_text = existing["last_seen_at"] or now_text
                if (
                    seconds_since_seen < FOCUS_ROOM_SESSION_JUMP_WINDOW_SECONDS
                    and session_count - previous_session_count
                    > FOCUS_ROOM_MAX_SESSION_COUNT_JUMP
                ):
                    session_count = min(
                        previous_session_count + FOCUS_ROOM_MAX_SESSION_COUNT_JUMP,
                        FOCUS_ROOM_MAX_SESSION_COUNT,
                    )
                    risk_flags.append("session_count_jump_capped")
        risk_flags_text, risk_summary = _focus_risk_payload(risk_flags)
        db.execute(
            """
            INSERT INTO focus_room_presence(
                room_id, user_id, display_name, raw_weekly_seconds,
                weekly_seconds, session_count, active, started_at,
                last_seen_at, risk_flags, risk_summary, updated_at
            )
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(room_id, user_id) DO UPDATE SET
                display_name=excluded.display_name,
                raw_weekly_seconds=excluded.raw_weekly_seconds,
                weekly_seconds=excluded.weekly_seconds,
                session_count=excluded.session_count,
                active=excluded.active,
                started_at=excluded.started_at,
                last_seen_at=excluded.last_seen_at,
                risk_flags=excluded.risk_flags,
                risk_summary=excluded.risk_summary,
                updated_at=excluded.updated_at
            """,
            (
                clean_room_id,
                user_id,
                display_name,
                raw_weekly_seconds,
                weekly_seconds,
                session_count,
                1 if req.active else 0,
                started_at_text,
                now_text,
                risk_flags_text,
                risk_summary,
                now_text,
            ),
        )
        db.commit()
        return _focus_room_ranking(db, clean_room_id, user_id)
    finally:
        db.close()


@app.get("/api/focus-rooms/{room_id:path}/ranking", include_in_schema=False)
@app.get("/api/focus-rooms/{room_id}/ranking")
def focus_room_ranking(room_id: str, user_id: str = Depends(_verify_token)):
    clean_room_id = _clean_focus_room_id(room_id)
    db = get_db()
    try:
        return _focus_room_ranking(db, clean_room_id, user_id)
    finally:
        db.close()


@app.get("/api/focus-rooms/{room_id:path}/events", include_in_schema=False)
@app.get("/api/focus-rooms/{room_id}/events")
async def focus_room_events(
    room_id: str,
    interval_seconds: int = Query(15, ge=2, le=60),
    user_id: str = Depends(_verify_token),
    authorization: Optional[str] = Header(None),
):
    clean_room_id = _clean_focus_room_id(room_id)

    async def event_stream():
        while True:
            db = get_db()
            try:
                payload = _focus_room_ranking(db, clean_room_id, user_id)
            finally:
                db.close()
            try:
                if _verify_token(authorization) != user_id:
                    return
            except HTTPException:
                return
            yield (
                "event: ranking\n"
                f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"
            )
            await asyncio.sleep(interval_seconds)

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


@app.websocket("/ws/focus-rooms/{room_id:path}/events")
@app.websocket("/ws/focus-rooms/{room_id}/events")
async def focus_room_events_ws(websocket: WebSocket, room_id: str):
    clean_room_id = _clean_focus_room_id(room_id)
    try:
        user_id = _verify_focus_websocket(websocket)
    except HTTPException:
        await websocket.close(code=1008)
        return
    await websocket.accept()
    interval_seconds = 15
    try:
        raw_interval = websocket.query_params.get("interval_seconds")
        if raw_interval is not None:
            interval_seconds = min(60, max(2, int(raw_interval)))
    except ValueError:
        interval_seconds = 15

    async def send_ranking():
        _verify_focus_websocket(websocket)
        db = get_db()
        try:
            payload = _focus_room_ranking(db, clean_room_id, user_id)
        finally:
            db.close()
        await websocket.send_json({"event": "ranking", "data": payload})

    try:
        await send_ranking()
        while True:
            try:
                message = await asyncio.wait_for(
                    websocket.receive_json(),
                    timeout=interval_seconds,
                )
                _verify_focus_websocket(websocket)
                event = message.get("event") if isinstance(message, dict) else None
                if event in ("ping", "ranking"):
                    await send_ranking()
            except asyncio.TimeoutError:
                await send_ranking()
    except HTTPException:
        await websocket.close(code=1008)
    except WebSocketDisconnect:
        return


@app.websocket("/ws/focus-leaderboard/global/events")
async def focus_global_leaderboard_events_ws(websocket: WebSocket):
    try:
        user_id = _verify_focus_websocket(websocket)
    except HTTPException:
        await websocket.close(code=1008)
        return
    await websocket.accept()
    interval_seconds = 15
    try:
        raw_interval = websocket.query_params.get("interval_seconds")
        if raw_interval is not None:
            interval_seconds = min(60, max(2, int(raw_interval)))
    except ValueError:
        interval_seconds = 15

    async def send_ranking():
        _verify_focus_websocket(websocket)
        db = get_db()
        try:
            payload = _focus_global_ranking(db, user_id)
        finally:
            db.close()
        await websocket.send_json({"event": "ranking", "data": payload})

    try:
        await send_ranking()
        while True:
            try:
                message = await asyncio.wait_for(
                    websocket.receive_json(),
                    timeout=interval_seconds,
                )
                _verify_focus_websocket(websocket)
                event = message.get("event") if isinstance(message, dict) else None
                if event in ("ping", "ranking"):
                    await send_ranking()
            except asyncio.TimeoutError:
                await send_ranking()
    except HTTPException:
        await websocket.close(code=1008)
    except WebSocketDisconnect:
        return


@app.post("/api/focus-rooms/{room_id:path}/leave", include_in_schema=False)
@app.post("/api/focus-rooms/{room_id}/leave")
def leave_focus_room(room_id: str, user_id: str = Depends(_verify_token)):
    clean_room_id = _clean_focus_room_id(room_id)
    now_text = _utc_now_text()
    db = get_db()
    try:
        db.execute(
            """
            UPDATE focus_room_presence
            SET active=0, last_seen_at=?, updated_at=?
            WHERE room_id=? AND user_id=?
            """,
            (now_text, now_text, clean_room_id, user_id),
        )
        db.commit()
        return _focus_room_ranking(db, clean_room_id, user_id)
    finally:
        db.close()


# ---- Sync ----


TOMBSTONE_COLLECTIONS = {
    "todos",
    "habits",
    "pomodoro_sessions",
    "focus_penalties",
    "notes",
    "countdowns",
    "anniversaries",
    "diaries",
    "goals",
    "calendar_events",
    "courses",
    "time_entries",
    "location_reminders",
    "quick_capture_templates",
    "list_groups",
}


def _timestamp_gte(left: str, right: str) -> bool:
    left_dt = _parse_server_time(left)
    right_dt = _parse_server_time(right)
    if left_dt is not None and right_dt is not None:
        return left_dt >= right_dt
    return str(left or "") >= str(right or "")


def _timestamp_gt(left: str, right: str) -> bool:
    left_dt = _parse_server_time(left)
    right_dt = _parse_server_time(right)
    if left_dt is not None and right_dt is not None:
        return left_dt > right_dt
    return str(left or "") > str(right or "")


def _item_updated_at(item: dict) -> str:
    for key in ("updatedAt", "updated_at", "modifiedAt", "endTime", "createdAt"):
        value = item.get(key)
        if value:
            return str(value)
    return ""


SYNC_PULL_COLLECTIONS = {
    "todos",
    "habits",
    "pomodoro_sessions",
    "focus_penalties",
    "pomodoro_config",
    "user_profile",
    "notes",
    "countdowns",
    "anniversaries",
    "diaries",
    "goals",
    "calendar_events",
    "courses",
    "time_entries",
    "location_reminders",
    "course_settings",
    "achievement_states",
    "virtual_rewards",
    "focus_rooms",
    "theme_shop_state",
    "preferences",
    "quick_capture_templates",
    "list_groups",
    "deleted_items",
    "workspace_payloads",
}

SYNC_OBJECT_COLLECTIONS = {
    "pomodoro_config",
    "user_profile",
    "course_settings",
    "achievement_states",
    "virtual_rewards",
    "focus_rooms",
    "theme_shop_state",
    "preferences",
    "quick_capture_templates",
}

SYNC_STATE_OBJECT_COLLECTIONS = {
    "achievement_states",
    "virtual_rewards",
}


def _canonical_json(value) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _payload_hash(value) -> str:
    return hashlib.sha256(_canonical_json(value).encode("utf-8")).hexdigest()


def _sync_collection_hashes(payload: dict) -> dict[str, str]:
    return {key: _payload_hash(payload.get(key)) for key in SYNC_PULL_COLLECTIONS}


def _normalize_deleted_items(raw) -> dict:
    if not isinstance(raw, dict):
        return {}
    result: dict[str, dict[str, str]] = {}
    for collection, values in raw.items():
        collection_key = str(collection)
        if collection_key not in TOMBSTONE_COLLECTIONS:
            continue
        normalized: dict[str, str] = {}
        if isinstance(values, dict):
            iterable = values.items()
        elif isinstance(values, list):
            entries = []
            for item in values:
                if isinstance(item, dict):
                    entries.append(
                        (
                            item.get("id") or item.get("item_id"),
                            item.get("deletedAt") or item.get("deleted_at"),
                        )
                    )
                else:
                    entries.append((item, ""))
            iterable = entries
        else:
            continue
        for item_id, deleted_at in iterable:
            item_id_text = str(item_id or "").strip()
            if not item_id_text:
                continue
            deleted_at_text = str(deleted_at or "").strip() or _utc_now_text()
            current = normalized.get(item_id_text)
            if current is None or _timestamp_gte(deleted_at_text, current):
                normalized[item_id_text] = deleted_at_text
        if normalized:
            result[collection_key] = normalized
    return result


def _merge_deleted_items(server, client) -> dict:
    merged = _normalize_deleted_items(server)
    for collection, values in _normalize_deleted_items(client).items():
        bucket = merged.setdefault(collection, {})
        for item_id, deleted_at in values.items():
            current = bucket.get(item_id)
            if current is None or _timestamp_gte(deleted_at, current):
                bucket[item_id] = deleted_at
    return merged


def _merge_by_timestamp(
    server: list,
    client: list,
    *,
    collection: Optional[str] = None,
    deleted_items: Optional[dict] = None,
) -> list:
    merged = {
        str(item.get("id")): item
        for item in server
        if isinstance(item, dict) and item.get("id") is not None
    }
    for item in client:
        if not isinstance(item, dict):
            continue
        item_id = item.get("id")
        if item_id is None:
            continue
        item_id = str(item_id)
        if item_id not in merged:
            merged[item_id] = item
        else:
            server_ts = _item_updated_at(merged[item_id])
            client_ts = _item_updated_at(item)
            if client_ts and (not server_ts or _timestamp_gt(client_ts, server_ts)):
                merged[item_id] = item
    if collection and deleted_items:
        tombstones = deleted_items.get(collection, {})
        if isinstance(tombstones, dict):
            for item_id, deleted_at in tombstones.items():
                item = merged.get(item_id)
                if not isinstance(item, dict):
                    continue
                updated_at = _item_updated_at(item)
                if not updated_at or _timestamp_gte(str(deleted_at), updated_at):
                    merged.pop(item_id, None)
    return list(merged.values())


def _diary_date_key(item: dict) -> str:
    raw = item.get("date") or item.get("day")
    text = str(raw or "").strip()
    parsed = _parse_server_time(text)
    if parsed is not None:
        return parsed.date().isoformat()
    if len(text) >= 10 and text[4:5] == "-" and text[7:8] == "-":
        return text[:10]
    return text


def _merge_diaries_by_date(
    server: list,
    client: list,
    *,
    deleted_items: Optional[dict] = None,
) -> list:
    by_id = _merge_by_timestamp(
        server,
        client,
        collection="diaries",
        deleted_items=deleted_items,
    )
    merged_by_date: dict[str, dict] = {}
    for item in by_id:
        if not isinstance(item, dict):
            continue
        date_key = _diary_date_key(item) or str(item.get("id") or "")
        if not date_key:
            continue
        current = merged_by_date.get(date_key)
        if current is None:
            merged_by_date[date_key] = item
            continue
        current_ts = _item_updated_at(current)
        item_ts = _item_updated_at(item)
        if item_ts and (not current_ts or _timestamp_gt(item_ts, current_ts)):
            merged_by_date[date_key] = item
    return list(merged_by_date.values())


def _apply_tombstones_to_list(
    items: list,
    collection: str,
    deleted_items: Optional[dict],
) -> list:
    if not deleted_items:
        return items
    tombstones = deleted_items.get(collection, {})
    if not isinstance(tombstones, dict):
        return items
    result = []
    for item in items:
        if not isinstance(item, dict):
            result.append(item)
            continue
        item_id = str(item.get("id") or "")
        deleted_at = tombstones.get(item_id)
        if not deleted_at:
            result.append(item)
            continue
        updated_at = _item_updated_at(item)
        if updated_at and _timestamp_gt(updated_at, str(deleted_at)):
            result.append(item)
    return result


def _habit_completion_map(item: dict) -> dict[str, int]:
    raw = item.get("completions")
    if not isinstance(raw, dict):
        return {}
    result: dict[str, int] = {}
    for key, value in raw.items():
        date_key = str(key).strip()
        if not date_key:
            continue
        try:
            count = int(value)
        except Exception:
            continue
        if count > 0:
            result[date_key] = count
    return result


def _habit_completion_updated_at_map(item: dict) -> dict[str, str]:
    raw = item.get("completionUpdatedAt") or item.get("completion_updated_at")
    if not isinstance(raw, dict):
        return {}
    result: dict[str, str] = {}
    for key, value in raw.items():
        date_key = str(key).strip()
        stamp = str(value or "").strip()
        if date_key and stamp:
            result[date_key] = stamp
    return result


def _merge_habit_item(server_item: dict, client_item: dict) -> dict:
    server_ts = _item_updated_at(server_item)
    client_ts = _item_updated_at(client_item)
    client_is_newer = client_ts and (
        not server_ts or _timestamp_gt(client_ts, server_ts)
    )
    result = dict(client_item if client_is_newer else server_item)
    server_completions = _habit_completion_map(server_item)
    client_completions = _habit_completion_map(client_item)
    server_completion_updated_at = _habit_completion_updated_at_map(server_item)
    client_completion_updated_at = _habit_completion_updated_at_map(client_item)

    completions: dict[str, int] = {}
    completion_updated_at: dict[str, str] = {}
    date_keys = (
        set(server_completions.keys())
        | set(client_completions.keys())
        | set(server_completion_updated_at.keys())
        | set(client_completion_updated_at.keys())
    )
    for date_key in sorted(date_keys):
        server_completion_ts = server_completion_updated_at.get(date_key)
        client_completion_ts = client_completion_updated_at.get(date_key)
        if server_completion_ts or client_completion_ts:
            client_wins = bool(client_completion_ts) and (
                not server_completion_ts
                or _timestamp_gt(client_completion_ts, server_completion_ts)
            )
            count = (
                client_completions.get(date_key, 0)
                if client_wins
                else server_completions.get(date_key, 0)
            )
            stamp = client_completion_ts if client_wins else server_completion_ts
            if stamp:
                completion_updated_at[date_key] = stamp
        else:
            count = max(
                server_completions.get(date_key, 0),
                client_completions.get(date_key, 0),
            )
        if count > 0:
            completions[date_key] = count
    result["completions"] = completions
    result["completionUpdatedAt"] = completion_updated_at
    result["currentStreak"] = int(result.get("currentStreak") or 0)
    result["bestStreak"] = max(
        int(server_item.get("bestStreak") or 0),
        int(client_item.get("bestStreak") or 0),
    )
    result["updatedAt"] = client_ts if client_is_newer else server_ts or client_ts
    return result


def _merge_habits_by_timestamp(
    server: list,
    client: list,
    *,
    deleted_items: Optional[dict] = None,
) -> list:
    merged = {
        str(item.get("id")): item
        for item in server
        if isinstance(item, dict) and item.get("id") is not None
    }
    for item in client:
        if not isinstance(item, dict):
            continue
        item_id = item.get("id")
        if item_id is None:
            continue
        item_id = str(item_id)
        prior = merged.get(item_id)
        if not isinstance(prior, dict):
            merged[item_id] = item
        elif _payload_hash(prior) != _payload_hash(item):
            merged[item_id] = _merge_habit_item(prior, item)
    if deleted_items:
        tombstones = deleted_items.get("habits", {})
        if isinstance(tombstones, dict):
            for item_id, deleted_at in tombstones.items():
                item = merged.get(item_id)
                if not isinstance(item, dict):
                    continue
                updated_at = _item_updated_at(item)
                if not updated_at or _timestamp_gte(str(deleted_at), updated_at):
                    merged.pop(item_id, None)
    return list(merged.values())


def _prune_deleted_items(deleted_items: dict, collections: dict[str, list]) -> dict:
    pruned = _normalize_deleted_items(deleted_items)
    for collection, items in collections.items():
        tombstones = pruned.get(collection)
        if not tombstones:
            continue
        if isinstance(items, dict):
            items = items.get("items", [])
        if not isinstance(items, list):
            items = []
        by_id = {
            str(item.get("id")): item
            for item in items
            if isinstance(item, dict) and item.get("id") is not None
        }
        for item_id, deleted_at in list(tombstones.items()):
            item = by_id.get(item_id)
            if isinstance(item, dict) and _timestamp_gte(
                _item_updated_at(item), deleted_at
            ):
                tombstones.pop(item_id, None)
        if not tombstones:
            pruned.pop(collection, None)
    return pruned


def _merge_dict(server: dict, client: dict) -> dict:
    server_ts = _item_updated_at(server) if isinstance(server, dict) else None
    client_ts = _item_updated_at(client) if isinstance(client, dict) else None
    if client_ts and (not server_ts or _timestamp_gt(client_ts, server_ts)):
        return client
    return server or client


def _merge_theme_shop_state(server: dict, client: dict) -> dict:
    if not isinstance(server, dict):
        server = {}
    if not isinstance(client, dict):
        client = {}
    if not server:
        return _normalize_theme_shop_state(client)
    if not client:
        return _normalize_theme_shop_state(server)

    server_state = _normalize_theme_shop_state(server)
    client_state = _normalize_theme_shop_state(client)
    server_ts = _item_updated_at(server_state)
    client_ts = _item_updated_at(client_state)
    client_is_newer = client_ts and (
        not server_ts or _timestamp_gt(client_ts, server_ts)
    )
    result = dict(client_state if client_is_newer else server_state)

    for item_type, default_id in THEME_SHOP_DEFAULTS.items():
        active_key, unlocked_key = THEME_SHOP_FIELDS[item_type]
        unlocked = []
        for value in [
            default_id,
            *_theme_shop_list(server_state.get(unlocked_key)),
            *_theme_shop_list(client_state.get(unlocked_key)),
        ]:
            if value and value not in unlocked:
                unlocked.append(value)
        result[unlocked_key] = unlocked
        active = str(
            (client_state if client_is_newer else server_state).get(active_key) or ""
        ).strip()
        result[active_key] = active if active in unlocked else default_id

    result["switchCount"] = max(
        int(server_state.get("switchCount") or 0),
        int(client_state.get("switchCount") or 0),
    )
    latest = _latest_timestamp(server_ts, client_ts)
    if latest:
        result["updatedAt"] = latest
    return _normalize_theme_shop_state(result)


def _latest_timestamp(*values: str) -> str:
    latest = ""
    for value in values:
        text = str(value or "")
        if text and (not latest or _timestamp_gt(text, latest)):
            latest = text
    return latest


def _merge_preferences(server: dict, client: dict) -> dict:
    if not isinstance(server, dict):
        server = {}
    if not isinstance(client, dict):
        client = {}
    if not server:
        return client
    if not client:
        return server
    server_ts = _item_updated_at(server)
    client_ts = _item_updated_at(client)
    client_is_newer = client_ts and (
        not server_ts or _timestamp_gt(client_ts, server_ts)
    )
    result = dict(client if client_is_newer else server)
    result.pop("changedKeys", None)
    result.pop("changed_keys", None)
    server_values = (
        server.get("values") if isinstance(server.get("values"), dict) else {}
    )
    client_values = (
        client.get("values") if isinstance(client.get("values"), dict) else {}
    )
    values = dict(server_values)
    raw_changed_keys = client.get("changedKeys") or client.get("changed_keys")
    changed_keys = {
        str(key).strip()
        for key in raw_changed_keys
        if str(key).strip()
    } if isinstance(raw_changed_keys, list) else set()
    if changed_keys:
        for key_text in changed_keys:
            if key_text in client_values:
                values[key_text] = client_values[key_text]
            else:
                values.pop(key_text, None)
    else:
        for key, value in client_values.items():
            key_text = str(key)
            if key_text not in values or client_is_newer:
                values[key_text] = value
    result["values"] = values
    latest = _latest_timestamp(server_ts, client_ts)
    if latest:
        result["updatedAt"] = latest
    return result


def _merge_quick_capture_templates(
    server: dict,
    client: dict,
    *,
    deleted_items: Optional[dict] = None,
) -> dict:
    if not isinstance(server, dict):
        server = {}
    if not isinstance(client, dict):
        client = {}
    server_ts = _item_updated_at(server)
    client_ts = _item_updated_at(client)
    client_is_newer = client_ts and (
        not server_ts or _timestamp_gt(client_ts, server_ts)
    )
    result = dict(client if client_is_newer else server)

    merged: dict[str, dict] = {}
    for source in (server, client):
        raw_items = source.get("items") if isinstance(source, dict) else []
        if not isinstance(raw_items, list):
            continue
        for item in raw_items:
            if not isinstance(item, dict) or item.get("id") is None:
                continue
            item_id = str(item.get("id"))
            current = merged.get(item_id)
            if current is None:
                merged[item_id] = item
                continue
            current_ts = _item_updated_at(current)
            item_ts = _item_updated_at(item)
            if item_ts and (not current_ts or _timestamp_gt(item_ts, current_ts)):
                merged[item_id] = item

    tombstones = {}
    if isinstance(deleted_items, dict):
        raw_tombstones = deleted_items.get("quick_capture_templates", {})
        if isinstance(raw_tombstones, dict):
            tombstones = raw_tombstones
    for item_id, deleted_at in tombstones.items():
        item = merged.get(str(item_id))
        if not isinstance(item, dict):
            continue
        updated_at = _item_updated_at(item)
        if not updated_at or _timestamp_gte(str(deleted_at), updated_at):
            merged.pop(str(item_id), None)

    items = list(merged.values())
    items.sort(key=lambda item: str(item.get("createdAt") or item.get("id") or ""))
    result["items"] = items
    latest = _latest_timestamp(
        server_ts,
        client_ts,
        *(_item_updated_at(item) for item in items if isinstance(item, dict)),
    )
    if latest:
        result["updatedAt"] = latest
    return result


def _merge_state_dict(server: dict, client: dict) -> dict:
    result = dict(server or {})
    for key, value in (client or {}).items():
        current = result.get(key)
        if current is None or str(value) > str(current):
            result[key] = value
    return result


def _is_legacy_anniversary_countdown(item: dict) -> bool:
    value = item.get("type")
    if isinstance(value, (int, float)):
        return int(value) == 0
    if isinstance(value, str):
        return value.strip().lower() in {"0", "normal", "countdown"}
    return False


def _countdown_from_legacy_anniversary(item: dict) -> dict:
    result = dict(item)
    target_date = (
        result.get("targetDate")
        or result.get("target_date")
        or result.get("date")
        or result.get("originDate")
        or result.get("origin_date")
    )
    if target_date:
        result["targetDate"] = target_date
    result.setdefault("category", "默认")
    return result


def _split_legacy_anniversary_countdowns(items: list) -> tuple[list, list]:
    countdowns: list = []
    anniversaries: list = []
    for item in items:
        if isinstance(item, dict) and _is_legacy_anniversary_countdown(item):
            countdowns.append(_countdown_from_legacy_anniversary(item))
        else:
            anniversaries.append(item)
    return countdowns, anniversaries


def _apply_item_delta_to_payload(payload: dict, req: SyncItemDeltaRequest) -> dict:
    next_payload = dict(payload)
    deleted_items = _merge_deleted_items(
        next_payload.get("deleted_items", {}), req.deleted_items
    )
    for collection, changes in (req.items or {}).items():
        collection_key = str(collection)
        if collection_key not in TOMBSTONE_COLLECTIONS:
            continue
        if collection_key in SYNC_OBJECT_COLLECTIONS:
            continue
        if not isinstance(changes, list):
            continue
        current = next_payload.get(collection_key)
        current_list = current if isinstance(current, list) else []
        if collection_key == "habits":
            next_payload[collection_key] = _merge_habits_by_timestamp(
                current_list,
                changes,
                deleted_items=deleted_items,
            )
        elif collection_key == "diaries":
            next_payload[collection_key] = _merge_diaries_by_date(
                current_list,
                changes,
                deleted_items=deleted_items,
            )
        else:
            next_payload[collection_key] = _merge_by_timestamp(
                current_list,
                changes,
                collection=collection_key,
                deleted_items=deleted_items,
            )
    for key, value in (req.objects or {}).items():
        key_text = str(key)
        if key_text not in SYNC_OBJECT_COLLECTIONS:
            continue
        current = next_payload.get(key_text)
        if key_text == "virtual_rewards":
            next_payload[key_text] = _merge_virtual_rewards(
                current if isinstance(current, dict) else {},
                value if isinstance(value, dict) else {},
            )
        elif key_text in SYNC_STATE_OBJECT_COLLECTIONS:
            next_payload[key_text] = _merge_state_dict(
                current if isinstance(current, dict) else {},
                value if isinstance(value, dict) else {},
            )
        elif key_text == "preferences":
            next_payload[key_text] = _merge_preferences(
                current if isinstance(current, dict) else {},
                value if isinstance(value, dict) else {},
            )
        elif key_text == "quick_capture_templates":
            next_payload[key_text] = _merge_quick_capture_templates(
                current if isinstance(current, dict) else {},
                value if isinstance(value, dict) else {},
                deleted_items=deleted_items,
            )
        elif key_text == "theme_shop_state":
            next_payload[key_text] = _merge_theme_shop_state(
                current if isinstance(current, dict) else {},
                value if isinstance(value, dict) else {},
            )
        else:
            next_payload[key_text] = _merge_dict(
                current if isinstance(current, dict) else {},
                value if isinstance(value, dict) else {},
            )
    if "quick_capture_templates" in deleted_items:
        current = next_payload.get("quick_capture_templates")
        next_payload["quick_capture_templates"] = _merge_quick_capture_templates(
            current if isinstance(current, dict) else {},
            {},
            deleted_items=deleted_items,
        )
    for collection, tombstones in deleted_items.items():
        collection_key = str(collection)
        if collection_key == "quick_capture_templates":
            continue
        if collection_key not in TOMBSTONE_COLLECTIONS:
            continue
        if collection_key in SYNC_OBJECT_COLLECTIONS:
            continue
        if collection_key in (req.items or {}):
            continue
        if not isinstance(tombstones, dict) or not tombstones:
            continue
        current = next_payload.get(collection_key)
        current_list = current if isinstance(current, list) else []
        if collection_key == "habits":
            next_payload[collection_key] = _merge_habits_by_timestamp(
                current_list,
                [],
                deleted_items=deleted_items,
            )
        elif collection_key == "diaries":
            next_payload[collection_key] = _merge_diaries_by_date(
                current_list,
                [],
                deleted_items=deleted_items,
            )
        else:
            next_payload[collection_key] = _apply_tombstones_to_list(
                current_list,
                collection_key,
                deleted_items,
            )
    next_payload["deleted_items"] = _prune_deleted_items(
        deleted_items,
        {
            collection: next_payload.get(collection, [])
            for collection in TOMBSTONE_COLLECTIONS
        },
    )
    return next_payload


def _require_workspace_member(db, workspace_id: str, user_id: str) -> sqlite3.Row:
    row = db.execute(
        """
        SELECT wm.role, w.name, w.owner_user_id, w.is_private
        FROM workspace_members wm
        JOIN workspaces w ON w.id = wm.workspace_id
        WHERE wm.workspace_id=? AND wm.user_id=?
        """,
        (workspace_id, user_id),
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=403, detail="No workspace access")
    return row


def _require_workspace_editor(db, workspace_id: str, user_id: str) -> sqlite3.Row:
    row = _require_workspace_member(db, workspace_id, user_id)
    if row["role"] not in {"owner", "editor"}:
        raise HTTPException(status_code=403, detail="Editor role required")
    return row


def _workspace_to_dict(row: sqlite3.Row, members: list[sqlite3.Row]) -> dict:
    return {
        "id": row["id"],
        "name": row["name"],
        "owner_user_id": row["owner_user_id"],
        "is_private": bool(row["is_private"]),
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
        "members": [
            {
                "workspace_id": m["workspace_id"],
                "user_id": m["user_id"],
                "username": m["username"],
                "role": m["role"],
                "joined_at": m["joined_at"],
            }
            for m in members
        ],
    }


def _workspace_comment_to_dict(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "workspace_id": row["workspace_id"],
        "target_id": row["target_id"] or "",
        "author_user_id": row["author_user_id"],
        "author_name": row["author_name"],
        "body": row["body"],
        "created_at": row["created_at"],
    }


def _workspace_mention_to_dict(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "workspace_id": row["workspace_id"],
        "workspace_name": row["workspace_name"],
        "comment_id": row["comment_id"],
        "target_id": row["target_id"] or "",
        "author_user_id": row["author_user_id"],
        "author_name": row["author_name"],
        "body": row["body"],
        "read_at": row["read_at"],
        "created_at": row["created_at"],
    }


def _workspace_activity_to_dict(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "workspace_id": row["workspace_id"],
        "actor_user_id": row["actor_user_id"],
        "actor_name": row["actor_name"],
        "action": row["action"],
        "detail": row["detail"] or "",
        "created_at": row["created_at"],
    }


def _extract_workspace_mentions(
    db, workspace_id: str, body: str, author_user_id: str
) -> list[str]:
    tokens = {
        match.group(1).strip().lower()
        for match in re.finditer(
            r"(?<![\w@])@([\w.\-+@/\u4e00-\u9fff]{1,96})",
            body,
        )
    }
    if not tokens:
        return []
    rows = db.execute(
        """
        SELECT wm.user_id, u.username, u.email, u.display_name
        FROM workspace_members wm
        JOIN users u ON u.id = wm.user_id
        WHERE wm.workspace_id=?
        """,
        (workspace_id,),
    ).fetchall()
    matched: list[str] = []
    seen: set[str] = set()
    for row in rows:
        if row["user_id"] == author_user_id:
            continue
        aliases = {
            row["user_id"].lower(),
            (row["username"] or "").lower(),
            (row["email"] or "").lower(),
            (row["display_name"] or "").lower(),
        }
        email = (row["email"] or "").strip().lower()
        if "@" in email:
            aliases.add(email.split("@", 1)[0])
        aliases = {alias for alias in aliases if alias}
        if tokens.intersection(aliases) and row["user_id"] not in seen:
            matched.append(row["user_id"])
            seen.add(row["user_id"])
    return matched


def _create_workspace_mentions_for_comment(
    db, workspace_id: str, comment_id: str, body: str, author_user_id: str
) -> list[str]:
    mentioned_user_ids = _extract_workspace_mentions(
        db, workspace_id, body, author_user_id
    )
    for target_user_id in mentioned_user_ids:
        db.execute(
            """
            INSERT OR IGNORE INTO workspace_mentions(
                workspace_id, comment_id, target_user_id, mentioned_by_user_id
            ) VALUES(?,?,?,?)
            """,
            (workspace_id, comment_id, target_user_id, author_user_id),
        )
    return mentioned_user_ids


def _workspace_leaderboard(db, workspace_id: str) -> list[dict]:
    members = db.execute(
        """
        SELECT wm.workspace_id, wm.user_id, u.username, wm.role, wm.joined_at
        FROM workspace_members wm
        JOIN users u ON u.id = wm.user_id
        WHERE wm.workspace_id=?
        """,
        (workspace_id,),
    ).fetchall()
    stats = {
        member["user_id"]: {
            "workspace_id": workspace_id,
            "user_id": member["user_id"],
            "username": member["username"],
            "role": member["role"],
            "assigned": 0,
            "completed": 0,
            "completion_rate": 0.0,
        }
        for member in members
    }
    for todo in _workspace_data(db, workspace_id).get("todos", []):
        if not isinstance(todo, dict):
            continue
        assignee_id = str(todo.get("assigneeId") or todo.get("assignee_id") or "")
        if assignee_id not in stats:
            continue
        stats[assignee_id]["assigned"] += 1
        if todo.get("isCompleted") is True or todo.get("completed") is True:
            stats[assignee_id]["completed"] += 1
    for item in stats.values():
        assigned = item["assigned"]
        item["completion_rate"] = (
            round(item["completed"] / assigned, 4) if assigned > 0 else 0.0
        )
    return sorted(
        stats.values(),
        key=lambda item: (
            item["completed"],
            item["completion_rate"],
            item["assigned"],
            item["username"],
        ),
        reverse=True,
    )


def _workspace_data(db, workspace_id: str) -> dict:
    row = db.execute(
        "SELECT todos, goals, courses, time_entries, calendar_events FROM workspace_data WHERE workspace_id=?",
        (workspace_id,),
    ).fetchone()
    if row is None:
        return {
            "todos": [],
            "goals": [],
            "courses": [],
            "time_entries": [],
            "calendar_events": [],
        }
    return {
        "todos": json.loads(row["todos"] or "[]"),
        "goals": json.loads(row["goals"] or "[]"),
        "courses": json.loads(row["courses"] or "[]"),
        "time_entries": json.loads(row["time_entries"] or "[]"),
        "calendar_events": json.loads(row["calendar_events"] or "[]"),
    }


def _visible_workspace_ids(db, user_id: str) -> set[str]:
    rows = db.execute(
        "SELECT workspace_id FROM workspace_members WHERE user_id=?",
        (user_id,),
    ).fetchall()
    return {r["workspace_id"] for r in rows}


def _merge_workspace_payloads(db, user_id: str, payloads: dict) -> dict:
    visible = _visible_workspace_ids(db, user_id)
    merged: dict = {}
    if not isinstance(payloads, dict):
        payloads = {}
    for workspace_id in visible:
        if workspace_id.startswith("private:"):
            continue
        role = _require_workspace_member(db, workspace_id, user_id)["role"]
        server = _workspace_data(db, workspace_id)
        client = payloads.get(workspace_id) if isinstance(payloads, dict) else None
        if not isinstance(client, dict) or role == "viewer":
            merged_data = server
        else:
            merged_data = {
                "todos": _merge_by_timestamp(server.get("todos", []), client.get("todos", [])),
                "goals": _merge_by_timestamp(server.get("goals", []), client.get("goals", [])),
                "courses": _merge_by_timestamp(server.get("courses", []), client.get("courses", [])),
                "time_entries": _merge_by_timestamp(
                    server.get("time_entries", []), client.get("time_entries", [])
                ),
                "calendar_events": _merge_by_timestamp(
                    server.get("calendar_events", []), client.get("calendar_events", [])
                ),
            }
            db.execute(
                """
                INSERT INTO workspace_data(workspace_id, todos, goals, courses, time_entries, calendar_events, updated_at)
                VALUES(?,?,?,?,?,?,datetime('now'))
                ON CONFLICT(workspace_id) DO UPDATE SET
                    todos=excluded.todos,
                    goals=excluded.goals,
                    courses=excluded.courses,
                    time_entries=excluded.time_entries,
                    calendar_events=excluded.calendar_events,
                    updated_at=datetime('now')
                """,
                (
                    workspace_id,
                    json.dumps(merged_data["todos"], ensure_ascii=False),
                    json.dumps(merged_data["goals"], ensure_ascii=False),
                    json.dumps(merged_data["courses"], ensure_ascii=False),
                    json.dumps(merged_data["time_entries"], ensure_ascii=False),
                    json.dumps(merged_data["calendar_events"], ensure_ascii=False),
                ),
            )
        merged[workspace_id] = merged_data
    return merged


def _sync_payload_from_row(db, user_id: str, row: Optional[sqlite3.Row]) -> dict:
    def _list(col):
        return json.loads(row[col]) if row and row[col] else []

    def _obj(col):
        value = json.loads(row[col]) if row and row[col] else {}
        return value if isinstance(value, dict) else {}

    legacy_countdowns, anniversaries = _split_legacy_anniversary_countdowns(
        _list("anniversaries")
    )
    countdowns = _merge_by_timestamp(_list("countdowns"), legacy_countdowns)

    return {
        "todos": _list("todos"),
        "habits": _list("habits"),
        "pomodoro_sessions": _list("pomodoro_sessions"),
        "focus_penalties": _list("focus_penalties"),
        "pomodoro_config": _obj("pomodoro_config"),
        "user_profile": _obj("user_profile"),
        "notes": _list("notes"),
        "countdowns": countdowns,
        "anniversaries": anniversaries,
        "diaries": _list("diaries"),
        "goals": _list("goals"),
        "calendar_events": _list("calendar_events"),
        "courses": _list("courses"),
        "time_entries": _list("time_entries"),
        "location_reminders": _list("location_reminders"),
        "course_settings": _obj("course_settings"),
        "achievement_states": _obj("achievement_states"),
        "virtual_rewards": _obj("virtual_rewards"),
        "focus_rooms": _obj("focus_rooms"),
        "theme_shop_state": _normalize_theme_shop_state(_obj("theme_shop_state")),
        "preferences": _obj("preferences"),
        "quick_capture_templates": _obj("quick_capture_templates"),
        "list_groups": _list("list_groups"),
        "deleted_items": _obj("deleted_items"),
        "workspace_payloads": _merge_workspace_payloads(db, user_id, {}),
    }


def _sync_response(
    *,
    server_updated_at: str,
    server_version: int,
    payload: dict,
    include_hashes: bool = False,
) -> dict:
    response = {
        "server_updated_at": server_updated_at,
        "server_version": server_version,
        **payload,
    }
    if include_hashes:
        response["collection_hashes"] = _sync_collection_hashes(payload)
    return response


def _sync_impl(
    req: SyncRequest,
    user_id: str,
    *,
    model_dump_payload: Optional[dict] = None,
) -> dict:
    db = get_db()
    try:
        if _setting_get(db, "maintenance_mode", False):
            raise HTTPException(status_code=503, detail="Maintenance mode")
        if not _setting_get(db, "backup_enabled", True):
            raise HTTPException(status_code=503, detail="云端备份已被管理员关闭")

        # 简单的 payload 大小保护
        max_kb = int(_setting_get(db, "backup_max_size_kb", 2048) or 2048)
        if max_kb > 0:
            dump_payload = model_dump_payload if model_dump_payload is not None else req.model_dump()
            payload_size = len(
                json.dumps(dump_payload, ensure_ascii=False).encode("utf-8")
            )
            if payload_size > max_kb * 1024:
                raise HTTPException(
                    status_code=413,
                    detail=f"同步数据过大 ({payload_size // 1024}KB > {max_kb}KB)",
                )

        _ensure_private_workspace(db, user_id)
        row = db.execute(
            "SELECT todos, habits, pomodoro_sessions, pomodoro_config, user_profile, "
            "notes, countdowns, anniversaries, diaries, goals, calendar_events, "
            "courses, time_entries, location_reminders, course_settings, achievement_states, virtual_rewards, focus_rooms, "
            "focus_penalties, theme_shop_state, preferences, quick_capture_templates, list_groups, "
            "deleted_items, sync_version "
            "FROM sync_data WHERE user_id=?",
            (user_id,),
        ).fetchone()
        next_sync_version = int(row["sync_version"] or 0) + 1 if row else 1
        sync_updated_at = _utc_now_text()

        def _list(col):
            return json.loads(row[col]) if row and row[col] else []

        def _obj(col):
            value = json.loads(row[col]) if row and row[col] else {}
            return value if isinstance(value, dict) else {}

        server_todos = _list("todos")
        server_habits = _list("habits")
        server_sessions = _list("pomodoro_sessions")
        server_focus_penalties = _list("focus_penalties")
        server_config = _obj("pomodoro_config")
        server_profile = _obj("user_profile")
        server_notes = _list("notes")
        legacy_server_countdowns, server_annis = _split_legacy_anniversary_countdowns(
            _list("anniversaries")
        )
        legacy_client_countdowns, req_annis = _split_legacy_anniversary_countdowns(
            req.anniversaries
        )
        server_countdowns = _merge_by_timestamp(
            _list("countdowns"), legacy_server_countdowns
        )
        server_diaries = _list("diaries")
        server_goals = _list("goals")
        server_calendar_events = _list("calendar_events")
        server_courses = _list("courses")
        server_time_entries = _list("time_entries")
        server_location_reminders = _list("location_reminders")
        server_course_settings = _obj("course_settings")
        server_achievement_states = _obj("achievement_states")
        server_virtual_rewards = _obj("virtual_rewards")
        server_focus_rooms = _obj("focus_rooms")
        server_theme_shop_state = _obj("theme_shop_state")
        server_preferences = _obj("preferences")
        server_quick_capture_templates = _obj("quick_capture_templates")
        server_list_groups = _list("list_groups")
        server_deleted_items = _obj("deleted_items")
        merged_deleted_items = _merge_deleted_items(
            server_deleted_items, req.deleted_items
        )

        merged_todos = _merge_by_timestamp(
            server_todos,
            req.todos,
            collection="todos",
            deleted_items=merged_deleted_items,
        )
        merged_habits = _merge_habits_by_timestamp(
            server_habits,
            req.habits,
            deleted_items=merged_deleted_items,
        )
        merged_sessions = _merge_by_timestamp(
            server_sessions,
            req.pomodoro_sessions,
            collection="pomodoro_sessions",
            deleted_items=merged_deleted_items,
        )
        merged_focus_penalties = _merge_by_timestamp(
            server_focus_penalties,
            req.focus_penalties,
            collection="focus_penalties",
            deleted_items=merged_deleted_items,
        )
        merged_config = _merge_dict(server_config, req.pomodoro_config)
        merged_profile = _merge_dict(server_profile, req.user_profile)
        merged_notes = _merge_by_timestamp(
            server_notes,
            req.notes,
            collection="notes",
            deleted_items=merged_deleted_items,
        )
        merged_countdowns = _merge_by_timestamp(
            server_countdowns,
            [*req.countdowns, *legacy_client_countdowns],
            collection="countdowns",
            deleted_items=merged_deleted_items,
        )
        merged_annis = _merge_by_timestamp(
            server_annis,
            req_annis,
            collection="anniversaries",
            deleted_items=merged_deleted_items,
        )
        merged_diaries = _merge_diaries_by_date(
            server_diaries,
            req.diaries,
            deleted_items=merged_deleted_items,
        )
        merged_goals = _merge_by_timestamp(
            server_goals,
            req.goals,
            collection="goals",
            deleted_items=merged_deleted_items,
        )
        merged_calendar_events = _merge_by_timestamp(
            server_calendar_events,
            req.calendar_events,
            collection="calendar_events",
            deleted_items=merged_deleted_items,
        )
        merged_courses = _merge_by_timestamp(
            server_courses,
            req.courses,
            collection="courses",
            deleted_items=merged_deleted_items,
        )
        merged_time_entries = _merge_by_timestamp(
            server_time_entries,
            req.time_entries,
            collection="time_entries",
            deleted_items=merged_deleted_items,
        )
        merged_location_reminders = _merge_by_timestamp(
            server_location_reminders,
            req.location_reminders,
            collection="location_reminders",
            deleted_items=merged_deleted_items,
        )
        merged_course_settings = _merge_dict(
            server_course_settings, req.course_settings
        )
        merged_achievement_states = _merge_state_dict(
            server_achievement_states, req.achievement_states
        )
        merged_virtual_rewards = _merge_virtual_rewards(
            server_virtual_rewards, req.virtual_rewards
        )
        merged_focus_rooms = _merge_dict(server_focus_rooms, req.focus_rooms)
        merged_theme_shop_state = _merge_theme_shop_state(
            server_theme_shop_state, req.theme_shop_state
        )
        merged_preferences = _merge_preferences(server_preferences, req.preferences)
        merged_quick_capture_templates = _merge_quick_capture_templates(
            server_quick_capture_templates,
            req.quick_capture_templates,
            deleted_items=merged_deleted_items,
        )
        merged_list_groups = _merge_by_timestamp(
            server_list_groups,
            req.list_groups,
            collection="list_groups",
            deleted_items=merged_deleted_items,
        )
        merged_workspace_payloads = _merge_workspace_payloads(
            db, user_id, req.workspace_payloads
        )
        merged_deleted_items = _prune_deleted_items(
            merged_deleted_items,
            {
                "todos": merged_todos,
                "habits": merged_habits,
                "pomodoro_sessions": merged_sessions,
                "focus_penalties": merged_focus_penalties,
                "notes": merged_notes,
                "countdowns": merged_countdowns,
                "anniversaries": merged_annis,
                "diaries": merged_diaries,
                "goals": merged_goals,
                "calendar_events": merged_calendar_events,
                "courses": merged_courses,
                "time_entries": merged_time_entries,
                "location_reminders": merged_location_reminders,
                "quick_capture_templates": merged_quick_capture_templates,
                "list_groups": merged_list_groups,
            },
        )

        db.execute(
            """
            INSERT OR REPLACE INTO sync_data
            (user_id, todos, habits, pomodoro_sessions, pomodoro_config, user_profile,
             notes, countdowns, anniversaries, diaries, goals, calendar_events,
             courses, time_entries, location_reminders,
             course_settings, achievement_states, virtual_rewards, focus_rooms,
             focus_penalties, theme_shop_state, preferences, quick_capture_templates,
             list_groups, deleted_items, sync_version, updated_at)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                user_id,
                json.dumps(merged_todos, ensure_ascii=False),
                json.dumps(merged_habits, ensure_ascii=False),
                json.dumps(merged_sessions, ensure_ascii=False),
                json.dumps(merged_config, ensure_ascii=False),
                json.dumps(merged_profile, ensure_ascii=False),
                json.dumps(merged_notes, ensure_ascii=False),
                json.dumps(merged_countdowns, ensure_ascii=False),
                json.dumps(merged_annis, ensure_ascii=False),
                json.dumps(merged_diaries, ensure_ascii=False),
                json.dumps(merged_goals, ensure_ascii=False),
                json.dumps(merged_calendar_events, ensure_ascii=False),
                json.dumps(merged_courses, ensure_ascii=False),
                json.dumps(merged_time_entries, ensure_ascii=False),
                json.dumps(merged_location_reminders, ensure_ascii=False),
                json.dumps(merged_course_settings, ensure_ascii=False),
                json.dumps(merged_achievement_states, ensure_ascii=False),
                json.dumps(merged_virtual_rewards, ensure_ascii=False),
                json.dumps(merged_focus_rooms, ensure_ascii=False),
                json.dumps(merged_focus_penalties, ensure_ascii=False),
                json.dumps(merged_theme_shop_state, ensure_ascii=False),
                json.dumps(merged_preferences, ensure_ascii=False),
                json.dumps(merged_quick_capture_templates, ensure_ascii=False),
                json.dumps(merged_list_groups, ensure_ascii=False),
                json.dumps(merged_deleted_items, ensure_ascii=False),
                next_sync_version,
                sync_updated_at,
            ),
        )
        db.commit()

        return _sync_response(
            server_updated_at=sync_updated_at,
            server_version=next_sync_version,
            payload={
                "todos": merged_todos,
                "habits": merged_habits,
                "pomodoro_sessions": merged_sessions,
                "focus_penalties": merged_focus_penalties,
                "pomodoro_config": merged_config,
                "user_profile": merged_profile,
                "notes": merged_notes,
                "countdowns": merged_countdowns,
                "anniversaries": merged_annis,
                "diaries": merged_diaries,
                "goals": merged_goals,
                "calendar_events": merged_calendar_events,
                "courses": merged_courses,
                "time_entries": merged_time_entries,
                "location_reminders": merged_location_reminders,
                "course_settings": merged_course_settings,
                "achievement_states": merged_achievement_states,
                "virtual_rewards": merged_virtual_rewards,
                "focus_rooms": merged_focus_rooms,
                "theme_shop_state": merged_theme_shop_state,
                "preferences": merged_preferences,
                "quick_capture_templates": merged_quick_capture_templates,
                "list_groups": merged_list_groups,
                "deleted_items": merged_deleted_items,
                "workspace_payloads": merged_workspace_payloads,
            },
            include_hashes=True,
        )
    finally:
        db.close()


@app.post("/api/sync")
def sync(req: SyncRequest, user_id: str = Depends(_verify_token)):
    return _sync_impl(req, user_id)


@app.post("/api/sync/delta")
def sync_delta(req: SyncDeltaRequest, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        _ensure_private_workspace(db, user_id)
        row = db.execute(
            "SELECT todos, habits, pomodoro_sessions, pomodoro_config, user_profile, "
            "notes, countdowns, anniversaries, diaries, goals, calendar_events, "
            "courses, time_entries, location_reminders, course_settings, achievement_states, virtual_rewards, focus_rooms, "
            "focus_penalties, theme_shop_state, preferences, quick_capture_templates, list_groups, "
            "deleted_items, sync_version "
            "FROM sync_data WHERE user_id=?",
            (user_id,),
        ).fetchone()
        payload = _sync_payload_from_row(db, user_id, row)
    finally:
        db.close()
    if isinstance(req.collections, dict):
        for key, value in req.collections.items():
            key_text = str(key)
            if key_text in payload:
                payload[key_text] = value
    return _sync_impl(
        SyncRequest(**payload),
        user_id,
        model_dump_payload=req.model_dump(),
    )


@app.post("/api/sync/item-delta")
def sync_item_delta(req: SyncItemDeltaRequest, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        _ensure_private_workspace(db, user_id)
        row = db.execute(
            "SELECT todos, habits, pomodoro_sessions, pomodoro_config, user_profile, "
            "notes, countdowns, anniversaries, diaries, goals, calendar_events, "
            "courses, time_entries, location_reminders, course_settings, achievement_states, virtual_rewards, focus_rooms, "
            "focus_penalties, theme_shop_state, preferences, quick_capture_templates, list_groups, "
            "deleted_items, sync_version "
            "FROM sync_data WHERE user_id=?",
            (user_id,),
        ).fetchone()
        payload = _sync_payload_from_row(db, user_id, row)
    finally:
        db.close()
    payload = _apply_item_delta_to_payload(payload, req)
    return _sync_impl(
        SyncRequest(**payload),
        user_id,
        model_dump_payload=req.model_dump(),
    )


@app.post("/api/sync/pull")
def sync_pull(req: SyncPullRequest, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        if _setting_get(db, "maintenance_mode", False):
            raise HTTPException(status_code=503, detail="Maintenance mode")
        if not _setting_get(db, "backup_enabled", True):
            raise HTTPException(status_code=503, detail="云端备份已被管理员关闭")

        _ensure_private_workspace(db, user_id)
        row = db.execute(
            "SELECT todos, habits, pomodoro_sessions, pomodoro_config, user_profile, "
            "notes, countdowns, anniversaries, diaries, goals, calendar_events, "
            "courses, time_entries, location_reminders, course_settings, achievement_states, virtual_rewards, focus_rooms, "
            "focus_penalties, theme_shop_state, preferences, quick_capture_templates, list_groups, "
            "deleted_items, sync_version, updated_at "
            "FROM sync_data WHERE user_id=?",
            (user_id,),
        ).fetchone()
        payload = _sync_payload_from_row(db, user_id, row)
        collection_hashes = _sync_collection_hashes(payload)
        client_hashes = req.collection_hashes if isinstance(req.collection_hashes, dict) else {}
        changed_payload = {
            key: payload[key]
            for key in SYNC_PULL_COLLECTIONS
            if str(client_hashes.get(key) or "") != collection_hashes[key]
        }
        changed_payload["collection_hashes"] = collection_hashes
        return {
            "server_updated_at": row["updated_at"] if row else "",
            "server_version": int(row["sync_version"] or 0) if row else 0,
            **changed_payload,
        }
    finally:
        db.close()


@app.get("/api/sync/status")
def sync_status(user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        row = db.execute(
            "SELECT updated_at, sync_version FROM sync_data WHERE user_id=?",
            (user_id,),
        ).fetchone()
        return {
            "server_updated_at": row["updated_at"] if row else "",
            "server_version": int(row["sync_version"] or 0) if row else 0,
        }
    finally:
        db.close()


@app.get("/api/sync/events")
async def sync_events(
    interval_seconds: int = Query(15, ge=2, le=60),
    user_id: str = Depends(_verify_token),
):
    def _sync_revision() -> dict:
        db = get_db()
        try:
            row = db.execute(
                "SELECT updated_at, sync_version FROM sync_data WHERE user_id=?",
                (user_id,),
            ).fetchone()
            return {
                "server_updated_at": row["updated_at"] if row else "",
                "server_version": int(row["sync_version"] or 0) if row else 0,
            }
        finally:
            db.close()

    async def event_stream():
        last_signature: Optional[tuple[int, str]] = None
        while True:
            payload = _sync_revision()
            signature = (
                int(payload.get("server_version") or 0),
                str(payload.get("server_updated_at") or ""),
            )
            if last_signature != signature:
                last_signature = signature
                yield (
                    "event: sync\n"
                    f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"
                )
            await asyncio.sleep(interval_seconds)

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


# ---- Workspaces ----


@app.get("/api/workspaces")
def list_workspaces(user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        _ensure_private_workspace(db, user_id)
        rows = db.execute(
            """
            SELECT w.*
            FROM workspaces w
            JOIN workspace_members wm ON wm.workspace_id = w.id
            WHERE wm.user_id=?
            ORDER BY w.is_private DESC, w.updated_at DESC
            """,
            (user_id,),
        ).fetchall()
        result = []
        for row in rows:
            members = db.execute(
                """
                SELECT wm.workspace_id, wm.user_id, u.username, wm.role, wm.joined_at
                FROM workspace_members wm
                JOIN users u ON u.id = wm.user_id
                WHERE wm.workspace_id=?
                ORDER BY wm.role='owner' DESC, wm.joined_at
                """,
                (row["id"],),
            ).fetchall()
            item = _workspace_to_dict(row, members)
            item["data"] = _workspace_data(db, row["id"])
            result.append(item)
        return result
    finally:
        db.close()


@app.post("/api/workspaces")
def create_workspace(req: WorkspaceCreate, user_id: str = Depends(_verify_token)):
    name = req.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Workspace name required")
    db = get_db()
    try:
        workspace_id = secrets.token_hex(12)
        db.execute(
            "INSERT INTO workspaces(id, name, owner_user_id, is_private) VALUES(?,?,?,0)",
            (workspace_id, name, user_id),
        )
        db.execute(
            "INSERT INTO workspace_members(workspace_id, user_id, role) VALUES(?,?, 'owner')",
            (workspace_id, user_id),
        )
        db.execute("INSERT INTO workspace_data(workspace_id) VALUES(?)", (workspace_id,))
        _audit(db, user_id, _get_username(db, user_id), "workspace.create", workspace_id)
        _workspace_activity(db, user_id, "workspace.create", workspace_id, name)
        db.commit()
        return {"id": workspace_id, "name": name}
    finally:
        db.close()


@app.patch("/api/workspaces/{workspace_id}")
def update_workspace(
    workspace_id: str, req: WorkspaceUpdate, user_id: str = Depends(_verify_token)
):
    db = get_db()
    try:
        row = _require_workspace_editor(db, workspace_id, user_id)
        if row["is_private"]:
            raise HTTPException(status_code=400, detail="Private workspace is immutable")
        changed = {}
        if req.name is not None and req.name.strip():
            db.execute(
                "UPDATE workspaces SET name=?, updated_at=datetime('now') WHERE id=?",
                (req.name.strip(), workspace_id),
            )
            changed["name"] = req.name.strip()
        _audit(
            db,
            user_id,
            _get_username(db, user_id),
            "workspace.update",
            workspace_id,
            json.dumps(changed, ensure_ascii=False),
        )
        db.commit()
        return {"status": "ok", "changed": changed}
    finally:
        db.close()


@app.post("/api/workspaces/{workspace_id}/invites")
def create_workspace_invite(
    workspace_id: str,
    req: WorkspaceInviteCreate,
    user_id: str = Depends(_verify_token),
):
    if req.role not in {"editor", "viewer"}:
        raise HTTPException(status_code=400, detail="Invalid role")
    db = get_db()
    try:
        row = _require_workspace_editor(db, workspace_id, user_id)
        if row["is_private"]:
            raise HTTPException(status_code=400, detail="Private workspace cannot invite")
        invite_id = secrets.token_hex(12)
        code = secrets.token_urlsafe(8).replace("-", "").replace("_", "")[:10]
        db.execute(
            """
            INSERT INTO workspace_invites(id, workspace_id, code, role, created_by, expires_at)
            VALUES(?,?,?,?,?,?)
            """,
            (invite_id, workspace_id, code, req.role, user_id, req.expires_at),
        )
        _audit(db, user_id, _get_username(db, user_id), "workspace.invite", workspace_id)
        _workspace_activity(db, user_id, "workspace.invite", workspace_id, req.role)
        db.commit()
        return {
            "id": invite_id,
            "workspace_id": workspace_id,
            "code": code,
            "role": req.role,
            "expires_at": req.expires_at,
        }
    finally:
        db.close()


@app.post("/api/invites/{code}/accept")
def accept_workspace_invite(code: str, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        row = db.execute(
            """
            SELECT wi.*, w.name
            FROM workspace_invites wi
            JOIN workspaces w ON w.id = wi.workspace_id
            WHERE wi.code=?
            """,
            (code.strip(),),
        ).fetchone()
        if row is None or row["revoked"]:
            raise HTTPException(status_code=404, detail="Invite not found")
        if row["expires_at"] and row["expires_at"] < datetime.now(timezone.utc).isoformat():
            raise HTTPException(status_code=400, detail="Invite expired")
        db.execute(
            "INSERT INTO workspace_members(workspace_id, user_id, role) VALUES(?,?,?) "
            "ON CONFLICT(workspace_id, user_id) DO UPDATE SET role=excluded.role",
            (row["workspace_id"], user_id, row["role"]),
        )
        db.execute(
            "UPDATE workspace_invites SET used_by=?, used_at=datetime('now') WHERE id=?",
            (user_id, row["id"]),
        )
        _audit(
            db,
            user_id,
            _get_username(db, user_id),
            "workspace.invite.accept",
            row["workspace_id"],
        )
        _workspace_activity(
            db,
            user_id,
            "workspace.invite.accept",
            row["workspace_id"],
            row["role"],
        )
        db.commit()
        return {
            "workspace_id": row["workspace_id"],
            "name": row["name"],
            "role": row["role"],
        }
    finally:
        db.close()


@app.patch("/api/workspaces/{workspace_id}/members/{member_user_id}")
def update_workspace_member(
    workspace_id: str,
    member_user_id: str,
    req: WorkspaceMemberUpdate,
    user_id: str = Depends(_verify_token),
):
    if req.role not in {"editor", "viewer"}:
        raise HTTPException(status_code=400, detail="Invalid role")
    db = get_db()
    try:
        owner = _require_workspace_member(db, workspace_id, user_id)
        if owner["role"] != "owner":
            raise HTTPException(status_code=403, detail="Owner role required")
        if member_user_id == owner["owner_user_id"]:
            raise HTTPException(status_code=400, detail="Owner role cannot change")
        db.execute(
            "UPDATE workspace_members SET role=? WHERE workspace_id=? AND user_id=?",
            (req.role, workspace_id, member_user_id),
        )
        _workspace_activity(
            db,
            user_id,
            "workspace.member.role",
            workspace_id,
            json.dumps({"user_id": member_user_id, "role": req.role}, ensure_ascii=False),
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


@app.delete("/api/workspaces/{workspace_id}/members/{member_user_id}")
def remove_workspace_member(
    workspace_id: str,
    member_user_id: str,
    user_id: str = Depends(_verify_token),
):
    db = get_db()
    try:
        owner = _require_workspace_member(db, workspace_id, user_id)
        if owner["role"] != "owner" and user_id != member_user_id:
            raise HTTPException(status_code=403, detail="Owner role required")
        if member_user_id == owner["owner_user_id"]:
            raise HTTPException(status_code=400, detail="Owner cannot be removed")
        db.execute(
            "DELETE FROM workspace_members WHERE workspace_id=? AND user_id=?",
            (workspace_id, member_user_id),
        )
        _workspace_activity(
            db,
            user_id,
            "workspace.member.remove",
            workspace_id,
            member_user_id,
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


@app.get("/api/workspaces/{workspace_id}/comments")
def list_workspace_comments(
    workspace_id: str,
    target_id: Optional[str] = None,
    user_id: str = Depends(_verify_token),
):
    db = get_db()
    try:
        _require_workspace_member(db, workspace_id, user_id)
        params: list = [workspace_id]
        where = "wc.workspace_id=?"
        if target_id:
            where += " AND wc.target_id=?"
            params.append(target_id)
        rows = db.execute(
            f"""
            SELECT wc.*, u.username AS author_name
            FROM workspace_comments wc
            JOIN users u ON u.id = wc.author_user_id
            WHERE {where}
            ORDER BY wc.created_at DESC
            LIMIT 100
            """,
            params,
        ).fetchall()
        return [_workspace_comment_to_dict(row) for row in rows]
    finally:
        db.close()


@app.post("/api/workspaces/{workspace_id}/comments")
def create_workspace_comment(
    workspace_id: str,
    req: WorkspaceCommentCreate,
    user_id: str = Depends(_verify_token),
):
    body = req.body.strip()
    if not body:
        raise HTTPException(status_code=400, detail="Comment body required")
    if len(body) > 1000:
        raise HTTPException(status_code=400, detail="Comment body too long")
    db = get_db()
    try:
        _require_workspace_member(db, workspace_id, user_id)
        comment_id = secrets.token_hex(12)
        target_id = (req.target_id or "").strip()
        db.execute(
            """
            INSERT INTO workspace_comments(id, workspace_id, target_id, author_user_id, body)
            VALUES(?,?,?,?,?)
            """,
            (comment_id, workspace_id, target_id, user_id, body),
        )
        _workspace_activity(
            db,
            user_id,
            "workspace.comment",
            workspace_id,
            json.dumps({"target_id": target_id, "body": body[:80]}, ensure_ascii=False),
        )
        mentioned_user_ids = _create_workspace_mentions_for_comment(
            db, workspace_id, comment_id, body, user_id
        )
        mention_count = len(mentioned_user_ids)
        if mention_count > 0:
            _workspace_activity(
                db,
                user_id,
                "workspace.mention",
                workspace_id,
                json.dumps(
                    {"target_id": target_id, "count": mention_count},
                    ensure_ascii=False,
                ),
            )
            author_name = _get_username(db, user_id)
            workspace_row = db.execute(
                "SELECT name FROM workspaces WHERE id=?",
                (workspace_id,),
            ).fetchone()
            workspace_name = workspace_row["name"] if workspace_row else workspace_id
            for target_user_id in mentioned_user_ids:
                try:
                    _send_workspace_mention_email(
                        db,
                        target_user_id=target_user_id,
                        author_name=author_name,
                        workspace_name=workspace_name,
                        target_id=target_id,
                        body=body,
                    )
                    _audit(
                        db,
                        user_id,
                        author_name,
                        "workspace.mention_email.sent",
                        target_user_id,
                        workspace_id,
                    )
                except Exception as e:
                    _audit(
                        db,
                        user_id,
                        author_name,
                        "workspace.mention_email.failed",
                        target_user_id,
                        str(e),
                    )
        db.commit()
        row = db.execute(
            """
            SELECT wc.*, u.username AS author_name
            FROM workspace_comments wc
            JOIN users u ON u.id = wc.author_user_id
            WHERE wc.id=?
            """,
            (comment_id,),
        ).fetchone()
        return _workspace_comment_to_dict(row)
    finally:
        db.close()


@app.get("/api/workspaces/mentions")
def list_workspace_mentions(
    unread_only: bool = False,
    user_id: str = Depends(_verify_token),
):
    db = get_db()
    try:
        where = "m.target_user_id=?"
        params: list = [user_id]
        if unread_only:
            where += " AND m.read_at IS NULL"
        rows = db.execute(
            f"""
            SELECT
                m.id,
                m.workspace_id,
                w.name AS workspace_name,
                m.comment_id,
                wc.target_id,
                wc.author_user_id,
                u.username AS author_name,
                wc.body,
                m.read_at,
                m.created_at
            FROM workspace_mentions m
            JOIN workspace_comments wc ON wc.id = m.comment_id
            JOIN workspaces w ON w.id = m.workspace_id
            JOIN users u ON u.id = wc.author_user_id
            JOIN workspace_members access
              ON access.workspace_id = m.workspace_id
             AND access.user_id = m.target_user_id
            WHERE {where}
            ORDER BY m.created_at DESC, m.id DESC
            LIMIT 100
            """,
            params,
        ).fetchall()
        return [_workspace_mention_to_dict(row) for row in rows]
    finally:
        db.close()


@app.post("/api/workspaces/mentions/{mention_id}/read")
def mark_workspace_mention_read(
    mention_id: int,
    user_id: str = Depends(_verify_token),
):
    db = get_db()
    try:
        row = db.execute(
            "SELECT id FROM workspace_mentions WHERE id=? AND target_user_id=?",
            (mention_id, user_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Mention not found")
        db.execute(
            "UPDATE workspace_mentions SET read_at=datetime('now') WHERE id=?",
            (mention_id,),
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


@app.get("/api/workspaces/{workspace_id}/activities")
def list_workspace_activities(
    workspace_id: str,
    user_id: str = Depends(_verify_token),
):
    db = get_db()
    try:
        _require_workspace_member(db, workspace_id, user_id)
        rows = db.execute(
            """
            SELECT *
            FROM workspace_activity
            WHERE workspace_id=?
            ORDER BY created_at DESC, id DESC
            LIMIT 100
            """,
            (workspace_id,),
        ).fetchall()
        return [_workspace_activity_to_dict(row) for row in rows]
    finally:
        db.close()


@app.get("/api/workspaces/{workspace_id}/leaderboard")
def workspace_leaderboard(workspace_id: str, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        row = _require_workspace_member(db, workspace_id, user_id)
        if row["is_private"]:
            raise HTTPException(status_code=400, detail="Private workspace has no leaderboard")
        return _workspace_leaderboard(db, workspace_id)
    finally:
        db.close()


# ---- Announcements (public) ----


@app.get("/api/announcements")
def list_announcements(limit: int = Query(20, ge=1, le=100)):
    db = get_db()
    try:
        rows = db.execute(
            "SELECT id, title, body, level, created_at FROM announcements "
            "WHERE published=1 ORDER BY id DESC LIMIT ?",
            (limit,),
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        db.close()


# ---- Feedback (user) ----


@app.post("/api/feedback")
@app.post("/api/me/feedback")
def create_feedback(req: FeedbackCreate, user_id: str = Depends(_verify_token)):
    category = _clean_feedback_category(req.category, req.type)
    content = _clean_feedback_content(req.content, req.title)
    db = get_db()
    try:
        cur = db.execute(
            "INSERT INTO feedback(user_id, category, content) VALUES(?,?,?)",
            (user_id, category, content),
        )
        db.commit()
        return {"id": cur.lastrowid, "status": "open"}
    finally:
        db.close()


@app.get("/api/me/feedback/{fb_id}")
@app.get("/api/feedback/me/{fb_id}")
def my_feedback_detail(fb_id: int, user_id: str = Depends(_verify_token)):
    db = get_db()
    try:
        row = db.execute(
            "SELECT id, category, content, status, admin_reply, created_at, updated_at "
            "FROM feedback WHERE id=? AND user_id=?",
            (fb_id, user_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="反馈不存在")
        return dict(row)
    finally:
        db.close()


@app.get("/api/feedback/me")
@app.get("/api/me/feedback")
def my_feedback(
    user_id: str = Depends(_verify_token),
    page: Optional[int] = None,
    page_size: Optional[int] = None,
    status: Optional[str] = None,
    category: Optional[str] = None,
    type: Optional[str] = None,
    keyword: Optional[str] = None,
    q: Optional[str] = None,
):
    db = get_db()
    try:
        where_parts = ["user_id=?"]
        params: list = [user_id]
        if status:
            where_parts.append("status=?")
            params.append(FEEDBACK_STATUS_ALIASES.get(status, status))
        if category:
            where_parts.append("category=?")
            params.append(_clean_feedback_category(category, type))
        elif type == "wish":
            where_parts.append("category=?")
            params.append("wish")
        search = (keyword or q or "").strip()
        if search:
            where_parts.append("(content LIKE ? OR admin_reply LIKE ?)")
            like = f"%{search}%"
            params.extend([like, like])
        where = " AND ".join(where_parts)
        if page is None and page_size is None:
            rows = db.execute(
                "SELECT id, category, content, status, admin_reply, created_at, updated_at "
                f"FROM feedback WHERE {where} ORDER BY id DESC",
                params,
            ).fetchall()
            return [dict(r) for r in rows]
        current_page = max(1, int(page or 1))
        current_page_size = max(1, min(int(page_size or 20), 100))
        offset = (current_page - 1) * current_page_size
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM feedback WHERE {where}",
            params,
        ).fetchone()["c"]
        rows = db.execute(
            "SELECT id, category, content, status, admin_reply, created_at, updated_at "
            f"FROM feedback WHERE {where} ORDER BY id DESC LIMIT ? OFFSET ?",
            (*params, current_page_size, offset),
        ).fetchall()
        total = int(total or 0)
        return {
            "items": [dict(r) for r in rows],
            "total": total,
            "page": current_page,
            "page_size": current_page_size,
            "total_pages": (total + current_page_size - 1) // current_page_size,
        }
    finally:
        db.close()


# =====================================================================
# ADMIN API
# =====================================================================


# ---- Dashboard / stats ----


@app.get("/api/admin/overview")
@app.get("/api/admin/stats")
def admin_stats(_: str = Depends(_require_admin)):
    db = get_db()
    try:
        actor = _
        online_ids = sorted(_online_user_ids())
        users_total = db.execute("SELECT COUNT(*) AS c FROM users").fetchone()["c"]
        users_admin = db.execute(
            "SELECT COUNT(*) AS c FROM users WHERE is_admin=1"
        ).fetchone()["c"]
        users_disabled = db.execute(
            "SELECT COUNT(*) AS c FROM users WHERE is_disabled=1"
        ).fetchone()["c"]
        users_today = db.execute(
            "SELECT COUNT(*) AS c FROM users WHERE date(created_at)=date('now')"
        ).fetchone()["c"]
        active_cutoff = _format_utc(_utc_now() - timedelta(days=7))
        users_active_7d = db.execute(
            """
            SELECT COUNT(*) AS c
            FROM users
            WHERE (last_active_at IS NOT NULL AND last_active_at >= ?)
               OR (last_login_at IS NOT NULL AND last_login_at >= ?)
            """,
            (active_cutoff, active_cutoff),
        ).fetchone()["c"]
        users_unverified_email = db.execute(
            "SELECT COUNT(*) AS c FROM users WHERE email<>'' AND email_verified=0"
        ).fetchone()["c"]

        fb_total = db.execute("SELECT COUNT(*) AS c FROM feedback").fetchone()["c"]
        fb_open = db.execute(
            "SELECT COUNT(*) AS c FROM feedback WHERE status='open'"
        ).fetchone()["c"]
        fb_in_progress = db.execute(
            "SELECT COUNT(*) AS c FROM feedback WHERE status='in_progress'"
        ).fetchone()["c"]
        fb_resolved = db.execute(
            "SELECT COUNT(*) AS c FROM feedback WHERE status='resolved'"
        ).fetchone()["c"]
        fb_closed = db.execute(
            "SELECT COUNT(*) AS c FROM feedback WHERE status='closed'"
        ).fetchone()["c"]

        ann_total = db.execute(
            "SELECT COUNT(*) AS c FROM announcements"
        ).fetchone()["c"]
        ann_published = db.execute(
            "SELECT COUNT(*) AS c FROM announcements WHERE published=1"
        ).fetchone()["c"]

        invite_total = db.execute(
            "SELECT COUNT(*) AS c FROM invite_codes"
        ).fetchone()["c"]
        invite_used = db.execute(
            "SELECT COUNT(*) AS c FROM invite_codes WHERE used_by IS NOT NULL"
        ).fetchone()["c"]

        # 近 7 天注册
        rows = db.execute(
            "SELECT date(created_at) AS d, COUNT(*) AS c FROM users "
            "WHERE created_at >= datetime('now','-7 days') "
            "GROUP BY d ORDER BY d"
        ).fetchall()
        reg_series = [{"date": r["d"], "count": r["c"]} for r in rows]

        return {
            "users": {
                "total": users_total,
                "admin": users_admin,
                "disabled": users_disabled,
                "new_today": users_today,
                "active_7d": users_active_7d,
                "online": len(online_ids),
                "unverified_email": users_unverified_email,
            },
            "feedback": {
                "total": fb_total,
                "open": fb_open,
                "in_progress": fb_in_progress,
                "resolved": fb_resolved,
                "closed": fb_closed,
            },
            "announcements": {"total": ann_total, "published": ann_published},
            "invites": {"total": invite_total, "used": invite_used},
            "registration_series": reg_series,
            "tokens_online": len(online_ids),
        }
    finally:
        db.close()


# ---- Settings ----


@app.get("/api/admin/settings")
def admin_get_settings(
    _: str = Depends(_require_admin),
    scope: Optional[str] = None,
):
    db = get_db()
    try:
        actor = _
        scope_key = (scope or "").strip().lower()
        allowed_keys = ADMIN_SETTINGS_SCOPES.get(scope_key)
        if allowed_keys is None:
            _ensure_admin_permission(db, actor, "settings")
        else:
            _ensure_admin_permission(db, actor, scope_key)
        rows = db.execute("SELECT key, value FROM settings").fetchall()
        result: dict = {}
        for r in rows:
            if allowed_keys is not None and r["key"] not in allowed_keys:
                continue
            try:
                result[r["key"]] = json.loads(r["value"])
            except Exception:
                result[r["key"]] = r["value"]
        # 敏感信息脱敏：只返回是否已配置 + 掩码
        def include_key(key: str) -> bool:
            return allowed_keys is None or key in allowed_keys

        if include_key("ai_api_key"):
            raw_key = str(result.get("ai_api_key") or "")
            result["ai_api_key_set"] = bool(raw_key)
            result["ai_api_key"] = (
                f"{raw_key[:3]}***{raw_key[-3:]}"
                if len(raw_key) > 6
                else ("***" if raw_key else "")
            )
        for secret_key in (
            "openlist_password",
            "backup_email_smtp_password",
            "reminder_email_smtp_password",
            "openclaw_mail_api_key",
            "resend_api_key",
            "hermes_api_key",
            "email_smtp_password",
        ):
            if not include_key(secret_key):
                continue
            raw = str(result.get(secret_key) or "")
            result[f"{secret_key}_set"] = bool(raw)
            result[secret_key] = (
                f"{raw[:2]}***{raw[-2:]}" if len(raw) > 4 else ("***" if raw else "")
            )
        if allowed_keys is None or scope_key == "backup":
            result.update(_account_email_runtime_status(_account_mail_runtime(db)))
        if allowed_keys is None:
            result.update(_update_release_defaults(db))
            result["force_relogin_enabled"] = _setting_get(
                db, "force_relogin_enabled", False
            )
            result["force_relogin_issued_at"] = _setting_get(
                db, "force_relogin_issued_at", ""
            )
        return result
    finally:
        db.close()


def _apply_settings_updates(db, update_items: dict, actor: str) -> dict:
    _coerce_update_settings(db, update_items)
    required_permissions = set()
    if any(key in AI_SETTING_KEYS for key in update_items):
        required_permissions.add("ai")
    if any(key in BACKUP_ADMIN_SETTING_KEYS for key in update_items):
        required_permissions.add("backup")
    if any(
        key not in AI_SETTING_KEYS and key not in BACKUP_ADMIN_SETTING_KEYS
        for key in update_items
    ) or not update_items:
        required_permissions.add("settings")
    for permission in sorted(required_permissions):
        _ensure_admin_permission(db, actor, permission)

    changed = {}
    for key, value in update_items.items():
        _setting_set(db, key, value)
        changed[key] = value
        if key == "allow_public_registration":
            _setting_set(db, "registration_enabled", value)
            changed["registration_enabled"] = value
        elif key == "registration_enabled":
            _setting_set(db, "allow_public_registration", value)
            changed["allow_public_registration"] = value
        elif key == "registration_invite_required":
            _setting_set(db, "invite_code_required", value)
            changed["invite_code_required"] = value
        elif key == "invite_code_required":
            _setting_set(db, "registration_invite_required", value)
            changed["registration_invite_required"] = value
        elif key == "default_registration_coins":
            db.execute(
                """
                UPDATE admin_groups
                SET default_time_coins=?, updated_at=datetime('now')
                WHERE id='group_default'
                """,
                (_bounded_int(value, 100),),
            )
    _audit(
        db,
        actor,
        _get_username(db, actor),
        "settings.update",
        detail=json.dumps(changed, ensure_ascii=False),
    )
    return changed


@app.post("/api/admin/settings")
@app.patch("/api/admin/settings")
def admin_update_settings(
    req: SettingsUpdate, actor: str = Depends(_require_admin)
):
    db = get_db()
    try:
        update_items = req.model_dump(exclude_none=True)
        changed = _apply_settings_updates(db, update_items, actor)
        db.commit()
        return {"status": "ok", "changed": changed}
    finally:
        db.close()


def _system_settings_payload(actor: str) -> dict:
    settings_map = admin_get_settings(actor)
    settings = [
        {"key": key, "value": value, "category": "", "description": ""}
        for key, value in sorted(settings_map.items())
        if not key.endswith("_set")
    ]
    runtime_status = {
        "current_version": settings_map.get("current_version", APP_CURRENT_VERSION),
        "current_version_name": settings_map.get(
            "current_version_name", APP_CURRENT_VERSION
        ),
        "current_version_code": settings_map.get(
            "current_version_code", APP_CURRENT_VERSION_CODE
        ),
        "app_package_name": settings_map.get("app_package_name", APP_PACKAGE_NAME),
        "version_options": settings_map.get("version_options", []),
        "force_update_required": settings_map.get("force_update_required", False),
        "force_app_update_enabled": settings_map.get(
            "force_app_update_enabled", False
        ),
        "latest_version": settings_map.get("latest_version", ""),
        "latest_version_name": settings_map.get("latest_version_name", ""),
        "latest_version_code": settings_map.get("latest_version_code", 0),
        "minimum_supported_version": settings_map.get(
            "minimum_supported_version", ""
        ),
        "update_notes": settings_map.get("update_notes", ""),
        "release_notes": settings_map.get("release_notes", ""),
        "update_download_url": settings_map.get("update_download_url", ""),
        "download_url": settings_map.get("download_url", ""),
        "force_relogin_enabled": settings_map.get("force_relogin_enabled", False),
        "force_relogin_issued_at": settings_map.get("force_relogin_issued_at", ""),
        "registration_email_required": settings_map.get(
            "registration_email_required", False
        ),
        "allow_public_registration": settings_map.get(
            "allow_public_registration",
            settings_map.get("registration_enabled", True),
        ),
        "registration_invite_required": settings_map.get(
            "registration_invite_required",
            settings_map.get("invite_code_required", False),
        ),
    }
    return {
        "settings": settings,
        "runtime_status": runtime_status,
        "local_backups": [],
    }


@app.get("/api/admin/system-settings")
def admin_system_settings(actor: str = Depends(_require_admin)):
    return _system_settings_payload(actor)


@app.post("/api/admin/system-settings")
@app.patch("/api/admin/system-settings")
@app.put("/api/admin/system-settings")
def admin_update_system_settings(
    payload: dict = Body(default={}), actor: str = Depends(_require_admin)
):
    update_items = {
        str(key): value
        for key, value in (payload or {}).items()
        if value is not None and not str(key).startswith("_")
    }
    db = get_db()
    try:
        _apply_settings_updates(db, update_items, actor)
        db.commit()
    finally:
        db.close()
    return _system_settings_payload(actor)


# ---- Groups / roles / permissions ----


def _clean_entity_id(value: Optional[str], fallback_prefix: str) -> str:
    text = (value or "").strip()
    if not text:
        return f"{fallback_prefix}_{secrets.token_hex(6)}"
    text = re.sub(r"[^a-zA-Z0-9_.:-]+", "_", text)
    return text[:64] or f"{fallback_prefix}_{secrets.token_hex(6)}"


def _bounded_int(value, default: int, minimum: int = 0, maximum: int = 1000000) -> int:
    try:
        parsed = int(value)
    except Exception:
        parsed = default
    return max(minimum, min(parsed, maximum))


def _group_default_time_coins(db, group_id: Optional[str]) -> int:
    clean_group_id = (group_id or "").strip() or "group_default"
    row = db.execute(
        "SELECT default_time_coins FROM admin_groups WHERE id=? AND is_active=1",
        (clean_group_id,),
    ).fetchone()
    if row is not None:
        return _bounded_int(row["default_time_coins"], 100)
    return _bounded_int(_setting_get(db, "default_registration_coins", 100), 100)


def _ensure_active_group(db, group_id: str):
    row = db.execute(
        "SELECT is_active FROM admin_groups WHERE id=?",
        (group_id,),
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=400, detail="用户组不存在")
    if not bool(row["is_active"]):
        raise HTTPException(status_code=400, detail="用户组已停用")
    return row


def _admin_group_row(db, row) -> dict:
    user_count = db.execute(
        "SELECT COUNT(*) AS c FROM users WHERE group_id=?",
        (row["id"],),
    ).fetchone()["c"]
    return {
        "id": row["id"],
        "name": row["name"],
        "description": row["description"] or "",
        "default_time_coins": int(row["default_time_coins"] or 0),
        "is_active": bool(row["is_active"]),
        "user_count": int(user_count or 0),
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


def _admin_role_row(db, row) -> dict:
    role_id = row["id"]
    permissions = (
        []
        if role_id == "role_user"
        else _admin_permissions_for_response(
            row["permissions"], is_admin=role_id == "role_admin"
        )
    )
    user_count = db.execute(
        "SELECT COUNT(*) AS c FROM users WHERE role_id=?",
        (row["id"],),
    ).fetchone()["c"]
    return {
        "id": row["id"],
        "name": row["name"],
        "description": row["description"] or "",
        "permissions": permissions,
        "permission_codes": permissions,
        "is_active": bool(row["is_active"]),
        "user_count": int(user_count or 0),
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


@app.get("/api/admin/permissions")
@app.get("/api/admin/permission-codes")
@app.get("/api/admin/permission_codes")
@app.get("/api/admin/user-permissions")
@app.get("/api/admin/user_permissions")
def admin_permissions(actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        _ensure_admin_any_permission(db, actor, ("permissions", "roles", "users"))
        return _admin_permission_catalog()
    finally:
        db.close()


@app.get("/api/admin/groups")
@app.get("/api/admin/user-groups")
@app.get("/api/admin/user_groups")
@app.get("/api/admin/userGroups")
def admin_groups(
    actor: str = Depends(_require_admin),
    limit: Optional[int] = Query(None, ge=1, le=500),
    offset: Optional[int] = Query(None, ge=0),
):
    db = get_db()
    try:
        _ensure_admin_any_permission(db, actor, ("groups", "users", "coins"))
        if limit is not None or offset is not None:
            safe_limit, safe_offset = _admin_page_window(
                limit if limit is not None else 50,
                offset if offset is not None else 0,
            )
            total = db.execute("SELECT COUNT(*) AS c FROM admin_groups").fetchone()["c"]
            rows = db.execute(
                """
                SELECT *
                FROM admin_groups
                ORDER BY is_active DESC, id='group_default' DESC, lower(name) ASC
                LIMIT ? OFFSET ?
                """,
                (safe_limit, safe_offset),
            ).fetchall()
            return _admin_page_response(
                [_admin_group_row(db, row) for row in rows],
                total,
                safe_limit,
                safe_offset,
            )
        rows = db.execute(
            "SELECT * FROM admin_groups ORDER BY is_active DESC, id='group_default' DESC, lower(name) ASC"
        ).fetchall()
        return [_admin_group_row(db, row) for row in rows]
    finally:
        db.close()


@app.post("/api/admin/groups")
@app.post("/api/admin/user-groups")
@app.post("/api/admin/user_groups")
@app.post("/api/admin/userGroups")
def admin_create_group(req: AdminGroupUpsert, actor: str = Depends(_require_admin)):
    return _admin_save_group(None, req, actor)


@app.put("/api/admin/groups/{group_id}")
@app.patch("/api/admin/groups/{group_id}")
@app.put("/api/admin/user-groups/{group_id}")
@app.patch("/api/admin/user-groups/{group_id}")
@app.put("/api/admin/user_groups/{group_id}")
@app.patch("/api/admin/user_groups/{group_id}")
@app.put("/api/admin/userGroups/{group_id}")
@app.patch("/api/admin/userGroups/{group_id}")
def admin_update_group(
    group_id: str, req: AdminGroupUpsert, actor: str = Depends(_require_admin)
):
    return _admin_save_group(group_id, req, actor)


@app.delete("/api/admin/groups/{group_id}")
@app.delete("/api/admin/user-groups/{group_id}")
@app.delete("/api/admin/user_groups/{group_id}")
@app.delete("/api/admin/userGroups/{group_id}")
def admin_delete_group(group_id: str, actor: str = Depends(_require_admin)):
    target_id = _clean_entity_id(group_id, "group")
    if target_id == "group_default":
        raise HTTPException(status_code=400, detail="默认用户组不能删除")
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "groups")
        row = db.execute("SELECT id FROM admin_groups WHERE id=?", (target_id,)).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="用户组不存在")
        reassigned = db.execute(
            "SELECT COUNT(*) AS c FROM users WHERE group_id=?",
            (target_id,),
        ).fetchone()["c"]
        db.execute(
            "UPDATE users SET group_id='group_default' WHERE group_id=?",
            (target_id,),
        )
        db.execute("DELETE FROM admin_groups WHERE id=?", (target_id,))
        _audit(
            db,
            actor,
            _get_username(db, actor),
            "group.delete",
            target=target_id,
            detail=json.dumps(
                {"reassigned_users": int(reassigned or 0)},
                ensure_ascii=False,
            ),
        )
        db.commit()
        return {
            "status": "ok",
            "deleted": 1,
            "id": target_id,
            "reassigned_users": int(reassigned or 0),
            "fallback_group_id": "group_default",
        }
    finally:
        db.close()


def _admin_save_group(group_id: Optional[str], req: AdminGroupUpsert, actor: str):
    name = _clean_short_text(req.name, 64, "用户组名称")
    description = _clean_short_text(req.description or "", 280, "用户组描述")
    target_id = _clean_entity_id(group_id or name, "group")
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "groups")
        existing_row = db.execute(
            "SELECT * FROM admin_groups WHERE id=?", (target_id,)
        ).fetchone()
        exists = existing_row is not None

        def group_int(field: str, fallback: int, *aliases: str) -> int:
            value = getattr(req, field)
            if value is None:
                for alias in aliases:
                    value = getattr(req, alias)
                    if value is not None:
                        break
            if value is not None:
                return _bounded_int(value, fallback)
            if existing_row is not None:
                return _bounded_int(existing_row[field], fallback)
            return fallback

        default_time_coins = group_int("default_time_coins", 100, "defaultTimeCoins")
        is_active_value = req.is_active
        if is_active_value is None:
            is_active_value = req.isActive
        if is_active_value is None and existing_row is not None:
            is_active_value = bool(existing_row["is_active"])
        values = (
            target_id,
            name,
            description,
            default_time_coins,
            1 if is_active_value is not False else 0,
        )
        if not exists:
            db.execute(
                """
                INSERT INTO admin_groups(
                    id, name, description, default_time_coins, is_active
                ) VALUES(?,?,?,?,?)
                """,
                values,
            )
        else:
            db.execute(
                """
                UPDATE admin_groups
                SET name=?, description=?, default_time_coins=?,
                    is_active=?, updated_at=datetime('now')
                WHERE id=?
                """,
                (*values[1:], target_id),
            )
        if target_id == "group_default":
            _setting_set(db, "default_registration_coins", default_time_coins)
        _audit(db, actor, _get_username(db, actor), "group.save", target=target_id)
        db.commit()
        row = db.execute("SELECT * FROM admin_groups WHERE id=?", (target_id,)).fetchone()
        return _admin_group_row(db, row)
    finally:
        db.close()


@app.get("/api/admin/roles")
@app.get("/api/admin/user-roles")
@app.get("/api/admin/user_roles")
@app.get("/api/admin/admin-roles")
@app.get("/api/admin/admin_roles")
def admin_roles(actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        _ensure_admin_any_permission(db, actor, ("roles", "users"))
        rows = db.execute(
            "SELECT * FROM admin_roles ORDER BY id='role_admin' DESC, id='role_user' DESC, lower(name) ASC"
        ).fetchall()
        return [_admin_role_row(db, row) for row in rows]
    finally:
        db.close()


@app.post("/api/admin/roles")
@app.post("/api/admin/user-roles")
@app.post("/api/admin/user_roles")
@app.post("/api/admin/admin-roles")
@app.post("/api/admin/admin_roles")
def admin_create_role(req: AdminRoleUpsert, actor: str = Depends(_require_admin)):
    return _admin_save_role(None, req, actor)


@app.put("/api/admin/roles/{role_id}")
@app.patch("/api/admin/roles/{role_id}")
@app.put("/api/admin/user-roles/{role_id}")
@app.patch("/api/admin/user-roles/{role_id}")
@app.put("/api/admin/user_roles/{role_id}")
@app.patch("/api/admin/user_roles/{role_id}")
@app.put("/api/admin/admin-roles/{role_id}")
@app.patch("/api/admin/admin-roles/{role_id}")
@app.put("/api/admin/admin_roles/{role_id}")
@app.patch("/api/admin/admin_roles/{role_id}")
def admin_update_role(
    role_id: str, req: AdminRoleUpsert, actor: str = Depends(_require_admin)
):
    return _admin_save_role(role_id, req, actor)


def _admin_save_role(role_id: Optional[str], req: AdminRoleUpsert, actor: str):
    name = _clean_short_text(req.name, 64, "角色名称")
    description = _clean_short_text(req.description or "", 280, "角色描述")
    target_id = _clean_entity_id(role_id or name, "role")
    permissions = _normalize_admin_permissions(
        req.permission_codes or req.permissions or []
    )
    if target_id == "role_user":
        permissions = []
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "roles")
        _ensure_admin_can_assign_permissions(db, actor, permissions)
        exists = db.execute(
            "SELECT 1 FROM admin_roles WHERE id=?", (target_id,)
        ).fetchone()
        values = (
            target_id,
            name,
            description,
            json.dumps(permissions, ensure_ascii=False),
            1 if req.is_active is not False else 0,
        )
        if exists is None:
            db.execute(
                "INSERT INTO admin_roles(id, name, description, permissions, is_active) VALUES(?,?,?,?,?)",
                values,
            )
        else:
            db.execute(
                """
                UPDATE admin_roles
                SET name=?, description=?, permissions=?, is_active=?,
                    updated_at=datetime('now')
                WHERE id=?
                """,
                (*values[1:], target_id),
            )
        _audit(db, actor, _get_username(db, actor), "role.save", target=target_id)
        db.commit()
        row = db.execute("SELECT * FROM admin_roles WHERE id=?", (target_id,)).fetchone()
        return _admin_role_row(db, row)
    finally:
        db.close()


# ---- Users ----


@app.post("/api/admin/users")
def admin_create_user(req: UserCreate, actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "users")
        username = _clean_username(req.username)
        password = _clean_password(req.password or secrets.token_urlsafe(12))
        email = _clean_email(req.email)
        display_name_value = req.display_name
        if display_name_value is None:
            display_name_value = req.displayName
        display_name = _clean_short_text(display_name_value, 64, "昵称")
        is_admin = bool(req.is_admin if req.is_admin is not None else req.isAdmin)
        is_disabled = bool(
            req.is_disabled if req.is_disabled is not None else req.isDisabled
        )
        group_id_value = req.group_id if req.group_id is not None else req.groupId
        role_id_value = req.role_id if req.role_id is not None else req.roleId
        admin_permissions_value = (
            req.admin_permissions
            if req.admin_permissions is not None
            else req.adminPermissions
        )
        group_id = (group_id_value or "").strip() or "group_default"
        role_id = (role_id_value or "").strip() or ("role_admin" if is_admin else "role_user")
        if group_id_value is not None:
            _ensure_admin_any_permission(db, actor, ("groups", "coins"))
        _ensure_active_group(db, group_id)
        if db.execute("SELECT 1 FROM admin_roles WHERE id=?", (role_id,)).fetchone() is None:
            raise HTTPException(status_code=400, detail="角色不存在")
        if is_admin or admin_permissions_value is not None or role_id != "role_user":
            _ensure_admin_management_permission(db, actor)
        _ensure_account_unique(db, username=username, email=email)
        user_id = secrets.token_hex(16)
        permissions = (
            _normalize_admin_permissions(admin_permissions_value)
            if is_admin
            else []
        )
        if is_admin and not permissions:
            permissions = _admin_role_permissions(db, role_id)
        _ensure_admin_can_assign_permissions(db, actor, permissions)
        _ensure_admin_can_assign_role(db, actor, role_id)
        db.execute(
            """
            INSERT INTO users(
                id, username, email, email_verified, password_hash, display_name,
                group_id, role_id, is_admin, admin_permissions, is_disabled
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                user_id,
                username,
                email,
                1 if email else 0,
                _hash_password(password),
                display_name,
                group_id,
                role_id,
                1 if is_admin else 0,
                json.dumps(permissions, ensure_ascii=False),
                1 if is_disabled else 0,
            ),
        )
        db.execute("INSERT INTO sync_data(user_id) VALUES(?)", (user_id,))
        _grant_registration_coins(
            db,
            user_id,
            _group_default_time_coins(db, group_id),
        )
        _ensure_private_workspace(db, user_id)
        _audit(db, actor, _get_username(db, actor), "user.create", target=user_id)
        db.commit()
        row = db.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        return _user_response(row, db=db)
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=409, detail="用户名或邮箱已被使用")
    finally:
        db.close()


@app.get("/api/admin/users")
def admin_list_users(
    _: str = Depends(_require_admin),
    q: Optional[str] = None,
    status: Optional[str] = None,
    online: Optional[bool] = None,
    sort: str = "created_desc",
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    limit, offset = _admin_page_window(limit, offset)
    db = get_db()
    try:
        actor = _
        _ensure_admin_any_permission(db, actor, ("users", "coins"))
        where, params = _user_admin_filters(q=q, status=status)
        if online is not None:
            online_ids = sorted(_online_user_ids())
            placeholders = ",".join("?" for _ in online_ids)
            online_clause = (
                f"u.id IN ({placeholders})"
                if online
                else (
                    f"u.id NOT IN ({placeholders})"
                    if online_ids
                    else "1=1"
                )
            )
            if online and not online_ids:
                online_clause = "1=0"
            where = (
                f"{where} AND {online_clause}"
                if where
                else f"WHERE {online_clause}"
            )
            params = [*params, *online_ids]
        order_by = _user_admin_order_by(sort)
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM users u {where}", params
        ).fetchone()["c"]
        rows = db.execute(
            "SELECT u.id, u.username, u.email, u.email_verified, u.display_name, "
            "u.group_id, u.role_id, u.is_admin, u.admin_permissions, u.is_disabled, "
            "u.created_at, u.last_login_at, u.last_active_at, sd.virtual_rewards, "
            "(SELECT COUNT(*) FROM feedback WHERE user_id=u.id) AS fb_count "
            f"FROM users u LEFT JOIN sync_data sd ON sd.user_id=u.id {where} "
            f"ORDER BY {order_by} LIMIT ? OFFSET ?",
            (*params, limit, offset),
        ).fetchall()
        online_user_ids = _online_user_ids(r["id"] for r in rows)
        items = []
        for r in rows:
            rewards_text = r["virtual_rewards"] if r["virtual_rewards"] else "{}"
            coin_balance, lifetime_coins = _virtual_rewards_summary(
                rewards_text
            )
            quota_aliases = _quota_aliases_from_rewards(rewards_text)
            is_admin = bool(r["is_admin"])
            items.append(
                {
                "id": r["id"],
                "user_id": r["id"],
                "username": r["username"],
                "email": r["email"],
                "email_verified": bool(r["email_verified"]),
                "display_name": r["display_name"],
                "group_id": r["group_id"] or "group_default",
                "role_id": r["role_id"] or ("role_admin" if is_admin else "role_user"),
                "group": {"id": r["group_id"] or "group_default"},
                "role": {"id": r["role_id"] or ("role_admin" if is_admin else "role_user")},
                "is_admin": is_admin,
                "admin_permissions": _merged_admin_permissions(r, db=db),
                "permissions": _merged_admin_permissions(r, db=db),
                "is_disabled": bool(r["is_disabled"]),
                "is_active": not bool(r["is_disabled"]),
                "created_at": r["created_at"],
                "last_login_at": r["last_login_at"],
                "last_active_at": r["last_active_at"],
                "feedback_count": r["fb_count"],
                "online": r["id"] in online_user_ids,
                "coin_balance": coin_balance,
                "lifetime_coins": lifetime_coins,
                **quota_aliases,
                }
            )
        return _admin_page_response(items, total, limit, offset)
    finally:
        db.close()


@app.get("/api/admin/users/export.csv")
def export_users_csv(
    actor: str = Depends(_require_admin),
    q: Optional[str] = None,
    status: Optional[str] = None,
    online: Optional[bool] = None,
    sort: str = "created_desc",
    limit: int = Query(5000, ge=1, le=20000),
):
    limit, _offset = _admin_page_window(limit, 0, default_limit=5000, max_limit=20000)
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "users")
        where, params = _user_admin_filters(q=q, status=status)
        if online is not None:
            online_ids = sorted(_online_user_ids())
            placeholders = ",".join("?" for _ in online_ids)
            online_clause = (
                f"u.id IN ({placeholders})"
                if online
                else (
                    f"u.id NOT IN ({placeholders})"
                    if online_ids
                    else "1=1"
                )
            )
            if online and not online_ids:
                online_clause = "1=0"
            where = (
                f"{where} AND {online_clause}"
                if where
                else f"WHERE {online_clause}"
            )
            params = [*params, *online_ids]
        order_by = _user_admin_order_by(sort)
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM users u {where}", params
        ).fetchone()["c"]
        rows = db.execute(
            "SELECT u.id, u.username, u.email, u.display_name, "
            "u.is_admin, u.is_disabled, u.created_at, u.last_login_at, u.last_active_at, "
            "(SELECT COUNT(*) FROM feedback WHERE user_id=u.id) AS fb_count "
            f"FROM users u {where} ORDER BY {order_by} LIMIT ?",
            (*params, limit),
        ).fetchall()
        buffer = io.StringIO()
        writer = csv.writer(buffer)
        writer.writerow(
            [
                "user_id",
                "username",
                "email",
                "display_name",
                "is_admin",
                "is_disabled",
                "created_at",
                "last_login_at",
                "last_active_at",
                "feedback_count",
            ]
        )
        for row in rows:
            writer.writerow(
                [
                    row["id"],
                    _csv_safe(row["username"]),
                    _csv_safe(row["email"]),
                    _csv_safe(row["display_name"]),
                    int(bool(row["is_admin"])),
                    int(bool(row["is_disabled"])),
                    _csv_safe(row["created_at"]),
                    _csv_safe(row["last_login_at"]),
                    _csv_safe(row["last_active_at"]),
                    int(row["fb_count"] or 0),
                ]
            )
        _audit(
            db,
            actor,
            _get_username(db, actor),
            "user.export",
            detail=json.dumps(
                {
                    "status": status or "",
                    "online": online,
                    "q": q or "",
                    "sort": sort,
                    "rows": len(rows),
                    "total": int(total or 0),
                },
                ensure_ascii=False,
            ),
        )
        db.commit()
        content = "\ufeff" + buffer.getvalue()
        filename = f"duoyi_users_{_utc_now().strftime('%Y%m%d_%H%M%S')}.csv"
        headers = {
            "Content-Disposition": f'attachment; filename="{filename}"',
            "X-Total-Count": str(int(total or 0)),
            "X-Exported-Count": str(len(rows)),
        }
        return StreamingResponse(
            iter([content]),
            media_type="text/csv; charset=utf-8",
            headers=headers,
        )
    finally:
        db.close()


@app.post("/api/admin/users/bulk-status")
@app.post("/api/admin/users/batch-status")
@app.patch("/api/admin/users/bulk-status")
@app.patch("/api/admin/users/batch-status")
def admin_bulk_update_user_status(
    req: UserBulkStatus, actor: str = Depends(_require_admin)
):
    raw_user_ids = req.user_ids or req.userIds or req.ids or []
    if req.id:
        raw_user_ids = [*raw_user_ids, req.id]
    user_ids = list(dict.fromkeys(str(user_id).strip() for user_id in raw_user_ids))
    user_ids = [user_id for user_id in user_ids if user_id]
    if not user_ids:
        raise HTTPException(status_code=400, detail="请选择要操作的用户")
    is_disabled = req.is_disabled
    if is_disabled is None:
        is_disabled = req.isDisabled
    if is_disabled is None:
        is_disabled = req.disabled
    if is_disabled is None and req.is_active is not None:
        is_disabled = not bool(req.is_active)
    if is_disabled is None and req.isActive is not None:
        is_disabled = not bool(req.isActive)
    if is_disabled is None:
        raise HTTPException(status_code=400, detail="请选择要设置的账号状态")
    is_disabled = bool(is_disabled)
    if actor in user_ids and is_disabled:
        raise HTTPException(status_code=400, detail="Cannot disable yourself")
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "users")
        placeholders = ",".join("?" for _ in user_ids)
        rows = db.execute(
            f"SELECT id, username, is_admin, is_disabled FROM users WHERE id IN ({placeholders})",
            user_ids,
        ).fetchall()
        found_ids = {row["id"] for row in rows}
        missing_ids = [user_id for user_id in user_ids if user_id not in found_ids]
        if missing_ids:
            raise HTTPException(status_code=404, detail="User not found")
        if is_disabled:
            active_admins = db.execute(
                "SELECT COUNT(*) AS c FROM users WHERE is_admin=1 AND is_disabled=0"
            ).fetchone()["c"]
            disabling_active_admins = sum(
                1
                for row in rows
                if row["is_admin"] and not row["is_disabled"]
            )
            if active_admins - disabling_active_admins <= 0:
                raise HTTPException(
                    status_code=400,
                    detail="Cannot disable the last active admin",
                )
        db.execute(
            f"UPDATE users SET is_disabled=? WHERE id IN ({placeholders})",
            (1 if is_disabled else 0, *user_ids),
        )
        if is_disabled:
            for user_id in user_ids:
                _revoke_user_token(user_id, db)
        _audit(
            db,
            actor,
            _get_username(db, actor),
            "user.bulk_status",
            target=",".join(user_ids[:20]),
            detail=json.dumps(
                {
                    "is_disabled": is_disabled,
                    "count": len(user_ids),
                },
                ensure_ascii=False,
            ),
        )
        db.commit()
        return {"status": "ok", "updated": len(user_ids)}
    finally:
        db.close()


@app.post("/api/admin/users/{user_id}")
@app.patch("/api/admin/users/{user_id}")
@app.put("/api/admin/users/{user_id}")
def admin_update_user(
    user_id: str, req: UserUpdate, actor: str = Depends(_require_admin)
):
    is_admin_value = req.is_admin if req.is_admin is not None else req.isAdmin
    is_disabled_value = (
        req.is_disabled if req.is_disabled is not None else req.isDisabled
    )
    new_password_value = req.new_password or req.newPassword or req.password
    admin_permissions_value = (
        req.admin_permissions
        if req.admin_permissions is not None
        else req.adminPermissions
    )
    group_id_value = req.group_id if req.group_id is not None else req.groupId
    role_id_value = req.role_id if req.role_id is not None else req.roleId
    coin_payload = UserCoinAdjustment(
        delta=req.delta,
        reason=req.reason,
        coins=req.coins,
        amount=req.amount,
        balance=req.balance,
        coin_balance=req.coin_balance,
        coinBalance=req.coinBalance,
        target_balance=req.target_balance,
        targetBalance=req.targetBalance,
        quota=req.quota,
        time_coins=req.time_coins,
        time_coin_balance=req.time_coin_balance,
        timeCoins=req.timeCoins,
        timeCoinBalance=req.timeCoinBalance,
        credit_balance=req.credit_balance,
        creditBalance=req.creditBalance,
        credits=req.credits,
        coin_delta=req.coin_delta,
        coinDelta=req.coinDelta,
        time_coin_delta=req.time_coin_delta,
        timeCoinDelta=req.timeCoinDelta,
    )
    has_coin_adjustment = any(
        value is not None
        for value in (
            coin_payload.delta,
            coin_payload.coins,
            coin_payload.amount,
            coin_payload.balance,
            coin_payload.coin_balance,
            coin_payload.coinBalance,
            coin_payload.target_balance,
            coin_payload.targetBalance,
            coin_payload.quota,
            coin_payload.time_coins,
            coin_payload.time_coin_balance,
            coin_payload.timeCoins,
            coin_payload.timeCoinBalance,
            coin_payload.credit_balance,
            coin_payload.creditBalance,
            coin_payload.credits,
            coin_payload.coin_delta,
            coin_payload.coinDelta,
            coin_payload.time_coin_delta,
            coin_payload.timeCoinDelta,
        )
    )
    has_user_update = any(
        value is not None
        for value in (
            is_admin_value,
            is_disabled_value,
            new_password_value,
            admin_permissions_value,
            group_id_value,
            role_id_value,
        )
    )
    if has_coin_adjustment and has_user_update:
        raise HTTPException(status_code=400, detail="用户资料和时光币调整请分开提交")
    if has_coin_adjustment:
        return _admin_adjust_user_coins_impl(user_id, coin_payload, actor)

    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "users")
        row = db.execute(
            "SELECT id, username, is_admin, is_disabled, admin_permissions, group_id, role_id FROM users WHERE id=?",
            (user_id,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="User not found")
        if has_coin_adjustment:
            _ensure_admin_permission(db, actor, "coins")
        if user_id == actor and is_disabled_value is True:
            raise HTTPException(status_code=400, detail="Cannot disable yourself")

        requested_role_id = (
            (role_id_value or "").strip()
            if role_id_value is not None
            else (row["role_id"] or "")
        )
        touches_admin_management = (
            is_admin_value is not None
            or admin_permissions_value is not None
            or (
                role_id_value is not None
                and (
                    requested_role_id != "role_user"
                    or bool(row["is_admin"])
                    or bool(is_admin_value)
                )
            )
        )
        if touches_admin_management:
            _ensure_admin_management_permission(db, actor)

        # Safeguard: can't demote or disable the last admin
        if is_admin_value is False and row["is_admin"] and not row["is_disabled"]:
            admins = db.execute(
                "SELECT COUNT(*) AS c FROM users WHERE is_admin=1 AND is_disabled=0"
            ).fetchone()["c"]
            if admins <= 1:
                raise HTTPException(
                    status_code=400, detail="Cannot demote the last active admin"
                )
        if is_disabled_value is True and row["is_admin"]:
            admins = db.execute(
                "SELECT COUNT(*) AS c FROM users WHERE is_admin=1 AND is_disabled=0"
            ).fetchone()["c"]
            if admins <= 1:
                raise HTTPException(
                    status_code=400, detail="Cannot disable the last active admin"
                )

        next_is_admin = (
            bool(row["is_admin"]) if is_admin_value is None else bool(is_admin_value)
        )
        next_permissions: Optional[list[str]] = None
        if admin_permissions_value is not None:
            next_permissions = _normalize_admin_permissions(admin_permissions_value)
        elif is_admin_value is True and not _admin_permissions_from_text(row["admin_permissions"]):
            target_role_id = (
                (role_id_value or "").strip()
                if role_id_value is not None
                else "role_admin"
            )
            next_permissions = _admin_role_permissions(db, target_role_id)
        elif is_admin_value is False:
            next_permissions = []
        if next_permissions is not None:
            _ensure_admin_can_assign_permissions(db, actor, next_permissions)
        if is_admin_value is not None and role_id_value is None:
            _ensure_admin_can_assign_role(
                db,
                actor,
                "role_admin" if is_admin_value else "role_user",
            )

        if is_admin_value is not None:
            db.execute(
                "UPDATE users SET is_admin=? WHERE id=?",
                (1 if is_admin_value else 0, user_id),
            )
            if role_id_value is None:
                db.execute(
                    "UPDATE users SET role_id=? WHERE id=?",
                    ("role_admin" if is_admin_value else "role_user", user_id),
                )
        if next_permissions is not None:
            db.execute(
                "UPDATE users SET admin_permissions=? WHERE id=?",
                (
                    json.dumps(next_permissions if next_is_admin else [], ensure_ascii=False),
                    user_id,
                ),
            )
        if is_disabled_value is not None:
            db.execute(
                "UPDATE users SET is_disabled=? WHERE id=?",
                (1 if is_disabled_value else 0, user_id),
            )
            if is_disabled_value:
                _revoke_user_token(user_id, db)
        if group_id_value is not None:
            _ensure_admin_any_permission(db, actor, ("groups", "coins"))
            group_id = (group_id_value or "").strip() or "group_default"
            _ensure_active_group(db, group_id)
            previous_group_id = row["group_id"] or "group_default"
            db.execute("UPDATE users SET group_id=? WHERE id=?", (group_id, user_id))
            if group_id != previous_group_id:
                _grant_group_assignment_coins(db, user_id, group_id)
        if role_id_value is not None:
            role_id = (role_id_value or "").strip() or ("role_admin" if next_is_admin else "role_user")
            if db.execute("SELECT 1 FROM admin_roles WHERE id=?", (role_id,)).fetchone() is None:
                raise HTTPException(status_code=400, detail="角色不存在")
            _ensure_admin_can_assign_role(db, actor, role_id)
            db.execute("UPDATE users SET role_id=? WHERE id=?", (role_id, user_id))
        next_password = new_password_value
        if next_password:
            db.execute(
                "UPDATE users SET password_hash=? WHERE id=?",
                (_hash_password(next_password), user_id),
            )
            _revoke_user_token(user_id, db)  # force re-login on every device

        coin_adjustment_result = None
        if has_coin_adjustment:
            coin_adjustment_result = _admin_adjust_user_coins_in_db(
                db,
                user_id,
                coin_payload,
                actor,
            )

        _audit(
            db,
            actor,
            _get_username(db, actor),
            "user.update",
            target=user_id,
            detail=json.dumps(req.model_dump(exclude_none=True)),
        )
        db.commit()
        if coin_adjustment_result is not None:
            return coin_adjustment_result
        fresh = db.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        return _user_response(fresh, db=db)
    finally:
        db.close()


def _coin_adjustment_delta(req: UserCoinAdjustment, current_balance: int) -> int:
    if req.delta is not None:
        return int(req.delta)
    if req.coin_delta is not None:
        return int(req.coin_delta)
    if req.coinDelta is not None:
        return int(req.coinDelta)
    if req.time_coin_delta is not None:
        return int(req.time_coin_delta)
    if req.timeCoinDelta is not None:
        return int(req.timeCoinDelta)
    if req.coins is not None:
        return int(req.coins)
    if req.amount is not None:
        return int(req.amount)
    if req.balance is not None:
        return int(req.balance) - current_balance
    if req.coin_balance is not None:
        return int(req.coin_balance) - current_balance
    if req.coinBalance is not None:
        return int(req.coinBalance) - current_balance
    if req.target_balance is not None:
        return int(req.target_balance) - current_balance
    if req.targetBalance is not None:
        return int(req.targetBalance) - current_balance
    if req.quota is not None:
        return int(req.quota) - current_balance
    if req.time_coins is not None:
        return int(req.time_coins) - current_balance
    if req.time_coin_balance is not None:
        return int(req.time_coin_balance) - current_balance
    if req.timeCoins is not None:
        return int(req.timeCoins) - current_balance
    if req.timeCoinBalance is not None:
        return int(req.timeCoinBalance) - current_balance
    if req.credit_balance is not None:
        return int(req.credit_balance) - current_balance
    if req.creditBalance is not None:
        return int(req.creditBalance) - current_balance
    if req.credits is not None:
        return int(req.credits) - current_balance
    raise HTTPException(status_code=400, detail="调整数量不能为空")


def _admin_adjust_user_coins_impl(
    user_id: str, req: UserCoinAdjustment, actor: str
):
    db = get_db()
    try:
        result = _admin_adjust_user_coins_in_db(db, user_id, req, actor)
        db.commit()
        return result
    finally:
        db.close()


def _admin_adjust_user_coins_in_db(
    db,
    user_id: str,
    req: UserCoinAdjustment,
    actor: str,
):
    _ensure_admin_permission(db, actor, "coins")
    user = db.execute(
        "SELECT id, username FROM users WHERE id=?", (user_id,)
    ).fetchone()
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    db.execute("INSERT OR IGNORE INTO sync_data(user_id) VALUES(?)", (user_id,))
    row = db.execute(
        "SELECT virtual_rewards, sync_version FROM sync_data WHERE user_id=?",
        (user_id,),
    ).fetchone()
    rewards = _json_object(row["virtual_rewards"] if row else "{}")

    def _num(value, fallback=0) -> int:
        try:
            return int(value)
        except Exception:
            return fallback

    now = _utc_now_text()
    old_balance = _num(rewards.get("balance"))
    delta = _coin_adjustment_delta(req, old_balance)
    if delta == 0:
        raise HTTPException(status_code=400, detail="调整数量不能为 0")
    if abs(delta) > 1000000:
        raise HTTPException(status_code=400, detail="单次调整不能超过 1000000")
    old_lifetime = _num(rewards.get("lifetime"), old_balance)
    balance = max(0, old_balance + delta)
    applied_delta = balance - old_balance
    if applied_delta == 0:
        raise HTTPException(status_code=400, detail="余额已为 0，不能继续扣减")
    lifetime = old_lifetime + max(0, applied_delta)
    reason = (req.reason or "").strip() or "管理员调整"
    ledger = rewards.get("ledger")
    if not isinstance(ledger, list):
        ledger = []
    entry = {
        "id": f"admin:{int(_utc_now().timestamp() * 1000000)}:{secrets.token_hex(4)}",
        "title": "管理员调整",
        "coins": applied_delta,
        "reason": reason,
        "awardedAt": now,
    }
    rewards.update(
        {
            "balance": balance,
            "lifetime": max(lifetime, balance),
            "ledger": [entry, *[item for item in ledger if isinstance(item, dict)]][:50],
            "updatedAt": now,
        }
    )
    next_sync_version = int(row["sync_version"] or 0) + 1 if row else 1
    db.execute(
        """
        UPDATE sync_data
        SET virtual_rewards=?, sync_version=?, updated_at=?
        WHERE user_id=?
        """,
        (
            json.dumps(rewards, ensure_ascii=False),
            next_sync_version,
            now,
            user_id,
        ),
    )
    _audit(
        db,
        actor,
        _get_username(db, actor),
        "user.coins_adjust",
        target=user_id,
        detail=json.dumps(
            {
                "delta": delta,
                "applied_delta": applied_delta,
                "reason": reason,
                "balance": balance,
                "lifetime": rewards["lifetime"],
            },
            ensure_ascii=False,
        ),
    )
    return {
        "status": "ok",
        "balance": balance,
        "lifetime": rewards["lifetime"],
        "ledger_entry": entry,
        "server_version": next_sync_version,
    }


def _grant_registration_coins(db, user_id: str, coins: int) -> None:
    _grant_default_coins(
        db,
        user_id,
        coins,
        entry_prefix="register",
        title="新用户默认额度",
        reason="默认用户组额度",
    )


def _grant_group_assignment_coins(db, user_id: str, group_id: str) -> None:
    coins = _group_default_time_coins(db, group_id)
    _grant_default_coins(
        db,
        user_id,
        coins,
        entry_prefix=f"group:{group_id}",
        title="用户组默认额度",
        reason="分配用户组额度",
    )


def _grant_default_coins(
    db,
    user_id: str,
    coins: int,
    *,
    entry_prefix: str,
    title: str,
    reason: str,
) -> None:
    # Keep the helper and legacy configuration contract, without automatic grants.
    # Historical rewards and manual compatibility APIs retain their original data.
    return


@app.post("/api/admin/welfare-grants")
def admin_create_welfare_grant(
    req: WelfareGrantCreate, actor: str = Depends(_require_admin)
):
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "coins")
        generate_bonus = max(0, int(req.generate_bonus or 0))
        edit_bonus = max(0, int(req.edit_bonus or 0))
        coins = generate_bonus + edit_bonus
        if coins <= 0:
            raise HTTPException(status_code=400, detail="福利额度必须大于 0")
        if coins > 1000000:
            raise HTTPException(status_code=400, detail="单次福利不能超过 1000000")
        title = (req.title or "").strip() or "全员福利"
        body = (req.body or "").strip()
        now = _utc_now_text()
        grant_id = f"welfare:{int(_utc_now().timestamp() * 1000000)}:{secrets.token_hex(4)}"
        users = db.execute(
            "SELECT id FROM users WHERE is_disabled=0 ORDER BY created_at ASC"
        ).fetchall()
        updated = 0
        for user in users:
            user_id = user["id"]
            db.execute("INSERT OR IGNORE INTO sync_data(user_id) VALUES(?)", (user_id,))
            row = db.execute(
                "SELECT virtual_rewards, sync_version FROM sync_data WHERE user_id=?",
                (user_id,),
            ).fetchone()
            rewards = _json_object(row["virtual_rewards"] if row else "{}")

            def _num(value, fallback=0) -> int:
                try:
                    return int(value)
                except Exception:
                    return fallback

            ledger = rewards.get("ledger")
            if not isinstance(ledger, list):
                ledger = []
            entry = {
                "id": f"{grant_id}:{user_id}",
                "title": title,
                "body": body,
                "coins": coins,
                "generate_bonus": generate_bonus,
                "edit_bonus": edit_bonus,
                "reason": title,
                "awardedAt": now,
            }
            balance = max(0, _num(rewards.get("balance")) + coins)
            lifetime = max(_num(rewards.get("lifetime")), balance)
            rewards.update(
                {
                    "balance": balance,
                    "lifetime": lifetime,
                    "ledger": [entry, *[item for item in ledger if isinstance(item, dict)]][:50],
                    "updatedAt": now,
                }
            )
            next_sync_version = int(row["sync_version"] or 0) + 1 if row else 1
            db.execute(
                """
                UPDATE sync_data
                SET virtual_rewards=?, sync_version=?, updated_at=?
                WHERE user_id=?
                """,
                (
                    json.dumps(rewards, ensure_ascii=False),
                    next_sync_version,
                    now,
                    user_id,
                ),
            )
            updated += 1
        _audit(
            db,
            actor,
            _get_username(db, actor),
            "welfare.grant_create",
            target=grant_id,
            detail=json.dumps(
                {
                    "title": title,
                    "body": body,
                    "generate_bonus": generate_bonus,
                    "edit_bonus": edit_bonus,
                    "coins": coins,
                    "notify": bool(req.notify),
                    "users": updated,
                },
                ensure_ascii=False,
            ),
        )
        db.commit()
        return {
            "status": "ok",
            "id": grant_id,
            "title": title,
            "body": body,
            "generate_bonus": generate_bonus,
            "edit_bonus": edit_bonus,
            "coins": coins,
            "users": updated,
        }
    finally:
        db.close()


@app.post("/api/admin/users/{user_id}/coins")
@app.post("/api/admin/users/{user_id}/coin")
@app.patch("/api/admin/users/{user_id}/coin")
@app.put("/api/admin/users/{user_id}/coin")
@app.post("/api/admin/users/{user_id}/coin-balance")
@app.patch("/api/admin/users/{user_id}/coin-balance")
@app.put("/api/admin/users/{user_id}/coin-balance")
@app.post("/api/admin/users/{user_id}/coin_balance")
@app.patch("/api/admin/users/{user_id}/coin_balance")
@app.put("/api/admin/users/{user_id}/coin_balance")
@app.patch("/api/admin/users/{user_id}/coins")
@app.put("/api/admin/users/{user_id}/coins")
@app.post("/api/admin/users/{user_id}/quota")
@app.patch("/api/admin/users/{user_id}/quota")
@app.put("/api/admin/users/{user_id}/quota")
@app.post("/api/admin/users/{user_id}/time-coins")
@app.patch("/api/admin/users/{user_id}/time-coins")
@app.put("/api/admin/users/{user_id}/time-coins")
@app.post("/api/admin/users/{user_id}/time-coin")
@app.patch("/api/admin/users/{user_id}/time-coin")
@app.put("/api/admin/users/{user_id}/time-coin")
@app.post("/api/admin/users/{user_id}/time-coin-balance")
@app.patch("/api/admin/users/{user_id}/time-coin-balance")
@app.put("/api/admin/users/{user_id}/time-coin-balance")
@app.post("/api/admin/users/{user_id}/time_coins")
@app.patch("/api/admin/users/{user_id}/time_coins")
@app.put("/api/admin/users/{user_id}/time_coins")
@app.post("/api/admin/users/{user_id}/time_coin")
@app.patch("/api/admin/users/{user_id}/time_coin")
@app.put("/api/admin/users/{user_id}/time_coin")
@app.post("/api/admin/users/{user_id}/time_coin_balance")
@app.patch("/api/admin/users/{user_id}/time_coin_balance")
@app.put("/api/admin/users/{user_id}/time_coin_balance")
@app.post("/api/admin/users/{user_id}/credits")
@app.patch("/api/admin/users/{user_id}/credits")
@app.put("/api/admin/users/{user_id}/credits")
@app.post("/api/admin/users/{user_id}/credit-balance")
@app.patch("/api/admin/users/{user_id}/credit-balance")
@app.put("/api/admin/users/{user_id}/credit-balance")
@app.post("/api/admin/users/{user_id}/credit_balance")
@app.patch("/api/admin/users/{user_id}/credit_balance")
@app.put("/api/admin/users/{user_id}/credit_balance")
@app.post("/api/admin/users/{user_id}/coins/adjust")
@app.patch("/api/admin/users/{user_id}/coins/adjust")
@app.put("/api/admin/users/{user_id}/coins/adjust")
@app.post("/api/admin/users/{user_id}/time-coins/adjust")
@app.patch("/api/admin/users/{user_id}/time-coins/adjust")
@app.put("/api/admin/users/{user_id}/time-coins/adjust")
@app.post("/api/admin/users/{user_id}/time-coin/adjust")
@app.patch("/api/admin/users/{user_id}/time-coin/adjust")
@app.put("/api/admin/users/{user_id}/time-coin/adjust")
@app.post("/api/admin/users/{user_id}/time_coins/adjust")
@app.patch("/api/admin/users/{user_id}/time_coins/adjust")
@app.put("/api/admin/users/{user_id}/time_coins/adjust")
@app.post("/api/admin/users/{user_id}/time_coin/adjust")
@app.patch("/api/admin/users/{user_id}/time_coin/adjust")
@app.put("/api/admin/users/{user_id}/time_coin/adjust")
@app.post("/api/admin/users/{user_id}/time-coin-balance/adjust")
@app.patch("/api/admin/users/{user_id}/time-coin-balance/adjust")
@app.put("/api/admin/users/{user_id}/time-coin-balance/adjust")
@app.post("/api/admin/users/{user_id}/time_coin_balance/adjust")
@app.patch("/api/admin/users/{user_id}/time_coin_balance/adjust")
@app.put("/api/admin/users/{user_id}/time_coin_balance/adjust")
@app.post("/api/admin/users/{user_id}/quota/adjust")
@app.patch("/api/admin/users/{user_id}/quota/adjust")
@app.put("/api/admin/users/{user_id}/quota/adjust")
@app.post("/api/admin/users/{user_id}/coin-adjustment")
@app.patch("/api/admin/users/{user_id}/coin-adjustment")
@app.put("/api/admin/users/{user_id}/coin-adjustment")
@app.post("/api/admin/users/{user_id}/coin_adjustment")
@app.patch("/api/admin/users/{user_id}/coin_adjustment")
@app.put("/api/admin/users/{user_id}/coin_adjustment")
def admin_adjust_user_coins(
    user_id: str, req: UserCoinAdjustment, actor: str = Depends(_require_admin)
):
    return _admin_adjust_user_coins_impl(user_id, req, actor)


@app.delete("/api/admin/users/{user_id}")
def admin_delete_user(user_id: str, actor: str = Depends(_require_admin)):
    if user_id == actor:
        raise HTTPException(status_code=400, detail="Cannot delete yourself")
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "users")
        row = db.execute(
            "SELECT username, is_admin FROM users WHERE id=?", (user_id,)
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="User not found")
        if row["is_admin"]:
            admins = db.execute(
                "SELECT COUNT(*) AS c FROM users WHERE is_admin=1"
            ).fetchone()["c"]
            if admins <= 1:
                raise HTTPException(
                    status_code=400, detail="Cannot delete the last admin"
                )
        db.execute("DELETE FROM users WHERE id=?", (user_id,))
        _revoke_user_token(user_id, db)
        _audit(
            db, actor, _get_username(db, actor),
            "user.delete", target=user_id, detail=row["username"]
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


# ---- Announcements (admin) ----


@app.get("/api/admin/announcements")
def admin_list_announcements(
    _: str = Depends(_require_admin),
    q: Optional[str] = None,
    status: Optional[str] = None,
    level: Optional[str] = None,
    sort: str = "created_desc",
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    limit, offset = _admin_page_window(limit, offset)
    db = get_db()
    try:
        actor = _
        _ensure_admin_permission(db, actor, "announcements")
        where_parts: list[str] = []
        params: list = []
        if q:
            where_parts.append("(title LIKE ? OR body LIKE ?)")
            like = f"%{q}%"
            params.extend([like, like])
        if status == "published":
            where_parts.append("published=1")
        elif status == "draft":
            where_parts.append("published=0")
        if level:
            where_parts.append("level=?")
            params.append(level)
        where = f"WHERE {' AND '.join(where_parts)}" if where_parts else ""
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM announcements {where}", params
        ).fetchone()["c"]
        order_by = {
            "created_desc": "id DESC",
            "updated_desc": "updated_at DESC, id DESC",
            "title_asc": "lower(title) ASC, id DESC",
            "level_desc": "CASE level WHEN 'critical' THEN 0 WHEN 'warning' THEN 1 ELSE 2 END, id DESC",
        }.get(sort, "id DESC")
        rows = db.execute(
            "SELECT id, title, body, level, published, created_at, updated_at "
            f"FROM announcements {where} ORDER BY {order_by} LIMIT ? OFFSET ?",
            (*params, limit, offset),
        ).fetchall()
        return _admin_page_response([dict(r) for r in rows], total, limit, offset)
    finally:
        db.close()


@app.post("/api/admin/announcements")
def create_announcement(req: AnnouncementCreate, actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "announcements")
        cur = db.execute(
            "INSERT INTO announcements(title, body, level, published) VALUES(?,?,?,?)",
            (req.title, req.body, req.level, 1 if req.published else 0),
        )
        _audit(
            db, actor, _get_username(db, actor),
            "announcement.create", target=str(cur.lastrowid), detail=req.title
        )
        db.commit()
        return {"id": cur.lastrowid}
    finally:
        db.close()


@app.patch("/api/admin/announcements/{ann_id}")
def update_announcement(
    ann_id: int, req: AnnouncementUpdate, actor: str = Depends(_require_admin)
):
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "announcements")
        data = req.model_dump(exclude_none=True)
        if not data:
            return {"status": "ok"}
        fields = []
        values: list = []
        for k, v in data.items():
            if k == "published":
                fields.append("published=?")
                values.append(1 if v else 0)
            else:
                fields.append(f"{k}=?")
                values.append(v)
        fields.append("updated_at=datetime('now')")
        values.append(ann_id)
        db.execute(
            f"UPDATE announcements SET {', '.join(fields)} WHERE id=?", values
        )
        _audit(
            db, actor, _get_username(db, actor),
            "announcement.update", target=str(ann_id),
            detail=json.dumps(data, ensure_ascii=False)
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


@app.delete("/api/admin/announcements/{ann_id}")
def delete_announcement(ann_id: int, actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "announcements")
        cur = db.execute("DELETE FROM announcements WHERE id=?", (ann_id,))
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="公告不存在")
        _audit(
            db, actor, _get_username(db, actor),
            "announcement.delete", target=str(ann_id)
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


# ---- Feedback (admin) ----


@app.get("/api/admin/feedback")
def list_all_feedback(
    _: str = Depends(_require_admin),
    status: Optional[str] = None,
    q: Optional[str] = None,
    keyword: Optional[str] = None,
    category: Optional[str] = None,
    type: Optional[str] = None,
    start_at: Optional[str] = None,
    end_at: Optional[str] = None,
    page: Optional[int] = None,
    page_size: Optional[int] = None,
    sort: str = "created_desc",
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    if page is not None or page_size is not None:
        limit = page_size or limit
        offset = (max(1, int(page or 1)) - 1) * int(limit or 50)
    limit, offset = _admin_page_window(limit, offset)
    db = get_db()
    try:
        actor = _
        _ensure_admin_permission(db, actor, "feedback")
        where, params = _feedback_admin_filters(
            status=status,
            q=keyword or q,
            category=category,
            feedback_type=type,
            start_at=start_at,
            end_at=end_at,
        )
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM feedback f JOIN users u ON u.id=f.user_id {where}",
            params,
        ).fetchone()["c"]
        order_by = _feedback_admin_order_by(sort)
        rows = db.execute(
            "SELECT f.*, u.username, u.email, u.email_verified, u.display_name, u.avatar "
            "FROM feedback f JOIN users u ON u.id=f.user_id "
            f"{where} ORDER BY {order_by} LIMIT ? OFFSET ?",
            (*params, limit, offset),
        ).fetchall()
        return _admin_page_response([dict(r) for r in rows], total, limit, offset)
    finally:
        db.close()


@app.get("/api/admin/feedback/export.csv")
def export_feedback_csv(
    actor: str = Depends(_require_admin),
    status: Optional[str] = None,
    q: Optional[str] = None,
    keyword: Optional[str] = None,
    category: Optional[str] = None,
    type: Optional[str] = None,
    start_at: Optional[str] = None,
    end_at: Optional[str] = None,
    sort: str = "created_desc",
    limit: int = Query(5000, ge=1, le=20000),
):
    limit, _offset = _admin_page_window(limit, 0, default_limit=5000, max_limit=20000)
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "feedback")
        where, params = _feedback_admin_filters(
            status=status,
            q=keyword or q,
            category=category,
            feedback_type=type,
            start_at=start_at,
            end_at=end_at,
        )
        order_by = _feedback_admin_order_by(sort)
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM feedback f JOIN users u ON u.id=f.user_id {where}",
            params,
        ).fetchone()["c"]
        rows = db.execute(
            """
            SELECT
                f.id, u.username, u.email, u.email_verified, u.display_name,
                f.category, f.status, f.content,
                f.admin_reply, f.created_at, f.updated_at
            FROM feedback f
            JOIN users u ON u.id=f.user_id
            """
            f"{where} ORDER BY {order_by} LIMIT ?",
            (*params, limit),
        ).fetchall()
        buffer = io.StringIO()
        writer = csv.writer(buffer)
        writer.writerow(
            [
                "id",
                "username",
                "email",
                "email_verified",
                "display_name",
                "category",
                "status",
                "content",
                "admin_reply",
                "created_at",
                "updated_at",
            ]
        )
        for row in rows:
            writer.writerow(
                [
                    row["id"],
                    _csv_safe(row["username"]),
                    _csv_safe(row["email"]),
                    1 if row["email_verified"] else 0,
                    _csv_safe(row["display_name"]),
                    _csv_safe(row["category"]),
                    _csv_safe(row["status"]),
                    _csv_safe(row["content"]),
                    _csv_safe(row["admin_reply"]),
                    _csv_safe(row["created_at"]),
                    _csv_safe(row["updated_at"]),
                ]
            )
        _audit(
            db,
            actor,
            _get_username(db, actor),
            "feedback.export",
            detail=json.dumps(
                {
                    "status": status or "",
                    "category": category or "",
                    "q": q or "",
                    "sort": sort,
                    "rows": len(rows),
                    "total": int(total or 0),
                },
                ensure_ascii=False,
            ),
        )
        db.commit()
        content = "\ufeff" + buffer.getvalue()
        filename = f"duoyi_feedback_{_utc_now().strftime('%Y%m%d_%H%M%S')}.csv"
        headers = {
            "Content-Disposition": f'attachment; filename="{filename}"',
            "X-Total-Count": str(int(total or 0)),
            "X-Exported-Count": str(len(rows)),
        }
        return StreamingResponse(
            iter([content]),
            media_type="text/csv; charset=utf-8",
            headers=headers,
        )
    finally:
        db.close()


@app.get("/api/admin/feedback/automation")
def admin_feedback_automation(actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "feedback")
        return {
            "auto_enabled": _setting_get(db, "feedback_ai_auto_enabled", False),
            "automation_limit": _setting_get(db, "feedback_ai_automation_limit", "20"),
            "interval_minutes": int(
                _setting_get(db, "feedback_ai_interval_minutes", 60) or 60
            ),
            "auto_reply_enabled": _setting_get(
                db, "feedback_ai_auto_reply_enabled", False
            ),
            "auto_export_enabled": _setting_get(
                db, "feedback_ai_auto_export_enabled", False
            ),
        }
    finally:
        db.close()


@app.post("/api/admin/feedback/automation")
def admin_feedback_save_automation(
    payload: Optional[dict] = Body(default=None),
    actor: str = Depends(_require_admin),
):
    payload = payload or {}
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "feedback")
        updates = {
            "feedback_ai_auto_enabled": _as_bool(payload.get("auto_enabled", False)),
            "feedback_ai_automation_limit": str(
                payload.get("automation_limit") or "20"
            ),
            "feedback_ai_interval_minutes": max(
                5, int(payload.get("interval_minutes") or 60)
            ),
            "feedback_ai_auto_reply_enabled": _as_bool(
                payload.get("auto_reply_enabled", False)
            ),
            "feedback_ai_auto_export_enabled": _as_bool(
                payload.get("auto_export_enabled", False)
            ),
        }
        for key, value in updates.items():
            _setting_set(db, key, value)
        _audit(db, actor, _get_username(db, actor), "feedback.ai_settings.update")
        db.commit()
        return admin_feedback_automation(actor)
    finally:
        db.close()


def _feedback_insights_payload(db, period: str = "week") -> dict:
    category_rows = db.execute(
        """
        SELECT category, COUNT(*) AS count
        FROM feedback
        GROUP BY category
        ORDER BY count DESC, category ASC
        """
    ).fetchall()
    status_rows = db.execute(
        """
        SELECT status, COUNT(*) AS count
        FROM feedback
        GROUP BY status
        ORDER BY count DESC, status ASC
        """
    ).fetchall()
    recent_rows = db.execute(
        """
        SELECT id, category, status, content, admin_reply, created_at, updated_at
        FROM feedback
        ORDER BY id DESC
        LIMIT 20
        """
    ).fetchall()
    return {
        "period": period,
        "categories": [dict(row) for row in category_rows],
        "statuses": [dict(row) for row in status_rows],
        "items": [dict(row) for row in recent_rows],
        "summary": "按分类、状态和最近反馈生成的需求清单。",
    }


@app.get("/api/admin/feedback/insights")
def admin_feedback_insights(
    period: str = "week",
    actor: str = Depends(_require_admin),
):
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "feedback")
        return _feedback_insights_payload(db, period)
    finally:
        db.close()


@app.post("/api/admin/feedback/export")
def admin_feedback_export_insights(
    period: str = "week",
    actor: str = Depends(_require_admin),
):
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "feedback")
        payload = _feedback_insights_payload(db, period)
        _audit(
            db,
            actor,
            _get_username(db, actor),
            "feedback.insights.export",
            detail=json.dumps({"period": period, "items": len(payload["items"])}, ensure_ascii=False),
        )
        db.commit()
        return {"ok": True, **payload}
    finally:
        db.close()


@app.post("/api/admin/feedback/auto-run")
def admin_feedback_auto_run(actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "feedback")
        rows = db.execute(
            """
            SELECT id, category, status, content
            FROM feedback
            WHERE status='open'
            ORDER BY id DESC
            LIMIT 20
            """
        ).fetchall()
        ids = [int(row["id"]) for row in rows]
        if ids:
            placeholders = ",".join("?" for _ in ids)
            db.execute(
                f"""
                UPDATE feedback
                SET status='in_progress', updated_at=datetime('now')
                WHERE id IN ({placeholders}) AND status='open'
                """,
                ids,
            )
            _audit(
                db,
                actor,
                _get_username(db, actor),
                "feedback.auto_run",
                target=",".join(str(v) for v in ids),
                detail=f"processed:{len(ids)}",
            )
            db.commit()
        return {
            "ok": True,
            "processed": len(rows),
            "items": [
                {
                    "id": row["id"],
                    "category": row["category"],
                    "status": row["status"],
                    "summary": _feedback_summary_text(row["content"]),
                }
                for row in rows
            ],
        }
    finally:
        db.close()


@app.post("/api/admin/feedback/auto-reply")
def admin_feedback_auto_reply(actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "feedback")
        enabled = _setting_get(db, "feedback_ai_auto_reply_enabled", False)
        if not enabled:
            return {
                "ok": True,
                "enabled": False,
                "processed": 0,
                "message": "自动回复开关未启用，未修改反馈。",
            }
        rows = db.execute(
            """
            SELECT id, category, status, content
            FROM feedback
            WHERE status IN ('open', 'in_progress')
              AND TRIM(COALESCE(admin_reply, '')) = ''
            ORDER BY id DESC
            LIMIT 20
            """
        ).fetchall()
        items = []
        for row in rows:
            reply = _feedback_auto_reply_text(row["category"], row["content"])
            db.execute(
                """
                UPDATE feedback
                SET admin_reply=?, status='in_progress', updated_at=datetime('now')
                WHERE id=?
                """,
                (reply, row["id"]),
            )
            items.append(
                {
                    "id": row["id"],
                    "status": "in_progress",
                    "reply": reply,
                    "summary": _feedback_summary_text(row["content"]),
                }
            )
        if items:
            _audit(
                db,
                actor,
                _get_username(db, actor),
                "feedback.auto_reply",
                target=",".join(str(item["id"]) for item in items),
                detail=f"processed:{len(items)}",
            )
            db.commit()
        return {
            "ok": True,
            "enabled": True,
            "processed": len(items),
            "items": items,
            "message": "已自动写入回复并标记为处理中。" if items else "没有待自动回复的反馈。",
        }
    finally:
        db.close()


@app.get("/api/admin/feedback/{fb_id}")
@app.get("/api/admin/feedback/{fb_id}/detail")
@app.get("/api/admin/feedback/detail/{fb_id}")
@app.get("/api/admin/feedbacks/{fb_id}")
def admin_feedback_detail(fb_id: int, actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "feedback")
        row = db.execute(
            "SELECT f.*, u.username, u.email, u.email_verified, u.display_name, u.avatar "
            "FROM feedback f JOIN users u ON u.id=f.user_id WHERE f.id=?",
            (fb_id,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="反馈不存在")
        return dict(row)
    finally:
        db.close()


def _feedback_summary_text(content: str) -> str:
    text = re.sub(r"\s+", " ", (content or "").strip())
    if len(text) <= 80:
        return text
    return text[:77] + "..."


def _feedback_auto_reply_text(category: str, content: str) -> str:
    summary = _feedback_summary_text(content)
    category_label = {
        "bug": "问题反馈",
        "feature": "功能建议",
        "wish": "许愿",
        "account": "账号问题",
        "system": "系统问题",
    }.get((category or "").strip(), "反馈")
    return (
        f"已收到你的{category_label}，我们会优先核查「{summary}」。"
        "处理进度会在反馈记录中同步更新。"
    )


@app.post("/api/admin/feedback/{fb_id}/ai-summary")
def admin_feedback_ai_summary(fb_id: int, actor: str = Depends(_require_admin)):
    item = admin_feedback_detail(fb_id, actor)
    summary = _feedback_summary_text(str(item.get("content") or ""))
    return {
        "ok": True,
        "id": fb_id,
        "summary": summary,
        "category": item.get("category"),
        "status": item.get("status"),
        "suggested_status": "in_progress"
        if item.get("status") == "open"
        else item.get("status"),
    }


@app.post("/api/admin/feedback/{fb_id}/status")
def admin_feedback_status_alias(
    fb_id: int,
    payload: Optional[dict] = Body(default=None),
    actor: str = Depends(_require_admin),
):
    payload = payload or {}
    status = str(payload.get("status") or "in_progress")
    note = str(payload.get("note") or payload.get("reply") or "")
    return reply_feedback(
        FeedbackReply(feedback_id=fb_id, reply=note, status=status),
        actor=actor,
    )


@app.post("/api/admin/feedback/{fb_id}/reply")
def admin_feedback_reply_alias(
    fb_id: int,
    payload: Optional[dict] = Body(default=None),
    actor: str = Depends(_require_admin),
):
    payload = payload or {}
    reply = str(payload.get("reply") or payload.get("note") or "")
    status = str(payload.get("status") or "resolved")
    return reply_feedback(
        FeedbackReply(feedback_id=fb_id, reply=reply, status=status),
        actor=actor,
    )


@app.post("/api/admin/feedback/reply")
def reply_feedback(req: FeedbackReply, actor: str = Depends(_require_admin)):
    feedback_id = _feedback_reply_id(req)
    raw_reply = _feedback_reply_text(req)
    reply = _clean_feedback_content(raw_reply) if raw_reply else ""
    status = _clean_feedback_status(req.status)
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "feedback")
        if reply:
            cur = db.execute(
                "UPDATE feedback SET admin_reply=?, status=?, updated_at=datetime('now') WHERE id=?",
                (reply, status, feedback_id),
            )
        else:
            cur = db.execute(
                "UPDATE feedback SET status=?, updated_at=datetime('now') WHERE id=?",
                (status, feedback_id),
            )
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="反馈不存在")
        _audit(
            db, actor, _get_username(db, actor),
            "feedback.reply", target=str(feedback_id), detail=status
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


@app.post("/api/admin/feedback/bulk-status")
@app.post("/api/admin/feedback/bulk_status")
@app.post("/api/admin/feedback/status/bulk")
@app.post("/api/admin/feedbacks/bulk-status")
@app.post("/api/admin/feedbacks/bulk_status")
def bulk_update_feedback_status(
    req: FeedbackBulkStatus,
    actor: str = Depends(_require_admin),
):
    ids = _feedback_bulk_ids(req)
    if not ids:
        raise HTTPException(status_code=400, detail="请选择要处理的反馈")
    if len(ids) > 100:
        raise HTTPException(status_code=400, detail="单次最多处理 100 条反馈")
    raw_reply = _feedback_bulk_text(req)
    reply = _clean_feedback_content(raw_reply) if raw_reply else ""
    status = _clean_feedback_status(req.status)
    placeholders = ",".join("?" for _ in ids)
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "feedback")
        existing = db.execute(
            f"SELECT id FROM feedback WHERE id IN ({placeholders})",
            ids,
        ).fetchall()
        existing_ids = [int(r["id"]) for r in existing]
        if len(existing_ids) != len(ids):
            raise HTTPException(status_code=404, detail="部分反馈不存在")
        if reply:
            db.execute(
                f"""
                UPDATE feedback
                SET admin_reply=?, status=?, updated_at=datetime('now')
                WHERE id IN ({placeholders})
                """,
                (reply, status, *ids),
            )
        else:
            db.execute(
                f"""
                UPDATE feedback
                SET status=?, updated_at=datetime('now')
                WHERE id IN ({placeholders})
                """,
                (status, *ids),
            )
        _audit(
            db,
            actor,
            _get_username(db, actor),
            "feedback.bulk_status",
            target=",".join(str(v) for v in existing_ids),
            detail=f"{status}:{len(existing_ids)}",
        )
        db.commit()
        return {"status": "ok", "updated": len(existing_ids)}
    finally:
        db.close()


@app.delete("/api/admin/feedback/{fb_id}")
@app.delete("/api/admin/feedbacks/{fb_id}")
@app.post("/api/admin/feedback/{fb_id}/delete")
@app.post("/api/admin/feedbacks/{fb_id}/delete")
def delete_feedback(fb_id: int, actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "feedback")
        cur = db.execute("DELETE FROM feedback WHERE id=?", (fb_id,))
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="反馈不存在")
        _audit(
            db, actor, _get_username(db, actor),
            "feedback.delete", target=str(fb_id)
        )
        db.commit()
        return {"status": "ok", "deleted": 1}
    finally:
        db.close()


# ---- Invite codes (admin) ----


@app.post("/api/admin/invite-codes")
@app.post("/api/admin/invitation-codes")
def create_invite_codes(req: InviteCodeCreate, actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "invites")
        codes: list[str] = []
        for _i in range(max(1, min(req.count, 100))):
            code = secrets.token_urlsafe(8)
            db.execute(
                "INSERT INTO invite_codes(code, note) VALUES(?, ?)",
                (code, req.note or ""),
            )
            codes.append(code)
        _audit(
            db, actor, _get_username(db, actor),
            "invite.create", detail=f"count={len(codes)}"
        )
        db.commit()
        return {"codes": codes}
    finally:
        db.close()


@app.get("/api/admin/invite-codes")
@app.get("/api/admin/invitation-codes")
def list_invite_codes(
    _: str = Depends(_require_admin),
    q: Optional[str] = None,
    status: Optional[str] = None,
    sort: str = "created_desc",
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    limit, offset = _admin_page_window(limit, offset)
    db = get_db()
    try:
        actor = _
        _ensure_admin_permission(db, actor, "invites")
        where_parts: list[str] = []
        params: list = []
        if q:
            where_parts.append("(ic.code LIKE ? OR ic.note LIKE ? OR u.username LIKE ?)")
            like = f"%{q}%"
            params.extend([like, like, like])
        if status == "used":
            where_parts.append("ic.used_by IS NOT NULL")
        elif status == "unused":
            where_parts.append("ic.used_by IS NULL")
        where = f"WHERE {' AND '.join(where_parts)}" if where_parts else ""
        total = db.execute(
            "SELECT COUNT(*) AS c FROM invite_codes ic "
            f"LEFT JOIN users u ON u.id=ic.used_by {where}",
            params,
        ).fetchone()["c"]
        order_by = {
            "created_desc": "ic.created_at DESC, ic.code ASC",
            "used_desc": "ic.used_at IS NULL, ic.used_at DESC, ic.created_at DESC",
            "code_asc": "lower(ic.code) ASC",
            "note_asc": "lower(ic.note) ASC, ic.created_at DESC",
        }.get(sort, "ic.created_at DESC, ic.code ASC")
        rows = db.execute(
            "SELECT ic.code, ic.used_by, ic.used_at, ic.created_at, ic.note, u.username AS used_by_name "
            "FROM invite_codes ic LEFT JOIN users u ON u.id=ic.used_by "
            f"{where} ORDER BY {order_by} LIMIT ? OFFSET ?",
            (*params, limit, offset),
        ).fetchall()
        return _admin_page_response([dict(r) for r in rows], total, limit, offset)
    finally:
        db.close()


@app.delete("/api/admin/invite-codes/{code}")
@app.delete("/api/admin/invitation-codes/{code}")
def delete_invite_code(code: str, actor: str = Depends(_require_admin)):
    db = get_db()
    try:
        _ensure_admin_permission(db, actor, "invites")
        row = db.execute(
            "SELECT used_by FROM invite_codes WHERE code=?", (code,)
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Code not found")
        if row["used_by"]:
            raise HTTPException(status_code=400, detail="Code already used")
        db.execute("DELETE FROM invite_codes WHERE code=?", (code,))
        _audit(
            db, actor, _get_username(db, actor),
            "invite.delete", target=code
        )
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


# ---- Audit log ----


@app.get("/api/admin/audit-log")
def admin_audit_log(
    _: str = Depends(_require_admin),
    action: Optional[str] = None,
    q: Optional[str] = None,
    sort: str = "created_desc",
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    limit, offset = _admin_page_window(limit, offset, max_limit=500)
    db = get_db()
    try:
        actor = _
        _ensure_admin_permission(db, actor, "audit")
        where_parts: list[str] = []
        params: list = []
        if action:
            where_parts.append("action=?")
            params.append(action)
        if q:
            where_parts.append(
                "(actor_name LIKE ? OR actor_id LIKE ? OR action LIKE ? OR target LIKE ? OR detail LIKE ?)"
            )
            like = f"%{q}%"
            params.extend([like, like, like, like, like])
        where = f"WHERE {' AND '.join(where_parts)}" if where_parts else ""
        total = db.execute(
            f"SELECT COUNT(*) AS c FROM audit_log {where}", params
        ).fetchone()["c"]
        order_by = {
            "created_desc": "id DESC",
            "actor_asc": "lower(actor_name) ASC, id DESC",
            "action_asc": "action ASC, id DESC",
            "target_asc": "target ASC, id DESC",
        }.get(sort, "id DESC")
        rows = db.execute(
            f"SELECT * FROM audit_log {where} ORDER BY {order_by} LIMIT ? OFFSET ?",
            (*params, limit, offset),
        ).fetchall()
        return _admin_page_response([dict(r) for r in rows], total, limit, offset)
    finally:
        db.close()
