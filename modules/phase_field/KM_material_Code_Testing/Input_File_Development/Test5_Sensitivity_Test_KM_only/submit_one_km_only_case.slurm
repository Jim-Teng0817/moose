#!/bin/bash

#SBATCH --time=12:00:00
#SBATCH --nodes=1
##SBATCH --ntasks=40
#SBATCH --cpus-per-task=40
#SBATCH --wckey=ne_ldrd
#SBATCH --partition=general
#SBATCH --job-name=km_only
#SBATCH --error=slurm-km-%j.err
#SBATCH --output=slurm-km-%j.out
#SBATCH --mail-user=tsuchun.teng@inl.gov
#SBATCH --mail-type=END,FAIL
#SBATCH --export=ALL

set -u

# -------------------------
# Inputs from submit_all_km_only_cases.sh
# -------------------------
T="$1"
RATE="$2"
RHO_INIT="${3:-1e12}"

# -------------------------
# MOOSE environment
# Edit this module line if your HPC uses a different MOOSE module.
# -------------------------
source /etc/profile.d/modules.sh 2>/dev/null || true
module purge
module load use.moose moose-dev-openmpi/2026.06.16

# -------------------------
# Paths
# -------------------------
SUBMIT_DIR="${SLURM_SUBMIT_DIR:-$(pwd)}"
cd "${SUBMIT_DIR}"

APP="/home/tengt/projects_moose/moose/modules/phase_field/phase_field-opt"
INPUT="${SUBMIT_DIR}/km_only_Sensitivity_mod5.i"

# -------------------------
# Output folder
# -------------------------
tag_number () {
  echo "$1" | sed 's/+//g; s/-/m/g; s/\./p/g'
}

T_TAG=$(tag_number "${T}")
RATE_TAG=$(tag_number "${RATE}")
RHO_TAG=$(tag_number "${RHO_INIT}")

CASE_DIR="${SUBMIT_DIR}/KM_output/rho_${RHO_TAG}/T_${T_TAG}_rate_${RATE_TAG}"
mkdir -p "${CASE_DIR}"

echo "========================================"
echo "Running KM-only case"
echo "T_i           = ${T}"
echo "strain_rate_i = ${RATE}"
echo "rho_init_i    = ${RHO_INIT}"
echo "CASE_DIR      = ${CASE_DIR}"
echo "APP           = ${APP}"
echo "INPUT         = ${INPUT}"
echo "========================================"

# -------------------------
# Run MOOSE
# -------------------------
mpiexec -n "${SLURM_NTASKS}" \
  moose-dev-exec "${APP}" \
  -i "${INPUT}" \
  T_i="${T}" \
  strain_rate_i="${RATE}" \
  rho_init_i="${RHO_INIT}" \
  out_dir="${CASE_DIR}" \
  case_name="km" \
  Outputs/file_base="${CASE_DIR}/km" \
  --allow-unused