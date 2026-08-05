#!/bin/bash

#SBATCH --time=48:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=40
#SBATCH --ntasks-per-node=40
#SBATCH --wckey=ne_ldrd
#SBATCH --partition=general
#SBATCH --job-name=umo_prob_3x3
#SBATCH --error=slurm-prob-%A_%a.err
#SBATCH --output=slurm-prob-%A_%a.out
#SBATCH --mail-user=tsuchun.teng@inl.gov
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --array=0-26%4

echo "=================================================="
echo "GLOBAL NUCLEATION-RATE SCALE SCREEN: 3x3 CASES"
echo "=================================================="
date
hostname

cd "${SLURM_SUBMIT_DIR}" || exit 10
module purge
module load use.moose moose-dev-openmpi/2026.06.16

APP="/home/tengt/projects_moose/moose/modules/phase_field/phase_field-opt"
INPUT_NAME="${INPUT_FILE:-km_nucleation_rate_scaled.i}"
INPUT="${SLURM_SUBMIT_DIR}/${INPUT_NAME}"

if [ ! -x "${APP}" ]; then
  echo "ERROR: executable is unavailable: ${APP}"
  exit 11
fi
if [ ! -f "${INPUT}" ]; then
  echo "ERROR: input is unavailable: ${INPUT}"
  ls -lh "${SLURM_SUBMIT_DIR}"/*.i 2>&1
  exit 12
fi

TEMPS=(873 1073 1273)
RATES=(0.1 100.0 1000.0)
FACTOR_NAMES=(low medium baseline)
FACTORS=(0.1 0.3 1.0)

TASK_ID=${SLURM_ARRAY_TASK_ID}
N_T=${#TEMPS[@]}
N_R=${#RATES[@]}
N_CASES=$((N_T * N_R))
FACTOR_INDEX=$((TASK_ID / N_CASES))
CASE_INDEX=$((TASK_ID % N_CASES))
T_INDEX=$((CASE_INDEX / N_R))
R_INDEX=$((CASE_INDEX % N_R))

T=${TEMPS[$T_INDEX]}
RATE=${RATES[$R_INDEX]}
FACTOR_NAME=${FACTOR_NAMES[$FACTOR_INDEX]}
FACTOR=${FACTORS[$FACTOR_INDEX]}

RHO_INIT=1e16
TIME_SCALE=1.0
# nuc_prob_i is fixed because nuc_prob_i and factor_n_i are multiplicative.
NUC_PROB="${NUC_PROB:-2e-3}"
GDOT_REF=1.0
RHO_REF=1.0
RSUB_NM="${RSUB_NM:-60.0}"
NUC_RADIUS="${NUC_RADIUS:-60.0}"
INT_WIDTH="${INT_WIDTH:-10.0}"
NUC_STRENGTH="${NUC_STRENGTH:-1000.0}"
HOLD_STRAIN="${HOLD_STRAIN:-0.10}"
BNDS_MIN="${BNDS_MIN:-0.55}"
BNDS_MAX="${BNDS_MAX:-0.85}"
SEED="${SEED:-12345}"

TOTAL_STRAIN=2.0
DELTA_STRAIN=5e-3
DT_CAP=1e-2
EXODUS_INTERVAL=20

DT_RAW=$(awk -v ds="${DELTA_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", ds/rate}')
DT=$(awk -v raw="${DT_RAW}" -v cap="${DT_CAP}" 'BEGIN {if (raw < cap) printf "%.12g", raw; else printf "%.12g", cap}')
DT_NUC=${DT}
HOLD_TIME=$(awk -v hs="${HOLD_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", hs/rate}')
END_TIME=$(awk -v eps="${TOTAL_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", eps/rate}')
RSUB_M=$(awk -v r="${RSUB_NM}" 'BEGIN {printf "%.12g", r*1.0e-9}')

parameter_set="factor_${FACTOR_NAME}_${FACTOR}"
rate_tag=$(echo "${RATE}" | sed 's/+//g; s/-/m/g; s/\./p/g')
factor_tag=$(echo "${FACTOR}" | sed 's/+//g; s/-/m/g; s/\./p/g')
case_name="factor_${FACTOR_NAME}_${factor_tag}_T_${T}_gdot_${rate_tag}"
ROOT="Calibration_03_probability_3x3"
CASE_DIR="${ROOT}/${case_name}"
STATUS_DIR="${ROOT}/status"
mkdir -p "${CASE_DIR}" "${STATUS_DIR}"

cat > "${CASE_DIR}/case_settings.txt" <<SETTINGS
stage = probability
parameter_set = ${parameter_set}
factor_name = ${FACTOR_NAME}
T_i = ${T}
strain_rate_i = ${RATE}
rho_init_i = ${RHO_INIT}
time_scale_i = ${TIME_SCALE}
nuc_prob_i = ${NUC_PROB}
factor_n_i = ${FACTOR}
gdot_ref_i = ${GDOT_REF}
rho_ref_i = ${RHO_REF}
r_subgrain_nm = ${RSUB_NM}
r_subgrain_i = ${RSUB_M}
nuc_radius_i = ${NUC_RADIUS}
int_width_i = ${INT_WIDTH}
nuc_strength_i = ${NUC_STRENGTH}
hold_strain = ${HOLD_STRAIN}
hold_time_i = ${HOLD_TIME}
bnds_min_i = ${BNDS_MIN}
bnds_max_i = ${BNDS_MAX}
seed = ${SEED}
total_strain = ${TOTAL_STRAIN}
delta_strain = ${DELTA_STRAIN}
dt_i = ${DT}
dt_nuc_i = ${DT_NUC}
end_time_i = ${END_TIME}
SLURM_JOB_ID = ${SLURM_JOB_ID}
SLURM_ARRAY_TASK_ID = ${TASK_ID}
SETTINGS

rm -f "${CASE_DIR}"/result*.csv "${CASE_DIR}"/result.e*

echo "Case: ${case_name}"
echo "factor_n_i = ${FACTOR}; nuc_prob_i = ${NUC_PROB}"
echo "output: ${CASE_DIR}"

mpiexec -n "${SLURM_NTASKS}" moose-dev-exec "${APP}" \
  -i "${INPUT}" \
  T_i="${T}" \
  strain_rate_i="${RATE}" \
  rho_init_i="${RHO_INIT}" \
  time_scale_i="${TIME_SCALE}" \
  nuc_prob_i="${NUC_PROB}" \
  factor_n_i="${FACTOR}" \
  gdot_ref_i="${GDOT_REF}" \
  rho_ref_i="${RHO_REF}" \
  r_subgrain_i="${RSUB_M}" \
  nuc_radius_i="${NUC_RADIUS}" \
  int_width_i="${INT_WIDTH}" \
  nuc_strength_i="${NUC_STRENGTH}" \
  hold_time_i="${HOLD_TIME}" \
  bnds_min_i="${BNDS_MIN}" \
  bnds_max_i="${BNDS_MAX}" \
  dt_i="${DT}" \
  dt_nuc_i="${DT_NUC}" \
  end_time_i="${END_TIME}" \
  exodus_interval_i="${EXODUS_INTERVAL}" \
  UserObjects/nuc_inserter/seed="${SEED}" \
  Outputs/file_base="${CASE_DIR}/result" \
  --allow-unused

exit_code=$?
if [ "${exit_code}" -eq 0 ] && [ -f "${CASE_DIR}/result.csv" ]; then
  status=OK
else
  status=FAILED
fi

STATUS_FILE="${STATUS_DIR}/run_status_${TASK_ID}.csv"
echo "array_id,stage,parameter_set,T,strain_rate,status,exit_code,case_dir" > "${STATUS_FILE}"
echo "${TASK_ID},probability,${parameter_set},${T},${RATE},${status},${exit_code},${CASE_DIR}" >> "${STATUS_FILE}"

echo "Finished: ${status}, exit_code=${exit_code}"
date
exit "${exit_code}"
