#!/bin/bash

# Validate one input before submitting it.
# Usage:
#   bash preflight_one_case.sh cases/00_mask_width/<case>/input.i

if [ "$#" -ne 1 ]; then
  echo "Usage: bash preflight_one_case.sh <relative/path/to/input.i>"
  exit 2
fi

module purge
module load use.moose moose-dev-openmpi/2026.06.16

APP="/home/tengt/projects_moose/moose/modules/phase_field/phase_field-opt"
INPUT="$1"

if [ ! -f "${INPUT}" ]; then
  echo "ERROR: input file is missing: ${INPUT}"
  exit 12
fi

moose-dev-exec "${APP}" \
  -i "${INPUT}" \
  --check-input \
  --allow-unused
