#!/usr/bin/env bash
# Set up MOSS-Music-8B (music understanding): the Python venv the
# `moss-music` wrapper runs on, and the bf16 weights it loads.
#
# Why a venv of its own: the model is custom transformers code pinned to
# transformers 4.57.1 (its modeling file imports Qwen3Model and
# WhisperEncoderLayer from that version), while the shared venv-analysis
# carries the newer transformers the MERT/CLAP/MTG stack needs. They cannot
# share site-packages.
#
# There is no llama.cpp or audio.cpp path for this model (checked 2026-11-07:
# mtmd audio covers MiMo-Audio and Muse-Spark-Audio only; audio.cpp has the
# MOSS TTS/transcribe families but no music-understanding family). The
# reference PyTorch implementation is the only local runtime, so the weights
# stay bf16: 18.1 GiB per variant against a 16 GB card means CPU inference.
#
# Usage:
#   moss-music-setup.sh [--venv DIR] [--models DIR] [--set instruct|thinking|both]
#                       [--check] [--dry-run] [--force]
#
#   --venv DIR     venv to create/populate (default /zero/ai/music-ai/venv-moss,
#                  or $MOSS_MUSIC_VENV)
#   --models DIR   weights root (default /zero/ai/music-ai/moss-music, or
#                  $MOSS_MUSIC_BASE); each variant gets its own subdirectory
#   --set NAME     which weight directories to fetch (default instruct)
#   --check        report only; exit 1 when the venv or the weights are missing
#   --dry-run      print the commands, change nothing
#   --force        recreate the venv even when the imports already work
#
# Exit codes: 0 ok or already done, 1 --check found something missing,
# 2 bad usage or a failed step.
#
# The download honors HTTPS_PROXY from the environment. On this link going
# direct is ~3x faster (measured 2026-11-07: 5.5 vs 1.9 MB/s per connection),
# so `env -u HTTPS_PROXY -u https_proxy just music-moss-models` is the quick
# path; the script resumes (`curl -C -`), so an interrupted run costs nothing.
set -euo pipefail

VENV="${MOSS_MUSIC_VENV:-/zero/ai/music-ai/venv-moss}"
MODELS="${MOSS_MUSIC_BASE:-/zero/ai/music-ai/moss-music}"
MODEL_SET="instruct"
ONLY="all"
MODE="apply"
FORCE=""
# Pinned to what the model card asks for: torch 2.9.1 is the +cu128 runtime the
# weights were exported with (the CPU wheel is bit-identical for inference) and
# 4.57.1 is the transformers the modeling code imports from.
# +cpu on purpose: `torch==2.9.1` resolves to the default wheel, which pulls
# ~3 GB of CUDA libraries onto a machine with no CUDA device.
TORCH_PIN="torch==2.9.1+cpu"
TRANSFORMERS_PIN="transformers==4.57.1"
UV_CACHE="${UV_CACHE_DIR:-/tmp/uv-cache}"
# The uv-managed interpreter survives nix-collect-garbage; a venv built on a
# store python loses bin/python to GC (scripts/dev/fix-music-venvs.sh exists
# because of exactly that). `uv venv --python 3.12` picks the managed 3.12; an
# explicit path wins when $MOSS_MUSIC_PYTHON is set.
PYTHON_PIN="${MOSS_MUSIC_PYTHON:-3.12}"
HF_REPO_INSTRUCT="OpenMOSS-Team/MOSS-Music-8B-Instruct"
HF_REPO_THINKING="OpenMOSS-Team/MOSS-Music-8B-Thinking"

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
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
      MODEL_SET="${2:?--set needs a value}"
      shift 2
      ;;
    --only)
      ONLY="${2:?--only needs venv, models or all}"
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

case "$MODEL_SET" in
  instruct | thinking | both) ;;
  *)
    echo "--set must be instruct, thinking or both" >&2
    exit 2
    ;;
esac

run() {
  if [[ "$MODE" == "dry" ]]; then
    printf '+ %s\n' "$*"
  else
    "$@"
  fi
}

venv_ok() {
  "$VENV/bin/python" - << 'PY' > /dev/null 2>&1
import torch, torchaudio, transformers, librosa, soundfile  # noqa: F401
import sentencepiece, google.protobuf  # noqa: F401  (tokenizer, chat template)
assert transformers.__version__.startswith("4.57.")
PY
}

# --- venv -------------------------------------------------------------------

want_venv=1
want_models=1
case "$ONLY" in
  venv) want_models=0 ;;
  models) want_venv=0 ;;
  all) ;;
  *)
    echo "--only must be venv, models or all" >&2
    exit 2
    ;;
esac

