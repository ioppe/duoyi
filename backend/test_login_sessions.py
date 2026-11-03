"""Persistent login-session contracts, exercised through real HTTP/WS lifecycles."""

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from datetime import timedelta
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

with patch.dict(os.environ, {"ADMIN_BOOTSTRAP_PASSWORD": "admin123"}):
    import main as api

BACKEND_DIR = Path(__file__).resolve().parent


class LoginSessionApiTest(unittest.TestCase):
    websocket_path = "/ws/focus-rooms/session-room/events"

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="duoyi-login-sessions-")
        self.addCleanup(temporary.cleanup)
        for name, value in (
            ("DB_PATH", os.path.join(temporary.name, "sessions.db")),
            ("TOKENS", {}),
            ("TOKEN_LAST_ACTIVE", {}),
        ):
            override = patch.object(api, name, value)
            override.start()
            self.addCleanup(override.stop)
        api.init_db()
        self._execute("UPDATE settings SET value='false' WHERE key='registration_email_required'")
        self.client = TestClient(api.app).__enter__()
        self.addCleanup(lambda: self.client.__exit__(None, None, None))
        self.owner = self._register("session-owner")
        self._execute(
            "UPDATE users SET email='session-owner@example.invalid', email_verified=1 WHERE id=?",
            (self.owner["user_id"],),
        )

    @staticmethod
    def _headers(token):
        return {"Authorization": f"Bearer {token}"}

    def _execute(self, sql, parameters=()):
        db = api.get_db()
        try:
            rows = db.execute(sql, parameters).fetchall()
            db.commit()
            return rows
        finally:
            db.close()

    def _register(self, name):
        response = self.client.post(
            "/api/auth/register", json={"username": name, "password": "pass123456"}
        )
        self.assertEqual(response.status_code, 200)
        return response.json()

    def _login(self, name, password="pass123456"):
        response = self.client.post(
            "/api/auth/login", json={"username": name, "password": password}
        )
        self.assertEqual(response.status_code, 200)
        return response.json()["token"]

    def _me(self, token):
        return self.client.get("/api/auth/me", headers=self._headers(token))

    def _pat(self, credential, name="phone"):
        response = self.client.post(
            "/api/auth/tokens", headers=self._headers(credential), json={"name": name}
        )
        self.assertEqual(response.status_code, 200)
        return response.json()["token"]

    def _restart(self):
        """Simulate a process restart: no memory cache, schema initialized twice."""
        api.TOKENS.clear()
        api.TOKEN_LAST_ACTIVE.clear()
        api.init_db()
        api.init_db()

    def _assert_ws_ok(self, token):
        with self.client.websocket_connect(
            self.websocket_path, headers=self._headers(token)
        ) as websocket:
            self.assertEqual(websocket.receive_json()["event"], "ranking")

    def _assert_ws_rejected(self, token):
        with self.assertRaises(WebSocketDisconnect) as closed:
            with self.client.websocket_connect(
                self.websocket_path, headers=self._headers(token)
            ):
                self.fail("Rejected credential opened a WebSocket")
        self.assertEqual(closed.exception.code, 1008)

    def _admin_headers(self, name="session-admin"):
        admin = self._register(name)
        self._execute(
            "UPDATE users SET is_admin=1, role_id='role_admin', admin_permissions=? WHERE id=?",
            (json.dumps(["*"]), admin["user_id"]),
        )
        return self._headers(admin["token"])

    def _enable_email_login(self):
        db = api.get_db()
        try:
            for key, value in {
                "email_code_login_enabled": True,
                "email_service_enabled": True,
                "email_code_primary_provider": "smtp",
                "email_smtp_host": "smtp.example.test",
                "email_smtp_username": "sender@example.test",
                "email_smtp_password": "test-mail-secret",
            }.items():
                api._setting_set(db, key, value)
            db.commit()
        finally:
            db.close()

    def _session_rows(self, user_id):
        return self._execute(
            "SELECT user_id, token_hash, created_at, expires_at, last_used_at "
            "FROM login_sessions WHERE user_id=?",
            (user_id,),
        )

    def test_password_login_persists_hash_only_session_across_restart(self):
        token = self._login("session-owner")
        self.assertEqual(self._me(token).status_code, 200)

        rows = self._session_rows(self.owner["user_id"])
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["token_hash"], api._hash_login_session_token(token))
        self.assertEqual(
            rows[0]["token_hash"], hashlib.sha256(token.encode("utf-8")).hexdigest()
        )
        self.assertFalse(any(value == token for value in rows[0]))
        self.assertNotIn(token.encode("utf-8"), Path(api.DB_PATH).read_bytes())
        self.assertNotIn(b"pass123456", Path(api.DB_PATH).read_bytes())
        db = api.get_db()
        try:
            self.assertNotIn(token, "\n".join(db.iterdump()))
        finally:
            db.close()

        self._restart()
        self.assertEqual(self._me(token).status_code, 200)
        self._assert_ws_ok(token)
        # A login session is not an access token and never shows up in the manager.
        listed = self.client.get("/api/auth/tokens", headers=self._headers(token))
        self.assertEqual(listed.status_code, 200)
        self.assertEqual(listed.json(), {"tokens": []})
        self.assertEqual(listed.json().get("token"), None)
        self.assertFalse(api.TOKENS)

    def test_registration_and_email_login_issue_persistent_sessions(self):
        registration_token = self.owner["token"]
        self.assertEqual(self._session_rows(self.owner["user_id"])[0]["token_hash"],
                         api._hash_login_session_token(registration_token))
        self._restart()
        self.assertEqual(self._me(registration_token).status_code, 200)

        self._enable_email_login()
        db = api.get_db()
        try:
            code = api._create_email_code(
                db,
                email="session-owner@example.invalid",
                purpose="login",
                user_id=self.owner["user_id"],
            )["code"]
            db.commit()
        finally:
            db.close()
        response = self.client.post(
            "/api/auth/email-login",
            json={"email": "session-owner@example.invalid", "code": code},
        )
        self.assertEqual(response.status_code, 200)
        email_token = response.json()["token"]
        self.assertEqual(self._session_rows(self.owner["user_id"])[0]["token_hash"],
                         api._hash_login_session_token(email_token))

        self._restart()
        self.assertEqual(self._me(email_token).status_code, 200)
        self.assertEqual(self._me(registration_token).status_code, 401)

    def test_new_login_replaces_previous_session_even_after_cache_clear(self):
        old_token = self._login("session-owner")
        new_token = self._login("session-owner")

        self.assertEqual(self._me(old_token).status_code, 401)
        self.assertEqual(self._me(new_token).status_code, 200)
        self._restart()
        self.assertEqual(self._me(old_token).status_code, 401)
        self._assert_ws_rejected(old_token)
        self.assertEqual(self._me(new_token).status_code, 200)
        self.assertEqual(len(self._session_rows(self.owner["user_id"])), 1)

    def test_old_logout_cannot_revoke_session_rotated_after_dependency_check(self):
        old_token = self._login("session-owner")
        rotated = []

        def authenticate_then_rotate():
            user_id = api._verify_token_value(old_token)
            payload = api.login(api.LoginRequest(
                username="session-owner", password="pass123456"
            ))
            rotated.append(payload["token"])
            return user_id

        api.app.dependency_overrides[api._verify_token] = authenticate_then_rotate
        try:
            response = self.client.post(
                "/api/auth/logout", headers=self._headers(old_token)
            )
        finally:
            api.app.dependency_overrides.pop(api._verify_token, None)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(rotated), 1)
        self.assertTrue(api.TOKENS[self.owner["user_id"]] == rotated[0])
        self.assertEqual(self._me(rotated[0]).status_code, 200)
        self._restart()
        self.assertEqual(self._me(rotated[0]).status_code, 200)
        self.assertEqual(self._me(old_token).status_code, 401)

    def test_session_logout_survives_restart_and_keeps_pats(self):
        session_token = self._login("session-owner")
        pat = self._pat(session_token)

        response = self.client.post(
            "/api/auth/logout", headers=self._headers(session_token)
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})
        self.assertNotIn(self.owner["user_id"], api.TOKENS)
        self.assertEqual(self._session_rows(self.owner["user_id"]), [])
        self.assertEqual(self._me(session_token).status_code, 401)
        self.assertEqual(self._me(pat).status_code, 200)

        self._restart()
        self.assertEqual(self._me(session_token).status_code, 401)
        self._assert_ws_rejected(session_token)
        self.assertEqual(self._me(pat).status_code, 200)
        self._assert_ws_ok(pat)

    def test_pat_logout_keeps_login_session(self):
        session_token = self._login("session-owner")
        pat = self._pat(session_token)

        response = self.client.post("/api/auth/logout", headers=self._headers(pat))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self._me(pat).status_code, 401)
        self.assertEqual(self._me(session_token).status_code, 200)
        self._restart()
        self.assertEqual(self._me(session_token).status_code, 200)
        self.assertEqual(self._me(pat).status_code, 401)

    def _assert_security_change_revokes_everything(self, change):
        user = self._register(f"victim-{change}")
        session_token = self._login(f"victim-{change}")
        pat = self._pat(session_token, "laptop")
        admin = self._admin_headers(f"admin-{change}")
        user_id = user["user_id"]

        if change == "password":
            response = self.client.post(
                "/api/auth/change-password",
                headers=self._headers(session_token),
                json={"current_password": "pass123456", "new_password": "newpass123456"},
            )
        elif change == "disable":
            response = self.client.patch(
                f"/api/admin/users/{user_id}", headers=admin, json={"is_disabled": True}
            )
        elif change == "delete":
            response = self.client.delete(f"/api/admin/users/{user_id}", headers=admin)
        else:  # force re-login on every device
            response = self.client.patch(
                f"/api/admin/users/{user_id}",
                headers=admin,
                json={"new_password": "newpass123456"},
            )
        self.assertEqual(response.status_code, 200)

        for credential in (session_token, pat):
            self.assertEqual(self._me(credential).status_code, 401)
            self._assert_ws_rejected(credential)
        self.assertEqual(self._session_rows(user_id), [])

        self._restart()
        for credential in (session_token, pat):
            self.assertEqual(self._me(credential).status_code, 401)
            self._assert_ws_rejected(credential)
        self.assertEqual(self._session_rows(user_id), [])

    def test_security_changes_revoke_session_and_pats(self):
        for change in ("password", "disable", "delete", "force"):
            with self.subTest(change=change):
                self._assert_security_change_revokes_everything(change)

    def test_session_expiry_boundary_rejects_even_with_cached_alias(self):
        now = api._utc_now().replace(microsecond=0)
        with patch.object(api, "_utc_now", return_value=now):
            token = self._login("session-owner")

        row = self._session_rows(self.owner["user_id"])[0]
        self.assertEqual(api._parse_server_time(row["created_at"]), now)
        self.assertEqual(
            api._parse_server_time(row["expires_at"]), now + timedelta(days=30)
        )
        deadline = api._parse_server_time(row["expires_at"])

        with patch.object(api, "_utc_now", return_value=deadline - timedelta(seconds=1)):
            self.assertEqual(self._me(token).status_code, 200)
            self._assert_ws_ok(token)

        for moment in (deadline, deadline + timedelta(seconds=1)):
            with patch.object(api, "_utc_now", return_value=moment):
                self.assertEqual(self._me(token).status_code, 401)
                self.assertNotIn(token, api.TOKENS.values())
                self._assert_ws_rejected(token)

        # Expiry rejects the credential; it is not a memory-cache accident.
        with patch.object(api, "_utc_now", return_value=deadline - timedelta(seconds=1)):
            self.assertEqual(self._me(token).status_code, 200)

    def test_settings_and_sync_preferences_survive_session_upgrade_and_restart(self):
        settings = {
            "ai_base_url": "https://ai.example.invalid/v1",
            "ai_model": "example-model",
            "email_smtp_host": "smtp.example.invalid",
            "email_code_login_enabled": False,
            "registration_email_required": False,
            "allow_public_registration": True,
        }
        marker = {"schema": "sync-v2", "migrationMarker": "keep-me"}
        db = api.get_db()
        try:
            for key, value in settings.items():
                api._setting_set(db, key, value)
            db.execute(
                "UPDATE sync_data SET preferences=? WHERE user_id=?",
                (json.dumps(marker, ensure_ascii=False), self.owner["user_id"]),
            )
            db.commit()
        finally:
            db.close()

        token = self._login("session-owner")
        self._restart()

        db = api.get_db()
        try:
            stored = {key: api._setting_get(db, key) for key in settings}
            preferences = db.execute(
                "SELECT preferences FROM sync_data WHERE user_id=?",
                (self.owner["user_id"],),
            ).fetchone()["preferences"]
        finally:
            db.close()
        self.assertEqual(stored, settings)
        self.assertEqual(json.loads(preferences), marker)
        self.assertEqual(self._me(token).status_code, 200)

    def test_old_database_gains_session_table_idempotently(self):
        db = api.get_db()
        try:
            users_before = [
                tuple(row)
                for row in db.execute(
                    "SELECT id, username, password_hash, role_id, group_id, is_disabled "
                    "FROM users ORDER BY id"
                ).fetchall()
            ]
            settings_before = [
                tuple(row)
                for row in db.execute("SELECT key, value FROM settings ORDER BY key").fetchall()
            ]
            db.execute("DROP TABLE login_sessions")
            db.commit()
        finally:
            db.close()

        self._restart()

        db = api.get_db()
        try:
            self.assertIsNotNone(
                db.execute(
                    "SELECT name FROM sqlite_master WHERE type='table' AND name='login_sessions'"
                ).fetchone()
            )
            self.assertIsNotNone(
                db.execute(
                    "SELECT name FROM sqlite_master WHERE type='index' "
                    "AND name='idx_login_sessions_expires'"
                ).fetchone()
            )
            self.assertEqual(db.execute("SELECT * FROM login_sessions").fetchall(), [])
            self.assertEqual(
                [
                    tuple(row)
                    for row in db.execute(
                        "SELECT id, username, password_hash, role_id, group_id, is_disabled "
                        "FROM users ORDER BY id"
                    ).fetchall()
                ],
                users_before,
            )
            self.assertEqual(
                [
                    tuple(row)
                    for row in db.execute(
                        "SELECT key, value FROM settings ORDER BY key"
                    ).fetchall()
                ],
                settings_before,
            )
        finally:
            db.close()

    def test_contract_advertises_persistent_login_sessions(self):
        payload = self.client.get("/api/config").json()
        self.assertEqual(payload["api_contract_version"], api.API_CONTRACT_VERSION)
        self.assertTrue(payload["features"]["persistent_login_sessions"])
        self.assertTrue(payload["features"]["access_tokens"])

    def test_session_survives_real_process_restart(self):
        script = textwrap.dedent(
            """
            import os, sys
            from unittest.mock import patch
            with patch.dict(os.environ, {"ADMIN_BOOTSTRAP_PASSWORD": "admin123"}):
                import main as api
            from fastapi.testclient import TestClient

            api.DB_PATH = sys.argv[1]
            api.TOKENS.clear()
            api.TOKEN_LAST_ACTIVE.clear()
            api.init_db()
            db = api.get_db()
            api._setting_set(db, "registration_email_required", False)
            api._setting_set(db, "default_registration_coins", 0)
            db.commit()
            db.close()
            with TestClient(api.app) as client:
                if sys.argv[2] == "register":
                    response = client.post(
                        "/api/auth/register",
                        json={"username": "process-restart", "password": "pass123456"},
                    )
                    print("TOKEN:" + response.json()["token"])
                else:
                    response = client.get(
                        "/api/auth/me",
                        headers={"Authorization": "Bearer " + sys.argv[3]},
                    )
                    print("STATUS:" + str(response.status_code))
                    db = api.get_db()
                    try:
                        tables = sorted(
                            row[0]
                            for row in db.execute(
                                "SELECT name FROM sqlite_master WHERE type='table'"
                            ).fetchall()
                        )
                    finally:
                        db.close()
                    print("TABLES:" + ",".join(tables))
            """
        )
        environment = {**os.environ, "ADMIN_BOOTSTRAP_PASSWORD": "admin123"}

        def run(*arguments):
            completed = subprocess.run(
                [sys.executable, "-c", script, api.DB_PATH, *arguments],
                cwd=str(BACKEND_DIR),
                env=environment,
                capture_output=True,
                text=True,
                timeout=120,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr[-2000:])
            return completed.stdout

        first = run("register")
        token_line = next(line for line in first.splitlines() if line.startswith("TOKEN:"))
        token = token_line.removeprefix("TOKEN:")
        self.assertEqual(len(token), 64)
        self.assertNotIn(token.encode("utf-8"), Path(api.DB_PATH).read_bytes())

        second = run("check", token)
        self.assertIn("STATUS:200", second)
        self.assertIn("login_sessions", second)
        self.assertEqual(self._me(token).status_code, 200)


if __name__ == "__main__":
    unittest.main()
