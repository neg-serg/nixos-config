# Script Catalog

## Hardware — `hwctl` (Rust CLI)

All hardware control scripts have been consolidated into a single Rust CLI:

- `hwctl cpu boost [status|on|off|toggle]` — toggle CPU boost
- `hwctl cpu masks` — suggest kernel masks for V-Cache CPUs
- `hwctl fan setup [--min-temp N] ...` — generate `/etc/fancontrol`
- `hwctl fan reapply [--gpu]` — reapply fan curves after resume
- `hwctl fan auto` — restore automatic fan control
- `hwctl fan manual [PWM]` — set fixed fan speed
- `hwctl fan test-stop [--list] ...` — check if fans can safely stop

See [../../packages/hwctl/src/main.rs](../../packages/hwctl/src/main.rs) for the full interface.

## Operations (`scripts/ops/`)

- [../../scripts/ops/collect-nextcloud-cli-debug.sh](../../scripts/ops/collect-nextcloud-cli-debug.sh)
  — capture nextcloudcmd logs and diagnostics.
- [../../scripts/ops/collect-quickshell-metrics.sh](../../scripts/ops/collect-quickshell-metrics.sh)
  — snapshot Quickshell metrics for support dumps.

## Development (`scripts/dev/`)

- [../../scripts/dev/check-markdown-language.sh](../../scripts/dev/check-markdown-language.sh) —
  enforce Markdown language annotations locally.
- [../../scripts/dev/diff-preview.sh](../../scripts/dev/diff-preview.sh) — build new system closure
  and show `nvd diff` against current system; flags: `--new-only` to see only added packages. Use
  via `just diff-preview [host]` or `just diff-preview-new [host]`.
- [../../scripts/dev/gen-options.sh](../../scripts/dev/gen-options.sh) — build options/module
  documentation artifacts.
