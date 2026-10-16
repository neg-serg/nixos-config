#!/usr/bin/env bash
# sysmon.sh - system monitor worker (pleamar helper; protocol: INTERFACES.md §7).
#
# Missing service for the system-monitor view: the scene spawns this worker
# while the view exists (spawn with an open stdin), subscribes to topics and
# kills it on close. The worker reads procfs/sysfs only (/proc/stat,
# /proc/meminfo, /proc/swaps, /proc/diskstats, one gpu_busy_percent and one
# hwmon CPU temperature input) and samples in one awk process per tick.
#
# Protocol (README.md has the full text):
#   handshake  {"ok":true,"worker":"sysmon","version":1,"topics":[sysmon,cpu,
#              mem,swap,disk,gpu,temp]}
#   commands   {"cmd":"subscribe","topic":"sysmon","interval_ms":1000}
#              {"cmd":"sample"} {"cmd":"set","interval_ms":500}
#              {"cmd":"unsubscribe","topic":"cpu"} {"cmd":"stop"}
#   samples    {"ok":true,"worker":"sysmon","topic":"sysmon","t":<ms>,
#              "data":{"ts":…,"cpu":{"percent":…},"mem":{…},"swap":{…},
#                      "disk":{…},"gpu":{…},"temp":{…}}}
#              A subtopic sample carries that subtopic's object as data.
#   errors     {"ok":false,"worker":"sysmon","err":"…","t":<ms>}
#
# `sysmon` is auto-subscribed at --interval-ms (1000 by default), so a scene
# that only reads lines still gets one full sample a second; `--once` prints
# the handshake plus one sample and exits. A closed stdin finishes the worker.
#
# Usage: sysmon.sh [--interval-ms N] [--once] [--io-max-kibps N]
#                  [--gpu-path PATH | --no-gpu] [--temp-path PATH | --no-temp]
#                  [--help]
#
# Exit: 0 when stdin closes or on stop; 1 when the worker cannot start.

set -euo pipefail

usage() {
  cat << 'EOF'
sysmon.sh - system monitor worker (JSON lines, INTERFACES.md §7)

Usage:
  sysmon.sh [options]

Options:
  --interval-ms N      default sample cadence for the `sysmon` topic,
                       100..60000 (default: 1000)
  --once               print the handshake and one sample, then exit
  --io-max-kibps N     disk I/O that counts as 100% (default: 512000)
  --gpu-path PATH      read gpu_busy_percent from PATH instead of discovering
  --no-gpu             report gpu as an error object without looking
  --temp-path PATH     read a millidegree temperature from PATH
  --no-temp            report temp as an error object without looking
  -h, --help           this text

Topics: sysmon (full sample), cpu, mem, swap, disk, gpu, temp.
Commands: subscribe, unsubscribe, set, sample, stop (one JSON object per
stdin line; every command is answered with an ack or an error line).

Exit status: 0 normal finish (stdin closed or stop); 1 cannot start.
EOF
}

WORKER=sysmon

die() {
  printf 'sysmon: error: %s\n' "$*" >&2
  exit 2
}

INTERVAL_MS=1000
ONCE=0
IO_MAX_KIBPS=512000
GPU_PATH=""
GPU_SET=0
TEMP_PATH=""
TEMP_SET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --interval-ms)
      [ $# -ge 2 ] || die "--interval-ms needs a value"
      INTERVAL_MS=$2
      shift 2
      ;;
    --once)
      ONCE=1
      shift
      ;;
    --io-max-kibps)
      [ $# -ge 2 ] || die "--io-max-kibps needs a value"
      IO_MAX_KIBPS=$2
      shift 2
      ;;
    --gpu-path)
      [ $# -ge 2 ] || die "--gpu-path needs a value"
      GPU_PATH=$2
      GPU_SET=1
      shift 2
      ;;
    --no-gpu)
      GPU_PATH=""
      GPU_SET=1
      shift
      ;;
    --temp-path)
      [ $# -ge 2 ] || die "--temp-path needs a value"
      TEMP_PATH=$2
      TEMP_SET=1
      shift 2
      ;;
    --no-temp)
      TEMP_PATH=""
      TEMP_SET=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "unknown option '$1' (see --help)"
      ;;
  esac
