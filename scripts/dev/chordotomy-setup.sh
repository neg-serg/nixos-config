#!/usr/bin/env bash
# Install chordotomy: beat-aligned chords, key changes and Roman numeral
# analysis from a recording.
#
# It is a Python CLI with a CPU-only model stack (lv-chordia for the chords,
# Beat This! for the beats), so it goes in as a uv tool: no nixpkgs package
# exists (checked 2026-11-07) and pulling librosa + torch into the store would
# buy nothing for a single-user CLI. The tool environment lives in
# ~/.local/share/uv/tools/chordotomy, the binary in ~/.local/bin.
#
# Two non-obvious pins:
#   UV_TORCH_BACKEND=cpu       without it the resolver takes the default torch
#                             wheel and drags ~2.6 GB of CUDA libraries onto a
#                             machine with no CUDA device.
#   SSL_CERT_FILE              the uv-managed python carries no CA bundle, so
#                             `chordotomy fetch-weights` fails against the Uni
#                             Linz server with CERTIFICATE_VERIFY_FAILED without
#                             it (the NixOS bundle path is the default here).
#
# `--engine dsp` needs no weights at all (librosa only); the default `auto`
# engine wants the lv-chordia wheel (in the tool) plus Beat This! weights
# (~81 MB, fetched once into ~/.cache/chordotomy and SHA-256 verified).
#
# Usage:
#   chordotomy-setup.sh [--python 3.12] [--check] [--dry-run] [--force]
#
#   --python VER   interpreter for the tool venv (default 3.12; uv fetches and
#                  keeps its own, which nix-collect-garbage cannot touch)
#   --check        report only; exit 1 when the tool or the weights are missing
#   --dry-run      print the commands, change nothing
#   --force        reinstall the tool even when `chordotomy --version` works
#
# Exit codes: 0 ok or already done, 1 --check found something missing,
# 2 bad usage or a failed step.
set -euo pipefail

PYTHON_PIN="3.12"
MODE="apply"
FORCE=""
WEIGHTS="${HOME}/.cache/chordotomy/beat_this-final0.ckpt"
SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-bundle.crt}"
UV_CACHE="${UV_CACHE_DIR:-/tmp/uv-cache}"
UV_HTTP_TIMEOUT="${UV_HTTP_TIMEOUT:-600}"
export SSL_CERT_FILE UV_HTTP_TIMEOUT

usage() {
  sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --python)
      PYTHON_PIN="${2:?--python needs a version}"
      shift 2
      ;;
    --check)
      MODE="check"
      shift
      ;;
    --dry-run)
      MODE="dry"
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h | --help) usage 0 ;;
    -*)
      echo "unknown option: $1" >&2
      usage 2
      ;;
    *)
      echo "unexpected argument: $1" >&2
      usage 2
      ;;
  esac
done

run() {
  if [[ "$MODE" == "dry" ]]; then
    printf '+ %s\n' "$*"
  else
    "$@"
  fi
}

tool_ok() {
  command -v chordotomy > /dev/null 2>&1 && chordotomy --version > /dev/null 2>&1
}

if [[ "$MODE" == "check" ]]; then
  status=0
  if tool_ok; then
    echo "tool: ok ($(command -v chordotomy), $(chordotomy --version | head -1))"
  else
    echo "tool: MISSING — run: just music-chordotomy-setup" >&2
    status=1
  fi
  if [[ -f "$WEIGHTS" ]]; then
    echo "weights: ok ($WEIGHTS)"
  else
    echo "weights: MISSING ($WEIGHTS) — run: just music-chordotomy-setup" >&2
    status=1
  fi
  exit "$status"
fi

if tool_ok && [[ -z "$FORCE" ]]; then
  echo "tool: already installed ($(command -v chordotomy))"
else
  if [[ -n "$FORCE" ]]; then
    run uv tool uninstall chordotomy
  fi
  run env UV_CACHE_DIR="$UV_CACHE" UV_TORCH_BACKEND=cpu \
    uv tool install --python "$PYTHON_PIN" "chordotomy[model]"
  if [[ "$MODE" != "dry" ]] && ! tool_ok; then
    echo "chordotomy did not land on PATH after install" >&2
    exit 2
  fi
fi

# Idempotent: the tool verifies the checkpoint and says "already there" when it
# is complete, so a re-run costs one stat.
run chordotomy fetch-weights

exit 0
