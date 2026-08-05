#!/bin/bash

#SBATCH --time=48:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=40
#SBATCH --ntasks-per-node=40
#SBATCH --wckey=ne_ldrd
#SBATCH --partition=general
#SBATCH --job-name=umo_nuc_cal_3x3
#SBATCH --error=slurm-nuccal-%A_%a.err
#SBATCH --output=slurm-nuccal-%A_%a.out
#SBATCH --mail-user=tsuchun.teng@inl.gov
#SBATCH --mail-type=BEGIN,END,FAIL

# 3 temperatures x 3 strain rates x 3 global probability factors = 27 tasks.
# Four tasks may run concurrently.  Change %4 to %2 if allocation is tight.
#SBATCH --array=0-26
#SBATCH --export=ALL

set -uo pipefail

# Do not use a conda environment for the MOOSE run.
unset CONDA_PREFIX CONDA_DEFAULT_ENV CONDA_SHLVL CONDA_PROMPT_MODIFIER
unset PYTHONPATH PYTHONHOME

source /etc/profile.d/modules.sh 2>/dev/null || true
module purge
module load use.moose moose-dev-openmpi/2026.06.16

SUBMIT_DIR="${SLURM_SUBMIT_DIR:-$(pwd)}"
cd "${SUBMIT_DIR}"

APP="/home/tengt/projects_moose/moose/modules/phase_field/phase_field-opt"
INPUT="km_nucleation_rate_scaled_Deformed10grains.i"

if [ ! -x "${APP}" ]; then
  echo "ERROR: executable is missing or not executable: ${APP}"
  exit 2
fi
if [ ! -f "${INPUT}" ]; then
  echo "ERROR: input file is missing: ${INPUT}"
  echo "Available input files:"
  ls -lh *.i 2>/dev/null || true
  exit 3
fi

# Physical test matrix requested by the user.
TEMPS=(873 1073 1273)
RATES=(0.1 100.0 1000.0)

# One global probability scale will ultimately be selected for all nine cases.
# factor=1 reproduces the previous probability magnitude per unit strain at
# gdot_ref=1/s; 0.1 and 0.3 test more conservative values.
FACTOR_NAMES=(low medium baseline)
FACTORS=(0.1 0.3 1.0)

RHO_INIT="1e16"
TIME_SCALE="1.0"
G_DOT_REF="1.0"
RHO_REF="1.0"
NUC_PROB="2e-3"

# Freeze survival/geometry parameters during this probability calibration.
HOLD_STRAIN="0.10"
NUC_RADIUS="60.0"
INT_WIDTH="10.0"
NUC_STRENGTH="1000.0"
BNDS_MIN="0.55"
BNDS_MAX="0.95"

# Short screening run.  After selecting a factor, rerun the nine physical
# cases with TOTAL_STRAIN=5 or longer.
TOTAL_STRAIN="2.0"
DELTA_STRAIN="5e-3"
DT_CAP="1e-2"
EXODUS_INTERVAL="20"

