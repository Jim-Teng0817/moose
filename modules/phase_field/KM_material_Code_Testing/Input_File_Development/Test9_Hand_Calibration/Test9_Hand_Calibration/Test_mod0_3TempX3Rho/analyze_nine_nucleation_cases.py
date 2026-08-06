#!/usr/bin/env python3
"""Post-process the nine U-Mo nucleation/growth screening cases.

Expected directory structure (the names may vary; case_settings.txt is preferred):

    NucleationQuick_3x3/
      T_873_gdot_0p1/
        case_settings.txt
        result.csv
        result_grain_features_0000.csv       # optional
        result_grain_features_0001.csv       # optional
        result_grain_features_time.csv       # optional
      ...

The script compares the cases versus both physical time and accumulated strain,
keeps incomplete runs, and prevents incomplete cases from being treated as
completed final states.

Example
-------
    python analyze_nine_nucleation_cases.py \
        --root NucleationQuick_3x3 \
        --checkpoints 0.1,0.5,1,2,5,10
"""

from __future__ import annotations

import argparse
import math
import re
from pathlib import Path
from typing import Iterable

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


# -----------------------------------------------------------------------------
# Column aliases
# -----------------------------------------------------------------------------

ALIASES: dict[str, list[str]] = {
    "time": ["time"],
    "T_avg": ["T_avg", "temperature", "T"],
    "gdot_avg": ["gdot_avg", "gamma_dot_avg", "strain_rate"],
    "rho_avg": ["rho_avg"],
    "rho_eff_avg": ["rho_eff_avg"],
    "tau_avg": ["tau_avg"],
    "Def_Eng": ["Def_Eng", "deformation_energy"],
    "beta_avg": ["beta_avg"],
    "P_nuc_avg": ["P_nuc_avg", "pnuc_avg"],
    "nuc_drive_ratio_avg": ["nuc_drive_ratio_avg", "drive_ratio_avg"],
    "nuc_drive_ratio_max": ["nuc_drive_ratio_max", "drive_ratio_max"],
    "stored_energy_avg": ["stored_energy_avg", "stored_energy_density_avg"],
    "curvature_penalty_avg": ["curvature_penalty_avg"],
    "energy_margin_min": ["energy_margin_min"],
    "energy_margin_max": ["energy_margin_max"],
    "energy_preferred_fraction": ["energy_preferred_fraction"],
    "eligible_nucleation_fraction": ["eligible_nucleation_fraction"],
    "P_nuc_unfavorable_max": ["P_nuc_unfavorable_max", "pnuc_unfavorable_max"],
    "P_nuc_unfavorable_integral": [
        "P_nuc_unfavorable_integral",
        "pnuc_unfavorable_integral",
    ],
    "nuc_count": ["nuc_count"],
    "nuc_rate": ["nuc_rate"],
    "nuc_insertions": ["nuc_insertions", "insertions"],
    "nuc_deletions": ["nuc_deletions", "deletions"],
    "grain_count_early": ["grain_count_early"],
    "grain_count_established": ["grain_count_established"],
    "grain_count_bnds_070": ["grain_count_bnds_070"],
    "grain_count_bnds_080": ["grain_count_bnds_080"],
    "grain_count_bnds_090": ["grain_count_bnds_090"],
    "avg_grain_area": ["avg_grain_area", "average_grain_volume", "avg_grain_volume"],
    "gb_length": ["gb_length", "grain_boundary_area", "grain_boundary_length"],
    "dt_actual": ["dt_actual", "timestep_size"],
    "dtnuc": ["dtnuc"],
}

ALL_TIME_METRICS: dict[str, str] = {
    "rho_avg": r"average dislocation density, $\rho$ (m$^{-2}$)",
    "rho_eff_avg": r"average effective dislocation density, $\rho_{eff}$",
    "nuc_drive_ratio_avg": "average nucleation driving ratio",
    "nuc_drive_ratio_max": "maximum nucleation driving ratio",
    "P_nuc_avg": "average nucleation probability/rate density",
    "energy_preferred_fraction": "energy-preferred domain fraction",
    "eligible_nucleation_fraction": "eligible nucleation-region fraction",
    "cum_insertions": "cumulative nucleus insertions",
    "cum_deletions": "cumulative nucleus deletions",
    "active_nucleus_sites": "active nucleus sites",
    "grain_count_early": "early connected-feature count",
    "grain_count_established": "established grain count",
    "new_grains_established_proxy": "new established grains (count proxy)",
    "D_norm": r"normalized equivalent grain diameter, $D/D_0$",
    "gb_length_norm": r"normalized grain-boundary length, $L_{GB}/L_{GB,0}$",
    "Def_Eng": "average deformation/stored energy",
    "dt_actual": "accepted timestep size",
}

QUICK_STRAIN_METRICS: dict[str, str] = {
    "rho_avg": r"average dislocation density, $\rho$ (m$^{-2}$)",
    "nuc_drive_ratio_max": "maximum nucleation driving ratio",
    "P_nuc_avg": "average nucleation probability/rate density",
    "cum_insertions": "cumulative nucleus insertions",
    "grain_count_established": "established grain count",
    "new_grains_established_proxy": "new established grains (count proxy)",
    "D_norm": r"normalized equivalent grain diameter, $D/D_0$",
    "gb_length_norm": r"normalized grain-boundary length, $L_{GB}/L_{GB,0}$",
}

