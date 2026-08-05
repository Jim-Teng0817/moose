#!/bin/bash

#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=40
#SBATCH --ntasks-per-node=40
#SBATCH --wckey=ne_ldrd
#SBATCH --partition=general
#SBATCH --job-name=umo_survival
#SBATCH --error=slurm-survival-%A_%a.err
#SBATCH --output=slurm-survival-%A_%a.out
#SBATCH --mail-user=tsuchun.teng@inl.gov
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --array=0-7%4

echo "=================================================="
echo "NUCLEUS SURVIVAL SCREEN"
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

# 2 radii x 2 hold strains x 2 forcing strengths = 8 tasks.
RADII=(40.0 60.0)
HOLD_STRAINS=(0.05 0.10)
STRENGTHS=(500.0 1000.0)

TASK_ID=${SLURM_ARRAY_TASK_ID}
N_HOLD=${#HOLD_STRAINS[@]}
N_STRENGTH=${#STRENGTHS[@]}
RADIUS_INDEX=$((TASK_ID / (N_HOLD * N_STRENGTH)))
REM=$((TASK_ID % (N_HOLD * N_STRENGTH)))
HOLD_INDEX=$((REM / N_STRENGTH))
STRENGTH_INDEX=$((REM % N_STRENGTH))

NUC_RADIUS=${RADII[$RADIUS_INDEX]}
HOLD_STRAIN=${HOLD_STRAINS[$HOLD_INDEX]}
NUC_STRENGTH=${STRENGTHS[$STRENGTH_INDEX]}

# Representative condition selected to have appreciable driving force.
T=1073
RATE=100.0
RHO_INIT=1e16
TIME_SCALE=1.0
NUC_PROB=2e-3
FACTOR=1.0
GDOT_REF=1.0
RHO_REF=1.0
RSUB_NM="${RSUB_NM:-60.0}"
INT_WIDTH="${INT_WIDTH:-10.0}"
BNDS_MIN="${BNDS_MIN:-0.55}"
BNDS_MAX="${BNDS_MAX:-0.85}"
SEED="${SEED:-12345}"

TOTAL_STRAIN=1.0
DELTA_STRAIN=5e-3
DT_CAP=1e-2
EXODUS_INTERVAL=5

DT_RAW=$(awk -v ds="${DELTA_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", ds/rate}')
DT=$(awk -v raw="${DT_RAW}" -v cap="${DT_CAP}" 'BEGIN {if (raw < cap) printf "%.12g", raw; else printf "%.12g", cap}')
DT_NUC=${DT}
HOLD_TIME=$(awk -v hs="${HOLD_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", hs/rate}')
END_TIME=$(awk -v eps="${TOTAL_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", eps/rate}')
RSUB_M=$(awk -v r="${RSUB_NM}" 'BEGIN {printf "%.12g", r*1.0e-9}')

parameter_set="radius_${NUC_RADIUS}_hold_${HOLD_STRAIN}_strength_${NUC_STRENGTH}"
case_tag=$(echo "${parameter_set}" | sed 's/+//g; s/-/m/g; s/\./p/g')
ROOT="Calibration_01_survival"
CASE_DIR="${ROOT}/${case_tag}"
STATUS_DIR="${ROOT}/status"
mkdir -p "${CASE_DIR}" "${STATUS_DIR}"

cat > "${CASE_DIR}/case_settings.txt" <<SETTINGS
stage = survival
parameter_set = ${parameter_set}
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

echo "Parameter set: ${parameter_set}"
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
echo "${TASK_ID},survival,${parameter_set},${status},${exit_code},${CASE_DIR}" >> "${STATUS_FILE}"

echo "Finished: ${status}, exit_code=${exit_code}"
date
exit "${exit_code}"
