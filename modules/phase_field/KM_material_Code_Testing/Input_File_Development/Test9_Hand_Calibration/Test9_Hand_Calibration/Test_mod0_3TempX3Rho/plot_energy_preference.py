#!/usr/bin/env python3
"""Plot stored-energy driving force and constant curvature penalty for each case.

Expected input columns in combined_time_history.csv:
    time, case, T, strain_rate, stored_energy_avg, curvature_penalty_avg

Optional columns:
    nuc_insertions

Optional grain-birth file columns:
    case, birth_time, survived_hold

The script creates one plot per temperature/strain-rate case and a summary CSV.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


REQUIRED_COLUMNS = {
    "time",
    "case",
    "T",
    "strain_rate",
    "stored_energy_avg",
    "curvature_penalty_avg",
}


def safe_filename(text: str) -> str:
    """Convert a case name into a filesystem-safe name."""
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", str(text))


def time_weighted_fraction(time: np.ndarray, indicator: np.ndarray) -> float:
    """Return the fraction of simulated time for which indicator is true."""
    if len(time) < 2 or time[-1] <= time[0]:
        return float(indicator[-1]) if len(indicator) else np.nan

    # Trapezoidal integration of a 0/1 indicator.
    preferred_duration = np.trapezoid(indicator.astype(float), time)
    return float(preferred_duration / (time[-1] - time[0]))


def last_value_at_or_before(
    time: np.ndarray,
    values: np.ndarray,
    event_time: float,
) -> float:
    """Return the last finite value available at or before event_time."""
    mask = (time <= event_time) & np.isfinite(values)
    if not np.any(mask):
        return np.nan
    return float(values[mask][-1])


def load_birth_events(path: Path | None) -> pd.DataFrame:
    """Load optional grain-birth events."""
    if path is None or not path.exists():
        return pd.DataFrame()

    events = pd.read_csv(path)
    required = {"case", "birth_time"}
    missing = required.difference(events.columns)
    if missing:
        raise ValueError(
            f"Birth-event file is missing columns: {sorted(missing)}"
        )

    events["birth_time"] = pd.to_numeric(events["birth_time"], errors="coerce")

    if "survived_hold" in events.columns:
        events["survived_hold"] = (
            events["survived_hold"]
            .astype(str)
            .str.strip()
            .str.lower()
            .map({"true": True, "false": False, "1": True, "0": False})
            .fillna(False)
        )
    else:
        events["survived_hold"] = False

    return events.dropna(subset=["birth_time"])


def plot_one_case(
    group: pd.DataFrame,
    case_name: str,
    case_events: pd.DataFrame,
    output_dir: Path,
    log_y: bool,
    mark_events: bool,
) -> dict[str, float | str | bool]:
    """Make one energy-versus-time plot and return summary metrics."""

    group = group.copy()
    for column in [
        "time",
        "T",
        "strain_rate",
        "stored_energy_avg",
        "curvature_penalty_avg",
    ]:
        group[column] = pd.to_numeric(group[column], errors="coerce")

    # Remove the INITIAL row where MOOSE postprocessors may still be zero.
    group = group[
        np.isfinite(group["time"])
        & np.isfinite(group["stored_energy_avg"])
        & np.isfinite(group["curvature_penalty_avg"])
        & (group["time"] > 0)
    ].sort_values("time")

    if group.empty:
        raise ValueError(f"Case {case_name!r} has no valid positive-time data.")

    time = group["time"].to_numpy(dtype=float)
    stored = group["stored_energy_avg"].to_numpy(dtype=float)

    # The penalty should be constant because sigma and r_subgrain are constant.
    curvature_series = group["curvature_penalty_avg"].to_numpy(dtype=float)
    curvature = float(np.nanmedian(curvature_series))

    curvature_spread = float(
        np.nanmax(curvature_series) - np.nanmin(curvature_series)
    )
    curvature_relative_spread = (
        curvature_spread / abs(curvature) if curvature != 0 else np.nan
    )

    preferred = stored >= curvature
    preferred_indices = np.flatnonzero(preferred)

    first_preferred_time = (
        float(time[preferred_indices[0]]) if preferred_indices.size else np.nan
    )
    final_preferred = bool(preferred[-1])
    preferred_fraction = time_weighted_fraction(time, preferred)

    temperature = float(group["T"].dropna().iloc[-1])
    strain_rate = float(group["strain_rate"].dropna().iloc[-1])

    fig, ax = plt.subplots(figsize=(7.2, 5.2))

    ax.plot(
        time,
        stored,
        linewidth=2.0,
        label="Stored-energy driving force",
    )

    ax.axhline(
        curvature,
        linestyle="--",
        linewidth=2.0,
        label="Curvature penalty",
    )

    # Highlight the times when the average stored energy exceeds the penalty.
    ax.fill_between(
        time,
        curvature,
        stored,
        where=preferred,
        interpolate=True,
        alpha=0.18,
        label="Energetically preferred",
    )

    # if np.isfinite(first_preferred_time):
    #     ax.axvline(
    #         first_preferred_time,
    #         linestyle=":",
    #         linewidth=1.2,
    #         label=f"First preferred time = {first_preferred_time:.3g} s",
    #     )

    total_insertions = 0.0
    first_insertion_time = np.nan
    preferred_at_first_insertion = np.nan

    if "nuc_insertions" in group.columns:
        insertions = pd.to_numeric(
            group["nuc_insertions"], errors="coerce"
        ).fillna(0.0)
        event_mask = insertions.to_numpy(dtype=float) > 0
        total_insertions = float(insertions.sum())

        if np.any(event_mask):
            insertion_times = time[event_mask]
            first_insertion_time = float(insertion_times[0])

            stored_before = last_value_at_or_before(
                time, stored, first_insertion_time
            )
            preferred_at_first_insertion = bool(stored_before >= curvature)

            if mark_events:
                ax.scatter(
                    insertion_times,
                    stored[event_mask],
                    marker="^",
                    s=55,
                    zorder=4,
                    label="Discrete-nucleation insertion",
                )

    surviving_birth_count = 0
    first_surviving_birth_time = np.nan
    preferred_at_first_surviving_birth = np.nan

    if not case_events.empty:
        surviving_events = case_events[case_events["survived_hold"]].copy()
        surviving_birth_count = len(surviving_events)

        if surviving_birth_count:
            birth_times = np.sort(
                surviving_events["birth_time"].to_numpy(dtype=float)
            )
            first_surviving_birth_time = float(birth_times[0])

            stored_birth = last_value_at_or_before(
                time, stored, first_surviving_birth_time
            )
            preferred_at_first_surviving_birth = bool(
                stored_birth >= curvature
            )

            if mark_events:
                y_birth = np.array(
                    [last_value_at_or_before(time, stored, t) for t in birth_times]
                )
                ax.scatter(
                    birth_times,
                    y_birth,
                    marker="o",
                    s=55,
                    facecolors="none",
                    linewidths=1.5,
                    zorder=5,
                    label="New grain surviving hold time",
                )

    ax.set_xlabel("Time (s)")
    ax.set_ylabel(r"Energy density (J m$^{-3}$)")
    ax.set_title(
        f"Energy criterion for nucleation\n"
        f"T = {temperature:g} K, strain rate = {strain_rate:g} s$^{{-1}}$"
    )

    if log_y:
        positive_values = np.concatenate(
            [stored[stored > 0], np.array([curvature]) if curvature > 0 else np.array([])]
        )
        if positive_values.size:
            ax.set_yscale("log")
    else:
        ax.ticklabel_format(axis="y", style="sci", scilimits=(0, 0))

    ax.set_xlim(left=0)
    ax.legend(loc="best")
    fig.tight_layout()

    output_path = output_dir / f"{safe_filename(case_name)}_energy_vs_time.png"
    fig.savefig(output_path, dpi=300)
    plt.close(fig)

    return {
        "case": case_name,
        "T": temperature,
        "strain_rate": strain_rate,
        "first_preferred_time_s": first_preferred_time,
        "first_preferred_strain": (
            first_preferred_time * strain_rate
            if np.isfinite(first_preferred_time)
            else np.nan
        ),
        "preferred_time_fraction": preferred_fraction,
        "final_energy_preferred": final_preferred,
        "max_stored_energy_J_per_m3": float(np.nanmax(stored)),
        "final_stored_energy_J_per_m3": float(stored[-1]),
        "curvature_penalty_J_per_m3": curvature,
        "max_energy_ratio": float(np.nanmax(stored / curvature))
        if curvature != 0
        else np.nan,
        "curvature_relative_spread": curvature_relative_spread,
        "total_insertions": total_insertions,
        "first_insertion_time_s": first_insertion_time,
        "energy_preferred_at_first_insertion": preferred_at_first_insertion,
        "surviving_birth_count": surviving_birth_count,
        "first_surviving_birth_time_s": first_surviving_birth_time,
        "energy_preferred_at_first_surviving_birth": (
            preferred_at_first_surviving_birth
        ),
        "plot_file": str(output_path),
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Plot stored-energy driving force and constant curvature penalty "
            "versus physical time for each simulation case."
        )
    )

    parser.add_argument(
        "--input",
        type=Path,
        default=Path("NucleationQuick_3x3/analysis/combined_time_history.csv"),
        help="Combined time-history CSV produced by the nine-case analysis.",
    )
    parser.add_argument(
        "--birth-events",
        type=Path,
        default=Path("NucleationQuick_3x3/analysis/grain_birth_events.csv"),
        help=(
            "Optional grain-birth event CSV. Persistent births are marked when "
            "the file exists."
        ),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("NucleationQuick_3x3/analysis/energy_vs_time_each_case"),
        help="Directory for the individual case plots and summary CSV.",
    )
    parser.add_argument(
        "--log-y",
        action="store_true",
        help="Use a logarithmic energy axis.",
    )
    parser.add_argument(
        "--no-event-markers",
        action="store_true",
        help="Do not mark insertion or persistent grain-birth events.",
    )

    args = parser.parse_args()

    if not args.input.exists():
        raise FileNotFoundError(f"Input CSV not found: {args.input}")

    data = pd.read_csv(args.input)
    missing = REQUIRED_COLUMNS.difference(data.columns)
    if missing:
        raise ValueError(
            f"Input CSV is missing required columns: {sorted(missing)}"
        )

    birth_events = load_birth_events(
        args.birth_events if args.birth_events.exists() else None
    )

    args.output_dir.mkdir(parents=True, exist_ok=True)

    summary_rows = []

    for case_name, group in data.groupby("case", sort=True):
        if birth_events.empty:
            case_events = pd.DataFrame()
        else:
            case_events = birth_events[birth_events["case"] == case_name]

        summary_rows.append(
            plot_one_case(
                group=group,
                case_name=str(case_name),
                case_events=case_events,
                output_dir=args.output_dir,
                log_y=args.log_y,
                mark_events=not args.no_event_markers,
            )
        )

    summary = pd.DataFrame(summary_rows).sort_values(
        ["T", "strain_rate"]
    )

    summary_path = args.output_dir / "energy_preference_summary.csv"
    summary.to_csv(summary_path, index=False)

    print(f"Created {len(summary)} case plots in:")
    print(args.output_dir)
    print()
    print("Summary:")
    print(summary_path)
    print()
    print(
        summary[
            [
                "case",
                "first_preferred_time_s",
                "preferred_time_fraction",
                "total_insertions",
                "energy_preferred_at_first_insertion",
                "surviving_birth_count",
                "energy_preferred_at_first_surviving_birth",
            ]
        ].to_string(index=False)
    )


if __name__ == "__main__":
    main()
