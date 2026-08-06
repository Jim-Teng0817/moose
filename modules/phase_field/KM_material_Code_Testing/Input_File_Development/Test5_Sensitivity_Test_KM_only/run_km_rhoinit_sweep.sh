#!/bin/bash

set -u

APP="/Users/tengt/projects_moose/moose/modules/phase_field/phase_field-opt"
INPUT="km_only_sensitivity.i"
ROOT="KM_output"

T="1073"
rate="10.0"

rho_inits=(1e14 1e15 1e16 1e17 1e18)

tag_number () {
  echo "$1" | sed 's/+//g; s/-/m/g; s/\./p/g'
}

rate_tag=$(tag_number "$rate")

for rho_init in "${rho_inits[@]}"; do

  rho_tag=$(tag_number "$rho_init")

  case_dir="${ROOT}/rho_${rho_tag}/T_${T}/gdot_${rate_tag}"

  mkdir -p "$case_dir"

  echo "Running rho_init=${rho_init}, T=${T} K, strain_rate=${rate} 1/s"

  "$APP" -i "$INPUT" \
    T_i="$T" \
    strain_rate_i="$rate" \
    rho_init_i="$rho_init" \
    out_dir="$case_dir" \
    case_name="km"

done

echo "Finished rho_init sweep."