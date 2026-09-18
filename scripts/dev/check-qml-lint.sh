#!/usr/bin/env bash
# Deep QML analysis (qmllint) for files/quickshell.
#
# `check-qml-syntax.sh` runs qmlformat, which only proves that a file parses.
# qmllint also resolves expressions, and that is what catches the defects that
# hurt here: a property that does not exist (read as undefined and absorbed by
# the expression around it), a singleton registered as a plain type, a dead
# binding. Four such bugs were found the first time this was configured
# properly — the list is in files/quickshell/.qmllint.ini.
#
# Configuration matters more than the tool: without import paths qmllint reports
# "module not found" for everything it cannot see (~9.7k warnings for this tree)
# and the real findings drown in that. The Qt paths are read out of the deployed
# qs wrapper (which builds QML2_IMPORT_PATH for exactly this stack), the
# Quickshell paths out of its package, and every qmldir in the tree is passed
# with -i so the qs.* modules resolve.
#
# Exit status: 1 when a defect-kind finding appears, or when the known-inherent
# count grows past its cap (see below).
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "${1:-}")"
QML_DIR="$REPO_ROOT/files/quickshell"

[ -d "$QML_DIR" ] || { echo "Directory not found: $QML_DIR"; exit 1; }
command -v qmllint >/dev/null 2>&1 || { echo "qmllint not found (qt6.qtdeclarative)"; exit 1; }

# --- import paths ----------------------------------------------------------
collect_paths() {
  local target="$1"
  # `qs` is a thin script that execs `.qs-wrapped`, and it is the latter that
  # builds QML2_IMPORT_PATH out of the Qt/Quickshell module dirs of this stack.
  # Both are scanned: whichever one carries the paths today, does tomorrow.
  for file in "$target" "$(dirname "$target")/.qs-wrapped"; do
    [ -f "$file" ] || continue
    grep -oE "/nix/store/[a-z0-9]+-[A-Za-z0-9._+-]+/lib/qt-6/qml" "$file" 2>/dev/null || true
  done | sort -u
}

QS_WRAPPER="$(command -v qs || true)"
IMPORT_PATHS=""
if [ -n "$QS_WRAPPER" ]; then
  IMPORT_PATHS="$(collect_paths "$(readlink -f "$QS_WRAPPER")")"
fi
IMPORT_PATHS="$(printf '%s\n' "$IMPORT_PATHS" | sed '/^$/d' | sort -u | paste -sd: -)"

if [ -z "$IMPORT_PATHS" ]; then
  echo "WARNING: no Qt/Quickshell QML module paths found — qmllint will report" >&2
  echo "         \"module not found\" for the framework imports." >&2
fi

cd "$QML_DIR"
mapfile -t MODULE_DIRS < <(find . -name qmldir -not -path "./qmldir" -printf '%h\n' | sort -u)
IMPORT_ARGS=()
for dir in "${MODULE_DIRS[@]}"; do
  IMPORT_ARGS+=(-i "$dir/qmldir")
done
mapfile -t FILES < <(find . -name "*.qml" -not -path "*/overview/*" | sort)

echo "qmllint: ${#FILES[@]} files, ${#MODULE_DIRS[@]} modules, $(printf '%s' "$IMPORT_PATHS" | tr ':' '\n' | wc -l) import paths"

REPORT="$(mktemp)"
trap 'rm -f "$REPORT"' EXIT
QML_IMPORT_PATH="$IMPORT_PATHS" qmllint -E -I . "${IMPORT_ARGS[@]}" "${FILES[@]}" 2>&1 \
  | grep -E "^(Warning|Error)" > "$REPORT" || true

# Findings that mean "this code cannot do what it says" — always fail. They are
# at zero today, and they are what the earlier defects (a property that does not
# exist, a dead binding, a singleton used as a plain type) would have tripped.
DEFECT_KINDS=(
  unintentional-empty-block
  confusing-expression-statement
  var-used-before-declaration
  unreachable-code
  read-only-property
  non-list-property
  invalid-lint-directive
  enums-are-not-types
  equality-type-coercion
  unterminated-case
  with
  comma
  eval
)

