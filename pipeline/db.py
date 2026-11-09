"""Подключение к PostgreSQL. Параметры берутся из переменных окружения (см. .env.example)."""
import os
from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parents[1]


def dsn() -> str:
    return (f"host={os.getenv('PGHOST', 'localhost')} port={os.getenv('PGPORT', '5432')} "
            f"dbname={os.getenv('PGDATABASE', 'plant')} user={os.getenv('PGUSER', 'postgres')} "
            f"password={os.getenv('PGPASSWORD', 'postgres')}")


def sqlalchemy_url() -> str:
    return (f"postgresql+psycopg://{os.getenv('PGUSER', 'postgres')}:{os.getenv('PGPASSWORD', 'postgres')}"
            f"@{os.getenv('PGHOST', 'localhost')}:{os.getenv('PGPORT', '5432')}/{os.getenv('PGDATABASE', 'plant')}")


def connect(autocommit: bool = False) -> psycopg.Connection:
    return psycopg.connect(dsn(), autocommit=autocommit)


def run_sql_file(conn: psycopg.Connection, path: Path):
    with conn.cursor() as cur:
        cur.execute(path.read_text(encoding="utf-8"))
