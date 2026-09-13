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
- [../../scripts/dev/check-nix-maid-app-dirs.sh](../../scripts/dev/check-nix-maid-app-dirs.sh) —
  verify every directory under `modules/user/nix-maid/apps` is either a real module or listed in the
  filter in that directory's `default.nix`; a plugin directory missing from that list breaks the
  whole system evaluation. Wired into `just check` as the `nix-maid-app-dirs-guard` flake check.
