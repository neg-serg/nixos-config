# Plan: `hwctl` — Rust CLI for CPU/fan hardware control

## Architecture

```
packages/hwctl/
├── Cargo.toml
├── Cargo.lock
├── src/
│   ├── main.rs          # CLI entry, subcommand dispatch (clap derive)
│   ├── cpu.rs           # boost toggle, V-Cache masks
│   ├── fan/
│   │   ├── mod.rs
│   │   ├── auto.rs       # fan-auto → restart fancontrol service
│   │   ├── manual.rs     # fan-manual → set fixed PWM
│   │   ├── setup.rs      # fancontrol-setup → auto-generate config (largest, ~120 lines)
│   │   ├── reapply.rs    # fancontrol-reapply → post-resume hook
│   │   └── test_stop.rs  # fan-stop-capability-test → PWM=0 probe
│   └── hwmon.rs          # sysfs hwmon discovery helpers (shared by fan/*)
├── build.rs              # (optional: just defaults)
└── default.nix            # buildRustPackage call
```

## Dependencies (Cargo.toml)

- `clap = { version = "4", features = ["derive"] }` — CLI
- `anyhow = "1"` — error handling
- `serde = { version = "1", features = ["derive"] }` — only if config generation benefits
- Stdlib: `std::fs`, `std::process::Command`, `std::path::Path`

Keep deps minimal. No `tokio`, no `sysinfo`, no `nix` crate — raw sysfs reads are fine.

## Subcommands

```
hwctl cpu boost    [status|on|off|toggle]
hwctl cpu masks
hwctl fan auto
hwctl fan manual   [PWM=70]
hwctl fan setup    [--min-temp 30] [--max-temp 70] [--min-pwm 50] [--max-pwm 255] [--allow-stop]
hwctl fan reapply  [post]
hwctl fan test-stop [--include-cpu] [--device PATH] [--wait 6] [--threshold 50] [--list]
```

## TODOs

1. [ ] Create `packages/hwctl/` with `Cargo.toml`, `default.nix`, and `buildRustPackage` wiring
   - Wire into `packages/overlays/tools.nix` under `pkgs.hwctl`
   - Wire into `flake/packages` if needed for `nix run`
   - Acceptance: `nix build .#hwctl` produces a binary

2. [ ] Implement `src/hwmon.rs` — sysfs hwmon scanner
   - Discover `/sys/class/hwmon/hwmon*/` devices
   - Detect Nuvoton (`nct*` in `name`)
   - Detect AMDGPU (`amdgpu` in `name`)
   - Read PWM channels, fan inputs, temp inputs
   - Acceptance: unit test on mock sysfs tree

3. [ ] Implement `cpu boost [status|on|off|toggle]`
   - Read/write `/sys/devices/system/cpu/cpufreq/boost`
   - Auto-detect boost interface
   - Acceptance: `hwctl cpu boost status` prints current state

4. [ ] Implement `cpu masks`
   - Parse `/sys/devices/system/cpu/cpu*/cache/index3/shared_cpu_map`
   - Find largest L3 group (V-Cache CCD)
   - Print recommended `nohz_full`, `rcu_nocbs`, `isolcpus`, `irqaffinity`
   - Acceptance: prints sensible mask for AMD X3D

5. [ ] Implement `fan auto`
   - `systemctl restart fancontrol` via subprocess
   - Root check
   - Acceptance: restarts service

6. [ ] Implement `fan manual [PWM]`
   - Stop fancontrol, set nct6799 PWM channels 1,4,5,6,7 to manual mode + fixed value
   - Skip GPU channels (2,3)
   - Root check
   - Acceptance: sets PWM, warns about GPU

7. [ ] Implement `fan setup` (largest — ~120 lines)
   - Probe Nuvoton hwmon, k10temp Tdie/Tctl, optional amdgpu
   - Derive MINSTART/MINSTOP thresholds
   - Generate `/etc/fancontrol.auto`, symlink to `/etc/fancontrol`
   - Env vars become CLI flags
   - Root check
   - Acceptance: generates valid fancontrol config

8. [ ] Implement `fan reapply [post]`
   - Post-resume: set all nct* PWM channels to manual mode, restart fancontrol
   - Acceptance: re-enables manual control after suspend

9. [ ] Implement `fan test-stop [--include-cpu] [--device ...]`
   - Probe each PWM channel: save original value, set 0, wait, check RPM
   - Restore original values after test
   - Skip CPU/PUMP/AIO by default
   - `--list` for dry-run inventory
   - Acceptance: safely tests which fans stop at PWM=0

10. [ ] Delete 7 old shell scripts from `scripts/hw/`
    - Acceptance: scripts gone, `hwctl` still works

11. [ ] Add `hwctl` to `environment.systemPackages` in the appropriate module
    - Best place: `modules/hardware/` or `modules/user/nix-maid/cli/`
    - Acceptance: `which hwctl` after rebuild

## Final Verification Wave

F1. [ ] `cargo build --release` in `packages/hwctl/` succeeds
F2. [ ] `nix build .#hwctl` succeeds via overlay
F3. [ ] `hwctl --help` lists all subcommands with descriptions
F4. [ ] `hwctl cpu masks` prints recommendations (non-root, safe)
F5. [ ] `hwctl fan test-stop --list` lists channels (non-root, read-only)
F6. [ ] `hwctl cpu boost status` works (non-root, read-only)
