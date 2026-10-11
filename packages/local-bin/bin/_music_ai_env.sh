#!/bin/sh
# Shared preamble for the music-AI launchers in this directory (audio-analysis,
# music-embed, music-index, music-similar, music-tags). Source it next to the
# caller so the interpreter/venv knowledge lives in one place:
#
#   MUSIC_AI_SELF=$0 . "$(dirname "$0")/_music_ai_env.sh"
#
# The interpreter is a nix python (GC-rooted) and the packages come from the
# venv over PYTHONPATH: the venv's own bin/python symlink dies whenever the
# store path it points at is collected, which took these tools down once.
# Sets BASE, LIB, PY, SP and exports PYTHONPATH, LD_LIBRARY_PATH, HF_HOME.
BASE="@MUSIC_AI_BASE@"
# shellcheck disable=SC2034  # consumed by the sourcing launchers.
LIB="@MUSIC_AI_LIB@"
PY="${MUSIC_AI_PY:-@MUSIC_AI_PY@}"
[ -x "$PY" ] || PY="$HOME/.local/bin/python3.12"
SP="$BASE/venv-analysis/lib/python3.12/site-packages"

export PYTHONPATH="$SP${PYTHONPATH:+:$PYTHONPATH}"
export LD_LIBRARY_PATH="@ZSTD_LIB_DIR@:@ZLIB_LIB_DIR@:@GCC_LIB_DIR@:$SP/torch/lib:${LD_LIBRARY_PATH:-}"
export HF_HOME="${MUSIC_AI_HF_HOME:-@MUSIC_AI_HF_HOME@}"
