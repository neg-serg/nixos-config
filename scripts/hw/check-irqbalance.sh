#!/usr/bin/env bash
# check-irqbalance.sh — Formal test for irqbalance benefit on this system
#
# Measures:
#   1. IRQ rate on isolated CPUs     (lower = better isolation)
#   2. IRQ spread across non-isolated CPUs  (lower CV = better balance)
#   3. IRQs pinned to isolated CPUs  (should be 0 with working irqbalance)
#
# Usage:
#   ./check-irqbalance.sh                    # single measurement (10s sample)
#   ./check-irqbalance.sh --duration 30      # custom sample duration
#   ./check-irqbalance.sh --json             # machine-readable output

set -euo pipefail

DURATION=10
JSON=false
THRESHOLD_PASS_ISO=50
THRESHOLD_WARN_ISO=500
THRESHOLD_PASS_CV=30    # percent
THRESHOLD_WARN_CV=50    # percent

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration) DURATION="$2"; shift 2 ;;
    --json) JSON=true; shift ;;
    --threshold-pass-iso) THRESHOLD_PASS_ISO="$2"; shift 2 ;;
    --threshold-warn-iso) THRESHOLD_WARN_ISO="$2"; shift 2 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

# --- helpers ---
expand_cpu_list() {
  local raw=$1
  [[ -z "$raw" ]] && return
  tr ',' '\n' <<< "$raw" | while read -r tok; do
    tok=$(echo "$tok" | xargs)
    [[ -z "$tok" ]] && continue
    if [[ "$tok" == *-* ]]; then
      seq "${tok%-*}" "${tok#*-}"
    else
      echo "$tok"
    fi
  done | sort -n | tr '\n' ' '
}

# Count CPUs from /proc/interrupts header (NF = number of CPU columns)
count_cpus_from_proc() {
  awk 'NR==1 { print NF; exit }' /proc/interrupts
}

read_interrupts() {
  awk '
    NR==1 { ncpus=NF; next }
    {
      for(i=2;i<=NF;i++) sum[i-1]+=$i
    }
    END {
      for(c=1;c<=ncpus;c++) printf "%d %s\n", c-1, sum[c]
    }
  ' /proc/interrupts | sort -n
}