done

is_uint() {
  case "$1" in
    '' | *[!0-9]*) return 1 ;;
  esac
  return 0
}

is_uint "$INTERVAL_MS" || die "--interval-ms must be an integer (got '$INTERVAL_MS')"
[ "$INTERVAL_MS" -ge 100 ] && [ "$INTERVAL_MS" -le 60000 ] || die "--interval-ms must be 100..60000"
is_uint "$IO_MAX_KIBPS" && [ "$IO_MAX_KIBPS" -ge 1 ] || die "--io-max-kibps must be a positive integer"

# A worker that cannot start says so in the protocol shape and exits non-zero.
start_error() {
  printf '{"ok":false,"worker":"%s","err":"%s"}\n' "$WORKER" "$1"
  exit 1
}

if ! command -v jq > /dev/null 2>&1; then
  start_error "jq not installed"
fi
if ! command -v awk > /dev/null 2>&1; then
  start_error "awk not installed"
fi

NOW_MS=0
now_ms() {
  local t=$EPOCHREALTIME
  printf -v NOW_MS '%s' "$((10#${t%.*} * 1000 + 10#${t#*.} / 1000))"
}

json_err() {
  jq -cn --arg e "$1" '{ok:false,err:$e}'
}

sample_error() {
  now_ms
  jq -cn --arg w "$WORKER" --arg e "$1" --argjson t "$NOW_MS" '{ok:false,worker:$w,err:$e,t:$t}'
}

ack() {
  printf '{"ok":true,"ack":"%s"}\n' "$1"
}

# Largest-VRAM DRM card that exposes gpu_busy_percent (the QS discovery rule).
find_gpu_path() {
  local dir best="" best_vram=0 vram
  for dir in /sys/class/drm/card[0-9]*/device; do
    if [ ! -r "$dir/gpu_busy_percent" ]; then
      continue
    fi
    vram=0
    if [ -r "$dir/mem_info_vram_total" ]; then
      read -r vram < "$dir/mem_info_vram_total" || vram=0
    fi
    case "$vram" in
      '' | *[!0-9]*) vram=0 ;;
    esac
    if [ -z "$best" ] || [ "$vram" -gt "$best_vram" ]; then
      best="$dir/gpu_busy_percent"
      best_vram="$vram"
    fi
  done
  if [ -n "$best" ]; then
    printf '%s' "$best"
  fi
  return 0
}

# k10temp/coretemp/zenpower temp1_input, else thermal zone 0 (the QS order).
find_temp_path() {
  local dir name candidate
  for dir in /sys/class/hwmon/hwmon*; do
    [ -r "$dir/name" ] || continue
    read -r name < "$dir/name" || name=""
    case "$name" in
      k10temp | coretemp | zenpower)
        candidate="$dir/temp1_input"
        if [ -r "$candidate" ]; then
          printf '%s' "$candidate"
          return 0
        fi
        ;;
    esac
  done
  candidate=/sys/class/thermal/thermal_zone0/temp
  if [ -r "$candidate" ]; then
    printf '%s' "$candidate"
  fi
  return 0
}

if [ "$GPU_SET" -eq 0 ]; then
  GPU_PATH=$(find_gpu_path)
fi
if [ "$TEMP_SET" -eq 0 ]; then
  TEMP_PATH=$(find_temp_path)
fi

STATE_FILE=$(mktemp "${TMPDIR:-/tmp}/pleamar-sysmon.XXXXXX")

cleanup() {
  rm -f -- "$STATE_FILE"
}
trap cleanup EXIT
trap 'cleanup; exit 0' INT TERM

# One-shot sampler: reads the previous counters from the state file, prints the
# data object, saves the new counters. Non-zero on an unreadable /proc file.
read -r -d '' AWK_PROGRAM << 'AWK' || true
function read_first(path, line) {
  if ((getline line < path) <= 0) {
    close(path)
    return ""
  }
  close(path)
  return line
}

function to_number(s, t) {
  t = s
  sub(/^[ \t]+/, "", t)
  sub(/[^0-9.+-].*$/, "", t)
  if (t == "" || t !~ /^[+-]?[0-9]/) return ""
  return t + 0
}

