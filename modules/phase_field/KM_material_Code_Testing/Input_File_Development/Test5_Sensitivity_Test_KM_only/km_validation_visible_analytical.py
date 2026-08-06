#!/usr/bin/env python3
"""Create physical-trend and numerical-validation plots for a KM-only sweep.

Assumed Kocks-Mecking equation
--------------------------------
    d(rho)/dt = time_scale * [k1 * gamma_dot * sqrt(rho) - k2_dyn * rho]

Saturation density
------------------
    rho_sat = (k1 * gamma_dot / k2_dyn)^2

Analytical transient
--------------------
    sqrt(rho(t)) = sqrt(rho_sat)
                   + [sqrt(rho_init) - sqrt(rho_sat)]
                     exp[-time_scale * k2_dyn * t / 2]

Expected directory structure
----------------------------
    KM_output/
      rho_1e16/
        T_1073/
          gdot_10p0/
            km.csv
            case_settings.txt   # optional but recommended

The script creates, for each selected rho_init:
  1. A four-panel physical-trend dashboard similar to the supplied example.
  2. A four-panel numerical-validation heatmap dashboard.
  3. An initial-condition convergence plot at a selected T and strain rate.
  4. Worst-case MOOSE-versus-analytical comparison plots.
  5. CSV summaries for quantitative reporting.
"""

from __future__ import annotations

import argparse
import math
import re
from pathlib import Path
from typing import Iterable

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


REQUIRED_COLUMNS = {
    "time",
    "T_avg",
    "gdot_avg",
    "k1_avg",
    "k2dyn_t_avg",
    "rho_avg",
}


def read_case_settings(case_dir: Path) -> dict[str, str]:
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


def parse_tag_number(text: str) -> float:
    """Convert tags such as 0p1, 1p0, m1p0, and 1e16 to floats."""
    value = str(text).strip().replace(",", ".")
    if value.startswith("m"):
        value = "-" + value[1:]
    value = value.replace("p", ".")
    return float(value)


def infer_from_path(path: Path, prefix: str) -> float | None:
    for part in reversed(path.parts):
        if part.startswith(prefix):
            try:
                return parse_tag_number(part[len(prefix):])
            except ValueError:
                return None
    return None


def positive_median(series: pd.Series, name: str) -> float:
    values = pd.to_numeric(series, errors="coerce")
    values = values[np.isfinite(values) & (values > 0)]
    if values.empty:
        raise ValueError(f"No positive finite values for {name}")
    return float(values.median())


def exact_time_to_relative_saturation(
    rho_init: float,
    rho_sat: float,
    k2: float,
    time_scale: float,
    tolerance: float,
) -> float:
    """Exact time until |rho/rho_sat - 1| <= tolerance.

    The criterion is applied to rho, not sqrt(rho). Returns 0 when the
    initial density is already inside the requested saturation band.
    """
    if rho_init <= 0 or rho_sat <= 0 or k2 <= 0 or time_scale <= 0:
        return math.nan
    if not 0 < tolerance < 1:
        raise ValueError("tolerance must be between 0 and 1")

    ratio0 = rho_init / rho_sat
    if abs(ratio0 - 1.0) <= tolerance:
        return 0.0

    y0 = math.sqrt(rho_init)
    ys = math.sqrt(rho_sat)
    decay_rate = 0.5 * time_scale * k2

    if y0 < ys:
        target = ys * math.sqrt(1.0 - tolerance)
        if y0 >= target:
            return 0.0
        exp_factor = (target - ys) / (y0 - ys)
    else:
        target = ys * math.sqrt(1.0 + tolerance)
        if y0 <= target:
            return 0.0
        exp_factor = (target - ys) / (y0 - ys)

    if not 0.0 < exp_factor < 1.0:
        return math.nan
    return -math.log(exp_factor) / decay_rate


