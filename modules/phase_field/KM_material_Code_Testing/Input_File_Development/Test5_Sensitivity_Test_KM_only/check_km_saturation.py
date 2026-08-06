#!/usr/bin/env python3
"""Check KM-only MOOSE results against the analytical KM solution.

Assumed model:
    d(rho)/dt = time_scale * [k1 * gamma_dot * sqrt(rho) - k2_dyn * rho]

At saturation, storage and dynamic recovery balance:
    rho_sat = (k1 * gamma_dot / k2_dyn)^2

The continuous analytical transient is:
    rho(t) = [sqrt(rho_sat)
              + (sqrt(rho_init) - sqrt(rho_sat))
                * exp(-time_scale * k2_dyn * t / 2)]^2

The script recursively reads KM_output/**/km.csv, writes a summary CSV,
and optionally makes one comparison plot per case.
"""

from __future__ import annotations

import argparse
import math
import re
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt


REQUIRED_COLUMNS = {
    "time",
    "T_avg",
    "gdot_avg",
    "k1_avg",
    "k2dyn_t_avg",
    "rho_avg",
}


def read_case_settings(case_dir: Path) -> dict[str, str]:
    """Read key = value entries from case_settings.txt when available."""
    settings: dict[str, str] = {}
    path = case_dir / "case_settings.txt"

    if not path.exists():
        return settings

    for line in path.read_text().splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        settings[key.strip()] = value.strip()

    return settings


def parse_folder_number(text: str) -> float:
    """Convert tags such as 0p1, 1p0, or 1e16 to floats."""
    cleaned = text.replace("p", ".").replace(",", ".")
    if cleaned.startswith("m"):
        cleaned = "-" + cleaned[1:]
    return float(cleaned)


def infer_rho_init(csv_path: Path, settings: dict[str, str]) -> float:
    """Read rho_init from case_settings.txt or a rho_* parent folder."""
    for key in ("rho_init_i", "rho_init"):
        if key in settings:
            return float(settings[key])

    for part in reversed(csv_path.parts):
        if part.startswith("rho_"):
            return parse_folder_number(part[len("rho_"):])

    raise ValueError(
        f"Could not determine rho_init for {csv_path}. "
        "Add case_settings.txt or use a parent folder such as rho_1e16."
    )


def positive_median(series: pd.Series, name: str) -> float:
    values = pd.to_numeric(series, errors="coerce")
    values = values[np.isfinite(values) & (values > 0)]
    if values.empty:
        raise ValueError(f"No positive finite values found for {name}")
    return float(values.median())


def finite_median(series: pd.Series, name: str) -> float:
    values = pd.to_numeric(series, errors="coerce")
    values = values[np.isfinite(values)]
    if values.empty:
        raise ValueError(f"No finite values found for {name}")
    return float(values.median())


