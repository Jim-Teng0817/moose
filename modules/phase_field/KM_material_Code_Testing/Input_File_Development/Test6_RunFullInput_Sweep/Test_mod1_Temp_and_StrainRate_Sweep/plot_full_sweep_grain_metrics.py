#!/usr/bin/env python3

from pathlib import Path
import argparse
import re

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt


def read_case_settings(case_dir: Path) -> dict:
    settings = {}

    settings_file = case_dir / "case_settings.txt"

    if settings_file.exists():
        for line in settings_file.read_text().splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                settings[key.strip()] = value.strip()

    return settings


def parse_number(text):
    text = str(text).replace("p", ".").replace(",", ".")
    match = re.search(r"[-+]?\d*\.?\d+(?:e[-+]?\d+)?", text)
    if match is None:
        return np.nan
    return float(match.group(0))


def parse_metadata_from_path(path: Path) -> dict:
    metadata = {
        "T": np.nan,
        "strain_rate": np.nan,
        "rho_init": np.nan,
    }

    for part in path.parts:
        lower = part.lower()

        if lower.startswith("t_"):
            metadata["T"] = parse_number(part)

        elif lower.startswith("gdot_"):
            metadata["strain_rate"] = parse_number(part)

        elif lower.startswith("rho_"):
            metadata["rho_init"] = parse_number(part)

    return metadata


def find_column(df, possible_names):
    clean_map = {
        re.sub(r"[^a-zA-Z0-9]", "", c.lower()): c
        for c in df.columns
    }

    for name in possible_names:
        clean = re.sub(r"[^a-zA-Z0-9]", "", name.lower())
        if clean in clean_map:
            return clean_map[clean]

    return None


def safe_tag(value):
    return f"{value:g}".replace(".", "p").replace("-", "m")


def equivalent_diameter_from_area(area):
    return 2.0 * np.sqrt(area / np.pi)


def load_scalar_results(root: Path) -> pd.DataFrame:
    csv_files = sorted(root.rglob("result.csv"))

    if not csv_files:
        csv_files = sorted(root.rglob("*.csv"))

    rows = []

    for csv_path in csv_files:
        if "logs" in csv_path.parts or "plots" in csv_path.parts:
            continue

        if "grain_volumes" in csv_path.name:
            continue

        try:
            df = pd.read_csv(csv_path)
        except Exception:
            continue

        time_col = find_column(df, ["time"])
        if time_col is None:
            continue

        case_dir = csv_path.parent
        settings = read_case_settings(case_dir)
        metadata = parse_metadata_from_path(csv_path)

        T = float(settings.get("T_i", metadata["T"]))
        strain_rate = float(settings.get("strain_rate_i", metadata["strain_rate"]))
        rho_init = float(settings.get("rho_init_i", metadata["rho_init"]))

        out = pd.DataFrame()
        out["time"] = pd.to_numeric(df[time_col], errors="coerce")
        out["T"] = T
        out["strain_rate"] = strain_rate
        out["rho_init"] = rho_init
        out["source_file"] = str(csv_path)

        optional_cols = {
            "avg_grain_area": ["avg_grain_area", "average_grain_volume"],
            "gb_length": ["gb_length", "grain_boundary_area"],
            "rho_avg": ["rho_avg"],
            "rho_eff_avg": ["rho_eff_avg"],
            "tau_avg": ["tau_avg"],
            "Def_Eng": ["Def_Eng"],
            "beta_avg": ["beta_avg"],
            "nuc_count": ["nuc_count"],
            "nuc_insertions": ["nuc_insertions"],
            "nuc_deletions": ["nuc_deletions"],
            "T_avg": ["T_avg"],
            "gdot_avg": ["gdot_avg"],
        }

        for out_col, names in optional_cols.items():
            col = find_column(df, names)
            if col is not None:
                out[out_col] = pd.to_numeric(df[col], errors="coerce")
            else:
                out[out_col] = np.nan

        out["accumulated_strain"] = out["strain_rate"] * out["time"]

        if not out["avg_grain_area"].isna().all():
            out["D_avg"] = equivalent_diameter_from_area(out["avg_grain_area"])
        else:
            out["D_avg"] = np.nan

        rows.append(out)

    if not rows:
        raise RuntimeError(f"No scalar result CSV files found under {root}")

    data = pd.concat(rows, ignore_index=True)

    data = data.dropna(subset=["time", "T", "strain_rate"])
    data = data.sort_values(["T", "strain_rate", "time"]).reset_index(drop=True)

    group_cols = ["T", "strain_rate"]

    if not data["D_avg"].isna().all():
        data["D_initial"] = data.groupby(group_cols)["D_avg"].transform(
            lambda s: s[s > 0].iloc[0] if (s > 0).any() else np.nan
        )
        data["D_norm"] = data["D_avg"] / data["D_initial"]

    return data


