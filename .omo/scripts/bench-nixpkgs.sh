#!/usr/bin/env bash
# bench-nixpkgs.sh — Benchmark nix eval performance with NIX_SHOW_STATS
#
# Usage: bench-nixpkgs.sh --variant slim|upstream
#
# Runs 1 cold eval + 3 warm evals of the nixosConfigurations.odin toplevel,
# captures NIX_SHOW_STATS JSON and wall time, outputs CSV to /tmp/bench-<variant>.csv.
set -euo pipefail

# ── Paths ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="$(dirname "$SCRIPT_DIR")/evidence"
mkdir -p "$EVIDENCE_DIR"

# ── Arg parsing ──────────────────────────────────────────────────────────────
VARIANT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant)
            VARIANT="$2"
            shift 2
            ;;
        --variant=*)
            VARIANT="${1#*=}"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 --variant slim|upstream" >&2
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Usage: $0 --variant slim|upstream" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$VARIANT" ]]; then
    echo "ERROR: --variant is required (slim or upstream)" >&2
    exit 1
fi
if [[ "$VARIANT" != "slim" && "$VARIANT" != "upstream" ]]; then
    echo "ERROR: --variant must be 'slim' or 'upstream', got '$VARIANT'" >&2
    exit 1
fi

# ── Tool detection ───────────────────────────────────────────────────────────
JSON_PARSER=""
if command -v jq &>/dev/null; then
    JSON_PARSER="jq"
elif command -v python3 &>/dev/null; then
    JSON_PARSER="python3"
else
    echo "ERROR: Neither jq nor python3 is available. One is required for JSON parsing." >&2
    exit 1
fi

# ── Nix eval expression ─────────────────────────────────────────────────────
NIX_EXPR='.#nixosConfigurations.odin.config.system.build.toplevel.name'
NIX_EVAL_ARGS=(--extra-experimental-features 'flakes nix-command')

# ── CSV output ──────────────────────────────────────────────────────────────
CSV_FILE="/tmp/bench-${VARIANT}.csv"
CSV_HEADER="variant,run_type,run_num,cpu_time,wall_time,values,thunks,sets_bytes,gc_time,gc_fraction,nrAvoided,nrLookups"
echo "$CSV_HEADER" > "$CSV_FILE"

# ── JSON parsing helpers ────────────────────────────────────────────────────

