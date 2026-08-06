#!/bin/bash

set -u

APP="/Users/tengt/projects_moose/moose/modules/phase_field/phase_field-opt"
INPUT="km_only_sensitivity.i"
ROOT="KM_output"

temps=(873 973 1073 1173 1273)
rates=(0.1 1.0 10.0 100.0 1000.0)

# Start with only one rho_init.
# Later you can change this to:
# rho_inits=(1e14 1e15 1e16 1e17 1e18)
rho_inits=(1e14)

tag_number () {
  echo "$1" | sed 's/+//g; s/-/m/g; s/\./p/g'
}

mkdir -p "$ROOT/logs"

status_file="$ROOT/run_status.csv"
echo "rho_init,T,strain_rate,status,exit_code,csv_file,log_file" > "$status_file"

for rho_init in "${rho_inits[@]}"; do
  rho_tag=$(tag_number "$rho_init")

  for T in "${temps[@]}"; do
    for rate in "${rates[@]}"; do

      rate_tag=$(tag_number "$rate")

      case_dir="${ROOT}/rho_${rho_tag}/T_${T}/gdot_${rate_tag}"
      log_file="${ROOT}/logs/rho_${rho_tag}_T_${T}_gdot_${rate_tag}.log"
      csv_file="${case_dir}/km.csv"

      mkdir -p "$case_dir"

      echo "Running rho_init=${rho_init}, T=${T} K, strain_rate=${rate} 1/s"

      "$APP" -i "$INPUT" \
        T_i="$T" \
        strain_rate_i="$rate" \
        rho_init_i="$rho_init" \
        Outputs/file_base="${case_dir}/km" \
        > "$log_file" 2>&1

      exit_code=$?

      if [ "$exit_code" -eq 0 ] && [ -f "$csv_file" ]; then
        echo "  OK: $csv_file"
        echo "${rho_init},${T},${rate},OK,${exit_code},${csv_file},${log_file}" >> "$status_file"
      else
        echo "  FAILED: rho_init=${rho_init}, T=${T}, strain_rate=${rate}"
        echo "  See log: $log_file"
        echo "${rho_init},${T},${rate},FAILED,${exit_code},${csv_file},${log_file}" >> "$status_file"
        tail -n 30 "$log_file"
      fi

    done
  done
done

echo
echo "Finished sweep."
echo "CSV files found:"
find "$ROOT" -name "km.csv" | sort

echo
echo "Number of CSV files:"
find "$ROOT" -name "km.csv" | wc -l

echo
echo "Status file:"
echo "$status_file"