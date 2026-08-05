#!/usr/bin/env python3

from pathlib import Path
import re

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt


ROOT = Path("FullSweep_rho1e16_0")
OUT = ROOT / "diagnostic_plots"


def parse_number(text):
    text = str(text).replace("p", ".").replace(",", ".")
    match = re.search(r"[-+]?\d*\.?\d+(?:e[-+]?\d+)?", text)
    if match is None:
        return np.nan
    return float(match.group(0))


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


def find_col(df, names):
    clean = {
        re.sub(r"[^a-zA-Z0-9]", "", c.lower()): c
        for c in df.columns
    }

    for name in names:
        key = re.sub(r"[^a-zA-Z0-9]", "", name.lower())
        if key in clean:
            return clean[key]

    return None


def equivalent_diameter(area):
    return 2.0 * np.sqrt(area / np.pi)


def load_data(root):
    files = sorted(root.rglob("result.csv"))

    if not files:
        files = sorted(root.rglob("*.csv"))

    rows = []

    for csv_path in files:
        if "logs" in csv_path.parts or "plots" in csv_path.parts:
            continue

        try:
            df = pd.read_csv(csv_path)
        except Exception:
            continue

        time_col = find_col(df, ["time"])
        if time_col is None:
            continue

        settings = read_case_settings(csv_path.parent)

        T = float(settings.get("T_i", np.nan))
        rate = float(settings.get("strain_rate_i", np.nan))

        if not np.isfinite(T) or not np.isfinite(rate):
            for part in csv_path.parts:
                lower = part.lower()
                if lower.startswith("t_"):
                    T = parse_number(part)
                elif lower.startswith("gdot_"):
                    rate = parse_number(part)

        out = pd.DataFrame()
        out["time"] = pd.to_numeric(df[time_col], errors="coerce")
        out["T"] = T
        out["strain_rate"] = rate
        out["accumulated_strain"] = out["time"] * out["strain_rate"]
        out["source_file"] = str(csv_path)

        wanted = {
            "rho_avg": ["rho_avg"],
            "rho_eff_avg": ["rho_eff_avg"],
            "Def_Eng": ["Def_Eng"],
            "beta_avg": ["beta_avg"],
            "P_nuc_avg": ["P_nuc_avg"],
            "nuc_drive_ratio_avg": ["nuc_drive_ratio_avg"],
            "nuc_count": ["nuc_count"],
            "nuc_insertions": ["nuc_insertions"],
            "nuc_deletions": ["nuc_deletions"],
            "avg_grain_area": ["avg_grain_area", "average_grain_volume"],
            "gb_length": ["gb_length", "grain_boundary_area"],
            "grain_count": ["grain_count", "grain_tracker", "num_grains"],
            "dt_actual": ["dt_actual", "dtnuc"],
            "T_avg": ["T_avg"],
            "gdot_avg": ["gdot_avg"],
        }

        for out_name, possible_names in wanted.items():
            col = find_col(df, possible_names)
            if col is not None:
                out[out_name] = pd.to_numeric(df[col], errors="coerce")
            else:
                out[out_name] = np.nan

        if not out["avg_grain_area"].isna().all():
            out["D_avg"] = equivalent_diameter(out["avg_grain_area"])
        else:
            out["D_avg"] = np.nan

        rows.append(out)

    if not rows:
        raise RuntimeError(f"No usable result CSV files found under {root}")

    data = pd.concat(rows, ignore_index=True)
    data = data.dropna(subset=["time", "T", "strain_rate"])
    data = data.sort_values(["T", "strain_rate", "time"]).reset_index(drop=True)

    if not data["D_avg"].isna().all():
        group_cols = ["T", "strain_rate"]
        data["D0"] = data.groupby(group_cols)["D_avg"].transform(
            lambda s: s[s > 0].iloc[0] if (s > 0).any() else np.nan
        )
        data["D_norm"] = data["D_avg"] / data["D0"]

    return data


