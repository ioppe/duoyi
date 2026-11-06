"""Boundary tests for :mod:`login_session_store` (standard library only).

These tests build the real ``login_sessions`` shapes in a throw-away SQLite
database and drive the migration through the same connection settings the
backend uses (``row_factory = sqlite3.Row``, ``PRAGMA foreign_keys = ON``,
explicit ``BEGIN IMMEDIATE``).  ``main``/FastAPI are deliberately not imported.
"""

import sqlite3
import unittest

import login_session_store as store

USERS_SCHEMA = """
CREATE TABLE users (
    id TEXT PRIMARY KEY,
    username TEXT NOT NULL
);
"""

LEGACY_SCHEMA = (
    USERS_SCHEMA
    + """
CREATE TABLE login_sessions (
    user_id TEXT PRIMARY KEY,
    token_hash TEXT UNIQUE NOT NULL,
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    last_used_at TEXT,
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX idx_login_sessions_expires ON login_sessions(expires_at);
"""
)

SESSION_SCHEMA = (
    USERS_SCHEMA
    + """
CREATE TABLE login_sessions (
    user_id TEXT NOT NULL,
    token_hash TEXT PRIMARY KEY,
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    last_used_at TEXT,
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX idx_login_sessions_expires ON login_sessions(expires_at);
CREATE INDEX idx_login_sessions_user ON login_sessions(user_id);
"""
)

# Two legacy rows, one per account: distinct digests, instants and a NULL
# last_used_at, so a rewrite that recomputes either column is visible.
LEGACY_ROWS = (
    (
        "user-1",
        "a" * 64,
        "2026-01-05T08:00:00Z",
        "2026-02-04T08:00:00Z",
        "2026-01-06T09:30:00Z",
    ),
    (
        "user-2",
        "b" * 64,
        "2026-01-07T10:15:00Z",
        "2026-02-06T10:15:00Z",
        None,
    ),
)

SESSION_COLUMNS = (
    "user_id",
    "token_hash",
    "created_at",
    "expires_at",
    "last_used_at",
)


class LoginSessionStoreTest(unittest.TestCase):
    schema = LEGACY_SCHEMA

    def setUp(self):
        self.conn = _connect(self.schema)
        self.addCleanup(self.conn.close)

    # helpers ---------------------------------------------------------------

    def _primary_key(self):
        return _primary_key(self.conn)

    def _index_names(self):
        return _index_names(self.conn)

    def _index_columns(self, name):
        return [
            row["name"]
            for row in self.conn.execute(f"PRAGMA index_info({name})").fetchall()
        ]

    def _rows(self):
        return _session_rows(self.conn)

    def _staging_exists(self):
        return _table_exists(self.conn, store.STAGING_TABLE)

    def _begin(self):
        self.conn.execute("BEGIN IMMEDIATE")

    def _seed(self, rows=LEGACY_ROWS):
        for user_id in sorted({row[0] for row in rows}):
            self.conn.execute(
                "INSERT INTO users(id, username) VALUES(?,?)", (user_id, user_id)
            )
        for row in rows:
            self.conn.execute(
                f"INSERT INTO login_sessions({', '.join(SESSION_COLUMNS)}) "
                f"VALUES(?,?,?,?,?)",
                row,
            )
        # Leave the connection outside a transaction so tests can BEGIN explicitly.
        self.conn.commit()

    def _insert_session(self, user_id, token_hash, expires_at="2026-03-01T00:00:00Z"):
        self.conn.execute(
            f"INSERT INTO login_sessions({', '.join(SESSION_COLUMNS)}) "
            f"VALUES(?,?,?,?,NULL)",
            (user_id, token_hash, "2026-02-01T00:00:00Z", expires_at),
        )
        self.conn.commit()


