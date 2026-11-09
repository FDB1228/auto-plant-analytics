"""Дискретно-событийная симуляция работы завода.

Результат - «полная правда» за весь период: все сущности со всеми метками
времени. Из неё source_loader затем собирает состояние операционной БД
на любую дату (как если бы система работала вживую), а также
выгрузки внешних систем (ERP-план, гарантийный портал дилеров).
"""
from __future__ import annotations

import bisect
import math
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta

import numpy as np
import pandas as pd

from . import config as C
from .names import NameFactory

DAY = timedelta(days=1)
EDUCATION = [
    "МГТУ им. Н.Э. Баумана, машиностроительные технологии",
    "Московский политех (МАМИ), наземные транспортно-технологические средства",
    "МАДИ, эксплуатация транспортно-технологических машин",
    "СПбПУ Петра Великого, технология машиностроения",
    "УрФУ, сварочное производство",
    "КНИТУ-КАИ, автоматизация технологических процессов",
    "Техникум, техническая эксплуатация автомобилей",
]


def ru_holidays(year: int) -> set[date]:
    days = {date(year, 1, d) for d in range(1, 9)}
    days |= {date(year, 2, 23), date(year, 3, 8), date(year, 5, 1), date(year, 5, 9),
             date(year, 6, 12), date(year, 11, 4), date(year, 12, 31)}
    return days


@dataclass
class Latent:
    defect_type_id: int
    severity: str
    origin_op: int
    stype: str
    detect_code: str
    detected: bool = False


@dataclass
class Brigade:
    brigade_id: int
    section_id: int
    shift: str
    name: str
    formed: date
    disbanded: date | None
    is_problem: bool = False
    memberships: list = field(default_factory=list)