QUICK_TIME_METRICS: dict[str, str] = {
    "cum_insertions": "cumulative nucleus insertions",
    "grain_count_established": "established grain count",
    "D_norm": r"normalized equivalent grain diameter, $D/D_0$",
    "gb_length_norm": r"normalized grain-boundary length, $L_{GB}/L_{GB,0}$",
}

HEATMAP_METRICS: dict[str, str] = {
    "completion_fraction": "completion fraction",
    "total_insertions": "total nucleus insertions",
    "total_deletions": "total nucleus deletions",
    "net_insertion_events": "net insertion events",
    "max_new_grains_established_proxy": "maximum new established grains",
    "distinct_new_grain_ids": "distinct new stable grain IDs",
    "survived_hold_grain_ids": "new grain IDs surviving hold interval",
    "final_D_norm": r"final $D/D_0$",
    "final_gb_length_norm": r"final $L_{GB}/L_{GB,0}$",
    "max_nuc_drive_ratio": "maximum nucleation driving ratio",
    "max_eligible_nucleation_fraction": "maximum eligible fraction",
    "final_rho_avg": r"final $\rho$ (m$^{-2}$)",
    "minimum_dt": "minimum accepted timestep",
}


# -----------------------------------------------------------------------------
# Basic helpers
# -----------------------------------------------------------------------------


def clean_name(value: object) -> str:
    return re.sub(r"[^a-zA-Z0-9]+", "", str(value)).lower()


def find_column(df: pd.DataFrame, candidates: Iterable[str]) -> str | None:
    lookup = {clean_name(column): column for column in df.columns}
    for candidate in candidates:
        key = clean_name(candidate)
        if key in lookup:
            return lookup[key]
    return None


def read_settings(case_dir: Path) -> dict[str, str]:
    settings: dict[str, str] = {}
    path = case_dir / "case_settings.txt"
    if not path.exists():
        return settings
    for raw_line in path.read_text(errors="replace").splitlines():
        if "=" not in raw_line:
            continue
        key, value = raw_line.split("=", 1)
        settings[key.strip()] = value.strip()
    return settings


def as_float(settings: dict[str, str], key: str, default: float = np.nan) -> float:
    try:
        return float(settings.get(key, default))
    except (TypeError, ValueError):
        return default


def parse_number(text: str) -> float:
    normalized = str(text).replace("p", ".").replace(",", ".")
    match = re.search(r"[-+]?\d*\.?\d+(?:e[-+]?\d+)?", normalized, re.IGNORECASE)
    return float(match.group(0)) if match else np.nan


def metadata_from_path(path: Path) -> tuple[float, float]:
    temperature = np.nan
    rate = np.nan
    for part in path.parts:
        lower = part.lower()
        if lower.startswith("t_"):
            temperature = parse_number(part)
        elif lower.startswith("gdot_"):
            rate = parse_number(part)
    return temperature, rate


def finite_series(series: pd.Series) -> pd.Series:
    return pd.to_numeric(series, errors="coerce").replace([np.inf, -np.inf], np.nan)


def first_finite(series: pd.Series, *, positive: bool = False) -> float:
    values = finite_series(series).dropna()
    if positive:
        values = values[values > 0]
    return float(values.iloc[0]) if not values.empty else np.nan


def last_finite(series: pd.Series) -> float:
    values = finite_series(series).dropna()
    return float(values.iloc[-1]) if not values.empty else np.nan


def max_finite(series: pd.Series) -> float:
    values = finite_series(series).dropna()
    return float(values.max()) if not values.empty else np.nan


def min_finite(series: pd.Series) -> float:
    values = finite_series(series).dropna()
    return float(values.min()) if not values.empty else np.nan


def safe_divide(numerator: float, denominator: float) -> float:
    if not np.isfinite(numerator) or not np.isfinite(denominator) or denominator == 0:
        return np.nan
    return numerator / denominator


def equivalent_diameter_from_area(area: pd.Series) -> pd.Series:
    area_numeric = finite_series(area).where(lambda values: values > 0)
    return 2.0 * np.sqrt(area_numeric / np.pi)


def safe_tag(value: object) -> str:
    return str(value).replace("+", "").replace("-", "m").replace(".", "p")


# -----------------------------------------------------------------------------
# Scalar loading
# -----------------------------------------------------------------------------


def locate_scalar_csvs(root: Path) -> list[Path]:
    exact = sorted(root.rglob("result.csv"))
    if exact:
        return exact

    candidates: list[Path] = []
    for path in sorted(root.rglob("*.csv")):
        if "analysis" in path.parts:
            continue
        if "grain_features" in path.name or "grain_volumes" in path.name:
            continue
        if path.name.endswith("_time.csv"):
            continue
        if path.name.startswith("result"):
            candidates.append(path)
    return candidates


