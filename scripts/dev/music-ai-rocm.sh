#!/usr/bin/env bash
# Make the music-AI embedding/tagging payloads run on the AMD GPU (RX 9070 XT,
# gfx1201) instead of the CPU.
#
# Why: venv-analysis holds CUDA builds of torch (2.14.0+cu130).  A +cu wheel
# never sees an AMD GPU, so torch.cuda.is_available() is False and
# pick_device() in music_embed.py / music_tags.py quietly falls back to CPU.
# This script swaps in the ROCm wheel that is already on disk
# (/zero/ai/music/tmp-dl) and verifies the result with the same environment the
# music-* wrappers use.
#
# transformers imports torchaudio whenever it is present (the MERT/CLAP audio
# path does), and the CUDA torchaudio/torchvision in the venv cannot load under
# ROCm torch (they want libcudart), so matching +rocm companion wheels are
# swapped in too whenever they are found next to the torch wheel.
#
# Idempotent and non-destructive: an existing +rocm set is reported and left
# alone (--force reinstalls), no site-packages directory is ever deleted, no
# other venv is touched, and no network access is needed.  The only repair the
# script may apply is the venv's own bin/python symlink when the nix store
# interpreter it points at has been garbage-collected: without a usable
# interpreter uv/pip cannot target the venv at all.
#
# Usage:
#   music-ai-rocm.sh [--venv DIR] [--wheel FILE] [--python PY]
#                    [--check] [--dry-run] [--force]
#
#   --venv DIR    venv to update (default: /zero/ai/music-ai/venv-analysis)
#   --wheel FILE  local torch wheel (default: newest torch-*+rocm*-cp<py>*.whl
#                 in /zero/ai/music/tmp-dl)
#   --python PY   interpreter for the install and the verification (default:
#                 the venv's bin/python, falling back to
#                 $HOME/.local/bin/python3.12)
#   --check       report only, change nothing; exit 1 when the venv does not
#                 have a GPU-visible ROCm torch
#   --dry-run     print the commands that would run, change nothing
#   --force       reinstall even when a +rocm torch is already present
#
# Exit codes: 0 ok or already done, 1 --check says "not GPU-ready" / the
# verification failed, 2 bad usage.
set -euo pipefail

VENV="/zero/ai/music-ai/venv-analysis"
WHEEL=""
PYTHON=""
WHEEL_DIR="/zero/ai/music/tmp-dl"
MODE="install"
DRY_RUN=0
FORCE=0

# CUDA builds of these break as soon as torch is the ROCm build, and
# transformers imports torchaudio from its audio path; only their exact
# versions/layout from the ROCm wheel set pair with torch.
COMPANIONS=(torchaudio torchvision)

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

usage() {
  awk 'NR > 1 && /^set -euo pipefail/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"
  exit "${1:-0}"
}

info() { printf '%s\n' "$*"; }

print_gpu_hint() {
  info "  GPU usage: music-embed --device cuda TRACK.flac (or music-tags ...);"
  info "  the music-* wrappers supply PYTHONPATH/LD_LIBRARY_PATH/HF_HOME."
}

short_version() {
  # "3.12.14" -> "3.12"; a bare "3.12" stays as is.
  local version="$1"
  if [[ "$version" == *.*.* ]]; then
    printf '%s\n' "${version%.*}"
  else
    printf '%s\n' "$version"
  fi
}

tag_version() {
  # "3.12" -> "312" for the wheel's cp tag.
  local short="$1"
  printf '%s\n' "${short//./}"
}

venv_version() {
  local venv="$1" version
  version=$(sed -n 's/^version_info *= *\([0-9][0-9.]*\).*/\1/p' "$venv/pyvenv.cfg" 2> /dev/null | head -1)
  if [[ -z "$version" ]]; then
    version=$(sed -n 's/^version *= *\([0-9][0-9.]*\).*/\1/p' "$venv/pyvenv.cfg" 2> /dev/null | head -1)
  fi
  if [[ -z "$version" ]]; then
    # Older venvs only record the interpreter path; the dangling link still
    # carries the version in its name.  `|| true` keeps pipefail from aborting.
    version=$(readlink "$venv/bin/python" 2> /dev/null | grep -o 'python3\.[0-9]*' | head -1 | sed 's/^python//' || true)
  fi
  printf '%s\n' "$version"
}

venv_python_works() {
  # Executable and actually starts — a dangling nix store symlink is neither,
  # and a stale pyvenv.cfg home can make an executable interpreter fail too.
  local venv="$1"
  [[ -x "$venv/bin/python" ]] && "$venv/bin/python" -c 'import sys' > /dev/null 2>&1
}