class Simulator:
    def __init__(self, seed: int = C.SEED, start: date = C.START, end: date = C.END, scale: float = 1.0):
        self.rng = np.random.default_rng(seed)
        self.start, self.end, self.scale = start, end, scale
        self.names = NameFactory(self.rng)
        self.t: dict[str, pd.DataFrame] = {}
        self.files: list[dict] = []          # внешние выгрузки (ERP, дилерский портал)

    # ------------------------------------------------------------------ util
    def _calendar(self):
        hol = set()
        for y in range(self.start.year - 1, self.end.year + 2):
            hol |= ru_holidays(y)
        self.holidays = hol
        d, wds = self.start, []
        while d <= self.end:
            if d.weekday() < 5 and d not in hol:
                wds.append(d)
            d += DAY
        self.workdays = wds
        self.workday_set = set(wds)
        by_month = defaultdict(list)
        for d in wds:
            by_month[(d.year, d.month)].append(d)
        self.month_workdays = by_month
        self.rush_days = {d for days in by_month.values() for d in days[-C.RUSH_DAYS:]}
        self.n_days = (self.end - self.start).days + 1
        self.ws_shifts = {w[0]: w[3] for w in C.WORKSHOPS}

    def is_wd(self, d: date) -> bool:
        if self.start <= d <= self.end:
            return d in self.workday_set
        return d.weekday() < 5 and d not in self.holidays

    def align(self, t: datetime, shifts: int) -> datetime:
        """Сдвигает момент в ближайшее рабочее окно (8:00-20:00 или 8:00-8:00 при 2 сменах)."""
        d = t.date()
        if shifts == 2:
            if t.hour < 8 and self.is_wd(d - DAY):
                return t
            if t.hour >= 8 and self.is_wd(d):
                return t
        elif 8 <= t.hour < 20 and self.is_wd(d):
            return t
        nd = d if t.hour < 8 else d + DAY
        while not self.is_wd(nd):
            nd += DAY
        return datetime.combine(nd, time(8, 0))

    @staticmethod
    def work_date(t: datetime) -> date:
        """Рабочие сутки: ночная смена после полуночи относится к предыдущему дню."""
        return t.date() if t.hour >= 8 else t.date() - DAY

    def didx(self, d: date) -> int:
        return min(max((d - self.start).days, 0), self.n_days - 1)

    # ----------------------------------------------------------- reference
    def _reference(self):
        T = self.t
        T["workshops"] = pd.DataFrame(C.WORKSHOPS, columns=["workshop_id", "code", "name", "shifts_per_day"])
        T["section_types"] = pd.DataFrame(C.SECTION_TYPES, columns=["section_type", "name"])
        T["sections"] = pd.DataFrame(C.SECTIONS, columns=["section_id", "workshop_id", "section_type", "code", "name"])
        T["professions"] = pd.DataFrame(C.PROFESSIONS, columns=["profession_id", "name", "staff_category"])
        T["management_roles"] = pd.DataFrame(C.MANAGEMENT_ROLES, columns=["role_code", "name"])
        T["product_categories"] = pd.DataFrame(C.CATEGORIES, columns=["category_id", "code", "name"])
        T["category_attributes"] = pd.DataFrame(
            C.CATEGORY_ATTRIBUTES, columns=["attribute_id", "category_id", "code", "name", "unit", "data_type"])
        T["product_models"] = pd.DataFrame([dict(
            model_id=m["id"], category_id=m["cat"], workshop_id=m["ws"], code=m["code"], name=m["name"],
            launch_date=m["launch"], discontinued_date=None, list_price_rub=m["price"], std_cost_rub=m["cost"])
            for m in C.MODELS])
        attr_type = {a[0]: a[5] for a in C.CATEGORY_ATTRIBUTES}
        T["model_attribute_values"] = pd.DataFrame([dict(
            model_id=m["id"], category_id=m["cat"], attribute_id=a,
            value_num=v if attr_type[a] == "numeric" else None,
            value_text=v if attr_type[a] == "text" else None)
            for m in C.MODELS for a, v in m["attrs"].items()])
        T["work_types"] = pd.DataFrame(C.WORK_TYPES, columns=["work_type_id", "code", "name", "section_type"])
        wt_stype = {w[0]: w[3] for w in C.WORK_TYPES}
        stype_pos = {"WELD": 0, "PAINT": 1, "ASSY": 2, "FIN": 3}
        rows = []
        for m in C.MODELS:
            for i, (wt, mins) in enumerate(C.ROUTES[m["cat"]], start=1):
                st = wt_stype[wt]
                rows.append(dict(model_id=m["id"], step_no=i, workshop_id=m["ws"], section_id=m["line"][stype_pos[st]],
                                 section_type=st, work_type_id=wt, std_minutes=round(mins * m["tmult"] * 2) / 2))
        T["route_steps"] = pd.DataFrame(rows)
        T["defect_types"] = pd.DataFrame([d[:4] for d in C.DEFECT_TYPES],
                                         columns=["defect_type_id", "code", "name", "section_type"])
        T["downtime_reasons"] = pd.DataFrame(C.DOWNTIME_REASONS, columns=["reason_code", "name", "is_planned"])
        T["labs"] = pd.DataFrame(C.LABS, columns=["lab_id", "code", "name"])
        T["lab_workshops"] = pd.DataFrame(C.LAB_WORKSHOPS, columns=["lab_id", "workshop_id"])
        T["test_types"] = pd.DataFrame([t[:3] for t in C.TEST_TYPES], columns=["test_type_id", "code", "name"])
        tt_id = {t[1]: t[0] for t in C.TEST_TYPES}
        T["category_test_plan"] = pd.DataFrame([dict(category_id=c, test_type_id=tt_id[code], seq_no=i)
                                                for c, codes in C.CATEGORY_TEST_PLAN.items()
                                                for i, code in enumerate(codes, start=1)])
        T["dealers"] = pd.DataFrame([dict(dealer_id=i, code=d[0], name=d[1], segment=d[2], region=d[3], city=d[4])
                                     for i, d in enumerate(C.DEALERS, start=1)])
        self.section = {s[0]: dict(ws=s[1], stype=s[2], code=s[3]) for s in C.SECTIONS}
        self.model = {m["id"]: m for m in C.MODELS}
        self.route = {mid: g.sort_values("step_no").to_dict("records") for mid, g in T["route_steps"].groupby("model_id")}
        self.std_min = {(r["model_id"], r["step_no"]): r["std_minutes"] for r in rows}

    # ------------------------------------------------------------ personnel
    def _new_employee(self, profession_id: int, category: str, hire: date, female_share: float) -> int:
        eid = len(self.employees) + 1
        self.employees.append(dict(employee_id=eid, personnel_no=f"ТН-{eid:05d}",
                                   full_name=self.names.make(female_share), profession_id=profession_id,
                                   staff_category=category, hire_date=hire, termination_date=None))
        if category == "worker":
            g = int(self.rng.choice([2, 3], p=[0.6, 0.4]))
            self.grades.append(dict(employee_id=eid, valid_from=hire, skill_grade=g))
            t = hire
            while g < 6:
                t = t + timedelta(days=int(self.rng.exponential(950)) + 180)
                if t > self.end:
                    break
                g += 1
                self.grades.append(dict(employee_id=eid, valid_from=t, skill_grade=g))
        else:
            self.itr.append(dict(employee_id=eid,
                                 qualification_category=self.rng.choice(["без категории", "II", "I", "ведущий"],
                                                                        p=[0.2, 0.35, 0.3, 0.15]),
                                 education=self.rng.choice(EDUCATION)))
        return eid

    def _terminate(self, eid: int, d: date):
        if d <= self.end:
            self.employees[eid - 1]["termination_date"] = d

    def _staff_and_brigades(self):
        rng = self.rng
        self.employees, self.grades, self.itr = [], [], []
        self.brigades: list[Brigade] = []
        size_rng = {"WELD": (5, 7), "PAINT": (5, 6), "ASSY": (7, 9), "FIN": (4, 5)}

        specs = []
        for sid, s in self.section.items():
            shifts = ["day", "night"] if self.ws_shifts[s["ws"]] == 2 else ["day"]
            per_shift = 2 if s["stype"] == "ASSY" else 1
            for sh in shifts:
                for k in range(1, per_shift + 1):
                    formed = date(2012, 1, 1) + timedelta(days=int(rng.integers(0, 4200)))
                    specs.append((sid, sh, k, formed, None))
        for sid, sh, formed, disb in C.NEW_BRIGADES:
            k = sum(1 for x in specs if x[0] == sid and x[1] == sh) + 1
            specs.append((sid, sh, k, formed, disb))

        for bid, (sid, sh, k, formed, disb) in enumerate(specs, start=1):
            name = f"Бригада {self.section[sid]['code']}-{'Д' if sh == 'day' else 'Н'}{k}"
            b = Brigade(bid, sid, sh, name, formed, disb,
                        is_problem=(sid == C.PROBLEM_BRIGADE_SECTION and sh == "night"))
            self.brigades.append(b)
            lo, hi = size_rng[self.section[sid]["stype"]]
            prof = C.SECTION_PROFESSION[self.section[sid]["stype"]]
            fshare = 0.35 if self.section[sid]["stype"] == "PAINT" else 0.05
            for _ in range(int(rng.integers(lo, hi + 1))):
                self._fill_slot(b, prof, fshare)

        # дневные массивы: средний «риск по стажу» и возраст бригады
        a, tau = C.TENURE_EFFECT
        nb = len(self.brigades)
        risk_sum = np.zeros((nb, self.n_days))
        cnt = np.zeros((nb, self.n_days))
        for b in self.brigades:
            for (eid, vf, vt) in b.memberships:
                hire = self.employees[eid - 1]["hire_date"]
                i0 = max((vf - self.start).days, 0)
                i1 = min(((vt or self.end + DAY) - self.start).days, self.n_days)
                if i1 <= i0:
                    continue
                tenure = np.arange(i0, i1) + (self.start - hire).days
                risk_sum[b.brigade_id - 1, i0:i1] += 1 + a * np.exp(-tenure / tau)
                cnt[b.brigade_id - 1, i0:i1] += 1
        self.brigade_risk = np.where(cnt > 0, risk_sum / np.maximum(cnt, 1), 1.0)
        self.brigade_by_section = defaultdict(list)
        for b in self.brigades:
            self.brigade_by_section[(b.section_id, b.shift)].append(b)

    def _fill_slot(self, b: Brigade, prof: int, fshare: float):
        rng = self.rng
        normal_stay = int(365 * C.BASE_STAY_YEARS)
        stop = min(b.disbanded or self.end + DAY, self.end + DAY)
        if b.formed < self.start - timedelta(days=365):
            tenure0 = int(rng.exponential(365 * 4.5)) + 20
            hire = self.start - timedelta(days=tenure0)
            vf = max(hire, b.formed)
            leave = self.start + timedelta(days=int(rng.exponential(normal_stay)))
        else:
            hire = b.formed - timedelta(days=int(rng.integers(0, 10)))
            vf = b.formed
            leave = vf + timedelta(days=int(rng.exponential(normal_stay)))
        eid = self._new_employee(prof, "worker", hire, fshare)
        wave_done = False
        while True:
            if b.is_problem and not wave_done and vf < C.PROBLEM_START < leave:
                wave_done = True
                if rng.random() < C.PROBLEM_WAVE_SHARE:
                    leave = C.PROBLEM_START + timedelta(days=int(rng.integers(0, 40)))
            if leave >= stop:
                b.memberships.append((eid, vf, b.disbanded if b.disbanded and b.disbanded <= self.end else None))
                if b.disbanded and b.disbanded <= self.end:
                    self._terminate(eid, b.disbanded)
                break
            b.memberships.append((eid, vf, leave))
            self._terminate(eid, leave)
            hire = leave + timedelta(days=int(rng.integers(5, 26)))
            if hire >= stop:
                break
            vf = hire
            stay = C.PROBLEM_NEW_HIRE_STAY_DAYS if (b.is_problem and hire >= C.PROBLEM_START) else normal_stay
            leave = hire + timedelta(days=int(rng.exponential(stay)) + 7)
            eid = self._new_employee(prof, "worker", hire, fshare)

    def _leaders(self):
        rows = []
        for b in self.brigades:
            t = max(b.formed, self.start - timedelta(days=365))
            mem = b.memberships
            while True:
                active = [m for m in mem if m[1] <= t and (m[2] is None or m[2] > t)]
                if not active:
                    later = [m[1] for m in mem if m[1] > t]
                    if not later:
                        break
                    t = min(later)
                    continue
                eid, vf, vt = min(active, key=lambda m: self.employees[m[0] - 1]["hire_date"])
                rows.append(dict(brigade_id=b.brigade_id, employee_id=eid, valid_from=t, valid_to=vt))
                if vt is None:
                    break
                t = vt
        return pd.DataFrame(rows)

    def _management_and_labs(self):
        rng = self.rng
        rows = []

        def itr(prof, hire):
            return self._new_employee(prof, "itr", hire, 0.25)

        def long_ago():
            return date(2014, 1, 1) + timedelta(days=int(rng.integers(0, 3000)))

        for ws_id, *_ in C.WORKSHOPS:
            vf = long_ago()
            e = itr(6, vf - timedelta(days=int(rng.integers(400, 3000))))
            if ws_id == 2:   # смена начальника цеха
                change = date(2025, 6, 2)
                rows.append(dict(employee_id=e, role_code="workshop_head", workshop_id=ws_id, section_id=None,
                                 valid_from=vf, valid_to=change))
                self._terminate(e, change)
                e2 = itr(6, change - timedelta(days=30))
                rows.append(dict(employee_id=e2, role_code="workshop_head", workshop_id=ws_id, section_id=None,
                                 valid_from=change, valid_to=None))
            else:
                rows.append(dict(employee_id=e, role_code="workshop_head", workshop_id=ws_id, section_id=None,
                                 valid_from=vf, valid_to=None))

        change_sections = set(rng.choice([s for s in self.section if s != C.VACANT_SECTION_HEAD["section"]], 3,
                                         replace=False).tolist())
        for sid, s in self.section.items():
            vf = long_ago()
            e = itr(5, vf - timedelta(days=int(rng.integers(200, 2500))))
            if sid == C.VACANT_SECTION_HEAD["section"]:
                vt = C.VACANT_SECTION_HEAD["from_"]
                rows.append(dict(employee_id=e, role_code="section_head", workshop_id=None, section_id=sid,
                                 valid_from=vf, valid_to=vt))
                self._terminate(e, vt)
            elif sid in change_sections:
                ch = self.start + timedelta(days=int(rng.integers(60, 650)))
                rows.append(dict(employee_id=e, role_code="section_head", workshop_id=None, section_id=sid,
                                 valid_from=vf, valid_to=ch))
                self._terminate(e, ch)
                e2 = itr(5, ch - timedelta(days=int(rng.integers(10, 60))))
                rows.append(dict(employee_id=e2, role_code="section_head", workshop_id=None, section_id=sid,
                                 valid_from=ch, valid_to=None))
            else:
                rows.append(dict(employee_id=e, role_code="section_head", workshop_id=None, section_id=sid,
                                 valid_from=vf, valid_to=None))
            for _ in range(self.ws_shifts[s["ws"]]):
                vfm = long_ago()
                em = itr(int(rng.choice([5, 6, 9])), vfm - timedelta(days=int(rng.integers(100, 1500))))
                rows.append(dict(employee_id=em, role_code="master", workshop_id=None, section_id=sid,
                                 valid_from=vfm, valid_to=None))
        self.t["management_assignments"] = pd.DataFrame(rows)

        # прочие ИТР (технологи, инженеры по качеству) - без руководящих должностей
        for _ in range(14):
            itr(int(rng.choice([5, 7, 9])), long_ago())

        # специалисты лабораторий
        staff = []
        self.lab_staff = defaultdict(list)
        for lab_id, *_ in C.LABS:
            for _ in range(5):
                vf = long_ago()
                e = itr(8, vf)
                vt = None
                if rng.random() < 0.25:
                    vt = self.start + timedelta(days=int(rng.integers(30, 700)))
                    self._terminate(e, vt)
                    e2 = itr(8, vt)
                    staff.append(dict(lab_id=lab_id, employee_id=e2, valid_from=vt, valid_to=None))
                    self.lab_staff[lab_id].append((e2, vt, None))
                staff.append(dict(lab_id=lab_id, employee_id=e, valid_from=vf, valid_to=vt))
                self.lab_staff[lab_id].append((e, vf, vt))
        self.t["lab_staff"] = pd.DataFrame(staff)

        # оборудование лабораторий
        tt = {t[1]: t[0] for t in C.TEST_TYPES}
        eq_spec = [
            (1, "GEOM", "Координатно-измерительная машина КИМ-2000", date(2019, 5, 1), None),
            (1, "LKP", "Комплекс контроля ЛКП (толщиномер, блескомер)", date(2020, 2, 1), None),
            (1, "LKP", "Камера дождевания КД-1", date(2016, 7, 1), None),
            (1, "DYN", "Тормозной стенд СТ-3", date(2018, 3, 1), None),
            (1, "DYN", "Стенд развал-схождения РС-4", date(2019, 9, 1), None),
            (1, "ELEC", "Диагностический комплекс ДК-7", date(2021, 1, 1), None),
            (1, None, "Мобильный сканер бортовой диагностики", date(2022, 6, 1), None),
            (2, "GEOM", "Координатно-измерительная машина КИМ-3500 (крупногабаритная)", date(2017, 4, 1), None),
            (2, "LKP", "Комплекс контроля ЛКП (толщиномер, адгезиметр)", date(2018, 10, 1), None),
            (2, "LKP", "Камера дождевания КД-3", date(2015, 5, 1), None),
            (2, "DYN", "Тормозной стенд СТ-1 (1998 г.)", date(1998, 6, 1), C.OLD_STAND_REPLACED),
            (2, "DYN", "Тормозной стенд СТ-5", C.OLD_STAND_REPLACED, None),
            (2, "DYN", "Стенд развал-схождения РС-6", date(2020, 3, 1), None),
            (2, "ELEC", "Диагностический комплекс ДК-7", date(2021, 1, 1), None),
            (2, "RUN", "Испытательный трек (участок 2 км)", date(2010, 1, 1), None),
            (2, None, "Мобильный сканер бортовой диагностики", date(2022, 6, 1), None),
            (3, "DYN", "Роликовый динамометрический стенд РД-10", date(2021, 8, 1), None),
            (3, "DYN", "Стенд развал-схождения РС-6", date(2021, 8, 1), None),
            (3, "RUN", "Испытательный трек (кольцо 4 км)", date(2012, 1, 1), None),
            (3, "RUN", "Бегущий барабан ББ-2", date(2019, 11, 1), None),
        ]
        eq_rows = []
        self.lab_equipment = defaultdict(list)
        for i, (lab, code, name, comm, decomm) in enumerate(eq_spec, start=1):
            eq_rows.append(dict(equipment_id=i, lab_id=lab, inventory_no=f"ИН-{lab}{i:04d}", name=name,
                                test_type_id=tt[code] if code else None, commissioned_date=comm,
                                decommissioned_date=decomm))
            self.lab_equipment[(lab, code)].append((i, comm, decomm))
        self.t["equipment"] = pd.DataFrame(eq_rows)

    # ------------------------------------------------------------ downtimes
    def _downtimes(self):
        rng = self.rng
        weights = np.array([0.35, 0.25, 0.25, 0.15])
        codes = [r[0] for r in C.DOWNTIME_REASONS]
        events = []
        months = (self.end.year - self.start.year) * 12 + self.end.month - self.start.month + 1
        for sid, s in self.section.items():
            shifts = self.ws_shifts[s["ws"]]
            for _ in range(rng.poisson(1.2 * months)):
                d = self.workdays[int(rng.integers(0, len(self.workdays)))]
                st = datetime.combine(d, time(8)) + timedelta(minutes=int(rng.integers(0, 60 * (22 if shifts == 2 else 11))))
                dur = min(float(rng.lognormal(math.log(90), 0.8)), 720)
                events.append((sid, str(rng.choice(codes, p=weights)), st, st + timedelta(minutes=dur)))
        pb = C.PAINT_BOOTH_FAILURE
        wds = [d for d in self.workdays if pb["start"] <= d <= pb["end"]]
        for _ in range(pb["events"] if wds else 0):
            d = wds[int(rng.integers(0, len(wds)))]
            st = datetime.combine(d, time(8)) + timedelta(minutes=int(rng.integers(0, 600)))
            dur = min(float(rng.lognormal(math.log(14 * 60), 0.5)), 40 * 60)
            events.append((pb["section"], "EQUIP_FAIL", st, st + timedelta(minutes=dur)))
        # убираем пересечения внутри участка
        events.sort(key=lambda e: (e[0], e[2]))
        clean, last_end = [], {}
        for e in events:
            if e[0] in last_end and e[2] < last_end[e[0]]:
                continue
            clean.append(e)
            last_end[e[0]] = e[3]
        self.t["section_downtimes"] = pd.DataFrame(
            [dict(downtime_id=i, section_id=e[0], reason_code=e[1], started_at=e[2], ended_at=e[3])
             for i, e in enumerate(clean, start=1)])
        self.dt_index = {}
        lost = defaultdict(float)   # (section, workdate) -> доля потерянного времени
        for sid, g in self.t["section_downtimes"].groupby("section_id"):
            g = g.sort_values("started_at")
            self.dt_index[sid] = (list(g["started_at"]), list(g["ended_at"]))
            shifts = self.ws_shifts[self.section[sid]["ws"]]
            for st, en in zip(g["started_at"], g["ended_at"]):
                lost[(sid, self.work_date(st))] += (en - st).total_seconds() / 3600 / (24 if shifts == 2 else 12)
        self.lost_frac = lost

    def _push_downtime(self, sid: int, t: datetime) -> datetime:
        idx = self.dt_index.get(sid)
        if not idx:
            return t
        starts, ends = idx
        i = bisect.bisect_right(starts, t) - 1
        if i >= 0 and ends[i] > t:
            return ends[i]
        return t

    # ----------------------------------------------------------------- plan
    def _plan(self):
        rng = self.rng
        rows, files = [], []
        self.final_plan = {}
        for (y, m), days in sorted(self.month_workdays.items()):
            years = ((date(y, m, 1) - self.start).days) / 365.25
            month_rows = []
            for md in C.MODELS:
                q = md["rate"] * self.scale * len(days) * C.SEASONALITY[md["season"]][m - 1] \
                    * (1 + md["growth"]) ** years * rng.uniform(0.97, 1.03)
                month_rows.append([md["id"], max(int(round(q)), 0)])
            first = date(y, m, 1)
            pub1 = first - timedelta(days=(first - timedelta(days=1)).day - 24)    # 25-е число пред. месяца
            versions = [(1, pub1, [r[:] for r in month_rows])]
            if rng.random() < 0.3:
                rev = [[mid, max(int(round(q * rng.uniform(0.92, 1.08))), 0)] for mid, q in month_rows]
                versions.append((2, date(y, m, 12), rev))
            for ver, pub, vr in versions:
                for mid, q in vr:
                    rows.append(dict(month=first, model_id=mid, version=ver, published=pub, planned_qty=q))
                files.append(dict(kind="erp_plan", ver=ver, publish_date=pub, month=first, rows=vr))
            for mid, q in versions[-1][2]:
                self.final_plan[(first, mid)] = q
        self.t["truth_production_plan"] = pd.DataFrame(rows)
        self._plan_files = files

    # ----------------------------------------------------------- production
    def _vin(self, model_code: str, started: datetime, seq: int) -> str:
        year_char = {2024: "R", 2025: "S", 2026: "T", 2027: "V"}[started.year]
        return f"X9P{model_code}0{year_char}K{seq:06d}"

    def _production(self):
        rng = self.rng
        a_l, tau_l = C.LEARNING_TIME
        a_ld, tau_ld = C.LEARNING_DEFECT
        dt_weights = defaultdict(list)
        for d in C.DEFECT_TYPES:
            dt_weights[d[3]].append(d)
        detect_code = {d[0]: d[5] for d in C.DEFECT_TYPES}
        dt_stype = {d[0]: d[3] for d in C.DEFECT_TYPES}
        tt_id = {t[1]: t[0] for t in C.TEST_TYPES}
        tt_min = {t[1]: t[3] for t in C.TEST_TYPES}
        sev_names, sev_p = list(C.SEVERITY_P), list(C.SEVERITY_P.values())
        lab_ws = defaultdict(list)
        for lab, ws in C.LAB_WORKSHOPS:
            lab_ws[ws].append(lab)

        units, ops, defects, tests, test_eq, ships = [], [], [], [], [], []
        escaped = []
        op_id = test_id = defect_id = 0
        seq = 0
        dealers = self.t["dealers"]
        seg_dealers = {seg: g["dealer_id"].tolist() for seg, g in dealers.groupby("segment")}

        for d in self.workdays:
            first = date(d.year, d.month, 1)
            n_wd = len(self.month_workdays[(d.year, d.month)])
            rush = d in self.rush_days
            vol = C.RUSH_VOLUME_MULT if rush else C.NORMAL_VOLUME_MULT
            for md in C.MODELS:
                shifts = self.ws_shifts[md["ws"]]
                cap = 1 - min(max((self.lost_frac.get((s, d), 0.0) for s in md["line"]), default=0), 0.9)
                lam = self.final_plan[(first, md["id"])] / n_wd * vol * cap
                for _ in range(rng.poisson(lam)):
                    seq += 1
                    span = 22 * 60 if shifts == 2 else 11 * 60
                    t = datetime.combine(d, time(8)) + timedelta(minutes=float(rng.uniform(0, span)))
                    started = t
                    latent: list[Latent] = []
                    unit_steps: dict[int, int] = {}
                    heavy = md["cat"] in (2, 3, 4, 5)
                    unit_id = seq
                    for step in self.route[md["id"]]:
                        sid, stype = step["section_id"], step["section_type"]
                        t = self.align(self._push_downtime(sid, self.align(t, shifts)), shifts)
                        wdate = self.work_date(t)
                        shift = "day" if 8 <= t.hour < 20 else "night"
                        cands = [b for b in self.brigade_by_section[(sid, shift)]
                                 if b.formed <= wdate and (b.disbanded is None or wdate < b.disbanded)]
                        b = cands[int(rng.integers(0, len(cands)))]
                        age = (wdate - b.formed).days
                        di = self.didx(wdate)
                        is_pilot = sid in C.WS2_PILOT_SECTIONS and wdate >= C.WS2_START
                        dur = step["std_minutes"] * (1 + a_l * math.exp(-age / tau_l)) \
                            * (C.NIGHT_TIME_MULT if shift == "night" else 1.0) \
                            * (C.WS2_TIME_MULT if is_pilot else 1.0) * rng.lognormal(0, 0.15)
                        p = C.BASE_DEFECT_P[stype] * C.CATEGORY_DEFECT_MULT[md["cat"]] \
                            * C.SECTION_DEFECT_MULT.get(sid, 1.0) * self.brigade_risk[b.brigade_id - 1, di] \
                            * (1 + a_ld * math.exp(-age / tau_ld)) \
                            * (C.NIGHT_DEFECT_MULT if shift == "night" else 1.0) \
                            * (C.RUSH_DEFECT_MULT if wdate in self.rush_days else 1.0)
                        if stype == "WELD":
                            p *= 1 + C.WELD_GLOBAL_TREND_PER_YEAR * (wdate - self.start).days / 365.25
                            if is_pilot:
                                p *= C.WS2_DEFECT_MULT
                        finish = t + timedelta(minutes=dur)
                        op_id += 1
                        this_op = op_id
                        unit_steps[this_op] = step["step_no"]
                        result = "ok"
                        if rng.random() < p:
                            if b.is_problem and stype == "PAINT" and wdate >= C.PROBLEM_START:
                                w = C.PROBLEM_PAINT_WEIGHTS
                                dtid = int(rng.choice(list(w), p=list(w.values())))
                            else:
                                cand = dt_weights[stype]
                                ws_ = np.array([c[4] for c in cand])
                                dtid = cand[int(rng.choice(len(cand), p=ws_ / ws_.sum()))][0]
                            sev = str(rng.choice(sev_names, p=sev_p))
                            if rng.random() < C.LINE_DETECTION_P[stype]:
                                result = "defect"
                                ops.append(dict(operation_id=this_op, unit_id=unit_id, model_id=md["id"],
                                                step_no=step["step_no"], attempt_no=1, section_id=sid,
                                                brigade_id=b.brigade_id, started_at=t, finished_at=finish,
                                                result=result))
                                r_start = finish + timedelta(minutes=float(rng.uniform(5, 30)))
                                r_dur = step["std_minutes"] * rng.uniform(0.25, 0.6)
                                op_id += 1
                                ops.append(dict(operation_id=op_id, unit_id=unit_id, model_id=md["id"],
                                                step_no=step["step_no"], attempt_no=2, section_id=sid,
                                                brigade_id=b.brigade_id, started_at=r_start,
                                                finished_at=r_start + timedelta(minutes=r_dur), result="ok"))
                                defect_id += 1
                                defects.append(dict(defect_id=defect_id, unit_id=unit_id, defect_type_id=dtid,
                                                    severity=sev, detection_point="line", detected_at=finish,
                                                    operation_id=this_op, test_id=None,
                                                    origin_operation_id=this_op, rework_minutes=round(r_dur, 1)))
                                finish = r_start + timedelta(minutes=r_dur)
                            else:
                                latent.append(Latent(dtid, sev, this_op, stype, detect_code[dtid]))
                        if result == "ok":
                            ops.append(dict(operation_id=this_op, unit_id=unit_id, model_id=md["id"],
                                            step_no=step["step_no"], attempt_no=1, section_id=sid,
                                            brigade_id=b.brigade_id, started_at=t, finished_at=finish, result="ok"))
                        t = finish + timedelta(minutes=float(rng.exponential(90 if heavy else 35)))
                    assembled = finish

                    # ---- испытания
                    t = assembled + timedelta(minutes=float(rng.exponential(180)))
                    for code in C.CATEGORY_TEST_PLAN[md["cat"]]:
                        options = [lab for lab in lab_ws[md["ws"]] if code in C.LAB_TESTS[lab]]
                        if len(options) > 1:
                            pr = C.LAB_CHOICE[(md["ws"], code)]
                            lab = int(rng.choice(list(pr), p=list(pr.values())))
                        else:
                            lab = options[0]
                        attempt = 1
                        while True:
                            t = self.align(t, 1)
                            tdate = t.date()
                            dur = tt_min[code] * C.TEST_TIME_MULT[md["cat"]] * rng.lognormal(0, 0.15)
                            tfin = t + timedelta(minutes=dur)
                            staff = [e for e, vf, vt in self.lab_staff[lab] if vf <= tdate and (vt is None or tdate < vt)]
                            spec = int(rng.choice(staff))
                            test_id += 1
                            found = []
                            for lt in latent:
                                if lt.detected:
                                    continue
                                if code == "RUN":
                                    if lt.stype not in ("ASSY", "FIN"):
                                        continue
                                    pdet = C.TEST_DETECTION_P["RUN"]
                                elif lt.detect_code == code:
                                    pdet = C.TEST_DETECTION_P[code]
                                    if code == "DYN" and lab == C.OLD_STAND_LAB and tdate < C.OLD_STAND_REPLACED:
                                        pdet = C.OLD_STAND_DETECTION_P
                                else:
                                    continue
                                if rng.random() < pdet:
                                    lt.detected = True
                                    found.append(lt)
                            tests.append(dict(test_id=test_id, unit_id=unit_id, test_type_id=tt_id[code],
                                              attempt_no=attempt, lab_id=lab, workshop_id=md["ws"],
                                              specialist_id=spec, started_at=t, finished_at=tfin,
                                              result="fail" if found else "pass"))
                            for eq_id, comm, decomm in self.lab_equipment[(lab, code)]:
                                if comm <= tdate and (decomm is None or tdate < decomm):
                                    test_eq.append(dict(test_id=test_id, lab_id=lab, equipment_id=eq_id))
                            if code in ("DYN", "ELEC") and rng.random() < 0.3:
                                for eq_id, comm, decomm in self.lab_equipment[(lab, None)]:
                                    test_eq.append(dict(test_id=test_id, lab_id=lab, equipment_id=eq_id))
                            if not found:
                                t = tfin + timedelta(minutes=float(rng.exponential(60)))
                                break
                            rework_total = 0.0
                            for lt in found:
                                std = self.std_min[(md["id"], unit_steps[lt.origin_op])]
                                rw = std * rng.uniform(0.4, 1.0)
                                rework_total += rw
                                defect_id += 1
                                defects.append(dict(defect_id=defect_id, unit_id=unit_id,
                                                    defect_type_id=lt.defect_type_id, severity=lt.severity,
                                                    detection_point="test", detected_at=tfin, operation_id=None,
                                                    test_id=test_id,
                                                    origin_operation_id=lt.origin_op if rng.random() < 0.85 else None,
                                                    rework_minutes=round(rw, 1)))
                            t = tfin + timedelta(minutes=rework_total + float(rng.exponential(120)))
                            attempt += 1
                    accepted = tfin
                    units.append(dict(unit_id=unit_id, serial_no=self._vin(md["code"], started, seq),
                                      model_id=md["id"], started_at=started, assembled_at=assembled,
                                      accepted_at=accepted))
                    # ---- отгрузка
                    shipped = datetime.combine(accepted.date() + timedelta(days=int(rng.integers(1, 11))),
                                               time(int(rng.integers(9, 18)), int(rng.integers(0, 60))))
                    dl = seg_dealers[C.CATEGORY_SEGMENT[md["cat"]]]
                    dealer = int(rng.choice(dl))
                    ships.append(dict(unit_id=unit_id, dealer_id=dealer, shipped_at=shipped,
                                      price_rub=round(md["price"] * rng.uniform(0.94, 1.0), -3)))
                    for lt in latent:
                        if not lt.detected:
                            escaped.append((unit_id, md["cat"], shipped, dealer, lt))

        self.t["truth_units"] = pd.DataFrame(units)
        self.t["truth_operations"] = pd.DataFrame(ops)
        self.t["truth_defects"] = pd.DataFrame(defects)
        self.t["truth_tests"] = pd.DataFrame(tests)
        self.t["truth_test_equipment"] = pd.DataFrame(test_eq).drop_duplicates()
        sh = pd.DataFrame(ships)
        sh.insert(0, "shipment_id", range(1, len(sh) + 1))
        self.t["truth_shipments"] = sh
        self._escaped = escaped
        self._dt_stype = dt_stype

    # ------------------------------------------------------------- warranty
    def _warranty(self):
        rng = self.rng
        claims = []
        units = self.t["truth_units"].set_index("unit_id")
        ships = self.t["truth_shipments"].set_index("unit_id")
        model_cat = {m["id"]: m["cat"] for m in C.MODELS}
        horizon = datetime.combine(self.end, time(23, 59))
        assy_types = [d[0] for d in C.DEFECT_TYPES if d[3] in ("ASSY", "FIN")]

        def add(unit_id, cat, claim_dt, dealer, dtid, stype, rejected, source):
            cost = C.WARRANTY_BASE_COST[cat] * C.WARRANTY_AREA_MULT[stype] * rng.lognormal(0, 0.35)
            claims.append(dict(unit_id=unit_id, claim_date=claim_dt.date(), dealer_id=dealer, defect_type_id=dtid,
                               rejected=rejected, amount_rub=round(cost, -1), source=source))

        for unit_id, cat, shipped, dealer, lt in self._escaped:
            if rng.random() >= C.CLAIM_P_BY_SEVERITY[lt.severity]:
                continue
            k, scale = C.CLAIM_WEIBULL[lt.stype]
            days = scale * rng.weibull(k)
            if days > 730:
                continue
            cd = shipped + timedelta(days=days)
            if cd <= horizon:
                add(unit_id, cat, cd, dealer, lt.defect_type_id, lt.stype, rng.random() < 0.03, "escaped_defect")
        for unit_id, row in ships.iterrows():
            cat = model_cat[units.loc[unit_id, "model_id"]]
            exposure = min((horizon - row["shipped_at"]).days, 730) / 365
            if exposure <= 0:
                continue
            for _ in range(rng.poisson(C.BACKGROUND_CLAIM_RATE_PER_YEAR * exposure)):
                cd = row["shipped_at"] + timedelta(days=float(rng.uniform(0, exposure * 365)))
                dtid = int(rng.choice(assy_types))
                add(unit_id, cat, cd, row["dealer_id"], dtid, self._dt_stype[dtid],
                    rng.random() < C.BACKGROUND_REJECT_P, "background")
        cl = pd.DataFrame(claims, columns=["unit_id", "claim_date", "dealer_id", "defect_type_id", "rejected",
                                           "amount_rub", "source"]).sort_values("claim_date").reset_index(drop=True)
        cl.insert(0, "claim_id", [f"WC-{i:07d}" for i in range(1000001, 1000001 + len(cl))])
        cl["decision_date"] = [d + timedelta(days=int(rng.integers(7, 29))) for d in cl["claim_date"]]
        self.t["truth_warranty_claims"] = cl

    # ----------------------------------------------------------------- run
    def run(self):
        self._calendar()
        self._reference()
        self._staff_and_brigades()
        self.t["brigade_leaders"] = self._leaders()
        self._management_and_labs()
        self._downtimes()
        self._plan()
        self._production()
        self._warranty()
        T = self.t
        T["employees"] = pd.DataFrame(self.employees)
        T["truth_worker_grades"] = pd.DataFrame(self.grades)
        T["itr_details"] = pd.DataFrame(self.itr)
        T["brigades"] = pd.DataFrame([dict(brigade_id=b.brigade_id, section_id=b.section_id, name=b.name,
                                           shift=b.shift, formed_date=b.formed, disbanded_date=b.disbanded)
                                      for b in self.brigades])
        mem = [dict(brigade_id=b.brigade_id, employee_id=e, valid_from=vf, valid_to=vt)
               for b in self.brigades for e, vf, vt in b.memberships]
        mdf = pd.DataFrame(mem).sort_values(["valid_from", "brigade_id"]).reset_index(drop=True)
        mdf.insert(0, "membership_id", range(1, len(mdf) + 1))
        T["brigade_memberships"] = mdf
        lead = T["brigade_leaders"]
        lead.insert(0, "leader_period_id", range(1, len(lead) + 1))
        ma = T["management_assignments"]
        ma.insert(0, "assignment_id", range(1, len(ma) + 1))
        ls = T["lab_staff"]
        ls.insert(0, "lab_staff_id", range(1, len(ls) + 1))
        return T, self._plan_files