defects=0
for kind in "${DEFECT_KINDS[@]}"; do
  count=$(grep -c "\[$kind\]" "$REPORT" || true)
  if [ "${count:-0}" -gt 0 ]; then
    echo ""
    echo "DEFECT [$kind] x$count:"
    grep "\[$kind\]" "$REPORT" | head -20
    defects=$((defects + count))
  fi
done

# Known-inherent: qmllint cannot see through Quickshell's plugin types or the Qt
# framework's own members (Qt.callLater, Screen.virtualGeometry, …), and the
# greeter is a deliberate fork of the tree with its own singletons. The per-
# category numbers live in .qmllint-baseline.tsv, with the reason for each; a
# category above its baseline fails, and one below it is printed as progress.
# Counting per category rather than in total is what keeps a regression legible:
# a new missing-property cannot hide inside a drop of unqualified.
BASELINE_FILE=".qmllint-baseline.tsv"
baseline_violations=0
inherent=0
if [ -f "$BASELINE_FILE" ]; then
  while IFS=$'\t' read -r category expected _rest; do
    expected=${expected:-0}
    [ "$category" = "__observed" ] && continue
    case "$category" in ""|"#"*) continue ;; esac
    count=$(grep -c "\[$category\]" "$REPORT" || true)
    count=${count:-0}
    inherent=$((inherent + count))
    if [ "$count" -gt "$expected" ]; then
      printf 'REGRESSION    %-28s %4d   (baseline %s)\n' "$category" "$count" "$expected"
      baseline_violations=$((baseline_violations + 1))
    elif [ "$count" -lt "$expected" ]; then
      printf 'improved      %-28s %4d   (baseline %s)\n' "$category" "$count" "$expected"
    fi
  done < "$BASELINE_FILE"
else
  echo "WARNING: $BASELINE_FILE not found — inherent findings are not compared" >&2
  inherent=$(grep -cE "\[(unqualified|missing-property|unresolved-type|uncreatable-type|incompatible-type|property-override|import|signal-handler-parameters|duplicate-property-binding|missing-type)\]" "$REPORT" || true)
fi

echo ""
echo "defect-kind findings: $defects"
echo "known-inherent findings: $inherent"

# QMLLINT_SHOW=1 prints the findings that are not in the disabled category, for
# when a number has to be looked at.
if [ "${QMLLINT_SHOW:-0}" = "1" ]; then
  echo ""
  grep -vE "\[unqualified\]" "$REPORT" | head -200
fi

if [ "${defects:-0}" -gt 0 ]; then
  echo "FAILED: $defects finding(s) of a kind that indicates a real defect"
  exit 1
fi
if [ "$baseline_violations" -gt 0 ]; then
  echo "FAILED: $baseline_violations categories above their baseline (see .qmllint-baseline.tsv)"
  exit 1
fi

# Record what was observed, into the file the baseline lives in (the numbers stay
# in the reviewed tree, not in a hidden cache). Only lowered automatically: a
# category that grew would have failed above, and a human has to look at that
# before the number moves.
if [ -f "$BASELINE_FILE" ]; then
  tmp="$(mktemp)"
  while IFS=$'\t' read -r category expected _rest; do
    case "$category" in ""|"#"*) printf '%s\n' "$category" >> "$tmp"; continue ;; esac
    count=$(grep -c "\[$category\]" "$REPORT" || true)
    count=${count:-0}
    [ "$count" -lt "$expected" ] && expected="$count"
    printf '%s\t%s\n' "$category" "$expected" >> "$tmp"
  done < "$BASELINE_FILE"
  mv "$tmp" "$BASELINE_FILE"
fi
echo "OK: no defect-kind findings"
