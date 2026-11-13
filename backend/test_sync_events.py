"""Targeted tests for the server-push sync revision stream.

These cover the account-level hub contract: immediate push after commit, no
business-data polling, rollback silence, bounded newest-only queues, reliable
unsubscribe, reconnect snapshots, worker-thread publishing, credential
revocation, and the write paths that reuse the shared revision publisher.
"""

import asyncio
import functools
import json
import os
import tempfile
import unittest
from unittest.mock import patch

from fastapi import HTTPException

# Keep the default settings path inside the test sandbox before main imports it.
_BOOTSTRAP_DIR = tempfile.TemporaryDirectory()
os.environ.setdefault(
    "DUOYI_DB_PATH", os.path.join(_BOOTSTRAP_DIR.name, "duoyi-sync-events.db")
)

# Test-only bootstrap credentials; production has no default password.
with patch.dict(os.environ, {"ADMIN_BOOTSTRAP_PASSWORD": "admin123"}):
    import main as api

HUB = api.sync_event_hub.SYNC_EVENTS_HUB


def _event_payload(chunk) -> dict:
    text = chunk.decode("utf-8") if isinstance(chunk, bytes) else chunk
    data_line = next(line for line in text.splitlines() if line.startswith("data: "))
    return json.loads(data_line.removeprefix("data: "))


async def _next_payload(stream) -> dict:
    chunk = await asyncio.wait_for(stream.__anext__(), timeout=3)
    return _event_payload(chunk)


