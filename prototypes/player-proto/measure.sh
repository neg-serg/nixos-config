#!/usr/bin/env bash
# Startup measurement: process start -> first presented frame.
# The binary stamps its exact process age (CLOCK_BOOTTIME minus /proc/self/stat starttime),
# so no launcher-side timing is needed. The binary is exec'd directly here: starttime is set
# at fork(), so a wrapper script that does work before exec would be charged to the app.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
runs=${1:-10}
bin=${PROTO_BIN:-$here/target/release/player-proto}
[ -s "$here/.libs" ] || "$here/libs.sh" > "$here/.libs"
libs=$(cat "$here/.libs")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for i in $(seq 1 "$runs"); do
  env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$libs" "$bin" --frames 1 --json > "$tmp/out.json" 2>"$tmp/err.log" || {
    echo "run $i failed:"; tail -5 "$tmp/err.log"; exit 1; }
  rg -o '"first_present":\{"rel_ms":[0-9.]+,"proc_ms":[0-9.]+' "$tmp/out.json" >> "$tmp/all.txt"
done
python3 - "$tmp/all.txt" <<'PY'
import re, sys
rows = []
for line in open(sys.argv[1]):
    m = re.search(r'first_present":\{"rel_ms":([0-9.]+),"proc_ms":([0-9.]+)', line)
    if m:
        rows.append((float(m.group(1)), float(m.group(2))))
if not rows:
    sys.exit("no first_present marks collected")
rel = sorted(r[0] for r in rows)
proc = sorted(r[1] for r in rows)
def q(v, p): return v[min(len(v) - 1, round(p * (len(v) - 1)))]
print(f"runs: {len(rows)}")
print(f"main    -> first_present  min {rel[0]:6.1f}  med {q(rel,0.5):6.1f}  max {rel[-1]:6.1f} ms")
print(f"process -> first_present  min {proc[0]:6.1f}  med {q(proc,0.5):6.1f}  max {proc[-1]:6.1f} ms")
PY
