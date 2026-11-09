"""Сохранение результатов симуляции.

data/generated/tables/*.parquet   - «полная правда» для source_loader
data/generated/landing/...        - выгрузки внешних систем в их «родном» формате:
    erp_plan/plan_YYYY-MM_vN.csv      - план производства из ERP (cp1251, «;»)
    dealer_claims/claims_YYYY-Www.json - гарантийные обращения с дилерского портала
data/generated/landing_manifest.csv - когда каждый файл «появился» (для загрузки на дату)
"""
from __future__ import annotations

import json
from datetime import date, datetime, timedelta
from pathlib import Path

import numpy as np
import pandas as pd

from . import config as C


def _ru_amount(x: float) -> str:
    s = f"{x:,.2f}".replace(",", " ").replace(".", ",")
    return s


def write_tables(tables: dict[str, pd.DataFrame], out: Path):
    (out / "tables").mkdir(parents=True, exist_ok=True)
    for name, df in tables.items():
        df.to_parquet(out / "tables" / f"{name}.parquet", index=False)


def write_erp_plan(plan_files: list[dict], out: Path) -> list[dict]:
    model = {m["id"]: m for m in C.MODELS}
    ws_code = {w[0]: w[1] for w in C.WORKSHOPS}
    folder = out / "landing" / "erp_plan"
    folder.mkdir(parents=True, exist_ok=True)
    manifest = []
    for f in plan_files:
        rows = [{
            "Период": f["month"].strftime("%d.%m.%Y"),
            "Код модели": model[mid]["code"],
            "Наименование модели": model[mid]["name"],
            "Цех": ws_code[model[mid]["ws"]],
            "План, шт.": q,
            "Версия": f["ver"],
            "Дата утверждения": f["publish_date"].strftime("%d.%m.%Y"),
        } for mid, q in f["rows"]]
        name = f"plan_{f['month']:%Y-%m}_v{f['ver']}.csv"
        pd.DataFrame(rows).to_csv(folder / name, sep=";", index=False, encoding="cp1251")
        manifest.append(dict(relative_path=f"erp_plan/{name}", source="erp_plan", publish_date=f["publish_date"]))
    return manifest


def write_dealer_claims(tables: dict[str, pd.DataFrame], out: Path, rng: np.random.Generator,
                        end: date) -> list[dict]:
    claims = tables["truth_warranty_claims"]
    units = tables["truth_units"].set_index("unit_id")
    dealers = tables["dealers"].set_index("dealer_id")
    dtypes = tables["defect_types"].set_index("defect_type_id")
    folder = out / "landing" / "dealer_claims"
    folder.mkdir(parents=True, exist_ok=True)

    events = []   # (event_date, record)
    for c in claims.itertuples():
        vin = units.loc[c.unit_id, "serial_no"]
        if rng.random() < 0.10:
            vin = vin.lower()
        if rng.random() < 0.05:
            vin = f"{vin[:3]} {vin[3:9]} {vin[9:]}"
        base = dict(claim_id=c.claim_id, vin=vin, dealer_code=dealers.loc[c.dealer_id, "code"],
                    defect_code=None if rng.random() < 0.04 else dtypes.loc[c.defect_type_id, "code"])
        requested = c.amount_rub * rng.uniform(1.0, 1.15)

        def fmt_date(d: date) -> str:
            return d.strftime("%d.%m.%Y") if rng.random() < 0.3 else d.isoformat()

        def fmt_amount(x):
            return _ru_amount(x) if rng.random() < 0.4 else round(float(x), 2)

        sub_ts = datetime.combine(c.claim_date, datetime.min.time()) + timedelta(hours=float(rng.uniform(9, 19)))
        events.append((c.claim_date, dict(base, claim_date=fmt_date(c.claim_date), status="submitted",
                                          amount=fmt_amount(requested), record_updated_at=sub_ts.isoformat(timespec="seconds"))))
        if c.decision_date <= end:
            dec_ts = datetime.combine(c.decision_date, datetime.min.time()) + timedelta(hours=float(rng.uniform(9, 19)))
            status = "rejected" if c.rejected else "approved"
            events.append((c.decision_date, dict(base, claim_date=fmt_date(c.claim_date), status=status,
                                                 amount=fmt_amount(0 if c.rejected else c.amount_rub),
                                                 record_updated_at=dec_ts.isoformat(timespec="seconds"))))

    if not events:
        return []
    ev = pd.DataFrame([dict(d=d, rec=r) for d, r in events])
    ev["d"] = pd.to_datetime(ev["d"])
    ev["week_start"] = ev["d"] - pd.to_timedelta(ev["d"].dt.weekday, unit="D")
    manifest = []
    for wk, g in ev.groupby("week_start"):
        recs = list(g["rec"])
        dup = [r for r in recs if rng.random() < 0.02]          # повторная отправка той же записи
        recs = recs + dup
        iso = wk.isocalendar()
        name = f"claims_{iso.year}-W{iso.week:02d}.json"
        publish = (wk + pd.Timedelta(days=7)).date()             # понедельник после недели
        payload = dict(export_id=f"DP-{iso.year}{iso.week:02d}", generated_at=f"{publish}T03:00:00+03:00",
                       period=dict(date_from=str(wk.date()), date_to=str((wk + pd.Timedelta(days=6)).date())),
                       claims=recs)
        (folder / name).write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
        manifest.append(dict(relative_path=f"dealer_claims/{name}", source="dealer_claims", publish_date=publish))
    return manifest


def write_ground_truth(out: Path, tables: dict[str, pd.DataFrame]):
    truth = {
        "A_problem_brigade": dict(section_id=C.PROBLEM_BRIGADE_SECTION, shift="night", since=str(C.PROBLEM_START),
                                  mechanism="текучесть кадров -> доля новичков -> рост дефектов ЛКП"),
        "B_ws2_pilot": dict(start=str(C.WS2_START), pilot=list(C.WS2_PILOT_SECTIONS),
                            control=list(C.WS2_CONTROL_SECTIONS), true_defect_effect=C.WS2_DEFECT_MULT - 1,
                            true_time_effect=C.WS2_TIME_MULT - 1),
        "C_learning_curve": dict(time=C.LEARNING_TIME, defect=C.LEARNING_DEFECT,
                                 new_brigades=[(s, sh, str(f)) for s, sh, f, _ in C.NEW_BRIGADES]),
        "D_month_end_rush": dict(days=C.RUSH_DAYS, volume=C.RUSH_VOLUME_MULT, defect=C.RUSH_DEFECT_MULT),
        "E_old_stand": dict(lab=C.OLD_STAND_LAB, replaced=str(C.OLD_STAND_REPLACED),
                            detection_old=C.OLD_STAND_DETECTION_P, detection_new=C.TEST_DETECTION_P["DYN"]),
        "F_paint_booth": {k: str(v) for k, v in C.PAINT_BOOTH_FAILURE.items()},
        "row_counts": {k: int(len(v)) for k, v in tables.items()},
    }
    (out / "ground_truth.json").write_text(json.dumps(truth, ensure_ascii=False, indent=2), encoding="utf-8")
