#!/bin/sh
# Fake khal for tests/parity.sh: logs its argv and answers from the
# environment. Copied next to the other tools on PATH by the harness.
#
#   FAKE_KHAL_MODE    ok | fail | retry | critical-first
#   FAKE_KHAL_TEXT    the lines printed on success
#   FAKE_KHAL_STDERR  the first stderr line of a `fail`
#   FAKE_KHAL_CODE    the exit code of a `fail` (default 3)
#
# $4 is the first date argument (khal list --format FORMAT FIRST LAST).
printf '%s\n' "$*" >> "${FAKE_KHAL_LOG:-/dev/null}"
mode=${FAKE_KHAL_MODE:-ok}
if [ "$mode" = fail ]; then
  printf '%s\n' "${FAKE_KHAL_STDERR:-}" >&2
  exit "${FAKE_KHAL_CODE:-3}"
fi
if [ "$mode" = retry ]; then
  case "$4" in
    *.*.*) printf '%s\n' "${FAKE_KHAL_TEXT:-}" ;;
    *)
      printf 'critical: cannot parse\n' >&2
      exit 1
      ;;
  esac
  exit 0
fi
if [ "$mode" = critical-first ]; then
  case "$4" in
    *.*.*) printf '%s\n' "${FAKE_KHAL_TEXT:-}" ;;
    *)
      printf 'critical: warning\n' >&2
      printf 'discarded\n'
      exit 0
      ;;
  esac
  exit 0
fi
printf '%s\n' "${FAKE_KHAL_TEXT:-}"
