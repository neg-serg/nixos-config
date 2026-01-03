#!/usr/bin/env bash
# Check QML files for syntax errors using qmlformat --dry-run.
# qmlformat can parse QML without requiring module dependencies.

set -euo pipefail

REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2> /dev/null || pwd)}"

# Directories containing QML files
QML_DIRS=(
  "$REPO_ROOT/files/quickshell"
)

echo "Checking QML syntax..."

error_count=0
checked_count=0

for dir in "${QML_DIRS[@]}"; do
  if [[ ! -d "$dir" ]]; then
    echo "Directory not found: $dir"
    continue
  fi

  while IFS= read -r -d '' qml_file; do
    ((checked_count++)) || true

    # Use qmlformat --dry-run to check syntax
    # If the file has syntax errors, qmlformat will fail
    if ! output=$(qmlformat --dry-run "$qml_file" 2>&1 > /dev/null); then
      echo "ERROR: $qml_file"
      echo "$output" | head -5
      echo ""
      ((error_count++)) || true
    fi
  done < <(find "$dir" -name "*.qml" -type f -print0)
done

echo ""
echo "Checked $checked_count QML files"

if [[ $error_count -gt 0 ]]; then
  echo "FAILED: $error_count file(s) have syntax errors"
  exit 1
fi

echo "All QML files have valid syntax!"
