# Run utilities for development (requires `nix develop` to get `just`)

set shell := ["bash", "-cu"]

# Generate aggregated options docs into docs/*.md
options:
    scripts/gen-options.sh

# Format the repo via flake formatter
fmt:
    nix fmt