def load_scalar_cases(root: Path, initial_grains: int) -> tuple[pd.DataFrame, list[str]]:
    csv_files = locate_scalar_csvs(root)
    if not csv_files:
        raise FileNotFoundError(f"No scalar result CSV files were found under {root}")

    frames: list[pd.DataFrame] = []
    warnings: list[str] = []

    for csv_path in csv_files:
        try:
            raw = pd.read_csv(csv_path)
        except Exception as exc:  # noqa: BLE001
            warnings.append(f"{csv_path}: could not read CSV ({exc})")
            continue

        time_column = find_column(raw, ALIASES["time"])
        if time_column is None:
            warnings.append(f"{csv_path}: no time column; skipped")
            continue

        settings = read_settings(csv_path.parent)
        T_path, rate_path = metadata_from_path(csv_path)
        temperature = as_float(settings, "T_i", T_path)
        rate = as_float(settings, "strain_rate_i", rate_path)

        if not np.isfinite(temperature) or not np.isfinite(rate):
            warnings.append(f"{csv_path}: could not determine T or strain rate; skipped")
            continue

        out = pd.DataFrame(index=raw.index)
        out["time"] = finite_series(raw[time_column])
        out["T"] = temperature
        out["strain_rate"] = rate
        out["case"] = csv_path.parent.name
        out["case_dir"] = str(csv_path.parent)
        out["source_file"] = str(csv_path)

        for canonical, aliases in ALIASES.items():
            if canonical == "time":
                continue
            column = find_column(raw, aliases)
            out[canonical] = finite_series(raw[column]) if column else np.nan
            if column is None:
                warnings.append(f"{csv_path.parent.name}: missing scalar column '{canonical}'")

        out = out.dropna(subset=["time"]).sort_values("time").reset_index(drop=True)
        out["accumulated_strain"] = rate * out["time"]

        out["nuc_insertions"] = out["nuc_insertions"].fillna(0.0)
        out["nuc_deletions"] = out["nuc_deletions"].fillna(0.0)
        out["active_nucleus_sites"] = out["nuc_count"]
        out["cum_insertions"] = out["nuc_insertions"].cumsum()
        out["cum_deletions"] = out["nuc_deletions"].cumsum()
        out["net_insertion_events"] = out["cum_insertions"] - out["cum_deletions"]

        out["D_avg"] = equivalent_diameter_from_area(out["avg_grain_area"])
        diameter_initial = first_finite(out["D_avg"], positive=True)
        out["D0"] = diameter_initial
        out["D_norm"] = (
            out["D_avg"] / diameter_initial
            if np.isfinite(diameter_initial) and diameter_initial > 0
            else np.nan
        )

        gb_initial = first_finite(out["gb_length"], positive=True)
        out["gb_length_initial"] = gb_initial
        out["gb_length_norm"] = (
            out["gb_length"] / gb_initial
            if np.isfinite(gb_initial) and gb_initial > 0
            else np.nan
        )

        initial_early = first_finite(out["grain_count_early"], positive=True)
        initial_established = first_finite(out["grain_count_established"], positive=True)
        if not np.isfinite(initial_early):
            initial_early = float(initial_grains)
        if not np.isfinite(initial_established):
            initial_established = float(initial_grains)

        out["new_grains_early_proxy"] = (out["grain_count_early"] - initial_early).clip(lower=0)
        out["new_grains_established_proxy"] = (
            out["grain_count_established"] - initial_established
        ).clip(lower=0)

        # Store settings needed later in every scalar row.
        for key in [
            "rho_init_i",
            "nuc_prob_i",
            "factor_n_i",
            "r_subgrain_i",
            "nuc_radius_i",
            "int_width_i",
            "nuc_strength_i",
            "hold_strain",
            "hold_time_i",
            "bnds_min_i",
            "bnds_max_i",
            "total_strain",
            "dt_i",
            "dt_nuc_i",
            "end_time_i",
        ]:
            out[key] = as_float(settings, key)

        frames.append(out)

    if not frames:
        raise RuntimeError("No usable scalar cases were loaded")

    combined = pd.concat(frames, ignore_index=True)
    combined = combined.sort_values(["T", "strain_rate", "time"]).reset_index(drop=True)
    return combined, warnings


# -----------------------------------------------------------------------------
# Grain-feature vector-postprocessor loading
# -----------------------------------------------------------------------------


def serial_from_name(path: Path, vpp_name: str) -> int | None:
    match = re.search(rf"_{re.escape(vpp_name)}_(\d{{4,}})\.csv$", path.name)
    return int(match.group(1)) if match else None


def locate_vpp_files(case_dir: Path, vpp_name: str) -> list[Path]:
    files = []
    for path in sorted(case_dir.glob(f"*_{vpp_name}_*.csv")):
        if path.name.endswith("_time.csv"):
            continue
        if serial_from_name(path, vpp_name) is not None:
            files.append(path)
    return files


def load_vpp_time_map(case_dir: Path, vpp_name: str) -> dict[int, float]:
    candidates = sorted(case_dir.glob(f"*_{vpp_name}_time.csv"))
    if not candidates:
        return {}
    try:
        frame = pd.read_csv(candidates[0])
    except Exception:  # noqa: BLE001
        return {}
    time_column = find_column(frame, ["time"])
    if time_column is None:
        return {}
    values = finite_series(frame[time_column]).tolist()
    return {index: float(value) for index, value in enumerate(values) if np.isfinite(value)}