def analyze_case(csv_path: Path, saturation_tolerance: float) -> tuple[dict[str, object], pd.DataFrame]:
    df = pd.read_csv(csv_path)
    missing = REQUIRED_COLUMNS.difference(df.columns)
    if missing:
        raise ValueError(f"Missing columns: {sorted(missing)}")

    settings = read_case_settings(csv_path.parent)

    rho_init_text = settings.get("rho_init_i", settings.get("rho_init"))
    if rho_init_text is not None:
        rho_init = float(rho_init_text)
    else:
        inferred = infer_from_path(csv_path, "rho_")
        if inferred is None:
            raise ValueError("Could not infer rho_init")
        rho_init = inferred

    time_scale = float(settings.get("time_scale_i", settings.get("time_scale", 1.0)))
    T = positive_median(df["T_avg"], "T_avg")
    gdot = positive_median(df["gdot_avg"], "gdot_avg")
    k1 = positive_median(df["k1_avg"], "k1_avg")
    k2 = positive_median(df["k2dyn_t_avg"], "k2dyn_t_avg")

    rho_sat = (k1 * gdot / k2) ** 2

    work = pd.DataFrame(
        {
            "time": pd.to_numeric(df["time"], errors="coerce"),
            "rho_moose": pd.to_numeric(df["rho_avg"], errors="coerce"),
        }
    )
    work = work.replace([np.inf, -np.inf], np.nan).dropna()
    work = work[(work["time"] >= 0) & (work["rho_moose"] > 0)].copy()
    work = work.sort_values("time").drop_duplicates("time").reset_index(drop=True)
    if work.empty:
        raise ValueError("No positive finite rho data")

    ys = math.sqrt(rho_sat)
    y0 = math.sqrt(rho_init)
    work["rho_exact"] = (
        ys + (y0 - ys) * np.exp(-0.5 * time_scale * k2 * work["time"])
    ) ** 2
    work["relative_error"] = (work["rho_moose"] - work["rho_exact"]) / work["rho_exact"]

    work["storage"] = k1 * gdot * np.sqrt(work["rho_moose"])
    work["recovery"] = k2 * work["rho_moose"]
    denominator = work["storage"].abs() + work["recovery"].abs()
    work["balance_residual"] = np.where(
        denominator > 0,
        (work["storage"] - work["recovery"]).abs() / denominator,
        np.nan,
    )

    final = work.iloc[-1]
    trajectory_rmse_pct = 100.0 * float(np.sqrt(np.mean(np.square(work["relative_error"]))))
    trajectory_max_abs_pct = 100.0 * float(work["relative_error"].abs().max())
    final_vs_exact_pct = 100.0 * (float(final["rho_moose"]) / float(final["rho_exact"]) - 1.0)
    final_vs_sat_pct = 100.0 * (float(final["rho_moose"]) / rho_sat - 1.0)
    t_to_sat = exact_time_to_relative_saturation(
        rho_init=rho_init,
        rho_sat=rho_sat,
        k2=k2,
        time_scale=time_scale,
        tolerance=saturation_tolerance,
    )

    expected_direction = (
        "increase" if rho_init < rho_sat else "decrease" if rho_init > rho_sat else "constant"
    )
    observed_direction = (
        "increase"
        if float(final["rho_moose"]) > float(work.iloc[0]["rho_moose"])
        else "decrease"
        if float(final["rho_moose"]) < float(work.iloc[0]["rho_moose"])
        else "constant"
    )

    row: dict[str, object] = {
        "rho_init": rho_init,
        "T_K": T,
        "strain_rate_per_s": gdot,
        "time_scale": time_scale,
        "k1": k1,
        "k2dyn_t": k2,
        "rho_sat": rho_sat,
        "rho_first": float(work.iloc[0]["rho_moose"]),
        "rho_final": float(final["rho_moose"]),
        "rho_exact_final": float(final["rho_exact"]),
        "rho_final_over_rho_sat": float(final["rho_moose"]) / rho_sat,
        "rho_final_over_rho_exact": float(final["rho_moose"]) / float(final["rho_exact"]),
        "final_vs_sat_pct": final_vs_sat_pct,
        "final_vs_exact_pct": final_vs_exact_pct,
        "trajectory_rmse_pct": trajectory_rmse_pct,
        "trajectory_max_abs_pct": trajectory_max_abs_pct,
        "final_balance_residual": float(final["balance_residual"]),
        "t_to_relative_saturation_s": t_to_sat,
        "strain_to_relative_saturation": gdot * t_to_sat if np.isfinite(t_to_sat) else math.nan,
        "final_time_s": float(final["time"]),
        "final_accumulated_strain": gdot * float(final["time"]),
        "expected_direction": expected_direction,
        "observed_direction": observed_direction,
        "direction_check": "OK" if expected_direction == observed_direction or expected_direction == "constant" else "CHECK",
        "saturation_reached": "YES" if abs(final_vs_sat_pct) <= 100.0 * saturation_tolerance else "NO",
        "csv_file": str(csv_path),
    }

    work["T_K"] = T
    work["strain_rate_per_s"] = gdot
    work["rho_init"] = rho_init
    work["rho_sat"] = rho_sat
    return row, work


