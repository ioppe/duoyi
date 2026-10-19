"""First-run settings only; INSERT OR IGNORE in main keeps the database authoritative."""

import json
from typing import TYPE_CHECKING, Mapping

if TYPE_CHECKING:
    if __package__:
        from .config import BackendSettings
    else:
        from config import BackendSettings


DEFAULT_AI_BASE_URL = "https://api.openai.com"
DEFAULT_AI_MODEL = "gpt-4o-mini"
EMAIL_CODE_PROVIDERS = {"claw163", "openclaw", "openclaw_mail", "resend", "smtp", "hermes", "none"}


def _existing_bool(existing: Mapping[str, str], key: str, default: bool) -> bool:
    if key not in existing:
        return default
    try:
        return bool(json.loads(existing[key]))
    except (TypeError, ValueError):
        return str(existing[key]).strip().lower() in {"1", "true", "yes", "on"}


def build_settings_defaults(
    settings: "BackendSettings", existing: Mapping[str, str] | None = None
) -> dict[str, object]:
    """Generate seed values while preserving legacy registration/SMTP aliases."""
    env = settings.environment
    existing = existing or {}
    default_registration_enabled = _existing_bool(
        existing, "registration_enabled", env.boolean("ALLOW_PUBLIC_REGISTRATION", default=True)
    )
    default_invite_code_required = _existing_bool(
        existing, "invite_code_required", env.boolean("INVITE_CODE_REQUIRED", default=False)
    )
    email_smtp_host_default = env.text(
        "EMAIL_SMTP_HOST", "SMTP_HOST", "MAIL_SMTP_HOST", "MAIL_HOST"
    )
    email_smtp_port_default = env.integer(
        "EMAIL_SMTP_PORT", "SMTP_PORT", "MAIL_SMTP_PORT", "MAIL_PORT",
        default=465, minimum=1, maximum=65535,
    )
    email_smtp_username_default = env.text(
        "EMAIL_SMTP_USERNAME", "EMAIL_ADDRESS", "SMTP_USERNAME", "SMTP_USER",
        "MAIL_SMTP_USERNAME", "MAIL_USERNAME", "MAIL_USER", "MAIL_ADDRESS",
    )
    email_smtp_password_default = env.text(
        "EMAIL_SMTP_PASSWORD", "EMAIL_PASSWORD", "SMTP_PASSWORD", "SMTP_PASS",
        "MAIL_SMTP_PASSWORD", "MAIL_PASSWORD", "MAIL_PASS",
    )
    email_smtp_from_default = env.text(
        "EMAIL_SMTP_FROM", "EMAIL_FROM", "MAIL_FROM", "SMTP_FROM",
        default=email_smtp_username_default,
    )
    email_smtp_use_ssl_default = env.smtp_use_ssl(
        email_smtp_port_default,
        "EMAIL_SMTP_USE_SSL", "SMTP_USE_SSL", "MAIL_SMTP_USE_SSL", "MAIL_USE_SSL",
    )
    backup_smtp_port_default = env.integer(
        "BACKUP_EMAIL_SMTP_PORT", "EMAIL_SMTP_PORT", "SMTP_PORT",
        default=email_smtp_port_default, minimum=1, maximum=65535,
    )
    backup_smtp_use_ssl_default = env.smtp_use_ssl(
        backup_smtp_port_default, "BACKUP_EMAIL_SMTP_USE_SSL", "EMAIL_SMTP_USE_SSL", "SMTP_USE_SSL"
    )
    reminder_smtp_port_default = env.integer(
        "REMINDER_EMAIL_SMTP_PORT", "EMAIL_SMTP_PORT", "SMTP_PORT",
        default=email_smtp_port_default, minimum=1, maximum=65535,
    )
    reminder_smtp_use_ssl_default = env.smtp_use_ssl(
        reminder_smtp_port_default, "REMINDER_EMAIL_SMTP_USE_SSL", "EMAIL_SMTP_USE_SSL", "SMTP_USE_SSL"
    )
    account_primary_provider_default = env.choice(
        "EMAIL_CODE_PRIMARY_PROVIDER",
        default=(
            "smtp"
            if email_smtp_host_default and email_smtp_username_default and email_smtp_password_default
            else "claw163"
        ),
        choices=EMAIL_CODE_PROVIDERS,
    )
    return {
        "invite_code_required": default_invite_code_required,
        "allow_public_registration": default_registration_enabled,
        "registration_invite_required": env.boolean(
            "REGISTRATION_INVITE_REQUIRED", default=default_invite_code_required
        ),
        "registration_enabled": default_registration_enabled,
        "registration_email_required": env.boolean("REGISTRATION_EMAIL_REQUIRED", default=True),
        "maintenance_mode": False,
        "maintenance_message": "",
        "force_update_required": False,
        "force_app_update_enabled": False,
        "force_relogin_enabled": False,
        "force_relogin_issued_at": "",
        "latest_version": "",
        "latest_version_name": "",
        "minimum_supported_version": "",
        "update_notes": "",
        "release_notes": "",
        "update_download_url": "",
        "default_registration_coins": 100,
        "download_url": "",
        # AI is configured by an administrator; clients use /api/ai/chat.
        "ai_enabled": False,
        "ai_base_url": env.url("AI_BASE_URL", default=DEFAULT_AI_BASE_URL),
        "ai_api_key": env.text("AI_API_KEY"),
        "ai_model": env.text("AI_MODEL", default=DEFAULT_AI_MODEL),
        "ai_daily_quota": 100,
        "backup_enabled": True,
        "backup_max_size_kb": 2048,
        "backup_interval_minutes": 30,
        "backup_retain_days": 0,
        "server_backup_enabled": env.boolean("SERVER_BACKUP_ENABLED", default=True),
        "server_backup_interval_minutes": env.integer(
            "SERVER_BACKUP_INTERVAL_MINUTES", default=720, minimum=1, maximum=525600
        ),
        "server_backup_retain_days": env.integer(
            "SERVER_BACKUP_RETAIN_DAYS", default=14, minimum=0, maximum=36500
        ),
        "openlist_backup_enabled": env.boolean("OPENLIST_BACKUP_ENABLED", default=False),
        "openlist_webdav_url": env.url("OPENLIST_WEBDAV_URL"),
        "openlist_public_url": env.url("OPENLIST_PUBLIC_URL"),
        "openlist_username": env.text("OPENLIST_USERNAME"),
        "openlist_password": env.text("OPENLIST_PASSWORD"),
        "openlist_backup_path": env.text("OPENLIST_BACKUP_PATH", default="/duoyi-backups"),
        "backup_email_enabled": env.boolean("BACKUP_EMAIL_ENABLED", default=False),
        "backup_email_to": env.text("BACKUP_EMAIL_TO"),
        "backup_email_from": env.text("BACKUP_EMAIL_FROM", default=email_smtp_from_default),
        "backup_email_smtp_host": env.text("BACKUP_EMAIL_SMTP_HOST", default=email_smtp_host_default),
        "backup_email_smtp_port": backup_smtp_port_default,
        "backup_email_smtp_username": env.text("BACKUP_EMAIL_SMTP_USERNAME", default=email_smtp_username_default),
        "backup_email_smtp_password": env.text("BACKUP_EMAIL_SMTP_PASSWORD", default=email_smtp_password_default),
        "backup_email_smtp_use_ssl": backup_smtp_use_ssl_default,
        "reminder_email_enabled": env.boolean("REMINDER_EMAIL_ENABLED", default=False),
        "reminder_email_to": env.text("REMINDER_EMAIL_TO"),
        "reminder_email_from": env.text("REMINDER_EMAIL_FROM", default=email_smtp_from_default),
        "reminder_email_smtp_host": env.text("REMINDER_EMAIL_SMTP_HOST", default=email_smtp_host_default),
        "reminder_email_smtp_port": reminder_smtp_port_default,
        "reminder_email_smtp_username": env.text("REMINDER_EMAIL_SMTP_USERNAME", default=email_smtp_username_default),
        "reminder_email_smtp_password": env.text("REMINDER_EMAIL_SMTP_PASSWORD", default=email_smtp_password_default),
        "reminder_email_smtp_use_ssl": reminder_smtp_use_ssl_default,
        "email_service_enabled": env.boolean("EMAIL_SERVICE_ENABLED", default=True),
        "email_title": settings.email_title,
        "email_sender_name": settings.email_sender_name,
        "email_code_primary_provider": account_primary_provider_default,
        "email_code_backup_provider": env.choice(
            "EMAIL_CODE_BACKUP_PROVIDER", default="resend", choices=EMAIL_CODE_PROVIDERS
        ),
        "email_code_active_slot": env.choice(
            "EMAIL_CODE_ACTIVE_SLOT", default="primary", choices={"primary", "backup"}
        ),
        "email_auto_switch_enabled": env.boolean("EMAIL_AUTO_SWITCH_ENABLED", default=False),
        "openclaw_mail_enabled": env.boolean("OPENCLAW_MAIL_ENABLED", default=False),
        "openclaw_mail_user": env.text("OPENCLAW_MAIL_USER", "OPENCLAW_MAIL_USERNAME"),
        "openclaw_mail_api_key": env.text("OPENCLAW_MAIL_API_KEY", "OPENCLAW_MAIL_KEY"),
        "resend_base_url": env.url("RESEND_BASE_URL", default="https://api.resend.com"),
        "resend_api_key": env.text("RESEND_API_KEY"),
        "resend_from": settings.resend_from,
        "hermes_base_url": env.url("HERMES_BASE_URL"),
        "hermes_api_key": env.text("HERMES_API_KEY"),
        "system_notice_email_to": env.text(
            "SYSTEM_NOTICE_EMAIL_TO", "EMAIL_HOME_ADDRESS", "EMAIL_HOME_CHANNEL"
        ),
        "email_smtp_host": email_smtp_host_default,
        "email_smtp_port": email_smtp_port_default,
        "email_smtp_username": email_smtp_username_default,
        "email_smtp_password": email_smtp_password_default,
        "email_smtp_from": email_smtp_from_default,
        "email_smtp_use_ssl": email_smtp_use_ssl_default,
    }