def load_one_grain_volume_file(vpp_file: Path) -> pd.DataFrame | None:
    try:
        df = pd.read_csv(vpp_file)
    except Exception:
        return None

    volume_col = find_column(
        df,
        ["feature_volumes", "feature_volume", "volume", "grain_volume"],
    )

    if volume_col is None:
        return None

    out = pd.DataFrame()
    out["area"] = pd.to_numeric(df[volume_col], errors="coerce")

    var_col = find_column(df, ["var_num"])
    if var_col is not None:
        out["var_num"] = pd.to_numeric(df[var_col], errors="coerce")
    else:
        out["var_num"] = 0

    bounds_col = find_column(df, ["intersects_bounds", "intersects_boundary"])
    if bounds_col is not None:
        out["intersects_bounds"] = pd.to_numeric(df[bounds_col], errors="coerce")
    else:
        out["intersects_bounds"] = 0

    out = out.dropna(subset=["area"])
    out = out[out["area"] > 0]
    out = out[out["var_num"] != -1]

    if out.empty:
        return None

    out["D"] = equivalent_diameter_from_area(out["area"])

    return out


def summarize_grain_distribution(grain_df: pd.DataFrame) -> dict:
    areas = grain_df["area"].to_numpy()
    diameters = grain_df["D"].to_numpy()

    total_area = areas.sum()

    if len(diameters) == 0 or total_area <= 0:
        return {}

    weights = areas / total_area

    summary = {
        "grain_count_from_vpp": len(diameters),
        "total_grain_area_from_vpp": total_area,
        "mean_area": np.mean(areas),
        "median_area": np.median(areas),
        "mean_D": np.mean(diameters),
        "area_weighted_mean_D": np.sum(weights * diameters),
        "D10": np.percentile(diameters, 10),
        "D50": np.percentile(diameters, 50),
        "D90": np.percentile(diameters, 90),
        "D_std": np.std(diameters),
        "D_cv": np.std(diameters) / np.mean(diameters),
        "largest_grain_area_fraction": areas.max() / total_area,
    }

    summary["D90_over_D10"] = summary["D90"] / summary["D10"]

    return summary


def load_distribution_results(root: Path, scalar_data: pd.DataFrame) -> pd.DataFrame:
    vpp_files = sorted(root.rglob("*grain_volumes*.csv"))

    rows = []

    for case_dir in sorted({p.parent for p in vpp_files}):
        case_vpp_files = sorted(case_dir.glob("*grain_volumes*.csv"))

        if not case_vpp_files:
            continue

        case_scalar = scalar_data[
            scalar_data["source_file"].str.startswith(str(case_dir))
        ].copy()

        if case_scalar.empty:
            continue

        case_scalar = case_scalar.sort_values("time").reset_index(drop=True)

        for i, vpp_file in enumerate(case_vpp_files):
            grain_df = load_one_grain_volume_file(vpp_file)

            if grain_df is None:
                continue

            if i < len(case_scalar):
                time = case_scalar.loc[i, "time"]
                T = case_scalar.loc[i, "T"]
                strain_rate = case_scalar.loc[i, "strain_rate"]
                rho_init = case_scalar.loc[i, "rho_init"]
                accumulated_strain = case_scalar.loc[i, "accumulated_strain"]
            else:
                time = np.nan
                T = case_scalar["T"].iloc[0]
                strain_rate = case_scalar["strain_rate"].iloc[0]
                rho_init = case_scalar["rho_init"].iloc[0]
                accumulated_strain = np.nan

            summary = summarize_grain_distribution(grain_df)
            if not summary:
                continue

            summary.update(
                {
                    "time": time,
                    "T": T,
                    "strain_rate": strain_rate,
                    "rho_init": rho_init,
                    "accumulated_strain": accumulated_strain,
                    "vpp_file": str(vpp_file),
                }
            )

            rows.append(summary)

    if not rows:
        return pd.DataFrame()

    data = pd.DataFrame(rows)
    data = data.sort_values(["T", "strain_rate", "time"]).reset_index(drop=True)

    group_cols = ["T", "strain_rate"]

    data["mean_D_initial"] = data.groupby(group_cols)["mean_D"].transform(
        lambda s: s[s > 0].iloc[0] if (s > 0).any() else np.nan
    )

    data["mean_D_norm"] = data["mean_D"] / data["mean_D_initial"]

    return data


