#!/usr/bin/env python3
"""Plot grain-size evolution for the 1073 K, 100 s^-1 nucleation case.

Accepted inputs:
  1. A raw MOOSE result.csv for this single case.
  2. A combined_time_history.csv containing several cases.

The script searches for one of the following grain-size quantities:
  - D_norm
  - D_avg / average_grain_diameter
  - avg_grain_area / average_grain_volume

If only area is available, the 2D equivalent diameter is calculated as

    D = 2*sqrt(A/pi)

and normalized by the first positive value, D0.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


def norm_name(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(text).lower())


def find_col(df: pd.DataFrame, aliases: list[str]) -> str | None:
    exact = {str(c): str(c) for c in df.columns}
    for alias in aliases:
        if alias in exact:
            return exact[alias]

    normalized = {norm_name(c): str(c) for c in df.columns}
    for alias in aliases:
        key = norm_name(alias)
        if key in normalized:
            return normalized[key]
    return None


def numeric(series: pd.Series) -> pd.Series:
    return pd.to_numeric(series, errors="coerce").replace([np.inf, -np.inf], np.nan)


def filter_case(df: pd.DataFrame, temperature: float, strain_rate: float) -> pd.DataFrame:
    t_col = find_col(df, ["T", "T_K", "temperature", "temperature_K"])
    r_col = find_col(
        df,
        [
            "strain_rate",
            "strain_rate_per_s",
            "gdot",
            "gdot_avg",
            "gamma_dot",
        ],
    )

    out = df.copy()
    if t_col is not None:
        values = numeric(out[t_col])
        out = out[np.isclose(values, temperature, rtol=0.0, atol=1.0e-6)]
    if r_col is not None:
        values = numeric(out[r_col])
        out = out[np.isclose(values, strain_rate, rtol=1.0e-6, atol=1.0e-9)]

    if out.empty:
        raise ValueError(
            f"No rows matched T={temperature:g} K and strain rate={strain_rate:g} s^-1"
        )
    return out.copy()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", type=Path, required=True, help="Raw result.csv or combined_time_history.csv")
    parser.add_argument("--temperature", type=float, default=1073.0)
    parser.add_argument("--strain-rate", type=float, default=100.0)
    parser.add_argument("--time-max", type=float, default=0.10)
    parser.add_argument("--output", type=Path, default=Path("grain_size_vs_time_1073K_100s.png"))
    args = parser.parse_args()

    csv_path = args.csv.expanduser().resolve()
    if not csv_path.exists():
        raise FileNotFoundError(csv_path)

    df = pd.read_csv(csv_path)
    df = filter_case(df, args.temperature, args.strain_rate)

    time_col = find_col(df, ["time", "Time", "t"])
    if time_col is None:
        raise ValueError("No time column was found")

    time = numeric(df[time_col])

    dnorm_col = find_col(df, ["D_norm", "normalized_grain_diameter", "grain_size_norm"])
    davg_col = find_col(df, ["D_avg", "avg_grain_diameter", "average_grain_diameter"])
    area_col = find_col(
        df,
        [
            "avg_grain_area",
            "average_grain_area",
            "average_grain_volume",
            "avg_grain_volume",
        ],
    )

    if dnorm_col is not None:
        d_norm = numeric(df[dnorm_col])
        source_label = dnorm_col
    elif davg_col is not None:
        diameter = numeric(df[davg_col]).where(lambda s: s > 0)
        positive = diameter.dropna()
        if positive.empty:
            raise ValueError(f"{davg_col} contains no positive values")
        d0 = float(positive.iloc[0])
        d_norm = diameter / d0
        source_label = davg_col
    elif area_col is not None:
        area = numeric(df[area_col]).where(lambda s: s > 0)
        diameter = 2.0 * np.sqrt(area / np.pi)
        positive = diameter.dropna()
        if positive.empty:
            raise ValueError(f"{area_col} contains no positive values")
        d0 = float(positive.iloc[0])
        d_norm = diameter / d0
        source_label = f"2*sqrt({area_col}/pi)"
    else:
        columns = "\n  ".join(map(str, df.columns))
        raise ValueError(
            "No D_norm, D_avg, or avg_grain_area column was found.\n"
            f"Available columns:\n  {columns}"
        )

    insertion_col = find_col(df, ["nuc_insertions", "insertions", "nucleus_insertions"])
    cumulative_col = find_col(df, ["cum_insertions", "cumulative_insertions"])
    nuc_count_col = find_col(df, ["nuc_count", "active_nucleus_sites"])

    if cumulative_col is not None:
        cumulative = numeric(df[cumulative_col]).fillna(method="ffill").fillna(0)
        events = cumulative.diff().fillna(cumulative) > 0
    elif insertion_col is not None:
        insertions = numeric(df[insertion_col]).fillna(0)
        cumulative = insertions.cumsum()
        events = insertions > 0
    elif nuc_count_col is not None:
        active = numeric(df[nuc_count_col]).fillna(0)
        increments = active.diff().fillna(active).clip(lower=0)
        cumulative = increments.cumsum()
        events = increments > 0
    else:
        cumulative = pd.Series(0.0, index=df.index)
        events = pd.Series(False, index=df.index)

    plot_df = pd.DataFrame(
        {
            "time": time,
            "D_norm": d_norm,
            "cum_insertions": cumulative,
            "event": events,
        }
    ).dropna(subset=["time", "D_norm"]).sort_values("time")

    fig, ax = plt.subplots(figsize=(7.2, 4.8))
    ax.plot(
        plot_df["time"],
        plot_df["D_norm"],
        linewidth=2.6,
        label=r"Equivalent grain diameter, $D/D_0$",
    )

    event_df = plot_df[plot_df["event"]]
    if not event_df.empty:
        ax.scatter(
            event_df["time"],
            event_df["D_norm"],
            marker="^",
            s=75,
            zorder=4,
            label="Discrete insertion event",
        )
        first_t = float(event_df["time"].iloc[0])
        ax.axvline(first_t, linestyle=":", linewidth=1.6, label="First insertion")
    else:
        first_t = np.nan

    ax.set_xlabel("Time (s)", fontsize=13)
    ax.set_ylabel(r"Normalized equivalent grain diameter, $D/D_0$", fontsize=13)
    ax.set_title(
        rf"Grain-size evolution at {args.temperature:g} K and {args.strain_rate:g} s$^{{-1}}$",
        fontsize=15,
    )
    ax.set_xlim(0, args.time_max)
    ax.grid(True, alpha=0.25)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.legend(frameon=False, fontsize=10)

    final_d = float(plot_df["D_norm"].iloc[-1])
    min_d = float(plot_df["D_norm"].min())
    total_insertions = int(round(float(plot_df["cum_insertions"].iloc[-1])))

    annotation = (
        rf"Final $D/D_0$ = {final_d:.3g}\n"
        rf"Minimum $D/D_0$ = {min_d:.3g}\n"
        rf"Insertions = {total_insertions}"
    )
    ax.text(
        0.98,
        0.04,
        annotation,
        transform=ax.transAxes,
        ha="right",
        va="bottom",
        fontsize=10,
        bbox={"boxstyle": "round,pad=0.35", "facecolor": "white", "alpha": 0.85, "edgecolor": "0.75"},
    )

    fig.tight_layout()
    output = args.output.expanduser().resolve()
    fig.savefig(output, dpi=300, bbox_inches="tight")
    plt.close(fig)

    summary = pd.DataFrame(
        [
            {
                "temperature_K": args.temperature,
                "strain_rate_per_s": args.strain_rate,
                "final_D_norm": final_d,
                "minimum_D_norm": min_d,
                "total_insertions": total_insertions,
                "first_insertion_time_s": first_t,
                "grain_size_source": source_label,
                "input_csv": str(csv_path),
            }
        ]
    )
    summary_path = output.with_name(output.stem + "_summary.csv")
    summary.to_csv(summary_path, index=False)

    print(f"Created: {output}")
    print(f"Created: {summary_path}")
    print(summary.to_string(index=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
