"""Выгрузка витрин в CSV для BI.

Power BI подключается к PostgreSQL напрямую; DataLens (облачный сервис)
до локальной базы не дотянется, поэтому для него витрины выгружаются в CSV
и загружаются через подключение «Файлы». Те же CSV подходят и для Power BI
без установленного PostgreSQL.
"""
from __future__ import annotations

from pathlib import Path

from .db import connect

EXPORTS = [
    "dim_date", "dim_workshop", "dim_model", "dim_section", "dim_brigade", "dim_lab", "dim_dealer", "dim_defect_type",
    "fct_units", "fct_defects", "fct_warranty_claims", "fct_production_plan",
    "mart_daily_workshop_kpi", "mart_quality_brigade_month", "mart_copq_monthly",
    "mart_welding_pilot", "mart_warranty_cohorts", "mart_downtime_monthly",
]


def export_bi(out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    with connect() as conn, conn.cursor() as cur:
        for name in EXPORTS:
            path = out / f"{name}.csv"
            with path.open("wb") as f:
                # UTF-8 с BOM: корректно открывается в Excel и Power BI, принимается DataLens
                f.write("﻿".encode("utf-8"))
                with cur.copy(f"COPY (SELECT * FROM marts.{name}) TO STDOUT WITH (FORMAT csv, HEADER true)") as cp:
                    for chunk in cp:
                        f.write(chunk)
            print(f"  {path.relative_to(out.parent.parent)}  {path.stat().st_size / 1024:,.0f} КБ")
