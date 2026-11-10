# free-llm-check — prove the free LLM routes actually answer as agents.
#
# The two routes are declared in dsh-terminal-plugins.nix (llmRows) and are
# key-gated at request time: pollinations answers anonymously, gemini needs
# a free key. Keys live in ~/.config/dsh/free-llm.env
# (KEY=VALUE lines, mode 0600); the dsh wrapper sources the same file.
#
# The pass criterion is a tool call, not a chat reply: a route that cannot emit
# `tool_calls` cannot drive an agent loop. One request per route.
#
# Gemini refuses direct connections from this region, so it is checked
# through the local sing-box HTTP inbound (10812). Pollinations is
# checked directly on purpose: it is the route that must work without the proxy.
#
# Exit status: 0 when every armed route passed, 1 when any armed route failed.

set -uo pipefail

PROXY="${FREE_LLM_PROXY:-http://127.0.0.1:10812}"
KEY_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dsh/free-llm.env"

if [ ! -e "$KEY_FILE" ]; then
  mkdir -p "$(dirname "$KEY_FILE")"
  (
    umask 077
    cat > "$KEY_FILE" << 'TEMPLATE'
# Free LLM routes for dsh. Paste the key after `=`, keep the file mode 0600.
# Gemini free tier (no card):  https://aistudio.google.com/apikey
GEMINI_API_KEY=
TEMPLATE
  )
  echo "free-llm-check: created $KEY_FILE — paste your free keys there."
fi

# shellcheck disable=SC1090
[ -r "$KEY_FILE" ] && {
  set -a
  . "$KEY_FILE"
  set +a
}

pass=0
fail=0
skip=0
throttled=0

payload() {
  jq -nc --arg m "$1" '{
    model: $m,
    messages: [{
      role: "user",
      content: "Call get_weather for Moscow. Use the tool, do not answer from memory."
    }],
    tools: [{
      type: "function",
      function: {
        name: "get_weather",
        description: "Get the current weather for a city",
        parameters: {
          type: "object",
          properties: { city: { type: "string" } },
          required: ["city"]
        }
      }
    }],
    tool_choice: "auto",
    max_tokens: 256
  }'
}

route() {
  local name="$1" base="$2" model="$3" keyvar="$4" proxy="$5"
  local key="" args=() body rc tool err

  if [ -n "$keyvar" ]; then
    key="${!keyvar:-}"
    if [ -z "$key" ]; then
      printf '%-13s %-46s SKIP  %s is unset\n' "$name" "$model" "$keyvar"
      skip=$((skip + 1))
      return
    fi
  fi

  args=(--silent --show-error --max-time 180 -H "Content-Type: application/json")
  [ -n "$proxy" ] && args+=(--proxy "$proxy")
  [ -n "$key" ] && args+=(-H "Authorization: Bearer $key")

  body=$(curl "${args[@]}" "${base%/}/chat/completions" -d "$(payload "$model")" 2>&1)
  rc=$?

  if [ "$rc" -ne 0 ]; then
    printf '%-13s %-46s FAIL  curl rc=%s: %s\n' "$name" "$model" "$rc" "$body"
    fail=$((fail + 1))
    return
  fi

  tool=$(printf '%s' "$body" \
    | jq -r '.choices[0].message.tool_calls[0].function.name // empty' 2> /dev/null)
  err=$(printf '%s' "$body" \
    | jq -r '.error.message // .error // .message // empty' 2> /dev/null)

  if [ "$tool" = "get_weather" ]; then
    printf '%-13s %-46s PASS  tool call emitted\n' "$name" "$model"
    pass=$((pass + 1))
  elif [[ "$body" == *FREE_LIMIT* || "$body" == *"free limit"* ]]; then
    printf '%-13s %-46s THROTTLED  %s\n' "$name" "$model" "${err:-rate limited}"
    throttled=$((throttled + 1))
  else
    printf '%-13s %-46s FAIL  %s\n' "$name" "$model" "${err:-unexpected response}"
    fail=$((fail + 1))
  fi
}

echo "free-llm-check: keys from $KEY_FILE; proxy $PROXY"
route pollinations "https://text.pollinations.ai/openai" "openai-fast" "" ""
route gemini "https://generativelanguage.googleapis.com/v1beta/openai" "gemini-3.8-flash" "GEMINI_API_KEY" "$PROXY"

printf '\n%d passed, %d throttled, %d failed, %d skipped\n' \
  "$pass" "$throttled" "$fail" "$skip"

if [ "$fail" -gt 0 ]; then
  exit 1
fi