function sample_cpu(line, n, f, i, v) {
  line = read_first("/proc/stat")
  if (line == "" || line !~ /^cpu /) return 0
  n = split(line, f, /[ \t]+/)
  cpu_total = 0
  cpu_idle = 0
  for (i = 2; i <= 9 && i <= n; i++) {
    v = f[i] + 0
    cpu_total += v
    if (i == 5 || i == 6) cpu_idle += v
  }
  return cpu_total > 0
}

function sample_mem(line, n, f) {
  mem_total_kb = -1
  mem_avail_kb = -1
  while ((getline line < "/proc/meminfo") > 0) {
    n = split(line, f, /[ \t]+/)
    if (n >= 2 && f[1] == "MemTotal:") mem_total_kb = f[2] + 0
    else if (n >= 2 && f[1] == "MemAvailable:") mem_avail_kb = f[2] + 0
  }
  close("/proc/meminfo")
  return mem_total_kb > 0 && mem_avail_kb >= 0
}

function sample_swap(line, n, f, first) {
  swap_total_kb = 0
  swap_used_kb = 0
  first = 1
  while ((getline line < "/proc/swaps") > 0) {
    if (first) {
      first = 0
      continue
    }
    n = split(line, f, /[ \t]+/)
    if (n >= 4) {
      swap_total_kb += f[3] + 0
      swap_used_kb += f[4] + 0
    }
  }
  close("/proc/swaps")
}

function sample_disk(line, n, f) {
  disk_read_sectors = 0
  disk_write_sectors = 0
  while ((getline line < "/proc/diskstats") > 0) {
    sub(/^[ \t]+/, "", line)
    n = split(line, f, /[ \t]+/)
    if (n >= 10 && f[3] ~ /^(sd[a-z]+|nvme[0-9]+n[0-9]+|vd[a-z]+)$/) {
      disk_read_sectors += f[6] + 0
      disk_write_sectors += f[10] + 0
    }
  }
  close("/proc/diskstats")
}

function sample_gpu(v) {
  gpu_err = ""
  gpu_pct = 0
  if (gpu_path == "") {
    gpu_err = "no readable /sys/class/drm/card*/device/gpu_busy_percent"
    return
  }
  v = to_number(read_first(gpu_path))
  if (v == "") {
    gpu_err = "cannot read " gpu_path
    return
  }
  gpu_pct = v < 0 ? 0 : v > 100 ? 100 : v
}

function sample_temp(v) {
  temp_err = ""
  temp_c = 0
  temp_pct = 0
  if (temp_path == "") {
    temp_err = "no hwmon k10temp/coretemp/zenpower temp1_input and no /sys/class/thermal/thermal_zone0/temp"
    return
  }
  v = to_number(read_first(temp_path))
  if (v == "") {
    temp_err = "cannot read " temp_path
    return
  }
  temp_c = v / 1000
  if (temp_c < 0) temp_c = 0
  temp_pct = (temp_c - 30) / 70 * 100
  if (temp_pct < 0) temp_pct = 0
  if (temp_pct > 100) temp_pct = 100
}

function json_escape(s) {
  gsub(/\\/, "\\\\", s)
  gsub(/"/, "\\\"", s)
  gsub(/\t/, "\\t", s)
  gsub(/\r/, "\\r", s)
  return s
}

function gpu_json() {
  if (gpu_err != "") return "{\"err\":\"" json_escape(gpu_err) "\"}"
  return sprintf("{\"percent\":%.1f}", gpu_pct)
}

function temp_json() {
  if (temp_err != "") return "{\"err\":\"" json_escape(temp_err) "\"}"
  return sprintf("{\"celsius\":%.1f,\"percent\":%.1f}", temp_c, temp_pct)
}

