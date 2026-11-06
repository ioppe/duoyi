"""Transactional rewrite of ``login_sessions`` for multi-device sessions.

``login_sessions`` used to hold one row per account (``user_id`` PRIMARY KEY,
``token_hash`` UNIQUE), which made every new login replace the previous device.
Multi-device support needs one row per issued token instead (``token_hash``
PRIMARY KEY, ``user_id`` indexed so the account-wide lookups still work).

:func:`migrate_login_sessions` performs that rewrite with plain
``Connection.execute`` calls: it never commits, never rolls back and never uses
``executescript`` (which would commit the caller's transaction first).  Like
``focus_runtime``, the module never opens its own connection -- callers pass a
connection that is already inside the ``BEGIN IMMEDIATE`` block of
``init_db``, and they own commit/rollback and the surrounding write lock.

Only stored digests, timestamps and the owning ``user_id`` are copied verbatim:
the migration never derives raw tokens, never touches passwords, and never
recomputes ``expires_at``, so existing sessions keep their original deadlines.
An unrecognised table shape raises instead of being rewritten silently.
"""

from __future__ import annotations

import sqlite3

__all__ = [
    "EXPIRES_INDEX",
    "LoginSessionSchemaError",
    "LoginSessionTransactionRequired",
    "STAGING_TABLE",
    "TABLE",
    "USER_INDEX",
    "migrate_login_sessions",
]

TABLE = "login_sessions"
# Fixed, single-use staging name: a leftover table with this name means an
# earlier attempt failed outside this module's control, so refuse to clobber it.
STAGING_TABLE = "login_sessions_migration"
EXPIRES_INDEX = "idx_login_sessions_expires"
USER_INDEX = "idx_login_sessions_user"

_LEGACY_PRIMARY_KEY = "user_id"
_SESSION_PRIMARY_KEY = "token_hash"
_REQUIRED_COLUMNS = ("user_id", "token_hash", "created_at", "expires_at")
_SESSION_COLUMNS = ("user_id", "token_hash", "created_at", "expires_at", "last_used_at")


class LoginSessionSchemaError(RuntimeError):
    """``login_sessions`` is missing or in a shape this module must not rewrite."""


class LoginSessionTransactionRequired(RuntimeError):
    """The caller opened no write transaction, so the migration cannot be atomic."""


def migrate_login_sessions(conn: sqlite3.Connection) -> bool:
    """Rewrite ``login_sessions`` to one row per token inside the caller's transaction.

    Returns ``True`` when the legacy ``user_id``-keyed table was rewritten, and
    ``False`` when the table was already keyed by ``token_hash`` (only missing
    indexes are ensured then).  The caller must already hold the write
    transaction; this function neither commits nor rolls back.
    """
    if not conn.in_transaction:
        raise LoginSessionTransactionRequired(
            "migrate_login_sessions() requires the caller's write transaction"
        )

    columns = _table_columns(conn)
    missing = [name for name in _REQUIRED_COLUMNS if name not in columns]
    if missing:
        raise LoginSessionSchemaError(
            f"{TABLE} is missing required columns: {', '.join(missing)}"
        )
    primary_key = sorted(
        (position, name) for name, (_, position) in columns.items() if position
    )
    if primary_key == [(1, _SESSION_PRIMARY_KEY)]:
        _ensure_indexes(conn)
        return False
    if primary_key != [(1, _LEGACY_PRIMARY_KEY)]:
        described = ", ".join(name for _, name in primary_key) or "no primary key"
        raise LoginSessionSchemaError(
            f"{TABLE} has an unexpected primary key ({described})"
        )

    if _table_exists(conn, STAGING_TABLE):
        raise LoginSessionSchemaError(
            f"temporary table {STAGING_TABLE} already exists; refusing to overwrite it"
        )

    conn.execute(
        f"""
        CREATE TABLE {STAGING_TABLE} (
            user_id TEXT NOT NULL,
            token_hash TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            last_used_at TEXT,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        )
        """
    )
    # Copy every legacy row as-is: digests, creation/expiry instants and the
    # optional last_used_at stay byte-identical, so no session is extended.
    conn.execute(
        f"INSERT INTO {STAGING_TABLE}({', '.join(_SESSION_COLUMNS)}) "
        f"SELECT {', '.join(_SESSION_COLUMNS)} FROM {TABLE}"
    )
    conn.execute(f"DROP TABLE {TABLE}")
    conn.execute(f"ALTER TABLE {STAGING_TABLE} RENAME TO {TABLE}")
    _ensure_indexes(conn)
    return True


def _table_columns(conn: sqlite3.Connection) -> dict[str, tuple[bool, int]]:
    """Map column name -> (NOT NULL, primary-key position) for ``TABLE``."""
    rows = conn.execute(f"PRAGMA table_info({TABLE})").fetchall()
    if not rows:
        raise LoginSessionSchemaError(f"{TABLE} table does not exist")
    return {row[1]: (bool(row[3]), int(row[5])) for row in rows}


def _table_exists(conn: sqlite3.Connection, name: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)
    ).fetchone()
    return row is not None


def _ensure_indexes(conn: sqlite3.Connection) -> None:
    """(Re)create the expiry and owner indexes; DROP TABLE took them with it."""
    conn.execute(
        f"CREATE INDEX IF NOT EXISTS {EXPIRES_INDEX} ON {TABLE}(expires_at)"
    )
    conn.execute(f"CREATE INDEX IF NOT EXISTS {USER_INDEX} ON {TABLE}(user_id)")
