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
# greeter is a deliberate fork of the tree with its own singletons. Reported as
# a count — a new finding of these kinds moves it, which is the signal — and
# capped so a burst fails instead of scrolling past.
INHERENT_CAP=160
inherent=$(grep -cE "\[(missing-type|missing-property|unresolved-type|uncreatable-type|incompatible-type|property-override|import|signal-handler-parameters|duplicate-property-binding)\]" "$REPORT" || true)

echo ""
echo "defect-kind findings: $defects"
echo "known-inherent findings: ${inherent:-0} (cap $INHERENT_CAP)"

if [ "${defects:-0}" -gt 0 ]; then
  echo "FAILED: $defects finding(s) of a kind that indicates a real defect"
  exit 1
fi
if [ "${inherent:-0}" -gt "$INHERENT_CAP" ]; then
  echo "FAILED: known-inherent findings grew past the cap — inspect the report"
  exit 1
fi
echo "OK: no defect-kind findings"
