import sys
from datetime import date
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from generator.simulate import Simulator  # noqa: E402


@pytest.fixture(scope="session")
def sim_tables():
    """Небольшая симуляция: 3 месяца, 20% объёма - быстро и детерминированно."""
    tables, plan_files = Simulator(seed=7, start=date(2025, 1, 1), end=date(2025, 3, 31), scale=0.2).run()
    return tables, plan_files
