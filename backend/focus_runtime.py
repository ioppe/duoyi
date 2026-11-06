"""Server-authoritative focus runtime for same-account multi-device sync.

The module owns the three private tables (``focus_runtime``, ``focus_commands``,
``focus_settlements``) and the pure state machine described in
``docs/focus-runtime-sync.md``.  It never opens its own connection: callers pass
a connection that is already inside the transaction the change must be atomic
in, so a settlement and the history it writes commit together.

Settlements append to the existing ``sync_data`` JSON collections and only
update those columns plus ``sync_version``/``updated_at``; the whole-row
``INSERT OR REPLACE`` in the cloud-sync path is deliberately left untouched.
"""

from __future__ import annotations

import hashlib
import json
import time
import uuid
from datetime import datetime, timezone
from typing import Any, Optional

STATUS_IDLE = "idle"
STATUS_RUNNING = "running"
STATUS_PAUSED = "paused"
STATUSES = (STATUS_IDLE, STATUS_RUNNING, STATUS_PAUSED)

MODE_COUNTDOWN = "countdown"
MODE_COUNTUP = "countup"
MODES = (MODE_COUNTDOWN, MODE_COUNTUP)

PHASE_FOCUS = "focus"
PHASE_SHORT_BREAK = "shortBreak"
PHASE_LONG_BREAK = "longBreak"
PHASES = (PHASE_FOCUS, PHASE_SHORT_BREAK, PHASE_LONG_BREAK)
PHASE_TYPE_INDEX = {PHASE_FOCUS: 0, PHASE_SHORT_BREAK: 1, PHASE_LONG_BREAK: 2}

ACTION_START = "start"
ACTION_PAUSE = "pause"
ACTION_RESUME = "resume"
ACTION_STOP = "stop"
ACTION_RESET = "reset"
ACTION_FINISH = "finish"
ACTION_SKIP = "skip"
ACTION_UPDATE = "update"
ACTIONS = (
    ACTION_START,
    ACTION_PAUSE,
    ACTION_RESUME,
    ACTION_STOP,
    ACTION_RESET,
    ACTION_FINISH,
    ACTION_SKIP,
    ACTION_UPDATE,
)

# Explicit task metadata updates; nothing else may be written through `update`.
TASK_FIELDS = ("taskName", "todoId", "subtaskId", "todoTitle", "tag", "focusRoomId")

# PomodoroConfig stores its durations in seconds and clamps them to this range.
MIN_DURATION_SECONDS = 60
MAX_DURATION_SECONDS = 12 * 60 * 60
# Count-up settlement reuses the mainline clamp(1, 24h).
COUNTUP_MAX_MS = 24 * 60 * 60 * 1000

MAX_ADVANCE_STEPS = 64

DEFAULT_CONFIG: dict[str, Any] = {
    "focusDuration": 1500,
    "shortBreakDuration": 300,
    "longBreakDuration": 900,
    "sessionsPerLongBreak": 4,
    "whiteNoiseSound": "none",
    "autoStartBreaks": False,
    "autoStartFocus": False,
    "autoEnableDnd": False,
    "strictFocusMode": False,
    "monitorDistractingApps": False,
    "distractingAppPackages": [],
    "distractingAppSelectionMode": "blacklist",
    "focusRoomId": None,
    "updatedAt": None,
}

PENALTY_LABELS = {
    "pause": "暂停专注",
    "skip": "跳过专注",
    "reset": "重置专注",
}


class FocusRuntimeError(Exception):
    """Base class for client-facing runtime errors."""

    status_code = 400

    def __init__(self, detail: str):
        super().__init__(detail)
        self.detail = detail


class FocusRuntimeConflict(FocusRuntimeError):
    """The command no longer matches the authoritative snapshot."""

    status_code = 409


class FocusRuntimeInvalid(FocusRuntimeError):
    """The command payload itself is not acceptable."""

    status_code = 422


# --------------------------------------------------------------------------
# schema
# --------------------------------------------------------------------------

