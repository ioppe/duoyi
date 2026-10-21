import hashlib
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing, redirect_stderr, redirect_stdout
import importlib
import io
import json
import os
from pathlib import Path
import sqlite3
import stat
import subprocess
import sys
import tempfile
from threading import Barrier
import unittest
from unittest.mock import Mock, patch

from fastapi.testclient import TestClient

if __package__:
    from . import config
    from . import deployment_config
    from .settings_defaults import DEFAULT_AI_BASE_URL, DEFAULT_AI_MODEL
else:
    import config
    import deployment_config
    from settings_defaults import DEFAULT_AI_BASE_URL, DEFAULT_AI_MODEL


class ConfigTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.profile = self.root / "deployment.json"
        self.profile.write_text("{}", encoding="utf-8")

    def load(self, environment=None, **kwargs):
        return config.load_settings(
            {} if environment is None else environment,
            backend_dir=self.root,
            deployment_file=self.profile,
            pubspec_path=self.root / "pubspec.yaml",
            **kwargs,
        )

    def test_neutral_standalone_defaults_have_no_instance_identity(self):
        with patch.object(deployment_config, "DEFAULT_CONFIG_FILE", self.root / "absent.json"):
            settings = config.load_settings({}, backend_dir=self.root, pubspec_path=self.root / "absent.yaml")
        self.assertIsNone(settings.public_source)
        self.assertEqual(settings.cors_origins, ())
        self.assertEqual(settings.app_update_repository, "")
        self.assertEqual((settings.app_current_version, settings.app_current_version_code), ("0.0.0", 0))
        self.assertEqual(settings.admin_bootstrap_password, "")
        self.assertEqual(settings.resend_from, "")
        self.assertEqual(settings.openclaw_mail_script, "")
        self.assertEqual(settings.initial_settings["ai_base_url"], DEFAULT_AI_BASE_URL)
        self.assertEqual(settings.initial_settings["ai_model"], DEFAULT_AI_MODEL)
        self.assertIs(settings.initial_settings["email_code_login_enabled"], False)
        self.assertIs(settings.initial_settings["registration_email_required"], False)
        self.assertFalse((self.root / "duoyi.db").exists())
        self.assertFalse((self.root / "backups").exists())

    def test_checked_in_public_profile_provides_backend_defaults(self):
        profile = Path(__file__).resolve().parents[1] / "config" / "deployment.json"
        settings = config.load_settings({}, backend_dir=self.root, deployment_file=profile)
        self.assertEqual(settings.cors_origins, ("https://todo.skydrow.site",))
        self.assertEqual(settings.app_update_repository, "ioppe/duoyi")
        self.assertEqual(settings.public_source, profile)

    def test_environment_file_and_process_override_public_defaults(self):
        self.profile.write_text(json.dumps({
            "DUOYI_SERVER_URL": "https://profile.example.test/app",
            "DUOYI_UPDATE_REPOSITORY": "profile/duoyi",
        }), encoding="utf-8")
        (self.root / ".env").write_text(
            "CORS_ORIGINS=https://private.example.test\nAPP_UPDATE_REPOSITORY=private/duoyi\n"
            "SESSION_ONLINE_SECONDS=600\nAI_API_KEY='private-value'\n",
            encoding="utf-8",
        )
        before = dict(os.environ)
        settings = self.load()
        self.assertEqual(settings.cors_origins, ("https://private.example.test",))
        self.assertEqual(settings.app_update_repository, "private/duoyi")
        self.assertEqual(settings.session_online_seconds, 600)
        self.assertEqual(settings.initial_settings["ai_api_key"], "private-value")
        settings = self.load({"CORS_ORIGINS": "", "APP_UPDATE_REPOSITORY": "", "AI_API_KEY": ""})
        self.assertEqual(settings.cors_origins, ())
        self.assertEqual(settings.app_update_repository, "")
        self.assertEqual(settings.initial_settings["ai_api_key"], "")
        self.assertEqual(dict(os.environ), before)

    def test_process_public_update_alias_overrides_private_legacy_alias(self):
        (self.root / ".env").write_text("APP_UPDATE_REPOSITORY=private/fork\n", encoding="utf-8")
        for repository in ("process/fork", ""):
            with self.subTest(repository=repository):
                settings = self.load({"DUOYI_UPDATE_REPOSITORY": repository})
                self.assertEqual(settings.app_update_repository, repository)

    def test_env_file_selection_empty_values_quotes_and_literal_shell_text(self):
        selected = self.root / "private.env"
        marker = self.root / "must-not-exist"
        selected.write_text(
            "# ignored\nADMIN_BOOTSTRAP_PASSWORD=\nEMAIL_SMTP_PASSWORD=''\n"
            'EMAIL_SENDER_NAME="A Sender"\n'
            f"AI_API_KEY='$(touch {marker}) $HOME `id`'\n",
            encoding="utf-8",
        )
        settings = self.load({"DUOYI_ENV_FILE": str(selected)})
        self.assertEqual(settings.env_file, selected)
        self.assertEqual(settings.admin_bootstrap_password, "")
        self.assertEqual(settings.initial_settings["email_smtp_password"], "")
        self.assertEqual(settings.email_sender_name, "A Sender")
        self.assertIn("$HOME `id`", settings.initial_settings["ai_api_key"])
        self.assertFalse(marker.exists())
        (self.root / ".env").write_text("AI_API_KEY=ignored\n", encoding="utf-8")
        self.assertEqual(self.load({"DUOYI_ENV_FILE": ""}).initial_settings["ai_api_key"], "")

    def test_env_file_rejects_malformed_lines_without_leaking_contents(self):
        for contents, key in (
            ("export AI_API_KEY=private-token", "DUOYI_ENV_FILE"),
            ("AI_API_KEY='private-token", "AI_API_KEY"),
            ("AI_API_KEY=private-token\nAI_API_KEY=another-token", "AI_API_KEY"),
            ("private-token", "DUOYI_ENV_FILE"),
        ):
            with self.subTest(contents=contents):
                selected = self.root / "invalid.env"
                selected.write_text(contents, encoding="utf-8")
                with self.assertRaises(config.ConfigurationError) as failure:
                    self.load({"DUOYI_ENV_FILE": str(selected)})
                self.assertIn(key, str(failure.exception))
                self.assertNotIn("private-token", str(failure.exception))
                self.assertNotIn("another-token", str(failure.exception))

    def test_explicit_missing_env_and_public_files_fail(self):
        for key in ("DUOYI_ENV_FILE", "DUOYI_CONFIG_FILE"):
            with self.subTest(key=key), self.assertRaisesRegex(config.ConfigurationError, key):
                config.load_settings({key: str(self.root / "absent")}, backend_dir=self.root)

    def test_email_code_login_environment_default_and_explicit_opt_in(self):
        self.assertIs(self.load().initial_settings["email_code_login_enabled"], False)
        self.assertIs(self.load({"EMAIL_CODE_LOGIN_ENABLED": "true"}).initial_settings["email_code_login_enabled"], True)
        self.assertIs(self.load({"EMAIL_CODE_LOGIN_ENABLED": "false"}).initial_settings["email_code_login_enabled"], False)

    def test_registration_email_environment_default_and_explicit_opt_in(self):
        self.assertIs(self.load().initial_settings["registration_email_required"], False)
        self.assertIs(self.load({"REGISTRATION_EMAIL_REQUIRED": "true"}).initial_settings["registration_email_required"], True)
        self.assertIs(self.load({"REGISTRATION_EMAIL_REQUIRED": "false"}).initial_settings["registration_email_required"], False)

    def test_boolean_and_numeric_errors_are_strict_and_redacted(self):
        bad_values = {
            "SESSION_ONLINE_SECONDS": ["not-a-number", "0", "-1", "1.5"],
            "FOCUS_ROOM_ONLINE_SECONDS": ["", "0"],
            "FOCUS_FRIEND_REQUEST_LIMIT_PER_DAY": ["0", "-10"],
            "FOCUS_ROOM_MAX_WEEKLY_SECONDS": ["0", "604801"],
            "FOCUS_ROOM_MAX_SESSION_COUNT": ["0"],
            "FOCUS_ROOM_HEARTBEAT_THROTTLE_SECONDS": ["-1"],
            "FOCUS_ROOM_SESSION_JUMP_WINDOW_SECONDS": ["0"],
            "FOCUS_ROOM_MAX_SESSION_COUNT_JUMP": ["-1"],
            "REMINDER_EMAIL_POLL_SECONDS": ["0", "-1", "false"],
            "APP_CURRENT_VERSION_CODE": ["-1", "1.5"],
            "SMTP_PORT": ["0", "65536", "private-token"],
            "BACKUP_EMAIL_SMTP_PORT": ["-1"],
            "SERVER_BACKUP_INTERVAL_MINUTES": ["0"],
            "SERVER_BACKUP_RETAIN_DAYS": ["-1"],
            "EMAIL_SERVICE_ENABLED": ["", "private-token"],
            "EMAIL_CODE_LOGIN_ENABLED": ["", "private-token"],
            "SMTP_USE_SSL": ["maybe"],
            "ALLOW_PUBLIC_REGISTRATION": ["maybe"],
            "REGISTRATION_EMAIL_REQUIRED": ["maybe"],
        }
        for key, values in bad_values.items():
            for value in values:
                with self.subTest(key=key, value=value):
                    with self.assertRaises(config.ConfigurationError) as failure:
                        self.load({key: value, "AI_API_KEY": "private-token"})
                    self.assertIn(key, str(failure.exception))
                    self.assertNotIn("private-token", str(failure.exception))
        self.assertTrue(self.load({"SERVER_BACKUP_ENABLED": "ON"}).initial_settings["server_backup_enabled"])
        self.assertFalse(self.load({"SERVER_BACKUP_ENABLED": "off"}).initial_settings["server_backup_enabled"])
        self.assertEqual(self.load({"SERVER_BACKUP_RETAIN_DAYS": "0"}).initial_settings["server_backup_retain_days"], 0)

    def test_invalid_urls_cors_and_versions_do_not_echo_private_values(self):
        for key, value in (
            ("AI_BASE_URL", "https://user:private-token@example.test"),
            ("RESEND_BASE_URL", "ftp://private-token.example.test"),
            ("CORS_ORIGINS", "https://example.test/private-token"),
            ("CORS_ORIGINS", "*,https://example.test"),
            ("CORS_ORIGINS", "https://example.test,"),
            ("CORS_ORIGINS", "https://example.test:99999"),
            ("APP_UPDATE_REPOSITORY", "private-token"),
            ("APP_CURRENT_VERSION", "private-token"),
            ("PASSWORD_HASH_SALT", ""),
            ("APP_UPDATE_REPOSITORY", "../duoyi"),
        ):
            with self.subTest(key=key, value=value), self.assertRaises(config.ConfigurationError) as failure:
                self.load({key: value})
            self.assertIn(key, str(failure.exception))
            self.assertNotIn("private-token", str(failure.exception))
        self.assertEqual(
            self.load({"CORS_ORIGINS": " https://app.example.test/, http://localhost:8000 "}).cors_origins,
            ("https://app.example.test", "http://localhost:8000"),
        )

    def test_all_historical_smtp_aliases_and_priority(self):
        groups = {
            "email_smtp_host": ("EMAIL_SMTP_HOST", "SMTP_HOST", "MAIL_SMTP_HOST", "MAIL_HOST"),
            "email_smtp_username": (
                "EMAIL_SMTP_USERNAME", "EMAIL_ADDRESS", "SMTP_USERNAME", "SMTP_USER",
                "MAIL_SMTP_USERNAME", "MAIL_USERNAME", "MAIL_USER", "MAIL_ADDRESS",
            ),
            "email_smtp_password": (
                "EMAIL_SMTP_PASSWORD", "EMAIL_PASSWORD", "SMTP_PASSWORD", "SMTP_PASS",
                "MAIL_SMTP_PASSWORD", "MAIL_PASSWORD", "MAIL_PASS",
            ),
            "email_smtp_from": ("EMAIL_SMTP_FROM", "EMAIL_FROM", "MAIL_FROM", "SMTP_FROM"),
            "email_smtp_port": ("EMAIL_SMTP_PORT", "SMTP_PORT", "MAIL_SMTP_PORT", "MAIL_PORT"),
            "email_smtp_use_ssl": ("EMAIL_SMTP_USE_SSL", "SMTP_USE_SSL", "MAIL_SMTP_USE_SSL", "MAIL_USE_SSL"),
        }
        for setting_key, aliases in groups.items():
            for index, alias in enumerate(aliases):
                value = "587" if setting_key.endswith("port") else "false" if setting_key.endswith("ssl") else "first"
                expected = 587 if setting_key.endswith("port") else False if setting_key.endswith("ssl") else "first"
                environment = {name: "465" if setting_key.endswith("port") else "true" if setting_key.endswith("ssl") else "later" for name in aliases[index:]}
                environment[alias] = value
                with self.subTest(alias=alias):
                    self.assertEqual(self.load(environment).initial_settings[setting_key], expected)
        settings = self.load({"SMTP_HOST": "smtp.example.test", "EMAIL_ADDRESS": "sender@example.test", "EMAIL_PASSWORD": "private-token", "SMTP_PORT": "587"})
        defaults = settings.initial_settings
        self.assertEqual(defaults["email_code_primary_provider"], "smtp")
        self.assertEqual(defaults["email_code_backup_provider"], "resend")
        for prefix in ("email", "backup_email", "reminder_email"):
            self.assertEqual(defaults[f"{prefix}_smtp_port"], 587)
            self.assertFalse(defaults[f"{prefix}_smtp_use_ssl"])
            self.assertEqual(defaults[f"{prefix}_smtp_password"], "private-token")
        self.assertEqual(defaults["email_smtp_from"], "sender@example.test")

    def test_process_aliases_override_file_canonical_names_including_empty(self):
        (self.root / ".env").write_text(
            "EMAIL_SMTP_HOST=file.example.test\nEMAIL_SMTP_PASSWORD=file-secret\n"
            "OPENCLAW_MAIL_USER=file-user\nOPENCLAW_MAIL_API_KEY=file-key\n",
            encoding="utf-8",
        )
        defaults = self.load({"SMTP_HOST": "process.example.test", "SMTP_PASS": "", "OPENCLAW_MAIL_USERNAME": "process-user", "OPENCLAW_MAIL_KEY": ""}).initial_settings
        self.assertEqual(defaults["email_smtp_host"], "process.example.test")
        self.assertEqual(defaults["email_smtp_password"], "")
        self.assertEqual(defaults["openclaw_mail_user"], "process-user")
        self.assertEqual(defaults["openclaw_mail_api_key"], "")

    def test_openclaw_and_email_identity_aliases(self):
        defaults = self.load({"OPENCLAW_MAIL_USER": "first", "OPENCLAW_MAIL_USERNAME": "later", "OPENCLAW_MAIL_API_KEY": "first-key", "OPENCLAW_MAIL_KEY": "later-key"}).initial_settings
        self.assertEqual(defaults["openclaw_mail_user"], "first")
        self.assertEqual(defaults["openclaw_mail_api_key"], "first-key")
        for alias in ("DUOYI_TITLE", "EMAIL_TITLE", "APP_TITLE"):
            self.assertEqual(self.load({alias: "Mail Brand", "TITLE": "unrelated"}).email_title, "Mail Brand")
        self.assertEqual(self.load({"TITLE": "unrelated"}).email_title, "多仪")
        for alias in ("EMAIL_SENDER_NAME", "EMAIL_FROM_NAME", "MAIL_FROM_NAME", "SENDER_NAME"):
            self.assertEqual(self.load({alias: "Sender"}).email_sender_name, "Sender")
        for alias in ("RESEND_FROM", "EMAIL_FROM", "MAIL_FROM"):
            self.assertEqual(self.load({alias: "sender@example.test"}).resend_from, "sender@example.test")
        for alias in ("SYSTEM_NOTICE_EMAIL_TO", "EMAIL_HOME_ADDRESS", "EMAIL_HOME_CHANNEL"):
            self.assertEqual(self.load({alias: "ops@example.test"}).initial_settings["system_notice_email_to"], "ops@example.test")

    def test_pubspec_version_explicit_aliases_and_build_metadata(self):
        (self.root / "pubspec.yaml").write_text("name: duoyi\nversion: 2.3.4+567\n", encoding="utf-8")
        settings = self.load()
        self.assertEqual((settings.app_current_version, settings.app_current_version_code), ("2.3.4", 567))
        settings = self.load({"DUOYI_APP_VERSION": "3.0.0", "DUOYI_APP_VERSION_CODE": "789", "BUILD_GIT_SHA": "abc", "BUILD_TIME": "2026-01-01"})
        self.assertEqual((settings.app_current_version, settings.app_current_version_code), ("3.0.0", 789))
        self.assertEqual((settings.build_git_sha, settings.build_time), ("abc", "2026-01-01"))
        settings = self.load({"APP_CURRENT_VERSION": "4.0.0", "DUOYI_APP_VERSION": "3.0.0", "APP_CURRENT_VERSION_CODE": "900", "DUOYI_APP_VERSION_CODE": "789", "GIT_SHA": "first", "BUILD_GIT_SHA": "second"})
        self.assertEqual((settings.app_current_version, settings.app_current_version_code), ("4.0.0", 900))
        self.assertEqual(settings.build_git_sha, "first")

    def test_private_values_are_absent_from_repr_and_environment_is_untouched(self):
        environment = {
            "ADMIN_BOOTSTRAP_PASSWORD": "private-password", "PASSWORD_HASH_SALT": "private-salt",
            "AI_API_KEY": "private-ai-key", "EMAIL_PASSWORD": "private-mail-password",
            "RESEND_API_KEY": "private-resend-key", "OPENCLAW_MAIL_KEY": "private-claw-key",
            "OPENLIST_PASSWORD": "private-webdav-password",
        }
        before = dict(environment)
        settings = self.load(environment)
        for secret in environment.values():
            self.assertNotIn(secret, repr(settings))
            self.assertNotIn(secret, repr(settings.environment))
        spaced_salt = "  private-existing-salt  "
        self.assertEqual(self.load({"PASSWORD_HASH_SALT": spaced_salt}).password_hash_salt, spaced_salt)
        self.assertEqual(environment, before)

    def test_import_and_explicit_db_path_never_open_database(self):
        path = self.root / "never-created.db"
        with patch.object(config.sqlite3, "connect", side_effect=AssertionError("database opened")):
            self.load({"DUOYI_DB_PATH": str(path)})
            importlib.reload(config)
        self.assertFalse(path.exists())

    def test_legacy_db_selection_is_preserved(self):
        for filename, user_count in (("duoyi.db", 1), (config._legacy_db_filename(), 3)):
            with closing(sqlite3.connect(self.root / filename)) as db, db:
                db.execute("CREATE TABLE users(id INTEGER)")
                db.executemany("INSERT INTO users VALUES(?)", [(number,) for number in range(user_count)])
        self.assertEqual(self.load().db_path, str(self.root / config._legacy_db_filename()))

    def test_example_env_has_no_bootstrap_password_or_sender_identity(self):
        example = Path(__file__).with_name(".env.example")
        settings = self.load(env_file=example)
        self.assertEqual(settings.admin_bootstrap_password, "")
        self.assertIs(settings.initial_settings["registration_email_required"], False)
        for key in ("ai_api_key", "email_smtp_password", "resend_api_key", "openclaw_mail_api_key", "openlist_password", "resend_from"):
            self.assertEqual(settings.initial_settings[key], "")


class SettingsDatabaseTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temporary = tempfile.TemporaryDirectory()
        cls.addClassCleanup(temporary.cleanup)
        with patch.dict(os.environ, {
            "DUOYI_DB_PATH": str(Path(temporary.name) / "import.db"),
            "DUOYI_ENV_FILE": "", "ADMIN_BOOTSTRAP_PASSWORD": "admin123", "APP_UPDATE_REPOSITORY": "",
        }, clear=True):
            cls.api = importlib.import_module(f"{__package__}.main" if __package__ else "main")

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.settings = config.load_settings({
            "DUOYI_DB_PATH": str(self.root / "db.sqlite"), "DUOYI_ENV_FILE": "",
            "ADMIN_BOOTSTRAP_PASSWORD": "admin123", "APP_UPDATE_REPOSITORY": "",
        })
        aliases = patch.multiple(
            self.api, SETTINGS=self.settings, DB_PATH=self.settings.db_path,
            ADMIN_BOOTSTRAP_USER=self.settings.admin_bootstrap_user,
            ADMIN_BOOTSTRAP_PASSWORD=self.settings.admin_bootstrap_password,
            _env_present=self.settings.environment.present,
        )
        aliases.start()
        self.addCleanup(aliases.stop)
        self.api.init_db()

    def test_existing_db_settings_are_not_reseeded(self):
        custom = {
            "ai_base_url": "https://custom.example.test", "ai_api_key": "saved-secret",
            "ai_model": "saved-model", "email_smtp_password": "saved-mail-secret",
            "server_backup_enabled": False, "registration_email_required": False,
            "registration_enabled": False, "invite_code_required": True,
            "email_code_login_enabled": True,
        }
        with closing(self.api.get_db()) as db, db:
            for key, value in custom.items():
                self.api._setting_set(db, key, value)
            db.execute("DELETE FROM settings WHERE key IN ('allow_public_registration', 'registration_invite_required')")
        self.api.init_db()
        with closing(self.api.get_db()) as db, db:
            for key, value in custom.items():
                self.assertEqual(self.api._setting_get(db, key, None), value)
            self.assertFalse(self.api._setting_get(db, "allow_public_registration", None))
            self.assertTrue(self.api._setting_get(db, "registration_invite_required", None))

    def test_explicit_file_registration_policy_survives_env_removal_and_restart(self):
        for required in (False, True):
            with self.subTest(required=required):
                env_file = self.root / f"registration-{required}.env"
                env_file.write_text(f"REGISTRATION_EMAIL_REQUIRED={str(required).lower()}\n", encoding="utf-8")
                settings = config.load_settings({}, env_file=env_file, backend_dir=self.root)
                with patch.multiple(self.api, SETTINGS=settings, DB_PATH=str(self.root / f"explicit-{required}.db"), _env_present=settings.environment.present):
                    self.api.init_db()
                    with closing(self.api.get_db()) as db:
                        self.assertIs(self.api._setting_get(db, "registration_email_required"), required)
                        self.assertIsNone(self.api._setting_get(db, "registration_email_required_default_on_migrated"))
                    with patch.multiple(self.api, SETTINGS=self.settings, _env_present=self.settings.environment.present):
                        self.api.init_db()
                        self.api.init_db()
                        with closing(self.api.get_db()) as db:
                            self.assertIs(self.api._setting_get(db, "registration_email_required"), required)
                            self.assertIsNone(self.api._setting_get(db, "registration_email_required_default_on_migrated"))

    def test_stored_registration_email_policy_overrides_environment_and_legacy_marker(self):
        for required in (False, True):
            for marker in (None, True):
                with closing(self.api.get_db()) as db, db:
                    self.api._setting_set(db, "registration_email_required", required)
                    db.execute("DELETE FROM settings WHERE key='registration_email_required_default_on_migrated'")
                    if marker is not None:
                        self.api._setting_set(db, "registration_email_required_default_on_migrated", marker)
                for environment_value in (None, "false", "true"):
                    with self.subTest(required=required, marker=marker, environment=environment_value):
                        environment = {"DUOYI_ENV_FILE": "", "DUOYI_DB_PATH": self.api.DB_PATH}
                        if environment_value is not None:
                            environment["REGISTRATION_EMAIL_REQUIRED"] = environment_value
                        settings = config.load_settings(environment, backend_dir=self.root)
                        with patch.multiple(self.api, SETTINGS=settings, _env_present=settings.environment.present):
                            self.api.init_db()
                            with closing(self.api.get_db()) as db:
                                self.assertIs(self.api._setting_get(db, "registration_email_required"), required)
                                self.assertIs(self.api._setting_get(db, "registration_email_required_default_on_migrated"), marker)
                            self.assertIs(self.api.public_config()["registration_email_required"], required)

    def test_explicit_bootstrap_password_hash_is_preserved_on_restart(self):
        with patch.object(self.api, "ADMIN_BOOTSTRAP_PASSWORD", ""):
            self.api.init_db()
        with closing(self.api.get_db()) as db:
            saved = db.execute("SELECT password_hash FROM users WHERE username='admin'").fetchone()[0]
        self.assertEqual(saved, hashlib.sha256((config.LEGACY_PASSWORD_HASH_SALT + "admin123").encode()).hexdigest())
        self.assertFalse(Path(self.api.DB_PATH + ".bootstrap-admin.json").exists())

    def test_unconfigured_openclaw_tool_returns_actionable_error(self):
        with patch.object(self.api, "OPENCLAW_MAIL_SCRIPT", ""), patch.object(self.api.subprocess, "run") as run:
            result = self.api._openclaw_mail_send_email(
                runtime={"openclaw_mail_enabled": True, "openclaw_mail_user": "test-user", "openclaw_mail_api_key": "private-token"},
                to_addr="recipient@example.test", subject="test", body="test",
            )
        self.assertFalse(result["sent"])
        self.assertIn("OPENCLAW_MAIL_SCRIPT", result["detail"])
        self.assertNotIn("private-token", result["detail"])
        run.assert_not_called()

    def test_both_legacy_env_int_signatures_remain_supported(self):
        self.assertEqual(self.api._env_int("NONEXISTENT_TEST_KEY", 42), 42)
        self.assertEqual(self.api._env_int("NONEXISTENT_TEST_KEY", "ANOTHER_TEST_KEY", default=43), 43)

    def test_package_import_works_with_isolated_database(self):
        environment = dict(os.environ)
        environment.update({
            "DUOYI_DB_PATH": str(self.root / "package.db"), "DUOYI_ENV_FILE": "",
            "ADMIN_BOOTSTRAP_PASSWORD": "test-only-password", "APP_UPDATE_REPOSITORY": "",
            "PYTHONDONTWRITEBYTECODE": "1",
        })
        result = subprocess.run(
            [sys.executable, "-c", "from backend import main; assert main.APP_UPDATE_REPOSITORY == ''"],
            cwd=Path(__file__).resolve().parents[1], env=environment, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)


class BootstrapDatabaseTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temporary = tempfile.TemporaryDirectory()
        cls.addClassCleanup(temporary.cleanup)
        with patch.dict(os.environ, {
            "DUOYI_DB_PATH": str(Path(temporary.name) / "import.db"),
            "DUOYI_ENV_FILE": "", "APP_UPDATE_REPOSITORY": "",
        }, clear=True):
            cls.api = importlib.import_module(f"{__package__}.main" if __package__ else "main")

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.db_path = self.root / "fresh.db"
        self.credentials_path = self.root / "fresh.db.bootstrap-admin.json"
        settings = config.load_settings({
            "DUOYI_DB_PATH": str(self.db_path), "DUOYI_ENV_FILE": "",
            "APP_UPDATE_REPOSITORY": "", "REGISTRATION_EMAIL_REQUIRED": "false",
        })
        aliases = patch.multiple(
            self.api, SETTINGS=settings, DB_PATH=settings.db_path,
            ADMIN_BOOTSTRAP_USER=settings.admin_bootstrap_user,
            ADMIN_BOOTSTRAP_PASSWORD=settings.admin_bootstrap_password,
            _env_present=settings.environment.present,
        )
        aliases.start()
        self.addCleanup(aliases.stop)
        self.addCleanup(self.api.TOKENS.clear)
        self.addCleanup(self.api.TOKEN_LAST_ACTIVE.clear)
        self.client = TestClient(self.api.app)
        self.addCleanup(self.client.close)

    def _credentials(self):
        return json.loads(self.credentials_path.read_text(encoding="utf-8"))

    def _login(self, username, password):
        return self.client.post("/api/auth/login", json={"username": username, "password": password})

    def _assert_database_empty(self):
        with closing(self.api.get_db()) as db:
            self.assertIsNone(db.execute("SELECT 1 FROM sqlite_master LIMIT 1").fetchone())

    def test_fresh_database_generates_private_credentials_and_can_login(self):
        output = io.StringIO()
        with redirect_stdout(output), redirect_stderr(output), patch.object(
            self.api.secrets, "token_urlsafe", wraps=self.api.secrets.token_urlsafe,
        ) as generate:
            self.api.init_db()
        generate.assert_called_once_with(32)
        credentials = self._credentials()
        self.assertEqual(credentials["username"], "admin")
        self.assertRegex(credentials["password"], r"^[A-Za-z0-9_-]{43}$")
        self.assertEqual(stat.S_IMODE(self.credentials_path.stat().st_mode), 0o600)
        self.assertNotIn(credentials["password"], output.getvalue())
        with closing(self.api.get_db()) as db:
            row = db.execute("SELECT * FROM users").fetchone()
            self.assertEqual(row["password_hash"], self.api._hash_password(credentials["password"]))
            self.assertEqual(row["is_admin"], 1)
            self.assertEqual(row["role_id"], "role_admin")
            self.assertEqual(json.loads(row["admin_permissions"]), ["*"])
            self.assertEqual(db.execute("SELECT COUNT(*) FROM sync_data").fetchone()[0], 1)
            self.assertEqual(db.execute("SELECT COUNT(*) FROM workspaces").fetchone()[0], 1)
        self.assertNotIn(credentials["password"].encode(), self.db_path.read_bytes())
        response = self._login(**credentials)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertTrue(response.json()["is_admin"])
        self.assertNotIn(credentials["password"], response.text)
        allowed = self.client.get("/api/admin/users", headers={"Authorization": "Bearer " + response.json()["token"]})
        self.assertEqual(allowed.status_code, 200, allowed.text)

    def test_restart_preserves_generated_file_and_changed_password_hash(self):
        self.api.init_db()
        original = self.credentials_path.read_bytes()
        original_stat = self.credentials_path.stat()
        changed_hash = self.api._hash_password("changed-admin-password")
        with closing(self.api.get_db()) as db, db:
            db.execute("UPDATE users SET password_hash=?", (changed_hash,))
        with patch.object(self.api.secrets, "token_urlsafe", side_effect=AssertionError("password regenerated")):
            self.api.init_db()
            with patch.multiple(self.api, ADMIN_BOOTSTRAP_USER="another-admin", ADMIN_BOOTSTRAP_PASSWORD="replacement"):
                self.api.init_db()
            self.assertEqual(self.credentials_path.read_bytes(), original)
            self.assertEqual(self.credentials_path.stat().st_mtime_ns, original_stat.st_mtime_ns)
            self.assertEqual(self.credentials_path.stat().st_ino, original_stat.st_ino)
            self.credentials_path.unlink()
            self.api.init_db()
        self.assertFalse(self.credentials_path.exists())
        with closing(self.api.get_db()) as db:
            rows = db.execute("SELECT username, password_hash FROM users").fetchall()
        self.assertEqual([(row["username"], row["password_hash"]) for row in rows], [("admin", changed_hash)])
        self.assertEqual(self._login("admin", "changed-admin-password").status_code, 200)
        self.assertEqual(self._login(**json.loads(original)).status_code, 401)

    def test_explicit_bootstrap_credentials_need_no_generated_file(self):
        with patch.multiple(self.api, ADMIN_BOOTSTRAP_USER="operator", ADMIN_BOOTSTRAP_PASSWORD="operator-password"), patch.object(
            self.api.secrets, "token_urlsafe", side_effect=AssertionError("generated despite explicit password"),
        ):
            self.api.init_db()
        self.assertFalse(self.credentials_path.exists())
        response = self._login("operator", "operator-password")
        self.assertEqual(response.status_code, 200, response.text)
        self.assertTrue(response.json()["is_admin"])

    def test_existing_custom_admin_and_data_survive_default_bootstrap(self):
        with patch.multiple(self.api, ADMIN_BOOTSTRAP_USER="custom-owner", ADMIN_BOOTSTRAP_PASSWORD="existing-password"):
            self.api.init_db()
        with closing(self.api.get_db()) as db, db:
            db.execute("UPDATE sync_data SET todos=?", ('[{"id":"saved-task"}]',))
            saved = dict(db.execute("SELECT * FROM users").fetchone())
            self.api._setting_set(db, "maintenance_message", "saved-setting")
        for password in ("", "new-configured-password"):
            with self.subTest(password_configured=bool(password)), patch.object(self.api, "ADMIN_BOOTSTRAP_PASSWORD", password):
                self.api.init_db()
                with closing(self.api.get_db()) as db:
                    self.assertEqual([dict(row) for row in db.execute("SELECT * FROM users")], [saved])
                    self.assertEqual(db.execute("SELECT todos FROM sync_data").fetchone()[0], '[{"id":"saved-task"}]')
                    self.assertEqual(self.api._setting_get(db, "maintenance_message", ""), "saved-setting")
        self.assertFalse(self.credentials_path.exists())
        self.assertEqual(self._login("custom-owner", "existing-password").status_code, 200)

    def test_existing_ordinary_user_named_admin_is_not_promoted_or_reset(self):
        with patch.object(self.api, "ADMIN_BOOTSTRAP_PASSWORD", "existing-password"):
            self.api.init_db()
        with closing(self.api.get_db()) as db, db:
            db.execute("UPDATE users SET is_admin=0, admin_permissions='[]', role_id='role_user'")
            saved = dict(db.execute("SELECT * FROM users").fetchone())
        for password in ("", "new-configured-password"):
            with self.subTest(password_configured=bool(password)), patch.object(self.api, "ADMIN_BOOTSTRAP_PASSWORD", password):
                self.api.init_db()
                with closing(self.api.get_db()) as db:
                    self.assertEqual([dict(row) for row in db.execute("SELECT * FROM users")], [saved])
        self.assertFalse(self.credentials_path.exists())
        response = self._login("admin", "existing-password")
        self.assertEqual(response.status_code, 200, response.text)
        self.assertFalse(response.json()["is_admin"])
        denied = self.client.get("/api/admin/users", headers={"Authorization": "Bearer " + response.json()["token"]})
        self.assertEqual(denied.status_code, 403)

    def test_existing_installation_with_no_users_does_not_receive_new_admin(self):
        with patch.object(self.api, "ADMIN_BOOTSTRAP_PASSWORD", "existing-password"):
            self.api.init_db()
        with closing(self.api.get_db()) as db, db:
            db.execute("DELETE FROM users")
        for password in ("", "new-configured-password"):
            with self.subTest(password_configured=bool(password)), patch.object(self.api, "ADMIN_BOOTSTRAP_PASSWORD", password):
                self.api.init_db()
                with closing(self.api.get_db()) as db:
                    self.assertEqual(db.execute("SELECT COUNT(*) FROM users").fetchone()[0], 0)
        self.assertFalse(self.credentials_path.exists())

    def test_public_bootstrap_config_and_registration_do_not_expose_admin_secrets_or_roles(self):
        self.api.init_db()
        credentials = self._credentials()
        with closing(self.api.get_db()) as db:
            password_hash = db.execute("SELECT password_hash FROM users").fetchone()[0]
        for path in ("/api/bootstrap", "/api/config", "/api/health"):
            with self.subTest(path=path):
                response = self.client.get(path)
                self.assertEqual(response.status_code, 200, response.text)
                for private in (credentials["password"], password_hash, str(self.credentials_path), "bootstrap_password", "bootstrap_credentials"):
                    self.assertNotIn(private, response.text)
        response = self.client.post("/api/auth/register", json={
            "username": "public-user", "password": "ordinary-user-password",
            "is_admin": True, "role_id": "role_admin", "admin_permissions": ["*"],
        })
        self.assertEqual(response.status_code, 200, response.text)
        self.assertFalse(response.json()["is_admin"])
        with closing(self.api.get_db()) as db:
            row = db.execute("SELECT * FROM users WHERE username='public-user'").fetchone()
            self.assertEqual(row["is_admin"], 0)
            self.assertEqual(row["role_id"], "role_user")
            self.assertEqual(json.loads(row["admin_permissions"]), [])
        denied = self.client.get("/api/admin/users", headers={"Authorization": "Bearer " + response.json()["token"]})
        self.assertEqual(denied.status_code, 403)

    def test_file_creation_and_write_failure_roll_back_without_leaking_secret(self):
        secret = "private-generated-test-secret"
        for operation in ("open", "fsync"):
            with self.subTest(operation=operation), patch.object(self.api.secrets, "token_urlsafe", return_value=secret), patch.object(
                self.api.os, operation, side_effect=OSError(secret),
            ), self.assertRaises(self.api.ConfigurationError) as failure:
                self.api.init_db()
            self.assertNotIn(secret, str(failure.exception))
            self.assertFalse(self.credentials_path.exists())
            self._assert_database_empty()
        self.api.init_db()
        self.assertEqual(self._login(**self._credentials()).status_code, 200)

    def test_existing_credentials_file_or_symlink_is_never_overwritten(self):
        target = self.root / "operator-file"
        target.write_text("keep-existing-content", encoding="utf-8")
        for symlink in (False, True):
            with self.subTest(symlink=symlink):
                if symlink:
                    self.credentials_path.symlink_to(target)
                else:
                    self.credentials_path.write_text("keep-existing-content", encoding="utf-8")
                with self.assertRaises(self.api.ConfigurationError):
                    self.api.init_db()
                self.assertEqual(self.credentials_path.read_text(), "keep-existing-content")
                self.assertEqual(target.read_text(), "keep-existing-content")
                self._assert_database_empty()
                self.credentials_path.unlink()

    def test_unrelated_db_failure_does_not_persist_generated_credentials(self):
        with patch.object(self.api, "_ensure_private_workspace", side_effect=sqlite3.DatabaseError("workspace insert failed")), self.assertRaises(sqlite3.DatabaseError):
            self.api.init_db()
        self.assertFalse(self.credentials_path.exists())
        self._assert_database_empty()
        self.api.init_db()
        self.assertEqual(self._login(**self._credentials()).status_code, 200)

    def test_commit_failure_removes_generated_credentials_and_rolls_back(self):
        connection = Mock(wraps=self.api.get_db())

        def failed_commit():
            self.assertTrue(self.credentials_path.exists())
            raise sqlite3.OperationalError("commit failed")

        connection.commit.side_effect = failed_commit
        with patch.object(self.api, "get_db", return_value=connection), self.assertRaises(sqlite3.OperationalError):
            self.api.init_db()
        connection.rollback.assert_called_once()
        connection.close.assert_called_once()
        self.assertFalse(self.credentials_path.exists())
        self._assert_database_empty()

    def test_concurrent_initialization_creates_one_working_admin_and_secret(self):
        barrier = Barrier(4)

        def initialize():
            barrier.wait(timeout=10)
            self.api.init_db()

        with patch.object(self.api.secrets, "token_urlsafe", wraps=self.api.secrets.token_urlsafe) as generate:
            with ThreadPoolExecutor(max_workers=4) as executor:
                futures = [executor.submit(initialize) for _ in range(4)]
                for future in futures:
                    future.result(timeout=15)
        generate.assert_called_once_with(32)
        with closing(self.api.get_db()) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM users").fetchone()[0], 1)
        self.assertEqual(stat.S_IMODE(self.credentials_path.stat().st_mode), 0o600)
        self.assertEqual(self._login(**self._credentials()).status_code, 200)


if __name__ == "__main__":
    unittest.main()
