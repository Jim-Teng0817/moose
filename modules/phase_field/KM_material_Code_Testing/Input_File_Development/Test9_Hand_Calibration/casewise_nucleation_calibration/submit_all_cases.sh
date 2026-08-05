#!/bin/bash

set -u
shopt -s nullglob

for input_file in cases/01_survival/*/input.i; do
    echo "Submitting: ${input_file}"
    sbatch submit_one_case.slurm "${input_file}"
done