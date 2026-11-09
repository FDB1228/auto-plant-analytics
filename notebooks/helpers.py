"""Общие функции ноутбуков: подключение к хранилищу и единый стиль графиков."""
import sys
from pathlib import Path

import matplotlib as mpl
import matplotlib.pyplot as plt
import pandas as pd
from sqlalchemy import create_engine

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from pipeline.db import sqlalchemy_url  # noqa: E402

FIG_DIR = ROOT / "reports" / "figures"
FIG_DIR.mkdir(parents=True, exist_ok=True)

ENGINE = create_engine(sqlalchemy_url())

# Палитра: категориальные слоты в фиксированном порядке (проверены на различимость при дальтонизме)
BLUE, ORANGE, AQUA, YELLOW = "#2a78d6", "#eb6834", "#1baf7a", "#eda100"
SERIES = [BLUE, ORANGE, AQUA, YELLOW]
GRAY, GRAY_LIGHT = "#8a8985", "#d9d8d4"
INK, INK_2 = "#0b0b0b", "#52514e"
SURFACE = "#fcfcfb"


def q(sql: str, **params) -> pd.DataFrame:
    """SQL-запрос к хранилищу -> DataFrame."""
    from sqlalchemy import text
    import datetime as dt
    with ENGINE.connect() as c:
        df = pd.read_sql(text(sql), c, params=params)
    for col in df.columns:          # даты из PostgreSQL приходят как datetime.date - приводим к Timestamp
        if df[col].dtype == object and df[col].map(lambda v: isinstance(v, dt.date)).any():
            df[col] = pd.to_datetime(df[col])
    return df


def setup_style():
    mpl.rcParams.update({
        "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
        "figure.dpi": 110, "savefig.dpi": 150, "figure.figsize": (10, 4.2),
        "font.size": 10.5, "axes.titlesize": 12.5, "axes.titleweight": "bold", "axes.titlelocation": "left",
        "axes.titlepad": 12, "axes.labelcolor": INK_2, "axes.edgecolor": GRAY_LIGHT, "text.color": INK,
        "xtick.color": INK_2, "ytick.color": INK_2, "axes.spines.top": False, "axes.spines.right": False,
        "axes.grid": True, "axes.grid.axis": "y", "axes.axisbelow": True, "grid.color": "#ecebe8", "grid.linewidth": 0.8,
        "axes.prop_cycle": mpl.cycler(color=SERIES), "lines.linewidth": 2, "legend.frameon": False,
        "legend.fontsize": 9.5,
    })


def save(fig, name: str):
    fig.tight_layout()
    fig.savefig(FIG_DIR / f"{name}.png", bbox_inches="tight")


def pct(ax, decimals=0, axis="y"):
    from matplotlib.ticker import PercentFormatter
    (ax.yaxis if axis == "y" else ax.xaxis).set_major_formatter(PercentFormatter(1.0, decimals=decimals))


def label_end(ax, x, y, text, color=INK_2, dx=4):
    """Прямая подпись серии у последней точки."""
    ax.annotate(text, (x, y), xytext=(dx, 0), textcoords="offset points", va="center", fontsize=9.5, color=color)


setup_style()


def label_ends(ax, x, items: dict, min_gap: float, dx=4):
    """Подписи серий у правого края без наложения: items = {подпись: (y, цвет)}."""
    ordered = sorted(items.items(), key=lambda kv: kv[1][0])
    placed = []
    for name, (y, color) in ordered:
        y_adj = y if not placed else max(y, placed[-1] + min_gap)
        placed.append(y_adj)
        ax.annotate(name, (x, y), xytext=(x, y_adj), textcoords="data", va="center", fontsize=9.5, color=color,
                    xycoords="data", annotation_clip=False)
    return placed
