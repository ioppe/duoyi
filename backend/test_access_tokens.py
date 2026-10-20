"""Persistent access-token contracts, exercised through real HTTP/WS lifecycles."""

import asyncio
import base64
import hashlib
import json
import os
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

with patch.dict(os.environ, {"ADMIN_BOOTSTRAP_PASSWORD": "admin123"}):
    import main as api


class AccessTokenApiTest(unittest.TestCase):
    metadata_keys = {
        "id", "name", "prefix", "created_at", "last_used_at", "expires_at",
        "revoked_at", "current",
    }
    websocket_paths = (
        "/ws/focus-rooms/token-test-room/events",
        "/ws/focus-leaderboard/global/events",
    )

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="duoyi-access-tokens-")
        self.addCleanup(temporary.cleanup)
        for name, value in (
            ("DB_PATH", os.path.join(temporary.name, "tokens.db")),
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
        self.owner = self._register("token-owner")
        self.other = self._register("token-other")
        self._execute(
            "UPDATE users SET email='token-owner@example.invalid', email_verified=1 WHERE id=?",
            (self.owner["user_id"],),
        )

    @staticmethod
    def _headers(token):
        return {"Authorization": f"Bearer {token}"}

    def _execute(self, sql, parameters=()):
        db = api.get_db()
        try:
            result = db.execute(sql, parameters)
            rows = result.fetchall()
            db.commit()
            return rows
        finally:
            db.close()

    def _register(self, name):
        response = self.client.post(
            "/api/auth/register", json={"username": name, "password": "pass123456"}
        )
        # Never include responses/credentials in assertion failure messages.
        self.assertEqual(response.status_code, 200)
        return response.json()

    def _create(self, name="Flutter phone", credential=None, days=None):
        response = self.client.post(
            "/api/auth/tokens",
            headers=self._headers(credential or self.owner["token"]),
            json={"name": name, "expires_in_days": days},
        )
        self.assertEqual(response.status_code, 200)
        return response.json()

    def _list(self, credential=None):
        response = self.client.get(
            "/api/auth/tokens", headers=self._headers(credential or self.owner["token"])
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(set(response.json()), {"tokens"})
        return response.json()["tokens"]

    def _assert_valid(self, token):
        response = self.client.get("/api/auth/me", headers=self._headers(token))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["user_id"], self.owner["user_id"])
        self.assertNotIn("token", response.json())

    def _assert_websocket_rejected(self, token, path=None):
        with self.assertRaises(WebSocketDisconnect) as closed:
            with self.client.websocket_connect(
                path or self.websocket_paths[0], headers=self._headers(token)
            ):
                self.fail("Invalid credential opened a WebSocket")
        self.assertEqual(closed.exception.code, 1008)

    def _assert_revoked(self, tokens, *, check_session=True):
        for token in tokens:
            response = self.client.get("/api/auth/me", headers=self._headers(token["token"]))
            self.assertEqual(response.status_code, 401)
            self._assert_websocket_rejected(token["token"])
        placeholders = ",".join("?" for _ in tokens)
        rows = self._execute(
            f"SELECT revoked_at FROM access_tokens WHERE id IN ({placeholders})",
            [token["id"] for token in tokens],
        )
        self.assertTrue(all(row["revoked_at"] is not None for row in rows))
        if check_session:
            response = self.client.get(
                "/api/auth/me", headers=self._headers(self.owner["token"])
            )
            self.assertEqual(response.status_code, 401)

    def _admin_headers(self):
        self._execute(
            "UPDATE users SET is_admin=1, admin_permissions=?, role_id='role_admin' WHERE id=?",
            (json.dumps(["*"]), self.other["user_id"]),
        )
        return self._headers(self.other["token"])

    def test_creation_metadata_activity_and_hash_only_storage(self):
        token = self._create(name="  Linux desktop  ")
        self.assertEqual(set(token), self.metadata_keys | {"token"})
        self.assertEqual(token["name"], "Linux desktop")
        self.assertIsNone(token["expires_at"])
        self.assertIsNone(token["last_used_at"])
        self.assertIsNone(token["revoked_at"])
        self.assertFalse(token["current"])
        self.assertTrue(token["token"].startswith("duoyi_pat_"))
        secret = token["token"].removeprefix("duoyi_pat_")
        self.assertGreaterEqual(len(base64.urlsafe_b64decode(secret + "=" * (-len(secret) % 4))), 32)
        self.assertTrue(token["token"].startswith(token["prefix"]))
        self.assertLess(len(token["prefix"]), len(token["token"]))
        row = self._execute("SELECT * FROM access_tokens WHERE id=?", (token["id"],))[0]
        expected_hash = hashlib.sha256(token["token"].encode()).hexdigest()
        self.assertTrue(row["token_hash"] == expected_hash)
        self.assertFalse(any(value == token["token"] for value in row))
        self.assertFalse(token["token"].encode() in Path(api.DB_PATH).read_bytes())
        db = api.get_db()
        try:
            self.assertFalse(token["token"] in "\n".join(db.iterdump()))
        finally:
            db.close()
        listed = self._list()
        self.assertEqual(len(listed), 1)
        self.assertEqual(set(listed[0]), self.metadata_keys)
        self.assertFalse(listed[0]["current"])
        self._assert_valid(token["token"])
        self.assertTrue(api.TOKENS[self.owner["user_id"]] == self.owner["token"])
        self._execute("UPDATE access_tokens SET last_used_at='2000-01-01T00:00:00Z'")
        now = api._utc_now() + timedelta(seconds=5)
        with patch.object(api, "_utc_now", return_value=now):
            listed = self._list(token["token"])
        self.assertTrue(listed[0]["current"])
        self.assertEqual(listed[0]["last_used_at"], api._format_utc(now))

    def test_restart_and_idempotent_initialization_preserve_tokens_and_settings(self):
        token = self._create()
        self._execute(
            "INSERT INTO settings(key, value) VALUES('access_token_migration_test', '\"keep me\"')"
        )
        self.client.__exit__(None, None, None)
        api.TOKENS.clear()
        api.TOKEN_LAST_ACTIVE.clear()
        api.init_db()
        api.init_db()
        self.client = TestClient(api.app).__enter__()
        self._assert_valid(token["token"])
        self.assertFalse(api.TOKENS)
        self.assertEqual(self._list(token["token"])[0]["id"], token["id"])
        self.assertEqual(
            self._execute("SELECT value FROM settings WHERE key='access_token_migration_test'")[0][0],
            '"keep me"',
        )
        self._assert_websocket_works(token["token"], self.websocket_paths[0])

    def test_other_accounts_cannot_list_or_revoke_tokens(self):
        owner_token = self._create()
        other_token = self._create(credential=self.other["token"])
        self.assertEqual([row["id"] for row in self._list()], [owner_token["id"]])
        other_list = self._list(self.other["token"])
        self.assertEqual([row["id"] for row in other_list], [other_token["id"]])
        for token_id in (owner_token["id"], "missing-token"):
            response = self.client.delete(
                f"/api/auth/tokens/{token_id}", headers=self._headers(self.other["token"])
            )
            self.assertEqual(response.status_code, 404)
        self._assert_valid(owner_token["token"])
        denied = self.client.get("/api/admin/users", headers=self._headers(owner_token["token"]))
        self.assertEqual(denied.status_code, 403)

    def test_revocation_is_idempotent_and_survives_restart(self):
        token = self._create()
        for _ in range(2):
            response = self.client.delete(
                f"/api/auth/tokens/{token['id']}", headers=self._headers(self.owner["token"])
            )
            self.assertEqual(response.status_code, 200)
        self.assertIsNotNone(self._list()[0]["revoked_at"])
        self._assert_revoked([token], check_session=False)
        api.TOKENS.clear()
        api.TOKEN_LAST_ACTIVE.clear()
        api.init_db()
        self._assert_revoked([token])

    def test_authentication_required_for_all_token_routes(self):
        for headers in ({}, {"Authorization": "Basic invalid"}, {"Authorization": "Bearer invalid"}):
            requests = (
                self.client.get("/api/auth/tokens", headers=headers),
                self.client.post("/api/auth/tokens", headers=headers, json={"name": "phone"}),
                self.client.delete("/api/auth/tokens/missing", headers=headers),
            )
            self.assertEqual([response.status_code for response in requests], [401, 401, 401])
        self.assertFalse(self._list())
        self._assert_websocket_rejected("invalid")

    def test_strict_name_and_expiry_validation_and_boundary_values(self):
        invalid = (
            {}, {"name": None}, {"name": 42}, {"name": ""}, {"name": " \t\n"},
            {"name": "n" * 81},
            *({"name": "phone", "expires_in_days": days} for days in (0, -1, 3651, 1.5, "3", True, False)),
        )
        for payload in invalid:
            with self.subTest(payload=payload):
                response = self.client.post(
                    "/api/auth/tokens", headers=self._headers(self.owner["token"]), json=payload
                )
                self.assertEqual(response.status_code, 422)
        self.assertFalse(self._list())
        now = api._utc_now().replace(microsecond=0)
        with patch.object(api, "_utc_now", return_value=now):
            for days in (1, 3650):
                token = self._create(name="n" * 80, days=days)
                self.assertEqual(token["expires_at"], api._format_utc(now + timedelta(days=days)))
        omitted = self.client.post(
            "/api/auth/tokens", headers=self._headers(self.owner["token"]), json={"name": "no expiry"}
        )
        self.assertEqual(omitted.status_code, 200)
        self.assertIsNone(omitted.json()["expires_at"])

    def test_active_token_quota_is_atomic_and_per_account(self):
        def create_one(index):
            return self.client.post(
                "/api/auth/tokens", headers=self._headers(self.owner["token"]),
                json={"name": f"device {index}"},
            ).status_code

        with patch.object(api, "ACCESS_TOKEN_LIMIT", 3):
            with ThreadPoolExecutor(max_workers=5) as executor:
                statuses = list(executor.map(create_one, range(8)))
            self.assertEqual(statuses.count(200), 3)
            self.assertEqual(statuses.count(400), 5)
            self._create(credential=self.other["token"])
            existing = self._list()
            self.client.delete(
                f"/api/auth/tokens/{existing[0]['id']}", headers=self._headers(self.owner["token"])
            )
            self._create(name="replacement for revoked")
            self._execute(
                "UPDATE access_tokens SET expires_at='2000-01-01T00:00:00Z' WHERE id=?",
                (existing[1]["id"],),
            )
            self._create(name="replacement for expired")

    def test_normal_password_and_email_logins_preserve_all_pats(self):
        tokens = [self._create("phone"), self._create("desktop")]
        password_login = self.client.post(
            "/api/auth/login", json={"username": "token-owner", "password": "pass123456"}
        )
        self.assertEqual(password_login.status_code, 200)
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
            code = api._create_email_code(
                db, email="token-owner@example.invalid", purpose="login", user_id=self.owner["user_id"]
            )["code"]
            db.commit()
        finally:
            db.close()
        email_login = self.client.post(
            "/api/auth/email-login", json={"email": "token-owner@example.invalid", "code": code}
        )
        self.assertEqual(email_login.status_code, 200)
        for token in tokens:
            self._assert_valid(token["token"])
        self._assert_valid(email_login.json()["token"])
        self.assertTrue(api.TOKENS[self.owner["user_id"]] == email_login.json()["token"])

    def test_pat_logout_only_revokes_current_device(self):
        phone = self._create("phone")
        desktop = self._create("desktop")
        response = self.client.post("/api/auth/logout", headers=self._headers(phone["token"]))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})
        self._assert_revoked([phone], check_session=False)
        self._assert_valid(desktop["token"])
        self._assert_valid(self.owner["token"])
        listed = {row["id"]: row for row in self._list(desktop["token"])}
        self.assertTrue(listed[desktop["id"]]["current"])
        self.assertFalse(listed[phone["id"]]["current"])

    def test_normal_session_logout_preserves_all_pats(self):
        tokens = [self._create("phone"), self._create("desktop")]
        response = self.client.post("/api/auth/logout", headers=self._headers(self.owner["token"]))
        self.assertEqual(response.status_code, 200)
        self.assertNotIn(self.owner["user_id"], api.TOKENS)
        for token in tokens:
            self._assert_valid(token["token"])
        # A PAT can provision another installation without becoming a memory session.
        self._create("third device", credential=tokens[0]["token"])
        self.assertNotIn(self.owner["user_id"], api.TOKENS)

    def test_pat_can_revoke_itself_without_affecting_other_credentials(self):
        phone = self._create("phone")
        desktop = self._create("desktop")
        response = self.client.delete(
            f"/api/auth/tokens/{phone['id']}", headers=self._headers(phone["token"])
        )
        self.assertEqual(response.status_code, 200)
        self._assert_revoked([phone], check_session=False)
        self._assert_valid(desktop["token"])
        self._assert_valid(self.owner["token"])

    def test_expiry_including_exact_deadline_applies_to_http_and_websocket(self):
        now = api._utc_now().replace(microsecond=0)
        with patch.object(api, "_utc_now", return_value=now):
            token = self._create(days=1)
        deadline = api._parse_server_time(token["expires_at"])
        with patch.object(api, "_utc_now", return_value=deadline - timedelta(seconds=1)):
            self._assert_valid(token["token"])
        for expired_at in (deadline, deadline + timedelta(seconds=1)):
            with patch.object(api, "_utc_now", return_value=expired_at):
                response = self.client.get("/api/auth/me", headers=self._headers(token["token"]))
                self.assertEqual(response.status_code, 401)
                for path in self.websocket_paths:
                    self._assert_websocket_rejected(token["token"], path)
        # Expired tokens remain visible and can be explicitly revoked.
        self.assertEqual(self._list()[0]["id"], token["id"])
        response = self.client.delete(
            f"/api/auth/tokens/{token['id']}", headers=self._headers(self.owner["token"])
        )
        self.assertEqual(response.status_code, 200)

    def test_malformed_expiry_and_missing_user_are_rejected(self):
        token = self._create()
        self._execute("UPDATE access_tokens SET expires_at='invalid' WHERE id=?", (token["id"],))
        self.assertEqual(
            self.client.get("/api/auth/me", headers=self._headers(token["token"])).status_code, 401
        )
        self._assert_websocket_rejected(token["token"])
        self._execute("UPDATE access_tokens SET expires_at=NULL WHERE id=?", (token["id"],))
        self._execute("DELETE FROM users WHERE id=?", (self.owner["user_id"],))
        self.assertFalse(self._execute("SELECT id FROM access_tokens WHERE id=?", (token["id"],)))
        self.assertEqual(
            self.client.get("/api/auth/me", headers=self._headers(token["token"])).status_code, 401
        )
        self._assert_websocket_rejected(token["token"])

    def _assert_websocket_works(self, token, path, *, query=False):
        if query:
            connection = self.client.websocket_connect(f"{path}?token={token}")
        else:
            connection = self.client.websocket_connect(path, headers=self._headers(token))
        with connection as websocket:
            self.assertEqual(websocket.receive_json()["event"], "ranking")
            websocket.send_json({"event": "ping"})
            self.assertEqual(websocket.receive_json()["event"], "ranking")

    def test_both_websockets_accept_header_and_query_pats_and_touch_activity(self):
        token = self._create()
        for path in self.websocket_paths:
            for query in (False, True):
                self._execute("UPDATE access_tokens SET last_used_at=NULL WHERE id=?", (token["id"],))
                self._assert_websocket_works(token["token"], path, query=query)
                row = self._execute("SELECT last_used_at FROM access_tokens WHERE id=?", (token["id"],))[0]
                self.assertIsNotNone(row["last_used_at"])

    def test_connected_websockets_close_after_revocation(self):
        for path in self.websocket_paths:
            token = self._create()
            with self.client.websocket_connect(path, headers=self._headers(token["token"])) as websocket:
                self.assertEqual(websocket.receive_json()["event"], "ranking")
                response = self.client.delete(
                    f"/api/auth/tokens/{token['id']}", headers=self._headers(self.owner["token"])
                )
                self.assertEqual(response.status_code, 200)
                last_used = self._execute(
                    "SELECT last_used_at FROM access_tokens WHERE id=?", (token["id"],)
                )[0][0]
                websocket.send_json({"event": "ping"})
                with self.assertRaises(WebSocketDisconnect) as closed:
                    websocket.receive_json()
                self.assertEqual(closed.exception.code, 1008)
            self.assertEqual(
                self._execute("SELECT last_used_at FROM access_tokens WHERE id=?", (token["id"],))[0][0],
                last_used,
            )

    def test_connected_websockets_recheck_expiry_and_disabled_users(self):
        for path in self.websocket_paths:
            for change in ("expiry", "disabled"):
                token = self._create()
                with self.client.websocket_connect(path, headers=self._headers(token["token"])) as websocket:
                    self.assertEqual(websocket.receive_json()["event"], "ranking")
                    if change == "expiry":
                        self._execute(
                            "UPDATE access_tokens SET expires_at='2000-01-01T00:00:00Z' WHERE id=?",
                            (token["id"],),
                        )
                    else:
                        self._execute("UPDATE users SET is_disabled=1 WHERE id=?", (self.owner["user_id"],))
                    websocket.send_json({"event": "ping"})
                    with self.assertRaises(WebSocketDisconnect) as closed:
                        websocket.receive_json()
                    self.assertEqual(closed.exception.code, 1008)
                self._execute("UPDATE users SET is_disabled=0 WHERE id=?", (self.owner["user_id"],))
                # A directly disabled account also loses its existing memory session.
                login = self.client.post(
                    "/api/auth/login", json={"username": "token-owner", "password": "pass123456"}
                )
                self.assertEqual(login.status_code, 200)
                self.owner = login.json()

    def test_disable_and_reenable_never_restore_revoked_tokens(self):
        tokens = [self._create("phone"), self._create("desktop")]
        admin_headers = self._admin_headers()
        for disabled in (True, False):
            response = self.client.patch(
                f"/api/admin/users/{self.owner['user_id']}",
                headers=admin_headers, json={"is_disabled": disabled},
            )
            self.assertEqual(response.status_code, 200)
        self._assert_revoked(tokens)

    def test_bulk_disable_revokes_tokens_and_normal_session(self):
        tokens = [self._create("phone"), self._create("desktop")]
        response = self.client.post(
            "/api/admin/users/bulk-status", headers=self._admin_headers(),
            json={"user_ids": [self.owner["user_id"]], "is_disabled": True},
        )
        self.assertEqual(response.status_code, 200)
        self._assert_revoked(tokens)

    def test_disabled_user_cannot_authenticate_even_without_admin_revocation(self):
        token = self._create()
        self._execute("UPDATE users SET is_disabled=1 WHERE id=?", (self.owner["user_id"],))
        response = self.client.get("/api/auth/me", headers=self._headers(token["token"]))
        self.assertEqual(response.status_code, 403)
        self._assert_websocket_rejected(token["token"])
        self._execute("UPDATE users SET is_disabled=0 WHERE id=?", (self.owner["user_id"],))
        self._assert_revoked([token])

    def test_password_change_revokes_all_pats_and_session_but_wrong_password_does_not(self):
        tokens = [self._create("phone"), self._create("desktop")]
        for password, expected_status in (("wrong-password", 403), ("pass123456", 200)):
            response = self.client.post(
                "/api/auth/change-password", headers=self._headers(tokens[0]["token"]),
                json={"current_password": password, "new_password": "newpass123456"},
            )
            self.assertEqual(response.status_code, expected_status)
            if expected_status == 403:
                for token in tokens:
                    self._assert_valid(token["token"])
        self._assert_revoked(tokens)
        response = self.client.post(
            "/api/auth/login", json={"username": "token-owner", "password": "newpass123456"}
        )
        self.assertEqual(response.status_code, 200)

    def test_admin_password_reset_revokes_all_pats_and_session(self):
        tokens = [self._create("phone"), self._create("desktop")]
        response = self.client.patch(
            f"/api/admin/users/{self.owner['user_id']}", headers=self._admin_headers(),
            json={"new_password": "newpass123456"},
        )
        self.assertEqual(response.status_code, 200)
        self._assert_revoked(tokens)

    def test_password_reset_confirmation_both_formats_revoke_all_credentials(self):
        for code_format in (False, True):
            tokens = [self._create("phone"), self._create("desktop")]
            reset_codes = []
            with patch.object(
                api, "_send_password_reset_email", side_effect=lambda db, user, code: reset_codes.append(code)
            ):
                request = self.client.post(
                    "/api/auth/password-reset", json={"email": "token-owner@example.invalid"}
                )
            self.assertEqual(request.status_code, 200)
            self.assertEqual(len(reset_codes), 1)
            payload = {"new_password": "newpass123456"}
            if code_format:
                payload.update(email="token-owner@example.invalid", code=reset_codes[0])
            else:
                payload["token"] = reset_codes[0]
            response = self.client.post("/api/auth/password-reset/confirm", json=payload)
            self.assertEqual(response.status_code, 200)
            self._assert_revoked(tokens)
            login = self.client.post(
                "/api/auth/login", json={"username": "token-owner", "password": "newpass123456"}
            )
            self.assertEqual(login.status_code, 200)
            self.owner = login.json()

    def test_account_deletion_removes_tokens_and_invalidates_all_protocols(self):
        token = self._create()
        response = self.client.delete(
            f"/api/admin/users/{self.owner['user_id']}", headers=self._admin_headers()
        )
        self.assertEqual(response.status_code, 200)
        self.assertFalse(self._execute("SELECT id FROM access_tokens WHERE user_id=?", (self.owner["user_id"],)))
        self._assert_revoked([token])

    def _create_after_dependency(self, credential, change):
        verify = api._verify_token_value
        changes = []

        def verify_then_change(raw_token):
            user_id = verify(raw_token)
            self.assertTrue(raw_token == credential)
            changes.append(True)
            change()
            return user_id

        before = self._execute("SELECT COUNT(*) FROM access_tokens")[0][0]
        with patch.object(api, "_verify_token_value", side_effect=verify_then_change):
            response = self.client.post(
                "/api/auth/tokens", headers=self._headers(credential),
                json={"name": "must not be created"},
            )
        self.assertEqual(len(changes), 1)
        self.assertEqual(self._execute("SELECT COUNT(*) FROM access_tokens")[0][0], before)
        self.assertNotIn("token", response.json())
        return response

    def test_creation_rechecks_pat_revoked_after_dependency_commit(self):
        token = self._create()
        response = self._create_after_dependency(
            token["token"],
            lambda: api.revoke_access_token(token["id"], user_id=self.owner["user_id"]),
        )
        self.assertEqual(response.status_code, 401)

    def test_creation_rechecks_session_after_logout_or_rotation(self):
        for change in ("logout", "rotation"):
            with self.subTest(change=change):
                login = self.client.post(
                    "/api/auth/login", json={"username": "token-owner", "password": "pass123456"}
                )
                self.assertEqual(login.status_code, 200)
                credential = login.json()["token"]

                def invalidate():
                    if change == "logout":
                        api._drop_session(self.owner["user_id"])
                    else:
                        api.login(api.LoginRequest(username="token-owner", password="pass123456"))

                response = self._create_after_dependency(credential, invalidate)
                self.assertEqual(response.status_code, 401)

    def test_creation_rechecks_both_credentials_after_password_reset(self):
        for kind in ("session", "pat"):
            with self.subTest(kind=kind):
                credential = self.owner["token"] if kind == "session" else self._create()["token"]
                reset_code = "deterministic-reset-" + kind
                self._execute(
                    "INSERT INTO password_reset_tokens(token_hash, user_id, expires_at) VALUES(?,?,?)",
                    (api._hash_reset_token(reset_code), self.owner["user_id"],
                     api._format_utc(api._utc_now() + timedelta(minutes=10))),
                )

                def reset_password():
                    result = api.confirm_password_reset(
                        api.PasswordResetConfirm(token=reset_code, new_password="newpass123456")
                    )
                    self.assertEqual(result, {"ok": True})

                response = self._create_after_dependency(credential, reset_password)
                self.assertEqual(response.status_code, 401)
                login = self.client.post(
                    "/api/auth/login", json={"username": "token-owner", "password": "newpass123456"}
                )
                self.assertEqual(login.status_code, 200)
                self.owner = login.json()

    def test_creation_rechecks_pat_expiry_ownership_and_user_state(self):
        for change in ("expired", "different owner", "disabled"):
            with self.subTest(change=change):
                token = self._create()

                def invalidate():
                    if change == "expired":
                        self._execute(
                            "UPDATE access_tokens SET expires_at='2000-01-01T00:00:00Z' WHERE id=?",
                            (token["id"],),
                        )
                    elif change == "different owner":
                        self._execute(
                            "UPDATE access_tokens SET user_id=? WHERE id=?",
                            (self.other["user_id"], token["id"]),
                        )
                    else:
                        self._execute("UPDATE users SET is_disabled=1 WHERE id=?", (self.owner["user_id"],))

                response = self._create_after_dependency(token["token"], invalidate)
                self.assertEqual(response.status_code, 403 if change == "disabled" else 401)

    def _prepare_pat_only_presence(self):
        active = self._create("active device")
        self._create("unused spare device")
        self._admin_headers()
        observer = self._create("observer", credential=self.other["token"])
        self._execute(
            "INSERT INTO focus_friends(user_id, friend_user_id, status) VALUES(?,?,'accepted')",
            (self.other["user_id"], self.owner["user_id"]),
        )
        api.TOKENS.clear()
        api.TOKEN_LAST_ACTIVE.clear()
        self.assertNotIn(self.owner["user_id"], api._online_user_ids())
        response = self.client.post(
            "/api/focus-rooms/token-test-room/heartbeat", headers=self._headers(active["token"]),
            json={"display_name": "PAT device", "weekly_seconds": 60, "session_count": 1, "active": True},
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["entries"][0]["online"])
        self.assertFalse(api.TOKENS)
        return active, self._headers(observer["token"])

    def _assert_online_views(self, headers, expected, *, disabled=False):
        user_id = self.owner["user_id"]
        self.assertEqual(user_id in api._online_user_ids(), expected)
        self.assertEqual(user_id in api._online_user_ids([user_id]), expected)
        for route, key in (
            ("/api/focus-rooms/token-test-room/ranking", "entries"),
            ("/api/focus-leaderboard/global", "entries"),
            ("/api/focus-leaderboard/friends", "entries"),
            ("/api/focus-friends", "items"),
            ("/api/admin/users?limit=100&offset=0", "items"),
        ):
            with self.subTest(route=route):
                response = self.client.get(route, headers=headers)
                self.assertEqual(response.status_code, 200)
                entries = [item for item in response.json()[key] if item["user_id"] == user_id]
                if disabled and route == "/api/focus-leaderboard/global":
                    self.assertEqual(entries, [])
                else:
                    self.assertEqual(len(entries), 1)
                    self.assertEqual(entries[0]["online"], expected)
        self._execute(
            "UPDATE focus_friends SET status='pending' WHERE user_id=? AND friend_user_id=?",
            (self.other["user_id"], user_id),
        )
        response = self.client.get("/api/focus-friends/requests", headers=headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["items"][0]["online"], expected)
        self._execute(
            "UPDATE focus_friends SET status='accepted' WHERE user_id=? AND friend_user_id=?",
            (self.other["user_id"], user_id),
        )

    def test_pat_only_heartbeat_is_online_and_revocation_clears_all_views(self):
        token, headers = self._prepare_pat_only_presence()
        self._assert_online_views(headers, True)
        response = self.client.delete(
            f"/api/auth/tokens/{token['id']}", headers=self._headers(token["token"])
        )
        self.assertEqual(response.status_code, 200)
        self._assert_online_views(headers, False)

    def test_expired_or_inactive_pats_and_disabled_users_cannot_stay_online(self):
        token, headers = self._prepare_pat_only_presence()
        self._assert_online_views(headers, True)
        for change in ("expired", "stale", "disabled"):
            with self.subTest(change=change):
                now = api._utc_now()
                self._execute(
                    "UPDATE access_tokens SET expires_at=?, last_used_at=? WHERE id=?",
                    (api._format_utc(now) if change == "expired" else None,
                     api._format_utc(now - timedelta(seconds=api.SESSION_ONLINE_SECONDS + 1))
                     if change == "stale" else api._format_utc(now), token["id"]),
                )
                self._execute(
                    "UPDATE users SET is_disabled=? WHERE id=?",
                    (int(change == "disabled"), self.owner["user_id"]),
                )
                self._assert_online_views(headers, False, disabled=change == "disabled")

    def test_online_activity_preserves_monkeypatched_session_aliases(self):
        user_id = self.owner["user_id"]
        now = api._utc_now()
        with patch.object(api, "TOKENS", {user_id: "test-session", "deleted-user": "missing"}), patch.object(
            api, "TOKEN_LAST_ACTIVE", {user_id: now, "deleted-user": now}
        ):
            self.assertEqual(api._online_user_ids(), {user_id})
            api.TOKEN_LAST_ACTIVE[user_id] = now - timedelta(seconds=api.SESSION_ONLINE_SECONDS + 1)
            self.assertEqual(api._online_user_ids(), set())
        # PAT activity must not refresh an idle ordinary session's online window.
        token = self._create()
        api.TOKEN_LAST_ACTIVE[user_id] = now - timedelta(seconds=api.SESSION_ONLINE_SECONDS + 1)
        self._assert_valid(token["token"])
        self.assertIn(user_id, api._online_user_ids())
        api.revoke_access_token(token["id"], user_id=user_id)
        self.assertNotIn(user_id, api._online_user_ids())
        self._assert_valid(self.owner["token"])
        self.assertIn(user_id, api._online_user_ids())

    def test_online_lists_batch_credential_queries(self):
        for index in range(8):
            friend = self._register(f"batch-friend-{index}")
            self._execute(
                "INSERT INTO focus_friends(user_id, friend_user_id, status) VALUES(?,?,?)",
                (self.other["user_id"], friend["user_id"], "accepted" if index % 2 else "pending"),
            )
            api.focus_room_heartbeat(
                "token-test-room", api.FocusRoomHeartbeatRequest(active=True), user_id=friend["user_id"]
            )
        get_db = api.get_db
        queries = []

        def traced_db():
            db = get_db()
            db.set_trace_callback(queries.append)
            return db

        for read in (
            lambda: api.list_focus_friends(user_id=self.other["user_id"]),
            lambda: api.list_focus_friend_requests(user_id=self.other["user_id"]),
            lambda: api.focus_friend_leaderboard(user_id=self.other["user_id"]),
            lambda: api.focus_global_leaderboard(user_id=self.other["user_id"]),
            lambda: api.focus_room_ranking("token-test-room", user_id=self.other["user_id"]),
        ):
            queries.clear()
            with patch.object(api, "get_db", side_effect=traced_db):
                read()
            credential_queries = [sql for sql in queries if "JOIN access_tokens" in sql]
            self.assertEqual(len(credential_queries), 1)

    async def _ranking_stream(self, scope, credential):
        authorization = self._headers(credential)["Authorization"]
        user_id = api._verify_token(authorization)
        if scope == "room":
            response = await api.focus_room_events(
                "token-test-room", interval_seconds=0, user_id=user_id, authorization=authorization
            )
        else:
            response = await api.focus_global_leaderboard_events(
                interval_seconds=0, user_id=user_id, authorization=authorization
            )
        self.assertEqual(response.media_type, "text/event-stream")
        return response.body_iterator

    async def _assert_sse_stops(self, scope, credential, change, *, before_first=False):
        stream = await self._ranking_stream(scope, credential)
        try:
            if not before_first:
                self.assertIn("event: ranking", await anext(stream))
            change()
            with self.assertRaises(StopAsyncIteration):
                await asyncio.wait_for(anext(stream), timeout=1)
        finally:
            await stream.aclose()

    def test_ranking_sse_ends_after_pat_revocation(self):
        for scope in ("room", "global"):
            token = self._create()
            asyncio.run(self._assert_sse_stops(
                scope, token["token"],
                lambda: api.revoke_access_token(token["id"], user_id=self.owner["user_id"]),
            ))

    def test_ranking_sse_ends_after_pat_expiry(self):
        for scope in ("room", "global"):
            token = self._create()
            asyncio.run(self._assert_sse_stops(
                scope, token["token"],
                lambda: self._execute(
                    "UPDATE access_tokens SET expires_at=? WHERE id=?",
                    (api._utc_now_text(), token["id"]),
                ),
            ))

    def test_ranking_sse_ends_when_user_is_disabled_without_prior_revocation(self):
        for scope in ("room", "global"):
            token = self._create()
            asyncio.run(self._assert_sse_stops(
                scope, token["token"],
                lambda: self._execute("UPDATE users SET is_disabled=1 WHERE id=?", (self.owner["user_id"],)),
            ))
            self._execute("UPDATE users SET is_disabled=0 WHERE id=?", (self.owner["user_id"],))
            login = self.client.post(
                "/api/auth/login", json={"username": "token-owner", "password": "pass123456"}
            )
            self.assertEqual(login.status_code, 200)
            self.owner = login.json()

    def test_ranking_sse_keeps_original_session_after_logout_and_relogin(self):
        for scope in ("room", "global"):
            credential = self.owner["token"]

            def relogin():
                api.logout(user_id=self.owner["user_id"])
                self.owner = api.login(api.LoginRequest(username="token-owner", password="pass123456"))

            asyncio.run(self._assert_sse_stops(scope, credential, relogin))
            self._assert_valid(self.owner["token"])

    def test_ranking_sse_rechecks_credential_before_first_event(self):
        for scope in ("room", "global"):
            token = self._create()
            asyncio.run(self._assert_sse_stops(
                scope, token["token"],
                lambda: api.revoke_access_token(token["id"], user_id=self.owner["user_id"]),
                before_first=True,
            ))


if __name__ == "__main__":
    unittest.main()