def nearest_available(values: Iterable[float], requested: float) -> float:
    array = np.asarray(sorted(set(float(v) for v in values)), dtype=float)
    if array.size == 0:
        raise ValueError("No available values")
    return float(array[np.argmin(np.abs(array - requested))])


def safe_tag(value: float) -> str:
    return f"{value:.6g}".replace("+", "").replace("-", "m").replace(".", "p")


def add_heatmap(ax: plt.Axes, data: pd.DataFrame, value_col: str, title: str, fmt: str = ".2g") -> None:
    pivot = data.pivot_table(
        index="T_K",
        columns="strain_rate_per_s",
        values=value_col,
        aggfunc="mean",
    ).sort_index().sort_index(axis=1)

    values = pivot.to_numpy(dtype=float)
    masked = np.ma.masked_invalid(values)
    image = ax.imshow(masked, origin="lower", aspect="auto")
    plt.colorbar(image, ax=ax, label=title)

    ax.set_xticks(np.arange(len(pivot.columns)))
    ax.set_xticklabels([f"{x:g}" for x in pivot.columns], rotation=45, ha="right")
    ax.set_yticks(np.arange(len(pivot.index)))
    ax.set_yticklabels([f"{x:g}" for x in pivot.index])
    ax.set_xlabel("strain rate, s$^{-1}$")
    ax.set_ylabel("temperature, K")
    ax.set_title(title)

    finite = values[np.isfinite(values)]
    threshold = np.nanmedian(finite) if finite.size else 0.0
    for i in range(values.shape[0]):
        for j in range(values.shape[1]):
            value = values[i, j]
            if np.isfinite(value):
                text_color = "white" if value < threshold else "black"
                ax.text(j, i, format(value, fmt), ha="center", va="center", color=text_color)


