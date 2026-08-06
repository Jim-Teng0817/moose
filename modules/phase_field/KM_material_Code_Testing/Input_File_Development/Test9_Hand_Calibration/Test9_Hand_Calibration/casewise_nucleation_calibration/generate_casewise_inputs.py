#!/usr/bin/env python3
"""Generate standalone, case-by-case MOOSE input files for calibration stages 00-04.

Each generated case directory contains:
  input.i
  case_settings.txt

The input writes scalar/VPP/Exodus outputs back into the same case directory
when launched from the workflow root with submit_one_case.slurm.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import shutil
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable


DEFAULT_CONFIG = {
    "rho_init": 1.0e16,
    "time_scale": 1.0,
    "nuc_prob": 2.0e-3,
    "gdot_ref": 1.0,
    "rho_ref": 1.0,
    "seed": 12345,
    "delta_strain": 5.0e-3,
    "dt_cap": 1.0e-2,
    "selected_bnds_min": 0.55,
    "selected_bnds_max": 0.85,
    "selected_int_width": 10.0,
    "selected_nuc_radius": 60.0,
    "selected_nuc_strength": 1000.0,
    "selected_hold_strain": 0.10,
    "selected_r_subgrain_nm": 60.0,
    "selected_factor_n": 0.3,
}


@dataclass(frozen=True)
class Case:
    stage: str
    case_name: str
    parameter_set: str
    temperature: float
    strain_rate: float
    total_strain: float
    exodus_interval: int
    nuc_prob: float
    factor_n: float
    r_subgrain_nm: float
    nuc_radius: float
    int_width: float
    nuc_strength: float
    hold_strain: float
    bnds_min: float
    bnds_max: float
    seed: int


def fmt(value: float | int) -> str:
    if isinstance(value, int):
        return str(value)
    return f"{float(value):.12g}"


def tag(value: float | int | str) -> str:
    text = str(value)
    return text.replace("+", "").replace("-", "m").replace(".", "p")


def timing(case: Case, config: dict[str, float]) -> dict[str, float]:
    dt_raw = float(config["delta_strain"]) / case.strain_rate
    dt = min(dt_raw, float(config["dt_cap"]))
    return {
        "dt_raw": dt_raw,
        "dt": dt,
        "dt_nuc": dt,
        "hold_time": case.hold_strain / case.strain_rate,
        "end_time": case.total_strain / case.strain_rate,
        "r_subgrain_m": case.r_subgrain_nm * 1.0e-9,
    }


def build_cases(config: dict[str, float]) -> dict[str, list[Case]]:
    common = {
        "nuc_prob": float(config["nuc_prob"]),
        "seed": int(config["seed"]),
    }

    stages: dict[str, list[Case]] = {f"{i:02d}": [] for i in range(5)}

    # Stage 00: three boundary windows x two insertion interface widths.
    windows = [
        ("narrow", 0.50, 0.70),
        ("medium", 0.55, 0.85),
        ("broad", 0.55, 0.95),
    ]
    for width in (8.0, 10.0):
        for window_name, bmin, bmax in windows:
            name = f"window_{window_name}_bmin_{tag(bmin)}_bmax_{tag(bmax)}_iw_{tag(width)}"
            stages["00"].append(
                Case(
                    stage="00_mask_width",
                    case_name=name,
                    parameter_set=f"window_{window_name}_iw_{width:g}",
                    temperature=1073.0,
                    strain_rate=100.0,
                    total_strain=0.20,
                    exodus_interval=1,
                    factor_n=0.3,
                    r_subgrain_nm=60.0,
                    nuc_radius=60.0,
                    int_width=width,
                    nuc_strength=1000.0,
                    hold_strain=0.10,
                    bnds_min=bmin,
                    bnds_max=bmax,
                    **common,
                )
            )

    # Stage 01: 2 radii x 2 hold strains x 2 forcing strengths.
    for radius in (40.0, 60.0):
        for hold_strain in (0.05, 0.10):
            for strength in (500.0, 1000.0):
                name = (
                    f"radius_{tag(radius)}_hold_{tag(hold_strain)}_"
                    f"strength_{tag(strength)}"
                )
                stages["01"].append(
                    Case(
                        stage="01_survival",
                        case_name=name,
                        parameter_set=f"radius_{radius:g}_hold_{hold_strain:g}_strength_{strength:g}",
                        temperature=1073.0,
                        strain_rate=100.0,
                        total_strain=1.0,
                        exodus_interval=5,
                        factor_n=1.0,
                        r_subgrain_nm=float(config["selected_r_subgrain_nm"]),
                        nuc_radius=radius,
                        int_width=float(config["selected_int_width"]),
                        nuc_strength=strength,
                        hold_strain=hold_strain,
                        bnds_min=float(config["selected_bnds_min"]),
                        bnds_max=float(config["selected_bnds_max"]),
                        **common,
                    )
                )

    # Stage 02: three representative physical cases x three subgrain radii.
    representative = [(873.0, 1000.0), (1073.0, 100.0), (1273.0, 0.1)]
    for rsub_nm in (40.0, 60.0, 80.0):
        for temperature, rate in representative:
            name = f"rsub_{tag(rsub_nm)}nm_T_{tag(temperature)}_gdot_{tag(rate)}"
            stages["02"].append(
                Case(
                    stage="02_energy_threshold",
                    case_name=name,
                    parameter_set=f"rsub_{rsub_nm:g}nm",
                    temperature=temperature,
                    strain_rate=rate,
                    total_strain=1.0,
                    exodus_interval=10,
                    factor_n=1.0,
                    r_subgrain_nm=rsub_nm,
                    nuc_radius=float(config["selected_nuc_radius"]),
                    int_width=float(config["selected_int_width"]),
                    nuc_strength=float(config["selected_nuc_strength"]),
                    hold_strain=float(config["selected_hold_strain"]),
                    bnds_min=float(config["selected_bnds_min"]),
                    bnds_max=float(config["selected_bnds_max"]),
                    **common,
                )
            )

    # Stage 03: 3 factors x 3 temperatures x 3 strain rates.
    factors = [("low", 0.1), ("medium", 0.3), ("baseline", 1.0)]
    temperatures = (873.0, 1073.0, 1273.0)
    rates = (0.1, 100.0, 1000.0)
    for factor_name, factor in factors:
        for temperature in temperatures:
            for rate in rates:
                name = (
                    f"factor_{factor_name}_{tag(factor)}_T_{tag(temperature)}_"
                    f"gdot_{tag(rate)}"
                )
                stages["03"].append(
                    Case(
                        stage="03_probability",
                        case_name=name,
                        parameter_set=f"factor_{factor_name}_{factor:g}",
                        temperature=temperature,
                        strain_rate=rate,
                        total_strain=2.0,
                        exodus_interval=20,
                        factor_n=factor,
                        r_subgrain_nm=float(config["selected_r_subgrain_nm"]),
                        nuc_radius=float(config["selected_nuc_radius"]),
                        int_width=float(config["selected_int_width"]),
                        nuc_strength=float(config["selected_nuc_strength"]),
                        hold_strain=float(config["selected_hold_strain"]),
                        bnds_min=float(config["selected_bnds_min"]),
                        bnds_max=float(config["selected_bnds_max"]),
                        **common,
                    )
                )

    # Stage 04: selected global factor x 3 temperatures x 3 rates x 3 seeds.
    for seed in (12345, 23456, 34567):
        for temperature in temperatures:
            for rate in rates:
                name = f"seed_{seed}_T_{tag(temperature)}_gdot_{tag(rate)}"
                stages["04"].append(
                    Case(
                        stage="04_validation",
                        case_name=name,
                        parameter_set="selected_global_set",
                        temperature=temperature,
                        strain_rate=rate,
                        total_strain=5.0,
                        exodus_interval=20,
                        factor_n=float(config["selected_factor_n"]),
                        r_subgrain_nm=float(config["selected_r_subgrain_nm"]),
                        nuc_radius=float(config["selected_nuc_radius"]),
                        int_width=float(config["selected_int_width"]),
                        nuc_strength=float(config["selected_nuc_strength"]),
                        hold_strain=float(config["selected_hold_strain"]),
                        bnds_min=float(config["selected_bnds_min"]),
                        bnds_max=float(config["selected_bnds_max"]),
                        nuc_prob=float(config["nuc_prob"]),
                        seed=seed,
                    )
                )

    return stages


def replace_assignment(text: str, key: str, value: str) -> str:
    pattern = re.compile(rf"(?m)^(?P<indent>[ \t]*){re.escape(key)}[ \t]*=.*$")
    matches = list(pattern.finditer(text))
    if not matches:
        raise RuntimeError(f"Active assignment not found: {key}")
    # Most keys are top-level and should have exactly one active match.
    match = matches[0]
    return text[: match.start()] + f"{match.group('indent')}{key} = {value}" + text[match.end() :]


def replace_seed(text: str, seed: int) -> str:
    # Replace only the active seed line in nuc_inserter; rand_seed is a different key.
    pattern = re.compile(r"(?m)^(?P<indent>[ \t]+)seed[ \t]*=.*$")
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        raise RuntimeError(f"Expected exactly one active seed assignment, found {len(matches)}")
    match = matches[0]
    return text[: match.start()] + f"{match.group('indent')}seed = {seed}" + text[match.end() :]


def replace_file_base(text: str) -> str:
    pattern = re.compile(r"(?m)^(?P<indent>[ \t]*)file_base[ \t]*=.*$")
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        raise RuntimeError(f"Expected exactly one active file_base assignment, found {len(matches)}")
    match = matches[0]
    return (
        text[: match.start()]
        + f"{match.group('indent')}file_base = ${{Folder_name}}/result"
        + text[match.end() :]
    )


def render_input(base_text: str, case: Case, case_rel_dir: Path, config: dict[str, float]) -> str:
    tm = timing(case, config)
    text = base_text

    replacements = {
        "time_scale_i": fmt(config["time_scale"]),
        "dt_i": fmt(tm["dt"]),
        "dt_nuc_i": fmt(tm["dt_nuc"]),
        "hold_time_i": fmt(tm["hold_time"]),
        "strain_rate_i": fmt(case.strain_rate),
        "total_strain_i": fmt(case.total_strain),
        "end_time_i": fmt(tm["end_time"]),
        "Folder_name": f"'{case_rel_dir.as_posix()}'",
        "mod_num": case.case_name,
        "nuc_radius_i": fmt(case.nuc_radius),
        "bnds_min_i": fmt(case.bnds_min),
        "bnds_max_i": fmt(case.bnds_max),
        "nuc_prob_i": fmt(case.nuc_prob),
        "rho_init_i": fmt(config["rho_init"]),
        "nuc_strength_i": fmt(case.nuc_strength),
        "int_width_i": fmt(case.int_width),
        "T_i": fmt(case.temperature),
        "r_subgrain_i": fmt(tm["r_subgrain_m"]),
        "rho_ref_i": fmt(config["rho_ref"]),
        "gdot_ref_i": fmt(config["gdot_ref"]),
        "factor_n_i": fmt(case.factor_n),
        "exodus_interval_i": str(case.exodus_interval),
    }

    for key, value in replacements.items():
        text = replace_assignment(text, key, value)

    text = replace_seed(text, case.seed)
    text = replace_file_base(text)

    header = (
        "# -----------------------------------------------------------------------------\n"
        "# AUTO-GENERATED CASEWISE CALIBRATION INPUT\n"
        f"# stage          = {case.stage}\n"
        f"# parameter_set  = {case.parameter_set}\n"
        f"# case_name      = {case.case_name}\n"
        "# Submit from the package root with:\n"
        f"#   sbatch submit_one_case.slurm {case_rel_dir.as_posix()}/input.i\n"
        "# -----------------------------------------------------------------------------\n\n"
    )
    return header + text


def settings_dict(case: Case, config: dict[str, float]) -> dict[str, object]:
    tm = timing(case, config)
    return {
        "stage": case.stage,
        "parameter_set": case.parameter_set,
        "case": case.case_name,
        "T_i": case.temperature,
        "strain_rate_i": case.strain_rate,
        "rho_init_i": config["rho_init"],
        "time_scale_i": config["time_scale"],
        "nuc_prob_i": case.nuc_prob,
        "factor_n_i": case.factor_n,
        "gdot_ref_i": config["gdot_ref"],
        "rho_ref_i": config["rho_ref"],
        "r_subgrain_nm": case.r_subgrain_nm,
        "r_subgrain_i": tm["r_subgrain_m"],
        "nuc_radius_i": case.nuc_radius,
        "int_width_i": case.int_width,
        "nuc_strength_i": case.nuc_strength,
        "hold_strain": case.hold_strain,
        "hold_time_i": tm["hold_time"],
        "bnds_min_i": case.bnds_min,
        "bnds_max_i": case.bnds_max,
        "seed": case.seed,
        "total_strain": case.total_strain,
        "delta_strain": config["delta_strain"],
        "dt_raw": tm["dt_raw"],
        "dt_i": tm["dt"],
        "dt_nuc_i": tm["dt_nuc"],
        "end_time_i": tm["end_time"],
        "exodus_interval_i": case.exodus_interval,
    }


def write_settings(path: Path, settings: dict[str, object]) -> None:
    lines = [f"{key} = {value}" for key, value in settings.items()]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def load_config(path: Path) -> dict[str, float]:
    if not path.exists():
        path.write_text(json.dumps(DEFAULT_CONFIG, indent=2) + "\n", encoding="utf-8")
        return dict(DEFAULT_CONFIG)
    loaded = json.loads(path.read_text(encoding="utf-8"))
    config = dict(DEFAULT_CONFIG)
    config.update(loaded)
    return config


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, default=Path("base_input_with_diagnostics.i"))
    parser.add_argument("--config", type=Path, default=Path("selected_parameters.json"))
    parser.add_argument("--out", type=Path, default=Path("cases"))
    parser.add_argument(
        "--stages",
        default="00,01,02,03,04",
        help="Comma-separated stages to generate, e.g. 00,01",
    )
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()

    base = args.base.resolve()
    config_path = args.config.resolve()
    out_root = args.out.resolve()
    workflow_root = Path.cwd().resolve()

    if not base.exists():
        raise FileNotFoundError(base)

    config = load_config(config_path)
    all_stages = build_cases(config)
    requested = [item.strip().zfill(2) for item in args.stages.split(",") if item.strip()]
    unknown = sorted(set(requested) - set(all_stages))
    if unknown:
        raise ValueError(f"Unknown stages: {unknown}")

    base_text = base.read_text(encoding="utf-8")
    manifests_dir = workflow_root / "manifests"
    commands_dir = workflow_root / "submit_commands"
    manifests_dir.mkdir(exist_ok=True)
    commands_dir.mkdir(exist_ok=True)

    total = 0
    summary_rows: list[dict[str, object]] = []

    for stage_id in requested:
        cases = all_stages[stage_id]
        stage_dir_name = cases[0].stage
        stage_dir = out_root / stage_dir_name
        stage_dir.mkdir(parents=True, exist_ok=True)
        manifest_rows: list[dict[str, object]] = []
        commands: list[str] = []

        for case in cases:
            case_dir = stage_dir / case.case_name
            input_path = case_dir / "input.i"
            settings_path = case_dir / "case_settings.txt"

            if case_dir.exists() and not args.overwrite:
                # Preserve existing results; only skip if the input/settings already exist.
                if input_path.exists() and settings_path.exists():
                    settings = settings_dict(case, config)
                    rel_input = input_path.relative_to(workflow_root)
                    row = {**settings, "input_file": rel_input.as_posix()}
                    manifest_rows.append(row)
                    summary_rows.append(row)
                    commands.append(f"sbatch submit_one_case.slurm {rel_input.as_posix()}")
                    total += 1
                    continue

            case_dir.mkdir(parents=True, exist_ok=True)
            rel_case_dir = case_dir.relative_to(workflow_root)
            input_path.write_text(
                render_input(base_text, case, rel_case_dir, config),
                encoding="utf-8",
            )
            settings = settings_dict(case, config)
            write_settings(settings_path, settings)

            rel_input = input_path.relative_to(workflow_root)
            row = {**settings, "input_file": rel_input.as_posix()}
            manifest_rows.append(row)
            summary_rows.append(row)
            commands.append(f"sbatch submit_one_case.slurm {rel_input.as_posix()}")
            total += 1

        manifest_path = manifests_dir / f"{stage_id}_{stage_dir_name}.csv"
        fieldnames = list(manifest_rows[0].keys())
        with manifest_path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(manifest_rows)

        (commands_dir / f"{stage_id}_{stage_dir_name}.txt").write_text(
            "\n".join(commands) + "\n", encoding="utf-8"
        )

    all_manifest = manifests_dir / "all_cases.csv"
    fieldnames = list(summary_rows[0].keys())
    with all_manifest.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(summary_rows)

    print(f"Generated/registered {total} standalone input files under: {out_root}")
    for stage_id in requested:
        print(f"  Stage {stage_id}: {len(all_stages[stage_id])} cases")
    print(f"Manifest: {all_manifest}")


if __name__ == "__main__":
    main()
