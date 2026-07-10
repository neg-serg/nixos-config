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

## Development (`scripts/dev/`)

- [../../scripts/dev/check-markdown-language.sh](../../scripts/dev/check-markdown-language.sh) —
  enforce Markdown language annotations locally.
