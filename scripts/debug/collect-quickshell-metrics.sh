#!/usr/bin/env bash
set -euo pipefail

# Collect CPU/memory/IO/network snapshots for a running quickshell process.
# Optional perf/strace/GPU samplers can be enabled via flags.

usage() {
  cat <<'EOF'
collect-quickshell-metrics: capture diagnostics for quickshell resource usage

Usage:
  collect-quickshell-metrics.sh [--pid PID] [--duration N] [--perf] [--strace] [--gpu]

Options:
  --pid PID      target PID (default: auto-detect newest quickshell)
  --duration N   seconds for perf/strace/GPU samplers (default: 15)
  --perf         run perf record/report (writes perf.data beside log)
  --strace       run strace -cf summary for the target PID
  --gpu          sample GPU load (nvidia-smi dmon | intel_gpu_top | radeontop)
  -h, --help     show this help

Outputs:
  - Log: /tmp/quickshell-metrics-<timestamp>.log
  - perf data (if --perf): /tmp/quickshell-perf-<timestamp>.data
  - strace summary (if --strace): /tmp/quickshell-strace-<timestamp>.txt
  - GPU dump (if --gpu): /tmp/quickshell-gpu-<timestamp>.log (or JSON when intel_gpu_top)
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }
log() { printf '\n=== %s ===\n' "$1"; }

duration=15
pid=""
do_perf=0
do_strace=0
do_gpu=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pid) pid="$2"; shift 2 ;;
    --duration) duration="$2"; shift 2 ;;
    --perf) do_perf=1; shift ;;
    --strace) do_strace=1; shift ;;
    --gpu) do_gpu=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$pid" ]]; then
  if have pgrep; then
    pid=$(pgrep -xo quickshell || true)
    [[ -z "$pid" ]] && pid=$(pgrep -fo quickshell || true)
  fi
fi

if [[ -z "$pid" ]]; then
  echo "error: quickshell PID not found (pass --pid)" >&2
  exit 1
fi

ts=$(date +%Y%m%d-%H%M%S)
LOG="/tmp/quickshell-metrics-${ts}.log"
PERF_DATA="/tmp/quickshell-perf-${ts}.data"
STRACE_OUT="/tmp/quickshell-strace-${ts}.txt"
GPU_OUT="/tmp/quickshell-gpu-${ts}.log"
GPU_JSON="/tmp/quickshell-gpu-${ts}.json"

exec >"$LOG" 2>&1

log "meta"
echo "timestamp: $(date -Iseconds)"
echo "pid: $pid"
echo "duration: ${duration}s"
echo "host: $(hostname)"
echo "user: $(id -un) ($(id -u))"
echo "kernel: $(uname -srmo)"

if [[ -r /proc/sys/kernel/perf_event_paranoid ]]; then
  echo "perf_event_paranoid: $(< /proc/sys/kernel/perf_event_paranoid)"
fi

log "command"
readlink -f "/proc/$pid/exe" || true
tr '\0' ' ' < "/proc/$pid/cmdline" || true

log "ps"
ps -p "$pid" -o pid,ppid,psr,pri,ni,stat,%cpu,%mem,rss,vsz,etimes,cmd || true
ps -Tp "$pid" -o pid,psr,pri,ni,stat,%cpu,%mem,comm || true

log "top snapshot"
COLUMNS=200 top -b -n 1 -p "$pid" || true

log "cgroup"
cat "/proc/$pid/cgroup" || true

log "proc status"
cat "/proc/$pid/status" || true

log "limits"
cat "/proc/$pid/limits" || true

log "sched"
cat "/proc/$pid/sched" || true

log "smaps_rollup"
cat "/proc/$pid/smaps_rollup" || true

log "io"
cat "/proc/$pid/io" || true

log "numa"
if have numastat; then numastat -p "$pid" || true; fi

log "open files"
find "/proc/$pid/fd" -maxdepth 1 -printf '%f -> %l\n' 2>/dev/null | head -n 200 || true
if have lsof; then
  fd_count=$(lsof -p "$pid" 2>/dev/null | wc -l || true)
  echo "fd count: ${fd_count:-unknown}"
  lsof -p "$pid" 2>/dev/null | head -n 200 || true
fi

log "pmap"
if have pmap; then pmap -x "$pid" || true; fi

log "network"
ss -tpn | grep "$pid" || true

log "journal (user quickshell)"
journalctl --user --no-pager -t quickshell -n 200 || true

if [[ $do_perf -eq 1 ]]; then
  log "perf record"
  if have perf; then
    perf record -F 99 -g -p "$pid" --output "$PERF_DATA" -- sleep "$duration" || true
    ls -lh "$PERF_DATA" || true
    log "perf report (truncated)"
    perf report --stdio --input "$PERF_DATA" --no-children --percent-limit 0.5 --max-stack 8 --sort dso,symbol | head -n 200 || true
  else
    echo "perf not found; skip"
  fi
fi

if [[ $do_strace -eq 1 ]]; then
  log "strace -cf"
  if have strace && have timeout; then
    timeout --kill-after=2 "$duration" strace -cf -p "$pid" -s 128 -o "$STRACE_OUT" || true
    cat "$STRACE_OUT" || true
  else
    echo "strace or timeout missing; skip"
  fi
fi

if [[ $do_gpu -eq 1 ]]; then
  log "gpu sampler"
  if have nvidia-smi; then
    nvidia-smi dmon -s pucvmet -d 1 -c "$duration" || true
  elif have intel_gpu_top; then
    timeout --kill-after=2 "$duration" intel_gpu_top -J -s 100 -o "$GPU_JSON" || true
    echo "intel_gpu_top JSON: $GPU_JSON"
  elif have radeontop; then
    timeout --kill-after=2 "$duration" radeontop -d "$GPU_OUT" -i 1 -l "$duration" || true
    echo "radeontop log: $GPU_OUT"
  else
    echo "no GPU sampler found (nvidia-smi/intel_gpu_top/radeontop)"
  fi
fi

log "done"
echo "log saved to: $LOG"
if [[ $do_perf -eq 1 ]]; then echo "perf data: $PERF_DATA"; fi
if [[ $do_strace -eq 1 ]]; then echo "strace summary: $STRACE_OUT"; fi
if [[ $do_gpu -eq 1 && -f "$GPU_OUT" ]]; then echo "gpu dump: $GPU_OUT"; fi
if [[ $do_gpu -eq 1 && -f "$GPU_JSON" ]]; then echo "gpu dump: $GPU_JSON"; fi
