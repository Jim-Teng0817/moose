#!/bin/bash

#SBATCH --time=12:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=40
#SBATCH --ntasks-per-node=40
#SBATCH --wckey=ne_ldrd
#SBATCH --partition=general
#SBATCH --job-name=umo_mask_width
#SBATCH --error=slurm-mask-%A_%a.err
#SBATCH --output=slurm-mask-%A_%a.out
#SBATCH --mail-user=tsuchun.teng@inl.gov
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --array=0-5%3

echo "=================================================="
echo "BOUNDARY MASK / INTERFACE-WIDTH SCREEN"
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

# Three boundary windows and two insertion-interface widths.
WINDOW_NAMES=(narrow medium broad)
BNDS_MINS=(0.50 0.55 0.55)
BNDS_MAXS=(0.70 0.85 0.95)
WIDTHS=(8.0 10.0)

TASK_ID=${SLURM_ARRAY_TASK_ID}
N_WINDOWS=${#WINDOW_NAMES[@]}
WIDTH_INDEX=$((TASK_ID / N_WINDOWS))
WINDOW_INDEX=$((TASK_ID % N_WINDOWS))

WINDOW_NAME=${WINDOW_NAMES[$WINDOW_INDEX]}
BNDS_MIN=${BNDS_MINS[$WINDOW_INDEX]}
BNDS_MAX=${BNDS_MAXS[$WINDOW_INDEX]}
INT_WIDTH=${WIDTHS[$WIDTH_INDEX]}

# One representative condition. This is a short localization check, not a
# physical calibration.
T=1073
RATE=100.0
RHO_INIT=1e16
TIME_SCALE=1.0
NUC_PROB=2e-3
FACTOR=0.3
GDOT_REF=1.0
RHO_REF=1.0
NUC_RADIUS=60.0
NUC_STRENGTH=1000.0
HOLD_STRAIN=0.10
RSUB_NM=60.0
SEED=12345

TOTAL_STRAIN=0.20
DELTA_STRAIN=5e-3
DT_CAP=1e-2
EXODUS_INTERVAL=1

DT_RAW=$(awk -v ds="${DELTA_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", ds/rate}')
DT=$(awk -v raw="${DT_RAW}" -v cap="${DT_CAP}" 'BEGIN {if (raw < cap) printf "%.12g", raw; else printf "%.12g", cap}')
DT_NUC=${DT}
HOLD_TIME=$(awk -v hs="${HOLD_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", hs/rate}')
END_TIME=$(awk -v eps="${TOTAL_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", eps/rate}')
RSUB_M=$(awk -v r="${RSUB_NM}" 'BEGIN {printf "%.12g", r*1.0e-9}')

case_name="window_${WINDOW_NAME}_bmin_${BNDS_MIN}_bmax_${BNDS_MAX}_iw_${INT_WIDTH}"
case_tag=$(echo "${case_name}" | sed 's/+//g; s/-/m/g; s/\./p/g')
ROOT="Calibration_00_mask_width"
CASE_DIR="${ROOT}/${case_tag}"
STATUS_DIR="${ROOT}/status"
mkdir -p "${CASE_DIR}" "${STATUS_DIR}"

cat > "${CASE_DIR}/case_settings.txt" <<SETTINGS
stage = mask_width
parameter_set = ${case_name}
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
echo "bnds window: ${BNDS_MIN} < bnds < ${BNDS_MAX}"
echo "int_width: ${INT_WIDTH}"
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
echo "array_id,stage,parameter_set,status,exit_code,case_dir" > "${STATUS_FILE}"
echo "${TASK_ID},mask_width,${case_name},${status},${exit_code},${CASE_DIR}" >> "${STATUS_FILE}"

echo "Finished: ${status}, exit_code=${exit_code}"
date
exit "${exit_code}"
