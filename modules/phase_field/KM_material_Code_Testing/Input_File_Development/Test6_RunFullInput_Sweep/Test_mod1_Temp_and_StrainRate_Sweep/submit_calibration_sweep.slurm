#!/bin/bash

#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=40
#SBATCH --ntasks-per-node=40
#SBATCH --wckey=ne_ldrd
#SBATCH --partition=general
#SBATCH --job-name=umo_calib_debug
#SBATCH --error=slurm-calib-%A_%a.err
#SBATCH --output=slurm-calib-%A_%a.out
#SBATCH --mail-user=tsuchun.teng@inl.gov
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --array=0-15
#SBATCH --export=ALL

set -x
set -o pipefail

SUBMIT_DIR="${SLURM_SUBMIT_DIR:-$(pwd)}"
cd "${SUBMIT_DIR}"

ROOT="CalibrationSweep_rho1e16"
mkdir -p "${ROOT}/debug" "${ROOT}/logs"

DEBUG_FILE="${ROOT}/debug/debug_${SLURM_JOB_ID:-nojob}_${SLURM_ARRAY_TASK_ID:-0}.txt"

exec > >(tee -a "${DEBUG_FILE}") 2>&1

echo "===== START DEBUG ====="
date
hostname
echo "PWD                 = $(pwd)"
echo "SLURM_JOB_ID        = ${SLURM_JOB_ID:-UNSET}"
echo "SLURM_ARRAY_TASK_ID = ${SLURM_ARRAY_TASK_ID:-UNSET}"
echo "SLURM_SUBMIT_DIR    = ${SLURM_SUBMIT_DIR:-UNSET}"
echo "SLURM_NTASKS        = ${SLURM_NTASKS:-UNSET}"
echo "DEBUG_FILE          = ${DEBUG_FILE}"
echo

unset CONDA_PREFIX
unset CONDA_DEFAULT_ENV
unset CONDA_SHLVL
unset CONDA_PROMPT_MODIFIER
unset PYTHONPATH
unset PYTHONHOME

source /etc/profile.d/modules.sh 2>/dev/null || true

module purge
module load use.moose moose-dev-openmpi/2026.06.16

echo "===== MODULE CHECK ====="
module list
which mpiexec || true
which moose-dev-exec || true
echo

APP="/home/tengt/projects_moose/moose/modules/phase_field/phase_field-opt"
INPUT="km_nucleation_Full_mod1.i"

echo "APP   = ${APP}"
echo "INPUT = ${INPUT}"

if [ ! -x "${APP}" ]; then
  echo "ERROR: APP does not exist or is not executable:"
  echo "${APP}"
  exit 2
fi

if [ ! -f "${INPUT}" ]; then
  echo "ERROR: INPUT file does not exist:"
  echo "${INPUT}"
  echo
  echo "Available input files:"
  ls -lh *.i
  exit 3
fi

RHO_INIT="1e16"
TIME_SCALE="1.0"

CASE_T=(873 873 1073 1273)
CASE_RATE=(1.0 1000.0 100.0 10.0)

SET_NAME=(A B C D)

HOLD_STRAIN=(0.05 0.10 0.10 0.10)
NUC_RADIUS=(40.0 40.0 60.0 60.0)
INT_WIDTH=(10.0 10.0 10.0 10.0)
NUC_STRENGTH=(1000.0 1000.0 1000.0 1000.0)
FACTOR_N=(1e-3 1e-3 1e-3 3e-4)

DELTA_STRAIN="5e-3"
DELTA_STRAIN_NUC="5e-3"
TOTAL_STRAIN="5.0"

