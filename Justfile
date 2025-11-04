# Run utilities for development

set shell := ["bash", "-cu"]

# Generate aggregated options docs into docs/*.md
gen-options:
    scripts/gen-options.sh

# Generate and commit options docs if there are changes
gen-options-commit:
    set -euo pipefail
    just gen-options
    if git -C . diff --quiet -- docs; then \
      echo "No changes in docs"; \
    else \
      git add docs; \
      git commit -m "[docs/options] Regenerate options docs"; \
    fi

# Format the repo via flake formatter
fmt:
    nix fmt

# Detect V-Cache CPU set and print recommended kernel masks
cpu-masks:
    scripts/cpu-recommend-masks.sh
