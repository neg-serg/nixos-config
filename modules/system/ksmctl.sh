#!/usr/bin/env bash
#
# ksmctl — switch the kernel's same-page merging (KSM) daemon and report what
# it actually merged.
#
# KSM merges anonymous pages only in ranges a process registered with
# madvise(MADV_MERGEABLE) (Documentation/admin-guide/mm/ksm.rst): VM and
# emulator runtimes register guest RAM, desktop applications register nothing,
# so the counters stay at zero for an ordinary workload. `run` enables the
# daemon for the duration of one command and restores the previous state on
# exit — the only way to scope a kernel-global switch.
#
# Writes go to $KSMCTL_SYSFS (default /sys/kernel/mm/ksm) and need root;
# `status` only reads. The switch is runtime-only: it does not survive a reboot.
set -euo pipefail

sysfs=${KSMCTL_SYSFS:-/sys/kernel/mm/ksm}

usage() {
  cat << 'EOF'
usage: ksmctl status
       ksmctl on  [--pages N] [--sleep MS] [--advisor MODE]
       ksmctl off
       ksmctl run [--pages N] [--sleep MS] [--advisor MODE] [--] COMMAND [ARG...]

status  daemon state and counters (no privileges needed)
on      start ksmd, optionally tuning the scan (root)
off     stop ksmd; already merged pages stay shared (root)
run     start ksmd for the duration of COMMAND, restore the previous state,
        then print how much was merged (root)

Expect 0 merged pages unless a workload registers memory with
madvise(MADV_MERGEABLE) — QEMU/KVM guests and some emulators do. `--advisor
scan-time` lets the kernel size pages_to_scan itself and cannot be combined
with --pages.
EOF
}

die() {
  printf 'ksmctl: %s\n' "$*" >&2
  exit 1
}

read_sys() {
  cat "$sysfs/$1" 2> /dev/null || printf '?'
}

write_sys() {
  if ! { printf '%s\n' "$2" > "$sysfs/$1"; } 2> /dev/null; then
    die "cannot write $sysfs/$1 — the kernel accepts it from root only (try sudo)"
  fi
}

# advisor_mode reports every choice with the active one in brackets:
# "[none] scan-time". Keep just the active name.
read_advisor() {
  local value
  value=$(read_sys advisor_mode) || true
  if [[ $value == *"["*"]"* ]]; then
    value=${value#*[}
    value=${value%%]*}
  fi
  printf '%s' "$value"
}

is_uint() {
  [[ $1 =~ ^[0-9]+$ ]]
}

human_of_pages() {
  awk -v pages="$1" 'BEGIN {
        kib = pages * 4
        if (kib < 1024) {
            printf "%.0f KiB", kib
        } else {
            printf "%.1f MiB", kib / 1024
        }
    }'
}

show_status() {
  local run pages sleep_ms advisor shared sharing unshared volatile skipped
  local scanned scans profit state rate saved cow

  run=$(read_sys run)
  pages=$(read_sys pages_to_scan)
  sleep_ms=$(read_sys sleep_millisecs)
  advisor=$(read_advisor)
  shared=$(read_sys pages_shared)
  sharing=$(read_sys pages_sharing)
  unshared=$(read_sys pages_unshared)
  volatile=$(read_sys pages_volatile)
  skipped=$(read_sys pages_skipped)
  scanned=$(read_sys pages_scanned)
  scans=$(read_sys full_scans)
  profit=$(read_sys general_profit)

  case "$run" in
    0) state="stopped" ;;
    1) state="enabled" ;;
    2) state="stopped (unmerge in progress)" ;;
    *) state="unknown" ;;
  esac

  rate="?"
  if is_uint "$pages" && is_uint "$sleep_ms" && [ "$sleep_ms" -gt 0 ]; then
    rate=$(
      awk -v p="$pages" -v s="$sleep_ms" \
        'BEGIN { printf "%.1f", (p * 1000 / s) * 4096 / 1048576 }'
    )
  fi

  saved="?"
  if is_uint "$sharing"; then
    saved=$(human_of_pages "$sharing")
  fi

  cow=$(awk '/^cow_ksm / { print $2 }' /proc/vmstat 2> /dev/null || true)

  printf 'daemon      %s (run=%s)\n' "$state" "$run"
  printf 'scan        pages_to_scan=%s sleep=%s ms (~%s MiB/s), advisor=%s\n' \
    "$pages" "$sleep_ms" "$rate" "$advisor"
  printf 'merged      %s shared pages / %s extra mappings -> saved %s\n' \
    "$shared" "$sharing" "$saved"
  printf 'candidates  %s unshared, %s volatile, %s skipped, smart_scan=%s\n' \
    "$unshared" "$volatile" "$skipped" "$(read_sys smart_scan)"
  printf 'scanned     %s pages in %s full scans\n' "$scanned" "$scans"
  if is_uint "$profit"; then
    printf 'profit      %s KiB (saved pages minus KSM rmap metadata)\n' \
      "$((profit / 1024))"
  fi
  printf 'cow_ksm     %s copies on write to a merged page\n' "${cow:-?}"

  if is_uint "$sharing" && [ "$sharing" -eq 0 ]; then
    printf 'note        nothing merged yet — no mergeable regions, or ksmd has not run\n'
  fi
}

