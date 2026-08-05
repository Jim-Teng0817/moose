#!/bin/bash

#SBATCH --time=168:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=40
#SBATCH --ntasks-per-node=40
#SBATCH --wckey=ne_ldrd
#SBATCH --partition=general
#SBATCH --job-name=umo_nuc_3x3
#SBATCH --error=slurm-nuc3x3-%A_%a.err
#SBATCH --output=slurm-nuc3x3-%A_%a.out
#SBATCH --mail-user=tsuchun.teng@inl.gov
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --array=0-8
#SBATCH --export=ALL

set -uo pipefail
unset CONDA_PREFIX CONDA_DEFAULT_ENV CONDA_SHLVL CONDA_PROMPT_MODIFIER
unset PYTHONPATH PYTHONHOME
source /etc/profile.d/modules.sh 2>/dev/null || true
module purge
module load use.moose moose-dev-openmpi/2026.06.16

cd "${SLURM_SUBMIT_DIR:-$(pwd)}"
APP="/home/tengt/projects_moose/moose/modules/phase_field/phase_field-opt"
INPUT="km_nucleation_rate_scaled_Deformed10grains.i"

# EDIT THIS after the 27 short calibration tasks are postprocessed.
SELECTED_FACTOR="0.3"

TEMPS=(873 1073 1273)
RATES=(0.1 100.0 1000.0)
N_R=${#RATES[@]}
TASK_ID="${SLURM_ARRAY_TASK_ID:-0}"
T_INDEX=$((TASK_ID / N_R))
R_INDEX=$((TASK_ID % N_R))
T="${TEMPS[$T_INDEX]}"
RATE="${RATES[$R_INDEX]}"

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

# Longer validation/production run.
TOTAL_STRAIN="5.0"
DELTA_STRAIN="5e-3"
DT_CAP="1e-2"
EXODUS_INTERVAL="20"

DT_RAW=$(awk -v ds="${DELTA_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", ds/rate}')
DT=$(awk -v raw="${DT_RAW}" -v cap="${DT_CAP}" 'BEGIN {if (raw < cap) printf "%.12g", raw; else printf "%.12g", cap}')
DT_NUC="${DT}"
HOLD_TIME=$(awk -v hs="${HOLD_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", hs/rate}')
END_TIME=$(awk -v eps="${TOTAL_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", eps/rate}')

rate_tag=$(echo "${RATE}" | sed 's/+//g; s/-/m/g; s/\./p/g')
factor_tag=$(echo "${SELECTED_FACTOR}" | sed 's/+//g; s/-/m/g; s/\./p/g')
case_name="factor_${factor_tag}_T_${T}_gdot_${rate_tag}"
ROOT="NucleationSweep_3x3_selectedFactor"
CASE_DIR="${ROOT}/${case_name}"
LOG_DIR="${ROOT}/logs"
mkdir -p "${CASE_DIR}" "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/${case_name}.log"

cat > "${CASE_DIR}/case_settings.txt" <<SETTINGS
factor_n_i = ${SELECTED_FACTOR}
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
dt_i = ${DT}
dt_nuc_i = ${DT_NUC}
end_time_i = ${END_TIME}
SETTINGS

NPROCS="${SLURM_NTASKS:-40}"
set +e
mpiexec -n "${NPROCS}" moose-dev-exec "${APP}" \
  -i "${INPUT}" \
  T_i="${T}" strain_rate_i="${RATE}" rho_init_i="${RHO_INIT}" \
  time_scale_i="${TIME_SCALE}" gdot_ref_i="${G_DOT_REF}" rho_ref_i="${RHO_REF}" \
  factor_n_i="${SELECTED_FACTOR}" nuc_prob_i="${NUC_PROB}" \
  hold_time_i="${HOLD_TIME}" nuc_radius_i="${NUC_RADIUS}" \
  int_width_i="${INT_WIDTH}" nuc_strength_i="${NUC_STRENGTH}" \
  bnds_min_i="${BNDS_MIN}" bnds_max_i="${BNDS_MAX}" \
  dt_i="${DT}" dt_nuc_i="${DT_NUC}" end_time_i="${END_TIME}" \
  exodus_interval_i="${EXODUS_INTERVAL}" \
  Outputs/file_base="${CASE_DIR}/result" --allow-unused \
  > "${LOG_FILE}" 2>&1
exit_code=$?
set -e

status="FAILED"
if [ "${exit_code}" -eq 0 ] && [ -f "${CASE_DIR}/result.csv" ]; then status="OK"; fi
echo "${case_name}: ${status}, exit_code=${exit_code}"
if [ "${exit_code}" -ne 0 ]; then tail -n 120 "${LOG_FILE}" || true; fi
exit "${exit_code}"