eff_has_cpu() {
  local eff=$1 cpu=$2
  local nibble_idx=$(( cpu / 4 ))
  local bit_in_nibble=$(( cpu % 4 ))
  local digit_idx=$(( ${#eff} - 1 - nibble_idx ))
  [[ $digit_idx -lt 0 ]] && return 1
  local digit="${eff:$digit_idx:1}"
  local dec_val=$(( 16#${digit} ))
  [[ $(( (dec_val >> bit_in_nibble) & 1 )) -eq 1 ]]
}

# --- collect ---
ISOLATED_RAW=$(cat /sys/devices/system/cpu/isolated 2>/dev/null || echo "")
ISOLATED_CPUS=$(expand_cpu_list "$ISOLATED_RAW")
ALL_CPUS=$(count_cpus_from_proc)

SNAPSHOT1=$(read_interrupts)
sleep "$DURATION"
SNAPSHOT2=$(read_interrupts)

declare -A RATE TOTAL1 TOTAL2
declare -a CPUS
while IFS=' ' read -r cpu cnt; do
  CPUS+=("$cpu")
  TOTAL1[$cpu]=$cnt
done <<< "$SNAPSHOT1"
while IFS=' ' read -r cpu cnt; do
  TOTAL2[$cpu]=$cnt
done <<< "$SNAPSHOT2"
for cpu in "${CPUS[@]}"; do
  RATE[$cpu]=$(( (${TOTAL2[$cpu]} - ${TOTAL1[$cpu]}) / DURATION ))
done

# --- metrics ---
iso_total_rate=0
noniso_total_rate=0
iso_cpu_count=0
noniso_cpu_count=0
iso_rates=()
noniso_rates=()

for cpu in "${CPUS[@]}"; do
  rate=${RATE[$cpu]}
  if [[ " $ISOLATED_CPUS " == *" $cpu "* ]]; then
    iso_total_rate=$((iso_total_rate + rate))
    iso_cpu_count=$((iso_cpu_count + 1))
    iso_rates+=("$rate")
  else
    noniso_total_rate=$((noniso_total_rate + rate))
    noniso_cpu_count=$((noniso_cpu_count + 1))
    noniso_rates+=("$rate")
  fi
done

noniso_mean=0
if [[ $noniso_cpu_count -gt 0 ]]; then
  noniso_mean=$((noniso_total_rate / noniso_cpu_count))
fi

# CV as percentage (integer math: stddev/mean * 100)
noniso_cv_pct="N/A"
if [[ $noniso_cpu_count -gt 1 && $noniso_mean -gt 0 ]]; then
  sum_sq=0
  for rate in "${noniso_rates[@]}"; do
    diff=$((rate - noniso_mean))
    sum_sq=$((sum_sq + diff * diff))
  done
  var=$((sum_sq / noniso_cpu_count))
  # integer sqrt via perl or python
  if command -v python3 &>/dev/null; then
    stddev=$(python3 -c "import math; print(int(math.sqrt($var)))")
  elif command -v perl &>/dev/null; then
    stddev=$(perl -e "print int(sqrt($var))")
  else
    stddev=0
  fi
  [[ $stddev -gt 0 ]] && noniso_cv_pct=$((stddev * 100 / noniso_mean))
fi

worst_deviation=0
if [[ $noniso_mean -gt 0 ]]; then
  for rate in "${noniso_rates[@]}"; do
    dev=$(( (rate - noniso_mean) * 100 / noniso_mean ))
    [[ $dev -lt 0 ]] && dev=$(( -dev ))
    [[ $dev -gt $worst_deviation ]] && worst_deviation=$dev
  done
fi

# pinned IRQs
iso_pinned=0
declare -a iso_pinned_list
for irqdir in /proc/irq/*/; do
  irq=$(basename "$irqdir")
  eff=$(cat "$irqdir/effective_affinity" 2>/dev/null) || continue
  name=$(cat "$irqdir/chip_name" 2>/dev/null || echo "?")
  for cpu in $ISOLATED_CPUS; do
    if eff_has_cpu "$eff" "$cpu"; then
      iso_pinned=$((iso_pinned + 1))
      iso_pinned_list+=("$irq|$name|$eff|$cpu")
      break
    fi
  done
done

# --- scoring ---
if [[ $iso_total_rate -le $THRESHOLD_PASS_ISO ]]; then
  iso_score="PASS"
elif [[ $iso_total_rate -le $THRESHOLD_WARN_ISO ]]; then
  iso_score="WARN"
else
  iso_score="FAIL"
fi

if [[ "$noniso_cv_pct" != "N/A" ]]; then
  if [[ $noniso_cv_pct -le $THRESHOLD_PASS_CV ]]; then
    cv_score="PASS"
  elif [[ $noniso_cv_pct -le $THRESHOLD_WARN_CV ]]; then
    cv_score="WARN"
  else
    cv_score="FAIL"
  fi
else
  cv_score="N/A"
fi

if [[ $iso_pinned -eq 0 ]]; then
  pin_score="PASS"
elif [[ $iso_pinned -le 5 ]]; then
  pin_score="WARN"
else
  pin_score="FAIL"
fi

if [[ "$iso_score" == "PASS" && "$cv_score" == "PASS" && "$pin_score" == "PASS" ]]; then
  overall="PASS"
elif [[ "$iso_score" == "FAIL" || "$pin_score" == "FAIL" ]]; then
  overall="FAIL"
else
  overall="WARN"
fi

# --- output ---
iso_max_rate=0
for r in "${iso_rates[@]}"; do [[ $r -gt $iso_max_rate ]] && iso_max_rate=$r; done

if $JSON; then
  cat <<EOF
{
  "overall": "$overall",
  "duration_sec": $DURATION,
  "timestamp": "$(date -Iseconds)",
  "cpus": { "total": $ALL_CPUS, "isolated": "$ISOLATED_RAW", "isolated_count": $iso_cpu_count, "nonisolated_count": $noniso_cpu_count },
  "metrics": {
    "isolated_irq_rate_total": $iso_total_rate,
    "isolated_max_cpu_rate": $iso_max_rate,
    "nonisolated_mean_rate": $noniso_mean,
    "nonisolated_cv_pct": $noniso_cv_pct,
    "nonisolated_worst_deviation_pct": $worst_deviation,
    "irqs_pinned_to_isolated": $iso_pinned
  },
  "scores": { "isolated_rate": "$iso_score", "distribution": "$cv_score", "pin_check": "$pin_score" }
}
EOF
else
  cat <<EOF
╔══════════════════════════════════════════════════════╗
║        irqbalance Benefit Test                       ║
╚══════════════════════════════════════════════════════╝

Duration:     ${DURATION}s sample
Host:         $(hostname)
Date:         $(date -Iseconds)

CPU config:   $ALL_CPUS total, $iso_cpu_count isolated ($ISOLATED_RAW)
              $noniso_cpu_count non-isolated

── Interrupt rates ────────────────────────────────────
  Isolated CPUs total:       ${iso_total_rate} IRQs/s
  Non-isolated mean:         ${noniso_mean} IRQs/s per CPU
  Non-isolated CV:           ${noniso_cv_pct}%
  Non-isolated worst dev:    ${worst_deviation}% from mean

  IRQs pinned to isolated:   ${iso_pinned}

── Per-CPU rates ─────────────────────────────────────
EOF
  for cpu in "${CPUS[@]}"; do
    rate=${RATE[$cpu]}
    if [[ " $ISOLATED_CPUS " == *" $cpu "* ]]; then
      printf "  CPU %2d: %8d IRQs/s  ← ISOLATED\n" "$cpu" "$rate"
    else
      printf "  CPU %2d: %8d IRQs/s\n" "$cpu" "$rate"
    fi
  done
  cat <<EOF

── Pinned IRQs on isolated CPUs ───────────────────────
EOF
  if [[ $iso_pinned -eq 0 ]]; then
    echo "  None found. Good."
  else
    for entry in "${iso_pinned_list[@]}"; do
      IFS='|' read -r irq name eff cpu <<< "$entry"
      printf "  IRQ %s (%s) eff=%s → CPU %d\n" "$irq" "$name" "$eff" "$cpu"
    done
  fi
  cat <<EOF

── Scores ────────────────────────────────────────────
  [${iso_score}] Isolated IRQ rate    (pass≤${THRESHOLD_PASS_ISO}, warn≤${THRESHOLD_WARN_ISO} IRQs/s)
  [${cv_score}] Non-isolated spread   (pass≤${THRESHOLD_PASS_CV}%, warn≤${THRESHOLD_WARN_CV}% CV)
  [${pin_score}] Pinned to isolated   (pass=0, warn≤5)

  OVERALL: ${overall}
EOF
fi

case "$overall" in
  PASS) exit 0 ;;
  WARN) exit 1 ;;
  FAIL) exit 2 ;;
esac
