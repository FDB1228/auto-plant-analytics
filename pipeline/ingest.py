"""Загрузка файлов внешних систем из landing в RAW-слой.

* идемпотентно: каждый файл фиксируется в raw.load_log (имя + sha256),
  повторный запуск не создаёт дублей;
* атомарно: строки файла и запись в журнале - в одной транзакции;
* без интерпретации: значения сохраняются как текст, разбор - в dbt staging.
"""
from __future__ import annotations

import csv
import hashlib
import io
import json
from pathlib import Path

from .db import connect

PLAN_COLUMNS = {
    "Период": "period_raw",
    "Код модели": "model_code",
    "Наименование модели": "model_name",
    "Цех": "workshop_code",
    "План, шт.": "planned_qty_raw",
    "Версия": "plan_version_raw",
    "Дата утверждения": "approved_date_raw",
}
CLAIM_FIELDS = ["claim_id", "vin", "dealer_code", "defect_code", "claim_date", "status", "amount",
                "record_updated_at"]


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _parse_plan(path: Path) -> list[tuple]:
    text = path.read_bytes().decode("cp1251")
    reader = csv.DictReader(io.StringIO(text), delimiter=";")
    missing = set(PLAN_COLUMNS) - set(reader.fieldnames or [])
    if missing:
        raise ValueError(f"{path.name}: нет колонок {missing}")
    return [tuple(row[k] for k in PLAN_COLUMNS) + (path.name, i)
            for i, row in enumerate(reader, start=1)]


def _parse_claims(path: Path) -> list[tuple]:
    doc = json.loads(path.read_text(encoding="utf-8"))
    rows = []
    for i, rec in enumerate(doc.get("claims", []), start=1):
        vals = [None if rec.get(f) is None else str(rec.get(f)) for f in CLAIM_FIELDS]
        rows.append((doc.get("export_id"), *vals, json.dumps(rec, ensure_ascii=False), path.name, i))
    return rows


SOURCES = {
    "erp_plan": dict(
        pattern="erp_plan/*.csv", parser=_parse_plan, table="raw.erp_production_plan",
        columns=list(PLAN_COLUMNS.values()) + ["_source_file", "_row_number"]),
    "dealer_claims": dict(
        pattern="dealer_claims/*.json", parser=_parse_claims, table="raw.dealer_warranty_claims",
        columns=["export_id", "claim_id", "vin", "dealer_code", "defect_code", "claim_date_raw", "status",
                 "amount_raw", "record_updated_at", "payload", "_source_file", "_row_number"]),
}


def ingest(landing: Path) -> None:
    total_files = total_rows = 0
    with connect(autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT file_name, file_sha256 FROM raw.load_log")
            done = dict(cur.fetchall())
        for source, spec in SOURCES.items():
            for path in sorted(landing.glob(spec["pattern"])):
                digest = _sha256(path)
                if path.name in done:
                    if done[path.name] != digest:
                        print(f"  ВНИМАНИЕ: файл {path.name} изменился после загрузки - пропущен, нужна проверка")
                    continue
                rows = spec["parser"](path)
                with conn.transaction(), conn.cursor() as cur:
                    with cur.copy(f"COPY {spec['table']} ({', '.join(spec['columns'])}) FROM STDIN") as cp:
                        for r in rows:
                            cp.write_row(r)
                    cur.execute("INSERT INTO raw.load_log (file_name, source, file_sha256, rows_loaded) "
                                "VALUES (%s, %s, %s, %s)", (path.name, source, digest, len(rows)))
                total_files += 1
                total_rows += len(rows)
    print(f"RAW: загружено файлов {total_files}, строк {total_rows}")