class SyncEventsTest(unittest.TestCase):
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
        self._tmp.cleanup()

    def _register(self, username: str) -> str:
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
        res = api.register(
            api.RegisterRequest(username=username, password="pass123456")
        )
        return res["user_id"]

    def _make_coin_admin(self, username: str) -> str:
        return self._make_admin(username, "coins")

    def _make_admin(self, username: str, permission: str) -> str:
        user_id = self._register(username)
        db = api.get_db()
        try:
            db.execute(
                "UPDATE users SET is_admin=1, admin_permissions=? WHERE id=?",
                (json.dumps([permission]), user_id),
            )
            db.commit()
        finally:
            db.close()
        return user_id

    def _write_todo(self, user_id: str, title: str) -> dict:
        return api.sync(
            api.SyncRequest(
                todos=[
                    {
                        "id": f"todo-{title}",
                        "title": title,
                        "updatedAt": "2026-05-22T00:00:00Z",
                    }
                ]
            ),
            user_id=user_id,
        )

    # -- contract ---------------------------------------------------------------
    def test_api_contract_advertises_sync_push_events(self):
        self.assertEqual(api.API_CONTRACT_VERSION, "2026-06-01.9")
        self.assertIn("GET /api/sync/events", api.API_CONTRACT_REQUIRED_ROUTES)
        self.assertTrue(api.API_CONTRACT_FEATURES["sync_push_events"])
        registered = {
            (method, route.path)
            for route in api.app.routes
            for method in getattr(route, "methods", ())
        }
        self.assertIn(("GET", "/api/sync/events"), registered)

    # -- hub push ---------------------------------------------------------------
    def test_same_account_subscribers_receive_commit_and_other_account_does_not(self):
        user_a = self._register("sync-events-a")
        user_b = self._register("sync-events-b")

        async def scenario():
            first = HUB.subscribe(user_a)
            second = HUB.subscribe(user_a)
            other = HUB.subscribe(user_b)
            try:
                synced = await asyncio.to_thread(
                    functools.partial(self._write_todo, user_a, "mac-new-todo")
                )
                payload_a1 = await asyncio.wait_for(first.queue.get(), timeout=3)
                payload_a2 = await asyncio.wait_for(second.queue.get(), timeout=3)
                self.assertEqual(
                    payload_a1["server_version"], synced["server_version"]
                )
                self.assertEqual(
                    payload_a1["server_updated_at"], synced["server_updated_at"]
                )
                self.assertEqual(payload_a1, payload_a2)
                with self.assertRaises(asyncio.TimeoutError):
                    await asyncio.wait_for(other.queue.get(), timeout=0.2)
            finally:
                for subscriber in (first, second, other):
                    HUB.unsubscribe(subscriber)

        asyncio.run(scenario())
        self.assertEqual(HUB.subscriber_count(user_a), 0)

    def test_publish_from_worker_thread_reaches_event_loop(self):
        user_id = self._register("sync-events-thread")

        async def scenario():
            subscriber = HUB.subscribe(user_id)
            try:
                dispatched = await asyncio.to_thread(
                    HUB.publish, user_id, 7, "2026-05-22T00:00:07Z"
                )
                self.assertEqual(dispatched, 1)
                payload = await asyncio.wait_for(subscriber.queue.get(), timeout=2)
                self.assertEqual(
                    payload,
                    {
                        "server_version": 7,
                        "server_updated_at": "2026-05-22T00:00:07Z",
                    },
                )
            finally:
                HUB.unsubscribe(subscriber)

        asyncio.run(scenario())

    def test_burst_keeps_only_newest_revision(self):
        user_id = self._register("sync-events-burst")

        async def scenario():
            subscriber = HUB.subscribe(user_id)
            try:
                for version in range(1, 6):
                    await asyncio.to_thread(
                        HUB.publish,
                        user_id,
                        version,
                        f"2026-05-22T00:00:0{version}Z",
                    )
                await asyncio.sleep(0.05)
                self.assertEqual(subscriber.queue.qsize(), 1)
                payload = subscriber.queue.get_nowait()
                self.assertEqual(payload["server_version"], 5)
                # A late callback for an older revision must not clobber it.
                await asyncio.to_thread(
                    HUB.publish, user_id, 4, "2026-05-22T00:00:04Z"
                )
                await asyncio.sleep(0.05)
                self.assertEqual(subscriber.queue.qsize(), 0)
            finally:
                HUB.unsubscribe(subscriber)

        asyncio.run(scenario())

    def test_equal_revision_updated_at_refresh_is_delivered(self):
        user_id = self._register("sync-events-same-version")

        async def scenario():
            subscriber = HUB.subscribe(user_id)
            try:
                HUB.publish(user_id, 5, "2026-06-01T00:00:00Z")
                await asyncio.sleep(0.05)
                subscriber.queue.get_nowait()
                # A same-revision updated_at refresh must still be delivered.
                HUB.publish(user_id, 5, "2026-06-01 00:05:00")
                await asyncio.sleep(0.05)
                self.assertEqual(subscriber.queue.qsize(), 1)
                payload = subscriber.queue.get_nowait()
                self.assertEqual(payload["server_version"], 5)
                self.assertEqual(payload["server_updated_at"], "2026-06-01 00:05:00")
            finally:
                HUB.unsubscribe(subscriber)

        asyncio.run(scenario())

    def test_unsubscribe_drops_pending_callbacks(self):
        user_id = self._register("sync-events-unsub")

        async def scenario():
            subscriber = HUB.subscribe(user_id)
            HUB.publish(user_id, 3, "2026-05-22T00:00:03Z")
            HUB.unsubscribe(subscriber)
            await asyncio.sleep(0.05)
            self.assertFalse(HUB.has_subscribers(user_id))
            self.assertEqual(subscriber.queue.qsize(), 0)
            HUB.publish(user_id, 4, "2026-05-22T00:00:04Z")
            await asyncio.sleep(0.05)
            self.assertEqual(subscriber.queue.qsize(), 0)

        asyncio.run(scenario())

    # -- SSE endpoint -----------------------------------------------------------
    def test_stream_first_frame_then_heartbeat_without_data_reads(self):
        user_id = self._register("sync-events-heartbeat")
        self._write_todo(user_id, "heartbeat-seed")

        async def scenario():
            response = await api.sync_events(interval_seconds=2, user_id=user_id)
            stream = response.body_iterator
            try:
                payload = await _next_payload(stream)
                self.assertGreaterEqual(payload["server_version"], 1)
                with patch.object(
                    api, "_sync_revision", side_effect=AssertionError("polled")
                ):
                    chunk = await asyncio.wait_for(stream.__anext__(), timeout=4)
                text = chunk.decode("utf-8") if isinstance(chunk, bytes) else chunk
                self.assertEqual(text, ": heartbeat\n\n")
            finally:
                await stream.aclose()

        asyncio.run(scenario())
        self.assertEqual(HUB.subscriber_count(user_id), 0)

    def test_rollback_does_not_publish(self):
        user_id = self._register("sync-events-rollback")

        async def scenario():
            subscriber = HUB.subscribe(user_id)
            try:
                with patch.object(
                    api, "_merge_workspace_payloads", side_effect=RuntimeError("boom")
                ):
                    with self.assertRaises(RuntimeError):
                        await asyncio.to_thread(
                            functools.partial(self._write_todo, user_id, "rolled-back")
                        )
                with self.assertRaises(asyncio.TimeoutError):
                    await asyncio.wait_for(subscriber.queue.get(), timeout=0.2)
            finally:
                HUB.unsubscribe(subscriber)

        asyncio.run(scenario())
        db = api.get_db()
        try:
            row = db.execute(
                "SELECT sync_version FROM sync_data WHERE user_id=?", (user_id,)
            ).fetchone()
        finally:
            db.close()
        self.assertFalse(row and int(row["sync_version"] or 0) > 0)

    def test_reconnect_snapshot_includes_offline_changes(self):
        user_id = self._register("sync-events-reconnect")

        async def scenario():
            response = await api.sync_events(interval_seconds=2, user_id=user_id)
            stream = response.body_iterator
            try:
                first = await _next_payload(stream)
            finally:
                await stream.aclose()
            self.assertEqual(first["server_version"], 0)
            synced = await asyncio.to_thread(
                functools.partial(self._write_todo, user_id, "offline-todo")
            )
            reopened = await api.sync_events(interval_seconds=2, user_id=user_id)
            stream = reopened.body_iterator
            try:
                snapshot = await _next_payload(stream)
            finally:
                await stream.aclose()
            self.assertEqual(snapshot["server_version"], synced["server_version"])
            self.assertEqual(snapshot["server_updated_at"], synced["server_updated_at"])

        asyncio.run(scenario())
        self.assertEqual(HUB.subscriber_count(user_id), 0)

    def test_revoked_credential_stops_further_events(self):
        user_id = self._register("sync-events-revoked")
        authorization = f"Bearer {api.TOKENS[user_id]}"

        async def scenario():
            response = await api.sync_events(
                interval_seconds=2,
                user_id=user_id,
                authorization=authorization,
            )
            stream = response.body_iterator
            try:
                await _next_payload(stream)
                login_headers = {"Authorization": authorization}
                api.logout(user_id=user_id, authorization=login_headers["Authorization"])
                await asyncio.to_thread(
                    functools.partial(self._write_todo, user_id, "after-revoke")
                )
                with self.assertRaises(StopAsyncIteration):
                    await asyncio.wait_for(stream.__anext__(), timeout=3)
            finally:
                await stream.aclose()

        asyncio.run(scenario())
        self.assertEqual(HUB.subscriber_count(user_id), 0)

    # -- shared revision publisher ---------------------------------------------
    def test_delta_and_item_delta_reuse_publisher(self):
        user_id = self._register("sync-events-delta")

        async def scenario():
            response = await api.sync_events(interval_seconds=2, user_id=user_id)
            stream = response.body_iterator
            try:
                first = await _next_payload(stream)
                delta_payload = await asyncio.to_thread(
                    api.sync_delta,
                    api.SyncDeltaRequest(
                        collections={
                            "notes": [
                                {
                                    "id": "note-delta",
                                    "title": "delta",
                                    "updatedAt": "2026-05-22T00:00:00Z",
                                }
                            ]
                        }
                    ),
                    user_id,
                )
                after_delta = await _next_payload(stream)
                self.assertEqual(
                    after_delta["server_version"],
                    delta_payload["server_version"],
                )
                self.assertGreater(after_delta["server_version"], first["server_version"])

                item_payload = await asyncio.to_thread(
                    api.sync_item_delta,
                    api.SyncItemDeltaRequest(
                        items={
                            "notes": [
                                {
                                    "id": "note-item",
                                    "title": "item",
                                    "updatedAt": "2026-05-22T00:00:01Z",
                                }
                            ]
                        }
                    ),
                    user_id,
                )
                after_item = await _next_payload(stream)
                self.assertEqual(
                    after_item["server_version"],
                    item_payload["server_version"],
                )
                self.assertGreater(after_item["server_version"], after_delta["server_version"])
            finally:
                await stream.aclose()

        asyncio.run(scenario())

    def test_admin_coin_write_publishes(self):
        admin_id = self._make_coin_admin("sync-events-coin-admin")
        user_id = self._register("sync-events-coin-user")

        async def scenario():
            response = await api.sync_events(interval_seconds=2, user_id=user_id)
            stream = response.body_iterator
            try:
                await _next_payload(stream)
                result = await asyncio.to_thread(
                    api._admin_adjust_user_coins_impl,
                    user_id,
                    api.UserCoinAdjustment(delta=5, reason="sync push"),
                    admin_id,
                )
                payload = await _next_payload(stream)
                self.assertEqual(payload["server_version"], result["server_version"])
            finally:
                await stream.aclose()

        asyncio.run(scenario())

    def test_admin_wipe_publishes_new_revision(self):
        admin_id = self._make_admin("sync-events-wipe-admin", "backup")
        user_id = self._register("sync-events-wipe-user")

        async def scenario():
            response = await api.sync_events(interval_seconds=2, user_id=user_id)
            stream = response.body_iterator
            try:
                first = await _next_payload(stream)
                await asyncio.to_thread(api.admin_backup_wipe, user_id, admin_id)
                payload = await _next_payload(stream)
                self.assertGreater(
                    payload["server_version"], first["server_version"]
                )
                self.assertTrue(payload["server_updated_at"])
            finally:
                await stream.aclose()

        asyncio.run(scenario())

    def test_focus_runtime_settlement_publishes_history_change(self):
        user_id = self._register("sync-events-focus")

        db = api.get_db()
        try:
            now = api.focus_runtime.now_ms()
            api.focus_runtime.ensure_runtime(db, user_id, now)
            db.execute(
                "UPDATE focus_runtime SET status='running', mode='countdown', "
                "phase='focus', duration_ms=1500000, elapsed_ms=0, "
                "anchor_at_ms=?, started_at_ms=? WHERE user_id=?",
                (now - 1600000, now - 1600000, user_id),
            )
            db.commit()
        finally:
            db.close()

        async def scenario():
            subscriber = HUB.subscribe(user_id)
            try:
                envelope, changed = await asyncio.to_thread(
                    api._focus_runtime_read, user_id
                )
                self.assertTrue(changed)
                payload = await asyncio.wait_for(subscriber.queue.get(), timeout=3)
                self.assertGreaterEqual(payload["server_version"], 1)
            finally:
                HUB.unsubscribe(subscriber)

        asyncio.run(scenario())
        db = api.get_db()
        try:
            row = db.execute(
                "SELECT pomodoro_sessions FROM sync_data WHERE user_id=?", (user_id,)
            ).fetchone()
        finally:
            db.close()
        self.assertTrue(row and json.loads(row["pomodoro_sessions"]))

    def test_welfare_commit_notifies_every_affected_online_account(self):
        admin_id = self._make_coin_admin("push-welfare-admin")
        user_ids = [self._register("push-welfare-first"), self._register("push-welfare-second")]

        async def scenario():
            subscribers = [HUB.subscribe(uid) for uid in user_ids]
            try:
                result = await asyncio.to_thread(
                    api.admin_create_welfare_grant,
                    api.WelfareGrantCreate(title="push all", generate_bonus=2),
                    admin_id,
                )
                self.assertGreaterEqual(result["users"], 2)
                for subscriber in subscribers:
                    event = await asyncio.wait_for(subscriber.queue.get(), timeout=1)
                    self.assertGreater(event["server_version"], 0)
            finally:
                for subscriber in subscribers:
                    HUB.unsubscribe(subscriber)

        asyncio.run(scenario())

    def test_welfare_without_active_recipients_returns_success(self):
        admin_id = self._make_coin_admin("push-welfare-empty")
        db = api.get_db()
        try:
            db.execute("UPDATE users SET is_disabled=1")
            db.commit()
        finally:
            db.close()
        with patch.object(api, "_ensure_admin_permission"):
            result = api.admin_create_welfare_grant(
                api.WelfareGrantCreate(generate_bonus=1), admin_id
            )
        self.assertEqual(result["users"], 0)
        self.assertEqual(result["status"], "ok")

    def test_notification_failure_does_not_fail_committed_write(self):
        user_id = self._register("push-notification-failure")

        async def scenario():
            subscriber = HUB.subscribe(user_id)
            try:
                with patch.object(api, "_sync_revision", side_effect=RuntimeError("read failed")):
                    with self.assertLogs(api.__name__, level="ERROR"):
                        result = await asyncio.to_thread(self._write_todo, user_id, "committed")
                self.assertGreater(result["server_version"], 0)
                self.assertEqual(api._sync_revision(user_id)["server_version"], result["server_version"])
            finally:
                HUB.unsubscribe(subscriber)

        asyncio.run(scenario())

    def test_credential_verification_error_closes_before_first_frame(self):
        user_id = self._register("push-auth-error")
        authorization = f"Bearer {api.TOKENS[user_id]}"

        async def scenario():
            response = await api.sync_events(interval_seconds=2, user_id=user_id, authorization=authorization)
            stream = response.body_iterator
            try:
                with patch.object(api, "_verify_token_value", side_effect=RuntimeError("database unavailable")):
                    with self.assertRaises(StopAsyncIteration):
                        await asyncio.wait_for(stream.__anext__(), timeout=1)
            finally:
                await stream.aclose()

        asyncio.run(scenario())
        self.assertEqual(HUB.subscriber_count(user_id), 0)

    def test_revocation_before_stream_iteration_sends_no_first_frame(self):
        user_id = self._register("push-auth-first-frame")
        authorization = f"Bearer {api.TOKENS[user_id]}"

        async def scenario():
            response = await api.sync_events(interval_seconds=2, user_id=user_id, authorization=authorization)
            api.logout(user_id=user_id, authorization=authorization)
            stream = response.body_iterator
            try:
                with self.assertRaises(StopAsyncIteration):
                    await asyncio.wait_for(stream.__anext__(), timeout=1)
            finally:
                await stream.aclose()

        asyncio.run(scenario())
        self.assertEqual(HUB.subscriber_count(user_id), 0)


if __name__ == "__main__":
    unittest.main()