def plot_lines(data, y_col, y_label, out_dir, x_col="accumulated_strain"):
    if y_col not in data.columns or data[y_col].isna().all():
        return

    plot_dir = out_dir / f"{y_col}_lines"
    plot_dir.mkdir(parents=True, exist_ok=True)

    for T, group_T in data.groupby("T"):
        plt.figure()

        for rate, curve in group_T.groupby("strain_rate"):
            curve = curve.sort_values(x_col)
            plt.plot(curve[x_col], curve[y_col], label=f"{rate:g} 1/s")

        plt.xlabel("accumulated strain" if x_col == "accumulated_strain" else x_col)
        plt.ylabel(y_label)
        plt.title(f"{y_label} at T = {T:g} K")
        plt.legend(title="strain rate")
        plt.tight_layout()
        plt.savefig(plot_dir / f"T_{safe_tag(T)}_{y_col}.png", dpi=300)
        plt.close()

    for rate, group_rate in data.groupby("strain_rate"):
        plt.figure()

        for T, curve in group_rate.groupby("T"):
            curve = curve.sort_values(x_col)
            plt.plot(curve[x_col], curve[y_col], label=f"{T:g} K")

        plt.xlabel("accumulated strain" if x_col == "accumulated_strain" else x_col)
        plt.ylabel(y_label)
        plt.title(f"{y_label} at strain rate = {rate:g} 1/s")
        plt.legend(title="temperature")
        plt.tight_layout()
        plt.savefig(plot_dir / f"gdot_{safe_tag(rate)}_{y_col}.png", dpi=300)
        plt.close()


def plot_final_heatmap(data, y_col, y_label, out_dir):
    if y_col not in data.columns or data[y_col].isna().all():
        return

    plot_dir = out_dir / "final_heatmaps"
    plot_dir.mkdir(parents=True, exist_ok=True)

    final_rows = (
        data.sort_values("time")
        .groupby(["T", "strain_rate"], as_index=False)
        .tail(1)
    )

    pivot = final_rows.pivot_table(
        index="T",
        columns="strain_rate",
        values=y_col,
        aggfunc="mean",
    )

    pivot = pivot.sort_index().sort_index(axis=1)

    plt.figure()
    img = plt.imshow(pivot.values, origin="lower", aspect="auto")
    plt.colorbar(img, label=y_label)

    plt.xticks(
        ticks=np.arange(len(pivot.columns)),
        labels=[f"{x:g}" for x in pivot.columns],
        rotation=45,
    )

    plt.yticks(
        ticks=np.arange(len(pivot.index)),
        labels=[f"{x:g}" for x in pivot.index],
    )

    plt.xlabel("strain rate, 1/s")
    plt.ylabel("temperature, K")
    plt.title(f"Final {y_label}")

    for i in range(pivot.shape[0]):
        for j in range(pivot.shape[1]):
            value = pivot.values[i, j]
            if np.isfinite(value):
                plt.text(j, i, f"{value:.2g}", ha="center", va="center")

    plt.tight_layout()
    plt.savefig(plot_dir / f"final_{y_col}.png", dpi=300)
    plt.close()


