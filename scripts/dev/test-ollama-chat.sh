#!/usr/bin/env bash
# test-ollama-chat.sh — smoke-test local Ollama chat models wired into DSH as
# the "ollama-local" provider source. Run when there is enough free VRAM.
# Usage: ./test-ollama-chat.sh [--force] [--limit-ms N]
set -uo pipefail
export OLLAMA_MODELS=/zero/ai/ollama OLLAMA_HOST=127.0.0.1:11434
API=http://127.0.0.1:11434/v1/chat/completions
PROMPT="Отвечай одним словом: привет"
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
done << 'MODELS'
qwen3:8b 5.2
qwen3:8b-q8_0 8.9
qwen3:8b-ru 5.2
qwen3:32b 20
qwen3.5:27b 17
qwen3.5:122b 76
qwen3:235b-a22b 142
qwen3-vl:8b 6.1
qwen2.5vl:7b 6.0
qwen2.5vl:7b-q8_0 9.4
qwen2.5vl:3b 3.2
qwen2.5:7b 4.7
granite4.1:8b 5.3
gemma4:latest 9.6
gemma4:12b 7.6
gemma4:26b 17
deepseek-r1-distill-qwen:14b 9.0
llama3.2:1b 1.3
llama3.3:70b-instruct-q5_K_M 49
qwen3-coder:30b 18
qwen3-coder-next:latest 51
qwen2.5-coder:7b-instruct-q6_K 6.3
devstral:24b 14
deepcoder:14b 9.0
qwq:32b 19
huihui_ai/qwen3-abliterated:30b-a3b 18
huihui_ai/qwen3.5-abliterated:35b-a3b 23
huihui_ai/qwen3-coder-abliterated:latest 18
MODELS
echo "==== summary: pass=$pass fail=$fail skip=$skip fullgpu=$fullgpu partial=$partial ===="