class LegacyMigrationTest(LoginSessionStoreTest):
    def test_legacy_table_is_rewritten_and_sessions_survive_verbatim(self):
        self._seed()
        self._begin()

        self.assertTrue(store.migrate_login_sessions(self.conn))
        # The helper owns no commit: the caller's transaction is still open.
        self.assertTrue(self.conn.in_transaction)
        self.conn.commit()

        self.assertEqual(self._primary_key(), ["token_hash"])
        self.assertEqual(self._rows(), sorted(LEGACY_ROWS))
        self.assertFalse(self._staging_exists())

        # One account may now hold several devices/tokens at once.
        self._insert_session("user-1", "c" * 64)
        self._insert_session("user-1", "d" * 64)
        user_one = [row for row in self._rows() if row[0] == "user-1"]
        self.assertEqual(len(user_one), 3)
        self.assertEqual(
            {row[1] for row in user_one}, {"a" * 64, "c" * 64, "d" * 64}
        )
        self.assertEqual(len(self._rows()), 4)

    def test_expiry_and_digests_are_not_recomputed(self):
        self._seed()
        self._begin()
        store.migrate_login_sessions(self.conn)
        self.conn.commit()

        stored = {row[1]: row for row in self._rows()}
        self.assertEqual(stored["a" * 64][2], "2026-01-05T08:00:00Z")
        self.assertEqual(stored["a" * 64][3], "2026-02-04T08:00:00Z")
        self.assertEqual(stored["a" * 64][4], "2026-01-06T09:30:00Z")
        self.assertEqual(stored["b" * 64][3], "2026-02-06T10:15:00Z")
        self.assertIsNone(stored["b" * 64][4])

    def test_multiple_accounts_are_preserved(self):
        rows = tuple(
            (
                f"user-{index}",
                f"{index:x}" * 64,
                f"2026-01-0{index}T00:00:00Z",
                f"2026-02-0{index}T00:00:00Z",
                None,
            )
            for index in range(1, 5)
        )
        self._seed(rows)
        self._begin()
        self.assertTrue(store.migrate_login_sessions(self.conn))
        self.conn.commit()

        self.assertEqual(self._rows(), sorted(rows))
        for index in range(1, 5):
            count = self.conn.execute(
                "SELECT COUNT(*) FROM login_sessions WHERE user_id=?",
                (f"user-{index}",),
            ).fetchone()[0]
            self.assertEqual(count, 1)

    def test_indexes_are_rebuilt_for_expiry_and_owner(self):
        self._seed()
        self._begin()
        store.migrate_login_sessions(self.conn)
        self.conn.commit()

        names = self._index_names()
        self.assertIn(store.EXPIRES_INDEX, names)
        self.assertIn(store.USER_INDEX, names)
        self.assertEqual(self._index_columns(store.EXPIRES_INDEX), ["expires_at"])
        self.assertEqual(self._index_columns(store.USER_INDEX), ["user_id"])

    def test_foreign_key_cascade_is_kept(self):
        self._seed()
        self._begin()
        store.migrate_login_sessions(self.conn)
        self.conn.commit()

        targets = [
            (row["table"], row["on_delete"])
            for row in self.conn.execute(
                "PRAGMA foreign_key_list(login_sessions)"
            ).fetchall()
        ]
        self.assertEqual(targets, [("users", "CASCADE")])

    def test_rollback_restores_the_legacy_table_and_every_row(self):
        self._seed()
        before = self._rows()
        self._begin()

        self.assertTrue(store.migrate_login_sessions(self.conn))
        self.assertEqual(self._primary_key(), ["token_hash"])
        # A plain INSERT inside the transaction: _insert_session() would commit.
        self.conn.execute(
            f"INSERT INTO login_sessions({', '.join(SESSION_COLUMNS)}) "
            "VALUES('user-1', ?, '2026-02-01T00:00:00Z', '2026-03-01T00:00:00Z', NULL)",
            ("e" * 64,),
        )
        self.conn.rollback()

        self.assertFalse(self.conn.in_transaction)
        self.assertEqual(self._primary_key(), ["user_id"])
        self.assertEqual(self._rows(), before)
        self.assertFalse(self._staging_exists())
        self.assertIn(store.EXPIRES_INDEX, self._index_names())

    def test_account_deletion_cascades_every_device_session(self):
        self._seed()
        self._begin()
        store.migrate_login_sessions(self.conn)
        self.conn.commit()
        self._insert_session("user-1", "c" * 64)

        self.conn.execute("DELETE FROM users WHERE id=?", ("user-1",))
        self.conn.commit()

        remaining = self._rows()
        self.assertEqual([row[0] for row in remaining], ["user-2"])
        self.assertEqual(
            self.conn.execute(
                "SELECT COUNT(*) FROM login_sessions WHERE user_id=?",
                ("user-1",),
            ).fetchone()[0],
            0,
        )

    def test_explicit_begin_on_autocommit_connection_is_supported(self):
        # A caller may disable sqlite3's implicit transaction handling and open
        # the write transaction itself; the helper must still work there.
        autocommit = _connect(LEGACY_SCHEMA, isolation_level=None)
        self.addCleanup(autocommit.close)
        autocommit.execute(
            "INSERT INTO users(id, username) VALUES('user-1', 'user-1')"
        )
        autocommit.execute(
            f"INSERT INTO login_sessions({', '.join(SESSION_COLUMNS)}) "
            "VALUES('user-1', ?, '2026-01-05T08:00:00Z', '2026-02-04T08:00:00Z', NULL)",
            ("a" * 64,),
        )
        autocommit.execute("BEGIN IMMEDIATE")

        self.assertTrue(store.migrate_login_sessions(autocommit))
        autocommit.commit()

        self.assertEqual(_primary_key(autocommit), ["token_hash"])
        self.assertEqual(
            _session_rows(autocommit)[0][3], "2026-02-04T08:00:00Z"
        )


