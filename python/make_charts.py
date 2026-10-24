"""
Builds the README charts from the cleaned MySQL tables.

Each chart runs one query from the EDA scripts (simplified where needed),
saves the result as CSV in outputs/, and draws a PNG in charts/.

Usage (from the repository root):
    pip install pymysql pandas matplotlib
    MYSQL_USER=root MYSQL_PASSWORD=secret python python/make_charts.py
"""
import os
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd
import pymysql

ROOT = Path(__file__).resolve().parent.parent
CHARTS = ROOT / "charts"
OUTPUTS = ROOT / "outputs"
CHARTS.mkdir(exist_ok=True)
OUTPUTS.mkdir(exist_ok=True)

# Palette: validated categorical slots 1-2, neutral text and grid.
BLUE, ORANGE = "#2a78d6", "#eb6834"
INK, INK_2, GRID, SURFACE = "#0b0b0b", "#52514e", "#e4e3df", "#fcfcfb"

plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE,
    "axes.edgecolor": GRID, "axes.labelcolor": INK_2,
    "xtick.color": INK_2, "ytick.color": INK_2,
    "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.8,
    "axes.spines.top": False, "axes.spines.right": False,
    "font.size": 10, "axes.titlesize": 13, "axes.titleweight": "bold",
    "axes.titlecolor": INK, "axes.titlelocation": "left",
})


def query(conn, sql, name):
    df = pd.read_sql(sql, conn)
    df.to_csv(OUTPUTS / f"{name}.csv", index=False)
    return df


def finish(fig, ax, name, subtitle):
    ax.text(0, 1.02, subtitle, transform=ax.transAxes, color=INK_2, fontsize=9.5)
    ax.set_axisbelow(True)
    fig.tight_layout()
    fig.savefig(CHARTS / f"{name}.png", dpi=160)
    plt.close(fig)


def hbar(ax, labels, values, fmt):
    ax.barh(labels, values, color=BLUE, height=0.6)
    ax.invert_yaxis()
    ax.grid(axis="y", visible=False)
    for y, v in enumerate(values):
        ax.text(v, y, " " + fmt.format(v), va="center", color=INK, fontsize=9)


