#!/usr/bin/env bash
set -euo pipefail

# Clean what can be cleaned without root:
# - Try vacuuming user journal (if permitted) to a minimal retention window
# - Truncate Hyprland runtime log
# - Truncate optional per-user app logs under XDG cache

keep_window="${1:-1d}"

if command -v journalctl > /dev/null 2>&1; then
  echo "== journalctl --user disk usage (before) =="
  journalctl --user --disk-usage || true
  if journalctl --user --vacuum-time="${keep_window}" > /dev/null 2>&1; then
    echo "Vacuumed user journal to keep ${keep_window}"
  else
    echo "Skipping vacuum: insufficient permission to remove system journal files (needs root)" >&2
  fi
  echo "== journalctl --user disk usage (after) =="
  journalctl --user --disk-usage || true
else
  echo "journalctl not available; skipping journal vacuum" >&2
fi

# Hyprland runtime log (safe to truncate)
if [[ -n "${XDG_RUNTIME_DIR:-}" && -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  hypr_log="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/hyprland.log"
  if [[ -f "${hypr_log}" ]]; then
    : > "${hypr_log}"
    echo "Truncated Hyprland log: ${hypr_log}"
  fi
fi

# Pyprland cache log (if present)
if [[ -n "${XDG_CACHE_HOME:-}" ]]; then
  for f in "${XDG_CACHE_HOME}/pyprland.log" "${XDG_CACHE_HOME}/pyprland/pyprland.log"; do
    if [[ -f "${f}" ]]; then
      : > "${f}"
      echo "Truncated ${f}"
    fi
  done
fi

echo "Done."
