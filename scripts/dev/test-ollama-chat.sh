#!/usr/bin/env bash
# test-ollama-chat.sh — smoke-test local Ollama chat models wired into DSH as
# the "ollama-local" provider source. Run when there is enough free VRAM.
# Usage: ./test-ollama-chat.sh [--force] [--limit-ms N]
#
# The model list is discovered from the daemon (`/api/tags` for names and exact
# bytes, `/api/show` for capabilities), so it follows the store instead of
# drifting: a hand-kept list named 28 models that had left months earlier.
set -uo pipefail
export OLLAMA_MODELS=/zero/ai/ollama OLLAMA_HOST=127.0.0.1:11434
HOST=http://127.0.0.1:11434
API=$HOST/v1/chat/completions
PROMPT="Answer with one word: hello"
LIMIT_MS=90000
FORCE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --limit-ms)
      LIMIT_MS=$2
      shift
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 2
      ;;
  esac
  shift
done

# Find the discrete GPU (largest VRAM total) to estimate free space.
TOTAL=0
USED=0
for d in /sys/class/drm/card*/device; do
  t=$(cat "$d/mem_info_vram_total" 2> /dev/null | tr -dc '0-9')
  if [ -z "$t" ]; then t=0; fi
  if [ "$t" -gt "$TOTAL" ]; then
    TOTAL=$t
    USED=$(cat "$d/mem_info_vram_used" 2> /dev/null | tr -dc '0-9')
  fi
  if [ -z "$USED" ]; then USED=0; fi
done
FREE_GB=$(python3 -c "print(round(($TOTAL - $USED)/1e9,1))" 2> /dev/null || echo "?")

# KV (q8_0 @32k) and runtime overhead, in GB.
KV_GB=2.4
BUF_GB=1.2

pass=0
fail=0
skip=0
fullgpu=0
partial=0
# Chat models only: "completion" is the capability a chat model carries and an
# embedding/OCR-only one does not, so the filter is by what the model can do
# rather than by its name.
discover() {
  python3 - "$HOST" << 'PY'
import json
import sys
import urllib.request

host = sys.argv[1]


def call(path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        host + path, data, {"Content-Type": "application/json"}
    )
    try:
        return json.load(urllib.request.urlopen(req, timeout=10))
    except Exception as exc:  # noqa: BLE001
        sys.exit(f"ollama API: {exc}")


rows = []
for m in call("/api/tags").get("models", []):
    caps = call("/api/show", {"model": m["name"]}).get("capabilities") or []
    if "completion" in caps:
        rows.append((m["size"], m["name"]))

# Smallest first: those are the ones a 16 GB card can actually run.
for size, name in sorted(rows):
    print(f"{name} {size / 1e9:.1f}")
PY
}

MODELS=$(discover)
if [ -z "$MODELS" ]; then
  echo "no chat models reported by $HOST (is ollama running?)" >&2
  exit 1
fi

while read -r model size; do
  [ -z "$model" ] && continue
  est=$(python3 -c "print(round($size + $KV_GB + $BUF_GB,1))")
  if [ "$FORCE" = 0 ] && [ "$FREE_GB" != "?" ]; then
    if ! python3 -c "import sys;sys.exit(0 if $est <= $FREE_GB else 1)"; then
      echo "SKIP $model (est ${est}G > free ${FREE_GB}G)"
      skip=$((skip + 1))
      continue
    fi
  fi
  start=$(date +%s%N)
  out=$(curl -s --max-time $((LIMIT_MS / 1000)) "$API" -H "Content-Type: application/json" -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"max_tokens\":8}" 2>&1)
  code=$?
  end=$(date +%s%N)
  tt=$(((end - start) / 1000000))
  proc=$(ollama ps 2> /dev/null | awk -v m="$model" '$1 == m {print $5" "$6}')
  if [ "$code" -eq 0 ] && echo "$out" | grep -q "\"content\""; then
    echo "PASS $model (${proc:-?}) (${tt}ms)"
    pass=$((pass + 1))
    case "$proc" in
      "100% GPU") fullgpu=$((fullgpu + 1)) ;;
      *%*) partial=$((partial + 1)) ;;
    esac
  else
    echo "FAIL $model (exit $code, ${tt}ms): $(echo "$out" | head -c 200)"
    fail=$((fail + 1))
  fi
done <<< "$MODELS"
echo "==== summary: pass=$pass fail=$fail skip=$skip fullgpu=$fullgpu partial=$partial ===="
