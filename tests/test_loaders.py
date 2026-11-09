"""Проверки без базы данных: состояние на дату и разбор файлов внешних систем."""
import json
from datetime import date
from pathlib import Path

import numpy as np
import pandas as pd

from generator.export import write_dealer_claims, write_erp_plan, write_tables
from pipeline.ingest import _parse_claims, _parse_plan
from pipeline.source_loader import build_state


def _materialize(tmp_path: Path, sim_tables) -> Path:
    tables, plan_files = sim_tables
    write_tables(tables, tmp_path)
    manifest = write_erp_plan(plan_files, tmp_path) + write_dealer_claims(
        tables, tmp_path, np.random.default_rng(0), date(2025, 3, 31))
    pd.DataFrame(manifest).to_csv(tmp_path / "landing_manifest.csv", index=False)
    return tmp_path


def test_as_of_state_has_no_future(tmp_path, sim_tables):
    gen = _materialize(tmp_path, sim_tables)
    cutoff = date(2025, 2, 15)
    st = build_state(gen, cutoff)
    limit = pd.Timestamp("2025-02-16")
    assert (st["operations"]["finished_at"] < limit).all()
    assert (st["tests"]["finished_at"] < limit).all()
    u = st["units"]
    assert u["accepted_at"].dropna().lt(limit).all()
    # незавершённые изделия не имеют даты приёмки
    assert u.loc[u["status"] == "in_progress", "accepted_at"].isna().all()
    # дата увольнения в будущем системе ещё не известна
    assert pd.to_datetime(st["employees"]["termination_date"]).dropna().le(pd.Timestamp(cutoff)).all()
    # все дефекты ссылаются на загруженные операции
    d = st["defects"]
    assert d["origin_operation_id"].dropna().isin(st["operations"]["operation_id"]).all()


def test_parse_erp_plan(tmp_path, sim_tables):
    gen = _materialize(tmp_path, sim_tables)
    f = sorted((gen / "landing" / "erp_plan").glob("*.csv"))[0]
    rows = _parse_plan(f)
    assert len(rows) == 14                      # по строке на модель
    assert rows[0][0].count(".") == 2           # дата в формате ДД.ММ.ГГГГ
    assert all(r[-2] == f.name for r in rows)


def test_parse_dealer_claims_keeps_raw_payload(tmp_path, sim_tables):
    gen = _materialize(tmp_path, sim_tables)
    files = sorted((gen / "landing" / "dealer_claims").glob("*.json"))
    if not files:
        return
    rows = _parse_claims(files[0])
    doc = json.loads(files[0].read_text(encoding="utf-8"))
    assert len(rows) == len(doc["claims"])
    assert json.loads(rows[0][9])["claim_id"] == rows[0][1]