N_T=${#TEMPS[@]}
N_R=${#RATES[@]}
N_CASES=$((N_T * N_R))
TASK_ID="${SLURM_ARRAY_TASK_ID:-0}"

FACTOR_INDEX=$((TASK_ID / N_CASES))
CASE_INDEX=$((TASK_ID % N_CASES))
T_INDEX=$((CASE_INDEX / N_R))
R_INDEX=$((CASE_INDEX % N_R))

T="${TEMPS[$T_INDEX]}"
RATE="${RATES[$R_INDEX]}"
FACTOR_NAME="${FACTOR_NAMES[$FACTOR_INDEX]}"
FACTOR="${FACTORS[$FACTOR_INDEX]}"

# Strain-controlled maximum increment, with a physical-time cap for the
# phase-field solve.  The adaptive time step may cut this further.
DT_RAW=$(awk -v ds="${DELTA_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", ds/rate}')
DT=$(awk -v raw="${DT_RAW}" -v cap="${DT_CAP}" 'BEGIN {if (raw < cap) printf "%.12g", raw; else printf "%.12g", cap}')
DT_NUC="${DT}"
HOLD_TIME=$(awk -v hs="${HOLD_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", hs/rate}')
END_TIME=$(awk -v eps="${TOTAL_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", eps/rate}')

rate_tag=$(echo "${RATE}" | sed 's/+//g; s/-/m/g; s/\./p/g')
factor_tag=$(echo "${FACTOR}" | sed 's/+//g; s/-/m/g; s/\./p/g')
case_name="factor_${FACTOR_NAME}_${factor_tag}_T_${T}_gdot_${rate_tag}"

ROOT="NucleationCalibration_3x3_rateScaled"
CASE_DIR="${ROOT}/${case_name}"
LOG_DIR="${ROOT}/logs"
mkdir -p "${CASE_DIR}" "${LOG_DIR}"

LOG_FILE="${LOG_DIR}/${case_name}.log"
STATUS_FILE="${ROOT}/run_status_${TASK_ID}.csv"

cat > "${CASE_DIR}/case_settings.txt" <<SETTINGS
factor_name = ${FACTOR_NAME}
factor_n_i = ${FACTOR}
T_i = ${T}
strain_rate_i = ${RATE}
rho_init_i = ${RHO_INIT}
time_scale_i = ${TIME_SCALE}
gdot_ref_i = ${G_DOT_REF}
rho_ref_i = ${RHO_REF}
nuc_prob_i = ${NUC_PROB}
hold_strain = ${HOLD_STRAIN}
hold_time_i = ${HOLD_TIME}
nuc_radius_i = ${NUC_RADIUS}
int_width_i = ${INT_WIDTH}
nuc_strength_i = ${NUC_STRENGTH}
bnds_min_i = ${BNDS_MIN}
bnds_max_i = ${BNDS_MAX}
total_strain = ${TOTAL_STRAIN}
delta_strain = ${DELTA_STRAIN}
dt_raw = ${DT_RAW}
dt_i = ${DT}
dt_nuc_i = ${DT_NUC}
end_time_i = ${END_TIME}
SLURM_JOB_ID = ${SLURM_JOB_ID:-UNSET}
SLURM_ARRAY_TASK_ID = ${TASK_ID}
SETTINGS

echo "Running ${case_name}"
echo "  T=${T} K, gdot=${RATE} 1/s, factor=${FACTOR}"
echo "  dt=${DT}, hold_time=${HOLD_TIME}, end_time=${END_TIME}"
echo "  output=${CASE_DIR}"

NPROCS="${SLURM_NTASKS:-40}"
set +e
mpiexec -n "${NPROCS}" moose-dev-exec "${APP}" \
  -i "${INPUT}" \
  T_i="${T}" \
  strain_rate_i="${RATE}" \
  rho_init_i="${RHO_INIT}" \
  time_scale_i="${TIME_SCALE}" \
  gdot_ref_i="${G_DOT_REF}" \
  rho_ref_i="${RHO_REF}" \
  factor_n_i="${FACTOR}" \
  nuc_prob_i="${NUC_PROB}" \
  hold_time_i="${HOLD_TIME}" \
  nuc_radius_i="${NUC_RADIUS}" \
  int_width_i="${INT_WIDTH}" \
  nuc_strength_i="${NUC_STRENGTH}" \
  bnds_min_i="${BNDS_MIN}" \
  bnds_max_i="${BNDS_MAX}" \
  dt_i="${DT}" \
  dt_nuc_i="${DT_NUC}" \
  end_time_i="${END_TIME}" \
  exodus_interval_i="${EXODUS_INTERVAL}" \
  Outputs/file_base="${CASE_DIR}/result" \
  --allow-unused \
  > "${LOG_FILE}" 2>&1
exit_code=$?
set -e

if [ "${exit_code}" -eq 0 ] && [ -f "${CASE_DIR}/result.csv" ]; then
  status="OK"
else
  status="FAILED"
fi

echo "array_id,factor_name,factor,T,strain_rate,rho_init,total_strain,dt,hold_time,status,exit_code,case_dir" > "${STATUS_FILE}"
echo "${TASK_ID},${FACTOR_NAME},${FACTOR},${T},${RATE},${RHO_INIT},${TOTAL_STRAIN},${DT},${HOLD_TIME},${status},${exit_code},${CASE_DIR}" >> "${STATUS_FILE}"

echo "Finished ${case_name}: ${status}, exit_code=${exit_code}"
if [ "${exit_code}" -ne 0 ]; then
  tail -n 120 "${LOG_FILE}" || true
fi
exit "${exit_code}"
