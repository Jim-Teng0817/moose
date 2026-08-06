# Case-by-case U-Mo nucleation calibration workflow

This package replaces the Slurm arrays with **77 standalone MOOSE input files**. Each case can be submitted independently with one simple, known-good Slurm script.

## Package contents

- `base_input_with_diagnostics.i` — the latest input containing the rate-scaled nucleation law, energy diagnostics, `FeatureFloodCount`, and `grain_features` vector output.
- `cases/00_mask_width/` — 6 inputs.
- `cases/01_survival/` — 8 inputs.
- `cases/02_energy_threshold/` — 9 inputs.
- `cases/03_probability/` — 27 inputs.
- `cases/04_validation/` — 27 inputs.
- `submit_one_case.slurm` — submit exactly one input file.
- `preflight_one_case.sh` — run `--check-input` for one input.
- `analyze_nucleation_calibration.py` — post-process one stage.
- `manifests/` — all parameter values and input paths.
- `submit_commands/` — one `sbatch` command per case.
- `selected_parameters.json` — provisional selections used when generating downstream stages.
- `generate_casewise_inputs.py` — regenerate the inputs after choosing parameters from an earlier stage.

## Before running

Copy your required dislocation-density file into the workflow root:

```text
test_e-2.txt
```

Run all commands from the workflow root. The generated inputs use relative output paths and expect `test_e-2.txt` in that root directory.

Convert scripts to Unix line endings after copying to HPC:

```bash
sed -i 's/\r$//' submit_one_case.slurm preflight_one_case.sh \
  generate_casewise_inputs.py analyze_nucleation_calibration.py
```

## Submit one case

Example preflight:

```bash
bash preflight_one_case.sh \
  cases/00_mask_width/window_narrow_bmin_0p5_bmax_0p7_iw_8p0/input.i
```

Example submission:

```bash
sbatch submit_one_case.slurm \
  cases/00_mask_width/window_narrow_bmin_0p5_bmax_0p7_iw_8p0/input.i
```

Each input writes `result.csv`, Exodus, and vector-postprocessor CSVs into its own case directory.

The files under `submit_commands/` contain all case-by-case commands. Copy and run one line at a time.

---

# Run the stages sequentially

Do **not** run Stages 00-04 simultaneously. The selected values from each stage should be used to regenerate the later-stage inputs.

## Stage 00: boundary mask and insertion width

Cases: 6

Parameters tested:

- boundary windows: `(0.50, 0.70)`, `(0.55, 0.85)`, `(0.55, 0.95)`
- `int_width_i`: `8`, `10`

Representative physical case:

- `T = 1073 K`
- `strain rate = 100 1/s`

Submit one line at a time from:

```text
submit_commands/00_00_mask_width.txt
```

Analyze:

```bash
module load python
conda activate scientific

python analyze_nucleation_calibration.py \
  --root cases/00_mask_width
```

Select a mask/width using:

- initial `grain_count_early` and `grain_count_established` should be about 4;
- `eligible_nucleation_region` should lie on ordinary two-grain boundaries;
- inspect Exodus to ensure triple junctions are not preferentially selected;
- `P_nuc_unfavorable_max` should remain zero.

Update these values in `selected_parameters.json`:

```json
"selected_bnds_min": 0.55,
"selected_bnds_max": 0.85,
"selected_int_width": 10.0
```

Then regenerate Stage 01 into a fresh location or overwrite unrun inputs:

```bash
python generate_casewise_inputs.py --stages 01 --overwrite
```

## Stage 01: nucleus survival controls

Cases: 8

Parameters tested:

- `nuc_radius_i`: `40`, `60`
- hold strain: `0.05`, `0.10`
- `nuc_strength_i`: `500`, `1000`

Fixed representative condition:

- `T = 1073 K`
- `strain rate = 100 1/s`

Analyze:

```bash
python analyze_nucleation_calibration.py \
  --root cases/01_survival
```

Choose the **smallest** radius, strength, and hold strain that gives:

- insertion events;
- increasing `grain_count_early`;
- increasing `grain_count_established`;
- a distinct stable new grain ID from `grain_features`;
- survival beyond the hold interval;
- no GrainTracker remapping failure.

Update:

```json
"selected_nuc_radius": 60.0,
"selected_nuc_strength": 1000.0,
"selected_hold_strain": 0.1
```

Then regenerate Stage 02.

## Stage 02: energy-threshold radius

Cases: 9

Physical cases:

- `873 K, 1000 1/s`
- `1073 K, 100 1/s`
- `1273 K, 0.1 1/s`

Tested physical subgrain radii:

- `40 nm`
- `60 nm`
- `80 nm`

The numerical insertion radius is fixed at the selected Stage 01 value. The physical `r_subgrain_i` is explicitly set in meters in each input, so the two effects are decoupled.

Analyze:

```bash
python analyze_nucleation_calibration.py \
  --root cases/02_energy_threshold
```

Use:

- `nuc_drive_ratio_avg` and maximum;
- `energy_preferred_fraction`;
- `eligible_nucleation_fraction`;
- `P_nuc_unfavorable_max` and integral.

Select a global radius that gives physically meaningful differentiation rather than making every case eligible or every case blocked.

Update:

```json
"selected_r_subgrain_nm": 60.0
```

Then regenerate Stage 03.

## Stage 03: global probability factor

Cases: 27

Physical matrix:

- `T = 873, 1073, 1273 K`
- strain rate `= 0.1, 100, 1000 1/s`

Factors:

- `factor_n_i = 0.1`
- `factor_n_i = 0.3`
- `factor_n_i = 1.0`

`nuc_prob_i = 2e-3` is fixed because `nuc_prob_i` and `factor_n_i` enter multiplicatively and cannot be independently identified.

Analyze:

```bash
python analyze_nucleation_calibration.py \
  --root cases/03_probability
```

Reject factors that cause:

- no insertions despite eligible energy/GB regions;
- excessive insertions followed by almost equal deletions;
- transient grains with low formation/survival efficiency;
- remapping failures;
- nonphysical or unstable size evolution.

Select one global factor and update:

```json
"selected_factor_n": 0.3
```

Then regenerate Stage 04.

## Stage 04: final stochastic validation

Cases: 27

- nine physical cases;
- three seeds: `12345`, `23456`, `34567`;
- one selected global parameter set;
- total strain = 5.

Analyze:

```bash
python analyze_nucleation_calibration.py \
  --root cases/04_validation
```

Use the mean and variation across seeds to distinguish robust physical trends from stochastic noise.

---

# Regenerating inputs

The package already contains all 77 inputs using provisional selected values. After selecting parameters from a stage, edit `selected_parameters.json` and regenerate only the next stage:

```bash
python generate_casewise_inputs.py --stages 01 --overwrite
python generate_casewise_inputs.py --stages 02 --overwrite
python generate_casewise_inputs.py --stages 03 --overwrite
python generate_casewise_inputs.py --stages 04 --overwrite
```

Do not use `--overwrite` after results already exist in that stage unless those results have been backed up or intentionally discarded.

# Main calibration outputs

For each case, prioritize:

- cumulative `nuc_insertions` and `nuc_deletions`;
- `grain_count_early` and `grain_count_established`;
- distinct and surviving grain IDs from `grain_features`;
- formation efficiency = distinct new IDs / cumulative insertions;
- survival efficiency = IDs surviving the hold interval / cumulative insertions;
- average equivalent diameter and `D/D0`;
- grain-boundary length;
- `rho_avg`, `rho_eff_avg`, `P_nuc_avg`;
- nucleation driving ratio and eligible fraction;
- `P_nuc_unfavorable_max = 0` as an energy-gate audit.
