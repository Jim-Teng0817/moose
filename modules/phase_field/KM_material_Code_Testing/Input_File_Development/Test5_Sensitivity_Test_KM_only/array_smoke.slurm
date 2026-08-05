#!/bin/bash

#SBATCH --time=00:05:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --wckey=ne_ldrd
#SBATCH --partition=general
#SBATCH --job-name=array_smoke
#SBATCH --output=array-smoke-%A_%a.out
#SBATCH --error=array-smoke-%A_%a.err
#SBATCH --array=0-3%2

set -uo pipefail

echo "Job ID: ${SLURM_JOB_ID}"
echo "Array task: ${SLURM_ARRAY_TASK_ID}"
echo "Host: $(hostname)"
date

sleep 30

date
echo "Task completed"