SCHEMA_STATEMENTS = (
    """
    CREATE TABLE IF NOT EXISTS focus_runtime (
        user_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'idle',
        mode TEXT NOT NULL DEFAULT 'countdown',
        phase TEXT NOT NULL DEFAULT 'focus',
        duration_ms INTEGER NOT NULL DEFAULT 0,
        elapsed_ms INTEGER NOT NULL DEFAULT 0,
        anchor_at_ms INTEGER,
        started_at_ms INTEGER,
        completed_sessions INTEGER NOT NULL DEFAULT 0,
        source_device_id TEXT NOT NULL DEFAULT '',
        config_json TEXT NOT NULL DEFAULT '{}',
        task_name TEXT,
        todo_id TEXT,
        subtask_id TEXT,
        todo_title TEXT,
        tag TEXT,
        focus_room_id TEXT,
        updated_at_ms INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS focus_commands (
        user_id TEXT NOT NULL,
        command_id TEXT NOT NULL,
        payload_digest TEXT NOT NULL,
        action TEXT NOT NULL DEFAULT '',
        revision_after INTEGER NOT NULL DEFAULT 0,
        result_json TEXT NOT NULL DEFAULT '{}',
        created_at_ms INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(user_id, command_id),
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS focus_settlements (
        user_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        settled_at_ms INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(user_id, session_id),
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    )
    """,
)


def ensure_schema(conn) -> None:
    """Create the private runtime tables inside the caller's transaction."""
    for statement in SCHEMA_STATEMENTS:
        conn.execute(statement)


def clear_user_data(conn, user_id: str) -> None:
    """Clear private state while preserving the account's revision clock."""
    conn.execute(
        "UPDATE focus_runtime SET session_id=?, revision=revision+1, "
        "status='idle', mode='countdown', phase='focus', duration_ms=?, "
        "elapsed_ms=0, anchor_at_ms=NULL, started_at_ms=NULL, completed_sessions=0, "
        "source_device_id='', config_json='{}', task_name=NULL, todo_id=NULL, "
        "subtask_id=NULL, todo_title=NULL, tag=NULL, focus_room_id=NULL, updated_at_ms=? "
        "WHERE user_id=?",
        (_new_id(), _phase_duration_ms(DEFAULT_CONFIG, PHASE_FOCUS), now_ms(), user_id),
    )
    conn.execute("DELETE FROM focus_commands WHERE user_id=?", (user_id,))
    conn.execute("DELETE FROM focus_settlements WHERE user_id=?", (user_id,))


# --------------------------------------------------------------------------
# small helpers
# --------------------------------------------------------------------------


def now_ms() -> int:
    return int(time.time() * 1000)


