#!/bin/bash

#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=40
#SBATCH --ntasks-per-node=40
#SBATCH --wckey=ne_ldrd
#SBATCH --partition=general
#SBATCH --job-name=umo_nuc_debug
#SBATCH --error=slurm-nucdebug-%A_%a.err
#SBATCH --output=slurm-nucdebug-%A_%a.out
#SBATCH --mail-user=tsuchun.teng@inl.gov
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --array=0-0

echo "========================================"
echo "BATCH SCRIPT STARTED"
echo "========================================"
date
hostname

echo "SLURM_JOB_ID        = ${SLURM_JOB_ID}"
echo "SLURM_ARRAY_TASK_ID = ${SLURM_ARRAY_TASK_ID}"
echo "SLURM_SUBMIT_DIR    = ${SLURM_SUBMIT_DIR}"
echo "SLURM_NTASKS        = ${SLURM_NTASKS}"
echo "Initial PWD         = $(pwd)"

cd "${SLURM_SUBMIT_DIR}" || {
  echo "ERROR: cannot enter ${SLURM_SUBMIT_DIR}"
  exit 10
}

echo "Working directory   = $(pwd)"

# This file proves that the batch script itself began executing.
touch "batch_started_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}.txt"

module purge
module load use.moose moose-dev-openmpi/2026.06.16

echo
echo "========================================"
echo "ENVIRONMENT CHECK"
echo "========================================"

module list 2>&1
echo "mpiexec        = $(which mpiexec 2>/dev/null)"
echo "moose-dev-exec = $(which moose-dev-exec 2>/dev/null)"

APP="/home/tengt/projects_moose/moose/modules/phase_field/phase_field-opt"
INPUT="${SLURM_SUBMIT_DIR}/km_nucleation_rate_scaled.i"

echo "APP   = ${APP}"
echo "INPUT = ${INPUT}"

if [ ! -x "${APP}" ]; then
  echo "ERROR: executable is missing or not executable"
  ls -lh "${APP}" 2>&1
  exit 11
fi

if [ ! -f "${INPUT}" ]; then
  echo "ERROR: input file is missing"
  echo "Available input files:"
  ls -lh "${SLURM_SUBMIT_DIR}"/*.i 2>&1
  exit 12
fi

mkdir -p NucleationDebug

echo
echo "========================================"
echo "MOOSE INPUT PREFLIGHT"
echo "========================================"

mpiexec -n 1 moose-dev-exec "${APP}" \
  -i "${INPUT}" \
  T_i=873 \
  strain_rate_i=0.1 \
  rho_init_i=1e16 \
  time_scale_i=1.0 \
  gdot_ref_i=1.0 \
  rho_ref_i=1.0 \
  factor_n_i=0.3 \
  nuc_prob_i=2e-3 \
  hold_time_i=1.0 \
  nuc_radius_i=60 \
  int_width_i=10 \
  nuc_strength_i=1000 \
  bnds_min_i=0.55 \
  bnds_max_i=0.95 \
  dt_i=0.01 \
  dt_nuc_i=0.01 \
  end_time_i=0.02 \
  exodus_interval_i=1 \
  Outputs/file_base=NucleationDebug/preflight \
  --check-input \
  --allow-unused

preflight_code=$?

echo "Preflight exit code = ${preflight_code}"

if [ "${preflight_code}" -ne 0 ]; then
  echo "ERROR: MOOSE input preflight failed."
  exit "${preflight_code}"
fi

echo
echo "========================================"
echo "TWO-STEP MOOSE TEST"
echo "========================================"

mpiexec -n "${SLURM_NTASKS}" moose-dev-exec "${APP}" \
  -i "${INPUT}" \
  T_i=873 \
  strain_rate_i=0.1 \
  rho_init_i=1e16 \
  time_scale_i=1.0 \
  gdot_ref_i=1.0 \
  rho_ref_i=1.0 \
  factor_n_i=0.3 \
  nuc_prob_i=2e-3 \
  hold_time_i=1.0 \
  nuc_radius_i=60 \
  int_width_i=10 \
  nuc_strength_i=1000 \
  bnds_min_i=0.55 \
  bnds_max_i=0.95 \
  dt_i=0.01 \
  dt_nuc_i=0.01 \
  end_time_i=0.02 \
  exodus_interval_i=1 \
  Outputs/file_base=NucleationDebug/result \
  --allow-unused

run_code=$?

echo
echo "MOOSE run exit code = ${run_code}"
date

exit "${run_code}"