def read_vpp_frame(path: Path) -> pd.DataFrame:
    raw = pd.read_csv(path)
    var_column = find_column(raw, ["var_num"])
    area_column = find_column(raw, ["feature_volumes", "feature_volume", "volume", "area"])
    if var_column is None or area_column is None:
        raise ValueError("missing var_num or feature volume")

    frame = pd.DataFrame(index=raw.index)
    frame["grain_id"] = np.arange(len(raw), dtype=int)
    frame["var_num"] = finite_series(raw[var_column])
    frame["area"] = finite_series(raw[area_column])

    for coord in ["x", "y", "z"]:
        column = find_column(raw, [f"centroid_{coord}"])
        frame[f"centroid_{coord}"] = finite_series(raw[column]) if column else np.nan

    frame = frame[(frame["var_num"] != -1) & (frame["area"] > 0)].copy()
    frame["D"] = 2.0 * np.sqrt(frame["area"] / np.pi)
    return frame


def analyze_vpp_case(
    case_dir: Path,
    scalar_case: pd.DataFrame,
    vpp_name: str,
    hold_time: float,
) -> tuple[dict[str, float], pd.DataFrame, pd.DataFrame | None]:
    files = locate_vpp_files(case_dir, vpp_name)
    if not files:
        return (
            {
                "vpp_available": 0.0,
                "distinct_new_grain_ids": np.nan,
                "survived_hold_grain_ids": np.nan,
                "final_new_grain_ids": np.nan,
                "final_active_grain_ids": np.nan,
            },
            pd.DataFrame(),
            None,
        )

    time_map = load_vpp_time_map(case_dir, vpp_name)
    snapshots: list[tuple[float, int, pd.DataFrame]] = []
    scalar_times = scalar_case["time"].to_numpy()

    for path in files:
        serial = serial_from_name(path, vpp_name)
        if serial is None:
            continue
        try:
            frame = read_vpp_frame(path)
        except Exception:
            continue
        if serial in time_map:
            time = time_map[serial]
        elif len(scalar_times):
            time = float(scalar_times[min(serial, len(scalar_times) - 1)])
        else:
            time = np.nan
        snapshots.append((time, serial, frame))

    if not snapshots:
        return (
            {
                "vpp_available": 0.0,
                "distinct_new_grain_ids": np.nan,
                "survived_hold_grain_ids": np.nan,
                "final_new_grain_ids": np.nan,
                "final_active_grain_ids": np.nan,
            },
            pd.DataFrame(),
            None,
        )

    snapshots.sort(key=lambda item: (item[0], item[1]))
    initial_ids = set(snapshots[0][2]["grain_id"].astype(int).tolist())
    all_new_ids: set[int] = set()
    final_ids = set(snapshots[-1][2]["grain_id"].astype(int).tolist())
    births: dict[int, tuple[float, pd.Series]] = {}

    for time, _, frame in snapshots:
        active_ids = set(frame["grain_id"].astype(int).tolist())
        new_ids = active_ids - initial_ids
        all_new_ids.update(new_ids)
        indexed = frame.set_index("grain_id")
        for grain_id in new_ids:
            if grain_id not in births:
                births[grain_id] = (time, indexed.loc[grain_id])

    survived: set[int] = set()
    for grain_id, (birth_time, _) in births.items():
        if not np.isfinite(hold_time):
            continue
        required_time = birth_time + hold_time
        later_snapshots = [item for item in snapshots if item[0] >= required_time]
        if not later_snapshots:
            continue
        if any(grain_id in set(item[2]["grain_id"].astype(int)) for item in later_snapshots):
            survived.add(grain_id)

    event_rows: list[dict[str, float]] = []
    for grain_id, (birth_time, row) in births.items():
        event_rows.append(
            {
                "grain_id": grain_id,
                "birth_time": birth_time,
                "birth_strain": float(scalar_case["strain_rate"].iloc[0]) * birth_time,
                "birth_area": float(row.get("area", np.nan)),
                "birth_D": float(row.get("D", np.nan)),
                "centroid_x": float(row.get("centroid_x", np.nan)),
                "centroid_y": float(row.get("centroid_y", np.nan)),
                "survived_hold": grain_id in survived,
                "active_at_final": grain_id in final_ids,
            }
        )

    final_frame = snapshots[-1][2].copy()
    final_new_ids = final_ids - initial_ids
    stats = {
        "vpp_available": 1.0,
        "distinct_new_grain_ids": float(len(all_new_ids)),
        "survived_hold_grain_ids": float(len(survived)),
        "final_new_grain_ids": float(len(final_new_ids)),
        "final_active_grain_ids": float(len(final_ids)),
    }
    return stats, pd.DataFrame(event_rows), final_frame


# -----------------------------------------------------------------------------
# Case summary, checkpoint sampling, and classification
# -----------------------------------------------------------------------------


def infer_target_strain(group: pd.DataFrame, default_target: float | None) -> float:
    recorded = first_finite(group["total_strain"], positive=True)
    if np.isfinite(recorded):
        return recorded
    if default_target is not None and np.isfinite(default_target):
        return float(default_target)
    end_time = first_finite(group["end_time_i"], positive=True)
    rate = float(group["strain_rate"].iloc[0])
    return end_time * rate if np.isfinite(end_time) else np.nan