def plot_physical_dashboard(
    case_summary: pd.DataFrame,
    case_curves: dict[str, pd.DataFrame],
    rho_init: float,
    fixed_rate: float,
    fixed_temperature: float,
    out_dir: Path,
    saturation_tolerance: float,
) -> Path:
    subset = case_summary[np.isclose(case_summary["rho_init"], rho_init)].copy()
    if subset.empty:
        raise ValueError(f"No cases found for rho_init={rho_init:g}")

    selected_rate = nearest_available(subset["strain_rate_per_s"], fixed_rate)
    selected_T = nearest_available(subset["T_K"], fixed_temperature)

    fig, axes = plt.subplots(2, 2, figsize=(15, 10))
    ax_temp, ax_rate, ax_sat, ax_time = axes.ravel()

    # Temperature sweep at fixed strain rate.
    # temp_cases = subset[np.isclose(subset["strain_rate_per_s"], selected_rate)].sort_values("T_K")
    # for _, row in temp_cases.iterrows():
    #     curve = case_curves[str(row["csv_file"])]
    #     line, = ax_temp.plot(curve["time"], curve["rho_moose"], label=f"{row['T_K']:g} K")
    #     ax_temp.plot(curve["time"], curve["rho_exact"], "--", color=line.get_color())
    #     ax_temp.axhline(row["rho_sat"], linestyle=":", color=line.get_color(), alpha=0.8)
    # ax_temp.set_xlabel("time, s")
    # ax_temp.set_ylabel(r"dislocation density, $\rho$ (m$^{-2}$)")
    # ax_temp.set_title(f"Temperature sweep at strain rate = {selected_rate:g} s$^{{-1}}$")
    # ax_temp.legend(title="temperature")
    # Temperature sweep at fixed strain rate.
    temp_cases = subset[
        np.isclose(subset["strain_rate_per_s"], selected_rate)
    ].sort_values("T_K")

    for _, row in temp_cases.iterrows():
        curve = case_curves[str(row["csv_file"])]

        # Report rho_sat in units of 1e16 m^-2
        rho_sat_scaled = row["rho_sat"] / 1.0e16

        legend_label = (
            rf"{row['T_K']:g} K, "
            rf"$\rho_{{\mathrm{{sat}}}}={rho_sat_scaled:.2f}"
            rf"\times10^{{16}}\ \mathrm{{m}}^{{-2}}$"
        )

        # MOOSE transient: draw it slightly thicker and lighter.
        # This allows the analytical dashed curve to remain visible even when
        # both solutions overlap almost exactly.
        line, = ax_temp.plot(
            curve["time"],
            curve["rho_moose"],
            linewidth=3.0,
            alpha=0.45,
            zorder=2,
            label=legend_label,
        )

        # Analytical transient: same case color, darker dashed line, plotted
        # on top of the MOOSE curve. It should nearly overlap the solid line.
        ax_temp.plot(
            curve["time"],
            curve["rho_exact"],
            color=line.get_color(),
            linewidth=2.0,
            linestyle=(0, (6, 3)),
            alpha=1.0,
            zorder=4,
            label="_nolegend_",
        )

        # Analytical saturation value.
        ax_temp.axhline(
            row["rho_sat"],
            linestyle=":",
            linewidth=1.8,
            color=line.get_color(),
            alpha=0.9,
            zorder=1,
        )

        ax_temp.set_xlabel("time, s")
        ax_temp.set_ylabel(r"dislocation density, $\rho$ (m$^{-2}$)")
        ax_temp.set_title(
            f"Temperature sweep at strain rate = "
            f"{selected_rate:g} s$^{{-1}}$")
        ax_temp.legend(title="temperature and saturation density", fontsize=9,)

    # Strain-rate sweep at fixed temperature.
    # rate_cases = subset[np.isclose(subset["T_K"], selected_T)].sort_values("strain_rate_per_s")
    # all_positive_time = True
    # for _, row in rate_cases.iterrows():
    #     curve = case_curves[str(row["csv_file"])]
    #     line, = ax_rate.plot(curve["time"], curve["rho_moose"], label=f"{row['strain_rate_per_s']:g} s$^{{-1}}$")
    #     ax_rate.plot(curve["time"], curve["rho_exact"], "--", color=line.get_color())
    #     ax_rate.axhline(row["rho_sat"], linestyle=":", color=line.get_color(), alpha=0.8)
    #     if (curve["time"] <= 0).any():
    #         all_positive_time = False
    # if all_positive_time:
    #     ax_rate.set_xscale("log")
    # ax_rate.set_xlabel("time, s")
    # ax_rate.set_ylabel(r"dislocation density, $\rho$ (m$^{-2}$)")
    # ax_rate.set_title(f"Strain-rate sweep at T = {selected_T:g} K")
    # ax_rate.legend(title="strain rate")
    # Strain-rate sweep at fixed temperature.
    rate_cases = subset[
        np.isclose(subset["T_K"], selected_T)
    ].sort_values("strain_rate_per_s")

    all_positive_time = True

    for _, row in rate_cases.iterrows():
        curve = case_curves[str(row["csv_file"])]

        # Report rho_sat in units of 1e14 m^-2
        rho_sat_scaled = row["rho_sat"] / 1.0e14

        legend_label = (
            rf"$\dot{{\gamma}}={row['strain_rate_per_s']:g}\ "
            rf"\mathrm{{s}}^{{-1}}$, "
            rf"$\rho_{{\mathrm{{sat}}}}={rho_sat_scaled:.2f}"
            rf"\times10^{{14}}\ \mathrm{{m}}^{{-2}}$"
        )

        # MOOSE transient: draw it slightly thicker and lighter so the
        # overlapping analytical dashed curve is still visible.
        line, = ax_rate.plot(
            curve["time"],
            curve["rho_moose"],
            linewidth=3.0,
            alpha=0.45,
            zorder=2,
            label=legend_label,
        )

        # Analytical transient: same case color, darker dashed line, plotted
        # directly on top of the MOOSE solution.
        ax_rate.plot(
            curve["time"],
            curve["rho_exact"],
            color=line.get_color(),
            linewidth=2.0,
            linestyle=(0, (6, 3)),
            alpha=1.0,
            zorder=4,
            label="_nolegend_",
        )

        # Analytical saturation density.
        ax_rate.axhline(
            row["rho_sat"],
            linestyle=":",
            linewidth=1.8,
            color=line.get_color(),
            alpha=0.9,
            zorder=1,
        )

        if (curve["time"] <= 0).any():
            all_positive_time = False

        if all_positive_time:
            ax_rate.set_xscale("log")

        ax_rate.set_xlabel("time, s")
        ax_rate.set_ylabel(r"dislocation density, $\rho$ (m$^{-2}$)")
        ax_rate.set_title(f"Strain-rate sweep at $T={selected_T:g}$ K")

        ax_rate.legend(title="strain rate and saturation density", fontsize=9,)

    # Saturation density versus temperature.
    # for rate, group in subset.groupby("strain_rate_per_s"):
    #     group = group.sort_values("T_K")
    #     ax_sat.plot(group["T_K"], group["rho_sat"], marker="o", label=f"{rate:g} s$^{{-1}}$")
    # ax_sat.set_xlabel("temperature, K")
    # plt.xticks([873, 973, 1073, 1173, 1273])
    # ax_sat.set_ylabel(r"saturation density, $\rho_{sat}$ (m$^{-2}$)")
    # ax_sat.set_title("Steady KM saturation density")
    # ax_sat.legend(title="strain rate")
    # Saturation density versus temperature
    temperature_ticks = [873, 973, 1073, 1173, 1273]

    for rate, group in subset.groupby("strain_rate_per_s"):
        group = group.sort_values("T_K")

        ax_sat.plot(
            group["T_K"],
            group["rho_sat"],
            marker="o",
            label=rf"{rate:g} s$^{{-1}}$",
        )

    ax_sat.set_xlabel("temperature, K")
    ax_sat.set_xticks(temperature_ticks)
    ax_sat.set_xlim(850, 1300)

    ax_sat.set_ylabel(
        r"saturation density, $\rho_{\mathrm{sat}}$ (m$^{-2}$)"
    )
    ax_sat.set_title("Steady KM saturation density")
    ax_sat.legend(title="strain rate")

    # Exact time to requested saturation band.
