#!/bin/bash

#SBATCH --time=12:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=40
#SBATCH --cpus-per-task=40
#SBATCH --wckey=ne_ldrd
#SBATCH --partition=general
#SBATCH --job-name=km_only
#SBATCH --error=slurm-km-%A_%a.err
#SBATCH --output=slurm-km-%A_%a.out
#SBATCH --mail-user=tsuchun.teng@inl.gov
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --array=0-11
#SBATCH --export=ALL

set -uo pipefail

# Clean possible local conda environment.
unset CONDA_PREFIX CONDA_DEFAULT_ENV CONDA_SHLVL CONDA_PROMPT_MODIFIER
unset PYTHONPATH PYTHONHOME

source /etc/profile.d/modules.sh 2>/dev/null || true
module purge
module load use.moose moose-dev-openmpi/2026.06.16

SUBMIT_DIR="${SLURM_SUBMIT_DIR:-$(pwd)}"
cd "${SUBMIT_DIR}" || exit 10

APP="/home/tengt/projects_moose/moose/modules/phase_field/phase_field-opt"
INPUT="${SUBMIT_DIR}/km_only_Sensitivity_mod5.i"

ROOT="${SUBMIT_DIR}/KM_output_rho1e12"
LOG_DIR="${ROOT}/logs"
STATUS_DIR="${ROOT}/status"

mkdir -p "${ROOT}" "${LOG_DIR}" "${STATUS_DIR}"

TASK_ID="${SLURM_ARRAY_TASK_ID:-0}"

temps=(873 1073 1273)
rates=(0.1 10 100 1000)
rho_inits=(1e12)

