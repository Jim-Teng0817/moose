# Staged global nucleation calibration workflow

This package is designed for the current `km_nucleation_rate_scaled.i` model and the following principle:

- `T_i` and `strain_rate_i` are physical case inputs.
- One global nucleation parameter set is used unchanged for all physical cases.
- The literature grain-boundary mobility is not tuned.

## Important identifiability point

In the current nucleation law, `nuc_prob_i` and `factor_n_i` are multiplicative. The simulation identifies only their product, not the two values independently. Therefore:

- keep `nuc_prob_i = 2e-3` fixed;
- calibrate `factor_n_i`;
- do not tune both independently.

## Required MOOSE outputs

The input should contain the following scalar postprocessors whenever available:

- `nuc_insertions`, `nuc_deletions`, `nuc_count`
- `grain_count_early`, `grain_count_established`
- `avg_grain_area`, `gb_length`
- `rho_avg`, `rho_eff_avg`, `P_nuc_avg`
- `nuc_drive_ratio_avg`, preferably `nuc_drive_ratio_max`
- `eligible_nucleation_fraction`
- `P_nuc_unfavorable_max` and/or `P_nuc_unfavorable_integral`

The input should also contain:

```text
[VectorPostprocessors]
  [grain_features]
    type = FeatureVolumeVectorPostprocessor
    flood_counter = grain_tracker
    output_centroids = true
    execute_on = 'INITIAL TIMESTEP_END'
  []
[]
```

The Python script can run without the vector postprocessor, but it will then use `FeatureFloodCount` only as a proxy and cannot calculate distinct stable grain IDs.

## Why the scripts override `r_subgrain_i`

Your input currently defines:

```text
r_subgrain_i = '${fparse nuc_radius_i * length_scale_i}'
```

That couples the physical energy-barrier radius to the numerical insertion radius. The energy-threshold script overrides `r_subgrain_i` directly in meters so that the two effects can be screened separately without immediately editing the input file.

## Stage 0: boundary mask and insertion-interface width

Script:

```bash
00_mask_width_screen.slurm
```

This tests three `bnds` windows and two `int_width_i` values. It is a short localization check, not a physical calibration.

Submit one task first:

```bash
sbatch --array=0-0%1 00_mask_width_screen.slurm
```

Then all six:

```bash
sbatch 00_mask_width_screen.slurm
```

Analyze:

```bash
python analyze_nucleation_calibration.py \
  --root Calibration_00_mask_width
```

Selection rule:

1. Initial `grain_count_early` and `grain_count_established` should be approximately 4.
2. The eligible region should be localized to ordinary grain boundaries.
3. Inspect Exodus in ParaView to ensure triple-junction regions are not preferentially selected.
4. After selection, freeze `bnds_min_i`, `bnds_max_i`, and `int_width_i`.

## Stage 1: nucleus survival controls

Script:

```bash
01_survival_screen.slurm
```

This tests:

- `nuc_radius_i = 40, 60`
- `hold_strain = 0.05, 0.10`
- `nuc_strength_i = 500, 1000`

Submit:

```bash
sbatch 01_survival_screen.slurm
```

Override the selected mask/width from Stage 0 if needed:

```bash
sbatch --export=ALL,BNDS_MIN=0.55,BNDS_MAX=0.85,INT_WIDTH=10 \
  01_survival_screen.slurm
```

Analyze:

```bash
python analyze_nucleation_calibration.py \
  --root Calibration_01_survival
```

Selection rule:

Choose the smallest radius, hold strain, and strength that gives:

- nonzero insertions;
- a new stable grain ID or an increase in established grain count;
- survival beyond the hold interval;
- no remapping failure.

## Stage 2: energy-threshold radius

Script:

```bash
02_energy_threshold_screen.slurm
```

This tests physical `r_subgrain` values of 40, 60, and 80 nm in three representative physical cases:

- 873 K, 1000 1/s
- 1073 K, 100 1/s
- 1273 K, 0.1 1/s

Submit with the selected survival parameters:

```bash
sbatch --export=ALL,NUC_RADIUS=60,NUC_STRENGTH=1000,HOLD_STRAIN=0.10,INT_WIDTH=10,BNDS_MIN=0.55,BNDS_MAX=0.85 \
  02_energy_threshold_screen.slurm
```