pick_interpreter() {
  local venv="$1" short="$2"
  if venv_python_works "$venv"; then
    printf '%s\n' "$venv/bin/python"
    return 0
  fi
  if [[ -n "$short" && -x "$HOME/.local/bin/python$short" ]]; then
    printf '%s\n' "$HOME/.local/bin/python$short"
    return 0
  fi
  if [[ -x "$HOME/.local/bin/python3.12" ]]; then
    printf '%s\n' "$HOME/.local/bin/python3.12"
    return 0
  fi
  return 1
}

newest_local_wheel() {
  # Newest "$dir/$package-*+rocm*-cp$tag*.whl"; empty -> non-zero.
  local dir="$1" package="$2" tag="$3" file newest=""
  for file in "$dir"/"$package"-*+rocm*-cp"$tag"*.whl; do
    [[ -e "$file" ]] || continue
    if [[ -z "$newest" || "$file" -nt "$newest" ]]; then
      newest="$file"
    fi
  done
  [[ -n "$newest" ]] || return 1
  printf '%s\n' "$newest"
}

# Print "<name> <version>" from the wheel's .dist-info/METADATA.  Runs the
# interpreter that will host the wheel, so a cp mismatch fails here too.
wheel_metadata() {
  local wheel="$1" python="$2"
  "$python" - "$wheel" << 'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    metas = [
        name
        for name in archive.namelist()
        if name.endswith(".dist-info/METADATA") and name.count("/") == 1
    ]
    if len(metas) != 1:
        sys.exit(f"expected exactly one .dist-info/METADATA, found {len(metas)}")
    text = archive.read(metas[0]).decode("utf-8", "replace")

name = version = ""
for line in text.splitlines():
    if not name and line.startswith("Name: "):
        name = line[len("Name: "):].strip()
    if not version and line.startswith("Version: "):
        version = line[len("Version: "):].strip()
if not name or not version:
    sys.exit("METADATA has no Name/Version")
print(name, version)
PY
}

installed_version() {
  local sp="$1" package="$2" meta version=""
  for meta in "$sp"/"$package"-*.dist-info/METADATA; do
    [[ -f "$meta" ]] || continue
    version=$(sed -n 's/^Version: //p' "$meta" | head -1)
    [[ -n "$version" ]] && break
  done
  printf '%s\n' "$version"
}

# The LD_LIBRARY_PATH the music-* wrappers export.  Sourcing their shared
# preamble keeps the nix store lib dirs and the venv's torch/lib in sync with
# whatever nix-maid currently generates.
wrapper_ld_library_path() {
  local env_script out
  for env_script in "$HOME/.local/bin/_music_ai_env.sh" /run/current-system/sw/bin/_music_ai_env.sh; do
    [[ -r "$env_script" ]] || continue
    if out=$(MUSIC_AI_PY="$PY" sh -c '. "$1" > /dev/null 2>&1; printf "%s" "${LD_LIBRARY_PATH:-}"' music-env "$env_script"); then
      printf '%s\n' "$out"
      return 0
    fi
  done
  return 1
}

compute_ld() {
  local sp="$1" ld
  ld=$(wrapper_ld_library_path || true)
  if [[ -n "$ld" && ":$ld:" != *":$sp/torch/lib:"* ]]; then
    ld="$sp/torch/lib:$ld"
  fi
  [[ -n "$ld" ]] || ld="$sp/torch/lib"
  if [[ -n "${LD_LIBRARY_PATH:-}" && ":$ld:" != *":$LD_LIBRARY_PATH:"* ]]; then
    ld="$ld:$LD_LIBRARY_PATH"
  fi
  printf '%s\n' "$ld"
}

# Run the torch check with the wrappers' environment.  Returns 0 when the GPU
# is visible, 1 when torch imported but no GPU is there, 2 when the import
# itself failed — the raw output is printed either way.
verify_torch() {
  local python="$1" sp="$2" ld output status=0
  ld=$(compute_ld "$sp")
  info "== verification"
  info "PYTHONPATH=$sp"
  info "LD_LIBRARY_PATH=$ld"
  info "$python -c \"import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0) if torch.cuda.is_available() else '')\""
  output=$(PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$sp${PYTHONPATH:+:$PYTHONPATH}" LD_LIBRARY_PATH="$ld" \
    "$python" -c "import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0) if torch.cuda.is_available() else '')" 2>&1) || status=$?
  printf '%s\n' "$output"
  if [[ "$status" -ne 0 ]]; then
    return 2
  fi
  if [[ "$output" == *" True "* ]]; then
    return 0
  fi
  return 1
}

