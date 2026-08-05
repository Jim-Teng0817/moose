#!/bin/bash

# KM-only Cartesian sweep: diagnostic-safe Slurm array script.
# Start with one task. After task 0 succeeds, change --array to 0-124%4 or 0-124%10.

#SBATCH --time=01:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --wckey=ne_ldrd
#SBATCH --partition=general
#SBATCH --job-name=km_only_test
#SBATCH --error=slurm-km-%A_%a.err
#SBATCH --output=slurm-km-%A_%a.out
#SBATCH --mail-user=tsuchun.teng@inl.gov
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --array=0-0%1
#SBATCH --export=ALL

set -uo pipefail

# Remove inherited Python/Conda settings that can conflict with MOOSE modules.
unset CONDA_PREFIX CONDA_DEFAULT_ENV CONDA_SHLVL CONDA_PROMPT_MODIFIER
unset PYTHONPATH PYTHONHOME

source /etc/profile.d/modules.sh 2>/dev/null || true
module purge
module load use.moose moose-dev-openmpi/2026.06.16

SUBMIT_DIR="${SLURM_SUBMIT_DIR:-$(pwd)}"
cd "${SUBMIT_DIR}"

TASK_ID="${SLURM_ARRAY_TASK_ID:-}"
if [ -z "${TASK_ID}" ]; then
    echo "ERROR: SLURM_ARRAY_TASK_ID is undefined. Submit as an array job."
    exit 10
fi

APP="/home/tengt/projects_moose/moose/modules/phase_field/phase_field-opt"
INPUT="${SUBMIT_DIR}/km_only_Sensitivity_mod5.i"
ROOT="${SUBMIT_DIR}/KM_output"

mkdir -p "${ROOT}/debug" "${ROOT}/logs" "${ROOT}/status"
echo "startup OK: $(date)" > "${ROOT}/debug/startup_${SLURM_ARRAY_JOB_ID:-${SLURM_JOB_ID}}_${TASK_ID}.txt"

echo "===== JOB INFORMATION ====="
date
hostname
echo "SLURM_JOB_ID        = ${SLURM_JOB_ID:-UNSET}"
echo "SLURM_ARRAY_JOB_ID  = ${SLURM_ARRAY_JOB_ID:-UNSET}"
echo "SLURM_ARRAY_TASK_ID = ${TASK_ID}"
echo "SLURM_NTASKS        = ${SLURM_NTASKS:-UNSET}"
echo "SUBMIT_DIR          = ${SUBMIT_DIR}"
echo "APP                 = ${APP}"
echo "INPUT               = ${INPUT}"
module list 2>&1
command -v moose-dev-exec || true

if [ ! -x "${APP}" ]; then
    echo "ERROR: application is missing or not executable: ${APP}"
    exit 11
fi

if [ ! -f "${INPUT}" ]; then
    echo "ERROR: input file does not exist: ${INPUT}"
    echo "Available input files:"
    ls -lh "${SUBMIT_DIR}"/*.i 2>/dev/null || true
    exit 12
fi

if ! command -v moose-dev-exec >/dev/null 2>&1; then
    echo "ERROR: moose-dev-exec is unavailable after module load."
    exit 13
fi

temps=(873 973 1073 1173 1273)
rates=(0.1 1.0 10.0 100.0 1000.0)
rho_inits=(1e14 1e15 1e16 1e17 1e18)

# These can be overridden at submission:
# sbatch --export=ALL,TOTAL_STRAIN=0.1,DELTA_STRAIN=1e-3 ...
delta_strain="${DELTA_STRAIN:-1e-3}"
total_strain="${TOTAL_STRAIN:-0.1}"

tag_number() {
    echo "$1" | sed 's/+//g; s/-/m/g; s/\./p/g'
}

n_rho=${#rho_inits[@]}
n_temp=${#temps[@]}
n_rate=${#rates[@]}
total_cases=$((n_rho * n_temp * n_rate))

if [ "${TASK_ID}" -lt 0 ] || [ "${TASK_ID}" -ge "${total_cases}" ]; then
    echo "ERROR: array task ${TASK_ID} is outside 0-$((total_cases - 1))."
    exit 14
fi

rho_index=$((TASK_ID / (n_temp * n_rate)))
remainder=$((TASK_ID % (n_temp * n_rate)))
temp_index=$((remainder / n_rate))
rate_index=$((remainder % n_rate))

rho_init="${rho_inits[$rho_index]}"
T="${temps[$temp_index]}"
rate="${rates[$rate_index]}"

rho_tag=$(tag_number "${rho_init}")
rate_tag=$(tag_number "${rate}")
case_name="rho_${rho_tag}_T_${T}_gdot_${rate_tag}"
case_dir="${ROOT}/rho_${rho_tag}/T_${T}/gdot_${rate_tag}"
log_file="${ROOT}/logs/${case_name}.log"
status_file="${ROOT}/status/run_status_${TASK_ID}.csv"
csv_file="${case_dir}/km.csv"

mkdir -p "${case_dir}"
rm -f "${csv_file}" "${log_file}"

dt=$(awk -v ds="${delta_strain}" -v rate="${rate}" 'BEGIN {printf "%.12g", ds/rate}')
end_time=$(awk -v es="${total_strain}" -v rate="${rate}" 'BEGIN {printf "%.12g", es/rate}')

cat > "${case_dir}/case_settings.txt" <<SETTINGS
rho_init_i = ${rho_init}
T_i = ${T}
strain_rate_i = ${rate}
delta_strain = ${delta_strain}
total_strain = ${total_strain}
dt_i = ${dt}
end_time_i = ${end_time}
SLURM_JOB_ID = ${SLURM_JOB_ID:-UNSET}
SLURM_ARRAY_TASK_ID = ${TASK_ID}
SETTINGS

echo "===== RUNNING CASE ====="
echo "case_name     = ${case_name}"
echo "rho_init      = ${rho_init}"
echo "T             = ${T} K"
echo "strain_rate   = ${rate} 1/s"
echo "delta_strain  = ${delta_strain}"
echo "total_strain  = ${total_strain}"
echo "dt            = ${dt} s"
echo "end_time      = ${end_time} s"
echo "log_file      = ${log_file}"

# One rank does not need mpiexec. Removing the nested MPI launcher makes the
# diagnostic case simpler and avoids launcher/container interactions.
set +e
moose-dev-exec "${APP}" \
    -i "${INPUT}" \
    T_i="${T}" \
    strain_rate_i="${rate}" \
    rho_init_i="${rho_init}" \
    dt_i="${dt}" \
    end_time_i="${end_time}" \
    Outputs/file_base="${case_dir}/km" \
    > "${log_file}" 2>&1
exit_code=$?
set -e

if [ "${exit_code}" -eq 0 ] && [ -s "${csv_file}" ]; then
    status="OK"
else
    status="FAILED"
fi

printf '%s\n' \
    'array_task_id,rho_init,T,strain_rate,delta_strain,total_strain,dt,end_time,status,exit_code,csv_file,log_file' \
    "${TASK_ID},${rho_init},${T},${rate},${delta_strain},${total_strain},${dt},${end_time},${status},${exit_code},${csv_file},${log_file}" \
    > "${status_file}"

echo "===== FINISHED CASE ====="
echo "status    = ${status}"
echo "exit_code = ${exit_code}"
echo "csv_file  = ${csv_file}"

if [ "${status}" != "OK" ]; then
    echo "Last 120 lines of MOOSE log:"
    tail -n 120 "${log_file}" 2>/dev/null || true
fi

date

if [ "${status}" = "OK" ]; then
    exit 0
else
    exit 1
fi
