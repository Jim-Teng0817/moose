# Nine-case nucleation/growth screening diagnosis

Use the regime column together with completion_fraction. Incomplete runs may be
compared at common strain checkpoints, but not as final-state results.

## T = 873 K, strain rate = 0.1 s^-1

- Completion fraction: 1
- Regime: `coarsening_only`
- Total insertions/deletions: 0 / 0
- Maximum drive ratio: 6.016
- Maximum new established-grain proxy: 2
- Final D/D0: 2
- Final normalized GB length: 4.21e-07

## T = 873 K, strain rate = 100 s^-1

- Completion fraction: 1
- Regime: `nucleation_and_growth`
- Total insertions/deletions: 13 / 11
- Maximum drive ratio: 9.827
- Maximum new established-grain proxy: 0
- Final D/D0: 0.5451
- Final normalized GB length: 1.571

## T = 873 K, strain rate = 1000 s^-1

- Completion fraction: 1
- Regime: `eligible_but_no_insertion`
- Total insertions/deletions: 0 / 0
- Maximum drive ratio: 12.64
- Maximum new established-grain proxy: 0
- Final D/D0: 0.9998
- Final normalized GB length: 1.017

## T = 1073 K, strain rate = 0.1 s^-1

- Completion fraction: 0.0232
- Regime: `coarsening_only`
- Total insertions/deletions: 0 / 0
- Maximum drive ratio: 6.016
- Maximum new established-grain proxy: 2
- Final D/D0: 2
- Final normalized GB length: 8.229e-10

## T = 1073 K, strain rate = 100 s^-1

- Completion fraction: 1
- Regime: `nucleation_and_growth`
- Total insertions/deletions: 11 / 10
- Maximum drive ratio: 7.068
- Maximum new established-grain proxy: 0
- Final D/D0: 0.5344
- Final normalized GB length: 1.894

## T = 1073 K, strain rate = 1000 s^-1

- Completion fraction: 1
- Regime: `insertion_but_no_new_grain`
- Total insertions/deletions: 21 / 21
- Maximum drive ratio: 9.502
- Maximum new established-grain proxy: 0
- Final D/D0: 0.9996
- Final normalized GB length: 0.9411

## T = 1273 K, strain rate = 0.1 s^-1

- Completion fraction: 0.0013
- Regime: `coarsening_only`
- Total insertions/deletions: 0 / 0
- Maximum drive ratio: 6.017
- Maximum new established-grain proxy: 2
- Final D/D0: 2
- Final normalized GB length: 8.527e-11

## T = 1273 K, strain rate = 100 s^-1

- Completion fraction: 1
- Regime: `nucleation_and_growth`
- Total insertions/deletions: 4 / 4
- Maximum drive ratio: 6.016
- Maximum new established-grain proxy: 1
- Final D/D0: 1.414
- Final normalized GB length: 0.4572

## T = 1273 K, strain rate = 1000 s^-1

- Completion fraction: 1
- Regime: `nucleation_and_growth`
- Total insertions/deletions: 14 / 14
- Maximum drive ratio: 7.568
- Maximum new established-grain proxy: 0
- Final D/D0: 0.6029
- Final normalized GB length: 1.23

# Calibration decision guide

- `energy_blocked`: inspect the physical energy threshold, especially r_subgrain.
- `eligible_but_no_insertion`: increase the single global probability scale (factor_n) while keeping nuc_prob fixed.
- `insertion_but_no_new_grain`: nucleus radius, strength, or hold strain is insufficient.
- `new_grain_but_not_surviving`: slightly increase hold strain or insertion radius.
- `nucleation_and_growth`: candidate behavior; inspect grain-size and GB-length trends.
- `coarsening_only`: grain growth occurred without evidence of new-grain formation.