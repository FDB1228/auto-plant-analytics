"""Эмуляция «живой» операционной системы завода.

Генератор создаёт полную историю за весь период. Этот модуль собирает из неё
состояние БД на заданную дату (as-of) и применяет его к схеме plant через
UPSERT: новые строки вставляются, изменившиеся - обновляются (updated_at
меняется только у реально изменённых строк). Повторный запуск с более поздней
датой имитирует ежедневную работу системы - на этом проверяется
инкрементальная загрузка DWH и SCD2-снапшоты.

Параллельно в папку landing «доставляются» файлы внешних систем, опубликованные
к этой дате.
"""
from __future__ import annotations

import io
import shutil
from datetime import date, datetime, timedelta
from pathlib import Path

import pandas as pd

from .db import connect

TZ = "Europe/Moscow"

# (таблица, первичный ключ) в порядке зависимостей
TABLES = [
    ("workshops", ["workshop_id"]),
    ("section_types", ["section_type"]),
    ("sections", ["section_id"]),
    ("professions", ["profession_id"]),
    ("management_roles", ["role_code"]),
    ("product_categories", ["category_id"]),
    ("category_attributes", ["attribute_id"]),
    ("product_models", ["model_id"]),
    ("model_attribute_values", ["model_id", "attribute_id"]),
    ("work_types", ["work_type_id"]),
    ("route_steps", ["model_id", "step_no"]),
    ("defect_types", ["defect_type_id"]),
    ("downtime_reasons", ["reason_code"]),
    ("labs", ["lab_id"]),
    ("lab_workshops", ["lab_id", "workshop_id"]),
    ("test_types", ["test_type_id"]),
    ("category_test_plan", ["category_id", "test_type_id"]),
    ("dealers", ["dealer_id"]),
    ("employees", ["employee_id"]),
    ("worker_details", ["employee_id"]),
    ("itr_details", ["employee_id"]),
    ("brigades", ["brigade_id"]),
    ("brigade_memberships", ["membership_id"]),
    ("brigade_leaders", ["leader_period_id"]),
    ("management_assignments", ["assignment_id"]),
    ("equipment", ["equipment_id"]),
    ("lab_staff", ["lab_staff_id"]),
    ("section_downtimes", ["downtime_id"]),
    ("units", ["unit_id"]),
    ("operations", ["operation_id"]),
    ("tests", ["test_id"]),
    ("test_equipment", ["test_id", "equipment_id"]),
    ("defects", ["defect_id"]),
    ("shipments", ["shipment_id"]),
]

IDENTITY = {
    "workshops": "workshop_id", "sections": "section_id", "professions": "profession_id",
    "product_categories": "category_id", "category_attributes": "attribute_id", "product_models": "model_id",
    "work_types": "work_type_id", "defect_types": "defect_type_id", "labs": "lab_id", "test_types": "test_type_id",
    "dealers": "dealer_id", "employees": "employee_id", "brigades": "brigade_id",
    "brigade_memberships": "membership_id", "brigade_leaders": "leader_period_id",
    "management_assignments": "assignment_id", "equipment": "equipment_id", "lab_staff": "lab_staff_id",
    "section_downtimes": "downtime_id", "units": "unit_id", "operations": "operation_id", "tests": "test_id",
    "defects": "defect_id", "shipments": "shipment_id",
}


def _read(gen: Path, name: str) -> pd.DataFrame:
    return pd.read_parquet(gen / "tables" / f"{name}.parquet")


def _known(series: pd.Series, cutoff: date) -> pd.Series:
    """Дата окончания периода известна системе, только если она уже наступила."""
    s = pd.to_datetime(series)
    return s.where(s <= pd.Timestamp(cutoff)).dt.date