#     for rate, group in subset.groupby("strain_rate_per_s"):
#         group = group.sort_values("T_K")
#         ax_time.plot(
#             group["T_K"],
#             group["t_to_relative_saturation_s"],
#             marker="o",
#             label=f"{rate:g} s$^{{-1}}$",
#         )
#     positive_times = subset["t_to_relative_saturation_s"]
#     positive_times = positive_times[np.isfinite(positive_times) & (positive_times > 0)]
#     if not positive_times.empty:
#         ax_time.set_yscale("log")
#     ax_time.set_xlabel("temperature, K")
#     plt.xticks([873, 973, 1073, 1173, 1273])
#     ax_time.set_ylabel("time, s")
#     ax_time.set_title(
#         rf"Analytical time to |$\rho/\rho_{{sat}}-1$| ≤ {100*saturation_tolerance:g}%"
#     )
#     ax_time.legend(title="strain rate")
    temperature_ticks = [873, 973, 1073, 1173, 1273]

    for rate, group in subset.groupby("strain_rate_per_s"):
        group = group.sort_values("T_K")

        ax_time.plot(
            group["T_K"],
            group["t_to_relative_saturation_s"],
            marker="o",
            label=rf"{rate:g} s$^{{-1}}$",
        )

    positive_times = subset["t_to_relative_saturation_s"]
    positive_times = positive_times[
        np.isfinite(positive_times) & (positive_times > 0)
    ]

    if not positive_times.empty:
        ax_time.set_yscale("log")

    ax_time.set_xlabel("temperature, K")
    ax_time.set_xticks(temperature_ticks)
    ax_time.set_xlim(850, 1300)

    ax_time.set_ylabel("time, s")
    ax_time.set_title(
        rf"Analytical time to "
        rf"$|\rho/\rho_{{\mathrm{{sat}}}}-1|"
        rf"\leq {100 * saturation_tolerance:g}\%$"
    )

    ax_time.legend(title="strain rate")

    fig.suptitle(
        rf"Kocks-Mecking validation dashboard — $\rho_0$ = {rho_init:.1e} m$^{{-2}}$",
        fontsize=16,
        y=0.99,
    )
    fig.text(
        0.5,
        0.955,
        "Transient panels: solid = MOOSE, dashed = analytical, dotted = saturation",
        ha="center",
        va="top",
        fontsize=10,
    )
    fig.tight_layout(rect=(0, 0, 1, 0.93))
    out_path = out_dir / f"physical_dashboard_rho_{safe_tag(rho_init)}.png"
    fig.savefig(out_path, dpi=300)
    plt.close(fig)
    return out_path


