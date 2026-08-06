#!/bin/bash

# Full Cartesian sweep:
#   5 temperatures
#   x 5 strain rates
#   x 5 initial dislocation densities
#   = 125 total cases

set -uo pipefail

APP="/Users/tengt/projects_moose/moose/modules/phase_field/phase_field-opt"
INPUT="km_only_sensitivity.i"
ROOT="KM_output"

# temps=(873 973 1073 1173 1273)
temps=(873 1073 1273)
# rates=(0.1 1.0 10.0 100.0 1000.0)
rates=(0.1 10.0 100.0 1000.0)
# rho_inits=(1e14 1e15 1e16 1e17 1e18)
# rho_inits=(1e16)
rho_inits=(1e12)

tag_number() {
  echo "$1" | sed 's/+//g; s/-/m/g; s/\./p/g'
}

# Check that the MOOSE executable exists.
if [ ! -x "$APP" ]; then
  echo "ERROR: MOOSE executable is missing or not executable:" >&2
  echo "       $APP" >&2
  exit 1
fi

# Check that the input file exists.
if [ ! -f "$INPUT" ]; then
  echo "ERROR: Input file not found:" >&2
  echo "       $INPUT" >&2
  exit 1
fi

mkdir -p "$ROOT/logs"

status_file="$ROOT/run_status.csv"

echo "rho_init,T,strain_rate,status,exit_code,csv_file,log_file" \
  > "$status_file"

total_cases=$((
  ${#rho_inits[@]} *
  ${#temps[@]} *
  ${#rates[@]}
))

case_number=0
ok_count=0
failed_count=0

for rho_init in "${rho_inits[@]}"; do

  rho_tag=$(tag_number "$rho_init")

  for T in "${temps[@]}"; do

    for rate in "${rates[@]}"; do

      case_number=$((case_number + 1))
      rate_tag=$(tag_number "$rate")

      case_dir="${ROOT}/rho_${rho_tag}/T_${T}/gdot_${rate_tag}"
      log_file="${ROOT}/logs/rho_${rho_tag}_T_${T}_gdot_${rate_tag}.log"
      csv_file="${case_dir}/km.csv"

      mkdir -p "$case_dir"

      # Remove an old output file so a failed run cannot be mistaken
      # for a successful run because of stale data.
      rm -f "$csv_file"

      echo
      echo "[${case_number}/${total_cases}] Running:"
      echo "  rho_init    = ${rho_init}"
      echo "  T           = ${T} K"
      echo "  strain_rate = ${rate} 1/s"

      delta_strain=1e-3
      total_strain=60.0

      dt=$(awk -v ds="$delta_strain" -v rate="$rate" 'BEGIN {printf "%.12g", ds/rate}')
      end_time=$(awk -v es="$total_strain" -v rate="$rate" 'BEGIN {printf "%.12g", es/rate}')

      mpiexec -n 8 "$APP" -i "$INPUT" \
        T_i="$T" \
        strain_rate_i="$rate" \
        rho_init_i="$rho_init" \
        dt_i="$dt" \
        end_time_i="$end_time" \
        Outputs/file_base="${case_dir}/km" \
        > "$log_file" 2>&1

      exit_code=$?

      if [ "$exit_code" -eq 0 ] && [ -f "$csv_file" ]; then

        echo "  OK: $csv_file"

        echo \
          "${rho_init},${T},${rate},OK,${exit_code},${csv_file},${log_file}" \
          >> "$status_file"

        ok_count=$((ok_count + 1))

      else

        echo "  FAILED:"
        echo "    rho_init    = ${rho_init}"
        echo "    T           = ${T}"
        echo "    strain_rate = ${rate}"
        echo "    exit code   = ${exit_code}"
        echo "    log file    = ${log_file}"

        echo \
          "${rho_init},${T},${rate},FAILED,${exit_code},${csv_file},${log_file}" \
          >> "$status_file"

        failed_count=$((failed_count + 1))

        echo
        echo "  Last 30 lines of the log:"
        tail -n 30 "$log_file"

      fi

    done
  done
done

echo
echo "Finished full parameter sweep."
echo "Total cases:      $total_cases"
echo "Successful cases: $ok_count"
echo "Failed cases:     $failed_count"

echo
echo "CSV files found:"
find "$ROOT" -name "km.csv" -print | sort

echo
echo "Number of CSV files:"
find "$ROOT" -name "km.csv" -print | wc -l | tr -d ' '
echo

echo
echo "Status file:"
echo "$status_file"

# Return a nonzero exit status when one or more simulations failed.
if [ "$failed_count" -gt 0 ]; then
  exit 1
fi