pages=""
sleep_ms=""
advisor=""
remaining=()

parse_write_opts() {
  pages=""
  sleep_ms=""
  advisor=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --pages)
        [ $# -ge 2 ] || die "--pages needs a value"
        pages=$2
        shift 2
        ;;
      --sleep)
        [ $# -ge 2 ] || die "--sleep needs a value"
        sleep_ms=$2
        shift 2
        ;;
      --advisor)
        [ $# -ge 2 ] || die "--advisor needs a value"
        advisor=$2
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done
  remaining=("$@")
}

apply_write_opts() {
  if [ -n "$advisor" ] && [ -n "$pages" ]; then
    die "cannot combine --advisor with --pages (the advisor owns pages_to_scan)"
  fi
  if [ -n "$advisor" ]; then
    write_sys advisor_mode "$advisor"
  fi
  if [ -n "$pages" ]; then
    write_sys pages_to_scan "$pages"
  fi
  if [ -n "$sleep_ms" ]; then
    write_sys sleep_millisecs "$sleep_ms"
  fi
}

do_on() {
  apply_write_opts
  write_sys run 1
  printf 'ksmctl: KSM enabled (run=1); stays on until "ksmctl off" or a reboot\n'
}

do_off() {
  write_sys run 0
  printf 'ksmctl: KSM stopped (run=0); pages merged so far stay shared\n'
}

do_run() {
  local prev_run before_sharing before_scanned after_sharing after_scanned delta rc
  local restored=0

  prev_run=$(read_sys run)
  before_sharing=$(read_sys pages_sharing)
  before_scanned=$(read_sys pages_scanned)

  restore() {
    [ "$restored" -eq 1 ] && return 0
    { printf '%s\n' "$prev_run" > "$sysfs/run"; } 2> /dev/null || true
    restored=1
  }
  trap restore EXIT
  trap 'restore; exit 130' INT
  trap 'restore; exit 143' TERM

  apply_write_opts
  write_sys run 1

  set +e
  "${remaining[@]}"
  rc=$?
  set -e

  restore
  trap - EXIT INT TERM

  after_sharing=$(read_sys pages_sharing)
  after_scanned=$(read_sys pages_scanned)
  printf 'ksmctl: KSM restored to run=%s\n' "$prev_run"
  if is_uint "$before_sharing" && is_uint "$after_sharing"; then
    delta=$((after_sharing - before_sharing))
    printf 'ksmctl: extra mappings %s -> %s (%+d pages = %s merged while it ran)\n' \
      "$before_sharing" "$after_sharing" "$delta" "$(human_of_pages "$delta")"
    if [ "$delta" -eq 0 ]; then
      printf 'ksmctl: nothing merged while it ran — no mergeable memory or no duplicates\n'
    fi
  fi
  if is_uint "$before_scanned" && is_uint "$after_scanned"; then
    printf 'ksmctl: pages scanned %s -> %s (+%d)\n' \
      "$before_scanned" "$after_scanned" "$((after_scanned - before_scanned))"
  fi
  exit "$rc"
}

main() {
  local cmd=${1:-status}
  if [ $# -gt 0 ]; then
    shift
  fi

  case "$cmd" in
    status)
      [ $# -eq 0 ] || die "status takes no arguments"
      show_status
      ;;
    on)
      parse_write_opts "$@"
      [ ${#remaining[@]} -eq 0 ] || die "on: unexpected argument: ${remaining[0]}"
      do_on
      ;;
    off)
      [ $# -eq 0 ] || die "off takes no arguments"
      do_off
      ;;
    run)
      parse_write_opts "$@"
      [ ${#remaining[@]} -gt 0 ] || die "run: needs a command (ksmctl run -- CMD...)"
      do_run
      ;;
    -h | --help | help)
      usage
      ;;
    *)
      usage >&2
      die "unknown subcommand: $cmd"
      ;;
  esac
}

main "$@"