def analyze_case(
    csv_path: Path,
    plot_dir: Path,
    make_plots: bool,
    numerical_tolerance_pct: float,
    saturation_tolerance_pct: float,
) -> dict[str, object]:
    df = pd.read_csv(csv_path)

    missing = REQUIRED_COLUMNS.difference(df.columns)
    if missing:
        raise ValueError(f"Missing columns: {sorted(missing)}")

    settings = read_case_settings(csv_path.parent)
    rho_init = infer_rho_init(csv_path, settings)
    time_scale = float(settings.get("time_scale_i", settings.get("time_scale", 1.0)))

    k1 = positive_median(df["k1_avg"], "k1_avg")
    k2 = positive_median(df["k2dyn_t_avg"], "k2dyn_t_avg")
    gdot = positive_median(df["gdot_avg"], "gdot_avg")
    temperature = positive_median(df["T_avg"], "T_avg")

    # Storage = recovery at saturation:
    # k1*gdot*sqrt(rho_sat) = k2*rho_sat
    rho_sat = (k1 * gdot / k2) ** 2

    work = pd.DataFrame(
        {
            "time": pd.to_numeric(df["time"], errors="coerce"),
            "rho_moose": pd.to_numeric(df["rho_avg"], errors="coerce"),
        }
    )
    work = work.replace([np.inf, -np.inf], np.nan).dropna()

    # The INITIAL postprocessor row may be zero even though rho_init is nonzero.
    work = work[(work["time"] >= 0) & (work["rho_moose"] > 0)].copy()
    work = work.sort_values("time").reset_index(drop=True)

    if work.empty:
        raise ValueError("No positive finite rho_avg data points")

    sqrt_rho_sat = math.sqrt(rho_sat)
    sqrt_rho_init = math.sqrt(rho_init)

    work["rho_exact"] = (
        sqrt_rho_sat
        + (sqrt_rho_init - sqrt_rho_sat)
        * np.exp(-0.5 * time_scale * k2 * work["time"])
    ) ** 2

    work["relative_error"] = (
        work["rho_moose"] - work["rho_exact"]
    ) / work["rho_exact"]

    final = work.iloc[-1]
    final_time = float(final["time"])
    rho_final = float(final["rho_moose"])
    rho_exact_final = float(final["rho_exact"])

    trajectory_rmse_pct = float(
        100.0 * np.sqrt(np.mean(np.square(work["relative_error"])))
    )
    trajectory_max_abs_pct = float(100.0 * work["relative_error"].abs().max())
    final_vs_exact_pct = 100.0 * (rho_final / rho_exact_final - 1.0)
    final_vs_sat_pct = 100.0 * (rho_final / rho_sat - 1.0)

    # The deviation in sqrt(rho) decays with time constant 2/(time_scale*k2).
    tau_sqrt = 2.0 / (time_scale * k2)
    t_99_sqrt = math.log(100.0) * tau_sqrt
    strain_99_sqrt = gdot * t_99_sqrt

    numerical_check = (
        "OK"
        if abs(final_vs_exact_pct) <= numerical_tolerance_pct
        else "CHECK_NUMERICS"
    )
    saturation_check = (
        "REACHED"
        if abs(final_vs_sat_pct) <= saturation_tolerance_pct
        else "NOT_REACHED"
    )

    expected_direction = (
        "increase"
        if rho_init < rho_sat
        else "decrease"
        if rho_init > rho_sat
        else "constant"
    )

    if make_plots:
        # Use the last three directory names for readable unique filenames.
        parts = list(csv_path.parent.parts[-3:])
        plot_name = "_".join(parts) + ".png"

        fig, ax = plt.subplots(figsize=(7.5, 5.0))
        ax.semilogy(
            work["time"],
            work["rho_moose"],
            label="MOOSE rho_avg",
            linewidth=2,
        )
        ax.semilogy(
            work["time"],
            work["rho_exact"],
            "--",
            label="Analytical KM transient",
            linewidth=2,
        )
        ax.axhline(
            rho_sat,
            linestyle=":",
            label=f"rho_sat = {rho_sat:.3e}",
        )
        ax.set_xlabel("time, s")
        ax.set_ylabel(r"dislocation density, $\rho$ (m$^{-2}$)")
        ax.set_title(
            f"T={temperature:g} K, strain rate={gdot:g} s$^{{-1}}$, "
            f"rho_init={rho_init:.1e}"
        )
        ax.legend()
        fig.tight_layout()
        fig.savefig(plot_dir / plot_name, dpi=250)
        plt.close(fig)

    return {
        "rho_init": rho_init,
        "T_K": temperature,
        "strain_rate_per_s": gdot,
        "time_scale": time_scale,
        "k1": k1,
        "k2dyn_t": k2,
        "rho_sat": rho_sat,
        "rho_final": rho_final,
        "rho_exact_final": rho_exact_final,
        "rho_final_over_rho_sat": rho_final / rho_sat,
        "rho_final_over_rho_exact": rho_final / rho_exact_final,
        "final_vs_sat_pct": final_vs_sat_pct,
        "final_vs_exact_pct": final_vs_exact_pct,
        "trajectory_rmse_pct": trajectory_rmse_pct,
        "trajectory_max_abs_pct": trajectory_max_abs_pct,
        "tau_sqrt_s": tau_sqrt,
        "t_99_sqrt_s": t_99_sqrt,
        "strain_99_sqrt": strain_99_sqrt,
        "final_time_s": final_time,
        "final_accumulated_strain": gdot * final_time,
        "expected_direction": expected_direction,
        "numerical_check": numerical_check,
        "saturation_check": saturation_check,
        "csv_file": str(csv_path),
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compare KM-only MOOSE CSV results with analytical saturation and transient solutions."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path("KM_output_dstrainPerStep1e-3_strainrate60"),                 # KM_output
        help="Root folder containing nested km.csv files (default: KM_output)",
    )
    parser.add_argument(
        "--no-plots",
        action="store_true",
        help="Do not create per-case comparison plots",
    )
    parser.add_argument(
        "--numerical-tolerance-pct",
        type=float,
        default=2.0,
        help="Allowed final MOOSE-vs-analytical error in percent (default: 2)",
    )
    parser.add_argument(
        "--saturation-tolerance-pct",
        type=float,
        default=5.0,
        help="Tolerance for declaring saturation reached in percent (default: 5)",
    )
    args = parser.parse_args()

    root = args.root.expanduser().resolve()
    out_dir = root / "saturation_check"
    plot_dir = out_dir / "plots"
    out_dir.mkdir(parents=True, exist_ok=True)
    plot_dir.mkdir(parents=True, exist_ok=True)

    csv_files = sorted(root.rglob("km.csv"))
    if not csv_files:
        raise FileNotFoundError(f"No km.csv files found below {root}")

    rows: list[dict[str, object]] = []
    failures: list[dict[str, str]] = []

    for csv_path in csv_files:
        try:
            rows.append(
                analyze_case(
                    csv_path=csv_path,
                    plot_dir=plot_dir,
                    make_plots=not args.no_plots,
                    numerical_tolerance_pct=args.numerical_tolerance_pct,
                    saturation_tolerance_pct=args.saturation_tolerance_pct,
                )
            )
        except Exception as exc:  # Continue through all cases and report failures.
            failures.append({"csv_file": str(csv_path), "error": str(exc)})
            print(f"Skipped {csv_path}: {exc}")

    if not rows:
        raise RuntimeError("No cases could be analyzed")

    summary = pd.DataFrame(rows).sort_values(
        ["rho_init", "T_K", "strain_rate_per_s"]
    )
    summary_path = out_dir / "km_saturation_summary.csv"
    summary.to_csv(summary_path, index=False)

    if failures:
        pd.DataFrame(failures).to_csv(out_dir / "skipped_cases.csv", index=False)

    print("\nKM saturation check complete.")
    print(f"Analyzed cases: {len(summary)}")
    print(f"Skipped cases:  {len(failures)}")
    print(f"Summary:        {summary_path}")
    if not args.no_plots:
        print(f"Plots:          {plot_dir}")

    print("\nNumerical comparison counts:")
    print(summary["numerical_check"].value_counts(dropna=False).to_string())

    print("\nSaturation status counts:")
    print(summary["saturation_check"].value_counts(dropna=False).to_string())

    print("\nCases with the largest analytical-trajectory mismatch:")
    cols = [
        "rho_init",
        "T_K",
        "strain_rate_per_s",
        "rho_sat",
        "rho_final",
        "final_vs_exact_pct",
        "trajectory_rmse_pct",
        "numerical_check",
        "saturation_check",
    ]
    print(
        summary.nlargest(10, "trajectory_rmse_pct")[cols].to_string(
            index=False,
            float_format=lambda x: f"{x:.5g}",
        )
    )


if __name__ == "__main__":
    main()