def classify_case(row: dict[str, object]) -> str:
    max_drive = float(row.get("max_nuc_drive_ratio", np.nan))
    insertions = float(row.get("total_insertions", 0.0))
    distinct = float(row.get("distinct_new_grain_ids", np.nan))
    max_new_proxy = float(row.get("max_new_grains_established_proxy", np.nan))
    final_d_norm = float(row.get("final_D_norm", np.nan))
    final_gb_norm = float(row.get("final_gb_length_norm", np.nan))

    if np.isfinite(max_drive) and max_drive < 1.0:
        return "energy_blocked"
    if insertions <= 0:
        if (
            np.isfinite(final_d_norm)
            and final_d_norm > 1.05
            and np.isfinite(final_gb_norm)
            and final_gb_norm < 0.95
        ):
            return "coarsening_only"
        return "eligible_but_no_insertion"

    has_new_grain = (
        (np.isfinite(distinct) and distinct > 0)
        or (np.isfinite(max_new_proxy) and max_new_proxy > 0)
    )
    if not has_new_grain:
        return "insertion_but_no_new_grain"

    survived = float(row.get("survived_hold_grain_ids", np.nan))
    if np.isfinite(survived) and survived <= 0:
        return "new_grain_but_not_surviving"
    return "nucleation_and_growth"


def build_case_summaries(
    data: pd.DataFrame,
    root: Path,
    initial_grains: int,
    default_target: float | None,
    vpp_name: str,
    energy_tolerance: float,
) -> tuple[pd.DataFrame, pd.DataFrame, dict[str, pd.DataFrame]]:
    summary_rows: list[dict[str, object]] = []
    event_frames: list[pd.DataFrame] = []
    final_distributions: dict[str, pd.DataFrame] = {}

    for (case, case_dir_text), group in data.groupby(["case", "case_dir"], sort=True):
        group = group.sort_values("time").reset_index(drop=True)
        case_dir = Path(case_dir_text)
        temperature = float(group["T"].iloc[0])
        rate = float(group["strain_rate"].iloc[0])
        hold_time = first_finite(group["hold_time_i"], positive=True)

        vpp_stats, events, final_distribution = analyze_vpp_case(
            case_dir,
            group,
            vpp_name,
            hold_time,
        )
        if not events.empty:
            events["case"] = case
            events["T"] = temperature
            events["strain_rate"] = rate
            event_frames.append(events)
        if final_distribution is not None:
            final_distributions[case] = final_distribution

        target_strain = infer_target_strain(group, default_target)
        final_strain = last_finite(group["accumulated_strain"])
        completion = safe_divide(final_strain, target_strain)

        total_insertions = float(group["nuc_insertions"].fillna(0).sum())
        total_deletions = float(group["nuc_deletions"].fillna(0).sum())
        min_dt = min_finite(group["dt_actual"])
        requested_dt = first_finite(group["dt_i"], positive=True)
        dt_collapse = safe_divide(min_dt, requested_dt)

        drive_series = pd.concat(
            [group["nuc_drive_ratio_max"], group["nuc_drive_ratio_avg"]],
            ignore_index=True,
        )

        row: dict[str, object] = {
            "case": case,
            "T": temperature,
            "strain_rate": rate,
            "final_time": last_finite(group["time"]),
            "target_strain": target_strain,
            "final_accumulated_strain": final_strain,
            "completion_fraction": completion,
            "run_complete": bool(np.isfinite(completion) and completion >= 0.99),
            "total_insertions": total_insertions,
            "total_deletions": total_deletions,
            "net_insertion_events": total_insertions - total_deletions,
            "deletion_fraction": safe_divide(total_deletions, total_insertions),
            "insertions_per_strain": safe_divide(total_insertions, final_strain),
            "max_active_nucleus_sites": max_finite(group["active_nucleus_sites"]),
            "initial_grain_count_early": first_finite(group["grain_count_early"], positive=True),
            "initial_grain_count_established": first_finite(
                group["grain_count_established"], positive=True
            ),
            "final_grain_count_early": last_finite(group["grain_count_early"]),
            "final_grain_count_established": last_finite(group["grain_count_established"]),
            "max_new_grains_early_proxy": max_finite(group["new_grains_early_proxy"]),
            "max_new_grains_established_proxy": max_finite(
                group["new_grains_established_proxy"]
            ),
            "D0": first_finite(group["D_avg"], positive=True),
            "final_D_avg": last_finite(group["D_avg"]),
            "final_D_norm": last_finite(group["D_norm"]),
            "minimum_D_norm": min_finite(group["D_norm"]),
            "maximum_D_norm": max_finite(group["D_norm"]),
            "initial_gb_length": first_finite(group["gb_length"], positive=True),
            "final_gb_length": last_finite(group["gb_length"]),
            "final_gb_length_norm": last_finite(group["gb_length_norm"]),
            "final_rho_avg": last_finite(group["rho_avg"]),
            "max_rho_avg": max_finite(group["rho_avg"]),
            "final_rho_eff_avg": last_finite(group["rho_eff_avg"]),
            "max_P_nuc_avg": max_finite(group["P_nuc_avg"]),
            "max_nuc_drive_ratio": max_finite(drive_series),
            "max_energy_preferred_fraction": max_finite(group["energy_preferred_fraction"]),
            "max_eligible_nucleation_fraction": max_finite(
                group["eligible_nucleation_fraction"]
            ),
            "max_P_nuc_unfavorable": max_finite(group["P_nuc_unfavorable_max"]),
            "max_P_nuc_unfavorable_integral": max_finite(
                group["P_nuc_unfavorable_integral"]
            ),
            "minimum_dt": min_dt,
            "final_dt": last_finite(group["dt_actual"]),
            "requested_dt": requested_dt,
            "dt_collapse_ratio": dt_collapse,
            "initial_grain_count_ok": (
                abs(first_finite(group["grain_count_established"], positive=True) - initial_grains)
                <= 0.25
                if np.isfinite(first_finite(group["grain_count_established"], positive=True))
                else np.nan
            ),
            "energy_gate_ok": (
                (
                    not np.isfinite(max_finite(group["P_nuc_unfavorable_max"]))
                    or abs(max_finite(group["P_nuc_unfavorable_max"])) <= energy_tolerance
                )
                and (
                    not np.isfinite(max_finite(group["P_nuc_unfavorable_integral"]))
                    or abs(max_finite(group["P_nuc_unfavorable_integral"]))
                    <= energy_tolerance
                )
            ),
            **vpp_stats,
        }

        row["formation_efficiency"] = safe_divide(
            float(row.get("distinct_new_grain_ids", np.nan)), total_insertions
        )
        row["survival_efficiency"] = safe_divide(
            float(row.get("survived_hold_grain_ids", np.nan)), total_insertions
        )
        row["regime"] = classify_case(row)
        row["usable_for_final_state"] = bool(row["run_complete"] and row["energy_gate_ok"])
        summary_rows.append(row)

    summary = pd.DataFrame(summary_rows).sort_values(["T", "strain_rate"]).reset_index(drop=True)
    events = pd.concat(event_frames, ignore_index=True) if event_frames else pd.DataFrame()
    return summary, events, final_distributions


