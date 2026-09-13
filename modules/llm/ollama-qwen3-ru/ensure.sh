set -eu
export OLLAMA_MODELS=/zero/ai/ollama
export OLLAMA_HOST=127.0.0.1:11434
mkdir -p "$OLLAMA_MODELS"

cp "@modelfile@" "@modelfileOut@"
chmod 0664 "@modelfileOut@"

# Wait for the ollama API to become reachable (max ~60s).
i=0
until @ollama@ list > /dev/null 2>&1; do
  i=$((i + 1))
  [ "$i" -ge 60 ] && break
  sleep 1
done

# Base model must be present; create the tuned variant only if missing.
if @ollama@ list 2> /dev/null | grep -q '^@base@ '; then
  if ! @ollama@ list 2> /dev/null | grep -q '^@model@ '; then
    @ollama@ create @model@ -f "@modelfileOut@"
  fi
fi