def plot_accuracy_dashboard(case_summary: pd.DataFrame, rho_init: float, out_dir: Path) -> Path:
    subset = case_summary[np.isclose(case_summary["rho_init"], rho_init)].copy()
    if subset.empty:
        raise ValueError(f"No cases found for rho_init={rho_init:g}")

    fig, axes = plt.subplots(2, 2, figsize=(15, 10))
    add_heatmap(axes[0, 0], subset, "trajectory_rmse_pct", "trajectory RMSE, %", ".2f")
    add_heatmap(axes[0, 1], subset, "final_vs_exact_pct", "final MOOSE − analytical, %", ".2f")
    add_heatmap(axes[1, 0], subset, "rho_final_over_rho_sat", r"final $\rho/\rho_{sat}$", ".3g")
    add_heatmap(axes[1, 1], subset, "final_balance_residual", "final storage/recovery residual", ".2g")

    fig.suptitle(
        rf"Numerical-validation metrics — $\rho_0$ = {rho_init:.1e} m$^{{-2}}$",
        fontsize=16,
    )
    fig.tight_layout(rect=(0, 0, 1, 0.96))
    out_path = out_dir / f"accuracy_dashboard_rho_{safe_tag(rho_init)}.png"
    fig.savefig(out_path, dpi=300)
    plt.close(fig)
    return out_path


def plot_initial_condition_convergence(
    case_summary: pd.DataFrame,
    case_curves: dict[str, pd.DataFrame],
    fixed_temperature: float,
    fixed_rate: float,
    out_dir: Path,
) -> Path:
    selected_T = nearest_available(case_summary["T_K"], fixed_temperature)
    selected_rate = nearest_available(case_summary["strain_rate_per_s"], fixed_rate)
    subset = case_summary[
        np.isclose(case_summary["T_K"], selected_T)
        & np.isclose(case_summary["strain_rate_per_s"], selected_rate)
    ].sort_values("rho_init")
    if subset.empty:
        raise ValueError("No cases available for initial-condition convergence plot")

    fig, ax = plt.subplots(figsize=(9, 6))
    for _, row in subset.iterrows():
        curve = case_curves[str(row["csv_file"])]
        line, = ax.semilogy(
            curve["time"],
            curve["rho_moose"],
            label=rf"MOOSE $\rho_0$={row['rho_init']:.0e}",
        )
        ax.semilogy(curve["time"], curve["rho_exact"], "--", color=line.get_color())

    rho_sat = float(subset["rho_sat"].median())
    ax.axhline(rho_sat, linestyle=":", label=rf"common $\rho_{{sat}}$={rho_sat:.3e}")
    ax.set_xlabel("time, s")
    ax.set_ylabel(r"dislocation density, $\rho$ (m$^{-2}$)")
    ax.set_title(
        f"Initial-condition convergence at T={selected_T:g} K, "
        f"strain rate={selected_rate:g} s$^{{-1}}$"
    )
    ax.legend()
    fig.tight_layout()
    out_path = out_dir / (
        f"rho_init_convergence_T_{safe_tag(selected_T)}_gdot_{safe_tag(selected_rate)}.png"
    )
    fig.savefig(out_path, dpi=300)
    plt.close(fig)
    return out_path