# transformers imports torchaudio when the package exists, and the old CUDA
# build raises OSError (libcudart) under ROCm torch; fail loudly here instead
# of letting the payload crash later.
companion_check() {
  local python="$1" sp="$2" ld output status=0
  ld=$(compute_ld "$sp")
  info "== companion check (torchaudio/torchvision are imported by transformers when present)"
  output=$(PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$sp${PYTHONPATH:+:$PYTHONPATH}" LD_LIBRARY_PATH="$ld" "$python" -c '
import importlib.util

for module in ("torchaudio", "torchvision"):
    if importlib.util.find_spec(module) is not None:
        __import__(module)
        print("imported", module)
' 2>&1) || status=$?
  printf '%s\n' "$output"
  [[ "$status" -eq 0 ]]
}

install_wheel() {
  local package="$1" wheel="$2"
  if command -v uv > /dev/null 2>&1; then
    if uv pip install --python "$VENV_PY" --no-deps --reinstall-package "$package" "$wheel"; then
      return 0
    fi
    info "uv install of $package failed; falling back to pip"
  fi
  "$VENV_PY" -m pip install --no-deps "$wheel"
}

print_instructions() {
  local ld lib_dir
  ld=$(compute_ld "$SP")
  lib_dir="$REPO_ROOT/packages/local-bin/lib"
  info ""
  info "== use the GPU"
  info "  music-embed --device cuda TRACK.flac"
  info "  music-tags  --device cuda TRACK.flac"
  info ""
  info "The music-* wrappers export PYTHONPATH/LD_LIBRARY_PATH/HF_HOME themselves;"
  info "--device cuda is the only flag needed (auto already picks CUDA once it is"
  info "available).  The environment overrides they honour are MUSIC_AI_PY for the"
  info "interpreter and MUSIC_AI_HF_HOME for the model cache."
  info "Direct invocation without the wrappers:"
  info "  PYTHONPATH=$SP LD_LIBRARY_PATH=$ld HF_HOME=\${HF_HOME:-/zero/ai/music-ai/hf} \\"
  info "    $PY $lib_dir/music_embed.py --device cuda TRACK.flac"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --venv)
      VENV="${2:?--venv needs a directory}"
      shift 2
      ;;
    --wheel)
      WHEEL="${2:?--wheel needs a file}"
      shift 2
      ;;
    --python)
      PYTHON="${2:?--python needs a path}"
      shift 2
      ;;
    --check)
      MODE="check"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h | --help)
      usage 0
      ;;
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

[[ -f "$VENV/pyvenv.cfg" ]] || {
  echo "not a python venv: $VENV (pyvenv.cfg missing)" >&2
  exit 2
}

VENV_VERSION=$(venv_version "$VENV")
VENV_SHORT=$(short_version "$VENV_VERSION")
if [[ -z "$VENV_SHORT" ]]; then
  echo "cannot determine the venv's python version from $VENV/pyvenv.cfg" >&2
  exit 2
fi

if [[ -n "$PYTHON" ]]; then
  [[ -x "$PYTHON" ]] || {
    echo "--python is not executable: $PYTHON" >&2
    exit 2
  }
  PY="$PYTHON"
else
  if ! PY=$(pick_interpreter "$VENV" "$VENV_SHORT"); then
    echo "no interpreter found: $VENV/bin/python is not usable and neither" >&2
    echo "\$HOME/.local/bin/python$VENV_SHORT nor \$HOME/.local/bin/python3.12 exists" >&2
    exit 2
  fi
  if [[ "$PY" != "$VENV/bin/python" ]]; then
    info "note: $VENV/bin/python is not usable (nix store GC?); using $PY"
  fi
fi

if ! PY_VERSION=$("$PY" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2> /dev/null); then
  echo "cannot run $PY" >&2
  exit 2
fi
PY_SHORT=$(short_version "$PY_VERSION")
PY_TAG=$(tag_version "$PY_SHORT")

# A wheel must match the venv's ABI; refusing here avoids a half-broken
# site-packages that the wrappers would then load.
if [[ "$PY_SHORT" != "$VENV_SHORT" ]]; then
  echo "refusing: $VENV was created with python $VENV_SHORT, but the selected" >&2
  echo "interpreter $PY is python $PY_SHORT — pass --python pointing at a" >&2
  echo "python$VENV_SHORT build" >&2
  exit 2
fi

