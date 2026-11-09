"""Инварианты синтетических данных: то, что должно выполняться при любом seed."""
import re
from datetime import date

import pandas as pd

from generator.simulate import Simulator


def test_deterministic_by_seed():
    a, _ = Simulator(seed=1, start=date(2025, 1, 1), end=date(2025, 1, 31), scale=0.1).run()
    b, _ = Simulator(seed=1, start=date(2025, 1, 1), end=date(2025, 1, 31), scale=0.1).run()
    pd.testing.assert_frame_equal(a["truth_operations"], b["truth_operations"])


def test_vin_format_and_uniqueness(sim_tables):
    units = sim_tables[0]["truth_units"]
    assert units["serial_no"].is_unique
    assert units["serial_no"].str.fullmatch(r"X9P[A-HJ-NPR-Z0-9]{14}").all()


def test_operations_follow_route_and_unit_lifecycle(sim_tables):
    t = sim_tables[0]
    ops = t["truth_operations"].merge(t["truth_units"], on="unit_id", suffixes=("", "_u"))
    assert (ops["finished_at"] > ops["started_at"]).all()
    assert (ops["started_at"] >= ops["started_at_u"]).all()
    assert (ops["finished_at"] <= ops["assembled_at"]).all()
    first = t["truth_operations"].query("attempt_no == 1").sort_values(["unit_id", "step_no"])
    assert (first.groupby("unit_id")["started_at"].apply(lambda s: s.is_monotonic_increasing)).all()


def test_rework_only_after_line_defect(sim_tables):
    ops = sim_tables[0]["truth_operations"]
    rework = ops[ops["attempt_no"] > 1][["unit_id", "step_no"]]
    defects = ops[ops["result"] == "defect"][["unit_id", "step_no"]]
    assert len(rework.merge(defects)) == len(rework)


def test_brigade_belongs_to_section(sim_tables):
    t = sim_tables[0]
    m = t["truth_operations"].merge(t["brigades"], on="brigade_id", suffixes=("", "_b"))
    assert (m["section_id"] == m["section_id_b"]).all()


def test_memberships_do_not_overlap(sim_tables):
    mem = sim_tables[0]["brigade_memberships"].copy()
    mem["valid_to"] = mem["valid_to"].fillna(date(9999, 12, 31))
    for _, g in mem.groupby("employee_id"):
        g = g.sort_values("valid_from")
        assert (g["valid_from"].iloc[1:].values >= g["valid_to"].iloc[:-1].values).all()


def test_leader_is_member(sim_tables):
    t = sim_tables[0]
    lead, mem = t["brigade_leaders"], t["brigade_memberships"]
    for r in lead.itertuples():
        m = mem[(mem.brigade_id == r.brigade_id) & (mem.employee_id == r.employee_id)]
        assert ((m.valid_from <= r.valid_from) &
                (m.valid_to.isna() | (r.valid_to is not None and not pd.isna(r.valid_to)))).any()


def test_tests_after_assembly_and_claims_after_shipment(sim_tables):
    t = sim_tables[0]
    tests = t["truth_tests"].merge(t["truth_units"], on="unit_id", suffixes=("", "_unit"))
    assert (tests["started_at"] >= tests["assembled_at"]).all()
    if len(t["truth_warranty_claims"]):
        c = t["truth_warranty_claims"].merge(t["truth_shipments"], on="unit_id")
        assert (pd.to_datetime(c["claim_date"]) >= c["shipped_at"].dt.normalize()).all()