num_temps=${#temps[@]}
num_rates=${#rates[@]}
num_rhos=${#rho_inits[@]}
num_cases=$((num_temps * num_rates * num_rhos))

if [ "${TASK_ID}" -lt 0 ] || [ "${TASK_ID}" -ge "${num_cases}" ]; then
  echo "ERROR: TASK_ID=${TASK_ID} is outside valid range 0-$((num_cases - 1))"
  exit 11
fi

rho_index=$((TASK_ID % num_rhos))
rate_index=$(((TASK_ID / num_rhos) % num_rates))
temp_index=$((TASK_ID / (num_rhos * num_rates)))

T="${temps[${temp_index}]}"
RATE="${rates[${rate_index}]}"
RHO_INIT="${rho_inits[${rho_index}]}"

# Use physical seconds per MOOSE time unit.
TIME_SCALE="1.0"

# Recommended for comparing strain-rate cases:
# run all cases to the same accumulated strain.
## Time Option 1:
TOTAL_STRAIN="1.0"
DELTA_STRAIN="0.01"

DT=$(awk -v de="${DELTA_STRAIN}" -v r="${RATE}" -v ts="${TIME_SCALE}" 'BEGIN { printf "%.12g", de / (r * ts) }')
END_TIME=$(awk -v et="${TOTAL_STRAIN}" -v r="${RATE}" -v ts="${TIME_SCALE}" 'BEGIN { printf "%.12g", et / (r * ts) }')

## Time Option 2:
# DT="0.01"
# END_TIME="10.0"
# TOTAL_STRAIN=$(awk -v r="${RATE}" -v et="${END_TIME}" -v ts="${TIME_SCALE}" 'BEGIN { printf "%.12g", r * et * ts }')
# DELTA_STRAIN=$(awk -v r="${RATE}" -v dt="${DT}" -v ts="${TIME_SCALE}" 'BEGIN { printf "%.12g", r * dt * ts }')

But for KM sensitivity, I recommend the same-total-strain version first.

Small input-file check

Your KM-only input should include:

[km]
  type = KocksMeckingDislocation
  gamma_dot = gamma_dot
  T = T
  time_scale = ${time_scale_i}

  enable_storage = true
  enable_dynamic_recovery = true
  enable_static_recovery = false

  k1_name = k1
  k20 = ${k20_i}
  Q_dyn = ${Q_dyn_i}
  Q_units = ${Q_units_i}
  m = ${m_i}

  rho_init = ${rho_init_i}

  block = 0
[]

and the output should be safe:

[Outputs]
  [csv]
    type = CSV
    execute_on = 'INITIAL TIMESTEP_END'
  []

  file_base = km_default/km
[]

The Slurm script will override this with:

Outputs/file_base="${CASE_DIR}/km"

so every case will write to its own folder.



tag_number () {
  echo "$1" | sed 's/+//g; s/-/m/g; s/\./p/g'
}

T_TAG=$(tag_number "${T}")
RATE_TAG=$(tag_number "${RATE}")
RHO_TAG=$(tag_number "${RHO_INIT}")

CASE_NAME="rho_${RHO_TAG}_T_${T_TAG}_gdot_${RATE_TAG}"
CASE_DIR="${ROOT}/${CASE_NAME}"
LOG_FILE="${LOG_DIR}/${CASE_NAME}.log"
STATUS_FILE="${STATUS_DIR}/run_status_${TASK_ID}.csv"

mkdir -p "${CASE_DIR}"

cat > "${CASE_DIR}/case_settings.txt" <<SETTINGS
case_name = ${CASE_NAME}
T_i = ${T}
strain_rate_i = ${RATE}
rho_init_i = ${RHO_INIT}
time_scale_i = ${TIME_SCALE}
total_strain = ${TOTAL_STRAIN}
delta_strain = ${DELTA_STRAIN}
dt_i = ${DT}
end_time_i = ${END_TIME}
SLURM_JOB_ID = ${SLURM_JOB_ID:-UNSET}
SLURM_ARRAY_JOB_ID = ${SLURM_ARRAY_JOB_ID:-UNSET}
SLURM_ARRAY_TASK_ID = ${TASK_ID}
SETTINGS

echo "========================================"
echo "KM-only sensitivity case"
echo "========================================"
date
hostname
echo "case_name      = ${CASE_NAME}"
echo "T              = ${T} K"
echo "strain_rate    = ${RATE} 1/s"
echo "rho_init       = ${RHO_INIT} m^-2"
echo "time_scale     = ${TIME_SCALE}"
echo "total_strain   = ${TOTAL_STRAIN}"
echo "delta_strain   = ${DELTA_STRAIN}"
echo "dt             = ${DT}"
echo "end_time       = ${END_TIME}"
echo "APP            = ${APP}"
echo "INPUT          = ${INPUT}"
echo "CASE_DIR       = ${CASE_DIR}"
echo "LOG_FILE       = ${LOG_FILE}"
echo

module list 2>&1
command -v moose-dev-exec || true

if [ ! -x "${APP}" ]; then
  echo "ERROR: application is missing or not executable: ${APP}"
  exit 12
fi

if [ ! -f "${INPUT}" ]; then
  echo "ERROR: input file does not exist: ${INPUT}"
  echo "Available input files:"
  ls -lh "${SUBMIT_DIR}"/*.i 2>/dev/null || true
  exit 13
fi

if ! command -v moose-dev-exec >/dev/null 2>&1; then
  echo "ERROR: moose-dev-exec is unavailable after module load."
  exit 14
fi

rm -f "${CASE_DIR}"/km.csv "${CASE_DIR}"/km.e* "${CASE_DIR}"/km_out.e*

set +e
moose-dev-exec "${APP}" \
  -i "${INPUT}" \
  T_i="${T}" \
  strain_rate_i="${RATE}" \
  rho_init_i="${RHO_INIT}" \
  time_scale_i="${TIME_SCALE}" \
  dt_i="${DT}" \
  end_time_i="${END_TIME}" \
  Outputs/file_base="${CASE_DIR}/km" \
  --allow-unused \
  > "${LOG_FILE}" 2>&1
exit_code=$?
set -e

CSV_FILE="${CASE_DIR}/km.csv"

if [ "${exit_code}" -eq 0 ] && [ -s "${CSV_FILE}" ]; then
  status="OK"
else
  status="FAILED"
fi

cat > "${STATUS_FILE}" <<STATUS
array_task_id,case_name,T,strain_rate,rho_init,time_scale,total_strain,delta_strain,dt,end_time,status,exit_code,csv_file,log_file
${TASK_ID},${CASE_NAME},${T},${RATE},${RHO_INIT},${TIME_SCALE},${TOTAL_STRAIN},${DELTA_STRAIN},${DT},${END_TIME},${status},${exit_code},${CSV_FILE},${LOG_FILE}
STATUS

echo "========================================"
echo "Finished ${CASE_NAME}"
echo "status    = ${status}"
echo "exit_code = ${exit_code}"
echo "csv_file  = ${CSV_FILE}"
echo "log_file  = ${LOG_FILE}"
echo "========================================"

if [ "${status}" != "OK" ]; then
  echo "Last 120 lines of MOOSE log:"
  tail -n 120 "${LOG_FILE}" 2>/dev/null || true
fi

date

if [ "${status}" = "OK" ]; then
  exit 0
else
  exit 1
fi