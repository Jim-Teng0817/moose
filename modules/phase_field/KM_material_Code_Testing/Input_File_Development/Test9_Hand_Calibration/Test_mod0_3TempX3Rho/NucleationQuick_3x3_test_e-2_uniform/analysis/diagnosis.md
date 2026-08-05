# Nine-case nucleation/growth screening diagnosis

Use the regime column together with completion_fraction. Incomplete runs may be
compared at common strain checkpoints, but not as final-state results.

## T = 873 K, strain rate = 0.1 s^-1

- Completion fraction: 1
- Regime: `nucleation_and_growth`
- Total insertions/deletions: 6 / 6
- Maximum drive ratio: 3.437
- Maximum new established-grain proxy: 0
- Final D/D0: 0.6663
- Final normalized GB length: 1.465

## T = 873 K, strain rate = 100 s^-1

- Completion fraction: 1
- Regime: `nucleation_and_growth`
- Total insertions/deletions: 12 / 9
- Maximum drive ratio: 7.243
- Maximum new established-grain proxy: 1
- Final D/D0: 0.5648
- Final normalized GB length: 1.482

## T = 873 K, strain rate = 1000 s^-1

- Completion fraction: 1
- Regime: `eligible_but_no_insertion`
- Total insertions/deletions: 0 / 0
- Maximum drive ratio: 10.06
- Maximum new established-grain proxy: 0
- Final D/D0: 0.9998
- Final normalized GB length: 1.017

## T = 1073 K, strain rate = 0.1 s^-1

- Completion fraction: 1
- Regime: `nucleation_and_growth`
- Total insertions/deletions: 1 / 1
- Maximum drive ratio: 3.436
- Maximum new established-grain proxy: 2
- Final D/D0: 2
- Final normalized GB length: 7.88e-16

## T = 1073 K, strain rate = 100 s^-1

- Completion fraction: 1
- Regime: `nucleation_and_growth`
- Total insertions/deletions: 7 / 7
- Maximum drive ratio: 4.486
- Maximum new established-grain proxy: 0
- Final D/D0: 0.7069
- Final normalized GB length: 1.185

## T = 1073 K, strain rate = 1000 s^-1

- Completion fraction: 1
- Regime: `insertion_but_no_new_grain`
- Total insertions/deletions: 11 / 11
- Maximum drive ratio: 6.918
- Maximum new established-grain proxy: 0
- Final D/D0: 0.9996
- Final normalized GB length: 0.9309

## T = 1273 K, strain rate = 0.1 s^-1

- Completion fraction: 0.0107
- Regime: `coarsening_only`
- Total insertions/deletions: 0 / 0
- Maximum drive ratio: 3.438
- Maximum new established-grain proxy: 0
- Final D/D0: 1.414
- Final normalized GB length: 0.2965

## T = 1273 K, strain rate = 100 s^-1

- Completion fraction: 1
- Regime: `nucleation_and_growth`
- Total insertions/deletions: 10 / 10
- Maximum drive ratio: 3.438
- Maximum new established-grain proxy: 2
- Final D/D0: 1.414
- Final normalized GB length: 0.3449

## T = 1273 K, strain rate = 1000 s^-1

- Completion fraction: 1
- Regime: `nucleation_and_growth`
- Total insertions/deletions: 7 / 7
- Maximum drive ratio: 4.983
- Maximum new established-grain proxy: 0
- Final D/D0: 0.8942
- Final normalized GB length: 0.9068

# Calibration decision guide

- `energy_blocked`: inspect the physical energy threshold, especially r_subgrain.
- `eligible_but_no_insertion`: increase the single global probability scale (factor_n) while keeping nuc_prob fixed.
- `insertion_but_no_new_grain`: nucleus radius, strength, or hold strain is insufficient.
- `new_grain_but_not_surviving`: slightly increase hold strain or insertion radius.
- `nucleation_and_growth`: candidate behavior; inspect grain-size and GB-length trends.
- `coarsening_only`: grain growth occurred without evidence of new-grain formation.