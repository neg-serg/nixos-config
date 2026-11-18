#!/usr/bin/env bash
# disk-triage — one-shot triage for "the disk is slow" / "is the disk loaded?".
#
# iostat -x answers only "what did the device do", and its %util column is a
# trap: on NVMe/RAID it reaches 100% while the device is far from saturated,
# because %util counts time with at least one request in flight, not capacity.
# This script samples the numbers that actually describe load (await, queue
# depth, PSI stall), adds dirty pages, per-process I/O, health and redundancy,
# and reports findings instead of raw tables.
#
# What it deliberately does NOT answer: application QPS/latency (watch the
# app), block-level per-I/O traces (blktrace/biosnoop need root and a wider
# window) and history (sar).
#
# Usage:
#   disk-triage.sh
#   disk-triage.sh --sample 10 --format json
#   disk-triage.sh --fio /var/tmp        # baseline: what the disk can do
#
# Thresholds (env, all optional):
#   TRIAGE_AWAIT_WARN_SSD=2      device latency, ms (non-rotational)
#   TRIAGE_AWAIT_CRIT_SSD=10
#   TRIAGE_AWAIT_WARN_HDD=20     device latency, ms (rotational)
#   TRIAGE_AWAIT_CRIT_HDD=100
#   TRIAGE_AQU_WARN=8            average queue depth (aqu-sz)
#   TRIAGE_PSI_IO_WARN=5         PSI io full avg10, percent
#   TRIAGE_PSI_IO_CRIT=20
#   TRIAGE_DIRTY_WARN=25         dirty pages vs the dirty limit, percent
#   TRIAGE_DIRTY_CRIT=50
#   TRIAGE_TOP_N=10              how many processes to report
#   TRIAGE_SAMPLE_SECONDS=5      sampling window
#
# Exit codes: 0 clean, 1 warnings, 2 critical findings, 3 usage/dependency error.
#
# Notes:
#   * Non-root is supported. Per-process I/O, SMART and zpool are then blind,
#     and the report says so instead of pretending the picture is complete.
#   * --fio writes FIO_SIZE bytes into the given directory and removes them;
#     point it at a scratch dataset, not a production path.
#   * iostat runs with -y: the first, since-boot report is a lifetime average
#     and must never be read as "current load".
#   * aqu-sz and await are reported per device; %util is shown, not judged.
#   * pidstat reads /proc/PID/io. When a short-lived child exits, the kernel
#     folds its counters into the parent, so a sub-second writer can show up
#     as "bash" instead of its own name; long-lived writers are attributed
#     correctly.

set -euo pipefail

readonly PROG=${0##*/}
readonly TOOL_VERSION=0.1.0

SAMPLE=${TRIAGE_SAMPLE_SECONDS:-5}
FORMAT=text
SMART_MODE=auto
FIO_DIR=""
FIO_SIZE=1G
FIO_RUNTIME=15
TOP_N=${TRIAGE_TOP_N:-10}

AWAIT_WARN_SSD=${TRIAGE_AWAIT_WARN_SSD:-2}
AWAIT_CRIT_SSD=${TRIAGE_AWAIT_CRIT_SSD:-10}
AWAIT_WARN_HDD=${TRIAGE_AWAIT_WARN_HDD:-20}
AWAIT_CRIT_HDD=${TRIAGE_AWAIT_CRIT_HDD:-100}
AQU_WARN=${TRIAGE_AQU_WARN:-8}
PSI_WARN=${TRIAGE_PSI_IO_WARN:-5}
PSI_CRIT=${TRIAGE_PSI_IO_CRIT:-20}
DIRTY_WARN=${TRIAGE_DIRTY_WARN:-25}
DIRTY_CRIT=${TRIAGE_DIRTY_CRIT:-50}

usage() {
  sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

die() {
  printf '%s: %s\n' "$PROG" "$*" >&2
  exit 3
}

while (($#)); do
  case $1 in
    --sample) SAMPLE=${2:-} && shift 2 ;;
    --format) FORMAT=${2:-} && shift 2 ;;
    --fio) FIO_DIR=${2:-} && shift 2 ;;
    --fio-size) FIO_SIZE=${2:-} && shift 2 ;;
    --fio-runtime) FIO_RUNTIME=${2:-} && shift 2 ;;
    --top) TOP_N=${2:-} && shift 2 ;;
    --smart) SMART_MODE=${2:-} && shift 2 ;;
    --help) usage 0 ;;
    --version) printf '%s %s\n' "$PROG" "$TOOL_VERSION" && exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