def iso_from_ms(value: int) -> str:
    return (
        datetime.fromtimestamp(int(value) / 1000, timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def _new_id() -> str:
    return str(uuid.uuid4())


def _clean_text(value: Any, limit: int) -> str:
    if value is None:
        return ""
    text = str(value).strip()
    if len(text) > limit:
        text = text[:limit]
    return text


def _optional_text(value: Any, limit: int = 400) -> Optional[str]:
    if value is None:
        return None
    text = str(value).strip()
    if not text or len(text) > limit:
        return None
    return text


def _as_int(value: Any, *, default: Optional[int] = None) -> Optional[int]:
    if isinstance(value, bool):
        return default
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        try:
            return int(value.strip())
        except ValueError:
            return default
    return default


def _as_bool(value: Any, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        text = value.strip().lower()
        if text in ("1", "true", "yes", "on"):
            return True
        if text in ("0", "false", "no", "off", ""):
            return False
    return default


def _json_list(raw: Any) -> list:
    if not raw:
        return []
    try:
        value = json.loads(raw) if isinstance(raw, str) else raw
    except (TypeError, ValueError):
        return []
    return value if isinstance(value, list) else []


def _config_dict(row) -> dict:
    try:
        value = json.loads(row["config_json"] or "{}")
    except (TypeError, ValueError):
        value = {}
    if not isinstance(value, dict):
        value = {}
    merged = dict(DEFAULT_CONFIG)
    merged.update(value)
    return merged


def normalize_config(raw: Any) -> dict:
    """Validate PomodoroConfig seconds/auto-rotation fields for this session.

    Sound volume and native permissions stay device-local, so they are dropped
    from the shared session config instead of being replicated to other clients.
    """
    if raw is None:
        raw = {}
    if not isinstance(raw, dict):
        raise FocusRuntimeInvalid("config must be an object")

    config = dict(DEFAULT_CONFIG)
    for key in ("focusDuration", "shortBreakDuration", "longBreakDuration"):
        if key not in raw:
            continue
        seconds = _as_int(raw.get(key))
        if seconds is None:
            raise FocusRuntimeInvalid(f"config.{key} must be an integer")
        if seconds < MIN_DURATION_SECONDS or seconds > MAX_DURATION_SECONDS:
            raise FocusRuntimeInvalid(
                f"config.{key} must be between {MIN_DURATION_SECONDS} and "
                f"{MAX_DURATION_SECONDS} seconds"
            )
        config[key] = seconds

    if "sessionsPerLongBreak" in raw:
        count = _as_int(raw.get("sessionsPerLongBreak"))
        if count is None or count < 1 or count > 20:
            raise FocusRuntimeInvalid("config.sessionsPerLongBreak must be 1..20")
        config["sessionsPerLongBreak"] = count

    for key in (
        "autoStartBreaks",
        "autoStartFocus",
        "autoEnableDnd",
        "strictFocusMode",
        "monitorDistractingApps",
    ):
        if key in raw:
            config[key] = _as_bool(raw.get(key), bool(config[key]))

    sound = raw.get("whiteNoiseSound")
    if sound is not None:
        config["whiteNoiseSound"] = _clean_text(sound, 60) or "none"

    mode = raw.get("distractingAppSelectionMode")
    if mode is not None:
        normalized = _clean_text(mode, 20).lower()
        config["distractingAppSelectionMode"] = (
            normalized if normalized in ("blacklist", "whitelist") else "blacklist"
        )

    packages = raw.get("distractingAppPackages")
    if isinstance(packages, list):
        config["distractingAppPackages"] = sorted(
            {
                str(item).strip()
                for item in packages
                if str(item).strip()
            }
        )

    if "focusRoomId" in raw:
        config["focusRoomId"] = _optional_text(raw.get("focusRoomId"), 120)

    updated_at = raw.get("updatedAt")
    if isinstance(updated_at, str) and updated_at.strip():
        config["updatedAt"] = updated_at.strip()

    return config


def _phase_duration_ms(config: dict, phase: str) -> int:
    if phase == PHASE_SHORT_BREAK:
        seconds = _as_int(config.get("shortBreakDuration"), default=300) or 300
    elif phase == PHASE_LONG_BREAK:
        seconds = _as_int(config.get("longBreakDuration"), default=900) or 900
    else:
        seconds = _as_int(config.get("focusDuration"), default=1500) or 1500
    return max(MIN_DURATION_SECONDS, min(MAX_DURATION_SECONDS, seconds)) * 1000


def _elapsed_at(row, at_ms: int) -> int:
    elapsed = int(row["elapsed_ms"] or 0)
    if row["status"] != STATUS_RUNNING:
        return elapsed
    anchor = row["anchor_at_ms"]
    if anchor is None:
        return elapsed
    return elapsed + max(0, int(at_ms) - int(anchor))


def _deadline_ms(row) -> Optional[int]:
    if row["status"] != STATUS_RUNNING:
        return None
    anchor = row["anchor_at_ms"]
    if anchor is None:
        return None
    remaining = int(row["duration_ms"] or 0) - _elapsed_at(row, anchor)
    return int(anchor) + max(0, remaining)


def is_due(row, at_ms: int) -> bool:
    """True when a running countdown has reached its deadline."""
    if row is None or row["status"] != STATUS_RUNNING:
        return False
    if row["mode"] != MODE_COUNTDOWN:
        return False
    deadline = _deadline_ms(row)
    return deadline is not None and deadline <= int(at_ms)


# --------------------------------------------------------------------------
# row access
# --------------------------------------------------------------------------


def fetch_runtime(conn, user_id: str):
    return conn.execute(
        "SELECT * FROM focus_runtime WHERE user_id=?", (user_id,)
    ).fetchone()


def ensure_runtime(conn, user_id: str, at_ms: int):
    row = fetch_runtime(conn, user_id)
    if row is not None:
        return row
    conn.execute(
        "INSERT OR IGNORE INTO focus_runtime("
        "user_id, session_id, revision, status, mode, phase, duration_ms, "
        "elapsed_ms, anchor_at_ms, started_at_ms, completed_sessions, "
        "source_device_id, config_json, updated_at_ms) "
        "VALUES(?,?,0,?,?,?,?,0,NULL,NULL,0,'','{}',?)",
        (
            user_id,
            _new_id(),
            STATUS_IDLE,
            MODE_COUNTDOWN,
            PHASE_FOCUS,
            _phase_duration_ms(DEFAULT_CONFIG, PHASE_FOCUS),
            at_ms,
        ),
    )
    row = fetch_runtime(conn, user_id)
    if row is None:  # pragma: no cover - only possible without the users row
        raise FocusRuntimeConflict("runtime row unavailable")
    return row


def runtime_view(row) -> dict:
    return {
        "sessionId": row["session_id"],
        "revision": int(row["revision"] or 0),
        "status": row["status"],
        "mode": row["mode"],
        "phase": row["phase"],
        "durationMs": int(row["duration_ms"] or 0),
        "elapsedMs": int(row["elapsed_ms"] or 0),
        "anchorAtMs": row["anchor_at_ms"],
        "startedAtMs": row["started_at_ms"],
        "completedSessions": int(row["completed_sessions"] or 0),
        "sourceDeviceId": row["source_device_id"] or "",
        "config": _config_dict(row),
        "taskName": row["task_name"],
        "todoId": row["todo_id"],
        "subtaskId": row["subtask_id"],
        "todoTitle": row["todo_title"],
        "tag": row["tag"],
        "focusRoomId": row["focus_room_id"],
    }


def _sync_row(conn, user_id: str):
    return conn.execute(
        "SELECT pomodoro_sessions, time_entries, focus_penalties, sync_version "
        "FROM sync_data WHERE user_id=?",
        (user_id,),
    ).fetchone()


def _task_label(row) -> Optional[str]:
    task = _optional_text(row["task_name"])
    todo_title = _optional_text(row["todo_title"])
    if row["subtask_id"] and todo_title:
        return f"{todo_title} / {task}" if task else todo_title
    return task


# --------------------------------------------------------------------------
# settlement (history + time footprint + version) and penalties
# --------------------------------------------------------------------------


def _write_settlement(conn, user_id: str, row, end_ms: int, duration_ms: int) -> Optional[dict]:
    """Record one canonical session exactly once; return it when newly written."""
    session_id = row["session_id"]
    inserted = conn.execute(
        "INSERT OR IGNORE INTO focus_settlements(user_id, session_id, settled_at_ms) "
        "VALUES(?,?,?)",
        (user_id, session_id, end_ms),
    )
    if inserted.rowcount == 0:
        return None

    phase = row["phase"]
    config = _config_dict(row)
    end_text = iso_from_ms(end_ms)
    start_text = iso_from_ms(int(end_ms) - max(0, int(duration_ms)))
    session = {
        "id": session_id,
        "startTime": start_text,
        "endTime": end_text,
        "durationSeconds": max(0, int(duration_ms) // 1000),
        "type": PHASE_TYPE_INDEX.get(phase, 0),
        "taskName": row["task_name"],
        "todoId": row["todo_id"],
        "subtaskId": row["subtask_id"],
        "todoTitle": row["todo_title"],
        "whiteNoiseSound": config.get("whiteNoiseSound") or "none",
        "tag": row["tag"],
        "focusRoomId": row["focus_room_id"],
        "updatedAt": end_text,
    }

    conn.execute("INSERT OR IGNORE INTO sync_data(user_id) VALUES(?)", (user_id,))
    sync_row = _sync_row(conn, user_id)
    sessions = _json_list(sync_row["pomodoro_sessions"] if sync_row else None)
    if not any(str(item.get("id")) == session_id for item in sessions if isinstance(item, dict)):
        sessions.append(session)

    entries = _json_list(sync_row["time_entries"] if sync_row else None)
    if phase == PHASE_FOCUS:
        dedupe_key = f"pomodoro:{session_id}"
        exists = any(
            isinstance(item, dict) and item.get("dedupeKey") == dedupe_key
            for item in entries
        )
        if not exists:
            sound = config.get("whiteNoiseSound") or "none"
            entries.append(
                {
                    "id": _new_id(),
                    "title": _task_label(row) or "番茄专注",
                    "startAt": start_text,
                    "endAt": end_text,
                    "category": 0,
                    "source": 1,
                    "sourceId": session_id,
                    "dedupeKey": dedupe_key,
                    "note": "" if sound == "none" else f"白噪音：{sound}",
                    "createdAt": end_text,
                    "updatedAt": end_text,
                }
            )

    version = int(sync_row["sync_version"] or 0) + 1 if sync_row else 1
    conn.execute(
        "UPDATE sync_data SET pomodoro_sessions=?, time_entries=?, sync_version=?, "
        "updated_at=? WHERE user_id=?",
        (
            json.dumps(sessions, ensure_ascii=False),
            json.dumps(entries, ensure_ascii=False),
            version,
            iso_from_ms(now_ms()),
            user_id,
        ),
    )
    return session


def _affected_seconds(row, at_ms: int) -> int:
    elapsed = _elapsed_at(row, at_ms)
    if row["mode"] == MODE_COUNTUP:
        return max(1, min(COUNTUP_MAX_MS // 1000, elapsed // 1000))
    target = max(1, int(row["duration_ms"] or 0) // 1000)
    return max(1, min(target, elapsed // 1000))


def _write_penalty(conn, user_id: str, row, reason: str, at_ms: int) -> Optional[dict]:
    """One penalty per accepted control command, in the existing JSON shape."""
    if reason not in PENALTY_LABELS:
        return None
    penalty_id = f"focus:{_new_id()}"
    conn.execute("INSERT OR IGNORE INTO sync_data(user_id) VALUES(?)", (user_id,))
    sync_row = _sync_row(conn, user_id)
    penalties = _json_list(sync_row["focus_penalties"] if sync_row else None)
    if any(str(item.get("id")) == penalty_id for item in penalties if isinstance(item, dict)):
        return None
    occurred = iso_from_ms(at_ms)
    penalty = {
        "id": penalty_id,
        "occurredAt": occurred,
        "updatedAt": occurred,
        "reason": reason,
        "reasonLabel": PENALTY_LABELS[reason],
        "affectedSeconds": _affected_seconds(row, at_ms),
        "taskName": row["task_name"],
        "tag": row["tag"],
        "focusRoomId": row["focus_room_id"],
        "appPackage": None,
        "appLabel": None,
    }
    penalties.insert(0, penalty)
    version = int(sync_row["sync_version"] or 0) + 1 if sync_row else 1
    conn.execute(
        "UPDATE sync_data SET focus_penalties=?, sync_version=?, updated_at=? "
        "WHERE user_id=?",
        (
            json.dumps(penalties, ensure_ascii=False),
            version,
            iso_from_ms(now_ms()),
            user_id,
        ),
    )
    return penalty


def _last_settled_session(conn, user_id: str) -> Optional[dict]:
    """Latest settlement that is still present in history (deleted stays deleted)."""
    sync_row = _sync_row(conn, user_id)
    if sync_row is None:
        return None
    sessions = {
        str(item.get("id")): item
        for item in _json_list(sync_row["pomodoro_sessions"])
        if isinstance(item, dict) and item.get("id") is not None
    }
    if not sessions:
        return None
    rows = conn.execute(
        "SELECT session_id FROM focus_settlements WHERE user_id=? "
        "ORDER BY settled_at_ms DESC LIMIT 50",
        (user_id,),
    ).fetchall()
    for row in rows:
        record = sessions.get(str(row["session_id"]))
        if record is not None:
            return record
    return None


def _last_penalty(conn, user_id: str) -> Optional[dict]:
    sync_row = _sync_row(conn, user_id)
    if sync_row is None:
        return None
    penalties = [
        item for item in _json_list(sync_row["focus_penalties"]) if isinstance(item, dict)
    ]
    if not penalties:
        return None
    return max(
        penalties,
        key=lambda item: str(item.get("occurredAt") or item.get("updatedAt") or ""),
    )


def build_envelope(conn, user_id: str, at_ms: Optional[int] = None) -> dict:
    at_ms = now_ms() if at_ms is None else at_ms
    row = ensure_runtime(conn, user_id, at_ms)
    sync_row = _sync_row(conn, user_id)
    return {
        "serverNowMs": int(at_ms),
        "runtime": runtime_view(row),
        "lastSession": _last_settled_session(conn, user_id),
        "lastPenalty": _last_penalty(conn, user_id),
        "syncVersion": int(sync_row["sync_version"] or 0) if sync_row else 0,
    }


# --------------------------------------------------------------------------
# transitions
# --------------------------------------------------------------------------


def _next_phase(phase: str, completed_sessions: int, config: dict) -> str:
    if phase != PHASE_FOCUS:
        return PHASE_FOCUS
    per_long = _as_int(config.get("sessionsPerLongBreak"), default=4) or 4
    if completed_sessions > 0 and completed_sessions % per_long == 0:
        return PHASE_LONG_BREAK
    return PHASE_SHORT_BREAK


def _persist_runtime(conn, user_id: str, row, *, expected_revision: int, **fields) -> None:
    """Conditional update: refuse to move a runtime that is not the expected one."""
    assignments = ", ".join(f"{key}=?" for key in fields)
    values = list(fields.values())
    cursor = conn.execute(
        f"UPDATE focus_runtime SET {assignments}, updated_at_ms=? "
        "WHERE user_id=? AND revision=?",
        (*values, now_ms(), user_id, expected_revision),
    )
    if cursor.rowcount != 1:  # pragma: no cover - guarded by BEGIN IMMEDIATE
        raise FocusRuntimeConflict("runtime changed concurrently")


def _rotate_after_phase(conn, user_id: str, row, *, end_ms: int, duration_ms: int):
    """Settle the current phase once, then advance to the next configured one."""
    session = _write_settlement(conn, user_id, row, end_ms, duration_ms)
    config = _config_dict(row)
    phase = row["phase"]
    completed = int(row["completed_sessions"] or 0) + (1 if phase == PHASE_FOCUS else 0)
    next_phase = _next_phase(phase, completed, config)
    auto_start = _as_bool(
        config.get("autoStartBreaks" if phase == PHASE_FOCUS else "autoStartFocus"),
        False,
    )
    revision = int(row["revision"] or 0) + 1
    anchor = int(end_ms) if auto_start else None
    _persist_runtime(
        conn,
        user_id,
        row,
        expected_revision=int(row["revision"] or 0),
        session_id=_new_id(),
        revision=revision,
        status=STATUS_RUNNING if auto_start else STATUS_IDLE,
        mode=MODE_COUNTDOWN,
        phase=next_phase,
        duration_ms=_phase_duration_ms(config, next_phase),
        elapsed_ms=0,
        anchor_at_ms=anchor,
        started_at_ms=anchor,
        completed_sessions=completed,
    )
    return session


def advance_due(conn, user_id: str, at_ms: Optional[int] = None, max_steps: int = MAX_ADVANCE_STEPS) -> bool:
    """Settle naturally expired phases in a bounded batch.

    Leftover due work stays due for the next call instead of looping forever or
    accumulating invented sessions.
    """
    at_ms = now_ms() if at_ms is None else int(at_ms)
    row = ensure_runtime(conn, user_id, at_ms)
    changed = False
    for _ in range(max(1, int(max_steps))):
        if not is_due(row, at_ms):
            break
        deadline = _deadline_ms(row) or at_ms
        _rotate_after_phase(
            conn,
            user_id,
            row,
            end_ms=deadline,
            duration_ms=int(row["duration_ms"] or 0),
        )
        row = fetch_runtime(conn, user_id)
        changed = True
    return changed


# --------------------------------------------------------------------------
# commands
# --------------------------------------------------------------------------


def _command_digest(
    command_id: str,
    action: str,
    device_id: str,
    session_id: str,
    expected_revision: int,
    payload: dict,
) -> str:
    material = {
        "commandId": command_id,
        "action": action,
        "deviceId": device_id,
        "sessionId": session_id,
        "expectedRevision": expected_revision,
        "payload": payload,
    }
    encoded = json.dumps(
        material, sort_keys=True, ensure_ascii=False, separators=(",", ":")
    )
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def _task_updates(payload: dict) -> dict:
    updates = {}
    for field in TASK_FIELDS:
        if field not in payload:
            continue
        updates[field] = _optional_text(payload.get(field))
    return updates


_TASK_COLUMNS = {
    "taskName": "task_name",
    "todoId": "todo_id",
    "subtaskId": "subtask_id",
    "todoTitle": "todo_title",
    "tag": "tag",
    "focusRoomId": "focus_room_id",
}


def handle_command(conn, user_id: str, command: Any, at_ms: Optional[int] = None) -> dict:
    """Apply one control command atomically and return the resulting snapshot."""
    at_ms = now_ms() if at_ms is None else int(at_ms)
    if not isinstance(command, dict):
        raise FocusRuntimeInvalid("command must be an object")

    command_id = _clean_text(command.get("commandId"), 200)
    action = _clean_text(command.get("action"), 40).lower()
    device_id = _clean_text(command.get("deviceId"), 200)
    session_id = _clean_text(command.get("sessionId"), 200)
    if not command_id:
        raise FocusRuntimeInvalid("commandId is required")
    if action not in ACTIONS:
        raise FocusRuntimeInvalid("unknown action")
    expected_revision = _as_int(command.get("expectedRevision"))
    if expected_revision is None:
        raise FocusRuntimeInvalid("expectedRevision must be an integer")

    raw_payload = command.get("payload")
    if raw_payload is None:
        raw_payload = {}
    if not isinstance(raw_payload, dict):
        raise FocusRuntimeInvalid("payload must be an object")
    # The account identity always comes from the credential, never from the body.
    payload = {
        key: value
        for key, value in raw_payload.items()
        if key not in ("userId", "user_id", "userID")
    }

    digest = _command_digest(
        command_id, action, device_id, session_id, expected_revision, payload
    )
    existing = conn.execute(
        "SELECT payload_digest, result_json FROM focus_commands "
        "WHERE user_id=? AND command_id=?",
        (user_id, command_id),
    ).fetchone()
    if existing is not None:
        # Retries are checked before the version guard: a replay of an accepted
        # command stays idempotent even after later transitions moved revision.
        if existing["payload_digest"] != digest:
            raise FocusRuntimeConflict("command payload mismatch")
        # A retry remains accepted, but return current state and live history.
        # Saved results must never resurrect a deleted session or penalty.
        advance_due(conn, user_id, at_ms)
        return build_envelope(conn, user_id, at_ms)

    # Expired phases are settled before the version guard so a stale pause can
    # never resurrect a finished session.
    advance_due(conn, user_id, at_ms)
    row = fetch_runtime(conn, user_id)
    if row is None:  # pragma: no cover
        raise FocusRuntimeConflict("runtime unavailable")
    if session_id != row["session_id"] or expected_revision != int(row["revision"] or 0):
        raise FocusRuntimeConflict("session or revision mismatch")

    status = row["status"]
    phase = row["phase"]
    mode = row["mode"]
    revision = int(row["revision"] or 0)
    fields: dict[str, Any] = {}
    penalty_reason: Optional[str] = None

    if action == ACTION_START:
        if status != STATUS_IDLE:
            raise FocusRuntimeConflict("start requires idle")
        config = normalize_config(payload.get("config"))
        requested_mode = _clean_text(payload.get("mode"), 20).lower() or MODE_COUNTDOWN
        if requested_mode not in MODES:
            raise FocusRuntimeInvalid("mode must be countdown or countup")
        requested_phase = _clean_text(payload.get("phase"), 20) or phase
        if requested_phase not in PHASES:
            raise FocusRuntimeInvalid("invalid start phase")
        if requested_mode == MODE_COUNTUP and requested_phase != PHASE_FOCUS:
            raise FocusRuntimeInvalid("countup requires the focus phase")
        fields.update(
            session_id=_new_id(),
            revision=revision + 1,
            status=STATUS_RUNNING,
            mode=requested_mode,
            phase=requested_phase,
            duration_ms=0
            if requested_mode == MODE_COUNTUP
            else _phase_duration_ms(config, requested_phase),
            elapsed_ms=0,
            anchor_at_ms=at_ms,
            started_at_ms=at_ms,
            config_json=json.dumps(config, ensure_ascii=False),
        )
        for field, column in _TASK_COLUMNS.items():
            fields[column] = _optional_text(payload.get(field))
        if device_id:
            fields["source_device_id"] = device_id

    elif action == ACTION_PAUSE:
        if status != STATUS_RUNNING:
            raise FocusRuntimeConflict("pause requires running")
        config = _config_dict(row)
        fields.update(
            revision=revision + 1,
            status=STATUS_PAUSED,
            elapsed_ms=_elapsed_at(row, at_ms),
            anchor_at_ms=None,
        )
        if phase == PHASE_FOCUS and _as_bool(config.get("strictFocusMode"), False):
            penalty_reason = "pause"

    elif action == ACTION_RESUME:
        if status != STATUS_PAUSED:
            raise FocusRuntimeConflict("resume requires paused")
        fields.update(
            revision=revision + 1,
            status=STATUS_RUNNING,
            anchor_at_ms=at_ms,
        )

    elif action in (ACTION_STOP, ACTION_RESET):
        config = _config_dict(row)
        fields.update(
            session_id=_new_id(),
            revision=revision + 1,
            status=STATUS_IDLE,
            mode=MODE_COUNTUP if mode == MODE_COUNTUP and phase == PHASE_FOCUS else MODE_COUNTDOWN,
            phase=PHASE_FOCUS,
            duration_ms=0
            if (mode == MODE_COUNTUP and phase == PHASE_FOCUS)
            else _phase_duration_ms(config, PHASE_FOCUS),
            elapsed_ms=0,
            anchor_at_ms=None,
            started_at_ms=None,
            completed_sessions=0,
        )
        if (
            status == STATUS_RUNNING
            and phase == PHASE_FOCUS
            and _as_bool(config.get("strictFocusMode"), False)
        ):
            penalty_reason = "reset"

    elif action == ACTION_SKIP:
        config = _config_dict(row)
        next_phase = PHASE_SHORT_BREAK if phase == PHASE_FOCUS else PHASE_FOCUS
        fields.update(
            session_id=_new_id(),
            revision=revision + 1,
            status=STATUS_IDLE,
            mode=MODE_COUNTDOWN,
            phase=next_phase,
            duration_ms=_phase_duration_ms(config, next_phase),
            elapsed_ms=0,
            anchor_at_ms=None,
            started_at_ms=None,
        )
        if (
            status == STATUS_RUNNING
            and phase == PHASE_FOCUS
            and _as_bool(config.get("strictFocusMode"), False)
        ):
            penalty_reason = "skip"

    elif action == ACTION_FINISH:
        if status not in (STATUS_RUNNING, STATUS_PAUSED):
            raise FocusRuntimeConflict("finish requires an active session")
        if phase != PHASE_FOCUS:
            raise FocusRuntimeConflict("finish requires the focus phase")
        if mode == MODE_COUNTUP:
            duration_ms = max(1000, min(COUNTUP_MAX_MS, _elapsed_at(row, at_ms)))
        else:
            duration_ms = int(row["duration_ms"] or 0)
        # Settles once (guarded by focus_settlements) and rotates the phase.
        _rotate_after_phase(
            conn,
            user_id,
            row,
            end_ms=at_ms,
            duration_ms=duration_ms,
        )

    elif action == ACTION_UPDATE:
        if status == STATUS_IDLE:
            raise FocusRuntimeConflict("update requires an active session")
        updates = _task_updates(payload)
        if not updates:
            raise FocusRuntimeInvalid("update requires a task field")
        fields.update(revision=revision + 1)
        for field, value in updates.items():
            fields[_TASK_COLUMNS[field]] = value

    if fields:
        _persist_runtime(conn, user_id, row, expected_revision=revision, **fields)
    if penalty_reason:
        _write_penalty(conn, user_id, row, penalty_reason, at_ms)
    row = fetch_runtime(conn, user_id)
    if row is None:  # pragma: no cover
        raise FocusRuntimeConflict("runtime unavailable")

    envelope = build_envelope(conn, user_id, at_ms)
    conn.execute(
        "INSERT INTO focus_commands("
        "user_id, command_id, payload_digest, action, revision_after, result_json, "
        "created_at_ms) VALUES(?,?,?,?,?,?,?)",
        (
            user_id,
            command_id,
            digest,
            action,
            int(envelope["runtime"]["revision"]),
            json.dumps(envelope, ensure_ascii=False),
            at_ms,
        ),
    )
    return envelope


# --------------------------------------------------------------------------
# read path used by HTTP/WS (caller decides whether a write transaction is needed)
# --------------------------------------------------------------------------


def read_state(conn, user_id: str, at_ms: Optional[int] = None) -> dict:
    """Snapshot the runtime, persisting the initial idle identity on first use."""
    at_ms = now_ms() if at_ms is None else int(at_ms)
    if fetch_runtime(conn, user_id) is None:
        if conn.in_transaction:
            ensure_runtime(conn, user_id, at_ms)
        else:
            conn.execute("BEGIN IMMEDIATE")
            try:
                ensure_runtime(conn, user_id, at_ms)
                conn.commit()
            except BaseException:
                conn.rollback()
                raise
    return build_envelope(conn, user_id, at_ms)


def probe(conn, user_id: str, at_ms: Optional[int] = None):
    """Cheap (revision, due) probe for the websocket loop."""
    at_ms = now_ms() if at_ms is None else int(at_ms)
    row = fetch_runtime(conn, user_id)
    if row is None:
        return (0, True)
    return (int(row["revision"] or 0), is_due(row, at_ms))


def due_user_ids(conn, at_ms: int, limit: int = 50) -> list[str]:
    rows = conn.execute(
        "SELECT user_id FROM focus_runtime "
        "WHERE status=? AND mode=? AND anchor_at_ms IS NOT NULL "
        "AND anchor_at_ms + (duration_ms - elapsed_ms) <= ? "
        "LIMIT ?",
        (STATUS_RUNNING, MODE_COUNTDOWN, int(at_ms), int(limit)),
    ).fetchall()
    return [row["user_id"] for row in rows]