if [[ "$want_venv" == 1 ]]; then

  if [[ "$MODE" == "check" ]]; then
    if venv_ok; then
      echo "venv: ok ($VENV)"
    else
      echo "venv: MISSING or broken ($VENV) — run: just music-moss-venv" >&2
      exit 1
    fi
  elif venv_ok && [[ -z "$FORCE" ]]; then
    echo "venv: already set up ($VENV)"
  else
    if [[ -n "$FORCE" && -d "$VENV" ]]; then
      run rm -rf -- "$VENV"
    fi
    run uv venv --python "$PYTHON_PIN" "$VENV"
    # Two steps on purpose: with both indexes in one command the resolver takes
    # the default (CUDA) torch from PyPI, so torch is pinned to the CPU index
    # alone first and only the pure-Python packages come from PyPI.
    run env UV_CACHE_DIR="$UV_CACHE" uv pip install --python "$VENV/bin/python" \
      --index-url https://download.pytorch.org/whl/cpu "$TORCH_PIN" "torchaudio==2.9.1+cpu"
    run env UV_CACHE_DIR="$UV_CACHE" uv pip install --python "$VENV/bin/python" \
      "$TRANSFORMERS_PIN" "librosa>=1.0" "soundfile>=0.13" accelerate \
      sentencepiece protobuf
    if [[ "$MODE" != "dry" ]]; then
      venv_ok || {
        echo "venv import check failed after install" >&2
        exit 2
      }
      echo "venv: ok ($VENV)"
    fi
  fi

fi

# --- weights ----------------------------------------------------------------

# Everything the reference loader needs: config + custom code + tokenizer +
# processor + shards. The README/asset files are skipped; they are not inputs.
# "file size" lines for one repo, READMEs and assets filtered out.
remote_listing() {
  curl -fsSL "https://huggingface.co/api/models/$1?blobs=true" \
    | jq -r '.siblings[]
      | select(.rfilename | test("^(assets/|\\.gitattributes|README)") | not)
      | "\(.rfilename) \(.size // 0)"'
}

# Everything the reference loader needs: config + custom code + tokenizer +
# processor + shards.
download_repo() {
  local repo="$1" dest="$2"
  local base="https://huggingface.co/$repo/resolve/main"

  if [[ "$MODE" == "check" ]]; then
    local listing
    listing=$(remote_listing "$repo" || true)
    if [[ -z "$listing" ]]; then
      echo "weights: present, UNVERIFIED (offline) ($dest)"
      return 0
    fi
    local missing=0
    while read -r file want; do
      local have=0
      [[ -f "$dest/$file" ]] && have=$(stat -c %s "$dest/$file")
      if [[ "$want" -gt 0 && "$have" -ne "$want" ]]; then
        echo "weights: INCOMPLETE $dest/$file ($have of $want bytes)" >&2
        missing=1
      fi
    done <<< "$listing"
    if [[ "$missing" -ne 0 ]]; then
      echo "weights: run: just music-moss-models" >&2
      return 1
    fi
    echo "weights: ok ($dest)"
    return 0
  fi

  run mkdir -p "$dest"
  # Sizes come with the listing, so a finished file is skipped instead of being
  # asked to resume into a 416 (curl -C - on an already complete file fails and
  # leaves the run stuck, which is what happened on the first attempt).
  local listing
  listing=$(remote_listing "$repo" || true)
  if [[ -z "$listing" ]]; then
    echo "could not list $repo" >&2
    return 2
  fi
  if [[ "$MODE" == "dry" ]]; then
    printf '+ curl -fSL -C - %s/<file> into %s (%s files)\n' "$base" "$dest" \
      "$(wc -l <<< "$listing")"
    return 0
  fi
  # 4 connections: HF throttles a single one to ~5.5 MB/s on this link, and the
  # whole set is 18.1 GiB. --speed-limit/--speed-time abort a connection that
  # goes quiet instead of hanging the whole run.
  # The listing line carries "file size" (names have no spaces); split it here
  # rather than with `set --`, which clobbers the positional parameters that
  # carry the destination directory and the base URL.
  printf '%s\n' "$listing" | xargs -P 4 -I{} sh -c '
    file="${1%% *}"; want="${1##* }"; dir="$2"; url="$3"
    have=0
    [ -f "$dir/$file" ] && have=$(stat -c %s "$dir/$file")
    if [ "$want" -gt 0 ] && [ "$have" -eq "$want" ]; then
      exit 0
    fi
    mkdir -p "$dir/$(dirname "$file")"
    curl -fSL -C - --retry 8 --retry-all-errors --retry-delay 3 \
      --connect-timeout 30 --speed-limit 4096 --speed-time 30 \
      -o "$dir/$file" "$url/$file"
  ' _ {} "$dest" "$base" || {
    echo "download failed (rerun: finished files are skipped)" >&2
    return 2
  }
  echo "weights: ok ($dest)"
}

status=0
if [[ "$want_models" == 1 ]]; then
  case "$MODEL_SET" in
    instruct) download_repo "$HF_REPO_INSTRUCT" "$MODELS/Instruct" || status=$? ;;
    thinking) download_repo "$HF_REPO_THINKING" "$MODELS/Thinking" || status=$? ;;
    both)
      download_repo "$HF_REPO_INSTRUCT" "$MODELS/Instruct" || status=$?
      download_repo "$HF_REPO_THINKING" "$MODELS/Thinking" || status=$?
      ;;
  esac
fi

exit "$status"