# parse_stats_json <file>  →  prints "cpu,values,thunks,sets_bytes,gc_time,gc_fraction,nrAvoided,nrLookups"
parse_stats_json() {
    local file="$1"
    if [[ "$JSON_PARSER" == "jq" ]]; then
        # nix emits stats JSON with fields like cpuTime, nrThunks, time.gc, time.gcFraction
        jq -r '[
            (.cpuTime // .time.cpu // 0),
            (.values.number // 0),
            (.nrThunks // .thunks.number // 0),
            (.sets.bytes // 0),
            (.time.gc // .gc.time // 0),
            (.time.gcFraction // .gc.fraction // 0),
            (.nrAvoided // 0),
            (.nrLookups // 0)
        ] | map(tostring) | join(",")' "$file"
    else
        python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
t = d.get('time', {})
g = d.get('gc', {})
vals = [
    d.get('cpuTime', t.get('cpu', 0)),
    d.get('values', {}).get('number', 0),
    d.get('nrThunks', d.get('thunks', {}).get('number', 0)),
    d.get('sets', {}).get('bytes', 0),
    t.get('gc', g.get('time', 0)),
    t.get('gcFraction', g.get('fraction', 0)),
    d.get('nrAvoided', 0),
    d.get('nrLookups', 0),
]
print(','.join(str(v) for v in vals))
" "$file"
    fi
}

# validate_json <file>  →  true if valid JSON, false otherwise
validate_json() {
    local file="$1"
    if [[ "$JSON_PARSER" == "jq" ]]; then
        jq -e . "$file" >/dev/null 2>&1
    else
        python3 -c "import json; json.load(open('$file'))" 2>/dev/null
    fi
}

# ── Run one benchmark iteration ─────────────────────────────────────────────

# Usage: run_bench <run_type> <run_num> <run_total>
# run_type = "cold" or "warm"
run_bench() {
    local run_type="$1"
    local run_num="$2"
    local run_total="$3"
    local stats_file="/tmp/stats-${VARIANT}-${run_type}-${run_num}.json"
    local time_file="/tmp/time-${VARIANT}-${run_type}-${run_num}.txt"

    echo "[bench] ${VARIANT} ${run_type} run ${run_num}/${run_total}..." >&2

    # Run nix eval with NIX_SHOW_STATS=1
    #
    # Diagram of the redirection trick:
    #   Outer 2> "${time_file}"  →  captures `command time -p` stderr (wall time)
    #   Inner exec 2> "${stats_file}"  →  redirects nix stderr (NIX_SHOW_STATS JSON + warnings)
    #
    # This keeps the time output and the JSON stats in separate files.
    NIX_SHOW_STATS=1 \
        command time -p \
        bash -c 'exec 2>"$1"; nix eval --extra-experimental-features "flakes nix-command" ".#nixosConfigurations.odin.config.system.build.toplevel.name" > /dev/null' \
        _ "$stats_file" 2> "$time_file"

    # Strip any evaluation warning lines from the stats JSON (they appear when
    # nix emits warnings on stderr before the JSON blob).
    if [[ -f "$stats_file" ]]; then
        sed -i '/^evaluation warning:/d' "$stats_file"
    fi

    # ── Validate stats JSON ──────────────────────────────────────────────
    if ! validate_json "$stats_file"; then
        cp "$stats_file" "$EVIDENCE_DIR/bench-parse-error.log"
        echo "ERROR: Failed to parse stats JSON from ${stats_file}" >&2
        echo "Raw content saved to ${EVIDENCE_DIR}/bench-parse-error.log" >&2
        cat "$stats_file" >&2
        exit 1
    fi

    # ── Parse wall time from time output ─────────────────────────────────
    local wall_time
    wall_time=$(grep '^real ' "$time_file" | head -1 | awk '{print $2}') || true
    if [[ -z "$wall_time" ]]; then
        echo "ERROR: Could not parse wall time from ${time_file}" >&2
        cat "$time_file" >&2
        exit 1
    fi

    # ── Parse stats JSON ─────────────────────────────────────────────────
    local parsed
    parsed=$(parse_stats_json "$stats_file")
    # parsed = "cpu,values,thunks,sets_bytes,gc_time,gc_fraction,nrAvoided,nrLookups"

    # ── Assemble CSV row ─────────────────────────────────────────────────
    # CSV column order: variant,run_type,run_num,cpu_time,wall_time,values,...
    # parsed order:     cpu,values,thunks,sets_bytes,gc_time,gc_fraction,nrAvoided,nrLookups
    # We need to insert wall_time after cpu.
    local cpu values thunks sets_bytes gc_time gc_fraction nrAvoided nrLookups
    IFS=',' read -r cpu values thunks sets_bytes gc_time gc_fraction nrAvoided nrLookups <<< "$parsed"

    local csv_row
    csv_row="${VARIANT},${run_type},${run_num},${cpu},${wall_time},${values},${thunks},${sets_bytes},${gc_time},${gc_fraction},${nrAvoided},${nrLookups}"
    echo "$csv_row" >> "$CSV_FILE"
    echo "$csv_row"
}

# ── Main ─────────────────────────────────────────────────────────────────────

# ---- Cold run (1 iteration) ----
echo "[bench] ${VARIANT} Flushing nix eval cache..." >&2
rm -rf ~/.cache/nix/eval-cache-v* ~/.cache/nix/eval-cache.lock 2>/dev/null

echo "[bench] ${VARIANT} Warming up (--refresh cache-bust)..." >&2
nix eval --refresh "${NIX_EVAL_ARGS[@]}" "$NIX_EXPR" > /dev/null 2>&1

run_bench "cold" "1" "1"

# ---- Warm runs (3 iterations) ----
for i in 1 2 3; do
    run_bench "warm" "$i" "3"
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo "[bench] ${VARIANT} Done. Results: ${CSV_FILE}" >&2
