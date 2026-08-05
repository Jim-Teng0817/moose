#!/bin/bash

#SBATCH --time=168:00:00 # walltime
#SBATCH --ntasks-per-node=40 # number of processor cores (i.e. tasks)
#SBATCH --nodes=1 # number of nodes
#SBATCH --wckey ne_ldrd # Project Code
#SBATCH --partition=general  # short, general, hbm (check needed)
#SBATCH --job-name=umo_nuc_cal_3x3 # job name
#SBATCH --error=slurm-nuccal-%A_%a.err # %j will be replaced by the SLURM_JOB_ID
#SBATCH --output=slurm-nuccal-%A_%a.out # %j will be replaced by the SLURM_JOB_ID
#SBATCH --mail-user=tsuchun.teng@inl.gov # email address
#SBATCH --mail-type=BEGIN,END,FAIL


# 3 temperatures x 3 strain rates x 3 factors = 27 tasks.
# At most four one-node cases run simultaneously.
#SBATCH --array=0-26%10

echo "=================================================="
echo "NUCLEATION CALIBRATION ARRAY TASK STARTED"
echo "=================================================="

date
hostname

echo "SLURM_JOB_ID        = ${SLURM_JOB_ID}"
echo "SLURM_ARRAY_JOB_ID  = ${SLURM_ARRAY_JOB_ID}"
echo "SLURM_ARRAY_TASK_ID = ${SLURM_ARRAY_TASK_ID}"
echo "SLURM_NTASKS        = ${SLURM_NTASKS}"
echo "SLURM_SUBMIT_DIR    = ${SLURM_SUBMIT_DIR}"

cd "${SLURM_SUBMIT_DIR}" || {
  echo "ERROR: Cannot enter submission directory:"
  echo "${SLURM_SUBMIT_DIR}"
  exit 10
}

# This proves that the batch task reached the shell script.
touch "batch_started_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.txt"

module purge
module load use.moose moose-dev-openmpi/2026.06.16

echo
echo "=================================================="
echo "RUNTIME ENVIRONMENT"
echo "=================================================="

module list 2>&1
echo "mpiexec        = $(command -v mpiexec 2>/dev/null)"
echo "moose-dev-exec = $(command -v moose-dev-exec 2>/dev/null)"

APP="/home/tengt/projects_moose/moose/modules/phase_field/phase_field-opt"
INPUT="${SLURM_SUBMIT_DIR}/km_nucleation_rate_scaled.i"

if [ ! -x "${APP}" ]; then
  echo "ERROR: Executable is missing or is not executable:"
  echo "${APP}"
  exit 11
fi

if [ ! -f "${INPUT}" ]; then
  echo "ERROR: Input file is missing:"
  echo "${INPUT}"
  echo
  echo "Available input files:"
  ls -lh "${SLURM_SUBMIT_DIR}"/*.i 2>&1
  exit 12
fi

# --------------------------------------------------
# Physical cases
# --------------------------------------------------

TEMPS=(873 1073 1273)
RATES=(0.1 100.0 1000.0)

# --------------------------------------------------
# Global nucleation probability calibration factors
# --------------------------------------------------

FACTOR_NAMES=(low medium baseline)
FACTORS=(0.1 0.3 1.0)

# --------------------------------------------------
# Fixed global parameters
# --------------------------------------------------

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

# Short calibration run
TOTAL_STRAIN="2.0"
DELTA_STRAIN="5e-3"

# Prevent excessively large physical time steps at low strain rate.
DT_CAP="1e-2"

EXODUS_INTERVAL="20"

# --------------------------------------------------
# Convert array task ID into factor, T, and rate
# --------------------------------------------------

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

# --------------------------------------------------
# Strain-controlled timing
# --------------------------------------------------

DT_RAW=$(awk \
  -v ds="${DELTA_STRAIN}" \
  -v rate="${RATE}" \
  'BEGIN {
     printf "%.12g", ds / rate
   }')

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
  'BEGIN {
     printf "%.12g", hs / rate
   }')

END_TIME=$(awk \
  -v total_strain="${TOTAL_STRAIN}" \
  -v rate="${RATE}" \
  'BEGIN {
     printf "%.12g", total_strain / rate
   }')

# --------------------------------------------------
# Case folder
# --------------------------------------------------

rate_tag=$(echo "${RATE}" |
  sed 's/+//g; s/-/m/g; s/\./p/g')

factor_tag=$(echo "${FACTOR}" |
  sed 's/+//g; s/-/m/g; s/\./p/g')

case_name="factor_${FACTOR_NAME}_${factor_tag}_T_${T}_gdot_${rate_tag}"

# Use a new directory name so old failed/stale results are not mixed in.
ROOT="NucleationCalibration_3x3_rateScaled_v2"

CASE_DIR="${ROOT}/${case_name}"
STATUS_DIR="${ROOT}/status"

mkdir -p "${CASE_DIR}" "${STATUS_DIR}"

# Remove stale outputs from an earlier submission of the same case.
rm -f \
  "${CASE_DIR}/result.csv" \
  "${CASE_DIR}"/result.e* \
  "${CASE_DIR}"/result_*.csv

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
SLURM_ARRAY_JOB_ID = ${SLURM_ARRAY_JOB_ID}
SLURM_ARRAY_TASK_ID = ${TASK_ID}
EOF

echo
echo "=================================================="
echo "RUNNING CASE"
echo "=================================================="

echo "Task ID       = ${TASK_ID}"
echo "Case          = ${case_name}"
echo "Factor index  = ${FACTOR_INDEX}"
echo "Factor name   = ${FACTOR_NAME}"
echo "Factor        = ${FACTOR}"
echo "Temperature   = ${T} K"
echo "Strain rate   = ${RATE} 1/s"
echo "rho_init      = ${RHO_INIT} 1/m^2"
echo "dt_raw        = ${DT_RAW} s"
echo "dt            = ${DT} s"
echo "dt_nuc        = ${DT_NUC} s"
echo "hold_time     = ${HOLD_TIME} s"
echo "end_time      = ${END_TIME} s"
echo "total strain  = ${TOTAL_STRAIN}"
echo "output folder = ${CASE_DIR}"
echo "MPI ranks     = ${SLURM_NTASKS}"

echo
echo "Starting MOOSE..."
date

# Do not redirect this command to a custom log yet.
# Slurm will write everything directly to:
# slurm-nuccal-%A_%a.out and slurm-nuccal-%A_%a.err

mpiexec -n "${SLURM_NTASKS}" \
  moose-dev-exec "${APP}" \
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

if [ "${exit_code}" -eq 0 ] &&
   [ -f "${CASE_DIR}/result.csv" ]; then
  status="OK"
else
  status="FAILED"
fi

STATUS_FILE="${STATUS_DIR}/run_status_${TASK_ID}.csv"

echo \
"array_id,factor_name,factor,T,strain_rate,rho_init,total_strain,dt,hold_time,status,exit_code,case_dir" \
> "${STATUS_FILE}"

echo \
"${TASK_ID},${FACTOR_NAME},${FACTOR},${T},${RATE},${RHO_INIT},${TOTAL_STRAIN},${DT},${HOLD_TIME},${status},${exit_code},${CASE_DIR}" \
>> "${STATUS_FILE}"

echo
echo "=================================================="
echo "CASE FINISHED"
echo "=================================================="

echo "Case       = ${case_name}"
echo "Status     = ${status}"
echo "Exit code  = ${exit_code}"
echo "CSV exists = $(test -f "${CASE_DIR}/result.csv" && echo yes || echo no)"

date

exit "${exit_code}"