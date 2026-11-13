"""In-process, account-scoped realtime revision hub for cloud sync.

The backend keeps one revision row per account in ``sync_data``.  This module
turns "the revision was committed" into an in-process notification without any
periodic database probe:

* FastAPI sync handlers run in the thread pool, so ``publish`` must be safe to
  call from any thread.  It never touches ``asyncio.Queue`` directly; it hops to
  the subscriber's event loop with ``loop.call_soon_threadsafe``.
* Each subscriber owns a bounded queue of capacity 1.  A burst of revisions
  collapses to the newest one instead of replaying stale intermediate states.
* A slow client can only lose intermediate revisions; it can never block the
  writer.
* Unsubscribing is immediate: pending callbacks already scheduled on the loop
  see the closed flag and drop the payload.

Deployment boundary: this hub is process-local.  It is exact for a single
uvicorn worker and is never claimed to work across workers or hosts.  The SSE
endpoint still sends an initial revision snapshot on every connection, so a
client that connected to another worker simply waits for its own process to
publish a newer revision.
"""

from __future__ import annotations

import asyncio
import threading
from typing import Dict, Optional


class SyncEventSubscriber:
    """One open SSE connection: bounded newest-only queue plus its own loop."""

    __slots__ = (
        "subscriber_id",
        "user_id",
        "loop",
        "queue",
        "closed",
        "_last_version",
    )

    def __init__(self, subscriber_id: int, user_id: str, loop: asyncio.AbstractEventLoop):
        self.subscriber_id = subscriber_id
        self.user_id = user_id
        self.loop = loop
        self.queue: asyncio.Queue = asyncio.Queue(maxsize=1)
        self.closed = False
        self._last_version = -1


class SyncEventHub:
    """Thread-safe registry of online SSE subscribers keyed by account."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._subscribers: Dict[str, Dict[int, SyncEventSubscriber]] = {}
        self._next_subscriber_id = 0

    # -- subscription lifecycle -------------------------------------------------
    def subscribe(self, user_id: str) -> SyncEventSubscriber:
        loop = asyncio.get_running_loop()
        with self._lock:
            self._next_subscriber_id += 1
            subscriber = SyncEventSubscriber(
                self._next_subscriber_id, str(user_id), loop
            )
            self._subscribers.setdefault(str(user_id), {})[
                subscriber.subscriber_id
            ] = subscriber
        return subscriber

    def unsubscribe(self, subscriber: Optional[SyncEventSubscriber]) -> None:
        if subscriber is None:
            return
        with self._lock:
            subscriber.closed = True
            bucket = self._subscribers.get(subscriber.user_id)
            if bucket is not None:
                bucket.pop(subscriber.subscriber_id, None)
                if not bucket:
                    self._subscribers.pop(subscriber.user_id, None)

    def has_subscribers(self, user_id: str) -> bool:
        with self._lock:
            return bool(self._subscribers.get(str(user_id)))

    def subscriber_count(self, user_id: str) -> int:
        with self._lock:
            return len(self._subscribers.get(str(user_id)) or {})

    # -- publishing -------------------------------------------------------------
    def publish(
        self,
        user_id: str,
        server_version: int,
        server_updated_at: str = "",
    ) -> int:
        """Notify that ``user_id`` committed ``server_version``.

        Returns the number of subscribers the revision was dispatched to.
        No database work and no loop interaction happens when nobody listens.
        """
        with self._lock:
            targets = list(self._subscribers.get(str(user_id), {}).values())
        if not targets:
            return 0
        payload = {
            "server_version": int(server_version or 0),
            "server_updated_at": str(server_updated_at or ""),
        }
        for subscriber in targets:
            self._dispatch(subscriber, payload)
        return len(targets)

    def _dispatch(self, subscriber: SyncEventSubscriber, payload: dict) -> None:
        try:
            subscriber.loop.call_soon_threadsafe(self._deliver, subscriber, payload)
        except RuntimeError:
            # The loop is already closed; the subscription is going away.
            self.unsubscribe(subscriber)

    def _deliver(self, subscriber: SyncEventSubscriber, payload: dict) -> None:
        """Runs on the subscriber's loop: newest revision wins, queue stays 1."""
        if subscriber.closed:
            return
        version = int(payload.get("server_version") or 0)
        if version < subscriber._last_version:
            return  # A late callback must not overwrite a newer revision.
        # Equal revisions still pass: paths such as an admin backup wipe refresh
        # ``updated_at`` without bumping ``sync_version``, and the stream dedupes
        # by the full (version, updated_at) signature before yielding.
        subscriber._last_version = version
        while True:
            try:
                subscriber.queue.get_nowait()
            except asyncio.QueueEmpty:
                break
        try:
            subscriber.queue.put_nowait(dict(payload))
        except asyncio.QueueFull:  # pragma: no cover - capacity is 1 and drained
            pass


SYNC_EVENTS_HUB = SyncEventHub()