SP="$VENV/lib/python$PY_SHORT/site-packages"
[[ -d "$SP" ]] || {
  echo "no site-packages at $SP (wrong venv or interpreter?)" >&2
  exit 2
}

if [[ -z "$WHEEL" ]]; then
  if ! WHEEL=$(newest_local_wheel "$WHEEL_DIR" torch "$PY_TAG"); then
    echo "no local torch-*+rocm*-cp$PY_TAG*.whl in $WHEEL_DIR" >&2
    echo "pass --wheel FILE with the wheel to install" >&2
    exit 2
  fi
fi
[[ -f "$WHEEL" ]] || {
  echo "wheel not found: $WHEEL" >&2
  exit 2
}

WHEEL_NAME=$(basename "$WHEEL")
case "$WHEEL_NAME" in
  torch-*+rocm*-cp"$PY_TAG"-*.whl) ;;
  *)
    echo "wheel name does not match python $PY_SHORT (expected torch-*+rocm*-cp$PY_TAG-*.whl):" >&2
    echo "  $WHEEL_NAME" >&2
    exit 2
    ;;
esac

if ! META=$(wheel_metadata "$WHEEL" "$PY"); then
  echo "cannot read METADATA from wheel: $WHEEL" >&2
  exit 2
fi
read -r META_NAME META_VERSION <<< "$META"
[[ "$META_NAME" == "torch" ]] || {
  echo "not a torch wheel (METADATA Name: $META_NAME)" >&2
  exit 2
}
[[ "$META_VERSION" == *+rocm* ]] || {
  echo "wheel is not a +rocm build (METADATA Version: $META_VERSION)" >&2
  exit 2
}

INSTALLED=$(installed_version "$SP" torch)
info "venv:            $VENV (python $VENV_VERSION)"
info "interpreter:     $PY (python $PY_VERSION)"
info "site-packages:   $SP"
info "wheel:           $WHEEL"
info "wheel torch:     $META_NAME $META_VERSION"
info "installed torch: ${INSTALLED:-none}"
for companion in "${COMPANIONS[@]}"; do
  companion_version=$(installed_version "$SP" "$companion")
  if [[ -n "$companion_version" ]]; then
    info "installed $companion: $companion_version"
  fi
done

# A companion that is present but not a +rocm build will break the transformers
# audio path once torch is swapped, so it is replaced from the local wheel set.
COMPANION_PLAN=()
COMPANION_BROKEN=()
for companion in "${COMPANIONS[@]}"; do
  companion_version=$(installed_version "$SP" "$companion")
  [[ -n "$companion_version" ]] || continue
  if companion_wheel=$(newest_local_wheel "$WHEEL_DIR" "$companion" "$PY_TAG"); then
    if [[ "$companion_version" != *+rocm* || "$FORCE" -eq 1 ]]; then
      COMPANION_PLAN+=("$companion $companion_wheel")
    fi
  elif [[ "$companion_version" != *+rocm* ]]; then
    COMPANION_BROKEN+=("$companion $companion_version")
  fi
done

NEED_INSTALL=0
if [[ "$FORCE" -eq 1 || -z "$INSTALLED" || "$INSTALLED" != *+rocm* ]]; then
  NEED_INSTALL=1
fi
if [[ "${#COMPANION_PLAN[@]}" -gt 0 ]]; then
  NEED_INSTALL=1
fi

if [[ "$MODE" == "check" ]]; then
  if [[ "$NEED_INSTALL" -eq 0 ]]; then
    if verify_torch "$PY" "$SP"; then
      if companion_check "$PY" "$SP"; then
        info "== state: ROCm torch $INSTALLED is installed and the GPU is visible"
        exit 0
      fi
      info "== state: torch is GPU-ready, but a companion torch build failed to import"
      exit 1
    fi
    info "== state: ROCm torch $INSTALLED is installed, but no GPU is visible to torch"
    exit 1
  fi
  if ! venv_python_works "$VENV"; then
    info "note: $VENV/bin/python is not usable; installing would relink it to $PY"
  fi
  info "== current state"
  verify_torch "$PY" "$SP" || true
  for entry in "${COMPANION_BROKEN[@]}"; do
    info "warning: $entry is a non-ROCm build and no local +rocm wheel was found"
  done
  info "== state: no complete +rocm set installed (torch: ${INSTALLED:-none});"
  info "   run without --check to install $META_VERSION from $WHEEL"
  print_gpu_hint
  exit 1
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  if [[ "$NEED_INSTALL" -eq 0 ]]; then
    info "dry run: torch $INSTALLED is already a +rocm build; nothing to do (--force reinstalls)"
  else
    if ! venv_python_works "$VENV"; then
      info "dry run: would repair $VENV/bin/python -> $(readlink -f "$PY") and update $VENV/pyvenv.cfg home"
    fi
    if [[ "$FORCE" -eq 1 || -z "$INSTALLED" || "$INSTALLED" != *+rocm* ]]; then
      info "dry run: would run: uv pip install --python $VENV/bin/python --no-deps --reinstall-package torch $WHEEL"
    fi
    for entry in "${COMPANION_PLAN[@]}"; do
      read -r companion companion_wheel <<< "$entry"
      info "dry run: would run: uv pip install --python $VENV/bin/python --no-deps --reinstall-package $companion $companion_wheel"
    done
    info "dry run: (pip fallback: $VENV/bin/python -m pip install --no-deps <wheel>)"
    info "dry run: would verify with: PYTHONPATH=$SP LD_LIBRARY_PATH=<wrappers> $VENV/bin/python -c 'import torch; ...'"
  fi
  print_gpu_hint
  exit 0
