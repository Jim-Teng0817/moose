#!/bin/bash

set -u
shopt -s nullglob

for T in 873 1073 1273; do
  for RATE in 0.1 100 1000; do
    sbatch \
      -J "nuc_T${T}_R${RATE}" \
      submit_quick_nucleation_case.slurm \
      "${T}" "${RATE}"
  done
done