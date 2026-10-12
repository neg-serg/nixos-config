#!/usr/bin/env bash
# One read-only report on the whole music-AI stack: wrappers, index, tags,
# playlists, models, venvs, GPU and the refresh timer.  Every section prints a
# one-line hint when something is missing, so the output doubles as a to-do
# list.
#
# Usage:
#   music-ai-status.sh [--json] [--quiet]
#
#   --json    machine-readable summary (no colours, one JSON object)
#   --quiet   only the sections that need attention
#
# Exit codes: 0 everything present, 1 at least one item needs attention,
# 2 bad usage.
set -euo pipefail

MODE="text"
QUIET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      MODE="json"
      shift
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    -h | --help)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      exit 2
      ;;
  esac
done

HOME_DIR="${HOME:-/home/neg}"
MUSIC_DIR="${MUSIC_DIR:-$HOME_DIR/music}"
INDEX_DIR="${MUSIC_INDEX_DIR:-$HOME_DIR/.cache/music-index}"
TAGS_FILE="${MUSIC_MTG_TAGS:-$HOME_DIR/.cache/music-mtg/tags.jsonl}"
PLAYLISTS="${MPD_PLAYLISTS:-$HOME_DIR/.config/mpd/playlists}"
HF_HOME_DIR="${MUSIC_AI_HF_HOME:-/zero/ai/music-ai/hf}"
MTG_MODELS="${MUSIC_MTG_MODELS:-/zero/ai/music-ai/mtg-models}"
MTG_VENV="${MUSIC_MTG_VENV:-/zero/ai/music-ai/venv-mtg}"
AV_VENV="${MUSIC_AI_BASE:-/zero/ai/music-ai}/venv-analysis"
PY="${MUSIC_AI_PY:-$HOME_DIR/.local/bin/python3.12}"
[[ -x "$PY" ]] || PY="$(command -v python3 || true)"

problems=()
note() {
  local status="$1" name="$2" detail="$3"
  [[ "$status" == "ok" ]] || problems+=("$name: $detail")
  if [[ "$MODE" == "json" ]]; then
    return
  fi
  if [[ -n "$QUIET" && "$status" == "ok" ]]; then
    return
  fi
  local mark="!"
  case "$status" in
    ok) mark="✓" ;;
    warn) mark="!" ;;
    bad) mark="✗" ;;
  esac
  printf '%s %-14s %s\n' "$mark" "$name" "$detail"
}

# --- wrappers -------------------------------------------------------------
tools_ok=0
tools_missing=()
for tool in music-embed music-tags music-index music-similar music-mtg-tags mpd-voice; do
  if [[ -x "$HOME_DIR/.local/bin/$tool" ]] || command -v "$tool" > /dev/null 2>&1; then
    tools_ok=$((tools_ok + 1))
  else
    tools_missing+=("$tool")
  fi
