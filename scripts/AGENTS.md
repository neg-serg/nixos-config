# AGENTS usage for scripts/

Scope
- Applies to utility scripts under `scripts/`.
- Root AGENTS rules still apply.

Guidelines
- Scripts are Bash-oriented; keep `#!/usr/bin/env bash` with `set -euo pipefail` and avoid nonportable bashisms unless necessary.
- Keep them non-root-friendly and configurable via flags/env vars; do not hardcode secrets or machine-specific paths.
- Document usage inline with short comments or help text; prefer reusing existing helpers over creating new binaries.
- Run shellcheck when touching scripts if available; keep behavior changes minimal and tested where possible.
