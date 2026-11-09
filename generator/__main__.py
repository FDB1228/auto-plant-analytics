"""CLI генератора: python -m generator --out data/generated [--seed 42] [--scale 1.0] [--start ...] [--end ...]"""
import argparse
import shutil
import time
from datetime import date
from pathlib import Path

import numpy as np
import pandas as pd

from . import config as C
from .export import write_dealer_claims, write_erp_plan, write_ground_truth, write_tables
from .simulate import Simulator


def main():
    ap = argparse.ArgumentParser(description="Генератор синтетических данных автозавода")
    ap.add_argument("--out", default="data/generated")
    ap.add_argument("--seed", type=int, default=C.SEED)
    ap.add_argument("--scale", type=float, default=1.0, help="множитель объёмов выпуска (для быстрых тестов < 1)")
    ap.add_argument("--start", type=date.fromisoformat, default=C.START)
    ap.add_argument("--end", type=date.fromisoformat, default=C.END)
    args = ap.parse_args()

    out = Path(args.out)
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)

    t0 = time.time()
    tables, plan_files = Simulator(args.seed, args.start, args.end, args.scale).run()
    write_tables(tables, out)
    rng = np.random.default_rng(args.seed + 1)
    manifest = write_erp_plan(plan_files, out) + write_dealer_claims(tables, out, rng, args.end)
    pd.DataFrame(manifest).sort_values("publish_date").to_csv(out / "landing_manifest.csv", index=False)
    write_ground_truth(out, tables)

    print(f"Готово за {time.time() - t0:.1f} с -> {out}")
    for k in ("employees", "brigades", "truth_units", "truth_operations", "truth_defects", "truth_tests",
              "truth_shipments", "truth_warranty_claims"):
        print(f"  {k:<24}{len(tables[k]):>9,}".replace(",", " "))
    print(f"  {'файлов внешних систем':<24}{len(manifest):>9}")


if __name__ == "__main__":
    main()
