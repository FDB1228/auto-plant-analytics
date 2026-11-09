"""Оркестратор пайплайна (локальный аналог DAG).

    python -m pipeline.run init-db --reset          создать схемы plant и raw
    python -m pipeline.run load-source --as-of D    состояние операционной БД на дату D + файлы в landing
    python -m pipeline.run ingest                   landing -> raw (идемпотентно)
    python -m pipeline.run transform                dbt build: модели + тесты качества данных
    python -m pipeline.run export-bi                витрины -> CSV для DataLens / Power BI
    python -m pipeline.run daily --as-of D          load-source + ingest + transform
    python -m pipeline.run demo                     полный прогон в два «дня»: 2026-06-30 и 2026-09-30
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import time
from datetime import date

from .db import ROOT, connect, run_sql_file
from .export_bi import export_bi
from .ingest import ingest
from .source_loader import load

GEN = ROOT / "data" / "generated"
LANDING = ROOT / "data" / "landing"
DWH = ROOT / "dwh"


def init_db(reset: bool) -> None:
    with connect() as conn:
        with conn.cursor() as cur:
            if reset:
                for schema in ("plant", "raw", "staging", "intermediate", "marts", "snapshots", "dq"):
                    cur.execute(f"DROP SCHEMA IF EXISTS {schema} CASCADE")
            cur.execute("SELECT current_database()")
            cur.execute(f"ALTER DATABASE {cur.fetchone()[0]} SET timezone TO 'Europe/Moscow'")
            cur.execute("SELECT to_regclass('plant.units') IS NOT NULL")
            exists = cur.fetchone()[0]
        if not exists:
            run_sql_file(conn, ROOT / "sql" / "oltp" / "01_schema.sql")
            run_sql_file(conn, ROOT / "sql" / "oltp" / "02_functions_triggers.sql")
        run_sql_file(conn, ROOT / "sql" / "raw" / "01_raw_schema.sql")
        conn.commit()
    if reset and LANDING.exists():
        shutil.rmtree(LANDING)
    print("Схемы plant и raw готовы")


def transform(extra: list[str] | None = None) -> None:
    cmd = ["dbt", "build", "--project-dir", str(DWH), "--profiles-dir", str(DWH)] + (extra or [])
    print("$", " ".join(cmd))
    res = subprocess.run(cmd, cwd=DWH)
    if res.returncode != 0:
        sys.exit(res.returncode)


def daily(as_of: date) -> None:
    t0 = time.time()
    load(GEN, LANDING, as_of)
    ingest(LANDING)
    transform()
    print(f"Прогон на {as_of} завершён за {time.time() - t0:.0f} с")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("init-db")
    p.add_argument("--reset", action="store_true")
    for name in ("load-source", "daily"):
        p = sub.add_parser(name)
        p.add_argument("--as-of", type=date.fromisoformat, required=True)
    sub.add_parser("ingest")
    p = sub.add_parser("transform")
    p.add_argument("dbt_args", nargs=argparse.REMAINDER)
    sub.add_parser("export-bi")
    sub.add_parser("demo")
    a = ap.parse_args()

    if a.cmd == "init-db":
        init_db(a.reset)
    elif a.cmd == "load-source":
        load(GEN, LANDING, a.as_of)
    elif a.cmd == "ingest":
        ingest(LANDING)
    elif a.cmd == "transform":
        transform(a.dbt_args)
    elif a.cmd == "export-bi":
        export_bi(ROOT / "bi" / "exports")
    elif a.cmd == "daily":
        daily(a.as_of)
    elif a.cmd == "demo":
        init_db(reset=True)
        daily(date(2026, 6, 30))
        daily(date(2026, 9, 30))
        export_bi(ROOT / "bi" / "exports")


if __name__ == "__main__":
    main()