BEGIN {
  prev_total = -1
  prev_idle = -1
  prev_read = -1
  prev_write = -1
  if ((getline l1 < state) > 0) {
    n = split(l1, f, " ")
    if (n >= 2) {
      prev_total = f[1] + 0
      prev_idle = f[2] + 0
    }
  }
  if ((getline l2 < state) > 0) {
    n = split(l2, f, " ")
    if (n >= 2) {
      prev_read = f[1] + 0
      prev_write = f[2] + 0
    }
  }
  close(state)

  if (!sample_cpu()) {
    print "cannot read /proc/stat" > "/dev/stderr"
    exit 1
  }
  if (!sample_mem()) {
    print "cannot read /proc/meminfo" > "/dev/stderr"
    exit 1
  }
  sample_swap()
  sample_disk()

  if (prev_total < 0 || cpu_total < prev_total) {
    prev_total = cpu_total
    prev_idle = cpu_idle
  }
  if (prev_read < 0 || disk_read_sectors < prev_read) {
    prev_read = disk_read_sectors
    prev_write = disk_write_sectors
  }

  dt = dt_ms / 1000
  if (dt <= 0) dt = interval_ms / 1000

  d_total = cpu_total - prev_total
  d_idle = cpu_idle - prev_idle
  cpu_pct = d_total > 0 ? 100.0 * (d_total - d_idle) / d_total : 0.0
  if (cpu_pct < 0) cpu_pct = 0
  if (cpu_pct > 100) cpu_pct = 100

  mem_used_kb = mem_total_kb - mem_avail_kb
  if (mem_used_kb < 0) mem_used_kb = 0
  mem_pct = 100.0 * mem_used_kb / mem_total_kb

  swap_pct = swap_total_kb > 0 ? 100.0 * swap_used_kb / swap_total_kb : 0.0

  read_kibps = (disk_read_sectors - prev_read) * 0.5 / dt
  write_kibps = (disk_write_sectors - prev_write) * 0.5 / dt
  if (read_kibps < 0) read_kibps = 0
  if (write_kibps < 0) write_kibps = 0
  disk_pct = 100.0 * (read_kibps + write_kibps) / io_max
  if (disk_pct > 100) disk_pct = 100

  sample_gpu()
  sample_temp()

  fmt = "{\"ts\":%d,\"cpu\":{\"percent\":%.1f}," \
    " \"mem\":{\"used_gib\":%.2f,\"total_gib\":%.2f,\"percent\":%.1f}," \
    " \"swap\":{\"available\":%s,\"used_gib\":%.2f,\"total_gib\":%.2f,\"percent\":%.1f}," \
    " \"disk\":{\"read_kibps\":%.1f,\"write_kibps\":%.1f,\"percent\":%.1f}," \
    " \"gpu\":%s,\"temp\":%s}"
  printf(fmt, systime(), cpu_pct, \
    mem_used_kb / 1048576, mem_total_kb / 1048576, mem_pct, \
    (swap_total_kb > 0 ? "true" : "false"), swap_used_kb / 1048576, swap_total_kb / 1048576, swap_pct, \
    read_kibps, write_kibps, disk_pct, gpu_json(), temp_json())
  printf "\n"

  printf "%d %d\n%d %d\n", cpu_total, cpu_idle, disk_read_sectors, disk_write_sectors > state
}
AWK

# The first sample needs a baseline: read the counters once now, so the first
# emitted sample covers a real interval instead of a cold start.
awk -v state="$STATE_FILE" -v io_max="$IO_MAX_KIBPS" \
  -v gpu_path="$GPU_PATH" -v temp_path="$TEMP_PATH" \
  -v dt_ms="$INTERVAL_MS" -v interval_ms="$INTERVAL_MS" "$AWK_PROGRAM" > /dev/null 2>&1 || true