def plot_final_cdfs(root: Path, dist_data: pd.DataFrame, out_dir: Path):
    if dist_data.empty:
        return

    plot_dir = out_dir / "final_grain_size_cdfs"
    plot_dir.mkdir(parents=True, exist_ok=True)

    final_rows = (
        dist_data.sort_values("time")
        .groupby(["T", "strain_rate"], as_index=False)
        .tail(1)
    )

    for T, group_T in final_rows.groupby("T"):
        plt.figure()

        for _, row in group_T.iterrows():
            grain_df = load_one_grain_volume_file(Path(row["vpp_file"]))
            if grain_df is None:
                continue

            D = np.sort(grain_df["D"].to_numpy())
            number_fraction = np.arange(1, len(D) + 1) / len(D)

            plt.plot(D, number_fraction, label=f"{row['strain_rate']:g} 1/s")

        plt.xlabel("equivalent grain diameter")
        plt.ylabel("cumulative number fraction")
        plt.title(f"Final grain-size CDF at T = {T:g} K")
        plt.legend(title="strain rate")
        plt.tight_layout()
        plt.savefig(plot_dir / f"T_{safe_tag(T)}_number_CDF.png", dpi=300)
        plt.close()

    for T, group_T in final_rows.groupby("T"):
        plt.figure()

        for _, row in group_T.iterrows():
            grain_df = load_one_grain_volume_file(Path(row["vpp_file"]))
            if grain_df is None:
                continue

            grain_df = grain_df.sort_values("D")
            D = grain_df["D"].to_numpy()
            area_fraction = np.cumsum(grain_df["area"].to_numpy()) / grain_df["area"].sum()

            plt.plot(D, area_fraction, label=f"{row['strain_rate']:g} 1/s")

        plt.xlabel("equivalent grain diameter")
        plt.ylabel("cumulative area fraction")
        plt.title(f"Final area-weighted grain-size CDF at T = {T:g} K")
        plt.legend(title="strain rate")
        plt.tight_layout()
        plt.savefig(plot_dir / f"T_{safe_tag(T)}_area_CDF.png", dpi=300)
        plt.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("FullSweep_rho1e16"))
    parser.add_argument("--domain-area", type=float, default="1562500")
    parser.add_argument("--length-unit", type=str, default="mu m")
    args = parser.parse_args()

    root = args.root.expanduser().resolve()
    out_dir = root / "comparison_plots"
    out_dir.mkdir(parents=True, exist_ok=True)

    scalar = load_scalar_results(root)

    if args.domain_area is not None and "gb_length" in scalar.columns:
        scalar["gb_length_density"] = scalar["gb_length"] / args.domain_area

    scalar_path = out_dir / "combined_scalar_results.csv"
    scalar.to_csv(scalar_path, index=False)

    dist = load_distribution_results(root, scalar)

    if not dist.empty:
        dist_path = out_dir / "combined_distribution_results.csv"
        dist.to_csv(dist_path, index=False)
    else:
        dist_path = None

    # Scalar grain metrics
    plot_lines(
        scalar,
        "D_avg",
        f"average equivalent grain diameter, {args.length_unit}",
        out_dir,
    )

    plot_lines(
        scalar,
        "D_norm",
        "normalized average grain size, D / D0",
        out_dir,
    )

    plot_lines(
        scalar,
        "gb_length",
        f"total grain-boundary length, {args.length_unit}",
        out_dir,
    )

    if "gb_length_density" in scalar.columns:
        plot_lines(
            scalar,
            "gb_length_density",
            "grain-boundary length density",
            out_dir,
        )

    plot_lines(
        scalar,
        "rho_avg",
        r"$\rho_{avg}$, 1/m$^2$",
        out_dir,
    )

    plot_lines(
        scalar,
        "nuc_insertions",
        "nucleation insertions",
        out_dir,
    )

    plot_final_heatmap(
        scalar,
        "D_avg",
        f"final average equivalent grain diameter, {args.length_unit}",
        out_dir,
    )

    plot_final_heatmap(
        scalar,
        "D_norm",
        "final normalized grain size, D / D0",
        out_dir,
    )

    plot_final_heatmap(
        scalar,
        "gb_length",
        f"final grain-boundary length, {args.length_unit}",
        out_dir,
    )

    # Distribution metrics
    if not dist.empty:
        plot_lines(
            dist,
            "mean_D",
            f"mean individual-grain diameter, {args.length_unit}",
            out_dir,
        )

        plot_lines(
            dist,
            "D50",
            f"median grain diameter D50, {args.length_unit}",
            out_dir,
        )

        plot_lines(
            dist,
            "D90_over_D10",
            "grain-size spread, D90 / D10",
            out_dir,
        )

        plot_lines(
            dist,
            "D_cv",
            "grain-size coefficient of variation",
            out_dir,
        )

        plot_lines(
            dist,
            "largest_grain_area_fraction",
            "largest grain area fraction",
            out_dir,
        )

        plot_final_heatmap(
            dist,
            "D50",
            f"final D50, {args.length_unit}",
            out_dir,
        )

        plot_final_heatmap(
            dist,
            "D90_over_D10",
            "final D90 / D10",
            out_dir,
        )

        plot_final_heatmap(
            dist,
            "grain_count_from_vpp",
            "final grain count",
            out_dir,
        )

        plot_final_cdfs(root, dist, out_dir)

    print("Finished analysis.")
    print()
    print("Scalar combined results:")
    print(scalar_path)

    if dist_path is not None:
        print()
        print("Distribution combined results:")
        print(dist_path)
    else:
        print()
        print("No grain-volume distribution files found.")
        print("Check that FeatureVolumeVectorPostprocessor output was enabled.")

    print()
    print("Plots saved under:")
    print(out_dir)


if __name__ == "__main__":
    main()