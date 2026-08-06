#!/usr/bin/env python3
"""Create presentation-ready Slide 9 plots for one U-10Mo RX case.

The script compares a local KM-only simulation with a coupled nucleation/
phase-field simulation and creates:

  1. slide9_rho_comparison.png
     Average dislocation density, KM-only versus coupled RX.

  2. slide9_grain_evolution.png
     Normalized equivalent grain diameter with nucleus-insertion markers.

  3. slide9_nucleation_events.png
     Cumulative insertion/deletion histories, when available.

  4. slide9_summary.png
     Two-panel figure ready to paste into the presentation.

  5. slide9_summary_metrics.csv
     Final values for small metric boxes on the slide.

The coupled input may be either:
  - one raw MOOSE result.csv, or
  - analysis/combined_time_history.csv containing several cases.

Example
-------
python make_slide9_plots.py \
  --rx-csv ~/Downloads/combined_time_history.csv \
  --temperature 1073 \
  --strain-rate 100

For a direct KM file, use --km-csv. Otherwise the script recursively searches
--km-root and selects the matching temperature/rate case.
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path
from typing import Iterable

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


DEFAULT_KM_ROOT = Path(
    "~/projects_moose/moose/modules/phase_field/"
    "KM_material_Code_Testing/Input_File_Development/"
    "Test5_Sensitivity_Test_KM_only/"
    "KM_output_dstrainPerStep1e-3_strainrate60/rho_1e16"
).expanduser()

ALIASES: dict[str, list[str]] = {
    "time": ["time", "Time", "t"],
    "temperature": [
        "T",
        "T_K",
        "T_avg",
        "temperature",
        "temperature_K",
        "temperature_avg",
    ],
    "strain_rate": [
        "strain_rate",
        "strain_rate_per_s",
        "strain_rate_i",
        "gdot",
        "gdot_avg",
        "gamma_dot",
        "gamma_dot_avg",
    ],
    "rho": ["rho_avg", "rho", "rho_eff_avg", "rho_mean"],
    "D_norm": ["D_norm", "normalized_grain_diameter", "grain_size_norm"],
    "D_avg": ["D_avg", "avg_grain_diameter", "average_grain_diameter"],
    "avg_grain_area": [
        "avg_grain_area",
        "average_grain_volume",
        "avg_grain_volume",
        "average_grain_area",
    ],
    "nuc_insertions": ["nuc_insertions", "insertions", "nucleus_insertions"],
    "nuc_deletions": ["nuc_deletions", "deletions", "nucleus_deletions"],
    "cum_insertions": ["cum_insertions", "cumulative_insertions"],
    "cum_deletions": ["cum_deletions", "cumulative_deletions"],
    "nuc_count": ["nuc_count", "active_nucleus_sites"],
    "case": ["case", "case_name"],
}


def normalized_name(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(name).lower())


def find_column(frame: pd.DataFrame, aliases: Iterable[str]) -> str | None:
    exact = {str(column): str(column) for column in frame.columns}
    for alias in aliases:
        if alias in exact:
            return exact[alias]

    normalized = {normalized_name(column): str(column) for column in frame.columns}
    for alias in aliases:
        key = normalized_name(alias)
        if key in normalized:
            return normalized[key]
    return None


def finite_series(values: pd.Series) -> pd.Series:
    return pd.to_numeric(values, errors="coerce").replace([np.inf, -np.inf], np.nan)


def decode_tag_number(text: str) -> float | None:
    """Decode common directory tags such as 0p1, 100p0, or m1p0."""
    value = text.strip().lower()
    if not value:
        return None
    if value.startswith("m"):
        value = "-" + value[1:]
    value = value.replace("p", ".")
    try:
        return float(value)
    except ValueError:
        return None


def metadata_from_path(path: Path) -> tuple[float | None, float | None]:
    text = str(path)
    temp_patterns = [
        r"(?:^|[/_\-])T[_\-]?([0-9]+(?:p[0-9]+|\.[0-9]+)?)",
        r"(?:temp|temperature)[_\-]?([0-9]+(?:p[0-9]+|\.[0-9]+)?)",
    ]
    rate_patterns = [
        r"(?:gdot|strain[_\-]?rate|rate)[_\-]?([m]?[0-9]+(?:p[0-9]+|\.[0-9]+)?)",
    ]

    temperature: float | None = None
    rate: float | None = None

    for pattern in temp_patterns:
        match = re.search(pattern, text, flags=re.IGNORECASE)
        if match:
            temperature = decode_tag_number(match.group(1))
            break

    for pattern in rate_patterns:
        match = re.search(pattern, text, flags=re.IGNORECASE)
        if match:
            rate = decode_tag_number(match.group(1))
            break

    return temperature, rate


def scalar_from_column(frame: pd.DataFrame, aliases: Iterable[str]) -> float | None:
    column = find_column(frame, aliases)
    if column is None:
        return None
    values = finite_series(frame[column]).dropna()
    if values.empty:
        return None
    return float(values.median())


def canonicalize(frame: pd.DataFrame, source: Path) -> pd.DataFrame:
    time_col = find_column(frame, ALIASES["time"])
    rho_col = find_column(frame, ALIASES["rho"])
    if time_col is None or rho_col is None:
        missing = []
        if time_col is None:
            missing.append("time")
        if rho_col is None:
            missing.append("rho/rho_avg")
        raise ValueError(f"{source}: missing required column(s): {', '.join(missing)}")

    out = pd.DataFrame()
    out["time"] = finite_series(frame[time_col])
    out["rho"] = finite_series(frame[rho_col])

    for canonical in [
        "temperature",
        "strain_rate",
        "D_norm",
        "D_avg",
        "avg_grain_area",
        "nuc_insertions",
        "nuc_deletions",
        "cum_insertions",
        "cum_deletions",
        "nuc_count",
        "case",
    ]:
        column = find_column(frame, ALIASES[canonical])
        if column is None:
            out[canonical] = np.nan
        elif canonical == "case":
            out[canonical] = frame[column].astype(str)
        else:
            out[canonical] = finite_series(frame[column])

    out["source_file"] = str(source)
    out = out.dropna(subset=["time", "rho"]).sort_values("time").reset_index(drop=True)
    return out


def filter_case(
    data: pd.DataFrame,
    temperature: float,
    strain_rate: float,
    case_contains: str | None,
    source: Path,
) -> pd.DataFrame:
    subset = data.copy()

    if case_contains:
        if "case" not in subset or subset["case"].isna().all():
            raise ValueError(
                f"--case-contains was supplied, but {source} has no case column"
            )
        mask = subset["case"].astype(str).str.contains(case_contains, case=False, regex=False)
        subset = subset[mask]

    if "temperature" in subset and subset["temperature"].notna().any():
        mask = np.isclose(
            subset["temperature"].to_numpy(dtype=float),
            temperature,
            rtol=0.0,
            atol=max(1.0e-6, abs(temperature) * 1.0e-6),
        )
        subset = subset[mask]

    if "strain_rate" in subset and subset["strain_rate"].notna().any():
        mask = np.isclose(
            subset["strain_rate"].to_numpy(dtype=float),
            strain_rate,
            rtol=1.0e-6,
            atol=max(1.0e-12, abs(strain_rate) * 1.0e-6),
        )
        subset = subset[mask]

    if subset.empty:
        available = []
        if "temperature" in data and "strain_rate" in data:
            pairs = (
                data[["temperature", "strain_rate"]]
                .dropna()
                .drop_duplicates()
                .sort_values(["temperature", "strain_rate"])
            )
            available = [
                f"T={row.temperature:g}, rate={row.strain_rate:g}"
                for row in pairs.itertuples(index=False)
            ]
        detail = "\nAvailable cases: " + ", ".join(available[:30]) if available else ""
        raise ValueError(
            f"No matching case in {source} for T={temperature:g} K and "
            f"rate={strain_rate:g} s^-1.{detail}"
        )

    # If duplicate case histories remain, use the one with the largest number
    # of time points. This prevents accidental mixing of repeated cases.
    if "case" in subset and subset["case"].notna().any():
        counts = subset.groupby("case", dropna=True).size().sort_values(ascending=False)
        if not counts.empty:
            chosen_case = str(counts.index[0])
            subset = subset[subset["case"].astype(str) == chosen_case]
            print(f"Selected coupled case: {chosen_case}")

    return subset.sort_values("time").reset_index(drop=True)


def read_csv_flexibly(path: Path) -> pd.DataFrame:
    try:
        return pd.read_csv(path)
    except UnicodeDecodeError:
        return pd.read_csv(path, encoding="latin-1")


def load_coupled_case(
    path: Path,
    temperature: float,
    strain_rate: float,
    case_contains: str | None,
) -> pd.DataFrame:
    if path.is_dir():
        preferred = path / "analysis" / "combined_time_history.csv"
        if preferred.exists():
            path = preferred
        else:
            exact = sorted(path.rglob("result.csv"))
            if not exact:
                raise FileNotFoundError(f"No result.csv found under {path}")
            frames: list[pd.DataFrame] = []
            for csv_path in exact:
                raw = read_csv_flexibly(csv_path)
                try:
                    case = canonicalize(raw, csv_path)
                except ValueError:
                    continue
                path_T, path_rate = metadata_from_path(csv_path)
                if case["temperature"].isna().all() and path_T is not None:
                    case["temperature"] = path_T
                if case["strain_rate"].isna().all() and path_rate is not None:
                    case["strain_rate"] = path_rate
                if case["case"].isna().all():
                    case["case"] = csv_path.parent.name
                frames.append(case)
            if not frames:
                raise RuntimeError(f"No usable coupled scalar CSVs under {path}")
            data = pd.concat(frames, ignore_index=True)
            return filter_case(data, temperature, strain_rate, case_contains, path)

    if not path.exists():
        raise FileNotFoundError(f"Coupled/nucleation CSV not found: {path}")

    raw = read_csv_flexibly(path)
    data = canonicalize(raw, path)
    path_T, path_rate = metadata_from_path(path)
    if data["temperature"].isna().all() and path_T is not None:
        data["temperature"] = path_T
    if data["strain_rate"].isna().all() and path_rate is not None:
        data["strain_rate"] = path_rate

    # A single raw result.csv often has no T/rate columns. In that case the
    # user has already selected the case, so keep the complete history.
    if data["temperature"].isna().all() and data["strain_rate"].isna().all():
        return data.sort_values("time").reset_index(drop=True)

    return filter_case(data, temperature, strain_rate, case_contains, path)


def candidate_km_csvs(root: Path) -> list[Path]:
    excluded_tokens = {
        "analysis",
        "plots",
        "logs",
        "model_validation",
        "saturation_check",
    }
    candidates: list[Path] = []
    for path in sorted(root.rglob("*.csv")):
        lower_parts = {part.lower() for part in path.parts}
        if lower_parts.intersection(excluded_tokens):
            continue
        low_name = path.name.lower()
        if any(token in low_name for token in ["status", "summary", "warning"]):
            continue
        candidates.append(path)
    return candidates


def load_km_case(
    km_root: Path,
    km_csv: Path | None,
    temperature: float,
    strain_rate: float,
) -> tuple[pd.DataFrame, Path]:
    if km_csv is not None:
        if not km_csv.exists():
            raise FileNotFoundError(f"KM CSV not found: {km_csv}")
        raw = read_csv_flexibly(km_csv)
        data = canonicalize(raw, km_csv)
        return data, km_csv

    if not km_root.exists():
        raise FileNotFoundError(
            f"KM root not found: {km_root}\n"
            "Use --km-root or provide the exact file with --km-csv."
        )

    matches: list[tuple[int, float, Path, pd.DataFrame]] = []
    examined = 0

    for path in candidate_km_csvs(km_root):
        examined += 1
        try:
            raw = read_csv_flexibly(path)
            data = canonicalize(raw, path)
        except Exception:
            continue

        T_col = scalar_from_column(raw, ALIASES["temperature"])
        rate_col = scalar_from_column(raw, ALIASES["strain_rate"])
        T_path, rate_path = metadata_from_path(path)
        T_value = T_col if T_col is not None else T_path
        rate_value = rate_col if rate_col is not None else rate_path

        if T_value is None or rate_value is None:
            continue

        T_match = math.isclose(T_value, temperature, rel_tol=0.0, abs_tol=max(1e-6, abs(temperature) * 1e-6))
        rate_match = math.isclose(rate_value, strain_rate, rel_tol=1e-6, abs_tol=max(1e-12, abs(strain_rate) * 1e-6))
        if not (T_match and rate_match):
            continue

        data["temperature"] = T_value
        data["strain_rate"] = rate_value
        # Prefer longer, more complete histories; use final time as tie breaker.
        matches.append((len(data), float(data["time"].max()), path, data))

    if not matches:
        raise RuntimeError(
            f"No KM-only CSV matched T={temperature:g} K and "
            f"rate={strain_rate:g} s^-1 under {km_root}.\n"
            f"Examined {examined} CSV files. For the fastest fix, locate the exact "
            "CSV in VS Code and pass it with --km-csv /full/path/file.csv."
        )

    matches.sort(key=lambda item: (item[0], item[1]), reverse=True)
    _, _, selected_path, selected_data = matches[0]
    return selected_data.sort_values("time").reset_index(drop=True), selected_path


def first_positive_value(series: pd.Series) -> float | None:
    values = finite_series(series)
    positive = values[values > 0]
    if positive.empty:
        return None
    return float(positive.iloc[0])


def first_finite_positive(series: pd.Series) -> float | None:
    values = finite_series(series)
    values = values[values > 0]
    if values.empty:
        return None
    return float(values.iloc[0])


def prepare_coupled_metrics(data: pd.DataFrame) -> pd.DataFrame:
    out = data.copy().sort_values("time").reset_index(drop=True)

    if out["D_norm"].notna().any():
        diameter_norm = finite_series(out["D_norm"])
    elif out["D_avg"].notna().any():
        diameter = finite_series(out["D_avg"])
        d0 = first_finite_positive(diameter)
        diameter_norm = diameter / d0 if d0 and d0 > 0 else pd.Series(np.nan, index=out.index)
    elif out["avg_grain_area"].notna().any():
        area = finite_series(out["avg_grain_area"]).where(lambda values: values > 0)
        diameter = 2.0 * np.sqrt(area / np.pi)
        d0 = first_finite_positive(diameter)
        diameter_norm = diameter / d0 if d0 and d0 > 0 else pd.Series(np.nan, index=out.index)
    else:
        diameter_norm = pd.Series(np.nan, index=out.index)

    out["D_norm_calc"] = diameter_norm

    if out["cum_insertions"].notna().any():
        out["cum_insertions_calc"] = finite_series(out["cum_insertions"]).fillna(method="ffill").fillna(0)
        insertion_step = out["cum_insertions_calc"].diff().fillna(out["cum_insertions_calc"])
    elif out["nuc_insertions"].notna().any():
        insertion_step = finite_series(out["nuc_insertions"]).fillna(0)
        out["cum_insertions_calc"] = insertion_step.cumsum()
    elif out["nuc_count"].notna().any():
        # nuc_count may be active sites rather than event count; use only as a
        # fallback indicator and do not cumulative-sum it.
        active = finite_series(out["nuc_count"]).fillna(0)
        insertion_step = active.diff().fillna(active).clip(lower=0)
        out["cum_insertions_calc"] = insertion_step.cumsum()
    else:
        insertion_step = pd.Series(0.0, index=out.index)
        out["cum_insertions_calc"] = 0.0

    if out["cum_deletions"].notna().any():
        out["cum_deletions_calc"] = finite_series(out["cum_deletions"]).fillna(method="ffill").fillna(0)
    elif out["nuc_deletions"].notna().any():
        out["cum_deletions_calc"] = finite_series(out["nuc_deletions"]).fillna(0).cumsum()
    else:
        out["cum_deletions_calc"] = 0.0

    out["insertion_event"] = insertion_step > 0
    return out


def value_at_times(time: np.ndarray, values: np.ndarray, query: np.ndarray) -> np.ndarray:
    valid = np.isfinite(time) & np.isfinite(values)
    if valid.sum() < 2:
        return np.full_like(query, np.nan, dtype=float)
    return np.interp(query, time[valid], values[valid])


def style_axes(ax: plt.Axes) -> None:
    ax.grid(True, alpha=0.25)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.tick_params(labelsize=11)


def plot_rho(
    km: pd.DataFrame,
    rx: pd.DataFrame,
    rho0: float,
    temperature: float,
    strain_rate: float,
    output_path: Path,
    first_insertion_time: float | None,
    xmax: float | None,
) -> None:
    fig, ax = plt.subplots(figsize=(7.0, 4.6))
    ax.plot(km["time"], km["rho"] / rho0, linestyle="--", linewidth=2.5, label="KM only")
    ax.plot(rx["time"], rx["rho"] / rho0, linestyle="-", linewidth=2.5, label="Coupled RX model")
    if first_insertion_time is not None:
        ax.axvline(first_insertion_time, linestyle=":", linewidth=1.8, label="First insertion")
    ax.set_xlabel("Time (s)", fontsize=13)
    ax.set_ylabel(r"Average dislocation density, $\bar{\rho}/\rho_0$", fontsize=13)
    ax.set_title(
        rf"Dislocation-density response: {temperature:g} K, {strain_rate:g} s$^{{-1}}$",
        fontsize=14,
    )
    ax.set_xlim(left=0, right=xmax)
    style_axes(ax)
    ax.legend(frameon=False, fontsize=11)
    fig.tight_layout()
    fig.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close(fig)


def plot_grain_evolution(
    rx: pd.DataFrame,
    temperature: float,
    strain_rate: float,
    output_path: Path,
    xmax: float | None,
) -> None:
    fig, ax = plt.subplots(figsize=(7.0, 4.6))

    if rx["D_norm_calc"].notna().any():
        ax.plot(rx["time"], rx["D_norm_calc"], linewidth=2.5, label=r"Equivalent diameter, $D/D_0$")
        events = rx[rx["insertion_event"]]
        if not events.empty:
            event_y = value_at_times(
                rx["time"].to_numpy(dtype=float),
                rx["D_norm_calc"].to_numpy(dtype=float),
                events["time"].to_numpy(dtype=float),
            )
            ax.scatter(
                events["time"],
                event_y,
                marker="^",
                s=65,
                zorder=4,
                label="Insertion event",
            )
        ax.set_ylabel(r"Normalized equivalent grain diameter, $D/D_0$", fontsize=13)
        title = "Grain-size evolution"
    else:
        ax.step(
            rx["time"],
            rx["cum_insertions_calc"],
            where="post",
            linewidth=2.5,
            label="Cumulative insertions",
        )
        ax.set_ylabel("Cumulative nucleus insertions", fontsize=13)
        title = "Nucleation-event history"
        ax.text(
            0.02,
            0.96,
            "avg_grain_area/D_norm was not found",
            transform=ax.transAxes,
            va="top",
            fontsize=10,
        )

    ax.set_xlabel("Time (s)", fontsize=13)
    ax.set_title(rf"{title}: {temperature:g} K, {strain_rate:g} s$^{{-1}}$", fontsize=14)
    ax.set_xlim(left=0, right=xmax)
    style_axes(ax)
    ax.legend(frameon=False, fontsize=11)
    fig.tight_layout()
    fig.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close(fig)


def plot_events(rx: pd.DataFrame, output_path: Path, xmax: float | None) -> None:
    fig, ax = plt.subplots(figsize=(7.0, 4.6))
    ax.step(
        rx["time"],
        rx["cum_insertions_calc"],
        where="post",
        linewidth=2.5,
        label="Cumulative insertions",
    )
    if rx["cum_deletions_calc"].max() > 0:
        ax.step(
            rx["time"],
            rx["cum_deletions_calc"],
            where="post",
            linewidth=2.5,
            linestyle="--",
            label="Cumulative deletions",
        )
    ax.set_xlabel("Time (s)", fontsize=13)
    ax.set_ylabel("Event count", fontsize=13)
    ax.set_title("Discrete-nucleation events", fontsize=14)
    ax.set_xlim(left=0, right=xmax)
    style_axes(ax)
    ax.legend(frameon=False, fontsize=11)
    fig.tight_layout()
    fig.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close(fig)


def plot_summary(
    km: pd.DataFrame,
    rx: pd.DataFrame,
    rho0: float,
    temperature: float,
    strain_rate: float,
    output_path: Path,
    first_insertion_time: float | None,
    xmax: float | None,
) -> None:
    fig, axes = plt.subplots(1, 2, figsize=(13.0, 4.8))
    ax_rho, ax_grain = axes

    ax_rho.plot(km["time"], km["rho"] / rho0, linestyle="--", linewidth=2.5, label="KM only")
    ax_rho.plot(rx["time"], rx["rho"] / rho0, linestyle="-", linewidth=2.5, label="Coupled RX model")
    if first_insertion_time is not None:
        ax_rho.axvline(first_insertion_time, linestyle=":", linewidth=1.6, label="First insertion")
    ax_rho.set_xlabel("Time (s)", fontsize=12)
    ax_rho.set_ylabel(r"$\bar{\rho}/\rho_0$", fontsize=13)
    ax_rho.set_title("Average dislocation density", fontsize=14)
    ax_rho.set_xlim(left=0, right=xmax)
    style_axes(ax_rho)
    ax_rho.legend(frameon=False, fontsize=10)

    if rx["D_norm_calc"].notna().any():
        ax_grain.plot(rx["time"], rx["D_norm_calc"], linewidth=2.5, label=r"$D/D_0$")
        events = rx[rx["insertion_event"]]
        if not events.empty:
            event_y = value_at_times(
                rx["time"].to_numpy(dtype=float),
                rx["D_norm_calc"].to_numpy(dtype=float),
                events["time"].to_numpy(dtype=float),
            )
            ax_grain.scatter(events["time"], event_y, marker="^", s=55, zorder=4, label="Insertion")
        ax_grain.set_ylabel(r"Equivalent grain diameter, $D/D_0$", fontsize=12)
        ax_grain.set_title("Grain-size evolution", fontsize=14)
    else:
        ax_grain.step(
            rx["time"],
            rx["cum_insertions_calc"],
            where="post",
            linewidth=2.5,
            label="Cumulative insertions",
        )
        ax_grain.set_ylabel("Cumulative insertions", fontsize=12)
        ax_grain.set_title("Nucleation-event history", fontsize=14)

    ax_grain.set_xlabel("Time (s)", fontsize=12)
    ax_grain.set_xlim(left=0, right=xmax)
    style_axes(ax_grain)
    ax_grain.legend(frameon=False, fontsize=10)

    total_insertions = int(round(float(rx["cum_insertions_calc"].iloc[-1])))
    final_rho_norm = float(rx["rho"].iloc[-1] / rho0)
    if rx["D_norm_calc"].notna().any():
        final_dnorm = float(rx["D_norm_calc"].dropna().iloc[-1])
        metric_text = (
            rf"Final $\bar{{\rho}}/\rho_0$ = {final_rho_norm:.3g}   |   "
            rf"Final $D/D_0$ = {final_dnorm:.3g}   |   "
            rf"Insertions = {total_insertions}"
        )
    else:
        metric_text = (
            rf"Final $\bar{{\rho}}/\rho_0$ = {final_rho_norm:.3g}   |   "
            rf"Insertions = {total_insertions}"
        )

    fig.suptitle(
        rf"Coupled recrystallization response — {temperature:g} K, {strain_rate:g} s$^{{-1}}$",
        fontsize=16,
        y=1.02,
    )
    fig.text(0.5, -0.015, metric_text, ha="center", fontsize=12)
    fig.tight_layout()
    fig.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close(fig)


def summarize_metrics(
    km: pd.DataFrame,
    rx: pd.DataFrame,
    rho0: float,
    temperature: float,
    strain_rate: float,
    first_insertion_time: float | None,
    km_path: Path,
    rx_path: Path,
) -> pd.DataFrame:
    D_final = np.nan
    D_min = np.nan
    if rx["D_norm_calc"].notna().any():
        D_final = float(rx["D_norm_calc"].dropna().iloc[-1])
        D_min = float(rx["D_norm_calc"].min())

    return pd.DataFrame(
        [
            {
                "temperature_K": temperature,
                "strain_rate_per_s": strain_rate,
                "rho0_per_m2": rho0,
                "km_final_time_s": float(km["time"].iloc[-1]),
                "rx_final_time_s": float(rx["time"].iloc[-1]),
                "km_final_rho_norm": float(km["rho"].iloc[-1] / rho0),
                "rx_final_rho_norm": float(rx["rho"].iloc[-1] / rho0),
                "rx_final_D_norm": D_final,
                "rx_min_D_norm": D_min,
                "total_insertions": float(rx["cum_insertions_calc"].iloc[-1]),
                "total_deletions": float(rx["cum_deletions_calc"].iloc[-1]),
                "first_insertion_time_s": first_insertion_time,
                "km_source": str(km_path),
                "rx_source": str(rx_path),
            }
        ]
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create Slide 9 KM-only versus coupled-RX plots."
    )
    parser.add_argument(
        "--km-root",
        type=Path,
        default=DEFAULT_KM_ROOT,
        help=f"Root of local KM-only results (default: {DEFAULT_KM_ROOT})",
    )
    parser.add_argument(
        "--km-csv",
        type=Path,
        default=None,
        help="Exact KM-only CSV; overrides --km-root recursive search.",
    )
    parser.add_argument(
        "--rx-csv",
        type=Path,
        required=True,
        help=(
            "Copied HPC result.csv, combined_time_history.csv, or the root "
            "directory containing the nucleation cases."
        ),
    )
    parser.add_argument("--temperature", type=float, default=1073.0)
    parser.add_argument("--strain-rate", type=float, default=100.0)
    parser.add_argument("--rho0", type=float, default=1.0e16)
    parser.add_argument(
        "--case-contains",
        type=str,
        default=None,
        help="Optional substring used to select one coupled case from a combined CSV.",
    )
    parser.add_argument(
        "--xmax",
        type=float,
        default=None,
        help="Optional maximum time. Default uses the common KM/RX time interval.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("slide9_plots"),
    )
    args = parser.parse_args()

    km_root = args.km_root.expanduser().resolve()
    km_csv = args.km_csv.expanduser().resolve() if args.km_csv else None
    rx_path = args.rx_csv.expanduser().resolve()
    output_dir = args.output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    km, km_selected_path = load_km_case(
        km_root=km_root,
        km_csv=km_csv,
        temperature=args.temperature,
        strain_rate=args.strain_rate,
    )
    rx = load_coupled_case(
        path=rx_path,
        temperature=args.temperature,
        strain_rate=args.strain_rate,
        case_contains=args.case_contains,
    )
    rx = prepare_coupled_metrics(rx)

    first_insertion_time: float | None = None
    event_rows = rx[rx["insertion_event"]]
    if not event_rows.empty:
        first_insertion_time = float(event_rows["time"].iloc[0])

    common_end = min(float(km["time"].max()), float(rx["time"].max()))
    xmax = args.xmax if args.xmax is not None else common_end
    if xmax <= 0:
        xmax = None

    plot_rho(
        km=km,
        rx=rx,
        rho0=args.rho0,
        temperature=args.temperature,
        strain_rate=args.strain_rate,
        output_path=output_dir / "slide9_rho_comparison.png",
        first_insertion_time=first_insertion_time,
        xmax=xmax,
    )
    plot_grain_evolution(
        rx=rx,
        temperature=args.temperature,
        strain_rate=args.strain_rate,
        output_path=output_dir / "slide9_grain_evolution.png",
        xmax=xmax,
    )
    plot_events(
        rx=rx,
        output_path=output_dir / "slide9_nucleation_events.png",
        xmax=xmax,
    )
    plot_summary(
        km=km,
        rx=rx,
        rho0=args.rho0,
        temperature=args.temperature,
        strain_rate=args.strain_rate,
        output_path=output_dir / "slide9_summary.png",
        first_insertion_time=first_insertion_time,
        xmax=xmax,
    )

    summary = summarize_metrics(
        km=km,
        rx=rx,
        rho0=args.rho0,
        temperature=args.temperature,
        strain_rate=args.strain_rate,
        first_insertion_time=first_insertion_time,
        km_path=km_selected_path,
        rx_path=rx_path,
    )
    summary.to_csv(output_dir / "slide9_summary_metrics.csv", index=False)

    print("\nSelected files")
    print(f"  KM only : {km_selected_path}")
    print(f"  Coupled : {rx_path}")
    print("\nCreated")
    for filename in [
        "slide9_rho_comparison.png",
        "slide9_grain_evolution.png",
        "slide9_nucleation_events.png",
        "slide9_summary.png",
        "slide9_summary_metrics.csv",
    ]:
        print(f"  {output_dir / filename}")

    if rx["D_norm_calc"].isna().all():
        print(
            "\nNOTE: No avg_grain_area, D_avg, or D_norm column was found. "
            "The grain-evolution panel therefore shows insertion history."
        )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