KNOWN_TOPICS="sysmon cpu mem swap disk gpu temp"
topic_known() {
  case " $KNOWN_TOPICS " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

declare -A SUB_INTERVAL=()
declare -A SUB_NEXT=()
now_ms
LAST_SAMPLE_MS=$NOW_MS

printf '{"ok":true,"worker":"%s","version":1,"topics":["sysmon","cpu","mem","swap","disk","gpu","temp"]}\n' "$WORKER"

# Auto-subscription: one full sample per --interval-ms even without commands.
SUB_INTERVAL[sysmon]=$INTERVAL_MS
SUB_NEXT[sysmon]=$((LAST_SAMPLE_MS + INTERVAL_MS))

emit_samples() {
  local topic due_topic now=$1 data d dt_ms
  local -a due=()
  for topic in "${!SUB_INTERVAL[@]}"; do
    if [ "${SUB_NEXT[$topic]}" -le "$now" ]; then
      due+=("$topic")
    fi
  done
  [ "${#due[@]}" -gt 0 ] || return 0

  dt_ms=1000
  if [ "$LAST_SAMPLE_MS" -gt 0 ]; then
    dt_ms=$((now - LAST_SAMPLE_MS))
  fi
  if ! data=$(awk -v state="$STATE_FILE" -v io_max="$IO_MAX_KIBPS" \
    -v gpu_path="$GPU_PATH" -v temp_path="$TEMP_PATH" \
    -v dt_ms="$dt_ms" -v interval_ms="$INTERVAL_MS" "$AWK_PROGRAM" 2> /dev/null); then
    sample_error "cannot read /proc/stat or /proc/meminfo"
    return 0
  fi
  LAST_SAMPLE_MS=$now
  for due_topic in "${due[@]}"; do
    SUB_NEXT[$due_topic]=$((now + SUB_INTERVAL[$due_topic]))
    if [ "$due_topic" = "sysmon" ]; then
      d=$data
    else
      d=$(printf '%s' "$data" | jq -c --arg t "$due_topic" '.[$t]')
    fi
    printf '{"ok":true,"worker":"%s","topic":"%s","t":%s,"data":%s}\n' "$WORKER" "$due_topic" "$now" "$d"
  done
  return 0
}

handle_command() {
  local line=$1 parts cmd topic interval now
  parts=$(printf '%s' "$line" | jq -r '[.cmd // "", .topic // "", ((.interval_ms // "") | tostring)] | join("|")' 2> /dev/null) || {
    json_err "bad command line"
    return 0
  }
  IFS='|' read -r cmd topic interval <<< "$parts"
  case "$cmd" in
    subscribe)
      if ! topic_known "$topic"; then
        json_err "unknown topic: $topic"
        return 0
      fi
      if [ -z "$interval" ]; then
        interval=${SUB_INTERVAL[$topic]:-$INTERVAL_MS}
      fi
      case "$interval" in
        '' | *[!0-9]*)
          json_err "interval_ms must be an integer"
          return 0
          ;;
      esac
      if [ "$interval" -lt 100 ] || [ "$interval" -gt 60000 ]; then
        json_err "interval_ms must be 100..60000"
        return 0
      fi
      SUB_INTERVAL[$topic]=$interval
      SUB_NEXT[$topic]=0
      ack subscribe
      ;;
    unsubscribe)
      if ! topic_known "$topic"; then
        json_err "unknown topic: $topic"
        return 0
      fi
      unset "SUB_INTERVAL[$topic]" "SUB_NEXT[$topic]" 2> /dev/null || true
      ack unsubscribe
      ;;
    set)
      if [ -z "$interval" ]; then
        json_err "set needs interval_ms"
        return 0
      fi
      case "$interval" in
        *[!0-9]*)
          json_err "interval_ms must be an integer"
          return 0
          ;;
      esac
      if [ "$interval" -lt 100 ] || [ "$interval" -gt 60000 ]; then
        json_err "interval_ms must be 100..60000"
        return 0
      fi
      for topic in "${!SUB_INTERVAL[@]}"; do
        SUB_INTERVAL[$topic]=$interval
      done
      ack set
      ;;
    sample)
      now_ms
      now=$NOW_MS
      for topic in "${!SUB_NEXT[@]}"; do
        SUB_NEXT[$topic]=0
      done
      ack sample
      emit_samples "$now"
      ;;
    stop)
      ack stop
      exit 0
      ;;
    *)
      json_err "unknown cmd: $cmd"
      ;;
  esac
  return 0
}

if [ "$ONCE" -eq 1 ]; then
  sleep "$(awk -v ms="$INTERVAL_MS" 'BEGIN { printf "%.3f", ms / 1000 }')"
  now_ms
  emit_samples "$NOW_MS"
  exit 0
fi

while :; do
  line=""
  if IFS= read -r -t 0.05 line; then
    if [ -n "$line" ]; then
      handle_command "$line" || true
    fi
  else
    rc=$?
    # End of stdin: the scene closed the command pipe; finish, never outlive it.
    if [ "$rc" -le 128 ]; then
      break
    fi
  fi
  now_ms
  emit_samples "$NOW_MS"
done
exit 0
