from pathlib import Path
import numpy as np
import pandas as pd


ROOT = Path("CalibrationSweep_rho1e16_4TestCases_1")


def read_case_settings(case_dir):
    settings = {}
    path = case_dir / "case_settings.txt"

    if not path.exists():
        return settings

    for line in path.read_text().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            settings[key.strip()] = value.strip()

    return settings


def safe_numeric(df, col):
    if col not in df.columns:
        return pd.Series(dtype=float)
    return pd.to_numeric(df[col], errors="coerce").replace([np.inf, -np.inf], np.nan)


def equivalent_diameter_from_area(area):
    return 2.0 * np.sqrt(area / np.pi)


rows = []

for csv_path in sorted(ROOT.rglob("result.csv")):
    case_dir = csv_path.parent
    settings = read_case_settings(case_dir)

    df = pd.read_csv(csv_path)

    set_name = settings.get("set_name", "unknown")
    T = float(settings.get("T_i", np.nan))
    rate = float(settings.get("strain_rate_i", np.nan))

    row = {
        "set": set_name,
        "T": T,
        "strain_rate": rate,
        "case": case_dir.name,
        "source_file": str(csv_path),
    }

    for key in [
        "hold_strain_i",
        "hold_time_i",
        "nuc_radius_i",
        "int_width_i",
        "nuc_strength_i",
        "factor_n_i",
    ]:
        try:
            row[key] = float(settings.get(key, np.nan))
        except ValueError:
            row[key] = settings.get(key, "")

    # Nucleation counters
    insertions = safe_numeric(df, "nuc_insertions").fillna(0)
    deletions = safe_numeric(df, "nuc_deletions").fillna(0)
    nuc_count = safe_numeric(df, "nuc_count").fillna(0)

    row["total_insertions"] = insertions.sum()
    row["total_deletions"] = deletions.sum()
    row["total_nuc_count"] = nuc_count.sum()

    if row["total_insertions"] > 0:
        row["deletion_fraction"] = row["total_deletions"] / row["total_insertions"]
        row["net_insertions"] = row["total_insertions"] - row["total_deletions"]
    else:
        row["deletion_fraction"] = np.nan
        row["net_insertions"] = 0.0

    # Grain size
    area = safe_numeric(df, "avg_grain_area")
    area = area[np.isfinite(area) & (area > 0)]

    if len(area) > 0:
        D = equivalent_diameter_from_area(area)
        row["D0"] = D.iloc[0]
        row["D_final"] = D.iloc[-1]
        row["D_norm_final"] = D.iloc[-1] / D.iloc[0]
    else:
        row["D0"] = np.nan
        row["D_final"] = np.nan
        row["D_norm_final"] = np.nan

    # Final scalar outputs
    for col in [
        "rho_avg",
        "rho_eff_avg",
        "P_nuc_avg",
        "nuc_drive_ratio_avg",
        "gb_length",
        "Def_Eng",
        "beta_avg",
    ]:
        vals = safe_numeric(df, col).dropna()
        row[f"final_{col}"] = vals.iloc[-1] if len(vals) else np.nan
        row[f"mean_{col}"] = vals.mean() if len(vals) else np.nan
        row[f"max_{col}"] = vals.max() if len(vals) else np.nan

    rows.append(row)


summary = pd.DataFrame(rows)

summary = summary.sort_values(["set", "T", "strain_rate"])

out_path = ROOT / "calibration_set_summary.csv"
summary.to_csv(out_path, index=False)

print()
print("Calibration case summary:")
print(
    summary[
        [
            "set",
            "T",
            "strain_rate",
            "total_insertions",
            "total_deletions",
            "deletion_fraction",
            "net_insertions",
            "D_norm_final",
            "final_gb_length",
            "final_rho_avg",
            "final_P_nuc_avg",
            "final_nuc_drive_ratio_avg",
        ]
    ].to_string(index=False)
)

print()
print(f"Saved: {out_path}")

# Set-level summary
set_summary = (
    summary.groupby("set", as_index=False)
    .agg(
        cases=("case", "count"),
        total_insertions=("total_insertions", "sum"),
        total_deletions=("total_deletions", "sum"),
        net_insertions=("net_insertions", "sum"),
        mean_deletion_fraction=("deletion_fraction", "mean"),
        mean_D_norm_final=("D_norm_final", "mean"),
        min_D_norm_final=("D_norm_final", "min"),
        max_D_norm_final=("D_norm_final", "max"),
        mean_final_gb_length=("final_gb_length", "mean"),
        cases_with_insertions=("total_insertions", lambda s: int((s > 0).sum())),
    )
)

set_summary["overall_deletion_fraction"] = (
    set_summary["total_deletions"] / set_summary["total_insertions"]
)

set_summary_path = ROOT / "calibration_set_level_summary.csv"
set_summary.to_csv(set_summary_path, index=False)

print()
print("Set-level summary:")
print(set_summary.to_string(index=False))
print()
print(f"Saved: {set_summary_path}")