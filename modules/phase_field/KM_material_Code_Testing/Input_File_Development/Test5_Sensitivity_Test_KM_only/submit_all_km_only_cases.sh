#!/bin/bash

set -u
shopt -s nullglob

RHO_INIT=1e12

# Use this if you want the three-rate set:
rates=(0.1 1 100 1000)

# Use this instead if you also want 10 1/s:
# rates=(0.1 10 100 1000)

for T in 873 1073 1273; do
  for RATE in "${rates[@]}"; do

    RATE_TAG=$(echo "${RATE}" | sed 's/\./p/g')
    RHO_TAG=$(echo "${RHO_INIT}" | sed 's/+//g; s/-/m/g; s/\./p/g')

    sbatch \
      -J "km_T${T}_R${RATE_TAG}" \
      submit_one_km_only_case.slurm \
      "${T}" "${RATE}" "${RHO_INIT}"

  done
done