class AlreadyMigratedTest(LoginSessionStoreTest):
    schema = SESSION_SCHEMA

    def test_new_schema_is_idempotent_and_untouched(self):
        self._seed(
            (
                ("user-1", "a" * 64, "2026-01-05T08:00:00Z", "2026-02-04T08:00:00Z", None),
                ("user-1", "c" * 64, "2026-01-06T08:00:00Z", "2026-02-05T08:00:00Z", "2026-01-07T08:00:00Z"),
            )
        )
        before = self._rows()
        self._begin()

        self.assertFalse(store.migrate_login_sessions(self.conn))
        self.assertFalse(store.migrate_login_sessions(self.conn))
        self.conn.commit()

        self.assertEqual(self._rows(), before)
        self.assertEqual(self._primary_key(), ["token_hash"])
        self.assertFalse(self._staging_exists())

    def test_missing_indexes_are_created_without_reporting_a_migration(self):
        self.conn.execute(f"DROP INDEX {store.USER_INDEX}")
        self.conn.execute(
            "INSERT INTO users(id, username) VALUES('user-1', 'user-1')"
        )
        self.conn.commit()
        self._begin()

        self.assertFalse(store.migrate_login_sessions(self.conn))
        self.conn.commit()

        self.assertIn(store.USER_INDEX, self._index_names())
        self.assertIn(store.EXPIRES_INDEX, self._index_names())


class RejectedSchemaTest(LoginSessionStoreTest):

    def _reset(self, script):
        """Swap the legacy table for a deliberately incompatible shape."""
        self.conn.execute("DROP TABLE login_sessions")
        self.conn.executescript(script)
        self.conn.commit()

    def test_migration_requires_the_callers_transaction(self):
        self._seed()
        before = self._rows()
        self.assertFalse(self.conn.in_transaction)

        with self.assertRaises(store.LoginSessionTransactionRequired):
            store.migrate_login_sessions(self.conn)

        self.assertEqual(self._primary_key(), ["user_id"])
        self.assertEqual(self._rows(), before)
        self.assertFalse(self._staging_exists())

        # Same connection, same data: only the missing transaction blocked it.
        self._begin()
        self.assertTrue(store.migrate_login_sessions(self.conn))
        self.conn.commit()
        self.assertEqual(self._primary_key(), ["token_hash"])

    def test_unknown_primary_key_is_rejected(self):
        self._reset(
            """
CREATE TABLE login_sessions (
    session_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    token_hash TEXT NOT NULL,
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    last_used_at TEXT
);
"""
        )
        self.conn.execute("INSERT INTO users(id, username) VALUES('user-1','user-1')")
        self.conn.execute(
            "INSERT INTO login_sessions VALUES('s1','user-1',?,?,?,NULL)",
            ("a" * 64, "2026-01-05T08:00:00Z", "2026-02-04T08:00:00Z"),
        )
        self.conn.commit()
        self._begin()

        with self.assertRaises(store.LoginSessionSchemaError):
            store.migrate_login_sessions(self.conn)
        self.conn.commit()

        self.assertEqual(self._primary_key(), ["session_id"])
        stored = self.conn.execute(
            "SELECT user_id, token_hash FROM login_sessions"
        ).fetchall()
        self.assertEqual([tuple(row) for row in stored], [("user-1", "a" * 64)])
        self.assertFalse(self._staging_exists())

    def test_missing_column_is_rejected(self):
        self._reset(
            """
CREATE TABLE login_sessions (
    user_id TEXT PRIMARY KEY,
    token_hash TEXT UNIQUE NOT NULL,
    created_at TEXT NOT NULL,
    last_used_at TEXT
);
"""
        )
        self._begin()

        with self.assertRaises(store.LoginSessionSchemaError):
            store.migrate_login_sessions(self.conn)

        self.assertEqual(self._primary_key(), ["user_id"])
        self.assertFalse(self._staging_exists())

    def test_missing_table_is_rejected(self):
        self._reset("")
        self._begin()

        with self.assertRaises(store.LoginSessionSchemaError):
            store.migrate_login_sessions(self.conn)

    def test_staging_table_collision_is_rejected_and_kept(self):
        self._seed()
        self.conn.executescript(
            f"CREATE TABLE {store.STAGING_TABLE} (marker TEXT);"
        )
        self.conn.execute(
            f"INSERT INTO {store.STAGING_TABLE}(marker) VALUES('leftover')"
        )
        self.conn.commit()
        before = self._rows()
        self._begin()

        with self.assertRaises(store.LoginSessionSchemaError):
            store.migrate_login_sessions(self.conn)
        self.conn.rollback()

        self.assertEqual(
            [
                tuple(row)
                for row in self.conn.execute(
                    f"SELECT marker FROM {store.STAGING_TABLE}"
                ).fetchall()
            ],
            [("leftover",)],
        )
        self.assertEqual(self._primary_key(), ["user_id"])
        self.assertEqual(self._rows(), before)


def _connect(script, isolation_level=""):
    conn = sqlite3.connect(":memory:", isolation_level=isolation_level)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.executescript(script)
    return conn


def _primary_key(conn):
    return [
        row["name"]
        for row in conn.execute("PRAGMA table_info(login_sessions)").fetchall()
        if row["pk"]
    ]


def _index_names(conn):
    return {
        row["name"]
        for row in conn.execute("PRAGMA index_list(login_sessions)").fetchall()
    }


def _table_exists(conn, name):
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)
    ).fetchone()
    return row is not None


def _session_rows(conn):
    rows = conn.execute(
        f"SELECT {', '.join(SESSION_COLUMNS)} FROM login_sessions"
    ).fetchall()
    return sorted(tuple(row) for row in rows)


if __name__ == "__main__":
    unittest.main()
