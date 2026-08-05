#!/usr/bin/env python3
"""
Analyze a MOOSE discrete-nucleation calibration sweep.

Expected case layout (one folder per case):

ROOT/
  factor_<name>_<value>_T_<T>_gdot_<rate>/
    case_settings.txt
    result.csv
    result_grain_features_0000.csv   # optional VPP files
    result_grain_features_0001.csv
    ...

The script is deliberately tolerant of missing columns. It uses whatever
postprocessors are available and writes a warning report for the rest.

Main outputs:
  analysis/combined_time_history.csv
  analysis/case_summary.csv
  analysis/factor_summary.csv
  analysis/insertion_event_audit.csv
  analysis/grain_birth_events.csv          # when grain-feature VPP files exist
  analysis/calibration_ranking.csv
  analysis/calibration_recommendation.txt
  analysis/plots/...

Dependencies:
  numpy, pandas, matplotlib
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


# -----------------------------------------------------------------------------
# Column aliases
# -----------------------------------------------------------------------------

ALIASES: dict[str, list[str]] = {
    "time": ["time"],
    "T_avg": ["T_avg", "temperature_avg", "temperature"],
    "gdot_avg": ["gdot_avg", "gamma_dot_avg", "strain_rate_avg", "strain_rate"],
    "rho_avg": ["rho_avg"],
    "rho_eff_avg": ["rho_eff_avg"],
    "tau_avg": ["tau_avg"],
    "Def_Eng": ["Def_Eng", "def_eng", "deformation_energy"],
    "beta_avg": ["beta_avg"],
    "nuc_count": ["nuc_count"],
    "nuc_rate": ["nuc_rate"],
    "nuc_insertions": ["nuc_insertions", "insertions"],
    "nuc_deletions": ["nuc_deletions", "deletions"],
    "P_nuc_avg": ["P_nuc_avg", "pnuc_avg", "p_nuc_avg"],
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
    "grain_count_early": ["grain_count_early"],
    "grain_count_established": ["grain_count_established"],
    "grain_count_bnds_070": ["grain_count_bnds_070", "grain_count_bnds_07"],
    "grain_count_bnds_080": ["grain_count_bnds_080", "grain_count_bnds_08"],
    "avg_grain_area": [
        "avg_grain_area",
        "average_grain_volume",
        "avg_grain_volume",
    ],
    "gb_length": ["gb_length", "grain_boundary_area", "grain_boundary_length"],
    "dt_actual": ["dt_actual", "timestep_size"],
    "dtnuc": ["dtnuc"],
}


KEY_TIME_METRICS: list[tuple[str, str]] = [
    ("cumulative_insertions", "cumulative nucleus insertions"),
    ("cumulative_deletions", "cumulative nucleus deletions"),
    ("active_nucleus_sites", "active nucleus sites"),
    ("grain_count_early", "early connected-grain count"),
    ("grain_count_established", "established connected-grain count"),
    ("active_stable_grain_ids", "active stable GrainTracker IDs"),
    ("active_new_grain_ids", "active new stable grain IDs"),
    ("D_norm", "normalized average equivalent diameter, D/D0"),
    ("gb_length", "grain-boundary length"),
    ("rho_avg", r"average dislocation density, $\rho$"),
    ("rho_eff_avg", r"average effective dislocation density, $\rho_{eff}$"),
    ("P_nuc_avg", "average nucleation probability/rate density"),
    ("nuc_drive_ratio_avg", "average nucleation driving ratio"),
    ("nuc_drive_ratio_max", "maximum nucleation driving ratio"),
    ("energy_preferred_fraction", "energy-preferred domain fraction"),
    ("eligible_nucleation_fraction", "eligible nucleation-region fraction"),
]


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------


def clean_name(value: str) -> str:
    return re.sub(r"[^a-zA-Z0-9]+", "", str(value)).lower()


def find_column(df: pd.DataFrame, candidates: Iterable[str]) -> str | None:
    lookup = {clean_name(col): col for col in df.columns}
    for candidate in candidates:
        found = lookup.get(clean_name(candidate))
        if found is not None:
            return found
    return None


def to_numeric(series: pd.Series) -> pd.Series:
    return pd.to_numeric(series, errors="coerce").replace([np.inf, -np.inf], np.nan)


def first_finite(series: pd.Series, positive: bool = False) -> float:
    values = to_numeric(series).dropna()
    if positive:
        values = values[values > 0]
    return float(values.iloc[0]) if not values.empty else np.nan


def last_finite(series: pd.Series) -> float:
    values = to_numeric(series).dropna()
    return float(values.iloc[-1]) if not values.empty else np.nan


def max_finite(series: pd.Series) -> float:
    values = to_numeric(series).dropna()
    return float(values.max()) if not values.empty else np.nan


def min_finite(series: pd.Series) -> float:
    values = to_numeric(series).dropna()
    return float(values.min()) if not values.empty else np.nan


def mean_finite(series: pd.Series) -> float:
    values = to_numeric(series).dropna()
    return float(values.mean()) if not values.empty else np.nan


def median_finite(series: pd.Series) -> float:
    values = to_numeric(series).dropna()
    return float(values.median()) if not values.empty else np.nan


def safe_divide(numerator: float, denominator: float) -> float:
    if not np.isfinite(numerator) or not np.isfinite(denominator) or denominator == 0:
        return np.nan
    return float(numerator / denominator)


def parse_value(text: str) -> Any:
    stripped = text.strip()
    try:
        return float(stripped)
    except ValueError:
        return stripped


def read_case_settings(case_dir: Path) -> dict[str, Any]:
    settings: dict[str, Any] = {}
    path = case_dir / "case_settings.txt"
    if not path.exists():
        return settings

    for raw_line in path.read_text(errors="replace").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        settings[key.strip()] = parse_value(value)
    return settings


def parse_tag_number(text: str) -> float:
    prepared = str(text).replace("p", ".").replace(",", ".")
    match = re.search(r"[-+]?\d*\.?\d+(?:e[-+]?\d+)?", prepared, re.IGNORECASE)
    return float(match.group(0)) if match else np.nan


def parse_metadata_from_path(path: Path) -> dict[str, Any]:
    metadata: dict[str, Any] = {
        "factor_name": "unknown",
        "factor_n_i": np.nan,
        "T_i": np.nan,
        "strain_rate_i": np.nan,
        "rho_init_i": np.nan,
    }

    for part in path.parts:
        low = part.lower()
        if low.startswith("factor_"):
            tokens = part.split("_")
            # Example: factor_medium_0p3_T_873_gdot_100p0
            if len(tokens) >= 3:
                metadata["factor_name"] = tokens[1]
                metadata["factor_n_i"] = parse_tag_number(tokens[2])
        if low.startswith("rho_"):
            metadata["rho_init_i"] = parse_tag_number(part)

    joined = "_".join(path.parts)
    t_match = re.search(r"(?:^|_)T_(\d+(?:p\d+)?)", joined)
    r_match = re.search(r"(?:^|_)gdot_([0-9epm+\-.]+)", joined)
    if t_match:
        metadata["T_i"] = parse_tag_number(t_match.group(1))
    if r_match:
        metadata["strain_rate_i"] = parse_tag_number(r_match.group(1))

    return metadata


def equivalent_diameter_from_area(area: pd.Series) -> pd.Series:
    values = to_numeric(area)
    values = values.where(values > 0)
    return 2.0 * np.sqrt(values / np.pi)


def safe_tag(value: Any) -> str:
    if isinstance(value, str):
        text = value
    elif np.isfinite(value):
        text = f"{value:g}"
    else:
        text = "unknown"
    return text.replace("+", "").replace("-", "m").replace(".", "p")


@dataclass
class VPPResult:
    timeline: pd.DataFrame
    births: pd.DataFrame
    initial_ids: set[int]
    warnings: list[str]


# -----------------------------------------------------------------------------
# Scalar CSV loading
# -----------------------------------------------------------------------------


def load_scalar_case(csv_path: Path, initial_grains: int) -> tuple[pd.DataFrame, list[str]]:
    warnings: list[str] = []
    raw = pd.read_csv(csv_path)

    time_col = find_column(raw, ALIASES["time"])
    if time_col is None:
        raise ValueError(f"No time column found in {csv_path}")

    case_dir = csv_path.parent
    settings = read_case_settings(case_dir)
    path_metadata = parse_metadata_from_path(case_dir)

    canonical = pd.DataFrame()
    canonical["time"] = to_numeric(raw[time_col])

    for canonical_name, aliases in ALIASES.items():
        if canonical_name == "time":
            continue
        source = find_column(raw, aliases)
        canonical[canonical_name] = to_numeric(raw[source]) if source else np.nan
        if source is None:
            warnings.append(f"{case_dir.name}: missing scalar column '{canonical_name}'")

    # Metadata: case_settings takes precedence over path and CSV values.
    factor_name = settings.get("factor_name", path_metadata["factor_name"])
    factor_value = settings.get("factor_n_i", path_metadata["factor_n_i"])
    T = settings.get("T_i", path_metadata["T_i"])
    rate = settings.get("strain_rate_i", path_metadata["strain_rate_i"])
    rho_init = settings.get("rho_init_i", path_metadata["rho_init_i"])
    hold_time = settings.get("hold_time_i", np.nan)
    hold_strain = settings.get("hold_strain", settings.get("hold_strain_i", np.nan))

    # Fall back to nonzero CSV values when metadata are unavailable.
    if not isinstance(T, (int, float)) or not np.isfinite(T):
        T = first_finite(canonical["T_avg"], positive=True)
    if not isinstance(rate, (int, float)) or not np.isfinite(rate):
        rate = first_finite(canonical["gdot_avg"], positive=True)

    canonical["factor_name"] = str(factor_name)
    canonical["factor_n_i"] = float(factor_value) if isinstance(factor_value, (int, float)) else np.nan
    canonical["T_i"] = float(T) if isinstance(T, (int, float)) else np.nan
    canonical["strain_rate_i"] = float(rate) if isinstance(rate, (int, float)) else np.nan
    canonical["rho_init_i"] = float(rho_init) if isinstance(rho_init, (int, float)) else np.nan
    canonical["hold_time_i"] = float(hold_time) if isinstance(hold_time, (int, float)) else np.nan
    canonical["hold_strain"] = float(hold_strain) if isinstance(hold_strain, (int, float)) else np.nan
    canonical["case_name"] = case_dir.name
    canonical["case_dir"] = str(case_dir)
    canonical["source_file"] = str(csv_path)

    canonical["accumulated_strain"] = canonical["strain_rate_i"] * canonical["time"]

    canonical["nuc_insertions"] = canonical["nuc_insertions"].fillna(0.0)
    canonical["nuc_deletions"] = canonical["nuc_deletions"].fillna(0.0)
    canonical["active_nucleus_sites"] = canonical["nuc_count"]
    canonical["cumulative_insertions"] = canonical["nuc_insertions"].cumsum()
    canonical["cumulative_deletions"] = canonical["nuc_deletions"].cumsum()
    canonical["net_insertions"] = canonical["cumulative_insertions"] - canonical["cumulative_deletions"]

    canonical["D_avg"] = equivalent_diameter_from_area(canonical["avg_grain_area"])
    D0 = first_finite(canonical["D_avg"], positive=True)
    canonical["D0"] = D0
    canonical["D_norm"] = canonical["D_avg"] / D0 if np.isfinite(D0) and D0 > 0 else np.nan

    for count_name in ["grain_count_early", "grain_count_established"]:
        canonical[f"new_{count_name}"] = (canonical[count_name] - initial_grains).clip(lower=0)

    canonical = canonical.sort_values("time").reset_index(drop=True)
    return canonical, warnings


# -----------------------------------------------------------------------------
# GrainTracker VPP loading
# -----------------------------------------------------------------------------


def locate_grain_feature_files(case_dir: Path, vpp_name: str) -> list[Path]:
    patterns = [
        f"result_{vpp_name}_[0-9][0-9][0-9][0-9].csv",
        f"*_{vpp_name}_[0-9][0-9][0-9][0-9].csv",
        "result_grain_features_[0-9][0-9][0-9][0-9].csv",
        "result_grain_volumes_[0-9][0-9][0-9][0-9].csv",
        "*grain_features_[0-9][0-9][0-9][0-9].csv",
        "*grain_volumes_[0-9][0-9][0-9][0-9].csv",
    ]
    found: set[Path] = set()
    for pattern in patterns:
        found.update(case_dir.glob(pattern))
    return sorted(found, key=lambda p: serial_from_vpp_name(p.name))


def serial_from_vpp_name(name: str) -> int:
    match = re.search(r"_(\d{4,})\.csv$", name)
    return int(match.group(1)) if match else -1


def read_one_feature_vpp(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    var_col = find_column(df, ["var_num"])
    vol_col = find_column(df, ["feature_volumes", "feature_volume", "volume", "area"])
    if var_col is None or vol_col is None:
        raise ValueError(f"VPP file lacks var_num or feature volume: {path}")

    out = pd.DataFrame()
    out["grain_id"] = np.arange(len(df), dtype=int)
    out["var_num"] = to_numeric(df[var_col])
    out["area"] = to_numeric(df[vol_col])

    for coord in ["x", "y", "z"]:
        col = find_column(df, [f"centroid_{coord}"])
        out[f"centroid_{coord}"] = to_numeric(df[col]) if col else np.nan

    bounds_col = find_column(df, ["intersects_bounds", "intersects_boundary"])
    out["intersects_bounds"] = to_numeric(df[bounds_col]) if bounds_col else np.nan

    # Preserve stable row IDs but exclude inactive rows and zero-area artifacts.
    out = out[(out["var_num"] != -1) & (out["area"] > 0)].copy()
    out["D"] = 2.0 * np.sqrt(out["area"] / np.pi)
    return out


def map_vpp_serial_to_time(serial: int, scalar: pd.DataFrame) -> tuple[float, float]:
    if scalar.empty:
        return np.nan, np.nan
    idx = min(max(serial, 0), len(scalar) - 1)
    return float(scalar.iloc[idx]["time"]), float(scalar.iloc[idx]["accumulated_strain"])


def load_grain_vpp(
    case_dir: Path,
    scalar: pd.DataFrame,
    vpp_name: str,
    hold_time: float,
) -> VPPResult:
    warnings: list[str] = []
    files = locate_grain_feature_files(case_dir, vpp_name)
    if not files:
        return VPPResult(pd.DataFrame(), pd.DataFrame(), set(), [f"{case_dir.name}: no grain-feature VPP files"])

    snapshots: list[pd.DataFrame] = []
    for path in files:
        try:
            snap = read_one_feature_vpp(path)
        except Exception as exc:  # noqa: BLE001
            warnings.append(f"{case_dir.name}: failed to read {path.name}: {exc}")
            continue
        serial = serial_from_vpp_name(path.name)
        time, strain = map_vpp_serial_to_time(serial, scalar)
        snap["serial"] = serial
        snap["time"] = time
        snap["accumulated_strain"] = strain
        snap["vpp_file"] = str(path)
        snapshots.append(snap)

    if not snapshots:
        return VPPResult(pd.DataFrame(), pd.DataFrame(), set(), warnings)

    all_features = pd.concat(snapshots, ignore_index=True)
    first_serial = int(all_features["serial"].min())
    initial_ids = set(
        all_features.loc[all_features["serial"] == first_serial, "grain_id"].astype(int).tolist()
    )

    timeline_rows: list[dict[str, Any]] = []
    for serial, group in all_features.groupby("serial", sort=True):
        active_ids = set(group["grain_id"].astype(int).tolist())
        new_ids = active_ids - initial_ids
        timeline_rows.append(
            {
                "serial": int(serial),
                "time": float(group["time"].iloc[0]),
                "accumulated_strain": float(group["accumulated_strain"].iloc[0]),
                "active_stable_grain_ids": len(active_ids),
                "active_new_grain_ids": len(new_ids),
                "mean_individual_grain_D": float(group["D"].mean()) if not group.empty else np.nan,
                "median_individual_grain_D": float(group["D"].median()) if not group.empty else np.nan,
                "D10": float(group["D"].quantile(0.10)) if not group.empty else np.nan,
                "D50": float(group["D"].quantile(0.50)) if not group.empty else np.nan,
                "D90": float(group["D"].quantile(0.90)) if not group.empty else np.nan,
            }
        )
    timeline = pd.DataFrame(timeline_rows).sort_values("serial").reset_index(drop=True)

    birth_rows: list[dict[str, Any]] = []
    for grain_id, history in all_features.groupby("grain_id", sort=True):
        grain_id_int = int(grain_id)
        if grain_id_int in initial_ids:
            continue
        history = history.sort_values("serial")
        birth = history.iloc[0]
        active_times = history["time"].to_numpy(dtype=float)
        birth_time = float(birth["time"])
        survived_hold = False
        if np.isfinite(hold_time):
            survived_hold = bool(np.any(active_times >= birth_time + hold_time - 1e-14))
        birth_rows.append(
            {
                "grain_id": grain_id_int,
                "birth_serial": int(birth["serial"]),
                "birth_time": birth_time,
                "birth_strain": float(birth["accumulated_strain"]),
                "last_active_time": float(history["time"].max()),
                "last_active_strain": float(history["accumulated_strain"].max()),
                "active_output_count": int(len(history)),
                "area_at_birth": float(birth["area"]),
                "D_at_birth": float(birth["D"]),
                "centroid_x": float(birth["centroid_x"]) if np.isfinite(birth["centroid_x"]) else np.nan,
                "centroid_y": float(birth["centroid_y"]) if np.isfinite(birth["centroid_y"]) else np.nan,
                "centroid_z": float(birth["centroid_z"]) if np.isfinite(birth["centroid_z"]) else np.nan,
                "survived_beyond_hold_time": survived_hold,
                "active_at_final_output": bool(int(history["serial"].max()) == int(all_features["serial"].max())),
            }
        )

    births = pd.DataFrame(birth_rows)
    return VPPResult(timeline, births, initial_ids, warnings)


# -----------------------------------------------------------------------------
# Event audit and case summary
# -----------------------------------------------------------------------------


def insertion_event_audit(scalar: pd.DataFrame, tolerance: float) -> pd.DataFrame:
    rows: list[dict[str, Any]] = []
    insertion_indices = scalar.index[scalar["nuc_insertions"].fillna(0) > 0].tolist()

    drive_col = None
    if scalar["nuc_drive_ratio_max"].notna().any():
        drive_col = "nuc_drive_ratio_max"
    elif scalar["nuc_drive_ratio_avg"].notna().any():
        drive_col = "nuc_drive_ratio_avg"

    for idx in insertion_indices:
        pre_idx = max(idx - 1, 0)
        current = scalar.loc[idx]
        previous = scalar.loc[pre_idx]
        pre_drive = float(previous[drive_col]) if drive_col and np.isfinite(previous[drive_col]) else np.nan
        pre_unfav = (
            float(previous["P_nuc_unfavorable_max"])
            if np.isfinite(previous["P_nuc_unfavorable_max"])
            else np.nan
        )
        gate_pass = (
            (not np.isfinite(pre_drive) or pre_drive >= 1.0 - tolerance)
            and (not np.isfinite(pre_unfav) or abs(pre_unfav) <= tolerance)
        )
        rows.append(
            {
                "case_name": current["case_name"],
                "factor_name": current["factor_name"],
                "factor_n_i": current["factor_n_i"],
                "T_i": current["T_i"],
                "strain_rate_i": current["strain_rate_i"],
                "event_time": current["time"],
                "event_strain": current["accumulated_strain"],
                "insertions_this_output": current["nuc_insertions"],
                "pre_event_drive_metric": drive_col or "unavailable",
                "pre_event_drive_value": pre_drive,
                "pre_event_P_nuc_unfavorable_max": pre_unfav,
                "scalar_energy_gate_audit_pass": gate_pass,
                "note": "Scalar/global pre-event audit; local centroid audit requires field sampling.",
            }
        )
    return pd.DataFrame(rows)


def build_case_summary(
    scalar: pd.DataFrame,
    vpp: VPPResult,
    initial_grains: int,
    tolerance: float,
) -> dict[str, Any]:
    first = scalar.iloc[0]
    total_insertions = float(scalar["nuc_insertions"].fillna(0).sum())
    total_deletions = float(scalar["nuc_deletions"].fillna(0).sum())
    final_insertions = last_finite(scalar["cumulative_insertions"])
    final_deletions = last_finite(scalar["cumulative_deletions"])

    summary: dict[str, Any] = {
        "case_name": first["case_name"],
        "case_dir": first["case_dir"],
        "factor_name": first["factor_name"],
        "factor_n_i": first["factor_n_i"],
        "T_i": first["T_i"],
        "strain_rate_i": first["strain_rate_i"],
        "rho_init_i": first["rho_init_i"],
        "hold_time_i": first["hold_time_i"],
        "hold_strain": first["hold_strain"],
        "final_time": last_finite(scalar["time"]),
        "final_strain": last_finite(scalar["accumulated_strain"]),
        "total_insertions": total_insertions,
        "total_deletions": total_deletions,
        "net_insertion_events": total_insertions - total_deletions,
        "deletion_fraction": safe_divide(total_deletions, total_insertions),
        "final_active_nucleus_sites": last_finite(scalar["active_nucleus_sites"]),
        "max_active_nucleus_sites": max_finite(scalar["active_nucleus_sites"]),
        "final_grain_count_early": last_finite(scalar["grain_count_early"]),
        "max_grain_count_early": max_finite(scalar["grain_count_early"]),
        "final_grain_count_established": last_finite(scalar["grain_count_established"]),
        "max_grain_count_established": max_finite(scalar["grain_count_established"]),
        "new_grain_count_early_proxy_max": max(
            0.0,
            max_finite(scalar["grain_count_early"]) - initial_grains,
        )
        if np.isfinite(max_finite(scalar["grain_count_early"]))
        else np.nan,
        "new_grain_count_established_proxy_max": max(
            0.0,
            max_finite(scalar["grain_count_established"]) - initial_grains,
        )
        if np.isfinite(max_finite(scalar["grain_count_established"]))
        else np.nan,
        "D0": first_finite(scalar["D_avg"], positive=True),
        "D_final": last_finite(scalar["D_avg"]),
        "D_norm_final": last_finite(scalar["D_norm"]),
        "D_norm_min": min_finite(scalar["D_norm"]),
        "D_norm_max": max_finite(scalar["D_norm"]),
        "gb_length_initial": first_finite(scalar["gb_length"], positive=True),
        "gb_length_final": last_finite(scalar["gb_length"]),
        "gb_length_max": max_finite(scalar["gb_length"]),
        "rho_avg_initial": first_finite(scalar["rho_avg"], positive=True),
        "rho_avg_final": last_finite(scalar["rho_avg"]),
        "rho_avg_max": max_finite(scalar["rho_avg"]),
        "rho_eff_avg_final": last_finite(scalar["rho_eff_avg"]),
        "P_nuc_avg_mean": mean_finite(scalar["P_nuc_avg"]),
        "P_nuc_avg_max": max_finite(scalar["P_nuc_avg"]),
        "drive_ratio_avg_final": last_finite(scalar["nuc_drive_ratio_avg"]),
        "drive_ratio_avg_max": max_finite(scalar["nuc_drive_ratio_avg"]),
        "drive_ratio_max_max": max_finite(scalar["nuc_drive_ratio_max"]),
        "energy_preferred_fraction_max": max_finite(scalar["energy_preferred_fraction"]),
        "eligible_nucleation_fraction_max": max_finite(scalar["eligible_nucleation_fraction"]),
        "P_nuc_unfavorable_max_max": max_finite(scalar["P_nuc_unfavorable_max"]),
        "P_nuc_unfavorable_integral_max_abs": max_finite(
            scalar["P_nuc_unfavorable_integral"].abs()
        ),
    }

    summary["gb_length_ratio_final"] = safe_divide(
        summary["gb_length_final"], summary["gb_length_initial"]
    )

    gate_max = summary["P_nuc_unfavorable_max_max"]
    gate_int = summary["P_nuc_unfavorable_integral_max_abs"]
    summary["energy_gate_violation"] = bool(
        (np.isfinite(gate_max) and abs(gate_max) > tolerance)
        or (np.isfinite(gate_int) and abs(gate_int) > tolerance)
    )

    max_drive = summary["drive_ratio_max_max"]
    if not np.isfinite(max_drive):
        max_drive = summary["drive_ratio_avg_max"]
    summary["energy_eligible_somewhere"] = bool(np.isfinite(max_drive) and max_drive >= 1.0 - tolerance)

    if not vpp.timeline.empty:
        summary["initial_stable_grain_ids"] = len(vpp.initial_ids)
        summary["final_active_stable_grain_ids"] = int(
            vpp.timeline.iloc[-1]["active_stable_grain_ids"]
        )
        summary["max_active_stable_grain_ids"] = int(
            vpp.timeline["active_stable_grain_ids"].max()
        )
        summary["distinct_new_grain_ids"] = int(len(vpp.births))
        summary["surviving_new_grain_ids"] = int(
            vpp.births["survived_beyond_hold_time"].sum()
        ) if not vpp.births.empty else 0
        summary["final_active_new_grain_ids"] = int(
            vpp.timeline.iloc[-1]["active_new_grain_ids"]
        )
    else:
        summary["initial_stable_grain_ids"] = np.nan
        summary["final_active_stable_grain_ids"] = np.nan
        summary["max_active_stable_grain_ids"] = np.nan
        summary["distinct_new_grain_ids"] = np.nan
        summary["surviving_new_grain_ids"] = np.nan
        summary["final_active_new_grain_ids"] = np.nan

    # Prefer stable-ID counts; fall back to FeatureFloodCount proxies.
    formed = summary["distinct_new_grain_ids"]
    if not np.isfinite(formed):
        formed = summary["new_grain_count_established_proxy_max"]
    survived = summary["surviving_new_grain_ids"]
    if not np.isfinite(survived):
        survived = summary["new_grain_count_established_proxy_max"]

    summary["grain_formation_efficiency"] = safe_divide(formed, total_insertions)
    summary["grain_survival_efficiency"] = safe_divide(survived, total_insertions)

    if summary["energy_gate_violation"]:
        classification = "invalid_energy_gate_audit"
    elif not summary["energy_eligible_somewhere"]:
        classification = "energy_barrier_not_reached"
    elif total_insertions <= 0:
        classification = "energy_eligible_but_no_insertions"
    elif formed <= 0:
        classification = "insertions_without_detected_new_grain"
    elif survived <= 0:
        classification = "new_grains_detected_but_not_surviving"
    else:
        classification = "nucleation_and_survival_detected"

    # Identify obvious curvature-driven coarsening separately.
    if (
        classification in {"energy_barrier_not_reached", "energy_eligible_but_no_insertions"}
        and np.isfinite(summary["D_norm_final"])
        and summary["D_norm_final"] > 1.2
        and np.isfinite(summary["gb_length_ratio_final"])
        and summary["gb_length_ratio_final"] < 0.5
    ):
        classification = "coarsening_dominated_without_nucleation"

    summary["case_classification"] = classification
    return summary


# -----------------------------------------------------------------------------
# Factor aggregation and calibration ranking
# -----------------------------------------------------------------------------


def aggregate_factors(case_summary: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, Any]] = []
    group_cols = ["factor_name", "factor_n_i"]

    for keys, group in case_summary.groupby(group_cols, dropna=False):
        factor_name, factor_value = keys
        eligible = group["energy_eligible_somewhere"].fillna(False)
        insertions = group["total_insertions"].fillna(0) > 0
        births = group["distinct_new_grain_ids"]
        birth_proxy = births.where(births.notna(), group["new_grain_count_established_proxy_max"])
        survivors = group["surviving_new_grain_ids"]
        survivor_proxy = survivors.where(
            survivors.notna(), group["new_grain_count_established_proxy_max"]
        )

        total_insertions = float(group["total_insertions"].fillna(0).sum())
        total_deletions = float(group["total_deletions"].fillna(0).sum())
        total_births = float(birth_proxy.fillna(0).sum())
        total_survivors = float(survivor_proxy.fillna(0).sum())
        eligible_cases = int(eligible.sum())
        eligible_no_insertions = int((eligible & ~insertions).sum())

        row = {
            "factor_name": factor_name,
            "factor_n_i": factor_value,
            "case_count": int(len(group)),
            "energy_eligible_case_count": eligible_cases,
            "insertion_case_count": int(insertions.sum()),
            "new_grain_case_count": int((birth_proxy.fillna(0) > 0).sum()),
            "survivor_case_count": int((survivor_proxy.fillna(0) > 0).sum()),
            "energy_gate_violation_case_count": int(group["energy_gate_violation"].sum()),
            "eligible_no_insertion_case_count": eligible_no_insertions,
            "eligible_no_insertion_fraction": safe_divide(eligible_no_insertions, eligible_cases),
            "total_insertions": total_insertions,
            "total_deletions": total_deletions,
            "overall_deletion_fraction": safe_divide(total_deletions, total_insertions),
            "total_distinct_new_grains_or_proxy": total_births,
            "total_surviving_new_grains_or_proxy": total_survivors,
            "overall_formation_efficiency": safe_divide(total_births, total_insertions),
            "overall_survival_efficiency": safe_divide(total_survivors, total_insertions),
            "median_case_deletion_fraction": median_finite(group["deletion_fraction"]),
            "mean_final_D_norm": mean_finite(group["D_norm_final"]),
            "median_final_D_norm": median_finite(group["D_norm_final"]),
            "mean_final_gb_length_ratio": mean_finite(group["gb_length_ratio_final"]),
        }

        if row["energy_gate_violation_case_count"] > 0:
            assessment = "reject: energy-gate audit violation"
        elif eligible_cases > 0 and row["eligible_no_insertion_fraction"] >= 0.5:
            assessment = "likely too low: many eligible cases never insert"
        elif total_insertions > 0 and (
            (np.isfinite(row["overall_survival_efficiency"]) and row["overall_survival_efficiency"] < 0.05)
            or (np.isfinite(row["overall_deletion_fraction"]) and row["overall_deletion_fraction"] > 0.9)
        ):
            assessment = "poor survival: many events but few persistent grains"
        elif row["survivor_case_count"] > 0:
            assessment = "promising: validate with longer strain"
        else:
            assessment = "inconclusive: inspect case plots"

        row["screening_assessment"] = assessment
        rows.append(row)

    return pd.DataFrame(rows).sort_values(["factor_n_i", "factor_name"]).reset_index(drop=True)


def rank_factors(factor_summary: pd.DataFrame) -> pd.DataFrame:
    if factor_summary.empty:
        return factor_summary

    ranked = factor_summary.copy()
    # Transparent lexicographic ranking rather than a hidden weighted score.
    ranked["rank_gate_violations"] = ranked["energy_gate_violation_case_count"]
    ranked["rank_missing_insertions"] = ranked["eligible_no_insertion_fraction"].fillna(1.0)
    ranked["rank_negative_survival"] = -ranked["overall_survival_efficiency"].fillna(0.0)
    ranked["rank_deletion_fraction"] = ranked["overall_deletion_fraction"].fillna(1.0)

    ranked = ranked.sort_values(
        [
            "rank_gate_violations",
            "rank_missing_insertions",
            "rank_negative_survival",
            "rank_deletion_fraction",
            "factor_n_i",
        ]
    ).reset_index(drop=True)
    ranked.insert(0, "screening_rank", np.arange(1, len(ranked) + 1))
    return ranked


# -----------------------------------------------------------------------------
# Plotting
# -----------------------------------------------------------------------------


def save_line_plot(
    data: pd.DataFrame,
    x_col: str,
    y_col: str,
    ylabel: str,
    title: str,
    legend_col: str,
    out_path: Path,
) -> None:
    if y_col not in data.columns or data[y_col].notna().sum() == 0:
        return
    plt.figure()
    for value, curve in data.groupby(legend_col, dropna=False):
        curve = curve.sort_values(x_col)
        plt.plot(curve[x_col], curve[y_col], label=f"{value:g}" if isinstance(value, (int, float)) else str(value))
    plt.xlabel("accumulated strain" if x_col == "accumulated_strain" else "time, s")
    plt.ylabel(ylabel)
    plt.title(title)
    plt.legend(title="strain rate, 1/s" if legend_col == "strain_rate_i" else "temperature, K")
    plt.tight_layout()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(out_path, dpi=200)
    plt.close()


def plot_time_histories(history: pd.DataFrame, out_dir: Path) -> None:
    plots_root = out_dir / "plots" / "time_histories"
    for (factor_name, factor_value), factor_data in history.groupby(
        ["factor_name", "factor_n_i"], dropna=False
    ):
        factor_tag = f"{safe_tag(factor_name)}_{safe_tag(factor_value)}"
        for metric, ylabel in KEY_TIME_METRICS:
            if metric not in factor_data.columns or factor_data[metric].notna().sum() == 0:
                continue

            for T, group_T in factor_data.groupby("T_i"):
                save_line_plot(
                    group_T,
                    "accumulated_strain",
                    metric,
                    ylabel,
                    f"{ylabel}; factor={factor_value:g}, T={T:g} K",
                    "strain_rate_i",
                    plots_root / factor_tag / f"{metric}_fixed_T" / f"T_{safe_tag(T)}.png",
                )

            for rate, group_rate in factor_data.groupby("strain_rate_i"):
                save_line_plot(
                    group_rate,
                    "accumulated_strain",
                    metric,
                    ylabel,
                    f"{ylabel}; factor={factor_value:g}, strain rate={rate:g} 1/s",
                    "T_i",
                    plots_root / factor_tag / f"{metric}_fixed_rate" / f"gdot_{safe_tag(rate)}.png",
                )


def heatmap(
    summary: pd.DataFrame,
    value_col: str,
    title: str,
    label: str,
    out_path: Path,
    log10: bool = False,
) -> None:
    if value_col not in summary.columns or summary[value_col].notna().sum() == 0:
        return
    pivot = summary.pivot_table(
        index="T_i",
        columns="strain_rate_i",
        values=value_col,
        aggfunc="mean",
    ).sort_index().sort_index(axis=1)
    if pivot.empty:
        return

    values = pivot.to_numpy(dtype=float)
    display_values = values.copy()
    if log10:
        display_values = np.where(values > 0, np.log10(values), np.nan)

    masked = np.ma.masked_invalid(display_values)
    plt.figure()
    image = plt.imshow(masked, origin="lower", aspect="auto")
    plt.colorbar(image, label=(f"log10({label})" if log10 else label))
    plt.xticks(np.arange(len(pivot.columns)), [f"{x:g}" for x in pivot.columns], rotation=45)
    plt.yticks(np.arange(len(pivot.index)), [f"{x:g}" for x in pivot.index])
    plt.xlabel("strain rate, 1/s")
    plt.ylabel("temperature, K")
    plt.title(title)

    for i in range(pivot.shape[0]):
        for j in range(pivot.shape[1]):
            original = values[i, j]
            if np.isfinite(original):
                plt.text(j, i, f"{original:.2g}", ha="center", va="center")

    plt.tight_layout()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(out_path, dpi=220)
    plt.close()


def plot_heatmaps(case_summary: pd.DataFrame, out_dir: Path) -> None:
    metrics = [
        ("total_insertions", "summed nucleus insertions", False),
        ("total_deletions", "summed nucleus deletions", False),
        ("distinct_new_grain_ids", "distinct new stable grain IDs", False),
        ("surviving_new_grain_ids", "new stable grain IDs surviving hold time", False),
        ("grain_formation_efficiency", "grain-formation efficiency", False),
        ("grain_survival_efficiency", "grain-survival efficiency", False),
        ("D_norm_final", "final D/D0", False),
        ("gb_length_final", "final grain-boundary length", True),
        ("rho_avg_final", "final rho_avg", True),
        ("P_nuc_avg_max", "maximum P_nuc_avg", True),
        ("drive_ratio_max_max", "maximum nucleation driving ratio", False),
        ("eligible_nucleation_fraction_max", "maximum eligible-region fraction", False),
    ]

    for (factor_name, factor_value), group in case_summary.groupby(
        ["factor_name", "factor_n_i"], dropna=False
    ):
        factor_tag = f"{safe_tag(factor_name)}_{safe_tag(factor_value)}"
        for metric, label, use_log in metrics:
            heatmap(
                group,
                metric,
                f"{label}; factor={factor_value:g}",
                label,
                out_dir / "plots" / "heatmaps" / factor_tag / f"{metric}.png",
                log10=use_log,
            )


def plot_factor_comparisons(case_summary: pd.DataFrame, out_dir: Path) -> None:
    metrics = [
        ("total_insertions", "total insertions"),
        ("distinct_new_grain_ids", "distinct new stable grain IDs"),
        ("surviving_new_grain_ids", "new grains surviving hold time"),
        ("grain_survival_efficiency", "grain-survival efficiency"),
        ("D_norm_final", "final D/D0"),
        ("deletion_fraction", "deletion fraction"),
    ]

    for (T, rate), physical_case in case_summary.groupby(["T_i", "strain_rate_i"]):
        physical_case = physical_case.sort_values("factor_n_i")
        labels = [f"{name}\n{value:g}" for name, value in zip(
            physical_case["factor_name"], physical_case["factor_n_i"]
        )]
        x = np.arange(len(labels))
        for metric, ylabel in metrics:
            if metric not in physical_case.columns or physical_case[metric].notna().sum() == 0:
                continue
            plt.figure()
            plt.bar(x, physical_case[metric])
            plt.xticks(x, labels)
            plt.xlabel("global nucleation factor")
            plt.ylabel(ylabel)
            plt.title(f"{ylabel}; T={T:g} K, strain rate={rate:g} 1/s")
            plt.tight_layout()
            path = (
                out_dir
                / "plots"
                / "factor_comparisons"
                / metric
                / f"T_{safe_tag(T)}_gdot_{safe_tag(rate)}.png"
            )
            path.parent.mkdir(parents=True, exist_ok=True)
            plt.savefig(path, dpi=200)
            plt.close()


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------


def discover_result_csvs(root: Path) -> list[Path]:
    files = sorted(root.rglob("result.csv"))
    if files:
        return files
    # Conservative fallback: exclude analysis/status/VPP CSV files.
    candidates: list[Path] = []
    for path in root.rglob("*.csv"):
        low_parts = {part.lower() for part in path.parts}
        if "analysis" in low_parts or "status" in low_parts or "logs" in low_parts:
            continue
        if re.search(r"_(grain_features|grain_volumes)_\d{4,}\.csv$", path.name):
            continue
        try:
            header = pd.read_csv(path, nrows=1)
        except Exception:  # noqa: BLE001
            continue
        if find_column(header, ALIASES["time"]):
            candidates.append(path)
    return sorted(candidates)


def write_recommendation(ranking: pd.DataFrame, path: Path) -> None:
    lines = [
        "NUCLEATION CALIBRATION SCREENING RECOMMENDATION",
        "",
        "This ranking is a screening aid, not an automatic physical calibration.",
        "Factors are ordered by: zero energy-gate violations, fewer eligible cases",
        "without insertions, higher survival efficiency, and lower deletion fraction.",
        "",
    ]
    for _, row in ranking.iterrows():
        lines.extend(
            [
                f"Rank {int(row['screening_rank'])}: {row['factor_name']} "
                f"(factor_n={row['factor_n_i']:g})",
                f"  Assessment: {row['screening_assessment']}",
                f"  Eligible cases: {int(row['energy_eligible_case_count'])}",
                f"  Cases with insertions: {int(row['insertion_case_count'])}",
                f"  Cases with surviving grains: {int(row['survivor_case_count'])}",
                f"  Eligible-no-insertion fraction: {row['eligible_no_insertion_fraction']:.3g}",
                f"  Overall deletion fraction: {row['overall_deletion_fraction']:.3g}",
                f"  Overall formation efficiency: {row['overall_formation_efficiency']:.3g}",
                f"  Overall survival efficiency: {row['overall_survival_efficiency']:.3g}",
                "",
            ]
        )
    lines.extend(
        [
            "Selection rule:",
            "  1. Reject any factor with an energy-gate audit violation.",
            "  2. A factor is too low when many energetically eligible cases have no insertions.",
            "  3. A factor is poor when insertions occur but almost no new stable grains survive.",
            "  4. Validate the best one or two factors with a longer total strain before the full sweep.",
            "",
            "Important limitation:",
            "  Scalar postprocessors verify the global energy gate. Confirming the exact local",
            "  energy at each new-grain centroid requires sampling the Exodus fields in the",
            "  pre-birth frame (for example in ParaView or a dedicated PyVista script).",
        ]
    )
    path.write_text("\n".join(lines))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Analyze and compare MOOSE discrete-nucleation calibration cases."
    )
    parser.add_argument(
        "--root",
        type=Path,
        required=True,
        help="Root folder containing case directories and result.csv files.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=None,
        help="Analysis output directory. Default: ROOT/analysis",
    )
    parser.add_argument(
        "--initial-grains",
        type=int,
        default=4,
        help="Number of initial grains used for FeatureFloodCount proxies.",
    )
    parser.add_argument(
        "--vpp-name",
        type=str,
        default="grain_features",
        help="FeatureVolumeVectorPostprocessor block name.",
    )
    parser.add_argument(
        "--energy-tolerance",
        type=float,
        default=1e-12,
        help="Tolerance for P_nuc_unfavorable audit values.",
    )
    parser.add_argument(
        "--skip-plots",
        action="store_true",
        help="Write CSV summaries without generating plots.",
    )
    args = parser.parse_args()

    root = args.root.expanduser().resolve()
    if not root.exists():
        raise FileNotFoundError(f"Root directory does not exist: {root}")

    out_dir = (
        args.output_dir.expanduser().resolve()
        if args.output_dir is not None
        else root / "analysis"
    )
    out_dir.mkdir(parents=True, exist_ok=True)

    result_csvs = discover_result_csvs(root)
    if not result_csvs:
        raise FileNotFoundError(f"No scalar result CSV files found under: {root}")

    all_history: list[pd.DataFrame] = []
    all_case_summaries: list[dict[str, Any]] = []
    all_event_audits: list[pd.DataFrame] = []
    all_births: list[pd.DataFrame] = []
    all_vpp_timelines: list[pd.DataFrame] = []
    warnings: list[str] = []

    for csv_path in result_csvs:
        try:
            scalar, scalar_warnings = load_scalar_case(csv_path, args.initial_grains)
        except Exception as exc:  # noqa: BLE001
            warnings.append(f"FAILED TO LOAD {csv_path}: {exc}")
            continue
        warnings.extend(scalar_warnings)

        hold_time = float(scalar.iloc[0]["hold_time_i"])
        vpp = load_grain_vpp(csv_path.parent, scalar, args.vpp_name, hold_time)
        warnings.extend(vpp.warnings)

        if not vpp.timeline.empty:
            timeline = vpp.timeline.copy()
            timeline["case_name"] = scalar.iloc[0]["case_name"]
            timeline["factor_name"] = scalar.iloc[0]["factor_name"]
            timeline["factor_n_i"] = scalar.iloc[0]["factor_n_i"]
            timeline["T_i"] = scalar.iloc[0]["T_i"]
            timeline["strain_rate_i"] = scalar.iloc[0]["strain_rate_i"]
            all_vpp_timelines.append(timeline)

            # Merge by nearest scalar time to add stable-ID counts to line plots.
            # Pandas merge_asof requires both merge keys to have exactly
            # the same numeric datatype.
            scalar = scalar.copy()
            timeline = timeline.copy()

            scalar["time"] = pd.to_numeric(
                scalar["time"],
                errors="coerce",
            ).astype("float64")

            timeline["time"] = pd.to_numeric(
                timeline["time"],
                errors="coerce",
            ).astype("float64")

            # Remove invalid time values and ensure both tables are sorted.
            scalar = (
                scalar
                .dropna(subset=["time"])
                .sort_values("time")
                .reset_index(drop=True)
            )

            timeline = (
                timeline
                .dropna(subset=["time"])
                .sort_values("time")
                .reset_index(drop=True)
            )

            scalar = pd.merge_asof(
                scalar,
                timeline[
                    [
                        "time",
                        "active_stable_grain_ids",
                        "active_new_grain_ids",
                        "mean_individual_grain_D",
                        "D10",
                        "D50",
                        "D90",
                    ]
                ],
                on="time",
                direction="nearest",
            )
        else:
            scalar["active_stable_grain_ids"] = np.nan
            scalar["active_new_grain_ids"] = np.nan
            scalar["mean_individual_grain_D"] = np.nan
            scalar["D10"] = np.nan
            scalar["D50"] = np.nan
            scalar["D90"] = np.nan

        if not vpp.births.empty:
            births = vpp.births.copy()
            births["case_name"] = scalar.iloc[0]["case_name"]
            births["factor_name"] = scalar.iloc[0]["factor_name"]
            births["factor_n_i"] = scalar.iloc[0]["factor_n_i"]
            births["T_i"] = scalar.iloc[0]["T_i"]
            births["strain_rate_i"] = scalar.iloc[0]["strain_rate_i"]
            all_births.append(births)

        event_audit = insertion_event_audit(scalar, args.energy_tolerance)
        if not event_audit.empty:
            all_event_audits.append(event_audit)

        all_case_summaries.append(
            build_case_summary(scalar, vpp, args.initial_grains, args.energy_tolerance)
        )
        all_history.append(scalar)

    if not all_history:
        raise RuntimeError("No cases could be loaded. Inspect analysis_warnings.txt.")

    history = pd.concat(all_history, ignore_index=True)
    case_summary = pd.DataFrame(all_case_summaries).sort_values(
        ["factor_n_i", "T_i", "strain_rate_i"]
    )
    factor_summary = aggregate_factors(case_summary)
    ranking = rank_factors(factor_summary)

    history.to_csv(out_dir / "combined_time_history.csv", index=False)
    case_summary.to_csv(out_dir / "case_summary.csv", index=False)
    factor_summary.to_csv(out_dir / "factor_summary.csv", index=False)
    ranking.to_csv(out_dir / "calibration_ranking.csv", index=False)

    event_audit_all = (
        pd.concat(all_event_audits, ignore_index=True)
        if all_event_audits
        else pd.DataFrame()
    )
    event_audit_all.to_csv(out_dir / "insertion_event_audit.csv", index=False)

    births_all = pd.concat(all_births, ignore_index=True) if all_births else pd.DataFrame()
    births_all.to_csv(out_dir / "grain_birth_events.csv", index=False)

    vpp_timeline_all = (
        pd.concat(all_vpp_timelines, ignore_index=True)
        if all_vpp_timelines
        else pd.DataFrame()
    )
    vpp_timeline_all.to_csv(out_dir / "grain_feature_time_history.csv", index=False)

    write_recommendation(ranking, out_dir / "calibration_recommendation.txt")

    # Deduplicate warnings to keep the report readable.
    unique_warnings = sorted(set(warnings))
    (out_dir / "analysis_warnings.txt").write_text("\n".join(unique_warnings))

    if not args.skip_plots:
        plot_time_histories(history, out_dir)
        plot_heatmaps(case_summary, out_dir)
        plot_factor_comparisons(case_summary, out_dir)

    print("Analysis completed.")
    print(f"Cases loaded: {len(case_summary)}")
    print(f"Analysis directory: {out_dir}")
    print(f"Case summary: {out_dir / 'case_summary.csv'}")
    print(f"Factor summary: {out_dir / 'factor_summary.csv'}")
    print(f"Screening ranking: {out_dir / 'calibration_ranking.csv'}")
    print(f"Recommendation: {out_dir / 'calibration_recommendation.txt'}")
    if unique_warnings:
        print(f"Warnings: {out_dir / 'analysis_warnings.txt'}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: {exc}", file=sys.stderr)
        raise