def plot_worst_cases(
    case_summary: pd.DataFrame,
    case_curves: dict[str, pd.DataFrame],
    out_dir: Path,
    count: int,
) -> Path:
    worst = case_summary.nlargest(count, "trajectory_rmse_pct")
    n = len(worst)
    ncols = 2
    nrows = int(math.ceil(n / ncols))
    fig, axes = plt.subplots(nrows, ncols, figsize=(14, 4.8 * nrows), squeeze=False)

    for ax, (_, row) in zip(axes.ravel(), worst.iterrows()):
        curve = case_curves[str(row["csv_file"])]
        ax.semilogy(curve["time"], curve["rho_moose"], label="MOOSE")
        ax.semilogy(curve["time"], curve["rho_exact"], "--", label="analytical")
        ax.axhline(row["rho_sat"], linestyle=":", label="saturation")
        ax.set_xlabel("time, s")
        ax.set_ylabel(r"$\rho$ (m$^{-2}$)")
        ax.set_title(
            f"T={row['T_K']:g} K, rate={row['strain_rate_per_s']:g} s$^{{-1}}$, "
            rf"$\rho_0$={row['rho_init']:.0e}" + "\n" + f"RMSE={row['trajectory_rmse_pct']:.2f}%"
        )
        ax.legend()

    for ax in axes.ravel()[n:]:
        ax.axis("off")

    fig.suptitle("Largest MOOSE-versus-analytical trajectory mismatches", fontsize=16)
    fig.tight_layout(rect=(0, 0, 1, 0.96))
    out_path = out_dir / "worst_case_analytical_comparisons.png"
    fig.savefig(out_path, dpi=300)
    plt.close(fig)
    return out_path