def main():
    conn = pymysql.connect(host=os.getenv("MYSQL_HOST", "localhost"),
                           user=os.getenv("MYSQL_USER", "root"),
                           password=os.getenv("MYSQL_PASSWORD", ""),
                           database="f1", charset="utf8mb4")

    # 1. Pole-to-win conversion by era (07_eda_race_dynamics.sql R1)
    df = query(conn, """
        SELECT era, ROUND(100 * SUM(is_win) / COUNT(*), 1) AS pole_to_win_pct
        FROM v_results WHERE is_pole = 1 AND is_indy500 = 0
        GROUP BY era ORDER BY era""", "pole_to_win_by_era")
    fig, ax = plt.subplots(figsize=(8, 4.5))
    labels = df.era.str.replace(" (hybrid era)", "\n(hybrid era)", regex=False)
    ax.bar(labels, df.pole_to_win_pct, color=BLUE, width=0.55)
    for x, v in enumerate(df.pole_to_win_pct):
        ax.text(x, v + 1, f"{v:.1f}%", ha="center", color=INK, fontsize=10)
    ax.set_ylim(0, 65); ax.set_ylabel("Pole sitter won (%)"); ax.grid(axis="x", visible=False)
    ax.set_title("Pole position matters more than ever", pad=22)
    finish(fig, ax, "pole_to_win_by_era", "Share of races won from pole, by era")

    # 2. Retirements by decade (R3)
    df = query(conn, """
        SELECT FLOOR(season / 10) * 10 AS decade,
          ROUND(100 * SUM(outcome = 'Retired' AND status_category = 'Mechanical') / COUNT(*), 1) AS mechanical_pct,
          ROUND(100 * SUM(outcome = 'Retired' AND status_category = 'Accident / damage') / COUNT(*), 1) AS accident_pct
        FROM v_results WHERE started = 1 AND is_indy500 = 0
        GROUP BY decade ORDER BY decade""", "dnf_by_decade")
    fig, ax = plt.subplots(figsize=(8, 4.5))
    x = df.decade.astype(int).astype(str) + "s"
    for col, color, label in [("mechanical_pct", BLUE, "Mechanical failure"),
                              ("accident_pct", ORANGE, "Accident or damage")]:
        ax.plot(x, df[col], color=color, linewidth=2, marker="o", markersize=5, label=label)
    first, last = df.iloc[0], df.iloc[-1]
    ax.annotate(f"{first.mechanical_pct:.0f}% of starters\nretired with a failure", (0, first.mechanical_pct),
                xytext=(10, -24), textcoords="offset points", va="top", color=INK, fontsize=9)
    ax.annotate(f"Now {last.mechanical_pct:.1f}%", (len(x) - 1, last.mechanical_pct),
                xytext=(0, -16), textcoords="offset points", ha="center", color=INK, fontsize=9)
    ax.set_ylim(0, None)
    ax.set_ylabel("% of starters"); ax.grid(axis="x", visible=False)
    ax.legend(frameon=False, loc="upper right")
    ax.set_title("Cars stopped breaking down", pad=22)
    finish(fig, ax, "dnf_by_decade", "Share of race starters who retired, by cause and decade")

    # 3. Era-neutral points per start (05_eda_drivers.sql D3)
    df = query(conn, """
        SELECT driver_name, COUNT(DISTINCT race_id) AS starts,
               ROUND(SUM(points_2010_scale) / COUNT(DISTINCT race_id), 2) AS pts_per_start
        FROM v_results WHERE started = 1 AND is_indy500 = 0
        GROUP BY driver_id, driver_name HAVING starts >= 50
        ORDER BY pts_per_start DESC LIMIT 12""", "era_neutral_points")
    fig, ax = plt.subplots(figsize=(8, 5))
    hbar(ax, df.driver_name, df.pts_per_start, "{:.1f}")
    ax.set_xlabel("Points per start on the 25-18-15 scale")
    ax.set_xlim(0, df.pts_per_start.max() * 1.12)
    ax.set_title("Fangio still tops an era-neutral points table", pad=22)
    finish(fig, ax, "era_neutral_points", "Every result re-scored with today's points system, drivers with 50+ starts")

    # 4. Teammate head-to-head (D8)
    df = query(conn, """
        SELECT a.driver_name, COUNT(*) AS shared_finishes,
               ROUND(100 * SUM(a.finish_position < b.finish_position) / COUNT(*), 1) AS pct_ahead
        FROM v_results a JOIN v_results b
          ON b.race_id = a.race_id AND b.constructor_id = a.constructor_id AND b.driver_id <> a.driver_id
        WHERE a.season >= 2014 AND a.outcome = 'Classified' AND b.outcome = 'Classified'
        GROUP BY a.driver_id, a.driver_name HAVING shared_finishes >= 40
        ORDER BY pct_ahead DESC LIMIT 12""", "teammate_h2h")
    fig, ax = plt.subplots(figsize=(8, 5))
    hbar(ax, df.driver_name, df.pct_ahead, "{:.0f}%")
    ax.axvline(50, color=INK_2, linewidth=1, linestyle="--")
    ax.set_xlim(0, 100); ax.set_xlabel("% of shared finishes ahead of teammate")
    ax.set_title("Verstappen beats his teammate 84% of the time", pad=22)
    finish(fig, ax, "teammate_h2h", "Hybrid era (2014+), both cars classified, 40+ shared finishes. Dashed line = level with teammates")

    # 5. Different winners per season (R6)
    df = query(conn, """
        SELECT season, COUNT(DISTINCT driver_id) AS winning_drivers
        FROM v_results WHERE is_win = 1 AND is_indy500 = 0
        GROUP BY season ORDER BY season""", "winners_per_season")
    fig, ax = plt.subplots(figsize=(9, 4.5))
    ax.plot(df.season, df.winning_drivers, color=BLUE, linewidth=2)
    peak = df.loc[df.winning_drivers.idxmax()]
    ax.annotate(f"{int(peak.season)}: {int(peak.winning_drivers)} winners", (peak.season, peak.winning_drivers),
                xytext=(10, 0), textcoords="offset points", va="center", color=INK, fontsize=9)
    ax.set_ylim(0, df.winning_drivers.max() + 2); ax.set_ylabel("Different race winners")
    ax.set_title("How open is each championship?", pad=22)
    finish(fig, ax, "winners_per_season", "Number of different drivers who won a Grand Prix each season (2026 in progress)")

    # 6. Constructor wins by decade (06_eda_constructors.sql T2, top team per decade)
    df = query(conn, """
        WITH d AS (
          SELECT FLOOR(season / 10) * 10 AS decade, constructor_name, COUNT(DISTINCT race_id) AS wins
          FROM v_results WHERE is_win = 1 AND is_indy500 = 0
          GROUP BY decade, constructor_id, constructor_name),
        r AS (
          SELECT decade, constructor_name, wins,
                 ROUND(100 * wins / SUM(wins) OVER (PARTITION BY decade), 1) AS share_pct,
                 ROW_NUMBER() OVER (PARTITION BY decade ORDER BY wins DESC, constructor_name) AS rn
          FROM d)
        SELECT decade, constructor_name, wins, share_pct FROM r WHERE rn = 1 ORDER BY decade""",
        "top_team_by_decade")
    fig, ax = plt.subplots(figsize=(9, 4.5))
    x = df.decade.astype(int).astype(str) + "s"
    ax.bar(x, df.share_pct, color=BLUE, width=0.55)
    for i, (v, team) in enumerate(zip(df.share_pct, df.constructor_name)):
        ax.text(i, v + 1, f"{team}\n{v:.0f}%", ha="center", color=INK, fontsize=8.5)
    ax.set_ylim(0, df.share_pct.max() + 14); ax.set_ylabel("Share of the decade's wins (%)")
    ax.grid(axis="x", visible=False)
    ax.set_title("The team that won the most in each decade", pad=22)
    finish(fig, ax, "top_team_by_decade", "Top constructor's share of all race wins in the decade (2020s in progress)")

    conn.close()
    print("Charts written to", CHARTS)


if __name__ == "__main__":
    main()