Analyze:

```bash
python analyze_nucleation_calibration.py \
  --root Calibration_02_energy_threshold
```

Selection rule:

- `P_nuc_unfavorable_max` and its integral should remain zero within numerical tolerance.
- Avoid a radius that blocks every physical case.
- Avoid choosing a radius merely because it makes every case eligible.
- Prefer physical evidence for subgrain radius when available.

## Stage 3: global nucleation-rate scale

Script:

```bash
03_probability_screen_3x3.slurm
```

This runs 3 temperatures x 3 strain rates x 3 global factors:

```text
T = 873, 1073, 1273 K
strain rate = 0.1, 100, 1000 1/s
factor_n_i = 0.1, 0.3, 1.0
```

Submit with the selected parameters from Stages 0-2:

```bash
sbatch --export=ALL,RSUB_NM=60,NUC_RADIUS=60,NUC_STRENGTH=1000,HOLD_STRAIN=0.10,INT_WIDTH=10,BNDS_MIN=0.55,BNDS_MAX=0.85 \
  03_probability_screen_3x3.slurm
```

Analyze:

```bash
python analyze_nucleation_calibration.py \
  --root Calibration_03_probability_3x3
```

Selection rule:

- Too low: `drive ratio > 1` and eligible area exists, but insertions remain zero.
- Too high: excessive insertions, deletion fraction near one, many transient nuclei, or remapping failure.
- Candidate: some physically favorable cases form surviving grains, while unfavorable cases can remain non-nucleating.

## Stage 4: final multi-seed validation

Script:

```bash
04_validation_3x3_multiseed.slurm
```

This runs the selected global set for all nine physical cases and three seeds.

Example:

```bash
sbatch --export=ALL,SELECTED_FACTOR=0.3,RSUB_NM=60,NUC_RADIUS=60,NUC_STRENGTH=1000,HOLD_STRAIN=0.10,INT_WIDTH=10,BNDS_MIN=0.55,BNDS_MAX=0.85,TOTAL_STRAIN=5 \
  04_validation_3x3_multiseed.slurm
```

Analyze:

```bash
python analyze_nucleation_calibration.py \
  --root Calibration_04_validation_3x3_multiseed
```

The analysis produces seed means and standard deviations for the main outputs.

## Python outputs

Each analysis run creates:

```text
ROOT/analysis/
  combined_time_history.csv
  case_summary.csv
  parameter_summary.csv
  grain_birth_events.csv
  recommendations.md
  plots/
```

Important columns in `case_summary.csv`:

- `total_insertions`, `total_deletions`
- `distinct_new_grain_ids`
- `survived_hold_grain_ids`
- `final_new_grain_ids`
- `formation_efficiency`
- `survival_efficiency`
- `initial_grain_count_ok`
- `energy_gate_ok`
- `valid_case`
- `regime`

Regime meanings:

- `energy_blocked`
- `eligible_but_no_insertion`
- `insertion_but_no_new_grain`
- `new_grain_but_not_surviving`
- `nucleation_and_growth`
- `coarsening_only`

## Local energy verification at a grain birth

The scalar CSV can verify the global energy gate, but it cannot prove the local energy at a specific birth point.

Use `grain_birth_events.csv` to obtain:

- new grain ID;
- birth time and accumulated strain;
- centroid coordinates.

Then inspect the preceding Exodus frame in ParaView at that centroid and confirm:

```text
nuc_drive_ratio >= 1
energy_margin >= 0
P_nuc > 0
bnds_min < bnds < bnds_max
```

Use the frame before birth because the new low-dislocation-density grain can reduce the local stored energy after it appears.

## Preparing the scripts

```bash
sed -i 's/\r$//' *.slurm analyze_nucleation_calibration.py
bash -n 00_mask_width_screen.slurm
bash -n 01_survival_screen.slurm
bash -n 02_energy_threshold_screen.slurm
bash -n 03_probability_screen_3x3.slurm
bash -n 04_validation_3x3_multiseed.slurm
python -m py_compile analyze_nucleation_calibration.py
```

Run MOOSE from a non-conda shell. Activate the `scientific` conda environment only for Python post-processing.
