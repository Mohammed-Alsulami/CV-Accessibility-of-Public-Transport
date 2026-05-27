import sqlite3
import os

DB_PATH = os.path.join(os.path.dirname(__file__), "accessibility.db")


def get_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with get_connection() as conn:
        # Table 1: AI training images (internal — not exposed to frontend)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS training_data (
                id                     INTEGER PRIMARY KEY AUTOINCREMENT,
                image_data             BLOB    NOT NULL,
                has_tactile_flooring   INTEGER NOT NULL CHECK (has_tactile_flooring IN (0, 1)),
                compatibility_percentage REAL,
                created_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Table 2: Images uploaded by the user from the frontend
        conn.execute("""
            CREATE TABLE IF NOT EXISTS user_input_images (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                filename   TEXT    NOT NULL,
                image_data BLOB    NOT NULL,
                uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Table 3: AI analysis results linked to each user input image
        conn.execute("""
            CREATE TABLE IF NOT EXISTS user_image_output (
                id                       INTEGER PRIMARY KEY AUTOINCREMENT,
                input_image_id           INTEGER NOT NULL REFERENCES user_input_images(id),
                output_image_data        BLOB,
                has_tactile_flooring     INTEGER CHECK (has_tactile_flooring IN (0, 1)),
                compatibility_percentage REAL,
                contrast_percentage      REAL,
                compatibility_label      TEXT,
                notes                    TEXT,
                report_pdf               BLOB,
                analyzed_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.commit()

    # Idempotent migration: add columns that may be missing from older DB versions
    _migrate_db()


def _migrate_db():
    conn = sqlite3.connect(DB_PATH)
    try:
        existing = {row[1] for row in conn.execute("PRAGMA table_info(user_image_output)")}
        for column, col_type in [
            ("contrast_percentage", "REAL"),
            ("compatibility_label", "TEXT"),
            ("notes",               "TEXT"),
        ]:
            if column not in existing:
                conn.execute(f"ALTER TABLE user_image_output ADD COLUMN {column} {col_type}")
        conn.commit()
    finally:
        conn.close()


# ── Training data ─────────────────────────────────────────────────────────────

def save_training_image(
    image_data: bytes,
    has_tactile_flooring: int,
    compatibility_percentage: float = None,
) -> int:
    with get_connection() as conn:
        cursor = conn.execute(
            """
            INSERT INTO training_data (image_data, has_tactile_flooring, compatibility_percentage)
            VALUES (?, ?, ?)
            """,
            (image_data, has_tactile_flooring, compatibility_percentage),
        )
        conn.commit()
        return cursor.lastrowid


# ── User input images ─────────────────────────────────────────────────────────

def save_user_input_image(filename: str, image_data: bytes) -> int:
    with get_connection() as conn:
        cursor = conn.execute(
            "INSERT INTO user_input_images (filename, image_data) VALUES (?, ?)",
            (filename, image_data),
        )
        conn.commit()
        return cursor.lastrowid


def get_all_user_inputs():
    with get_connection() as conn:
        rows = conn.execute(
            "SELECT id, filename, uploaded_at FROM user_input_images ORDER BY uploaded_at DESC"
        ).fetchall()
        return [dict(row) for row in rows]


# ── Analysis output ───────────────────────────────────────────────────────────

def save_analysis_output(
    input_image_id: int,
    output_image_data: bytes = None,
    has_tactile_flooring: int = None,
    compatibility_percentage: float = None,
    contrast_percentage: float = None,
    compatibility_label: str = None,
    notes: str = None,
    report_pdf: bytes = None,
) -> int:
    with get_connection() as conn:
        cursor = conn.execute(
            """
            INSERT INTO user_image_output
                (input_image_id, output_image_data, has_tactile_flooring,
                 compatibility_percentage, contrast_percentage,
                 compatibility_label, notes, report_pdf)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (input_image_id, output_image_data, has_tactile_flooring,
             compatibility_percentage, contrast_percentage,
             compatibility_label, notes, report_pdf),
        )
        conn.commit()
        return cursor.lastrowid


def get_output_by_id(output_id: int):
    with get_connection() as conn:
        row = conn.execute("""
            SELECT
                o.id,
                o.input_image_id,
                i.filename,
                i.image_data        AS input_image_data,
                o.output_image_data,
                o.has_tactile_flooring,
                o.compatibility_percentage,
                o.contrast_percentage,
                o.compatibility_label,
                o.notes,
                o.report_pdf,
                o.analyzed_at
            FROM user_image_output o
            JOIN user_input_images i ON i.id = o.input_image_id
            WHERE o.id = ?
        """, (output_id,)).fetchone()
        return dict(row) if row else None


def clear_db():
    with get_connection() as conn:
        conn.execute("DELETE FROM user_image_output")
        conn.execute("DELETE FROM user_input_images")
        conn.commit()


def get_all_outputs():
    with get_connection() as conn:
        rows = conn.execute("""
            SELECT
                o.id,
                o.input_image_id,
                i.filename,
                o.has_tactile_flooring,
                o.compatibility_percentage,
                o.contrast_percentage,
                o.compatibility_label,
                o.analyzed_at
            FROM user_image_output o
            JOIN user_input_images i ON i.id = o.input_image_id
            ORDER BY o.analyzed_at DESC
        """).fetchall()
        return [dict(row) for row in rows]