fi

if [[ "$NEED_INSTALL" -eq 0 ]]; then
  info "== torch $INSTALLED is already a ROCm build — no install needed (use --force to reinstall)"
else
  if venv_python_works "$VENV"; then
    VENV_PY="$VENV/bin/python"
  else
    # The wrappers work around a GC'd interpreter with PYTHONPATH; uv/pip
    # cannot, so point the venv's own link at the selected python first (the
    # same repair scripts/dev/fix-music-venvs.sh applies).
    REPAIR_TARGET=$(readlink -f "$PY")
    info "== repairing $VENV/bin/python -> $REPAIR_TARGET"
    ln -sfn "$REPAIR_TARGET" "$VENV/bin/python"
    ln -sfn python "$VENV/bin/python3"
    ln -sfn python "$VENV/bin/python$PY_SHORT"
    prefix=$(dirname "$(dirname "$REPAIR_TARGET")")
    if grep -q '^home *=' "$VENV/pyvenv.cfg"; then
      sed -i "s#^home *= *.*#home = $prefix/bin#" "$VENV/pyvenv.cfg"
    else
      printf 'home = %s/bin\n' "$prefix" >> "$VENV/pyvenv.cfg"
    fi
    VENV_PY="$VENV/bin/python"
    if ! "$VENV_PY" -c 'import sys' 2> /dev/null; then
      echo "repaired interpreter does not start: $VENV_PY" >&2
      exit 1
    fi
  fi

  if [[ "$FORCE" -eq 1 || -z "$INSTALLED" || "$INSTALLED" != *+rocm* ]]; then
    info "== installing torch $META_VERSION into $VENV"
    install_wheel torch "$WHEEL"
  fi
  for entry in "${COMPANION_PLAN[@]}"; do
    read -r companion companion_wheel <<< "$entry"
    info "== installing $companion (ROCm companion) into $VENV"
    install_wheel "$companion" "$companion_wheel"
  done
  info "== installed torch: $(installed_version "$SP" torch)"
  for companion in "${COMPANIONS[@]}"; do
    companion_version=$(installed_version "$SP" "$companion")
    if [[ -n "$companion_version" ]]; then
      info "== installed $companion: $companion_version"
    fi
  done
  for entry in "${COMPANION_BROKEN[@]}"; do
    info "warning: $entry is a non-ROCm build and no local +rocm wheel was found"
  done
fi

VERIFY_PY="$PY"
if venv_python_works "$VENV"; then
  VERIFY_PY="$VENV/bin/python"
fi

if verify_torch "$VERIFY_PY" "$SP"; then
  if companion_check "$VERIFY_PY" "$SP"; then
    info "== GPU is usable: torch.cuda.is_available() is True"
    print_instructions
    exit 0
  fi
  info ""
  info "== GPU works, but importing a companion torch build failed (see above)"
  info "transformers imports torchaudio when it is present, so the MERT/CLAP"
  info "payload would crash.  Put matching torchaudio-*+rocm*-cp$PY_TAG*.whl and"
  info "torchvision-*+rocm*-cp$PY_TAG*.whl wheels into $WHEEL_DIR and re-run."
  exit 1
fi

info ""
info "== not GPU-ready: see the verification output above"
info "If the import itself failed, the traceback is the cause (check that"
info "$SP/torch/lib exists and is complete)."
info "If torch imported but is_available() is False, check access to /dev/kfd"
info "and that the user is in the 'render' group (id | grep render)."
print_gpu_hint
exit 1
