#!/usr/bin/env bash
set -euo pipefail

# Detect the CPUs belonging to the largest L3 cache group (V-Cache CCD on X3D)
# and print recommended kernel masks (nohz_full, rcu_nocbs, isolcpus, irqaffinity).

sysfs_base="/sys/devices/system/cpu"

parse_cpuset() {
  # Expand a CPU list like 0-3,8,10-11 to a sorted unique list of integers
  local s="$1"
  awk -v S="$s" 'BEGIN{
    n=split(S, A, ",");
    for (i=1;i<=n;i++) {
      g=A[i];
      if (g=="") continue;
      m=split(g, R, "-");
      if (m==2) { a=R[1]; b=R[2]; if (a>b) { t=a; a=b; b=t } for (j=a;j<=b;j++) print j; }
      else { print g }
    }
  }' | sort -n | uniq
}

compress_cpuset() {
  # Compress sorted list of integers to range form 0-3,8,10-11
  awk 'BEGIN{prev=""; start=""}
       { cur=$1; if (start=="") { start=cur; prev=cur; next }
         if (cur==prev+1) { prev=cur; next }
         if (start==prev) { printf (out?",":""); printf "%d", start }
         else { printf (out?",":""); printf "%d-%d", start, prev }
         out=1; start=cur; prev=cur }
       END{
         if (start=="") next;
         if (start==prev) { printf (out?",":""); printf "%d", start }
         else { printf (out?",":""); printf "%d-%d", start, prev }
         printf "\n" }'
}

pick_l3_vcache() {
  # Output CPUs of the largest L3 group as comma-ranges
  declare -A seen
  local best_size=0
  local best_cpus=""
  for cpu_dir in "$sysfs_base"/cpu[0-9]*; do
    [[ -d "$cpu_dir" ]] || continue
    local idx
    idx="${cpu_dir##*/}"
    idx="${idx#cpu}"
    [[ "$idx" =~ ^[0-9]+$ ]] || continue
    local base="$cpu_dir/cache/index3"
    local size_f="$base/size" share_f="$base/shared_cpu_list"
    [[ -r "$size_f" && -r "$share_f" ]] || continue
    local size shared
    size=$(<"$size_f")
    shared=$(<"$share_f")
    # Normalize size to bytes
    local bytes
    case "${size^^}" in
      *K) bytes=$(awk -v v="${size%K}" 'BEGIN{ printf "%.0f", v*1024 }') ;;
      *M) bytes=$(awk -v v="${size%M}" 'BEGIN{ printf "%.0f", v*1024*1024 }') ;;
      *G) bytes=$(awk -v v="${size%G}" 'BEGIN{ printf "%.0f", v*1024*1024*1024 }') ;;
      *) bytes=${size} ;;
    esac
    # Dedupe by shared CPU set
    key=$(parse_cpuset "$shared" | paste -sd, -)
    [[ -n "$key" ]] || continue
    if [[ -z "${seen[$key]:-}" ]]; then
      seen[$key]=$bytes
      if (( bytes > best_size )); then
        best_size=$bytes
        best_cpus="$key"
      fi
    fi
  done
  if [[ -z "$best_cpus" ]]; then
    # Fallback to online CPUs
    if [[ -r "$sysfs_base/online" ]]; then
      best_cpus=$(parse_cpuset "$(<"$sysfs_base/online")" | paste -sd, -)
    fi
  fi
  printf "%s\n" "$best_cpus"
}

main() {
  local vcache cpus_all non_vcache
  vcache=$(pick_l3_vcache)
  if [[ -z "$vcache" ]]; then
    echo "Could not detect L3 groups; is sysfs available?" >&2
    exit 1
  fi
  if [[ -r "$sysfs_base/online" ]]; then
    cpus_all=$(parse_cpuset "$(<"$sysfs_base/online")")
  else
    cpus_all=$(parse_cpuset "$vcache")
  fi
  # Build non-vcache set
  non_vcache=$(comm -23 \
    <(printf "%s\n" $cpus_all) \
    <(printf "%s\n" $(parse_cpuset "$vcache")) \
    | compress_cpuset)

  echo "VCACHE_CPUSET=$vcache"
  echo
  echo "Suggested kernel params:"
  echo "  nohz_full=$vcache"
  echo "  rcu_nocbs=$vcache"
  echo "  isolcpus=managed,domain,$vcache"
  if [[ -n "$non_vcache" ]]; then
    echo "  irqaffinity=$non_vcache"
  fi
}

main "$@"

