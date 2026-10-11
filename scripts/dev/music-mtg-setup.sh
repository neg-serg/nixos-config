#!/usr/bin/env bash
# Set up the trained MTG/Essentia tagger: a dedicated venv with
# essentia-tensorflow plus the model files that music-mtg-tags needs.
#
# Why a separate venv: venv-analysis carries a plain essentia build without the
# TensorflowPredict* classes, and swapping it there would touch the other
# music-AI tools. Nothing else is modified, no sudo, no system python.
#
# Usage:
#   music-mtg-setup.sh [--venv DIR] [--models DIR] [--check] [--dry-run] [--force]
#
#   --venv DIR    venv to create/populate (default /zero/ai/music-ai/venv-mtg,
#                 or $MUSIC_MTG_VENV)
#   --models DIR  model directory (default /zero/ai/music-ai/mtg-models, or
#                 $MUSIC_MTG_MODELS)
#   --set core|all  model set to fetch (default core: genre/mood/instrument)
#   --check       report only; exit 1 when the venv or the models are missing
#   --dry-run     print the commands, change nothing
#   --force       reinstall the wheel even when the import already works
#
# Exit codes: 0 ok or already done, 1 --check found something missing,
# 2 bad usage or a failed step.
set -euo pipefail

VENV="${MUSIC_MTG_VENV:-/zero/ai/music-ai/venv-mtg}"
MODELS="${MUSIC_MTG_MODELS:-/zero/ai/music-ai/mtg-models}"
MODEL_SET="core"
MODE="apply"
FORCE=""
# Pinned by scripts/dev/music-mtg-models.sh's sibling work: this is the build
# whose wheel ships the TensorflowPredictEffnetDiscogs/TensorflowPredict2D
# classes for python 3.12 (numpy 2.5 works, no numpy<2 pin).
ESSENTIA_PIN="essentia-tensorflow==2.1b6.dev1389"
UV_CACHE="${UV_CACHE_DIR:-/tmp/uv-cache}"

usage() {
  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --venv)
      VENV="${2:?--venv needs a directory}"
      shift 2
      ;;
    --models)
      MODELS="${2:?--models needs a directory}"
      shift 2
      ;;
    --set)
      MODEL_SET="${2:?--set needs core or all}"
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
      FORCE="--reinstall-package essentia-tensorflow"
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

case "$MODEL_SET" in
  core | all) ;;
  *)
    echo "--set must be core or all, got '$MODEL_SET'" >&2
    exit 2
    ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
MODELS_SCRIPT="$REPO_ROOT/scripts/dev/music-mtg-models.sh"
PY="$VENV/bin/python"

find_python() {
  local candidate
  for candidate in "$HOME/.local/bin/python3.12" "$(command -v python3.12 || true)" python3; do
    [[ -n "$candidate" ]] || continue
    if command -v "$candidate" > /dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

venv_ready() {
  [[ -x "$PY" ]] || return 1
  "$PY" -c 'import essentia.standard as es; es.TensorflowPredictEffnetDiscogs' > /dev/null 2>&1
}

echo "venv:   $VENV"
echo "models: $MODELS ($MODEL_SET)"

if [[ "$MODE" == "check" ]]; then
  status=0
  if venv_ready; then
    echo "venv: ok ($("$PY" -c 'import essentia; print(essentia.__version__)' 2> /dev/null || echo '?'))"
  else
    echo "venv: missing or without essentia-tensorflow ($ESSENTIA_PIN)" >&2
    status=1
  fi
  if bash "$MODELS_SCRIPT" --dir "$MODELS" --set "$MODEL_SET" --check; then
    :
  else
    status=1
  fi
  exit "$status"
fi

if [[ "$MODE" == "dry" ]]; then
  echo "dry run: would create $VENV with $(find_python || echo '<no python3.12 found>')"
  echo "dry run: would run: $PY -m pip install $ESSENTIA_PIN"
  echo "dry run: would run: bash $MODELS_SCRIPT --dir $MODELS --set $MODEL_SET"
  exit 0
fi

if venv_ready && [[ -z "$FORCE" ]]; then
  echo "venv: already has essentia-tensorflow — nothing to install (--force to redo)"
else
  python_bin="$(find_python)" || {
    echo "no python3.12 found; install one or pass a working PATH" >&2
    exit 2
  }
  if command -v uv > /dev/null 2>&1; then
    [[ -x "$PY" ]] || UV_CACHE_DIR="$UV_CACHE" uv venv --python "$python_bin" "$VENV"
    UV_CACHE_DIR="$UV_CACHE" uv pip install --python "$PY" $FORCE "$ESSENTIA_PIN"
  else
    echo "uv not found; falling back to python -m venv + pip" >&2
    [[ -x "$PY" ]] || "$python_bin" -m venv "$VENV"
    "$PY" -m pip install --upgrade pip
    "$PY" -m pip install $FORCE "$ESSENTIA_PIN"
  fi
  venv_ready || {
    echo "essentia-tensorflow did not import after install" >&2
    exit 2
  }
  echo "venv: ok"
fi

bash "$MODELS_SCRIPT" --dir "$MODELS" --set "$MODEL_SET"
echo
echo "next: music-mtg-tags --check && music-mtg-tags --set core TRACK.flac"