done
if [[ ${#tools_missing[@]} -eq 0 ]]; then
  note ok "wrappers" "all 6 in ~/.local/bin"
else
  note warn "wrappers" "${tools_ok}/6 present, missing: ${tools_missing[*]} (switch a newer generation)"
fi

# --- index ----------------------------------------------------------------
if [[ -f "$INDEX_DIR/meta.json" ]]; then
  read -r count layer created <<< "$(
    "$PY" - "$INDEX_DIR/meta.json" << 'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
print(meta.get("count", 0), meta.get("layer", "?"), meta.get("created", "?"))
PY
  )"
  age_h=$(
    "$PY" - "$created" << 'PY'
import datetime, sys
try:
    stamp = datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%S")
    print(int((datetime.datetime.now() - stamp).total_seconds() // 3600))
except Exception:
    print(-1)
PY
  )
  cache_files=$(find "$INDEX_DIR/cache" -name '*.npy' 2> /dev/null | wc -l)
  center="no center.npy"
  [[ -f "$INDEX_DIR/center.npy" ]] && center="centered"
  note ok "index" "$count tracks, layer $layer, built ${age_h}h ago, $cache_files cached vectors, $center"
else
  note bad "index" "no $INDEX_DIR/meta.json (run: music-index ~/music --out $INDEX_DIR)"
fi

# --- tags -----------------------------------------------------------------
if [[ -f "$TAGS_FILE" ]]; then
  read -r lines coverage with_seconds samples <<< "$(
    "$PY" - "$TAGS_FILE" << 'PY'
import json, sys
lines = covered = with_seconds = samples = 0
for line in open(sys.argv[1], errors="replace"):
    if not line.strip():
        continue
    try:
        record = json.loads(line)
    except ValueError:
        continue
    lines += 1
    if "/samples/" in str(record.get("path", "")):
        samples += 1
    if "audio_seconds" in record:
        with_seconds += 1
    moods = (record.get("tags") or {}).get("mood") or []
    if moods and float(moods[0].get("score", 0)) >= 0.10:
        covered += 1
print(lines, covered, with_seconds, samples)
PY
  )"
  detail="$lines tracks, mood coverage $coverage"
  status="ok"
  if [[ "$with_seconds" -eq 0 ]]; then
    detail+=" — no audio_seconds yet, so the length filter is inert (re-tag to enable)"
    status="warn"
  fi
  if [[ "$samples" -gt 0 ]]; then
    detail+=", $samples sample paths inside (tags_exclude hides them from the mood queue)"
    status="warn"
  fi
  note "$status" "tags" "$detail"
else
  note warn "tags" "no $TAGS_FILE (run: just music-refresh --skip-playlists)"
fi

# --- playlists ------------------------------------------------------------
if [[ -d "$PLAYLISTS" ]]; then
  m3u=$(find "$PLAYLISTS" -maxdepth 1 -name '*.m3u' 2> /dev/null | wc -l)
  if [[ "$m3u" -gt 0 ]]; then
    note ok "playlists" "$m3u .m3u in $PLAYLISTS"
  else
    note warn "playlists" "none in $PLAYLISTS (run: music-mtg-tags --tags $TAGS_FILE --playlists $PLAYLISTS --by mood)"
  fi
else
  note warn "playlists" "no $PLAYLISTS (run music-refresh to create the lists)"
fi

# --- models ---------------------------------------------------------------
mert=0
clap=0
[[ -d "$HF_HOME_DIR/hub" ]] && mert=$(find "$HF_HOME_DIR/hub" -maxdepth 1 -name 'models--m-a-p--MERT*' 2> /dev/null | wc -l)
[[ -d "$HF_HOME_DIR/hub" ]] && clap=$(find "$HF_HOME_DIR/hub" -maxdepth 1 -name 'models--laion--clap*' 2> /dev/null | wc -l)
mtg=$(find "$MTG_MODELS" -maxdepth 1 -name '*.pb' 2> /dev/null | wc -l)
say() { [[ "$1" -gt 0 ]] && printf 'yes' || printf 'no'; }
detail="HF: MERT $(say "$mert"), CLAP $(say "$clap") in $HF_HOME_DIR; MTG: $mtg graphs"
status="ok"
if [[ "$clap" -eq 0 ]]; then
  detail+=" — CLAP downloads on the first music-tags run"
fi
# Backbone + genre + mood + instrument = 4 graphs for the core set.
if [[ "$mtg" -lt 4 ]]; then
  detail+=" (fetch MTG with: just music-mtg-setup)"
  status="warn"
fi
note "$status" "models" "$detail"

# --- venvs and GPU --------------------------------------------------------
fix_script="$(dirname "$(readlink -f "$0")")/fix-music-venvs.sh"
if [[ -x "$fix_script" ]]; then
  venv_line="$("$fix_script" --check 2>&1 | tail -1)"
  if [[ "$venv_line" == *"0 broken"* ]]; then
    note ok "venvs" "$venv_line"
  else
    note warn "venvs" "$venv_line (run: just fix-music-venvs)"
  fi
fi
if [[ -d "$AV_VENV/lib" ]]; then
  device="$(
    PYTHONPATH="$AV_VENV/lib/python3.12/site-packages" \
      LD_LIBRARY_PATH="$AV_VENV/lib/python3.12/site-packages/torch/lib" \
      timeout 120 "$PY" -c 'import torch; print(torch.__version__, "cuda" if torch.cuda.is_available() else "cpu-only")' 2> /dev/null || echo "torch unavailable"
  )"
  if [[ "$device" == *"cuda"* ]]; then
    # A ROCm wheel can report a device and still abort inside a kernel: this
    # host crashed MERT inference once ("page not present"), so the status also
    # runs the two operations that died (a matmul and a conv1d) and reports.
    smoke="$(
      PYTHONPATH="$AV_VENV/lib/python3.12/site-packages" \
        LD_LIBRARY_PATH="$AV_VENV/lib/python3.12/site-packages/torch/lib" \
        timeout 180 "$PY" - << 'PYSMOKE' 2>&1 | tail -1
import torch
a = torch.randn(512, 512, device="cuda")
b = (a @ a).sum().item()
conv = torch.nn.Conv1d(1, 8, 10).cuda()
out = conv(torch.randn(1, 1, 24000, device="cuda")).shape[0]
print(f"ok matmul {b:.0f} conv {out}")
PYSMOKE
    )" || smoke="crashed"
    case "$smoke" in
      ok\ matmul*) note ok "gpu" "$device, $smoke" ;;
      *)
        note warn "gpu" "$device but the smoke test failed ($smoke) — the ROCm path is not trustworthy, use --device cpu"
        ;;
    esac
  elif [[ "$device" == *"+rocm"* ]]; then
    # A ROCm wheel reports cpu-only when /dev/kfd is unreachable (sandboxed
    # shell, missing render group): the environment is the problem, not the venv.
    note warn "gpu" "$device — ROCm wheel installed, no device visible from this process (check from the host session)"
  else
    note warn "gpu" "$device (just music-ai-rocm moves the venv to the ROCm wheel)"
  fi
