#!/bin/bash

# ============================================================
# KM-only full Cartesian sensitivity sweep
#
#   5 temperatures
#   x 5 strain rates
#   x 5 initial dislocation densities
#   = 125 independent cases
#
# Each array task runs one case.
# Up to 20 cases run concurrently.
# ============================================================

#SBATCH --time=24:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --wckey=ne_ldrd
#SBATCH --partition=general
#SBATCH --job-name=km_only_sweep
#SBATCH --error=slurm-km-%A_%a.err
#SBATCH --output=slurm-km-%A_%a.out
#SBATCH --mail-user=tsuchun.teng@inl.gov
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --array=0-0%1
##SBATCH --array=0-124%20

set -uo pipefail


# ============================================================
# Clean inherited Python/Conda environment
# ============================================================

unset CONDA_PREFIX
unset CONDA_DEFAULT_ENV
unset CONDA_SHLVL
unset CONDA_PROMPT_MODIFIER
unset PYTHONPATH
unset PYTHONHOME


# ============================================================
# Load INL MOOSE environment
# ============================================================

source /etc/profile.d/modules.sh 2>/dev/null || true

module purge
module load use.moose moose-dev-openmpi/2026.06.16


# ============================================================
# Move to directory where sbatch was submitted
# ============================================================

SUBMIT_DIR="${SLURM_SUBMIT_DIR:-$(pwd)}"
cd "${SUBMIT_DIR}"


# ============================================================
# Verify that this job was submitted as an array
# ============================================================

if [ -z "${SLURM_ARRAY_TASK_ID:-}" ]; then
    echo "ERROR: SLURM_ARRAY_TASK_ID is not defined."
    echo "This script must be submitted as a Slurm array."
    exit 1
fi

task_id="${SLURM_ARRAY_TASK_ID}"


# ============================================================
# Basic job information
# ============================================================

echo "============================================================"
echo "SLURM JOB INFORMATION"
echo "============================================================"
date
hostname

echo "SLURM_JOB_ID        = ${SLURM_JOB_ID:-UNSET}"
echo "SLURM_ARRAY_JOB_ID  = ${SLURM_ARRAY_JOB_ID:-UNSET}"
echo "SLURM_ARRAY_TASK_ID = ${task_id}"
echo "SLURM_SUBMIT_DIR    = ${SLURM_SUBMIT_DIR:-UNSET}"
echo "SLURM_NTASKS        = ${SLURM_NTASKS:-UNSET}"
echo "Working directory   = $(pwd)"
echo


# ============================================================
# MOOSE executable, input file, and output root
# ============================================================

APP="/home/tengt/projects_moose/moose/modules/phase_field/phase_field-opt"

INPUT="km_only_Sensitivity_mod5.i"

ROOT="KM_output"


# ============================================================
# Parameter arrays
# ============================================================

temps=(
    873
    973
    1073
    1173
    1273
)

rates=(
    0.1
    1.0
    10.0
    100.0
    1000.0
)

rho_inits=(
    1e14
    1e15
    1e16
    1e17
    1e18
)


# ============================================================
# Strain-controlled time integration
#
# dt       = delta_strain / strain_rate
# end_time = total_strain / strain_rate
#
# Every case therefore experiences:
#
#   50 / 0.001 = 50,000 strain increments
# ============================================================

delta_strain="1e-3"
total_strain="50.0"


# ============================================================
# Utility: create filesystem-safe number tags
#
# Examples:
#   0.1   -> 0p1
#   1.0   -> 1p0
#   1e16  -> 1e16
# ============================================================

tag_number()
{
    echo "$1" | sed 's/+//g; s/-/m/g; s/\./p/g'
}


# ============================================================
# Check executable, input file, and runtime commands
# ============================================================

if [ ! -x "${APP}" ]; then
    echo "ERROR: MOOSE executable is missing or not executable:"
    echo "       ${APP}"
    exit 2
fi

if [ ! -f "${INPUT}" ]; then
    echo "ERROR: Input file was not found:"
    echo "       ${INPUT}"
    echo
    echo "Available MOOSE input files:"
    ls -lh *.i 2>/dev/null || true
    exit 3
fi

if ! command -v mpiexec >/dev/null 2>&1; then
    echo "ERROR: mpiexec was not found after loading the MOOSE module."
    exit 4
fi

if ! command -v moose-dev-exec >/dev/null 2>&1; then
    echo "ERROR: moose-dev-exec was not found after loading the MOOSE module."
    exit 5
fi

echo "MOOSE executable:"
echo "  ${APP}"

echo "Input file:"
echo "  ${INPUT}"

echo "MPI executable:"
command -v mpiexec

echo "MOOSE wrapper:"
command -v moose-dev-exec

echo


# ============================================================
# Create output folders
# ============================================================

mkdir -p \
    "${ROOT}/logs" \
    "${ROOT}/status"


# ============================================================
# Calculate total number of cases
# ============================================================