def sample_at_checkpoints(data: pd.DataFrame, checkpoints: list[float]) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    sample_metrics = [
        "cum_insertions",
        "cum_deletions",
        "net_insertion_events",
        "grain_count_early",
        "grain_count_established",
        "new_grains_established_proxy",
        "D_norm",
        "gb_length_norm",
        "rho_avg",
        "rho_eff_avg",
        "P_nuc_avg",
        "nuc_drive_ratio_avg",
        "nuc_drive_ratio_max",
        "energy_preferred_fraction",
        "eligible_nucleation_fraction",
        "dt_actual",
    ]

    for (case, temperature, rate), group in data.groupby(["case", "T", "strain_rate"]):
        group = group.sort_values("accumulated_strain")
        final_strain = last_finite(group["accumulated_strain"])
        for checkpoint in checkpoints:
            if not np.isfinite(final_strain) or final_strain + 1.0e-12 < checkpoint:
                continue
            distances = (group["accumulated_strain"] - checkpoint).abs()
            index = distances.idxmin()
            selected = group.loc[index]
            row: dict[str, object] = {
                "case": case,
                "T": temperature,
                "strain_rate": rate,
                "checkpoint_strain": checkpoint,
                "sample_time": selected["time"],
                "sample_strain": selected["accumulated_strain"],
            }
            for metric in sample_metrics:
                row[metric] = selected.get(metric, np.nan)
            rows.append(row)
    return pd.DataFrame(rows)


# -----------------------------------------------------------------------------
# Plotting
# -----------------------------------------------------------------------------


def plot_curves(
    data: pd.DataFrame,
    output_dir: Path,
    x_column: str,
    x_label: str,
    metrics: dict[str, str],
    *,
    include_fixed_rate: bool,
    dpi: int,
) -> None:
    curve_root = output_dir / f"curves_vs_{x_column}"
    curve_root.mkdir(parents=True, exist_ok=True)

    for metric, label in metrics.items():
        if metric not in data.columns or data[metric].isna().all():
            continue
        metric_dir = curve_root / metric
        metric_dir.mkdir(parents=True, exist_ok=True)

        # Fixed T, compare rates.
        for temperature, group_t in data.groupby("T"):
            plt.figure()
            for rate, curve in group_t.groupby("strain_rate"):
                curve = curve.sort_values(x_column)
                plt.plot(curve[x_column], curve[metric], label=f"{rate:g} s$^{{-1}}$")
            plt.xlabel(x_label)
            plt.ylabel(label)
            plt.title(f"{label} at T = {temperature:g} K")
            if metric == "dt_actual":
                positive = group_t[metric][group_t[metric] > 0]
                if not positive.empty:
                    plt.yscale("log")
            plt.legend(title="strain rate")
            plt.tight_layout()
            plt.savefig(metric_dir / f"T_{safe_tag(temperature)}.png", dpi=dpi)
            plt.close()

        # Fixed rate, compare T.
        if not include_fixed_rate:
            continue
        for rate, group_r in data.groupby("strain_rate"):
            plt.figure()
            for temperature, curve in group_r.groupby("T"):
                curve = curve.sort_values(x_column)
                plt.plot(curve[x_column], curve[metric], label=f"{temperature:g} K")
            plt.xlabel(x_label)
            plt.ylabel(label)
            plt.title(f"{label} at strain rate = {rate:g} s$^{{-1}}$")
            if metric == "dt_actual":
                positive = group_r[metric][group_r[metric] > 0]
                if not positive.empty:
                    plt.yscale("log")
            plt.legend(title="temperature")
            plt.tight_layout()
            plt.savefig(metric_dir / f"gdot_{safe_tag(rate)}.png", dpi=dpi)
            plt.close()