def build_state(gen: Path, cutoff: date) -> dict[str, pd.DataFrame]:
    limit = pd.Timestamp(cutoff + timedelta(days=1))
    cut = pd.Timestamp(cutoff)
    st: dict[str, pd.DataFrame] = {}
    for name in ["workshops", "section_types", "sections", "professions", "management_roles",
                 "product_categories", "category_attributes", "product_models", "model_attribute_values",
                 "work_types", "route_steps", "defect_types", "downtime_reasons", "labs", "lab_workshops",
                 "test_types", "category_test_plan", "dealers"]:
        st[name] = _read(gen, name)

    emp = _read(gen, "employees")
    emp = emp[pd.to_datetime(emp["hire_date"]) <= cut].copy()
    emp["termination_date"] = _known(emp["termination_date"], cutoff)
    st["employees"] = emp

    gr = _read(gen, "truth_worker_grades")
    gr = gr[(pd.to_datetime(gr["valid_from"]) <= cut) & gr["employee_id"].isin(emp["employee_id"])]
    st["worker_details"] = (gr.sort_values("valid_from").groupby("employee_id").tail(1)
                            [["employee_id", "skill_grade"]])
    itr = _read(gen, "itr_details")
    st["itr_details"] = itr[itr["employee_id"].isin(emp["employee_id"])]

    br = _read(gen, "brigades")
    br = br[pd.to_datetime(br["formed_date"]) <= cut].copy()
    br["disbanded_date"] = _known(br["disbanded_date"], cutoff)
    st["brigades"] = br

    for name in ["brigade_memberships", "brigade_leaders", "management_assignments", "lab_staff"]:
        df = _read(gen, name)
        df = df[pd.to_datetime(df["valid_from"]) <= cut].copy()
        df["valid_to"] = _known(df["valid_to"], cutoff)
        st[name] = df

    eq = _read(gen, "equipment")
    eq = eq[pd.to_datetime(eq["commissioned_date"]) <= cut].copy()
    eq["decommissioned_date"] = _known(eq["decommissioned_date"], cutoff)
    st["equipment"] = eq

    dt = _read(gen, "section_downtimes")
    st["section_downtimes"] = dt[dt["ended_at"] < limit]

    u = _read(gen, "truth_units")
    sh = _read(gen, "truth_shipments")
    u = u[u["started_at"] < limit].copy()
    u["assembled_at"] = u["assembled_at"].where(u["assembled_at"] < limit)
    u["accepted_at"] = u["accepted_at"].where(u["accepted_at"] < limit)
    shipped = set(sh.loc[sh["shipped_at"] < limit, "unit_id"])
    u["status"] = "in_progress"
    u.loc[u["assembled_at"].notna(), "status"] = "testing"
    u.loc[u["accepted_at"].notna(), "status"] = "accepted"
    u.loc[u["unit_id"].isin(shipped), "status"] = "shipped"
    st["units"] = u

    ops = _read(gen, "truth_operations")
    st["operations"] = ops[ops["finished_at"] < limit]
    tests = _read(gen, "truth_tests")
    tests = tests[tests["finished_at"] < limit]
    st["tests"] = tests
    te = _read(gen, "truth_test_equipment")
    st["test_equipment"] = te[te["test_id"].isin(tests["test_id"])]
    de = _read(gen, "truth_defects")
    st["defects"] = de[de["detected_at"] < limit]
    st["shipments"] = sh[sh["shipped_at"] < limit]
    return st


def _copy_frame(df: pd.DataFrame) -> pd.DataFrame:
    out = df.copy()
    for c in out.columns:
        s = out[c]
        if pd.api.types.is_datetime64_any_dtype(s):
            out[c] = s.dt.tz_localize(TZ).dt.strftime("%Y-%m-%d %H:%M:%S%z")
        elif pd.api.types.is_float_dtype(s) and s.dropna().apply(float.is_integer).all() and c not in (
                "value_num", "std_minutes", "rework_minutes", "list_price_rub", "std_cost_rub", "price_rub"):
            out[c] = s.astype("Int64")
    return out


def upsert(conn, table: str, pk: list[str], df: pd.DataFrame) -> tuple[int, int]:
    cols = list(df.columns)
    buf = io.StringIO()
    _copy_frame(df).to_csv(buf, index=False, header=False, na_rep="")
    buf.seek(0)
    collist = ", ".join(cols)
    non_pk = [c for c in cols if c not in pk]
    with conn.cursor() as cur:
        cur.execute(f"CREATE TEMP TABLE _stage (LIKE plant.{table} INCLUDING DEFAULTS) ON COMMIT DROP")
        with cur.copy(f"COPY _stage ({collist}) FROM STDIN (FORMAT csv, NULL '')") as cp:
            cp.write(buf.read())
        if non_pk:
            sets = ", ".join(f"{c} = EXCLUDED.{c}" for c in non_pk)
            changed = " OR ".join(f"t.{c} IS DISTINCT FROM EXCLUDED.{c}" for c in non_pk)
            conflict = f"DO UPDATE SET {sets} WHERE {changed}"
        else:
            conflict = "DO NOTHING"
        cur.execute(f"""
            WITH ins AS (
                INSERT INTO plant.{table} AS t ({collist})
                SELECT {collist} FROM _stage ORDER BY {", ".join(pk)}
                ON CONFLICT ({", ".join(pk)}) {conflict}
                RETURNING (xmax = 0) AS inserted
            )
            SELECT count(*) FILTER (WHERE inserted), count(*) FILTER (WHERE NOT inserted) FROM ins""")
        ins, upd = cur.fetchone()
        cur.execute("DROP TABLE _stage")
    return ins, upd


def deliver_landing(gen: Path, landing: Path, cutoff: date) -> int:
    man = pd.read_csv(gen / "landing_manifest.csv", parse_dates=["publish_date"])
    n = 0
    for r in man[man["publish_date"] <= pd.Timestamp(cutoff)].itertuples():
        dst = landing / r.relative_path
        if not dst.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(gen / "landing" / r.relative_path, dst)
            n += 1
    return n


def load(gen: Path, landing: Path, cutoff: date) -> None:
    state = build_state(gen, cutoff)
    print(f"Состояние операционной системы на {cutoff}:")
    with connect() as conn:
        for table, pk in TABLES:
            ins, upd = upsert(conn, table, pk, state[table])
            if ins or upd:
                print(f"  plant.{table:<24} +{ins:<7} ~{upd}")
        with conn.cursor() as cur:
            for table, col in IDENTITY.items():
                cur.execute(f"SELECT setval(pg_get_serial_sequence('plant.{table}', '{col}'), "
                            f"coalesce((SELECT max({col}) FROM plant.{table}), 0) + 1, false)")
        conn.commit()
    n = deliver_landing(gen, landing, cutoff)
    print(f"  новых файлов внешних систем в landing: {n}")