n_rho=${#rho_inits[@]}
n_temp=${#temps[@]}
n_rate=${#rates[@]}

total_cases=$(( n_rho * n_temp * n_rate ))


# ============================================================
# Validate array task number
# ============================================================

if [ "${task_id}" -lt 0 ] || [ "${task_id}" -ge "${total_cases}" ]; then
    echo "ERROR: Array task ID is outside the valid range."
    echo "task_id    = ${task_id}"
    echo "valid IDs  = 0 through $(( total_cases - 1 ))"
    exit 6
fi


# ============================================================
# Map array task ID to parameter indices
#
# task_id =
#     rho_index * (n_temp * n_rate)
#     + temp_index * n_rate
#     + rate_index
# ============================================================

rho_index=$(( task_id / (n_temp * n_rate) ))

remainder=$(( task_id % (n_temp * n_rate) ))

temp_index=$(( remainder / n_rate ))

rate_index=$(( remainder % n_rate ))


# ============================================================
# Select parameters for this array task
# ============================================================

rho_init="${rho_inits[$rho_index]}"
T="${temps[$temp_index]}"
rate="${rates[$rate_index]}"


# ============================================================
# Build output folder names
# ============================================================

rho_tag=$(tag_number "${rho_init}")
rate_tag=$(tag_number "${rate}")

case_name="rho_${rho_tag}_T_${T}_gdot_${rate_tag}"

case_dir="${ROOT}/rho_${rho_tag}/T_${T}/gdot_${rate_tag}"

log_file="${ROOT}/logs/${case_name}.log"

status_file="${ROOT}/status/run_status_${task_id}.csv"

csv_file="${case_dir}/km.csv"


# ============================================================
# Compute time step and end time
# ============================================================

dt=$(
    awk \
        -v ds="${delta_strain}" \
        -v rate="${rate}" \
        'BEGIN {printf "%.12g", ds / rate}'
)

end_time=$(
    awk \
        -v es="${total_strain}" \
        -v rate="${rate}" \
        'BEGIN {printf "%.12g", es / rate}'
)


# ============================================================
# Prepare case directory
# ============================================================

mkdir -p "${case_dir}"

# Remove old files so failed reruns cannot be confused with
# successful earlier runs.
rm -f \
    "${csv_file}" \
    "${log_file}"


# ============================================================
# Write complete case settings
# ============================================================

cat > "${case_dir}/case_settings.txt" << EOF
case_name = ${case_name}

rho_init_i = ${rho_init}
T_i = ${T}
strain_rate_i = ${rate}

delta_strain = ${delta_strain}
total_strain = ${total_strain}

dt_i = ${dt}
end_time_i = ${end_time}

rho_index = ${rho_index}
temp_index = ${temp_index}
rate_index = ${rate_index}

SLURM_JOB_ID = ${SLURM_JOB_ID:-UNSET}
SLURM_ARRAY_JOB_ID = ${SLURM_ARRAY_JOB_ID:-UNSET}
SLURM_ARRAY_TASK_ID = ${task_id}

MOOSE_executable = ${APP}
input_file = ${INPUT}
EOF


# ============================================================
# Print case information
# ============================================================

echo "============================================================"
echo "RUNNING KM-ONLY CASE"
echo "============================================================"

echo "Array task:"
echo "  ${task_id} of $(( total_cases - 1 ))"

echo "Parameter indices:"
echo "  rho_index  = ${rho_index}"
echo "  temp_index = ${temp_index}"
echo "  rate_index = ${rate_index}"

echo "Physical parameters:"
echo "  rho_init     = ${rho_init} 1/m^2"
echo "  temperature  = ${T} K"
echo "  strain_rate  = ${rate} 1/s"

echo "Integration parameters:"
echo "  delta_strain = ${delta_strain}"
echo "  total_strain = ${total_strain}"
echo "  dt           = ${dt} s"
echo "  end_time     = ${end_time} s"

echo "Output:"
echo "  case_dir     = ${case_dir}"
echo "  csv_file     = ${csv_file}"
echo "  log_file     = ${log_file}"
echo "  status_file  = ${status_file}"

echo


# ============================================================
# Run one KM-only MOOSE case
#
# One MPI rank is enough for the one-element KM-only problem.
# Array concurrency provides parallel throughput.
# ============================================================

# mpiexec -n 1 \
#     moose-dev-exec "${APP}" \
#     -i "${INPUT}" \
#     T_i="${T}" \
#     strain_rate_i="${rate}" \
#     rho_init_i="${rho_init}" \
#     dt_i="${dt}" \
#     end_time_i="${end_time}" \
#     Outputs/file_base="${case_dir}/km" \
#     > "${log_file}" 2>&1

srun --ntasks=1 \
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


# ============================================================
# Determine success/failure
# ============================================================

if [ "${exit_code}" -eq 0 ] && [ -s "${csv_file}" ]; then
    status="OK"
else
    status="FAILED"
fi


# ============================================================
# Write one status file per array task
#
# Separate files prevent simultaneous array tasks from writing
# to the same status CSV.
# ============================================================

echo \
"array_task_id,rho_init,T,strain_rate,delta_strain,total_strain,dt,end_time,status,exit_code,csv_file,log_file" \
> "${status_file}"

echo \
"${task_id},${rho_init},${T},${rate},${delta_strain},${total_strain},${dt},${end_time},${status},${exit_code},${csv_file},${log_file}" \
>> "${status_file}"


# ============================================================
# Report result
# ============================================================

echo
echo "============================================================"
echo "FINISHED KM-ONLY CASE"
echo "============================================================"

echo "case_name = ${case_name}"
echo "status    = ${status}"
echo "exit_code = ${exit_code}"
echo "csv_file  = ${csv_file}"

if [ "${status}" != "OK" ]; then
    echo
    echo "The case failed or did not create a nonempty CSV file."
    echo
    echo "Last 100 lines of the MOOSE log:"
    tail -n 100 "${log_file}" 2>/dev/null || true
fi

echo
date


# ============================================================
# Return the MOOSE exit status to Slurm
# ============================================================

if [ "${status}" = "OK" ]; then
    exit 0
else
    exit 1
fi