def draw_heatmap(
    frame: pd.DataFrame,
    value_column: str,
    label: str,
    output_path: Path,
    title: str,
    dpi: int,
) -> None:
    clean = frame[["T", "strain_rate", value_column]].copy()
    clean[value_column] = finite_series(clean[value_column])
    clean = clean.dropna(subset=["T", "strain_rate", value_column])
    if clean.empty:
        return

    pivot = clean.pivot_table(index="T", columns="strain_rate", values=value_column, aggfunc="mean")
    pivot = pivot.sort_index().sort_index(axis=1)
    if pivot.empty or not np.isfinite(pivot.to_numpy(dtype=float)).any():
        return

    values = pivot.to_numpy(dtype=float)
    plt.figure()
    image = plt.imshow(values, origin="lower", aspect="auto")
    plt.colorbar(image, label=label)
    plt.xticks(np.arange(len(pivot.columns)), [f"{value:g}" for value in pivot.columns])
    plt.yticks(np.arange(len(pivot.index)), [f"{value:g}" for value in pivot.index])
    plt.xlabel(r"strain rate (s$^{-1}$)")
    plt.ylabel("temperature (K)")
    plt.title(title)
    for i in range(values.shape[0]):
        for j in range(values.shape[1]):
            value = values[i, j]
            if np.isfinite(value):
                plt.text(j, i, f"{value:.3g}", ha="center", va="center")
    plt.tight_layout()
    plt.savefig(output_path, dpi=dpi)
    plt.close()


def plot_heatmaps(summary: pd.DataFrame, checkpoints: pd.DataFrame, output_dir: Path, dpi: int) -> None:
    heatmap_dir = output_dir / "heatmaps"
    heatmap_dir.mkdir(parents=True, exist_ok=True)

    for metric, label in HEATMAP_METRICS.items():
        if metric not in summary.columns or summary[metric].isna().all():
            continue
        draw_heatmap(
            summary,
            metric,
            label,
            heatmap_dir / f"final_{metric}.png",
            f"Final/available {label}",
            dpi,
        )

    if checkpoints.empty:
        return

    checkpoint_metrics = {
        "cum_insertions": "cumulative insertions",
        "new_grains_established_proxy": "new established grains",
        "D_norm": r"$D/D_0$",
    }
    for checkpoint, group in checkpoints.groupby("checkpoint_strain"):
        for metric, label in checkpoint_metrics.items():
            if metric not in group.columns or group[metric].isna().all():
                continue
            draw_heatmap(
                group,
                metric,
                label,
                heatmap_dir / f"strain_{safe_tag(checkpoint)}_{metric}.png",
                f"{label} near accumulated strain = {checkpoint:g}",
                dpi,
            )


def plot_final_distributions(
    final_distributions: dict[str, pd.DataFrame],
    summary: pd.DataFrame,
    output_dir: Path,
    dpi: int,
) -> None:
    if not final_distributions:
        return
    dist_dir = output_dir / "final_grain_size_distributions"
    dist_dir.mkdir(parents=True, exist_ok=True)

    lookup = summary.set_index("case")[["T", "strain_rate"]].to_dict("index")

    for temperature in sorted(summary["T"].dropna().unique()):
        plt.figure()
        plotted = False
        for case, frame in final_distributions.items():
            metadata = lookup.get(case)
            if metadata is None or metadata["T"] != temperature or frame.empty:
                continue
            diameter = np.sort(frame["D"].dropna().to_numpy())
            if len(diameter) == 0:
                continue
            cdf = np.arange(1, len(diameter) + 1) / len(diameter)
            plt.plot(diameter, cdf, label=f"{metadata['strain_rate']:g} s$^{{-1}}$")
            plotted = True
        if plotted:
            plt.xlabel("equivalent grain diameter (simulation length unit)")
            plt.ylabel("cumulative number fraction")
            plt.title(f"Final available grain-size CDF at T = {temperature:g} K")
            plt.legend(title="strain rate")
            plt.tight_layout()
            plt.savefig(dist_dir / f"T_{safe_tag(temperature)}_number_cdf.png", dpi=dpi)
        plt.close()