TASK_ID="${SLURM_ARRAY_TASK_ID:-0}"
N_CASES=${#CASE_T[@]}

SET_INDEX=$(( TASK_ID / N_CASES ))
CASE_INDEX=$(( TASK_ID % N_CASES ))

T="${CASE_T[$CASE_INDEX]}"
RATE="${CASE_RATE[$CASE_INDEX]}"

SET="${SET_NAME[$SET_INDEX]}"

HS="${HOLD_STRAIN[$SET_INDEX]}"
RNUC="${NUC_RADIUS[$SET_INDEX]}"
IW="${INT_WIDTH[$SET_INDEX]}"
NSTRENGTH="${NUC_STRENGTH[$SET_INDEX]}"
FN="${FACTOR_N[$SET_INDEX]}"

DT=$(awk -v ds="${DELTA_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", ds/rate}')
DT_NUC=$(awk -v ds="${DELTA_STRAIN_NUC}" -v rate="${RATE}" 'BEGIN {printf "%.12g", ds/rate}')
HOLD_TIME=$(awk -v hs="${HS}" -v rate="${RATE}" 'BEGIN {printf "%.12g", hs/rate}')
END_TIME=$(awk -v eps="${TOTAL_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", eps/rate}')

rate_tag=$(echo "${RATE}" | sed 's/\./p/g')
case_name="set_${SET}_T_${T}_gdot_${rate_tag}"

CASE_DIR="${ROOT}/${case_name}"
LOG_DIR="${ROOT}/logs"

mkdir -p "${CASE_DIR}" "${LOG_DIR}"

LOG_FILE="${LOG_DIR}/${case_name}.log"
STATUS_FILE="${ROOT}/run_status_${TASK_ID}.csv"

cat > "${CASE_DIR}/case_settings.txt" << EOF
set_name = ${SET}
T_i = ${T}
strain_rate_i = ${RATE}
rho_init_i = ${RHO_INIT}
time_scale_i = ${TIME_SCALE}
delta_strain = ${DELTA_STRAIN}
delta_strain_nuc = ${DELTA_STRAIN_NUC}
total_strain = ${TOTAL_STRAIN}
dt_i = ${DT}
dt_nuc_i = ${DT_NUC}
hold_strain_i = ${HS}
hold_time_i = ${HOLD_TIME}
nuc_radius_i = ${RNUC}
int_width_i = ${IW}
nuc_strength_i = ${NSTRENGTH}
factor_n_i = ${FN}
SLURM_JOB_ID = ${SLURM_JOB_ID:-UNSET}
SLURM_ARRAY_TASK_ID = ${TASK_ID}
EOF

echo "===== RUNNING CALIBRATION CASE ====="
echo "set          = ${SET}"
echo "T            = ${T}"
echo "strain_rate  = ${RATE}"
echo "dt           = ${DT}"
echo "dt_nuc       = ${DT_NUC}"
echo "hold_time    = ${HOLD_TIME}"
echo "end_time     = ${END_TIME}"
echo "case_dir     = ${CASE_DIR}"
echo "log_file     = ${LOG_FILE}"
echo

NPROCS="${SLURM_NTASKS:-40}"

set +e

mpiexec -n "${NPROCS}" moose-dev-exec "${APP}" \
  -i "${INPUT}" \
  T_i="${T}" \
  strain_rate_i="${RATE}" \
  rho_init_i="${RHO_INIT}" \
  time_scale_i="${TIME_SCALE}" \
  dt_i="${DT}" \
  dt_nuc_i="${DT_NUC}" \
  hold_time_i="${HOLD_TIME}" \
  nuc_radius_i="${RNUC}" \
  int_width_i="${IW}" \
  nuc_strength_i="${NSTRENGTH}" \
  factor_n_i="${FN}" \
  end_time_i="${END_TIME}" \
  Outputs/file_base="${CASE_DIR}/result" \
  --allow-unused \
  > "${LOG_FILE}" 2>&1

exit_code=$?

set -e

if [ "${exit_code}" -eq 0 ]; then
  status="OK"
else
  status="FAILED"
fi

echo "array_id,set,T,strain_rate,rho_init,dt,dt_nuc,hold_time,end_time,nuc_radius,int_width,nuc_strength,factor_n,status,exit_code,case_dir" > "${STATUS_FILE}"
echo "${TASK_ID},${SET},${T},${RATE},${RHO_INIT},${DT},${DT_NUC},${HOLD_TIME},${END_TIME},${RNUC},${IW},${NSTRENGTH},${FN},${status},${exit_code},${CASE_DIR}" >> "${STATUS_FILE}"

echo "===== FINISHED CASE ====="
echo "status    = ${status}"
echo "exit_code = ${exit_code}"

if [ "${exit_code}" -ne 0 ]; then
  echo "===== LAST 120 LINES OF MOOSE LOG ====="
  tail -120 "${LOG_FILE}" || true
fi

date
exit "${exit_code}"