def plot_fixed_T(data, y, ylabel):
    if y not in data.columns or data[y].isna().all():
        return

    plot_dir = OUT / f"{y}_fixed_T"
    plot_dir.mkdir(parents=True, exist_ok=True)

    for T, group_T in data.groupby("T"):
        plt.figure()

        for rate, curve in group_T.groupby("strain_rate"):
            curve = curve.sort_values("accumulated_strain")
            plt.plot(
                curve["accumulated_strain"],
                curve[y],
                label=f"{rate:g} 1/s",
            )

        plt.xlabel("accumulated strain")
        plt.ylabel(ylabel)
        plt.title(f"{ylabel}, T = {T:g} K")
        plt.legend(title="strain rate")
        plt.tight_layout()
        plt.savefig(plot_dir / f"T_{T:g}_{y}.png", dpi=300)
        plt.close()


def plot_fixed_rate(data, y, ylabel):
    if y not in data.columns or data[y].isna().all():
        return

    plot_dir = OUT / f"{y}_fixed_strain_rate"
    plot_dir.mkdir(parents=True, exist_ok=True)

    for rate, group_rate in data.groupby("strain_rate"):
        plt.figure()

        for T, curve in group_rate.groupby("T"):
            curve = curve.sort_values("accumulated_strain")
            plt.plot(
                curve["accumulated_strain"],
                curve[y],
                label=f"{T:g} K",
            )

        plt.xlabel("accumulated strain")
        plt.ylabel(ylabel)
        plt.title(f"{ylabel}, strain rate = {rate:g} 1/s")
        plt.legend(title="temperature")
        plt.tight_layout()
        plt.savefig(plot_dir / f"gdot_{rate:g}_{y}.png", dpi=300)
        plt.close()


def make_final_summary(data):
    final_rows = (
        data.sort_values("time")
        .groupby(["T", "strain_rate"], as_index=False)
        .tail(1)
        .sort_values(["T", "strain_rate"])
    )

    final_rows["case_type"] = "unclassified"

    if "nuc_insertions" in final_rows.columns:
        final_rows.loc[
            final_rows["nuc_insertions"].fillna(0) <= 0,
            "case_type",
        ] = "no_or_low_nucleation"

    if "nuc_insertions" in final_rows.columns and "D_norm" in final_rows.columns:
        mask = (
            final_rows["nuc_insertions"].fillna(0) > 0
        ) & (
            final_rows["D_norm"].fillna(1) < 1.2
        )
        final_rows.loc[mask, "case_type"] = "nucleation_but_limited_growth"

    if "D_norm" in final_rows.columns:
        final_rows.loc[
            final_rows["D_norm"].fillna(1) >= 1.2,
            "case_type",
        ] = "growth_observed"

    return final_rows


def plot_final_heatmap(summary, y, ylabel):
    if y not in summary.columns:
        print(f"Skipping heatmap for {y}: column not found")
        return

    plot_dir = OUT / "final_heatmaps"
    plot_dir.mkdir(parents=True, exist_ok=True)

    clean_summary = summary.copy()
    clean_summary[y] = pd.to_numeric(clean_summary[y], errors="coerce")
    clean_summary[y] = clean_summary[y].replace([np.inf, -np.inf], np.nan)

    clean_summary = clean_summary.dropna(subset=[y, "T", "strain_rate"])

    if clean_summary.empty:
        print(f"Skipping heatmap for {y}: no finite values")
        return

    max_abs = clean_summary[y].abs().max()

    if max_abs > 1e100:
        print(f"Skipping heatmap for {y}: values are too large, max_abs = {max_abs:.3e}")
        return

    pivot = clean_summary.pivot_table(
        index="T",
        columns="strain_rate",
        values=y,
        aggfunc="mean",
    )

    pivot = pivot.sort_index().sort_index(axis=1)

    if pivot.empty:
        print(f"Skipping heatmap for {y}: empty pivot table")
        return

    values = pivot.values.astype(float)

    if not np.isfinite(values).any():
        print(f"Skipping heatmap for {y}: no finite pivot values")
        return

    plt.figure()

    image = plt.imshow(
        values,
        origin="lower",
        aspect="auto",
    )

    plt.colorbar(image, label=ylabel)

    plt.xticks(
        np.arange(len(pivot.columns)),
        [f"{x:g}" for x in pivot.columns],
        rotation=45,
    )

    plt.yticks(
        np.arange(len(pivot.index)),
        [f"{x:g}" for x in pivot.index],
    )

    plt.xlabel("strain rate, 1/s")
    plt.ylabel("temperature, K")
    plt.title(f"Final {ylabel}")

    for i in range(pivot.shape[0]):
        for j in range(pivot.shape[1]):
            value = pivot.values[i, j]
            if np.isfinite(value):
                plt.text(j, i, f"{value:.2g}", ha="center", va="center")

    plt.tight_layout()
    plt.savefig(plot_dir / f"final_{y}.png", dpi=300)
    plt.close()