def write_diagnosis(summary: pd.DataFrame, output_path: Path) -> None:
    lines = [
        "# Nine-case nucleation/growth screening diagnosis",
        "",
        "Use the regime column together with completion_fraction. Incomplete runs may be",
        "compared at common strain checkpoints, but not as final-state results.",
        "",
    ]

    for _, row in summary.iterrows():
        lines.extend(
            [
                f"## T = {row['T']:g} K, strain rate = {row['strain_rate']:g} s^-1",
                "",
                f"- Completion fraction: {row['completion_fraction']:.3g}" if np.isfinite(row["completion_fraction"]) else "- Completion fraction: unavailable",
                f"- Regime: `{row['regime']}`",
                f"- Total insertions/deletions: {row['total_insertions']:.0f} / {row['total_deletions']:.0f}",
                f"- Maximum drive ratio: {row['max_nuc_drive_ratio']:.4g}" if np.isfinite(row["max_nuc_drive_ratio"]) else "- Maximum drive ratio: unavailable",
                f"- Maximum new established-grain proxy: {row['max_new_grains_established_proxy']:.4g}" if np.isfinite(row["max_new_grains_established_proxy"]) else "- Maximum new established-grain proxy: unavailable",
                f"- Final D/D0: {row['final_D_norm']:.4g}" if np.isfinite(row["final_D_norm"]) else "- Final D/D0: unavailable",
                f"- Final normalized GB length: {row['final_gb_length_norm']:.4g}" if np.isfinite(row["final_gb_length_norm"]) else "- Final normalized GB length: unavailable",
                "",
            ]
        )

    lines.extend(
        [
            "# Calibration decision guide",
            "",
            "- `energy_blocked`: inspect the physical energy threshold, especially r_subgrain.",
            "- `eligible_but_no_insertion`: increase the single global probability scale (factor_n) while keeping nuc_prob fixed.",
            "- `insertion_but_no_new_grain`: nucleus radius, strength, or hold strain is insufficient.",
            "- `new_grain_but_not_surviving`: slightly increase hold strain or insertion radius.",
            "- `nucleation_and_growth`: candidate behavior; inspect grain-size and GB-length trends.",
            "- `coarsening_only`: grain growth occurred without evidence of new-grain formation.",
        ]
    )
    output_path.write_text("\n".join(lines))


# -----------------------------------------------------------------------------
# Command line
# -----------------------------------------------------------------------------


def parse_checkpoints(text: str) -> list[float]:
    values = []
    for token in text.split(","):
        token = token.strip()
        if not token:
            continue
        value = float(token)
        if value >= 0:
            values.append(value)
    return sorted(set(values))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Analyze the nine MOOSE nucleation/growth screening cases."
    )
    parser.add_argument("--root", type=Path, default=Path("NucleationQuick_3x3"))
    parser.add_argument("--outdir", type=Path, default=None)
    parser.add_argument("--initial-grains", type=int, default=4)
    parser.add_argument("--target-strain", type=float, default=None)
    parser.add_argument(
        "--checkpoints",
        type=str,
        default="0.1,1,5,10",
        help="Comma-separated accumulated-strain checkpoints.",
    )
    parser.add_argument("--vpp-name", type=str, default="grain_features")
    parser.add_argument("--energy-tolerance", type=float, default=1.0e-14)
    parser.add_argument("--full-plots", action="store_true", help="Generate every available metric and fixed-rate plots.")
    parser.add_argument("--dpi", type=int, default=200)
    args = parser.parse_args()

    root = args.root.expanduser().resolve()
    output_dir = (
        args.outdir.expanduser().resolve()
        if args.outdir is not None
        else root / "analysis"
    )
    output_dir.mkdir(parents=True, exist_ok=True)

    data, warnings = load_scalar_cases(root, args.initial_grains)
    summary, events, final_distributions = build_case_summaries(
        data,
        root,
        args.initial_grains,
        args.target_strain,
        args.vpp_name,
        args.energy_tolerance,
    )
    checkpoints = sample_at_checkpoints(data, parse_checkpoints(args.checkpoints))

    data.to_csv(output_dir / "combined_time_history.csv", index=False)
    summary.to_csv(output_dir / "case_summary.csv", index=False)
    checkpoints.to_csv(output_dir / "checkpoint_summary.csv", index=False)
    events.to_csv(output_dir / "grain_birth_events.csv", index=False)

    (output_dir / "analysis_warnings.txt").write_text("\n".join(sorted(set(warnings))))

    if args.full_plots:
        strain_metrics = ALL_TIME_METRICS
        time_metrics = ALL_TIME_METRICS
        include_fixed_rate = True
    else:
        strain_metrics = QUICK_STRAIN_METRICS
        time_metrics = QUICK_TIME_METRICS
        include_fixed_rate = True

    plot_curves(
        data, output_dir, "accumulated_strain", "accumulated strain",
        strain_metrics, include_fixed_rate=include_fixed_rate, dpi=args.dpi
    )
    plot_curves(
        data, output_dir, "time", "physical time (s)",
        time_metrics, include_fixed_rate=False, dpi=args.dpi
    )
    plot_heatmaps(summary, checkpoints, output_dir, args.dpi)
    plot_final_distributions(final_distributions, summary, output_dir, args.dpi)
    write_diagnosis(summary, output_dir / "diagnosis.md")

    display_columns = [
        "T",
        "strain_rate",
        "completion_fraction",
        "total_insertions",
        "total_deletions",
        "max_nuc_drive_ratio",
        "max_new_grains_established_proxy",
        "distinct_new_grain_ids",
        "survived_hold_grain_ids",
        "final_D_norm",
        "final_gb_length_norm",
        "minimum_dt",
        "regime",
    ]
    available_display = [column for column in display_columns if column in summary.columns]

    print("\nNine-case summary:\n")
    print(summary[available_display].to_string(index=False))
    print("\nSaved analysis to:")
    print(output_dir)
    print("\nPrimary files:")
    print(output_dir / "case_summary.csv")
    print(output_dir / "checkpoint_summary.csv")
    print(output_dir / "diagnosis.md")


if __name__ == "__main__":
    main()