fi
if [[ -d "$MTG_VENV/lib" ]]; then
  note ok "mtg venv" "$MTG_VENV"
else
  note warn "mtg venv" "no $MTG_VENV (tagging needs it: just music-mtg-setup)"
fi

# --- refresh timer --------------------------------------------------------
bus="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus"
if command -v systemctl > /dev/null 2>&1 && [[ ! -S "$bus" ]]; then
  # Without a session bus (sandboxed shell, cron) systemd would answer
  # "not installed" even when the unit exists, so name the real problem.
  note warn "timer" "cannot reach the user systemd from here (no $bus) — check: systemctl --user list-timers music-index.timer"
elif command -v systemctl > /dev/null 2>&1; then
  state="$(systemctl --user is-enabled music-index.timer 2> /dev/null || true)"
  case "$state" in
    enabled)
      next="$(systemctl --user list-timers music-index.timer --no-pager 2> /dev/null | sed -n 2p | tr -s ' ' | cut -d' ' -f1-4)"
      note ok "timer" "enabled, next run: ${next:-unknown}"
      ;;
    "")
      note warn "timer" "music-index.timer not installed (features.media.audio.musicTagging.autoIndex)"
      ;;
    *)
      note warn "timer" "state: $state (systemctl --user enable --now music-index.timer)"
      ;;
  esac
fi

if [[ "$MODE" == "json" ]]; then
  printf '{"problems":%s,"count":%d}\n' \
    "$("$PY" -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "${problems[@]+"${problems[@]}"}")" \
    "${#problems[@]}"
  exit 0
fi

if [[ ${#problems[@]} -eq 0 ]]; then
  echo "music-ai-status: everything present"
  exit 0
fi
echo
echo "needs attention (${#problems[@]}):"
for item in "${problems[@]}"; do
  echo "  - $item"
done
exit 1
