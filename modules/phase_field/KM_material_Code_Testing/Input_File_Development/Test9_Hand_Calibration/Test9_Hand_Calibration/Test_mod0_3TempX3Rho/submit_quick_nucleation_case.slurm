#!/bin/bash

#SBATCH --time=24:00:00
#SBATCH --nodes=3
#SBATCH --ntasks=40
#SBATCH --ntasks-per-node=40
#SBATCH --wckey=ne_ldrd
#SBATCH --partition=general
#SBATCH --job-name=umo_nuc_quick
#SBATCH --error=slurm-nucquick-%j.err
#SBATCH --output=slurm-nucquick-%j.out
#SBATCH --mail-user=tsuchun.teng@inl.gov
#SBATCH --mail-type=BEGIN,END,FAIL

# Usage:
#   sbatch submit_quick_nucleation_case.slurm TEMPERATURE STRAIN_RATE
#
# Example:
#   sbatch submit_quick_nucleation_case.slurm 873 0.1

if [ "$#" -ne 2 ]; then
  echo "Usage:"
  echo "  sbatch $0 TEMPERATURE STRAIN_RATE"
  exit 1
fi

T="$1"
RATE="$2"

date
hostname

cd "${SLURM_SUBMIT_DIR}" || exit 10

module purge
module load use.moose moose-dev-openmpi/2026.06.16

APP="/home/tengt/projects_moose/moose/modules/phase_field/phase_field-opt"
INPUT="${SLURM_SUBMIT_DIR}/km_nucleation_rate_scaled.i"

if [ ! -x "${APP}" ]; then
  echo "ERROR: executable not found:"
  echo "${APP}"
  exit 11
fi

if [ ! -f "${INPUT}" ]; then
  echo "ERROR: input file not found:"
  echo "${INPUT}"
  exit 12
fi

# --------------------------------------------------
# Fixed global parameters
# --------------------------------------------------

RHO_INIT="1e16"
TIME_SCALE="1.0"

NUC_PROB="2e-3"
FACTOR_N="0.3"
G_DOT_REF="1.0"
RHO_REF="1.0"

RSUBGRAIN="6e-8"

NUC_RADIUS="60.0"
INT_WIDTH="10.0"
NUC_STRENGTH="1000.0"

HOLD_STRAIN="0.05"

BNDS_MIN="0.55"
BNDS_MAX="0.85"

# --------------------------------------------------
# Short common-strain screening
# --------------------------------------------------

TOTAL_STRAIN="20.00"
DELTA_STRAIN="5e-3"
DT_CAP="1e-2"

DT_RAW=$(awk \
  -v ds="${DELTA_STRAIN}" \
  -v rate="${RATE}" \
  'BEGIN {printf "%.12g", ds / rate}')

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
  'BEGIN {printf "%.12g", hs / rate}')

END_TIME=$(awk \
  -v eps="${TOTAL_STRAIN}" \
  -v rate="${RATE}" \
  'BEGIN {printf "%.12g", eps / rate}')

rate_tag=$(echo "${RATE}" |
  sed 's/+//g; s/-/m/g; s/\./p/g')

CASE_NAME="T_${T}_gdot_${rate_tag}"
ROOT="NucleationQuick_3x3"
CASE_DIR="${ROOT}/${CASE_NAME}"

mkdir -p "${CASE_DIR}"

cat > "${CASE_DIR}/case_settings.txt" << EOF
T_i = ${T}
strain_rate_i = ${RATE}

rho_init_i = ${RHO_INIT}
time_scale_i = ${TIME_SCALE}

nuc_prob_i = ${NUC_PROB}
factor_n_i = ${FACTOR_N}
gdot_ref_i = ${G_DOT_REF}
rho_ref_i = ${RHO_REF}

r_subgrain_i = ${RSUBGRAIN}

nuc_radius_i = ${NUC_RADIUS}
int_width_i = ${INT_WIDTH}
nuc_strength_i = ${NUC_STRENGTH}

hold_strain = ${HOLD_STRAIN}
hold_time_i = ${HOLD_TIME}

bnds_min_i = ${BNDS_MIN}
bnds_max_i = ${BNDS_MAX}

total_strain = ${TOTAL_STRAIN}
delta_strain = ${DELTA_STRAIN}

dt_raw = ${DT_RAW}
dt_i = ${DT}
dt_nuc_i = ${DT_NUC}
end_time_i = ${END_TIME}

SLURM_JOB_ID = ${SLURM_JOB_ID}
EOF

echo "=================================================="
echo "QUICK NUCLEATION SCREEN"
echo "=================================================="
echo "T             = ${T} K"
echo "strain rate   = ${RATE} 1/s"
echo "target strain = ${TOTAL_STRAIN}"
echo "dt            = ${DT} s"
echo "hold time     = ${HOLD_TIME} s"
echo "end time      = ${END_TIME} s"
echo "output        = ${CASE_DIR}"
echo

mpiexec -n "${SLURM_NTASKS}" \
  moose-dev-exec "${APP}" \
  -i "${INPUT}" \
  T_i="${T}" \
  strain_rate_i="${RATE}" \
  rho_init_i="${RHO_INIT}" \
  time_scale_i="${TIME_SCALE}" \
  nuc_prob_i="${NUC_PROB}" \
  factor_n_i="${FACTOR_N}" \
  gdot_ref_i="${G_DOT_REF}" \
  rho_ref_i="${RHO_REF}" \
  r_subgrain_i="${RSUBGRAIN}" \
  nuc_radius_i="${NUC_RADIUS}" \
  int_width_i="${INT_WIDTH}" \
  nuc_strength_i="${NUC_STRENGTH}" \
  hold_time_i="${HOLD_TIME}" \
  bnds_min_i="${BNDS_MIN}" \
  bnds_max_i="${BNDS_MAX}" \
  dt_i="${DT}" \
  dt_nuc_i="${DT_NUC}" \
  end_time_i="${END_TIME}" \
  exodus_interval_i=1 \
  Outputs/file_base="${CASE_DIR}/result" \
  --allow-unused

exit_code=$?

echo
echo "Exit code = ${exit_code}"
date

exit "${exit_code}"