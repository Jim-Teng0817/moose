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

# Submit 27 tasks, but run no more than four concurrently.
#SBATCH --array=0-26%4

date
hostname

cd "${SLURM_SUBMIT_DIR}" || exit 10

module purge
module load use.moose moose-dev-openmpi/2026.06.16

APP="/home/tengt/projects_moose/moose/modules/phase_field/phase_field-opt"
INPUT="${SLURM_SUBMIT_DIR}/km_nucleation_rate_scaled.i"

TEMPS=(873 1073 1273)
RATES=(0.1 100.0 1000.0)

FACTOR_NAMES=(low medium baseline)
FACTORS=(0.1 0.3 1.0)

RHO_INIT="1e16"
TIME_SCALE="1.0"
G_DOT_REF="1.0"
RHO_REF="1.0"
NUC_PROB="2e-3"

HOLD_STRAIN="0.10"
NUC_RADIUS="60.0"
INT_WIDTH="10.0"
NUC_STRENGTH="1000.0"
BNDS_MIN="0.55"
BNDS_MAX="0.95"

TOTAL_STRAIN="2.0"
DELTA_STRAIN="5e-3"
DT_CAP="1e-2"
EXODUS_INTERVAL="20"

N_T=${#TEMPS[@]}
N_R=${#RATES[@]}
N_CASES=$((N_T * N_R))

TASK_ID=${SLURM_ARRAY_TASK_ID}

FACTOR_INDEX=$((TASK_ID / N_CASES))
CASE_INDEX=$((TASK_ID % N_CASES))
T_INDEX=$((CASE_INDEX / N_R))
R_INDEX=$((CASE_INDEX % N_R))

T=${TEMPS[$T_INDEX]}
RATE=${RATES[$R_INDEX]}
FACTOR_NAME=${FACTOR_NAMES[$FACTOR_INDEX]}
FACTOR=${FACTORS[$FACTOR_INDEX]}

DT_RAW=$(awk \
  -v ds="${DELTA_STRAIN}" \
  -v rate="${RATE}" \
  'BEGIN {printf "%.12g", ds/rate}')

DT=$(awk \
  -v raw="${DT_RAW}" \
  -v cap="${DT_CAP}" \
  'BEGIN {
     if (raw < cap)
       printf "%.12g", raw;
     else
       printf "%.12g", cap;
   }')

DT_NUC="${DT}"

HOLD_TIME=$(awk \
  -v hs="${HOLD_STRAIN}" \
  -v rate="${RATE}" \
  'BEGIN {printf "%.12g", hs/rate}')

END_TIME=$(awk \
  -v eps="${TOTAL_STRAIN}" \
  -v rate="${RATE}" \
  'BEGIN {printf "%.12g", eps/rate}')

rate_tag=$(echo "${RATE}" | sed 's/+//g; s/-/m/g; s/\./p/g')
factor_tag=$(echo "${FACTOR}" | sed 's/+//g; s/-/m/g; s/\./p/g')

case_name="factor_${FACTOR_NAME}_${factor_tag}_T_${T}_gdot_${rate_tag}"

ROOT="NucleationCalibration_3x3_rateScaled"
CASE_DIR="${ROOT}/${case_name}"

mkdir -p "${CASE_DIR}" "${ROOT}/status"

cat > "${CASE_DIR}/case_settings.txt" << EOF
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
SLURM_JOB_ID = ${SLURM_JOB_ID}
SLURM_ARRAY_TASK_ID = ${TASK_ID}
EOF

echo "========================================"
echo "RUNNING NUCLEATION CALIBRATION CASE"
echo "========================================"
echo "Task ID       = ${TASK_ID}"
echo "Case          = ${case_name}"
echo "T             = ${T} K"
echo "Strain rate   = ${RATE} 1/s"
echo "Factor        = ${FACTOR}"
echo "dt            = ${DT}"
echo "hold_time     = ${HOLD_TIME}"
echo "end_time      = ${END_TIME}"
echo "output        = ${CASE_DIR}"
echo "MPI ranks     = ${SLURM_NTASKS}"
echo

if [ ! -x "${APP}" ]; then
  echo "ERROR: application is unavailable: ${APP}"
  exit 11
fi

if [ ! -f "${INPUT}" ]; then
  echo "ERROR: input is unavailable: ${INPUT}"
  ls -lh *.i 2>&1
  exit 12
fi

mpiexec -n "${SLURM_NTASKS}" moose-dev-exec "${APP}" \
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
  --allow-unused

exit_code=$?

if [ "${exit_code}" -eq 0 ] && [ -f "${CASE_DIR}/result.csv" ]; then
  status="OK"
else
  status="FAILED"
fi

STATUS_FILE="${ROOT}/status/run_status_${TASK_ID}.csv"

echo \
"array_id,factor_name,factor,T,strain_rate,status,exit_code,case_dir" \
> "${STATUS_FILE}"

echo \
"${TASK_ID},${FACTOR_NAME},${FACTOR},${T},${RATE},${status},${exit_code},${CASE_DIR}" \
>> "${STATUS_FILE}"

echo
echo "Finished ${case_name}"
echo "Status    = ${status}"
echo "Exit code = ${exit_code}"
date

exit "${exit_code}"