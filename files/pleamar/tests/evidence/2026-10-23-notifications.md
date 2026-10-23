# pleamar report · 2026-10-23 14:05

pleamar 0.4.11 · measured 8 s · notifications

## Verdict

- **notifications:** smooth · 60 fps against 60 Hz

## The machine

- **System:** NixOS 26.11 (Zokor)
- **Kernel:** 7.3.0-rc6
- **CPU:** AMD Ryzen 9 9950X3D 16-Core Processor · 32 threads
- **CPU frequency policy:** powersave governor · amd-pstate-epp driver · EPP balance_performance
- **Memory:** 60.5 GB · 24.2 GB available · swap in use 2.3 GB
- **Session:** wayland · Hyprland
- **GPU:** card1 · AMD 0x1002:0x7550 · driver amdgpu · 0000:03:00.0

## While measuring

- **CPU busy (whole system):** 3%
- **Load average:** 1.62 3.92 5.76
- **Core clock (mean of the cores):** 3370 MHz on average · 2286–5368
- **CPU temperature:** 63 °C on average · 65 at most
- **GPU busy (0000:03:00.0):** 9% on average · 34% at most
- **GPU temperature (0000:03:00.0):** 52 °C on average · 53 at most
- **Most CPU (% of a core):** MainThread 46% · windows 9% · .pleamar-wrappe 5% · .kitty-wrapped 3% ·
  Hyprland 2% · vivaldi-bin 2%

## notifications

- **Scene:** 2764 instructions, 1761 properties, 360 rules, 408 zones
- **Card:** AMD Radeon RX 9070 XT (RADV GFX1201) · Vulkan · discrete · driver radv Mesa 26.2.4 ·
  mailbox
- **Card memory in use:** 18 MB
- **Surface:** DP-2 · 1920×1080 · 60 Hz · scale 1 · closed
- **Measured:** 8 s · animating 100% of it · 496 frames
- **Frame time:** median 16.7 · p95 16.7 · p99 16.7 · worst 16.8 ms (the screen gives 16.7)
- **Late frames:** 0 (0.0%) over 1.5 periods of the screen's · 0 over 2.5 (a frame or more lost)
- **Process CPU:** 0% of a core
- **Memory (RSS):** 66 MB

| per round (ms)         | on average | in the late ones |
| ---------------------- | ---------- | ---------------- |
| input                  | 0.00       | —                |
| rules and springs      | 0.03       | —                |
| windows' frames        | 0.00       | —                |
| compose                | 0.01       | —                |
| regions                | 0.01       | —                |
| paint                  | 0.00       | —                |
| rest                   | 8.05       | —                |
| waiting for the screen | 8.56       | —                |

The worst frames:

- 17 ms · input 0.0 · rules 0.0 · windows 0.0 · compose 0.0 · regions 0.0 · paint 0.0 · rest 8.1 ·
  waiting 8.5
- 17 ms · input 0.0 · rules 0.0 · windows 0.0 · compose 0.0 · regions 0.0 · paint 0.0 · rest 8.1 ·
  waiting 8.6
- 17 ms · input 0.0 · rules 0.0 · windows 0.0 · compose 0.0 · regions 0.0 · paint 0.0 · rest 8.1 ·
  waiting 8.6
- 17 ms · input 0.0 · rules 0.0 · windows 0.0 · compose 0.0 · regions 0.0 · paint 0.0 · rest 8.1 ·
  waiting 8.6
- 17 ms · input 0.0 · rules 0.0 · windows 0.0 · compose 0.0 · regions 0.0 · paint 0.0 · rest 8.1 ·
  waiting 8.6
