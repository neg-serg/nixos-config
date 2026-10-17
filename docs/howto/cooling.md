# Cooling and fan control (quiet profile)

- Enable sensors and a quiet fan curve via `hardware.cooling.*` (module:
  `modules/hardware/cooling.nix`).
- For typical ASUS/Nuvoton motherboards, the module loads `nct6775` and generates `/etc/fancontrol`
  on boot.
- Optional: include AMD GPU fan in the same profile
  (`hardware.cooling.gpuFancontrol.enable = true;`).

Example (quiet, safe defaults):

```nix
{
  hardware.cooling = {
    enable = true;
    autoFancontrol.enable = true;  # generate conservative quiet curve
    gpuFancontrol.enable = true;   # include AMDGPU pwm1 with a quiet curve
    # Optional tweaks (defaults shown):
    # autoFancontrol.minTemp = 35;  # °C to start ramping
    # autoFancontrol.maxTemp = 75;  # °C for max fan speed
    # autoFancontrol.minPwm  = 70;  # 0–255, avoid stall while quiet
    # autoFancontrol.maxPwm  = 255; # 0–255
    # autoFancontrol.hysteresis = 3;  # °C
    # autoFancontrol.interval  = 2;   # seconds
    # autoFancontrol.allowStop = false;      # allow fans to fully stop below minTemp
    # autoFancontrol.gpuPwmChannels = [ ];   # PWM channels (e.g., [2 3]) to follow GPU temp
  };
}
```

- Notes:
- The generator uses CPU temperature (`k10temp`) to drive all motherboard PWM channels (nct6775).
- If `gpuFancontrol.enable = true`, GPU fan (amdgpu pwm1) is driven by GPU temp (prefer junction
  sensor when available).
- If `/etc/fancontrol` already exists, it is backed up once to `/etc/fancontrol.backup` and replaced
  with a symlink to `/etc/fancontrol.auto`.
- GPU fans remain managed by the GPU driver; only motherboard PWM headers are targeted.
  - Exception: when `gpuFancontrol.enable = true`, we switch `pwm1_enable` to manual and fancontrol
    takes over.

## Fan stop capability test

- Utility: `hwctl fan test-stop` checks which motherboard PWM channels can fully stop at 0%.
- Safe by default: skips CPU/PUMP/AIO headers; restores original settings after probing.
- Usage examples:
  - List channels only: `sudo hwctl fan test-stop --list`
  - Test chassis fans: `sudo hwctl fan test-stop`
  - Include CPU/PUMP (at your own risk): `sudo hwctl fan test-stop --include-cpu`
- Options: `--device <hwmonN|nct6798>`, `--wait <sec>` (default 6), `--threshold <rpm>` (default
  50).
- Note: stop `fancontrol` during the test for accurate results: `sudo systemctl stop fancontrol`.
