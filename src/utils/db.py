import os
import psycopg2
import psycopg2.extras
from contextlib import contextmanager
from src.utils.logger import get_logger

logger = get_logger(__name__)


def get_connection_params() -> dict:
    return {
        "host": os.getenv("POSTGRES_HOST", "postgres"),
        "port": int(os.getenv("POSTGRES_PORT", 5432)),
        "dbname": os.getenv("PIPELINE_DB_NAME", "retail_pipeline"),
        "user": os.getenv("POSTGRES_USER", "retail_user"),
        "password": os.getenv("POSTGRES_PASSWORD", "retail_password"),
    }


@contextmanager
def get_connection():
    """Context manager that yields a psycopg2 connection and auto-commits or rolls back."""
    conn = None
    try:
        conn = psycopg2.connect(**get_connection_params())
        yield conn
        conn.commit()
    except Exception as e:
        if conn:
            conn.rollback()
        logger.error(f"Database error: {e}")
        raise
    finally:
        if conn:
            conn.close()


@contextmanager
def get_cursor(cursor_factory=psycopg2.extras.RealDictCursor):
    """Context manager that yields a cursor from a managed connection."""
    with get_connection() as conn:
        cursor = conn.cursor(cursor_factory=cursor_factory)
        try:
            yield cursor
        finally:
            cursor.close()


def execute_many(sql: str, records: list[tuple]) -> int:
    """Bulk insert records using executemany. Returns row count."""
    with get_connection() as conn:
        with conn.cursor() as cur:
            psycopg2.extras.execute_values(cur, sql, records, page_size=500)
            return cur.rowcount


def check_health() -> bool:
    """Quick connectivity check. Returns True if DB is reachable."""
    try:
        with get_cursor() as cur:
            cur.execute("SELECT 1")
        logger.info("✅ Database health check passed")
        return True
    except Exception as e:
        logger.error(f"❌ Database health check failed: {e}")
        return False
