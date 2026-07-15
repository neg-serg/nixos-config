# Plan: TIER 2 Rust rewrites — rofiw, pwroute, amnezia-tun

## Goal

Rewrite 3 borderline bash scripts as Rust CLI tools, eliminating ~450 LOC of bash + 120 LOC Python.

## Architecture

```
packages/rofiw/          # ~250 LOC — rofi wrapper with auto-offsets
packages/pwroute/         # ~350 LOC — PipeWire audio routing for RME AIO Pro
packages/amnezia-tun/     # ~250 LOC — AmneziaVPN config decoder
```

All 3 use `clap` + `serde_json`. `pwroute` adds `regex`. `amnezia-tun` adds `base64` + `regex`.

## TODOs

1. [ ] Create `packages/rofiw/` — Rust binary replacing `files/rofi/rofi-wrapper.sh` (123 LOC bash)
   - `clap` for arg parsing (pass-through to rofi + intercept `-theme`, `-xoffset`, etc.)
   - `serde_json` for reading Quickshell `.theme.json` (panel offsets) and `hyprctl -j monitors` (scale)
   - Pure Rust offset math replacing `awk`/`sed`/`grep`
   - `exec rofi` at the end — hyprctl stays as subprocess
   - Wire: `packages/overlays/gui.nix`, replace `@ROFI_BIN@`/`@JQ_BIN@`/`@HYPRCTL_BIN@` with clap env defaults
   - Acceptance: `rofiw -theme catppuccin -show drun` works

2. [ ] Create `packages/pwroute/` — Rust binary replacing `modules/hardware/audio/hdspe/pw-route.sh` (190 LOC zsh)
   - `clap` subcommands: `{aes,an,spdif,phones}` for direct routing, `toggle` (cycle aes↔an), `current`, `status`, `list` (JSON)
   - Route config from HashMap (hardcoded initially, later from `/etc/audio/routing.yaml`)
   - `pw-link` subprocess for link management (`-l`, `-d`, connect)
   - `pw-cli` subprocess for sink discovery
   - Replace `awk`/`grep` parsing with Rust regex
   - Wire: `packages/overlays/media.nix`, update `hdspe/default.nix` to use `pkgs.pwroute` instead of `writeScriptBin`
   - Remove `pkgs.zsh` dependency from the service, keep `pkgs.pipewire`
   - Acceptance: `pwroute list` returns JSON, `pwroute aes` routes to AES

3. [ ] Create `packages/amnezia-tun/` — Rust binary replacing `amnezia-import-tun-config.sh` (136 LOC bash + Python)
   - `clap` subcommands: `import` (default), `show-path`, `check`
   - `regex` for extracting `last_config=@ByteArray(...)` and `serversList="..."` patterns
   - `base64` crate for decoding the ByteArray
   - `serde_json` for JSON parsing/unescaping (use `from_str` trick: wrap in quotes to handle `\n`/`\"`)
   - Pure Rust `std::fs::set_permissions` instead of `chmod`
   - Wire: `packages/overlays/tools.nix`, update `vpn-scripts/default.nix` to drop python3 dependency if unused
   - Acceptance: `amnezia-tun import` decodes config, `amnezia-tun check` verifies

4. [ ] Delete old scripts after verification:
   - `files/rofi/rofi-wrapper.sh`
   - `modules/hardware/audio/hdspe/pw-route.sh`
   - `modules/system/net/vpn-scripts/scripts/amnezia-import-tun-config.sh`

5. [ ] Update `hdspe/default.nix` — replace `writeScriptBin "pw-route"` with `pkgs.pwroute`, remove zsh + gawk deps

6. [ ] Update `vpn-scripts/default.nix` — replace bash+python script with `pkgs.amnezia-tun`

7. [ ] Check quickshell Audio.qml references — ensure `pwroute` binary name matches (currently calls `pw-route`)

## Final Verification Wave

F1. [ ] `cargo build --release` in each of 3 packages succeeds
F2. [ ] `nix build .#rofiw .#pwroute .#amnezia-tun` succeeds
F3. [ ] `nh os switch /etc/nixos` rebuilds without errors
F4. [ ] `pwroute list` returns valid JSON
F5. [ ] `amnezia-tun show-path` prints ~/.config/sing-box-tun/config.json
