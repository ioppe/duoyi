"""Targeted tests for the server-authoritative focus runtime.

Covers the backend scope listed in docs/focus-runtime-sync.md: state machine,
countdown/count-up settlement, pause/resume, rotation, two-device races,
command retries, unique settlement, cloud-sync concurrency, account isolation,
revocation, websocket fan-out and old-client compatibility.
"""

import json
import os
import tempfile
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch

from starlette.websockets import WebSocketDisconnect
from fastapi.testclient import TestClient

# Test-only bootstrap credentials; production has no default password.
with patch.dict(os.environ, {"ADMIN_BOOTSTRAP_PASSWORD": "admin123"}):
    import main as api


T0 = 1_700_000_000_000  # fixed wall-clock anchor for deterministic tests

SHORT_CONFIG = {
    "focusDuration": 60,
    "shortBreakDuration": 60,
    "longBreakDuration": 120,
    "sessionsPerLongBreak": 2,
}


class FocusRuntimeTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._old_db_path = api.DB_PATH
        api.DB_PATH = os.path.join(self._tmp.name, "duoyi-test.db")
        api.TOKENS.clear()
        api.TOKEN_LAST_ACTIVE.clear()
        api.init_db()

    def tearDown(self):
        api.DB_PATH = self._old_db_path
        api.TOKENS.clear()
        api.TOKEN_LAST_ACTIVE.clear()
        api.FOCUS_RUNTIME_CONNECTIONS.clear()
        self._tmp.cleanup()

    # ------------------------------------------------------------------
    # helpers
    # ------------------------------------------------------------------

    def _register(self, username: str) -> tuple[str, str]:
        db = api.get_db()
        try:
            api._setting_set(db, "registration_email_required", False)
            api._setting_set(db, "default_registration_coins", 0)
            db.execute(
                "UPDATE admin_groups SET default_time_coins=0 WHERE id='group_default'"
            )
            db.commit()
        finally:
            db.close()
        result = api.register(
            api.RegisterRequest(username=username, password="pass123456")
        )
        return result["user_id"], result["token"]

    def _make_admin(self, user_id: str) -> None:
        db = api.get_db()
        try:
            db.execute(
                "UPDATE users SET is_admin=1, admin_permissions='[\"*\"]' WHERE id=?",
                (user_id,),
            )
            db.commit()
        finally:
            db.close()

    def _apply(self, user_id: str, command: dict, at_ms: int = T0) -> dict:
        db = api.get_db()
        try:
            db.execute("BEGIN IMMEDIATE")
            try:
                envelope = api.focus_runtime.handle_command(
                    db, user_id, command, at_ms=at_ms
                )
                db.commit()
            except BaseException:
                db.rollback()
                raise
            return envelope
        finally:
            db.close()

    def _advance(self, user_id: str, at_ms: int) -> bool:
        db = api.get_db()
        try:
            db.execute("BEGIN IMMEDIATE")
            try:
                changed = api.focus_runtime.advance_due(db, user_id, at_ms=at_ms)
                db.commit()
            except BaseException:
                db.rollback()
                raise
            return changed
        finally:
            db.close()

    def _snapshot(self, user_id: str, at_ms: int = T0) -> dict:
        db = api.get_db()
        try:
            snapshot = api.focus_runtime.read_state(db, user_id, at_ms=at_ms)
            db.commit()
            return snapshot
        finally:
            db.close()

    def _sync_row(self, user_id: str):
        db = api.get_db()
        try:
            return db.execute(
                "SELECT pomodoro_sessions, time_entries, focus_penalties, sync_version "
                "FROM sync_data WHERE user_id=?",
                (user_id,),
            ).fetchone()
        finally:
            db.close()

    def _history(self, user_id: str) -> list:
        row = self._sync_row(user_id)
        return json.loads(row["pomodoro_sessions"]) if row else []

    def _time_entries(self, user_id: str) -> list:
        row = self._sync_row(user_id)
        return json.loads(row["time_entries"]) if row else []

    def _penalties(self, user_id: str) -> list:
        row = self._sync_row(user_id)
        return json.loads(row["focus_penalties"]) if row else []

    def _command(
        self,
        action: str,
        session_id: str,
        revision: int,
        payload: dict = None,
        command_id: str = None,
        device_id: str = "device-a",
    ) -> dict:
        return {
            "commandId": command_id or str(uuid.uuid4()),
            "deviceId": device_id,
            "sessionId": session_id,
            "expectedRevision": revision,
            "action": action,
            "payload": payload or {},
        }

    def _start(self, user_id: str, at_ms: int = T0, config: dict = None, mode: str = "countdown"):
        snapshot = self._snapshot(user_id, at_ms)
        runtime = snapshot["runtime"]
        return self._apply(
            user_id,
            self._command(
                "start",
                runtime["sessionId"],
                runtime["revision"],
                {
                    "mode": mode,
                    "config": config or dict(SHORT_CONFIG),
                    "taskName": "写代码",
                    "todoId": "todo-1",
                    "subtaskId": "sub-1",
                    "todoTitle": "后端",
                    "tag": "work",
                    "focusRoomId": "room-1",
                },
            ),
            at_ms,
        )

    # ------------------------------------------------------------------
    # baseline snapshot
    # ------------------------------------------------------------------

    def test_initial_snapshot_is_idle_with_session_identity(self):
        user_id, _ = self._register("idle-user")
        snapshot = self._snapshot(user_id)
        runtime = snapshot["runtime"]

        self.assertTrue(runtime["sessionId"])
        self.assertEqual(runtime["revision"], 0)
        self.assertEqual(runtime["status"], "idle")
        self.assertEqual(runtime["mode"], "countdown")
        self.assertEqual(runtime["phase"], "focus")
        self.assertEqual(runtime["durationMs"], 1_500_000)
        self.assertEqual(runtime["elapsedMs"], 0)
        self.assertIsNone(runtime["anchorAtMs"])
        self.assertIsNone(runtime["startedAtMs"])
        self.assertEqual(runtime["completedSessions"], 0)
        self.assertEqual(runtime["sourceDeviceId"], "")
        self.assertIsNone(snapshot["lastSession"])
        self.assertIsNone(snapshot["lastPenalty"])
        self.assertEqual(snapshot["syncVersion"], 0)
        self.assertEqual(snapshot["serverNowMs"], T0)

        # A stable identity is reused instead of generating a new one per read.
        again = self._snapshot(user_id, T0 + 5000)
        self.assertEqual(again["runtime"]["sessionId"], runtime["sessionId"])

    # ------------------------------------------------------------------
    # countdown / count-up
    # ------------------------------------------------------------------

    def test_start_pause_resume_freezes_elapsed(self):
        user_id, _ = self._register("pause-user")
        idle = self._snapshot(user_id)["runtime"]

        started = self._apply(
            user_id,
            self._command(
                "start",
                idle["sessionId"],
                idle["revision"],
                {"mode": "countdown", "config": dict(SHORT_CONFIG)},
                device_id="phone",
            ),
        )["runtime"]
        self.assertEqual(started["status"], "running")
        self.assertEqual(started["revision"], 1)
        self.assertEqual(started["durationMs"], 60_000)
        self.assertEqual(started["anchorAtMs"], T0)
        self.assertEqual(started["sourceDeviceId"], "phone")
        self.assertNotEqual(started["sessionId"], idle["sessionId"])

        paused = self._apply(
            user_id,
            self._command("pause", started["sessionId"], started["revision"], {}, device_id="laptop"),
            T0 + 30_000,
        )["runtime"]
        self.assertEqual(paused["status"], "paused")
        self.assertEqual(paused["elapsedMs"], 30_000)
        self.assertIsNone(paused["anchorAtMs"])
        # Pause keeps the identity and the originating device.
        self.assertEqual(paused["sessionId"], started["sessionId"])
        self.assertEqual(paused["sourceDeviceId"], "phone")

        resumed = self._apply(
            user_id,
            self._command("resume", paused["sessionId"], paused["revision"]),
            T0 + 90_000,
        )["runtime"]
        self.assertEqual(resumed["status"], "running")
        self.assertEqual(resumed["anchorAtMs"], T0 + 90_000)
        self.assertEqual(resumed["elapsedMs"], 30_000)

        # The paused gap is not counted: 30s elapsed before, 20s after resume.
        finished = self._apply(
            user_id,
            self._command("finish", resumed["sessionId"], resumed["revision"]),
            T0 + 110_000,
        )["runtime"]
        self.assertEqual(finished["status"], "idle")
        self.assertEqual(finished["phase"], "shortBreak")
        self.assertEqual(finished["completedSessions"], 1)

        history = self._history(user_id)
        self.assertEqual(len(history), 1)
        # Countdown settlement records the configured target, not the elapsed time.
        self.assertEqual(history[0]["durationSeconds"], 60)

    def test_countup_finish_uses_accumulated_elapsed_only(self):
        user_id, _ = self._register("countup-user")
        started = self._start(user_id, T0, mode="countup")["runtime"]
        self.assertEqual(started["mode"], "countup")
        self.assertEqual(started["durationMs"], 0)

        paused = self._apply(
            user_id,
            self._command("pause", started["sessionId"], started["revision"]),
            T0 + 40_000,
        )["runtime"]
        resumed = self._apply(
            user_id,
            self._command("resume", paused["sessionId"], paused["revision"]),
            T0 + 100_000,
        )["runtime"]
        self._apply(
            user_id,
            self._command("finish", resumed["sessionId"], resumed["revision"]),
            T0 + 160_000,
        )

        history = self._history(user_id)
        self.assertEqual(len(history), 1)
        # 40s before the pause + 60s after the resume; the 60s gap is excluded.
        self.assertEqual(history[0]["durationSeconds"], 100)
        self.assertEqual(history[0]["type"], 0)
        entries = self._time_entries(user_id)
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["source"], 1)
        self.assertEqual(entries[0]["category"], 0)
        self.assertEqual(entries[0]["dedupeKey"], f"pomodoro:{history[0]['id']}")
        self.assertEqual(entries[0]["sourceId"], history[0]["id"])

    # ------------------------------------------------------------------
    # stop / reset / skip
    # ------------------------------------------------------------------

    def test_stale_command_keeps_natural_expiry_committed(self):
        user_id, token = self._register("stale-expiry-user")
        runtime = self._start(user_id)["runtime"]
        with patch.object(api.focus_runtime, "now_ms", return_value=T0 + 61_000):
            with self.assertRaises(api.focus_runtime.FocusRuntimeConflict):
                api._focus_runtime_apply(user_id, self._command(
                    "pause", runtime["sessionId"], runtime["revision"]
                ), token)
        self.assertEqual(len(self._history(user_id)), 1)
        self.assertEqual(self._snapshot(user_id)["runtime"]["phase"], "shortBreak")

    def test_command_rechecks_exact_token_after_dependency_validation(self):
        user_id, token = self._register("command-revoke-user")
        runtime = self._snapshot(user_id)["runtime"]

        def verify_then_revoke():
            verified = api._verify_token_value(token)
            api.logout(user_id=verified, authorization=f"Bearer {token}")
            return verified

        api.app.dependency_overrides[api._verify_token] = verify_then_revoke
        try:
            with TestClient(api.app) as client:
                response = client.post("/api/focus/runtime/commands", json=self._command(
                    "start", runtime["sessionId"], runtime["revision"]
                ), headers={"Authorization": f"Bearer {token}"})
        finally:
            api.app.dependency_overrides.pop(api._verify_token, None)
        self.assertEqual(response.status_code, 401)
        self.assertEqual(self._snapshot(user_id)["runtime"]["status"], "idle")

    def test_subsecond_countup_finishes_with_one_second(self):
        user_id, _ = self._register("subsecond-user")
        runtime = self._start(user_id, mode="countup")["runtime"]
        self._apply(user_id, self._command(
            "finish", runtime["sessionId"], runtime["revision"]
        ), T0 + 100)
        self.assertEqual(self._history(user_id)[0]["durationSeconds"], 1)

    def test_retry_does_not_return_deleted_history_or_old_revision(self):
        user_id, _ = self._register("deleted-retry-user")
        runtime = self._start(user_id)["runtime"]
        finish = self._command("finish", runtime["sessionId"], runtime["revision"])
        finished = self._apply(user_id, finish, T0 + 10_000)
        self.assertIsNotNone(finished["lastSession"])
        idle = finished["runtime"]
        reset = self._apply(user_id, self._command(
            "reset", idle["sessionId"], idle["revision"]
        ), T0 + 11_000)
        db = api.get_db()
        try:
            db.execute("UPDATE sync_data SET pomodoro_sessions='[]' WHERE user_id=?", (user_id,))
            db.commit()
        finally:
            db.close()
        replay = self._apply(user_id, finish, T0 + 12_000)
        self.assertIsNone(replay["lastSession"])
        self.assertEqual(replay["runtime"]["revision"], reset["runtime"]["revision"])

    def test_reset_penalty_uses_elapsed_before_reset(self):
        user_id, _ = self._register("reset-penalty-user")
        runtime = self._start(user_id, config={**SHORT_CONFIG, "strictFocusMode": True})["runtime"]
        self._apply(user_id, self._command(
            "reset", runtime["sessionId"], runtime["revision"]
        ), T0 + 20_000)
        self.assertEqual(self._penalties(user_id)[0]["affectedSeconds"], 20)

    def test_reset_and_stop_return_to_focus_idle_without_history(self):
        user_id, _ = self._register("reset-user")
        started = self._start(user_id)["runtime"]

        reset = self._apply(
            user_id,
            self._command("reset", started["sessionId"], started["revision"]),
            T0 + 10_000,
        )["runtime"]
        self.assertEqual(reset["status"], "idle")
        self.assertEqual(reset["phase"], "focus")
        self.assertEqual(reset["elapsedMs"], 0)
        self.assertEqual(reset["durationMs"], 60_000)
        self.assertEqual(reset["completedSessions"], 0)
        self.assertEqual(reset["revision"], 2)
        self.assertNotEqual(reset["sessionId"], started["sessionId"])

        started_again = self._apply(
            user_id,
            self._command(
                "start", reset["sessionId"], reset["revision"],
                {"mode": "countdown", "config": dict(SHORT_CONFIG)},
            ),
            T0 + 20_000,
        )["runtime"]
        stopped = self._apply(
            user_id,
            self._command("stop", started_again["sessionId"], started_again["revision"]),
            T0 + 30_000,
        )["runtime"]
        self.assertEqual(stopped["status"], "idle")
        self.assertEqual(stopped["phase"], "focus")
        self.assertNotEqual(stopped["sessionId"], started_again["sessionId"])
        self.assertEqual(self._history(user_id), [])
        self.assertEqual(self._time_entries(user_id), [])

    def test_skip_rotates_phase_without_recording(self):
        user_id, _ = self._register("skip-user")
        started = self._start(user_id)["runtime"]

        skipped = self._apply(
            user_id,
            self._command("skip", started["sessionId"], started["revision"]),
            T0 + 10_000,
        )["runtime"]
        self.assertEqual(skipped["status"], "idle")
        self.assertEqual(skipped["phase"], "shortBreak")
        self.assertEqual(skipped["durationMs"], 60_000)
        self.assertEqual(skipped["completedSessions"], 0)
        self.assertNotEqual(skipped["sessionId"], started["sessionId"])
        self.assertEqual(self._history(user_id), [])

        # Break -> focus, still without any completion record.
        back = self._apply(
            user_id,
            self._command("skip", skipped["sessionId"], skipped["revision"]),
            T0 + 20_000,
        )["runtime"]
        self.assertEqual(back["phase"], "focus")
        self.assertEqual(self._history(user_id), [])

    # ------------------------------------------------------------------
    # natural expiry / rotation
    # ------------------------------------------------------------------

    def test_natural_expiry_settles_once_and_enters_break(self):
        user_id, _ = self._register("expiry-user")
        started = self._start(user_id)["runtime"]
        session_id = started["sessionId"]

        self.assertTrue(self._advance(user_id, T0 + 59_000) is False)
        self.assertTrue(self._advance(user_id, T0 + 60_000) is True)

        snapshot = self._snapshot(user_id, T0 + 61_000)
        runtime = snapshot["runtime"]
        self.assertEqual(runtime["status"], "idle")
        self.assertEqual(runtime["phase"], "shortBreak")
        self.assertEqual(runtime["completedSessions"], 1)
        self.assertEqual(runtime["revision"], 2)
        self.assertNotEqual(runtime["sessionId"], session_id)
        self.assertEqual(runtime["anchorAtMs"], None)

        history = self._history(user_id)
        self.assertEqual(len(history), 1)
        record = history[0]
        self.assertEqual(record["id"], session_id)
        self.assertEqual(record["type"], 0)
        self.assertEqual(record["durationSeconds"], 60)
        self.assertEqual(record["startTime"], api.focus_runtime.iso_from_ms(T0))
        self.assertEqual(record["endTime"], api.focus_runtime.iso_from_ms(T0 + 60_000))
        self.assertEqual(snapshot["lastSession"]["id"], session_id)

        entries = self._time_entries(user_id)
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["dedupeKey"], f"pomodoro:{session_id}")
        self.assertEqual(entries[0]["title"], "后端 / 写代码")
        self.assertEqual(snapshot["syncVersion"], 1)

        # A second pass must not duplicate history or the time footprint.
        self.assertFalse(self._advance(user_id, T0 + 62_000))
        self.assertEqual(len(self._history(user_id)), 1)
        self.assertEqual(len(self._time_entries(user_id)), 1)

    def test_auto_start_break_anchors_to_theoretical_deadline(self):
        user_id, _ = self._register("auto-user")
        config = dict(SHORT_CONFIG)
        config["autoStartBreaks"] = True

        started = self._start(user_id, T0, config=config)["runtime"]
        self._advance(user_id, T0 + 60_000 + 5_000)

        runtime = self._snapshot(user_id, T0 + 65_000)["runtime"]
        self.assertEqual(runtime["status"], "running")
        self.assertEqual(runtime["phase"], "shortBreak")
        self.assertEqual(runtime["revision"], 2)
        # Anchored on the theoretical deadline, not on the scan time.
        self.assertEqual(runtime["anchorAtMs"], T0 + 60_000)
        self.assertEqual(runtime["startedAtMs"], T0 + 60_000)
        self.assertEqual(runtime["durationMs"], 60_000)

        # The break also expires from its anchor and returns to focus idle.
        self._advance(user_id, T0 + 120_000)
        after_break = self._snapshot(user_id, T0 + 121_000)["runtime"]
        self.assertEqual(after_break["phase"], "focus")
        self.assertEqual(after_break["status"], "idle")
        self.assertEqual(after_break["completedSessions"], 1)
        history = self._history(user_id)
        self.assertEqual([record["type"] for record in history], [0, 1])

    # ------------------------------------------------------------------
    # concurrency, retries, conflicts
    # ------------------------------------------------------------------

    def test_two_devices_same_revision_only_first_wins(self):
        user_id, _ = self._register("race-user")
        started = self._start(user_id)["runtime"]

        accepted = self._apply(
            user_id,
            self._command("pause", started["sessionId"], started["revision"], {}, device_id="phone"),
            T0 + 5_000,
        )["runtime"]
        self.assertEqual(accepted["status"], "paused")

        with self.assertRaises(api.focus_runtime.FocusRuntimeConflict):
            self._apply(
                user_id,
                self._command("pause", started["sessionId"], started["revision"], {}, device_id="laptop"),
                T0 + 6_000,
            )
        # The rejected command left no state behind.
        self.assertEqual(self._snapshot(user_id, T0 + 7_000)["runtime"]["revision"], accepted["revision"])

    def test_duplicate_command_is_idempotent_and_payload_change_conflicts(self):
        user_id, _ = self._register("retry-user")
        idle = self._snapshot(user_id)["runtime"]
        command_id = "cmd-1"
        start = self._command(
            "start",
            idle["sessionId"],
            idle["revision"],
            {"mode": "countdown", "config": dict(SHORT_CONFIG)},
            command_id=command_id,
        )
        first = self._apply(user_id, start)
        replay = self._apply(user_id, start, T0 + 3_000)

        self.assertEqual(replay["runtime"]["revision"], first["runtime"]["revision"])
        self.assertEqual(replay["runtime"]["sessionId"], first["runtime"]["sessionId"])
        self.assertEqual(replay["serverNowMs"], T0 + 3_000)
        self.assertEqual(len(self._history(user_id)), 0)

        conflicting = dict(start)
        conflicting["action"] = "pause"
        with self.assertRaises(api.focus_runtime.FocusRuntimeConflict):
            self._apply(user_id, conflicting, T0 + 4_000)

        # A replay of an accepted command still works after later transitions.
        pause_id = "cmd-2"
        pause = self._command(
            "pause", first["runtime"]["sessionId"], first["runtime"]["revision"],
            {}, command_id=pause_id,
        )
        self._apply(user_id, pause, T0 + 5_000)
        self._apply(user_id, pause, T0 + 9_000)
        self.assertEqual(self._snapshot(user_id, T0 + 9_000)["runtime"]["status"], "paused")

    def test_strict_mode_records_one_penalty_per_command(self):
        user_id, _ = self._register("strict-user")
        config = dict(SHORT_CONFIG)
        config["strictFocusMode"] = True
        started = self._start(user_id, T0, config=config)["runtime"]

        pause_cmd = self._command("pause", started["sessionId"], started["revision"])
        paused = self._apply(user_id, pause_cmd, T0 + 20_000)["runtime"]
        self._apply(user_id, pause_cmd, T0 + 20_500)  # retry, same command id

        penalties = self._penalties(user_id)
        self.assertEqual(len(penalties), 1)
        self.assertEqual(penalties[0]["reason"], "pause")
        self.assertEqual(penalties[0]["affectedSeconds"], 20)
        self.assertEqual(penalties[0]["reasonLabel"], "暂停专注")

        self._apply(user_id, self._command("reset", paused["sessionId"], paused["revision"]), T0 + 30_000)
        reasons = [item["reason"] for item in self._penalties(user_id)]
        # Mainline strict mode only penalizes controls while running.
        self.assertEqual(reasons, ["pause"])
        self.assertEqual(self._snapshot(user_id, T0 + 31_000)["lastPenalty"]["reason"], "pause")

    def test_settlement_survives_concurrent_cloud_sync(self):
        user_id, _ = self._register("concurrent-user")

        def push_sync(marker: int):
            return api._sync_impl(
                api.SyncRequest(
                    todos=[
                        {
                            "id": f"todo-{marker}",
                            "title": f"并发任务 {marker}",
                            "isCompleted": False,
                            "createdAt": "2026-01-01T00:00:00Z",
                            "updatedAt": "2026-01-01T00:00:00Z",
                        }
                    ]
                ),
                user_id,
            )

        for round_index in range(3):
            started = self._start(user_id, T0 + round_index * 1_000_000)
            with ThreadPoolExecutor(max_workers=2) as pool:
                settle = pool.submit(self._advance, user_id, T0 + round_index * 1_000_000 + 60_000)
                sync = pool.submit(push_sync, round_index)
                self.assertTrue(settle.result())
                sync.result()

            history = self._history(user_id)
            self.assertEqual(len(history), round_index + 1)
            self.assertEqual(len(self._time_entries(user_id)), round_index + 1)
            db = api.get_db()
            try:
                row = db.execute(
                    "SELECT todos FROM sync_data WHERE user_id=?", (user_id,)
                ).fetchone()
            finally:
                db.close()
            ids = {item["id"] for item in json.loads(row["todos"])}
            self.assertEqual(ids, {f"todo-{index}" for index in range(round_index + 1)})

            # Back to focus idle for the next round.
            snapshot = self._snapshot(user_id, T0 + round_index * 1_000_000 + 61_000)
            if snapshot["runtime"]["status"] != "idle":
                continue
            self._apply(
                user_id,
                self._command(
                    "reset",
                    snapshot["runtime"]["sessionId"],
                    snapshot["runtime"]["revision"],
                ),
                T0 + round_index * 1_000_000 + 62_000,
            )

    def test_accounts_are_isolated(self):
        alice, _ = self._register("alice")
        bob, _ = self._register("bob")

        alice_runtime = self._start(alice)["runtime"]
        bob_snapshot = self._snapshot(bob)
        self.assertEqual(bob_snapshot["runtime"]["status"], "idle")
        self.assertNotEqual(bob_snapshot["runtime"]["sessionId"], alice_runtime["sessionId"])

        with self.assertRaises(api.focus_runtime.FocusRuntimeConflict):
            self._apply(
                bob,
                self._command("pause", alice_runtime["sessionId"], alice_runtime["revision"]),
                T0 + 1_000,
            )
        self.assertEqual(self._snapshot(alice, T0 + 2_000)["runtime"]["status"], "running")

    def test_deleted_history_is_not_resurrected(self):
        user_id, _ = self._register("history-user")
        started = self._start(user_id)["runtime"]
        session_id = started["sessionId"]
        self._advance(user_id, T0 + 60_000)
        self.assertEqual(len(self._history(user_id)), 1)

        # Simulate the client deleting the record through normal cloud sync.
        db = api.get_db()
        try:
            db.execute(
                "UPDATE sync_data SET pomodoro_sessions='[]', time_entries='[]' WHERE user_id=?",
                (user_id,),
            )
            db.commit()
        finally:
            db.close()

        snapshot = self._snapshot(user_id, T0 + 61_000)
        self.assertIsNone(snapshot["lastSession"])
        # Re-processing the same expiry must not re-create the deleted record.
        self.assertFalse(self._advance(user_id, T0 + 120_000))
        self.assertEqual(self._history(user_id), [])

        # A brand-new session still settles normally afterwards.
        reset = self._snapshot(user_id, T0 + 121_000)["runtime"]
        self._apply(
            user_id,
            self._command("reset", reset["sessionId"], reset["revision"]),
            T0 + 122_000,
        )
        fresh = self._start(user_id, T0 + 123_000)["runtime"]
        self._advance(user_id, T0 + 123_000 + 60_000)
        history = self._history(user_id)
        self.assertEqual([record["id"] for record in history], [fresh["sessionId"]])
        self.assertNotEqual(history[0]["id"], session_id)

    # ------------------------------------------------------------------
    # transport: HTTP + websocket
    # ------------------------------------------------------------------

    def test_ws_broadcasts_snapshot_to_two_same_account_connections(self):
        user_id, token = self._register("ws-user")
        headers = {"Authorization": f"Bearer {token}"}
        path = f"/ws/focus/runtime/events?token={token}"

        with TestClient(api.app) as client:
            with client.websocket_connect(path) as first:
                with client.websocket_connect(path) as second:
                    initial_first = first.receive_json()
                    initial_second = second.receive_json()
                    self.assertEqual(initial_first["event"], "focus.runtime")
                    self.assertEqual(initial_second["event"], "focus.runtime")
                    runtime = initial_first["data"]["runtime"]
                    self.assertEqual(runtime["status"], "idle")

                    response = client.post(
                        "/api/focus/runtime/commands",
                        headers=headers,
                        json={
                            "commandId": "ws-start",
                            "deviceId": "device-a",
                            "sessionId": runtime["sessionId"],
                            "expectedRevision": runtime["revision"],
                            "action": "start",
                            "payload": {"mode": "countdown", "config": dict(SHORT_CONFIG)},
                        },
                    )
                    self.assertEqual(response.status_code, 200, response.text)
                    started = response.json()["runtime"]
                    self.assertEqual(started["status"], "running")

                    pushed_first = first.receive_json()
                    pushed_second = second.receive_json()
                    for pushed in (pushed_first, pushed_second):
                        self.assertEqual(pushed["event"], "focus.runtime")
                        self.assertEqual(pushed["data"]["runtime"]["status"], "running")
                        self.assertEqual(
                            pushed["data"]["runtime"]["sessionId"], started["sessionId"]
                        )

                    snapshot = client.get("/api/focus/runtime", headers=headers)
                    self.assertEqual(snapshot.status_code, 200)
                    self.assertEqual(
                        snapshot.json()["runtime"]["revision"], started["revision"]
                    )

                    conflict = client.post(
                        "/api/focus/runtime/commands",
                        headers=headers,
                        json={
                            "commandId": "ws-stale",
                            "deviceId": "device-b",
                            "sessionId": runtime["sessionId"],
                            "expectedRevision": runtime["revision"],
                            "action": "pause",
                        },
                    )
                    self.assertEqual(conflict.status_code, 409)

    def test_revoked_credential_is_rejected_on_http_and_ws(self):
        user_id, token = self._register("revoked-user")
        headers = {"Authorization": f"Bearer {token}"}
        path = f"/ws/focus/runtime/events?token={token}"

        api._revoke_user_token(user_id)

        with TestClient(api.app) as client:
            self.assertEqual(client.get("/api/focus/runtime", headers=headers).status_code, 401)
            self.assertEqual(
                client.post(
                    "/api/focus/runtime/commands",
                    headers=headers,
                    json={
                        "commandId": "revoked",
                        "deviceId": "d",
                        "sessionId": "s",
                        "expectedRevision": 0,
                        "action": "start",
                    },
                ).status_code,
                401,
            )
            with self.assertRaises(WebSocketDisconnect) as closed:
                with client.websocket_connect(path):
                    self.fail("revoked credential opened a focus websocket")
            self.assertEqual(closed.exception.code, 1008)

    def test_contract_advertises_focus_runtime_sync(self):
        self.assertTrue(api.API_CONTRACT_FEATURES["focus_runtime_sync"])
        self.assertIn("GET /api/focus/runtime", api.API_CONTRACT_REQUIRED_ROUTES)
        self.assertIn("POST /api/focus/runtime/commands", api.API_CONTRACT_REQUIRED_ROUTES)
        self.assertIn("WS /ws/focus/runtime/events", api.API_CONTRACT_REQUIRED_ROUTES)

        with TestClient(api.app) as client:
            payload = client.get("/api/config").json()
        self.assertTrue(payload["features"]["focus_runtime_sync"])
        self.assertEqual(payload["api_contract_version"], api.API_CONTRACT_VERSION)

    # ------------------------------------------------------------------
    # account cleanup
    # ------------------------------------------------------------------

    def test_backup_wipe_and_account_deletion_clear_runtime(self):
        admin_id, _ = self._register("admin-user")
        self._make_admin(admin_id)
        user_id, _ = self._register("cleanup-user")

        started = self._start(user_id)["runtime"]
        self._advance(user_id, T0 + 60_000)
        self.assertEqual(len(self._history(user_id)), 1)

        api.admin_backup_wipe(user_id, admin_id)
        self.assertEqual(self._history(user_id), [])
        db = api.get_db()
        try:
            self.assertEqual(
                db.execute(
                    "SELECT COUNT(*) AS c FROM focus_runtime WHERE user_id=?", (user_id,)
                ).fetchone()["c"],
                1,
            )
        finally:
            db.close()
        # A wiped account starts from a fresh idle identity.
        wiped = self._snapshot(user_id, T0 + 61_000)["runtime"]
        self.assertEqual(wiped["status"], "idle")
        self.assertNotEqual(wiped["sessionId"], started["sessionId"])
        self.assertGreater(wiped["revision"], started["revision"] + 1)
        self.assertIsNone(wiped["taskName"])
        self.assertEqual(wiped["sourceDeviceId"], "")

        self._start(user_id, T0 + 70_000)
        api.admin_delete_user(user_id, admin_id)
        db = api.get_db()
        try:
            for table in ("focus_runtime", "focus_commands", "focus_settlements"):
                self.assertEqual(
                    db.execute(
                        f"SELECT COUNT(*) AS c FROM {table} WHERE user_id=?", (user_id,)
                    ).fetchone()["c"],
                    0,
                    table,
                )
        finally:
            db.close()

    def test_stop_preserves_strict_reset_penalty(self):
        user_id, _ = self._register("strict-stop-user")
        runtime = self._start(user_id, config={**SHORT_CONFIG, "strictFocusMode": True})["runtime"]
        self._apply(user_id, self._command(
            "stop", runtime["sessionId"], runtime["revision"]
        ), T0 + 20_000)
        penalties = self._penalties(user_id)
        self.assertEqual(len(penalties), 1)
        self.assertEqual(penalties[0]["reason"], "reset")
        self.assertEqual(penalties[0]["affectedSeconds"], 20)

    def test_finish_rejects_break_phase(self):
        user_id, _ = self._register("break-finish-user")
        self._start(user_id)
        self._advance(user_id, T0 + 60_000)
        runtime = self._start(user_id, T0 + 61_000)["runtime"]
        self.assertEqual(runtime["phase"], "shortBreak")
        with self.assertRaises(api.focus_runtime.FocusRuntimeConflict):
            self._apply(user_id, self._command(
                "finish", runtime["sessionId"], runtime["revision"]
            ), T0 + 62_000)
        self.assertEqual(len(self._history(user_id)), 1)

    def test_idle_stage_can_start_selected_focus_mode(self):
        user_id, _ = self._register("idle-mode-user")
        self._start(user_id)
        self._advance(user_id, T0 + 60_000)
        idle = self._snapshot(user_id, T0 + 61_000)["runtime"]
        self.assertEqual(idle["phase"], "shortBreak")
        runtime = self._apply(user_id, self._command(
            "start", idle["sessionId"], idle["revision"],
            {"mode": "countup", "phase": "focus", "config": SHORT_CONFIG},
        ), T0 + 61_000)["runtime"]
        self.assertEqual(runtime["phase"], "focus")
        self.assertEqual(runtime["mode"], "countup")
        self.assertEqual(runtime["status"], "running")


if __name__ == "__main__":
    unittest.main()