def plot_final_log_heatmap(summary, y, ylabel):
    if y not in summary.columns:
        return

    plot_dir = OUT / "final_log_heatmaps"
    plot_dir.mkdir(parents=True, exist_ok=True)

    clean_summary = summary.copy()
    clean_summary[y] = pd.to_numeric(clean_summary[y], errors="coerce")
    clean_summary[y] = clean_summary[y].replace([np.inf, -np.inf], np.nan)

    clean_summary = clean_summary.dropna(subset=[y, "T", "strain_rate"])
    clean_summary = clean_summary[clean_summary[y] > 0]

    if clean_summary.empty:
        print(f"Skipping log heatmap for {y}: no positive finite values")
        return

    clean_summary[f"log10_{y}"] = np.log10(clean_summary[y])

    pivot = clean_summary.pivot_table(
        index="T",
        columns="strain_rate",
        values=f"log10_{y}",
        aggfunc="mean",
    )

    pivot = pivot.sort_index().sort_index(axis=1)

    plt.figure()

    image = plt.imshow(
        pivot.values,
        origin="lower",
        aspect="auto",
    )

    plt.colorbar(image, label=f"log10({ylabel})")

    plt.xticks(
        np.arange(len(pivot.columns)),
        [f"{x:g}" for x in pivot.columns],
        rotation=45,
    )

    plt.yticks(
        np.arange(len(pivot.index)),
        [f"{x:g}" for x in pivot.index],
    )

    plt.xlabel("strain rate, 1/s")
    plt.ylabel("temperature, K")
    plt.title(f"Final log10({ylabel})")

    for i in range(pivot.shape[0]):
        for j in range(pivot.shape[1]):
            value = pivot.values[i, j]
            if np.isfinite(value):
                plt.text(j, i, f"{value:.1f}", ha="center", va="center")

    plt.tight_layout()
    plt.savefig(plot_dir / f"final_log10_{y}.png", dpi=300)
    plt.close()


def main():
    OUT.mkdir(parents=True, exist_ok=True)

    data = load_data(ROOT)
    data.to_csv(OUT / "combined_diagnostic_data.csv", index=False)

    metrics = {
        "nuc_insertions": "nucleation insertions",
        "nuc_deletions": "nucleation deletions",
        "nuc_count": "nucleation count",
        "P_nuc_avg": "average nucleation probability",
        "nuc_drive_ratio_avg": "nucleation driving ratio",
        "rho_eff_avg": r"$\rho_{eff}$",
        "rho_avg": r"$\rho_{avg}$",
        "Def_Eng": "stored deformation energy",
        "beta_avg": "beta average",
        "D_avg": "average equivalent grain diameter",
        "D_norm": "normalized grain diameter, D/D0",
        "gb_length": "grain-boundary length",
        "grain_count": "grain count",
        "dt_actual": "actual time step",
    }

    for y, ylabel in metrics.items():
        plot_fixed_T(data, y, ylabel)
        plot_fixed_rate(data, y, ylabel)

    summary = make_final_summary(data)
    summary.to_csv(OUT / "final_case_summary.csv", index=False)

    for y, ylabel in metrics.items():
        plot_final_heatmap(summary, y, ylabel)

    log_heatmap_metrics = {
        "P_nuc_avg": "average nucleation probability",
        "nuc_drive_ratio_avg": "nucleation driving ratio",
        "rho_eff_avg": r"$\rho_{eff}$",
        "rho_avg": r"$\rho_{avg}$",
        "Def_Eng": "stored deformation energy",
    }

    for y, ylabel in log_heatmap_metrics.items():
        plot_final_log_heatmap(summary, y, ylabel)

    print("Finished diagnostic plotting.")
    print(f"Combined data: {OUT / 'combined_diagnostic_data.csv'}")
    print(f"Final summary: {OUT / 'final_case_summary.csv'}")
    print(f"Plots: {OUT}")


if __name__ == "__main__":
    main()