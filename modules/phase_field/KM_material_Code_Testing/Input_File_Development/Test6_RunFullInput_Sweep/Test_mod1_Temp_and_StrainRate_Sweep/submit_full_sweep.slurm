#!/bin/bash

#SBATCH --time=168:00:00
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=40
#SBATCH --wckey=ne_ldrd
#SBATCH --partition=general
#SBATCH --job-name=umo_full_sweep
#SBATCH --error=slurm-%A_%a.err
#SBATCH --output=slurm-%A_%a.out
#SBATCH --mail-user=tsuchun.teng@inl.gov
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --array=0-24

set -uo pipefail

module purge
module load use.moose moose-dev-openmpi/2026.06.16

cd "${SLURM_SUBMIT_DIR}"

date
echo "SLURM_JOB_ID        = ${SLURM_JOB_ID}"
echo "SLURM_ARRAY_TASK_ID = ${SLURM_ARRAY_TASK_ID}"
echo "SLURM_NTASKS        = ${SLURM_NTASKS}"
echo "Working directory   = ${SLURM_SUBMIT_DIR}"

APP="/home/tengt/projects_moose/moose/modules/phase_field/phase_field-opt"
INPUT="km_nucleation_Full_mod1.i"

echo "Checking executable and input..."
which moose-dev-exec || true
ls -lh "${APP}"
ls -lh "${INPUT}"

RHO_INIT="1e16"
TIME_SCALE="1.0"

TEMPS=(873 973 1073 1173 1273)
RATES=(0.1 1.0 10.0 100.0 1000.0)

N_RATES=${#RATES[@]}

T_INDEX=$(( SLURM_ARRAY_TASK_ID / N_RATES ))
R_INDEX=$(( SLURM_ARRAY_TASK_ID % N_RATES ))

T="${TEMPS[$T_INDEX]}"
RATE="${RATES[$R_INDEX]}"

DELTA_STRAIN="5e-3"

case "${T}" in
  873)
    TOTAL_STRAIN="150.0"        # 50.0
    ;;
  973)
    TOTAL_STRAIN="105.0"        # 35.0
    ;;
  1073)
    TOTAL_STRAIN="60.0"        # 20.0
    ;;
  1173)
    TOTAL_STRAIN="36.0"        # 12.0
    ;;
  1273)
    TOTAL_STRAIN="24.0"         # 8.0
    ;;
  *)
    TOTAL_STRAIN="60.0"        # 20.0
    ;;
esac

DT=$(awk -v ds="${DELTA_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", ds/rate}')
END_TIME=$(awk -v eps="${TOTAL_STRAIN}" -v rate="${RATE}" 'BEGIN {printf "%.12g", eps/rate}')
DT_NUC="${DT}"

rate_tag=$(echo "${RATE}" | sed 's/\./p/g')
rho_tag=$(echo "${RHO_INIT}" | sed 's/+//g; s/\./p/g')

case_name="rho_${rho_tag}_T_${T}_gdot_${rate_tag}"

ROOT="FullSweep_rho1e16_longerTime_largerStrain"
CASE_DIR="${ROOT}/${case_name}"
LOG_DIR="${ROOT}/logs"

mkdir -p "${CASE_DIR}" "${LOG_DIR}"

LOG_FILE="${LOG_DIR}/${case_name}.log"
STATUS_FILE="${ROOT}/run_status_${SLURM_ARRAY_TASK_ID}.csv"

cat > "${CASE_DIR}/case_settings.txt" << EOF
T_i = ${T}
strain_rate_i = ${RATE}
rho_init_i = ${RHO_INIT}
time_scale_i = ${TIME_SCALE}
total_strain_i = ${TOTAL_STRAIN}
delta_strain = ${DELTA_STRAIN}
dt_i = ${DT}
dt_nuc_i = ${DT_NUC}
end_time_i = ${END_TIME}
SLURM_JOB_ID = ${SLURM_JOB_ID}
SLURM_ARRAY_TASK_ID = ${SLURM_ARRAY_TASK_ID}
EOF

echo "Running case:"
echo "  T            = ${T}"
echo "  strain_rate  = ${RATE}"
echo "  rho_init     = ${RHO_INIT}"
echo "  dt           = ${DT}"
echo "  dt_nuc       = ${DT_NUC}"
echo "  end_time     = ${END_TIME}"
echo "  CASE_DIR     = ${CASE_DIR}"
echo "  LOG_FILE     = ${LOG_FILE}"

set +e

mpiexec -n "${SLURM_NTASKS}" moose-dev-exec "${APP}" \
  -i "${INPUT}" \
  T_i="${T}" \
  strain_rate_i="${RATE}" \
  rho_init_i="${RHO_INIT}" \
  time_scale_i="${TIME_SCALE}" \
  dt_i="${DT}" \
  dt_nuc_i="${DT_NUC}" \
  end_time_i="${END_TIME}" \
  Outputs/file_base="${CASE_DIR}/result" \
  --allow-unused \
  > "${LOG_FILE}" 2>&1

exit_code=$?

set -e

if [ "${exit_code}" -eq 0 ]; then
  status="OK"
else
  status="FAILED"
fi

echo "array_id,T,strain_rate,rho_init,total_strain,delta_strain,dt,end_time,status,exit_code,case_dir" > "${STATUS_FILE}"
echo "${SLURM_ARRAY_TASK_ID},${T},${RATE},${RHO_INIT},${TOTAL_STRAIN},${DELTA_STRAIN},${DT},${END_TIME},${status},${exit_code},${CASE_DIR}" >> "${STATUS_FILE}"

echo "Finished case ${case_name} with status ${status}"
echo "Exit code = ${exit_code}"

if [ "${exit_code}" -ne 0 ]; then
  echo "Last 100 lines of MOOSE log:"
  tail -n 100 "${LOG_FILE}"
fi

date

exit "${exit_code}"