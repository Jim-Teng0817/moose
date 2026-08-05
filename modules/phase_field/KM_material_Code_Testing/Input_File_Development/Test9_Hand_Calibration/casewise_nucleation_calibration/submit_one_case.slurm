#!/bin/bash

#SBATCH --time=96:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=40
#SBATCH --ntasks-per-node=40
#SBATCH --wckey=ne_ldrd
#SBATCH --partition=general
#SBATCH --job-name=umo_nuc_one
#SBATCH --error=slurm-one-%j.err
#SBATCH --output=slurm-one-%j.out
#SBATCH --mail-user=tsuchun.teng@inl.gov
#SBATCH --mail-type=BEGIN,END,FAIL

# Submit one case at a time, for example:
#   sbatch submit_one_case.slurm cases/00_mask_width/<case>/input.i

if [ "$#" -ne 1 ]; then
  echo "Usage: sbatch submit_one_case.slurm <relative/path/to/input.i>"
  exit 2
fi

cd "${SLURM_SUBMIT_DIR}" || exit 10

module purge
module load use.moose moose-dev-openmpi/2026.06.16

APP="/home/tengt/projects_moose/moose/modules/phase_field/phase_field-opt"
INPUT_REL="$1"
INPUT="${SLURM_SUBMIT_DIR}/${INPUT_REL}"

if [ ! -x "${APP}" ]; then
  echo "ERROR: executable is missing or is not executable: ${APP}"
  exit 11
fi

if [ ! -f "${INPUT}" ]; then
  echo "ERROR: input file is missing: ${INPUT}"
  exit 12
fi

if [ ! -f "${SLURM_SUBMIT_DIR}/test_e-2.txt" ]; then
  echo "ERROR: test_e-2.txt is missing from the workflow root:"
  echo "${SLURM_SUBMIT_DIR}/test_e-2.txt"
  exit 13
fi

echo "=================================================="
echo "RUNNING ONE NUCLEATION CALIBRATION CASE"
echo "=================================================="
date
hostname
echo "Job ID      = ${SLURM_JOB_ID}"
echo "Input       = ${INPUT_REL}"
echo "MPI ranks   = ${SLURM_NTASKS}"
echo "Working dir = ${SLURM_SUBMIT_DIR}"
echo

mpiexec -n "${SLURM_NTASKS}" moose-dev-exec "${APP}" \
  -i "${INPUT}" \
  --allow-unused

exit_code=$?

echo
echo "MOOSE exit code = ${exit_code}"
date
exit "${exit_code}"
