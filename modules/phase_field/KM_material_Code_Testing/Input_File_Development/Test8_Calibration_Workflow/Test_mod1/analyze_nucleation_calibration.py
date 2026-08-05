#!/usr/bin/env python3
"""Analyze staged MOOSE nucleation-calibration sweeps.

The script reads each case directory containing:

    case_settings.txt
    result.csv
    result_grain_features_0000.csv, ...        (optional)
    result_grain_features_time.csv             (optional)

It creates:

    analysis/combined_time_history.csv
    analysis/case_summary.csv
    analysis/parameter_summary.csv
    analysis/grain_birth_events.csv
    analysis/recommendations.md
    analysis/plots/...

The analysis distinguishes discrete nucleation insertions from actual connected
features/grains.  FeatureVolumeVectorPostprocessor row indices are treated as
stable grain IDs when it is driven by GrainTracker or a derived object.
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


SCALAR_ALIASES: dict[str, list[str]] = {
    "time": ["time"],
    "T_avg": ["T_avg", "temperature", "T"],
    "gdot_avg": ["gdot_avg", "gamma_dot_avg", "strain_rate"],
    "rho_avg": ["rho_avg"],
    "rho_eff_avg": ["rho_eff_avg"],
    "tau_avg": ["tau_avg"],
    "Def_Eng": ["Def_Eng", "deformation_energy"],
    "beta_avg": ["beta_avg"],
    "P_nuc_avg": ["P_nuc_avg"],
    "nuc_drive_ratio_avg": ["nuc_drive_ratio_avg"],
    "nuc_drive_ratio_max": ["nuc_drive_ratio_max"],
    "stored_energy_avg": ["stored_energy_avg"],
    "curvature_penalty_avg": ["curvature_penalty_avg"],
    "energy_margin_min": ["energy_margin_min"],
    "energy_margin_max": ["energy_margin_max"],
    "energy_preferred_fraction": ["energy_preferred_fraction"],
    "eligible_nucleation_fraction": ["eligible_nucleation_fraction"],
    "P_nuc_unfavorable_max": ["P_nuc_unfavorable_max"],
    "P_nuc_unfavorable_integral": ["P_nuc_unfavorable_integral"],
    "nuc_count": ["nuc_count"],
    "nuc_rate": ["nuc_rate"],
    "nuc_insertions": ["nuc_insertions"],
    "nuc_deletions": ["nuc_deletions"],
    "nuc_update": ["nuc_update"],
    "avg_grain_area": ["avg_grain_area", "average_grain_volume"],
    "gb_length": ["gb_length", "grain_boundary_area"],
    "grain_count_early": ["grain_count_early"],
    "grain_count_established": ["grain_count_established"],
    "grain_count_bnds_070": ["grain_count_bnds_070"],
    "grain_count_bnds_080": ["grain_count_bnds_080"],
    "grain_count_bnds_090": ["grain_count_bnds_090"],
    "dt_actual": ["dt_actual"],
    "dtnuc": ["dtnuc"],
}

SETTING_NUMERIC_KEYS = [
    "T_i",
    "strain_rate_i",
    "rho_init_i",
    "time_scale_i",
    "nuc_prob_i",
    "factor_n_i",
    "gdot_ref_i",
    "rho_ref_i",
    "r_subgrain_nm",
    "r_subgrain_i",
    "nuc_radius_i",
    "int_width_i",
    "nuc_strength_i",
    "hold_strain",
    "hold_time_i",
    "bnds_min_i",
    "bnds_max_i",
    "seed",
    "total_strain",
    "delta_strain",
    "dt_i",
    "dt_nuc_i",
    "end_time_i",
]

KEY_LINE_METRICS: dict[str, str] = {
    "cum_insertions": "cumulative nucleation insertions",
    "cum_deletions": "cumulative nucleation deletions",
    "net_nuclei_events": "net insertion events",
    "grain_count_early": "incipient connected-feature count",
    "grain_count_established": "established connected-grain count",
    "D_norm": "normalized equivalent grain diameter, D/D0",
    "D_avg": "average equivalent grain diameter",
    "gb_length": "grain-boundary length",
    "rho_avg": "average dislocation density, 1/m^2",
    "rho_eff_avg": "average effective dislocation density",
    "P_nuc_avg": "average nucleation rate density",
    "nuc_drive_ratio_avg": "average nucleation driving ratio",
    "nuc_drive_ratio_max": "maximum nucleation driving ratio",
    "eligible_nucleation_fraction": "eligible nucleation-region fraction",
    "energy_preferred_fraction": "energy-preferred fraction",
}

SUMMARY_HEATMAP_METRICS: dict[str, tuple[str, bool]] = {
    "total_insertions": ("total nucleation insertions", False),
    "total_deletions": ("total nucleation deletions", False),
    "distinct_new_grain_ids": ("distinct new grain IDs", False),
    "survived_hold_grain_ids": ("new grains surviving hold strain", False),
    "final_new_grain_ids": ("new grain IDs active at final state", False),
    "formation_efficiency": ("grain-formation efficiency", False),
    "survival_efficiency": ("grain-survival efficiency", False),
    "final_D_norm": ("final D/D0", False),
    "final_gb_length": ("final grain-boundary length", True),
    "max_nuc_drive_ratio": ("maximum nucleation driving ratio", False),
    "max_eligible_nucleation_fraction": (
        "maximum eligible nucleation-region fraction",
        False,
    ),
}


def normalize_name(value: str) -> str:
    return re.sub(r"[^a-zA-Z0-9]+", "", str(value).lower())


def find_column(df: pd.DataFrame, candidates: Iterable[str]) -> str | None:
    lookup = {normalize_name(col): col for col in df.columns}
    for candidate in candidates:
        key = normalize_name(candidate)
        if key in lookup:
            return lookup[key]
    return None


def to_float(value: object, default: float = np.nan) -> float:
    if value is None:
        return default
    text = str(value).strip().strip("'\"")
    try:
        return float(text)
    except (TypeError, ValueError):
        match = re.search(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", text)
        return float(match.group(0)) if match else default


def read_settings(case_dir: Path) -> dict[str, str]:
    settings: dict[str, str] = {}
    path = case_dir / "case_settings.txt"
    if not path.exists():
        return settings
    for raw_line in path.read_text(errors="replace").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        settings[key.strip()] = value.strip()
    return settings


def first_positive(series: pd.Series) -> float:
    numeric = pd.to_numeric(series, errors="coerce")
    numeric = numeric[np.isfinite(numeric) & (numeric > 0)]
    return float(numeric.iloc[0]) if not numeric.empty else np.nan


def first_finite(series: pd.Series) -> float:
    numeric = pd.to_numeric(series, errors="coerce")
    numeric = numeric[np.isfinite(numeric)]
    return float(numeric.iloc[0]) if not numeric.empty else np.nan


def last_finite(series: pd.Series) -> float:
    numeric = pd.to_numeric(series, errors="coerce")
    numeric = numeric[np.isfinite(numeric)]
    return float(numeric.iloc[-1]) if not numeric.empty else np.nan


def max_finite(series: pd.Series) -> float:
    numeric = pd.to_numeric(series, errors="coerce")
    numeric = numeric[np.isfinite(numeric)]
    return float(numeric.max()) if not numeric.empty else np.nan


def min_finite(series: pd.Series) -> float:
    numeric = pd.to_numeric(series, errors="coerce")
    numeric = numeric[np.isfinite(numeric)]
    return float(numeric.min()) if not numeric.empty else np.nan


def safe_tag(value: object) -> str:
    text = str(value)
    return text.replace("+", "").replace("-", "m").replace(".", "p").replace(" ", "_")


def infer_stage(root: Path, settings: dict[str, str]) -> str:
    if settings.get("stage"):
        return settings["stage"]
    low = root.name.lower()
    for stage in ["mask_width", "survival", "energy_threshold", "probability", "validation"]:
        if stage in low:
            return stage
    return "unknown"


def infer_parameter_set(case_dir: Path, settings: dict[str, str]) -> str:
    return settings.get("parameter_set", settings.get("factor_name", case_dir.name))


def load_scalar_results(root: Path) -> tuple[pd.DataFrame, list[str]]:
    csv_files = sorted(root.rglob("result.csv"))
    warnings: list[str] = []
    frames: list[pd.DataFrame] = []

    if not csv_files:
        raise FileNotFoundError(f"No result.csv files were found under {root}")

    for csv_path in csv_files:
        case_dir = csv_path.parent
        settings = read_settings(case_dir)
        try:
            raw = pd.read_csv(csv_path)
        except Exception as exc:  # noqa: BLE001
            warnings.append(f"Skipped {csv_path}: {exc}")
            continue

        time_col = find_column(raw, SCALAR_ALIASES["time"])
        if time_col is None:
            warnings.append(f"Skipped {csv_path}: no time column")
            continue

        stage = infer_stage(root, settings)
        parameter_set = infer_parameter_set(case_dir, settings)
        temperature = to_float(settings.get("T_i"))
        rate = to_float(settings.get("strain_rate_i"))

        out = pd.DataFrame(index=raw.index)
        out["time"] = pd.to_numeric(raw[time_col], errors="coerce")
        out["stage"] = stage
        out["parameter_set"] = parameter_set
        out["case"] = case_dir.name
        out["case_dir"] = str(case_dir)
        out["source_file"] = str(csv_path)
        out["T"] = temperature
        out["strain_rate"] = rate

        for key in SETTING_NUMERIC_KEYS:
            out[key] = to_float(settings.get(key))
        out["seed"] = to_float(settings.get("seed"))

        for canonical, aliases in SCALAR_ALIASES.items():
            if canonical == "time":
                continue
            col = find_column(raw, aliases)
            out[canonical] = pd.to_numeric(raw[col], errors="coerce") if col else np.nan

        # Prefer case settings as the grouping truth, but fall back to recorded
        # postprocessor values if needed.
        if not np.isfinite(temperature):
            out["T"] = pd.to_numeric(out["T_avg"], errors="coerce")
        if not np.isfinite(rate):
            out["strain_rate"] = pd.to_numeric(out["gdot_avg"], errors="coerce")

        out["accumulated_strain"] = out["strain_rate"] * out["time"]

        area = pd.to_numeric(out["avg_grain_area"], errors="coerce")
        area = area.where(area > 0)
        out["D_avg"] = 2.0 * np.sqrt(area / np.pi)
        d0 = first_positive(out["D_avg"])
        out["D0"] = d0
        out["D_norm"] = out["D_avg"] / d0 if np.isfinite(d0) and d0 > 0 else np.nan

        gb0 = first_positive(out["gb_length"])
        out["gb_length_initial"] = gb0
        out["gb_length_norm"] = (
            out["gb_length"] / gb0 if np.isfinite(gb0) and gb0 > 0 else np.nan
        )

        out["nuc_insertions_step"] = pd.to_numeric(
            out["nuc_insertions"], errors="coerce"
        ).fillna(0.0)
        out["nuc_deletions_step"] = pd.to_numeric(
            out["nuc_deletions"], errors="coerce"
        ).fillna(0.0)
        out["cum_insertions"] = out["nuc_insertions_step"].cumsum()
        out["cum_deletions"] = out["nuc_deletions_step"].cumsum()
        out["net_nuclei_events"] = out["cum_insertions"] - out["cum_deletions"]

        initial_early = first_positive(out["grain_count_early"])
        initial_established = first_positive(out["grain_count_established"])
        out["initial_grain_count_early"] = initial_early
        out["initial_grain_count_established"] = initial_established
        out["new_grains_early_proxy"] = out["grain_count_early"] - initial_early
        out["new_grains_established_proxy"] = (
            out["grain_count_established"] - initial_established
        )

        frames.append(out)

    if not frames:
        raise RuntimeError("No usable scalar CSV files were loaded")

    combined = pd.concat(frames, ignore_index=True)
    combined = combined.dropna(subset=["time", "T", "strain_rate"])
    combined = combined.sort_values(
        ["stage", "parameter_set", "T", "strain_rate", "seed", "time"],
        na_position="last",
    ).reset_index(drop=True)
    return combined, warnings


def parse_vpp_serial(path: Path, vpp_name: str) -> int | None:
    match = re.search(rf"_{re.escape(vpp_name)}_(\d{{4,}})\.csv$", path.name)
    return int(match.group(1)) if match else None


def load_vpp_time_map(case_dir: Path, vpp_name: str) -> dict[int, float]:
    candidates = sorted(case_dir.glob(f"result_{vpp_name}_time.csv"))
    if not candidates:
        return {}
    try:
        df = pd.read_csv(candidates[0])
    except Exception:  # noqa: BLE001
        return {}
    time_col = find_column(df, ["time"])
    if time_col is None:
        return {}
    times = pd.to_numeric(df[time_col], errors="coerce").tolist()
    return {index: float(value) for index, value in enumerate(times) if np.isfinite(value)}


def load_feature_events_for_case(
    case_dir: Path,
    scalar_case: pd.DataFrame,
    vpp_name: str,
) -> tuple[pd.DataFrame, dict[str, float]]:
    files = [
        path
        for path in sorted(case_dir.glob(f"result_{vpp_name}_*.csv"))
        if not path.name.endswith("_time.csv") and parse_vpp_serial(path, vpp_name) is not None
    ]
    if not files:
        return pd.DataFrame(), {
            "vpp_available": 0.0,
            "distinct_new_grain_ids": np.nan,
            "survived_hold_grain_ids": np.nan,
            "final_new_grain_ids": np.nan,
        }

    time_map = load_vpp_time_map(case_dir, vpp_name)
    scalar_times = sorted(pd.to_numeric(scalar_case["time"], errors="coerce").dropna().unique())
    rate = first_finite(scalar_case["strain_rate"])
    hold_strain = first_finite(scalar_case["hold_strain"])
    if not np.isfinite(hold_strain):
        hold_time = first_finite(scalar_case["hold_time_i"])
        hold_strain = hold_time * rate if np.isfinite(hold_time) and np.isfinite(rate) else 0.0

    snapshots: list[dict[str, object]] = []
    for path in files:
        serial = parse_vpp_serial(path, vpp_name)
        if serial is None:
            continue
        try:
            df = pd.read_csv(path)
        except Exception:  # noqa: BLE001
            continue

        volume_col = find_column(df, ["feature_volumes", "feature_volume", "volume"])
        var_col = find_column(df, ["var_num"])
        cx_col = find_column(df, ["centroid_x"])
        cy_col = find_column(df, ["centroid_y"])
        cz_col = find_column(df, ["centroid_z"])
        if volume_col is None:
            continue

        time_value = time_map.get(serial, np.nan)
        if not np.isfinite(time_value) and serial < len(scalar_times):
            time_value = float(scalar_times[serial])
        strain_value = time_value * rate if np.isfinite(time_value) and np.isfinite(rate) else np.nan

        volumes = pd.to_numeric(df[volume_col], errors="coerce")
        var_nums = (
            pd.to_numeric(df[var_col], errors="coerce")
            if var_col
            else pd.Series(np.zeros(len(df)), index=df.index)
        )

        for grain_id in range(len(df)):
            volume = volumes.iloc[grain_id]
            var_num = var_nums.iloc[grain_id]
            if not np.isfinite(volume) or volume <= 0:
                continue
            if np.isfinite(var_num) and var_num < 0:
                continue
            snapshots.append(
                {
                    "serial": serial,
                    "time": time_value,
                    "accumulated_strain": strain_value,
                    "grain_id": grain_id,
                    "var_num": var_num,
                    "area": float(volume),
                    "equivalent_diameter": 2.0 * math.sqrt(float(volume) / math.pi),
                    "centroid_x": to_float(df[cx_col].iloc[grain_id]) if cx_col else np.nan,
                    "centroid_y": to_float(df[cy_col].iloc[grain_id]) if cy_col else np.nan,
                    "centroid_z": to_float(df[cz_col].iloc[grain_id]) if cz_col else np.nan,
                    "vpp_file": str(path),
                }
            )

    snapshots_df = pd.DataFrame(snapshots)
    if snapshots_df.empty:
        return snapshots_df, {
            "vpp_available": 1.0,
            "distinct_new_grain_ids": 0.0,
            "survived_hold_grain_ids": 0.0,
            "final_new_grain_ids": 0.0,
        }

    snapshots_df = snapshots_df.sort_values(["serial", "grain_id"]).reset_index(drop=True)
    first_serial = int(snapshots_df["serial"].min())
    final_serial = int(snapshots_df["serial"].max())
    initial_ids = set(
        snapshots_df.loc[snapshots_df["serial"] == first_serial, "grain_id"].astype(int)
    )
    final_ids = set(
        snapshots_df.loc[snapshots_df["serial"] == final_serial, "grain_id"].astype(int)
    )
    all_ids = set(snapshots_df["grain_id"].astype(int))
    new_ids = sorted(all_ids - initial_ids)

    final_strain = max_finite(snapshots_df["accumulated_strain"])
    event_rows: list[dict[str, object]] = []
    survived_hold_count = 0
    final_new_count = 0

    for grain_id in new_ids:
        history = snapshots_df[snapshots_df["grain_id"] == grain_id].sort_values("serial")
        birth = history.iloc[0]
        last = history.iloc[-1]
        birth_strain = to_float(birth["accumulated_strain"])
        last_strain = to_float(last["accumulated_strain"])
        observable_hold = (
            np.isfinite(final_strain)
            and np.isfinite(birth_strain)
            and final_strain >= birth_strain + hold_strain - 1.0e-12
        )
        survived_hold = (
            observable_hold
            and np.isfinite(last_strain)
            and last_strain >= birth_strain + hold_strain - 1.0e-12
        )
        survives_final = grain_id in final_ids
        survived_hold_count += int(bool(survived_hold))
        final_new_count += int(bool(survives_final))

        event_rows.append(
            {
                "grain_id": grain_id,
                "birth_serial": int(birth["serial"]),
                "birth_time": birth["time"],
                "birth_strain": birth["accumulated_strain"],
                "birth_area": birth["area"],
                "birth_equivalent_diameter": birth["equivalent_diameter"],
                "centroid_x": birth["centroid_x"],
                "centroid_y": birth["centroid_y"],
                "centroid_z": birth["centroid_z"],
                "last_serial": int(last["serial"]),
                "last_time": last["time"],
                "last_strain": last["accumulated_strain"],
                "last_area": last["area"],
                "observable_hold_interval": observable_hold,
                "survived_hold": survived_hold if observable_hold else np.nan,
                "survives_final": survives_final,
            }
        )

    event_df = pd.DataFrame(event_rows)
    stats = {
        "vpp_available": 1.0,
        "initial_grain_ids_vpp": float(len(initial_ids)),
        "distinct_new_grain_ids": float(len(new_ids)),
        "survived_hold_grain_ids": float(survived_hold_count),
        "final_new_grain_ids": float(final_new_count),
    }
    return event_df, stats


def classify_regime(row: pd.Series) -> str:
    drive = row.get("max_nuc_drive_ratio", np.nan)
    eligible = row.get("max_eligible_nucleation_fraction", np.nan)
    insertions = row.get("total_insertions", 0.0)
    distinct = row.get("distinct_new_grain_ids", np.nan)
    survived = row.get("survived_hold_grain_ids", np.nan)
    established_gain = row.get("max_new_grains_established_proxy", np.nan)
    dnorm = row.get("final_D_norm", np.nan)
    gb_norm = row.get("final_gb_length_norm", np.nan)

    if np.isfinite(drive) and drive < 1.0 and (not np.isfinite(eligible) or eligible <= 0):
        return "energy_blocked"
    if insertions <= 0:
        if np.isfinite(dnorm) and dnorm > 1.05 and np.isfinite(gb_norm) and gb_norm < 0.9:
            return "coarsening_only"
        return "eligible_but_no_insertion"
    if np.isfinite(distinct):
        if distinct <= 0:
            return "insertion_but_no_new_grain"
        if np.isfinite(survived) and survived <= 0:
            return "new_grain_but_not_surviving"
        if np.isfinite(survived) and survived > 0:
            return "nucleation_and_growth"
    if np.isfinite(established_gain):
        if established_gain <= 0:
            return "insertion_but_no_established_grain"
        return "nucleation_and_growth_proxy"
    return "mixed_or_unresolved"


def build_case_summary(
    data: pd.DataFrame,
    vpp_name: str,
    expected_initial_grains: int,
    gate_tolerance: float,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    case_rows: list[dict[str, object]] = []
    event_frames: list[pd.DataFrame] = []

    group_cols = ["stage", "parameter_set", "case", "case_dir", "T", "strain_rate", "seed"]
    for keys, group in data.groupby(group_cols, dropna=False, sort=True):
        stage, parameter_set, case, case_dir_text, temperature, rate, seed = keys
        group = group.sort_values("time")
        case_dir = Path(case_dir_text)

        event_df, vpp_stats = load_feature_events_for_case(case_dir, group, vpp_name)
        if not event_df.empty:
            for key, value in {
                "stage": stage,
                "parameter_set": parameter_set,
                "case": case,
                "case_dir": case_dir_text,
                "T": temperature,
                "strain_rate": rate,
                "seed": seed,
            }.items():
                event_df[key] = value
            event_frames.append(event_df)

        row: dict[str, object] = {
            "stage": stage,
            "parameter_set": parameter_set,
            "case": case,
            "case_dir": case_dir_text,
            "T": temperature,
            "strain_rate": rate,
            "seed": seed,
            "final_time": last_finite(group["time"]),
            "final_accumulated_strain": last_finite(group["accumulated_strain"]),
            "total_insertions": float(group["nuc_insertions_step"].sum()),
            "total_deletions": float(group["nuc_deletions_step"].sum()),
            "final_nuc_count": last_finite(group["nuc_count"]),
            "final_D_avg": last_finite(group["D_avg"]),
            "final_D_norm": last_finite(group["D_norm"]),
            "final_gb_length": last_finite(group["gb_length"]),
            "final_gb_length_norm": last_finite(group["gb_length_norm"]),
            "final_rho_avg": last_finite(group["rho_avg"]),
            "final_rho_eff_avg": last_finite(group["rho_eff_avg"]),
            "final_P_nuc_avg": last_finite(group["P_nuc_avg"]),
            "max_P_nuc_avg": max_finite(group["P_nuc_avg"]),
            "max_nuc_drive_ratio": max_finite(
                pd.concat(
                    [
                        pd.to_numeric(group["nuc_drive_ratio_max"], errors="coerce"),
                        pd.to_numeric(group["nuc_drive_ratio_avg"], errors="coerce"),
                    ],
                    ignore_index=True,
                )
            ),
            "max_eligible_nucleation_fraction": max_finite(
                group["eligible_nucleation_fraction"]
            ),
            "max_energy_preferred_fraction": max_finite(group["energy_preferred_fraction"]),
            "max_P_nuc_unfavorable": max_finite(group["P_nuc_unfavorable_max"]),
            "max_P_nuc_unfavorable_integral": max_finite(
                group["P_nuc_unfavorable_integral"]
            ),
            "initial_grain_count_early": first_positive(group["grain_count_early"]),
            "initial_grain_count_established": first_positive(
                group["grain_count_established"]
            ),
            "final_grain_count_early": last_finite(group["grain_count_early"]),
            "final_grain_count_established": last_finite(group["grain_count_established"]),
            "max_new_grains_early_proxy": max_finite(group["new_grains_early_proxy"]),
            "max_new_grains_established_proxy": max_finite(
                group["new_grains_established_proxy"]
            ),
        }

        for key in SETTING_NUMERIC_KEYS:
            row[key] = first_finite(group[key]) if key in group.columns else np.nan
        row.update(vpp_stats)

        total_insertions = float(row["total_insertions"])
        total_deletions = float(row["total_deletions"])
        row["net_insertions"] = total_insertions - total_deletions
        row["deletion_fraction"] = (
            total_deletions / total_insertions if total_insertions > 0 else np.nan
        )
        row["event_survival_fraction"] = (
            1.0 - row["deletion_fraction"]
            if np.isfinite(row["deletion_fraction"])
            else np.nan
        )

        distinct = to_float(row.get("distinct_new_grain_ids"))
        survived_hold = to_float(row.get("survived_hold_grain_ids"))
        row["formation_efficiency"] = (
            distinct / total_insertions
            if total_insertions > 0 and np.isfinite(distinct)
            else np.nan
        )
        row["survival_efficiency"] = (
            survived_hold / total_insertions
            if total_insertions > 0 and np.isfinite(survived_hold)
            else np.nan
        )

        intended_end = to_float(row.get("end_time_i"))
        row["run_complete"] = (
            not np.isfinite(intended_end)
            or (np.isfinite(row["final_time"]) and row["final_time"] >= 0.99 * intended_end)
        )

        initial_count = row["initial_grain_count_established"]
        if not np.isfinite(initial_count):
            initial_count = row["initial_grain_count_early"]
        row["initial_grain_count_ok"] = (
            not np.isfinite(initial_count)
            or abs(initial_count - expected_initial_grains) <= 0.25
        )

        gate_value = row["max_P_nuc_unfavorable"]
        gate_integral = row["max_P_nuc_unfavorable_integral"]
        gate_ok = True
        if np.isfinite(gate_value):
            gate_ok = gate_ok and abs(gate_value) <= gate_tolerance
        if np.isfinite(gate_integral):
            gate_ok = gate_ok and abs(gate_integral) <= gate_tolerance
        row["energy_gate_ok"] = gate_ok

        key_values = [
            row["final_D_norm"],
            row["final_gb_length"],
            row["final_rho_avg"],
            row["max_nuc_drive_ratio"],
        ]
        row["finite_outputs_ok"] = all(
            (not np.isfinite(value)) or abs(float(value)) < 1.0e300 for value in key_values
        )
        row["valid_case"] = bool(
            row["run_complete"]
            and row["initial_grain_count_ok"]
            and row["energy_gate_ok"]
            and row["finite_outputs_ok"]
        )

        row_series = pd.Series(row)
        row["regime"] = classify_regime(row_series)
        if np.isfinite(row.get("formation_efficiency", np.nan)) and row["formation_efficiency"] > 1.05:
            row["feature_id_warning"] = "formation_efficiency_above_one"
        else:
            row["feature_id_warning"] = ""

        case_rows.append(row)

    case_summary = pd.DataFrame(case_rows)
    if not case_summary.empty:
        case_summary = case_summary.sort_values(
            ["stage", "parameter_set", "T", "strain_rate", "seed"],
            na_position="last",
        ).reset_index(drop=True)
    events = pd.concat(event_frames, ignore_index=True) if event_frames else pd.DataFrame()
    return case_summary, events


def build_parameter_summary(case_summary: pd.DataFrame) -> pd.DataFrame:
    if case_summary.empty:
        return pd.DataFrame()

    rows: list[dict[str, object]] = []
    for (stage, parameter_set), group in case_summary.groupby(
        ["stage", "parameter_set"], dropna=False, sort=True
    ):
        valid = group[group["valid_case"] == True]  # noqa: E712
        regimes = group["regime"].value_counts().to_dict()
        row: dict[str, object] = {
            "stage": stage,
            "parameter_set": parameter_set,
            "cases": len(group),
            "valid_cases": len(valid),
            "valid_fraction": len(valid) / len(group) if len(group) else np.nan,
            "cases_with_insertions": int((group["total_insertions"] > 0).sum()),
            "cases_with_distinct_new_grains": int(
                (pd.to_numeric(group["distinct_new_grain_ids"], errors="coerce") > 0).sum()
            ),
            "cases_with_surviving_grains": int(
                (pd.to_numeric(group["survived_hold_grain_ids"], errors="coerce") > 0).sum()
            ),
            "total_insertions": group["total_insertions"].sum(),
            "total_deletions": group["total_deletions"].sum(),
            "median_deletion_fraction": group["deletion_fraction"].median(),
            "median_formation_efficiency": group["formation_efficiency"].median(),
            "median_survival_efficiency": group["survival_efficiency"].median(),
            "median_final_D_norm": group["final_D_norm"].median(),
            "median_final_gb_length_norm": group["final_gb_length_norm"].median(),
            "energy_blocked_cases": regimes.get("energy_blocked", 0),
            "eligible_no_insertion_cases": regimes.get("eligible_but_no_insertion", 0),
            "insertion_no_grain_cases": regimes.get("insertion_but_no_new_grain", 0)
            + regimes.get("insertion_but_no_established_grain", 0),
            "new_grain_not_surviving_cases": regimes.get("new_grain_but_not_surviving", 0),
            "nucleation_growth_cases": regimes.get("nucleation_and_growth", 0)
            + regimes.get("nucleation_and_growth_proxy", 0),
            "coarsening_only_cases": regimes.get("coarsening_only", 0),
        }

        # Preserve parameter values that are constant within this parameter set.
        for key in SETTING_NUMERIC_KEYS:
            values = pd.to_numeric(group[key], errors="coerce").dropna().unique()
            row[key] = float(values[0]) if len(values) == 1 else np.nan

        notes: list[str] = []
        if row["valid_fraction"] < 1.0:
            notes.append("reject_or_debug_invalid_cases")
        if row["energy_blocked_cases"] == row["cases"]:
            notes.append("energy_threshold_too_strict_for_all_cases")
        if row["eligible_no_insertion_cases"] > 0:
            notes.append("increase_single_probability_scale_if_these_cases_should_nucleate")
        if row["insertion_no_grain_cases"] > 0:
            notes.append("increase_nucleus_survival_controls")
        if row["new_grain_not_surviving_cases"] > 0:
            notes.append("hold_radius_or_strength_may_be_insufficient")
        if row["median_deletion_fraction"] > 0.8:
            notes.append("most_insertions_expire_or_disappear")
        if row["nucleation_growth_cases"] > 0:
            notes.append("candidate_global_set")
        row["screening_notes"] = ";".join(notes) if notes else "inspect_physics_and_experimental_targets"
        rows.append(row)

    return pd.DataFrame(rows).sort_values(["stage", "parameter_set"]).reset_index(drop=True)


def plot_parameter_case_lines(
    data: pd.DataFrame,
    out_dir: Path,
    metric: str,
    label: str,
) -> None:
    if metric not in data.columns or data[metric].isna().all():
        return
    plot_dir = out_dir / "plots" / "lines_by_physical_case" / metric
    plot_dir.mkdir(parents=True, exist_ok=True)

    for (temperature, rate), group in data.groupby(["T", "strain_rate"], dropna=False):
        plt.figure()
        plotted = False
        for parameter_set, curve in group.groupby("parameter_set", dropna=False):
            curve = curve.sort_values("accumulated_strain")
            valid = curve[["accumulated_strain", metric]].replace([np.inf, -np.inf], np.nan).dropna()
            if valid.empty:
                continue
            plt.plot(valid["accumulated_strain"], valid[metric], label=str(parameter_set))
            plotted = True
        if not plotted:
            plt.close()
            continue
        plt.xlabel("accumulated strain")
        plt.ylabel(label)
        plt.title(f"{label}; T = {temperature:g} K, strain rate = {rate:g} 1/s")
        plt.legend(title="parameter set")
        plt.tight_layout()
        plt.savefig(
            plot_dir / f"T_{safe_tag(temperature)}_gdot_{safe_tag(rate)}_{metric}.png",
            dpi=300,
        )
        plt.close()


def plot_parameter_summary_bars(parameter_summary: pd.DataFrame, out_dir: Path) -> None:
    if parameter_summary.empty:
        return
    plot_dir = out_dir / "plots" / "parameter_summary"
    plot_dir.mkdir(parents=True, exist_ok=True)

    metrics = {
        "cases_with_surviving_grains": "cases with grains surviving hold strain",
        "median_formation_efficiency": "median formation efficiency",
        "median_survival_efficiency": "median survival efficiency",
        "median_deletion_fraction": "median deletion fraction",
        "median_final_D_norm": "median final D/D0",
    }
    for stage, stage_group in parameter_summary.groupby("stage", dropna=False):
        for metric, label in metrics.items():
            values = pd.to_numeric(stage_group[metric], errors="coerce")
            if values.isna().all():
                continue
            plt.figure()
            positions = np.arange(len(stage_group))
            plt.bar(positions, values)
            plt.xticks(positions, stage_group["parameter_set"], rotation=45, ha="right")
            plt.ylabel(label)
            plt.title(f"{label}; stage = {stage}")
            plt.tight_layout()
            plt.savefig(plot_dir / f"{safe_tag(stage)}_{metric}.png", dpi=300)
            plt.close()


def plot_heatmaps(case_summary: pd.DataFrame, out_dir: Path) -> None:
    if case_summary.empty:
        return
    plot_dir = out_dir / "plots" / "heatmaps"
    plot_dir.mkdir(parents=True, exist_ok=True)

    for (stage, parameter_set), group in case_summary.groupby(
        ["stage", "parameter_set"], dropna=False
    ):
        if group["T"].nunique() < 2 or group["strain_rate"].nunique() < 2:
            continue
        for metric, (label, use_log) in SUMMARY_HEATMAP_METRICS.items():
            values = pd.to_numeric(group[metric], errors="coerce").replace([np.inf, -np.inf], np.nan)
            if values.isna().all():
                continue
            temp = group.copy()
            plot_col = metric
            if use_log:
                temp = temp[values > 0].copy()
                if temp.empty:
                    continue
                plot_col = f"log10_{metric}"
                temp[plot_col] = np.log10(pd.to_numeric(temp[metric], errors="coerce"))
            pivot = temp.pivot_table(
                index="T", columns="strain_rate", values=plot_col, aggfunc="mean"
            ).sort_index().sort_index(axis=1)
            if pivot.empty:
                continue

            plt.figure()
            image = plt.imshow(pivot.values, origin="lower", aspect="auto")
            color_label = f"log10({label})" if use_log else label
            plt.colorbar(image, label=color_label)
            plt.xticks(
                np.arange(len(pivot.columns)),
                [f"{value:g}" for value in pivot.columns],
                rotation=45,
            )
            plt.yticks(
                np.arange(len(pivot.index)),
                [f"{value:g}" for value in pivot.index],
            )
            plt.xlabel("strain rate, 1/s")
            plt.ylabel("temperature, K")
            plt.title(f"{label}; {parameter_set}")
            for i in range(pivot.shape[0]):
                for j in range(pivot.shape[1]):
                    value = pivot.values[i, j]
                    if np.isfinite(value):
                        text = f"{value:.2g}" if not use_log else f"{value:.2f}"
                        plt.text(j, i, text, ha="center", va="center")
            plt.tight_layout()
            filename = f"{safe_tag(stage)}_{safe_tag(parameter_set)}_{metric}.png"
            plt.savefig(plot_dir / filename, dpi=300)
            plt.close()


def plot_validation_uncertainty(case_summary: pd.DataFrame, out_dir: Path) -> None:
    validation = case_summary[case_summary["stage"] == "validation"].copy()
    if validation.empty or validation["seed"].nunique() < 2:
        return
    plot_dir = out_dir / "plots" / "validation_uncertainty"
    plot_dir.mkdir(parents=True, exist_ok=True)

    metrics = {
        "total_insertions": "total insertions",
        "survived_hold_grain_ids": "surviving new grains",
        "final_D_norm": "final D/D0",
        "final_gb_length": "final grain-boundary length",
    }
    for metric, label in metrics.items():
        if validation[metric].isna().all():
            continue
        stats = (
            validation.groupby(["T", "strain_rate"])[metric]
            .agg(["mean", "std"])
            .reset_index()
        )
        for temperature, group in stats.groupby("T"):
            group = group.sort_values("strain_rate")
            plt.figure()
            x = np.arange(len(group))
            plt.errorbar(x, group["mean"], yerr=group["std"].fillna(0), marker="o")
            plt.xticks(x, [f"{value:g}" for value in group["strain_rate"]])
            plt.xlabel("strain rate, 1/s")
            plt.ylabel(label)
            plt.title(f"seed mean +/- standard deviation; T = {temperature:g} K")
            plt.tight_layout()
            plt.savefig(plot_dir / f"T_{safe_tag(temperature)}_{metric}.png", dpi=300)
            plt.close()


def write_recommendations(
    case_summary: pd.DataFrame,
    parameter_summary: pd.DataFrame,
    out_path: Path,
) -> None:
    lines: list[str] = [
        "# Nucleation calibration screening recommendations",
        "",
        "These recommendations are based on internal consistency, not a unique fit to experimental data.",
        "",
        "## Hard checks",
    ]

    if case_summary.empty:
        lines.append("No cases were available.")
        out_path.write_text("\n".join(lines))
        return

    invalid = case_summary[case_summary["valid_case"] != True]  # noqa: E712
    if invalid.empty:
        lines.append("- All loaded cases passed the run-completion, initial-count, finite-value, and energy-gate checks.")
    else:
        lines.append(f"- {len(invalid)} case(s) failed at least one hard check. Debug these before selecting parameters.")
        for _, row in invalid.iterrows():
            lines.append(
                f"  - {row['case']}: run_complete={row['run_complete']}, "
                f"initial_count_ok={row['initial_grain_count_ok']}, "
                f"energy_gate_ok={row['energy_gate_ok']}, finite_outputs_ok={row['finite_outputs_ok']}"
            )

    for stage, group in case_summary.groupby("stage", dropna=False):
        lines.extend(["", f"## Stage: {stage}"])
        regime_counts = group["regime"].value_counts()
        for regime, count in regime_counts.items():
            lines.append(f"- {regime}: {count} case(s)")

        if stage == "mask_width":
            lines.append(
                "- Choose a bnds window and int_width that preserve an initial count of four grains and localize the eligible region to ordinary grain boundaries. Confirm triple-junction exclusion in Exodus/ParaView; global averages cannot prove local exclusion."
            )
        elif stage == "survival":
            candidates = parameter_summary[
                (parameter_summary["stage"] == stage)
                & (parameter_summary["valid_fraction"] == 1.0)
            ].copy()
            if not candidates.empty:
                candidates = candidates.sort_values(
                    [
                        "median_survival_efficiency",
                        "cases_with_surviving_grains",
                        "nuc_radius_i",
                        "hold_strain",
                        "nuc_strength_i",
                    ],
                    ascending=[False, False, True, True, True],
                )
                best = candidates.iloc[0]
                lines.append(
                    f"- Screening candidate: {best['parameter_set']}. Prefer the smallest radius/hold/strength that produces an established grain surviving the hold interval."
                )
        elif stage == "energy_threshold":
            lines.append(
                "- Select r_subgrain from physical evidence when available. As an internal screen, prefer a value that differentiates the high-storage, intermediate, and recovery-dominated cases rather than making every case eligible or every case blocked."
            )
        elif stage == "probability":
            lines.append(
                "- Keep nuc_prob_i fixed and select factor_n_i; they are multiplicative and cannot be independently identified from this model form."
            )
            lines.append(
                "- A factor is too low when drive ratio exceeds one and eligible area exists but insertions remain zero. It is too high when insertions are excessive, deletion fraction approaches one, or remapping failures occur."
            )
        elif stage == "validation":
            lines.append(
                "- Use the seed mean and standard deviation to report stochastic uncertainty. Do not retune individual temperature/strain-rate cases."
            )

    lines.extend(
        [
            "",
            "## Regime interpretation",
            "- energy_blocked: adjust/justify r_subgrain or accept that the condition is not nucleation-favorable.",
            "- eligible_but_no_insertion: increase only one global probability scale (nuc_prob_i or factor_n_i).",
            "- insertion_but_no_new_grain: improve nucleus radius, forcing strength, or hold strain.",
            "- new_grain_but_not_surviving: survival controls are insufficient or physical growth is too slow.",
            "- nucleation_and_growth: candidate behavior for global validation.",
            "- coarsening_only: boundary migration occurs without detectable new grain formation.",
        ]
    )
    out_path.write_text("\n".join(lines))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Post-process staged MOOSE nucleation calibration sweeps."
    )
    parser.add_argument(
        "--root",
        type=Path,
        required=True,
        help="Root folder containing case directories with result.csv and case_settings.txt",
    )
    parser.add_argument(
        "--outdir",
        type=Path,
        default=None,
        help="Output folder; default is ROOT/analysis",
    )
    parser.add_argument(
        "--vpp-name",
        default="grain_features",
        help="FeatureVolumeVectorPostprocessor block name",
    )
    parser.add_argument(
        "--initial-grains",
        type=int,
        default=4,
        help="Expected initial grain count",
    )
    parser.add_argument(
        "--gate-tolerance",
        type=float,
        default=1.0e-14,
        help="Tolerance for P_nuc in energetically unfavorable regions",
    )
    args = parser.parse_args()

    root = args.root.expanduser().resolve()
    out_dir = (
        args.outdir.expanduser().resolve()
        if args.outdir
        else root / "analysis"
    )
    out_dir.mkdir(parents=True, exist_ok=True)

    data, warnings = load_scalar_results(root)
    case_summary, events = build_case_summary(
        data,
        vpp_name=args.vpp_name,
        expected_initial_grains=args.initial_grains,
        gate_tolerance=args.gate_tolerance,
    )
    parameter_summary = build_parameter_summary(case_summary)

    data.to_csv(out_dir / "combined_time_history.csv", index=False)
    case_summary.to_csv(out_dir / "case_summary.csv", index=False)
    parameter_summary.to_csv(out_dir / "parameter_summary.csv", index=False)
    events.to_csv(out_dir / "grain_birth_events.csv", index=False)

    for metric, label in KEY_LINE_METRICS.items():
        plot_parameter_case_lines(data, out_dir, metric, label)
    plot_parameter_summary_bars(parameter_summary, out_dir)
    plot_heatmaps(case_summary, out_dir)
    plot_validation_uncertainty(case_summary, out_dir)

    write_recommendations(
        case_summary,
        parameter_summary,
        out_dir / "recommendations.md",
    )

    print("Analysis complete.")
    print(f"Combined history:   {out_dir / 'combined_time_history.csv'}")
    print(f"Case summary:       {out_dir / 'case_summary.csv'}")
    print(f"Parameter summary:  {out_dir / 'parameter_summary.csv'}")
    print(f"Grain birth events: {out_dir / 'grain_birth_events.csv'}")
    print(f"Recommendations:    {out_dir / 'recommendations.md'}")
    print(f"Plots:              {out_dir / 'plots'}")

    if warnings:
        print("\nWarnings:")
        for warning in warnings[:30]:
            print(f"  {warning}")
        if len(warnings) > 30:
            print(f"  ... {len(warnings) - 30} more")


if __name__ == "__main__":
    main()