def write_reliability_report(
    case_summary: pd.DataFrame,
    out_path: Path,
    rmse_tolerance_pct: float,
    final_tolerance_pct: float,
) -> None:
    numerical_pass = (
        (case_summary["trajectory_rmse_pct"] <= rmse_tolerance_pct)
        & (case_summary["final_vs_exact_pct"].abs() <= final_tolerance_pct)
        & (case_summary["direction_check"] == "OK")
    )

    lines = [
        "KM-only numerical reliability report",
        "===================================",
        "",
        f"Cases analyzed: {len(case_summary)}",
        f"Trajectory RMSE tolerance: {rmse_tolerance_pct:g}%",
        f"Final analytical error tolerance: {final_tolerance_pct:g}%",
        f"Cases passing all numerical checks: {int(numerical_pass.sum())}/{len(case_summary)}",
        f"Cases reaching the requested saturation band: {(case_summary['saturation_reached'] == 'YES').sum()}/{len(case_summary)}",
        f"Direction checks passed: {(case_summary['direction_check'] == 'OK').sum()}/{len(case_summary)}",
        "",
        "Important interpretation:",
        "- Agreement with the analytical transient tests numerical correctness.",
        "- Reaching rho_sat tests whether the simulation was run long enough.",
        "- A case can be numerically correct even when saturation was not reached.",
        "",
        "Largest trajectory RMSE cases:",
    ]

    cols = [
        "rho_init",
        "T_K",
        "strain_rate_per_s",
        "trajectory_rmse_pct",
        "final_vs_exact_pct",
        "rho_final_over_rho_sat",
        "direction_check",
        "saturation_reached",
    ]
    worst = case_summary.nlargest(min(10, len(case_summary)), "trajectory_rmse_pct")[cols]
    lines.append(worst.to_string(index=False, float_format=lambda x: f"{x:.5g}"))
    out_path.write_text("\n".join(lines) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create KM-only physical-trend and numerical-validation dashboards."
    )
    parser.add_argument("--root", type=Path, default=Path("KM_output_dstrainPerStep1e-3_strainrate60"))     # KM_output
    parser.add_argument(
        "--rho-init",
        type=float,
        action="append",
        default=None,
        help="rho_init value to plot. Repeat for multiple values. Default: all.",
    )
    parser.add_argument("--fixed-rate", type=float, default=10.0)
    parser.add_argument("--fixed-temperature", type=float, default=1073.0)
    parser.add_argument(
        "--saturation-tolerance",
        type=float,
        default=0.01,
        help="Relative saturation band, e.g. 0.01 means 1%% (default: 0.01).",
    )
    parser.add_argument("--rmse-tolerance-pct", type=float, default=2.0)
    parser.add_argument("--final-tolerance-pct", type=float, default=2.0)
    parser.add_argument("--worst-case-count", type=int, default=6)
    args = parser.parse_args()

    root = args.root.expanduser().resolve()
    csv_files = sorted(root.rglob("km.csv"))
    if not csv_files:
        raise FileNotFoundError(f"No km.csv files found below {root}")

    out_dir = root / "model_validation"
    out_dir.mkdir(parents=True, exist_ok=True)

    rows: list[dict[str, object]] = []
    curves: dict[str, pd.DataFrame] = {}
    failures: list[dict[str, str]] = []

    for csv_path in csv_files:
        try:
            row, work = analyze_case(csv_path, args.saturation_tolerance)
            rows.append(row)
            curves[str(csv_path)] = work
        except Exception as exc:
            failures.append({"csv_file": str(csv_path), "error": str(exc)})
            print(f"Skipped {csv_path}: {exc}")

    if not rows:
        raise RuntimeError("No cases could be analyzed")

    summary = pd.DataFrame(rows).sort_values(["rho_init", "T_K", "strain_rate_per_s"])
    summary_path = out_dir / "km_model_validation_summary.csv"
    summary.to_csv(summary_path, index=False)

    if failures:
        pd.DataFrame(failures).to_csv(out_dir / "skipped_cases.csv", index=False)

    requested_rhos = args.rho_init
    if requested_rhos is None:
        requested_rhos = sorted(summary["rho_init"].unique())
    else:
        requested_rhos = [nearest_available(summary["rho_init"], value) for value in requested_rhos]

    generated: list[Path] = []
    for rho_init in sorted(set(requested_rhos)):
        generated.append(
            plot_physical_dashboard(
                case_summary=summary,
                case_curves=curves,
                rho_init=rho_init,
                fixed_rate=args.fixed_rate,
                fixed_temperature=args.fixed_temperature,
                out_dir=out_dir,
                saturation_tolerance=args.saturation_tolerance,
            )
        )
        generated.append(plot_accuracy_dashboard(summary, rho_init, out_dir))

    generated.append(
        plot_initial_condition_convergence(
            case_summary=summary,
            case_curves=curves,
            fixed_temperature=args.fixed_temperature,
            fixed_rate=args.fixed_rate,
            out_dir=out_dir,
        )
    )
    generated.append(
        plot_worst_cases(
            case_summary=summary,
            case_curves=curves,
            out_dir=out_dir,
            count=max(1, args.worst_case_count),
        )
    )

    report_path = out_dir / "reliability_report.txt"
    write_reliability_report(
        summary,
        report_path,
        rmse_tolerance_pct=args.rmse_tolerance_pct,
        final_tolerance_pct=args.final_tolerance_pct,
    )

    print("\nKM model-validation suite complete.")
    print(f"Cases analyzed: {len(summary)}")
    print(f"Cases skipped:  {len(failures)}")
    print(f"Summary CSV:    {summary_path}")
    print(f"Report:         {report_path}")
    print("Generated figures:")
    for path in generated:
        print(f"  {path}")


if __name__ == "__main__":
    main()