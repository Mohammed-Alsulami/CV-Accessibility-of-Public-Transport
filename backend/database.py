import sqlite3
import os

DB_PATH = os.path.join(os.path.dirname(__file__), "accessibility.db")


def get_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with get_connection() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS analyses (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                filename  TEXT    NOT NULL,
                status    TEXT    NOT NULL,
                ramp      TEXT,
                stairs    TEXT,
                pathway   TEXT,
                signage   TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.commit()


def save_analysis(filename: str, status: str, features: dict):
    with get_connection() as conn:
        conn.execute(
            """
            INSERT INTO analyses (filename, status, ramp, stairs, pathway, signage)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                filename,
                status,
                features.get("ramp"),
                features.get("stairs"),
                features.get("pathway"),
                features.get("signage"),
            ),
        )
        conn.commit()


def get_all_analyses():
    with get_connection() as conn:
        rows = conn.execute(
            "SELECT * FROM analyses ORDER BY created_at DESC"
        ).fetchall()
        return [dict(row) for row in rows]
