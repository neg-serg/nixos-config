# pleamar report · 2026-10-28 14:05

pleamar 0.4.29 · measured 15 s · lock

## Verdict

- **lock:** smooth · 240 fps against 240 Hz

## The machine

- **System:** NixOS 26.11 (Zokor)
- **Kernel:** 7.3.0-rc6
- **CPU:** AMD Ryzen 9 9950X3D 16-Core Processor · 32 threads
- **CPU frequency policy:** powersave governor · amd-pstate-epp driver · EPP balance_performance
- **Memory:** 60.5 GB · 20.2 GB available · swap in use 0.0 GB
- **Session:** wayland · Hyprland
- **GPU:** card1 · AMD 0x1002:0x7550 · driver amdgpu · 0000:03:00.0

## While measuring

- **CPU busy (whole system):** 5%
- **Load average:** 1.94 2.06 2.11
- **Core clock (mean of the cores):** 4204 MHz on average · 2906–5530
- **CPU temperature:** 64 °C on average · 66 at most
- **GPU busy (0000:03:00.0):** 7% on average · 8% at most
- **GPU temperature (0000:03:00.0):** 54 °C on average · 55 at most
- **Most CPU (% of a core):** .pleamar-wrappe 50% · MainThread 24% · windows 9% · systemd 5% ·
  .vicinae-file-i 5% · Hyprland 2%

## lock

- **Scene:** 51 instructions, 17 properties, 3 rules, 4 zones
- **Card:** AMD Radeon RX 9070 XT (RADV GFX1201) · Vulkan · discrete · driver radv Mesa 26.2.4 ·
  mailbox
- **Card memory in use:** 319 MB
- **Surface:** DP-2 (lock) · 3840×2160 · 240 Hz · scale 2 · sets the pace
- **Measured:** 15 s · animating 100% of it · 3606 frames
- **Frame time:** median 4.2 · p95 4.2 · p99 4.3 · worst 5.2 ms (the screen gives 4.2)
- **Late frames:** 0 (0.0%) over 1.5 periods of the screen's · 0 over 2.5 (a frame or more lost)
- **Process CPU:** 1% of a core
- **Memory (RSS):** 56 MB

| per round (ms)         | on average | in the late ones |
| ---------------------- | ---------- | ---------------- |
| input                  | 0.00       | —                |
| rules and springs      | 0.00       | —                |
| windows' frames        | 0.00       | —                |
| compose                | 0.00       | —                |
| regions                | 0.00       | —                |
| paint                  | 0.02       | —                |
| rest                   | 0.00       | —                |
| waiting for the screen | 4.14       | —                |

The worst frames:

- 5 ms · input 0.0 · rules 0.0 · windows 0.0 · compose 0.1 · regions 0.0 · paint 1.0 · rest 0.0 ·
  waiting 4.1
- 5 ms · input 0.0 · rules 0.0 · windows 0.0 · compose 0.1 · regions 0.0 · paint 1.0 · rest 0.0 ·
  waiting 4.1
- 5 ms · input 0.0 · rules 0.0 · windows 0.0 · compose 0.1 · regions 0.0 · paint 0.8 · rest 0.0 ·
  waiting 4.1
- 5 ms · input 0.0 · rules 0.0 · windows 0.0 · compose 0.1 · regions 0.0 · paint 0.8 · rest 0.0 ·
  waiting 4.1
- 5 ms · input 0.0 · rules 0.0 · windows 0.0 · compose 0.1 · regions 0.0 · paint 0.8 · rest 0.0 ·
  waiting 4.1