[[ $FORMAT == text || $FORMAT == json ]] || die "--format must be text or json"
[[ $SMART_MODE == auto || $SMART_MODE == off ]] || die "--smart must be auto or off"
[[ $SAMPLE =~ ^[1-9][0-9]*$ ]] || die "--sample must be a positive integer"
[[ $TOP_N =~ ^[0-9]+$ ]] || die "--top must be a non-negative integer"
[[ $FIO_RUNTIME =~ ^[1-9][0-9]*$ ]] || die "--fio-runtime must be a positive integer"

command -v iostat > /dev/null 2>&1 || die "iostat not found (install sysstat)"
command -v jq > /dev/null 2>&1 || die "jq not found"
command -v awk > /dev/null 2>&1 || die "awk not found"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/disk-triage.XXXXXX")
FIO_FILE=""
cleanup() {
  [[ -n $FIO_FILE ]] && rm -f "$FIO_FILE"
  rm -rf "$TMP"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

nz() {
  local v=${1:-}
  if [[ $v =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then printf '%s' "$v"; else printf '0'; fi
}

ge() { awk -v a="$(nz "$1")" -v b="$(nz "$2")" 'BEGIN { exit !(a >= b) }'; }
lt() { awk -v a="$(nz "$1")" -v b="$(nz "$2")" 'BEGIN { exit !(a < b) }'; }

pct() {
  awk -v a="$(nz "$1")" -v b="$(nz "$2")" 'BEGIN { if (b == 0) print "n/a"; else printf "%.1f", a * 100 / b }'
}

# avg10 of a PSI class ("some" or "full"); empty when the file is absent.
psi_avg10() {
  local file=$1 class=$2
  [[ -r $file ]] || return 0
  awk -v c="$class" '
    $1 == c { for (i = 2; i <= NF; i++) { split($i, kv, "="); if (kv[1] == "avg10") { print kv[2]; exit } } }
  ' "$file"
}

meminfo_kb() {
  awk -v k="$1:" '$1 == k { print $2; exit }' /proc/meminfo
}

sysctl_int() {
  local v
  v=$(cat "/proc/sys/$1" 2> /dev/null || printf '0')
  nz "${v// /}"
}

bytes_human() {
  awk -v b="$(nz "$1")" 'BEGIN {
    split("B KiB MiB GiB TiB", u, " ");
    i = 1; while (b >= 1024 && i < 5) { b /= 1024; i++ }
    printf "%.1f %s", b, u[i]
  }'
}

F_SEV=() F_CODE=() F_MSG=() F_EV=() F_HINT=()
add_finding() {
  F_SEV+=("$1") F_CODE+=("$2") F_MSG+=("$3") F_EV+=("${4:-}") F_HINT+=("${5:-}")
}

# ---------------------------------------------------------------------------
# sample: iostat, pidstat and vmstat over the same window, in parallel
# ---------------------------------------------------------------------------

IOSTAT_JSON=$TMP/iostat.json
PIDSTAT_OUT=$TMP/pidstat.txt
VMSTAT_OUT=$TMP/vmstat.txt

LC_ALL=C iostat -x -y -d "$SAMPLE" 1 -o JSON > "$IOSTAT_JSON" 2> "$TMP/iostat.err" &
IOSTAT_PID=$!

if command -v pidstat > /dev/null 2>&1; then
  # One-second buckets over the whole window: a single SAMPLE-long bucket
  # never reports a writer that starts and exits inside it.
  LC_ALL=C pidstat -d 1 "$SAMPLE" > "$PIDSTAT_OUT" 2> "$TMP/pidstat.err" &
  PIDSTAT_PID=$!
else
  printf 'not installed\n' > "$PIDSTAT_OUT"
  PIDSTAT_PID=""
fi

LC_ALL=C vmstat "$SAMPLE" 1 > "$VMSTAT_OUT" 2> /dev/null &
VMSTAT_PID=$!

wait "$IOSTAT_PID" || die "iostat failed: $(head -n2 "$TMP/iostat.err")"
[[ -n $PIDSTAT_PID ]] && { wait "$PIDSTAT_PID" || true; }
wait "$VMSTAT_PID" || true

# PSI and dirty pages are point-in-time: read them at the end of the window.
PSI_SOME=$(psi_avg10 /proc/pressure/io some)
PSI_FULL=$(psi_avg10 /proc/pressure/io full)
PSI_CPU=$(psi_avg10 /proc/pressure/cpu some)
PSI_MEM=$(psi_avg10 /proc/pressure/memory some)

DIRTY_KB=$(nz "$(meminfo_kb Dirty)")
WRITEBACK_KB=$(nz "$(meminfo_kb Writeback)")
MEMTOTAL_KB=$(nz "$(meminfo_kb MemTotal)")
DIRTY_BYTES=$(sysctl_int vm/dirty_bytes)
DIRTY_RATIO=$(sysctl_int vm/dirty_ratio)
DIRTY_BG_BYTES=$(sysctl_int vm/dirty_background_bytes)
DIRTY_BG_RATIO=$(sysctl_int vm/dirty_background_ratio)
if ((DIRTY_BYTES > 0)); then
  DIRTY_LIMIT_KB=$((DIRTY_BYTES / 1024))
else
  DIRTY_LIMIT_KB=$(awk -v m="$MEMTOTAL_KB" -v r="$DIRTY_RATIO" 'BEGIN { printf "%.0f", m * r / 100 }')
fi
if ((DIRTY_BG_BYTES > 0)); then
  DIRTY_BG_LIMIT_KB=$((DIRTY_BG_BYTES / 1024))
else
  DIRTY_BG_LIMIT_KB=$(awk -v m="$MEMTOTAL_KB" -v r="$DIRTY_BG_RATIO" 'BEGIN { printf "%.0f", m * r / 100 }')
fi
DIRTY_PCT=$(pct "$DIRTY_KB" "$DIRTY_LIMIT_KB")

# vmstat: r b | swpd free buff cache | si so | bi bo | in cs | us sy id wa st
read -r VM_R VM_B VM_WA VM_BI VM_BO < <(
  awk 'NF >= 16 { line = $0 } END {
    if (line == "") { print "0 0 0 0 0"; exit }
    split(line, f, " ")
    print f[1], f[2], f[16], f[9], f[10]
  }' "$VMSTAT_OUT"
)

# ---------------------------------------------------------------------------
# per-device metrics
# ---------------------------------------------------------------------------

DEV_NAMES=() DEV_ROTA=() DEV_RS=() DEV_WS=() DEV_RKB=() DEV_WKB=()
DEV_RAWAIT=() DEV_WAWAIT=() DEV_AQSZ=() DEV_UTIL=()

while IFS=$'\t' read -r dev rs ws rkb wkb rawait wawait aqsz util; do
  [[ -n $dev ]] || continue
  rota=$(cat "/sys/block/$dev/queue/rotational" 2> /dev/null || printf 'x')
  DEV_NAMES+=("$dev")
  DEV_ROTA+=("$rota")
  DEV_RS+=("$rs") DEV_WS+=("$ws") DEV_RKB+=("$rkb") DEV_WKB+=("$wkb")
  DEV_RAWAIT+=("$rawait") DEV_WAWAIT+=("$wawait") DEV_AQSZ+=("$aqsz") DEV_UTIL+=("$util")
done < <(
  jq -r '
    .sysstat.hosts[0].statistics[-1].disk[]
    | select(.disk_device | test("^(loop|ram|zram|sr|fd|nbd)") | not)
    | [ .disk_device, .["r/s"], .["w/s"], .["rkB/s"], .["wkB/s"],
        .["r_await"], .["w_await"], .["aqu-sz"], .util ]
    | @tsv
  ' "$IOSTAT_JSON"
)

for i in "${!DEV_NAMES[@]}"; do
  dev=${DEV_NAMES[$i]}
  rota=${DEV_ROTA[$i]}
  if [[ $rota == 1 ]]; then
    warn=$AWAIT_WARN_HDD crit=$AWAIT_CRIT_HDD kind=hdd
  else
    warn=$AWAIT_WARN_SSD crit=$AWAIT_CRIT_SSD kind=ssd
  fi
  rawait=${DEV_RAWAIT[$i]} wawait=${DEV_WAWAIT[$i]}
  # A device that only reads never populates w_await, and vice versa; take the
  # busy direction, not the maximum of two zeros.
  await_eff=$rawait
  if ge "$wawait" "$rawait"; then await_eff=$wawait; fi
  if ge "$await_eff" "$crit"; then
    add_finding critical device_latency \
      "$dev: ${await_eff} ms average latency (${kind} threshold ${crit} ms)" \
      "r_await ${rawait} ms, w_await ${wawait} ms, aqu-sz ${DEV_AQSZ[$i]}, util ${DEV_UTIL[$i]}%" \
      "latency is the load metric; %util only says the queue was non-empty"
  elif ge "$await_eff" "$warn"; then
    add_finding warn device_latency \
      "$dev: ${await_eff} ms average latency (${kind} threshold ${warn} ms)" \
      "r_await ${rawait} ms, w_await ${wawait} ms, aqu-sz ${DEV_AQSZ[$i]}, util ${DEV_UTIL[$i]}%" \
      "check the top I/O consumers and the dirty-page pressure before blaming the disk"
  fi
  if ge "${DEV_AQSZ[$i]}" "$AQU_WARN" && lt "$await_eff" "$warn"; then
    add_finding info queue_depth \
      "$dev: queue depth ${DEV_AQSZ[$i]} with ${await_eff} ms latency" "" \
      "deep queue with low latency is normal parallelism (NVMe, RAID), not saturation"
  fi
  # The trap this script exists for: util pegged, latency fine.
  if ge "${DEV_UTIL[$i]}" 90 && lt "$await_eff" "$warn"; then
    add_finding info util_trap \
      "$dev: util ${DEV_UTIL[$i]}% but latency only ${await_eff} ms" "" \
      "%util=100 means 'at least one request in flight', not 'device saturated'"
  fi
done

# ---------------------------------------------------------------------------
# top I/O consumers
# ---------------------------------------------------------------------------

TOP_IO=()
if [[ -s $PIDSTAT_OUT ]] && ! grep -q 'not installed' "$PIDSTAT_OUT"; then
  while IFS=$'\t' read -r pid total rd wr delay cmd; do
    [[ -n $pid ]] || continue
    TOP_IO+=("${pid}|${total}|${rd}|${wr}|${delay}|${cmd}")
  done < <(
    awk -v window="$SAMPLE" '
      # Sum per-second buckets; the "Average:" block is skipped so that it is
      # not counted a second time.
      $1 ~ /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/ {
        if ($3 !~ /^[0-9]+$/ || $4 !~ /^[0-9.]+$/) next
        pid = $3; rd = $4 + 0; wr = $5 + 0; dly = $7 + 0
        cmd = $8; for (i = 9; i <= NF; i++) cmd = cmd " " $i
        TOT[pid] += rd + wr; RD[pid] += rd; WR[pid] += wr
        if (dly > DL[pid]) DL[pid] = dly
        CMD[pid] = cmd
      }
      END {
        for (p in TOT) printf "%s\t%.1f\t%.1f\t%.1f\t%.1f\t%s\n",
          p, TOT[p] / window, RD[p] / window, WR[p] / window, DL[p], CMD[p]
      }
    ' "$PIDSTAT_OUT" | sort -t$'\t' -k2,2nr | head -n "$TOP_N"
  )
  if [[ $EUID -ne 0 ]] && ((${#TOP_IO[@]} > 0)); then
    add_finding info process_io_blind \
      "per-process I/O is limited to your own processes (not root)" "" \
      "run as root for the full list; /proc/PID/io is not world-readable"
  fi
  if ((${#TOP_IO[@]} == 0)); then
    add_finding info process_io_idle "no per-process I/O in this window" "" \
      "nothing to attribute; the device numbers above are the whole story"
  fi
else
  add_finding info process_io_blind "pidstat not installed" "" \
    "install sysstat to attribute I/O to processes"
fi

# ---------------------------------------------------------------------------
# system pressure findings
# ---------------------------------------------------------------------------

if [[ -n $PSI_FULL ]]; then
  if ge "$PSI_FULL" "$PSI_CRIT"; then
    add_finding critical io_stall \
      "tasks stalled on I/O ${PSI_FULL}% of the time (full avg10)" \
      "some ${PSI_SOME}%, cpu ${PSI_CPU:-?}%, memory ${PSI_MEM:-?}%" \
      "PSI is the closest thing to 'users feel it'; compare with the device latency above"
  elif ge "$PSI_FULL" "$PSI_WARN"; then
    add_finding warn io_stall \
      "tasks stalled on I/O ${PSI_FULL}% of the time (full avg10)" \
      "some ${PSI_SOME}%, cpu ${PSI_CPU:-?}%, memory ${PSI_MEM:-?}%" \
      "still below the critical threshold; check whether it is periodic (backup, sync)"
  fi
fi

if [[ $DIRTY_PCT != n/a ]] && ge "$DIRTY_PCT" "$DIRTY_CRIT"; then
  add_finding warn dirty_pages \
    "dirty pages at ${DIRTY_PCT}% of the writeback limit (${DIRTY_KB} of ${DIRTY_LIMIT_KB} kB)" \
    "writeback ${WRITEBACK_KB} kB, vm.dirty_ratio ${DIRTY_RATIO}%, vm.dirty_background_ratio ${DIRTY_BG_RATIO}%" \
    "writers can block in balance_dirty_pages; the disk is a victim here, not the cause"
elif [[ $DIRTY_PCT != n/a ]] && ge "$DIRTY_PCT" "$DIRTY_WARN"; then
  add_finding info dirty_pages \
    "dirty pages at ${DIRTY_PCT}% of the writeback limit" "" \
    "watch the trend; fsync-heavy writers may be the real latency source"
fi

if ge "$VM_WA" 30; then
  add_finding info iowait \
    "vmstat iowait ${VM_WA}% (r=${VM_R}, b=${VM_B})" "" \
    "iowait is context, not a verdict; PSI io.full is the sharper number"
fi

# ---------------------------------------------------------------------------
# health and redundancy (root only for SMART/zpool)
# ---------------------------------------------------------------------------

if [[ $SMART_MODE == auto ]]; then
  if [[ $EUID -ne 0 ]]; then
    if command -v smartctl > /dev/null 2>&1; then
      add_finding info smart_blind "SMART is not readable without root" "" \
        "run as root to check media errors and reallocated sectors"
    fi
  elif command -v smartctl > /dev/null 2>&1 && command -v lsblk > /dev/null 2>&1; then
    while read -r disk; do
      [[ -n $disk ]] || continue
      out=$(smartctl -H -A "/dev/$disk" 2>&1 || true)
      [[ -n $out ]] || continue
      if grep -q 'overall-health self-assessment test result: FAILED' <<< "$out"; then
        add_finding critical smart_failed "$disk: SMART self-assessment FAILED" "" \
          "plan a replacement; check smartctl -a for the failing attribute"
      fi
      cw=$(awk -F': *' '/^Critical Warning:/ { print $2; exit }' <<< "$out")
      if [[ -n $cw && $cw =~ ^0x[0-9A-Fa-f]+$ ]] && ((cw != 0)); then
        add_finding warn smart_warning "$disk: NVMe critical warning $cw" "" \
          "smartctl -a $disk; nonzero warns about spare, temperature or reliability"
      fi
      mde=$(awk -F': *' '/^Media and Data Integrity Errors:/ { print $2; exit }' <<< "$out")
      if [[ -n $mde && $mde =~ ^[0-9]+$ ]] && ((mde > 0)); then
        add_finding warn media_errors "$disk: $mde media/data integrity error(s)" "" \
          "data may already be lost; verify backups and replace the device"
      fi
      realloc=$(awk -F' +' '/Reallocated_Sector_Ct/ { print $NF; exit }' <<< "$out")
      if [[ -n $realloc && $realloc =~ ^[0-9]+$ ]] && ((realloc > 0)); then
        add_finding warn reallocated_sectors "$disk: $realloc reallocated sector(s)" "" \
          "watch the growth rate; a few old remaps are not an emergency"
      fi
    done < <(lsblk -dno NAME,TYPE 2> /dev/null | awk '$2 == "disk" { print $1 }')
  fi
fi

if [[ -r /proc/mdstat ]] && ! grep -q 'unused devices: <none>' /proc/mdstat 2> /dev/null; then
  if grep -qE '\[[^]]*_' /proc/mdstat; then
    add_finding critical raid_degraded "md RAID is degraded" "$(grep -E '\[[^]]*_' /proc/mdstat | head -n2 | tr '\n' ';')" \
      "reads continue, redundancy does not; check the failed member"
  elif grep -qE 'recovery|resync|reshape' /proc/mdstat; then
    add_finding info raid_resync "md RAID is rebuilding" "$(grep -E 'recovery|resync|reshape' /proc/mdstat | head -n2 | tr '\n' ';')" \
      "rebuild traffic is a real load source; do not benchmark during it"
  fi
fi

if command -v zpool > /dev/null 2>&1; then
  if [[ $EUID -ne 0 ]]; then
    add_finding info zpool_blind "ZFS pool health is not readable without root" "" \
      "zpool status -x and zpool list -v need root on this system"
  else
    while IFS=$'\t' read -r pool health cap frag; do
      [[ -n $pool ]] || continue
      if [[ $health != ONLINE ]]; then
        add_finding critical zpool_health "$pool: pool health $health" "capacity ${cap}%, frag ${frag}%" \
          "zpool status -v $pool for the failing vdev"
      elif ge "$cap" 90; then
        add_finding warn zpool_capacity "$pool: ${cap}% allocated" "frag ${frag}%" \
          "ZFS performance degrades with capacity; add space before it hurts"
      fi
    done < <(zpool list -H -o name,health,cap,frag 2> /dev/null || true)
  fi
fi

# ---------------------------------------------------------------------------
# optional baseline: fio
# ---------------------------------------------------------------------------

FIO_ROWS=()
run_fio() {
  local dir=$1
  command -v fio > /dev/null 2>&1 || die "fio not found in PATH"
  [[ -d $dir && -w $dir ]] || die "fio directory is not writable: $dir"

  local size_bytes avail
  size_bytes=$(awk -v s="$FIO_SIZE" 'BEGIN {
    u = toupper(substr(s, length(s))); n = s; m = 1
    if (u == "K") { n = substr(s, 1, length(s) - 1); m = 1024 }
    else if (u == "M") { n = substr(s, 1, length(s) - 1); m = 1048576 }
    else if (u == "G") { n = substr(s, 1, length(s) - 1); m = 1073741824 }
    else if (u == "T") { n = substr(s, 1, length(s) - 1); m = 1099511627776 }
    if (n !~ /^[0-9]+$/) { print 0; exit }
    printf "%.0f", n * m
  }')
  ((size_bytes > 0)) || die "bad --fio-size: $FIO_SIZE (use N, NK, NM, NG, NT)"
  avail=$(df -P -B1 "$dir" | awk 'NR == 2 { print $4 }')
  ((size_bytes * 2 <= avail)) || die "not enough free space in $dir for ${FIO_SIZE} x2"

  FIO_FILE=$dir/.disk-triage-fio
  trap cleanup EXIT

  local name section out iops bw mean p99
  for spec in "randread:read" "randwrite:write"; do
    name=${spec%%:*} section=${spec##*:}
    if ! out=$(LC_ALL=C fio --name="$name" --filename="$FIO_FILE" --size="$FIO_SIZE" \
      --rw="$name" --bs=4k --iodepth=32 --ioengine=io_uring --direct=1 \
      --time_based --runtime="$FIO_RUNTIME" --group_reporting --output-format=json \
      2> "$TMP/fio.err"); then
      # io_uring is the default on modern fio; libaio is the portable fallback.
      out=$(LC_ALL=C fio --name="$name" --filename="$FIO_FILE" --size="$FIO_SIZE" \
        --rw="$name" --bs=4k --iodepth=32 --ioengine=libaio --direct=1 \
        --time_based --runtime="$FIO_RUNTIME" --group_reporting --output-format=json \
        2>> "$TMP/fio.err") || die "fio failed: $(head -n3 "$TMP/fio.err")"
    fi
    read -r iops bw mean p99 < <(
      jq -r --arg s "$section" '
        .jobs[0][$s]
        | [ (.iops // 0), (.bw_bytes // 0), (.clat_ns.mean // 0),
            (.clat_ns.percentile["99.000000"] // 0) ]
        | @tsv
      ' <<< "$out"
    )
    FIO_ROWS+=("${name}|${iops}|${bw}|${mean}|${p99}")
  done
}

if [[ -n $FIO_DIR ]]; then
  run_fio "$FIO_DIR"
fi

# ---------------------------------------------------------------------------
# findings roll-up
# ---------------------------------------------------------------------------

CRITICAL=0
WARN=0
for s in "${F_SEV[@]}"; do
  [[ $s == critical ]] && CRITICAL=$((CRITICAL + 1))
  [[ $s == warn ]] && WARN=$((WARN + 1))
done

EXIT_CODE=0
if ((CRITICAL > 0)); then
  EXIT_CODE=2
elif ((WARN > 0)); then
  EXIT_CODE=1
fi

json_esc() {
  local s=${1:-}
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

render_json() {
  local i sep
  printf '{\n'
  printf '  "tool": {"name": "disk-triage", "version": "%s"},\n' "$TOOL_VERSION"
  printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "sample_seconds": %s,\n' "$SAMPLE"
  printf '  "host": {"kernel": "%s", "nodename": "%s", "uid": %s},\n' \
    "$(json_esc "$(uname -r)")" "$(json_esc "$(uname -n)")" "$EUID"
  printf '  "metrics": {\n'
  printf '    "psi_io_some_avg10": "%s",\n' "${PSI_SOME:-n/a}"
  printf '    "psi_io_full_avg10": "%s",\n' "${PSI_FULL:-n/a}"
  printf '    "psi_cpu_some_avg10": "%s",\n' "${PSI_CPU:-n/a}"
  printf '    "psi_memory_some_avg10": "%s",\n' "${PSI_MEM:-n/a}"
  printf '    "dirty_kb": %s,\n' "$DIRTY_KB"
  printf '    "writeback_kb": %s,\n' "$WRITEBACK_KB"
  printf '    "dirty_limit_kb": %s,\n' "$DIRTY_LIMIT_KB"
  printf '    "dirty_background_kb": %s,\n' "$DIRTY_BG_LIMIT_KB"
  printf '    "dirty_pct": "%s",\n' "$DIRTY_PCT"
  printf '    "vmstat_r": %s,\n' "$VM_R"
  printf '    "vmstat_b": %s,\n' "$VM_B"
  printf '    "vmstat_wa": %s\n' "$VM_WA"
  printf '  },\n'
  printf '  "devices": ['
  sep=""
  for i in "${!DEV_NAMES[@]}"; do
    printf '%s\n    {"name": "%s", "rotational": "%s", "r_per_s": %s, "w_per_s": %s, "rkB_per_s": %s, "wkB_per_s": %s, "r_await_ms": %s, "w_await_ms": %s, "aqu_sz": %s, "util_pct": %s}' \
      "$sep" "${DEV_NAMES[$i]}" "${DEV_ROTA[$i]}" "$(nz "${DEV_RS[$i]}")" "$(nz "${DEV_WS[$i]}")" \
      "$(nz "${DEV_RKB[$i]}")" "$(nz "${DEV_WKB[$i]}")" "$(nz "${DEV_RAWAIT[$i]}")" "$(nz "${DEV_WAWAIT[$i]}")" \
      "$(nz "${DEV_AQSZ[$i]}")" "$(nz "${DEV_UTIL[$i]}")"
    sep=","
  done
  if ((${#DEV_NAMES[@]} > 0)); then printf '\n  '; fi
  printf '],\n'
  printf '  "top_io": ['
  sep=""
  for row in "${TOP_IO[@]}"; do
    IFS='|' read -r pid total rd wr delay cmd <<< "$row"
    printf '%s\n    {"pid": %s, "total_kb_per_s": %s, "read_kb_per_s": %s, "write_kb_per_s": %s, "iodelay": %s, "command": "%s"}' \
      "$sep" "$(nz "$pid")" "$(nz "$total")" "$(nz "$rd")" "$(nz "$wr")" "$(nz "$delay")" "$(json_esc "$cmd")"
    sep=","
  done
  if ((${#TOP_IO[@]} > 0)); then printf '\n  '; fi
  printf '],\n'
  printf '  "fio": ['
  sep=""
  for row in "${FIO_ROWS[@]}"; do
    IFS='|' read -r name iops bw mean p99 <<< "$row"
    printf '%s\n    {"job": "%s", "iops": %s, "bw_bytes": %s, "clat_mean_ns": %s, "clat_p99_ns": %s}' \
      "$sep" "$name" "$(nz "$iops")" "$(nz "$bw")" "$(nz "$mean")" "$(nz "$p99")"
    sep=","
  done
  if ((${#FIO_ROWS[@]} > 0)); then printf '\n  '; fi
  printf '],\n'
  printf '  "findings": ['
  sep=""
  for i in "${!F_SEV[@]}"; do
    printf '%s\n    {"severity": "%s", "code": "%s", "message": "%s", "evidence": "%s", "hint": "%s"}' \
      "$sep" "${F_SEV[$i]}" "${F_CODE[$i]}" \
      "$(json_esc "${F_MSG[$i]}")" "$(json_esc "${F_EV[$i]}")" "$(json_esc "${F_HINT[$i]}")"
    sep=","
  done
  if ((${#F_SEV[@]} > 0)); then printf '\n  '; fi
  printf '],\n'
  printf '  "exit_code": %s\n' "$EXIT_CODE"
  printf '}\n'
}

render_text() {
  printf 'host        %s, Linux %s, uid %s\n' "$(uname -n)" "$(uname -r)" "$EUID"
  printf 'window      %ss, one interval sample (iostat -y: no since-boot average)\n' "$SAMPLE"
  printf 'psi io      some %s%%, full %s%% (avg10; cpu %s%%, memory %s%%)\n' \
    "${PSI_SOME:-n/a}" "${PSI_FULL:-n/a}" "${PSI_CPU:-n/a}" "${PSI_MEM:-n/a}"
  if ((DIRTY_BYTES > 0)); then
    printf 'dirty       %s kB dirty, %s kB writeback; limit %s kB (%s%%), background %s kB (byte-based)\n' \
      "$DIRTY_KB" "$WRITEBACK_KB" "$DIRTY_LIMIT_KB" "$DIRTY_PCT" "$DIRTY_BG_LIMIT_KB"
  else
    printf 'dirty       %s kB dirty, %s kB writeback; limit %s kB (%s%%), dirty_ratio %s%%, background_ratio %s%%\n' \
      "$DIRTY_KB" "$WRITEBACK_KB" "$DIRTY_LIMIT_KB" "$DIRTY_PCT" "$DIRTY_RATIO" "$DIRTY_BG_RATIO"
  fi
  printf 'vmstat      r %s, b %s, wa %s%%, bi %s, bo %s\n\n' \
    "$VM_R" "$VM_B" "$VM_WA" "$VM_BI" "$VM_BO"

  printf 'devices\n'
  local i kind
  for i in "${!DEV_NAMES[@]}"; do
    kind='?'
    case ${DEV_ROTA[$i]} in 1) kind=hdd ;; 0) kind=ssd ;; esac
    printf '  %-10s %-3s r %6s/s w %6s/s  r_await %6s ms  w_await %6s ms  aqu-sz %6s  util %5s%%\n' \
      "${DEV_NAMES[$i]}" "$kind" "${DEV_RS[$i]}" "${DEV_WS[$i]}" \
      "${DEV_RAWAIT[$i]}" "${DEV_WAWAIT[$i]}" "${DEV_AQSZ[$i]}" "${DEV_UTIL[$i]}"
  done

  if ((${#TOP_IO[@]} > 0)); then
    printf '\ntop io\n'
    local row
    for row in "${TOP_IO[@]}"; do
      IFS='|' read -r pid total rd wr delay cmd <<< "$row"
      printf '  %8s kB/s total (r %s, w %s), iodelay %s  pid %s  %s\n' \
        "$total" "$rd" "$wr" "$delay" "$pid" "$cmd"
    done
  fi

  if ((${#FIO_ROWS[@]} > 0)); then
    printf '\nbaseline (fio, %s, %ss per job)\n' "$FIO_SIZE" "$FIO_RUNTIME"
    local row
    for row in "${FIO_ROWS[@]}"; do
      IFS='|' read -r name iops bw mean p99 <<< "$row"
      printf '  %-10s %8.0f IOPS  %s/s  clat mean %.2f ms  p99 %.2f ms\n' \
        "$name" "$(nz "$iops")" "$(bytes_human "$bw")" \
        "$(awk -v v="$(nz "$mean")" 'BEGIN { printf "%.2f", v / 1000000 }')" \
        "$(awk -v v="$(nz "$p99")" 'BEGIN { printf "%.2f", v / 1000000 }')"
    done
  fi

  printf '\n'
  if ((${#F_SEV[@]} == 0)); then
    printf 'no findings\n'
    return 0
  fi
  local sev
  for sev in critical warn info; do
    for i in "${!F_SEV[@]}"; do
      [[ ${F_SEV[$i]} == "$sev" ]] || continue
      printf '%-8s %s\n' "${F_SEV[$i]^^}" "${F_MSG[$i]}"
      [[ -n ${F_EV[$i]} ]] && printf '         evidence: %s\n' "${F_EV[$i]}"
      [[ -n ${F_HINT[$i]} ]] && printf '         next:     %s\n' "${F_HINT[$i]}"
    done
  done
  printf '\n%d critical, %d warning(s)\n' "$CRITICAL" "$WARN"
}

# Render into a file first: piping the report into head/less must not turn
# every truncated printf into "write error: Broken pipe" on stderr.
set +e
if [[ $FORMAT == json ]]; then
  render_json > "$TMP/report.json"
  cat "$TMP/report.json"
else
  render_text > "$TMP/report.txt"
  cat "$TMP/report.txt"
fi
set -e

exit "$EXIT_CODE"
