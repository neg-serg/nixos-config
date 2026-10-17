#
# Cooling and fan control (quiet profile)
# (moved out of the docs tree; keep it in sync with the code it describes)
#
#
# - Enable sensors and a quiet fan curve via `hardware.cooling.*` (module:
#   `modules/hardware/cooling.nix`).
# - For typical ASUS/Nuvoton motherboards, the module loads `nct6775` and generates `/etc/fancontrol`
#   on boot.
# - Optional: include AMD GPU fan in the same profile
#   (`hardware.cooling.gpuFancontrol.enable = true;`).
#
# Example (quiet, safe defaults):
#
#     {
#       hardware.cooling = {
#         enable = true;
#         autoFancontrol.enable = true;  # generate conservative quiet curve
#         gpuFancontrol.enable = true;   # include AMDGPU pwm1 with a quiet curve
#         # Optional tweaks (defaults shown):
#         # autoFancontrol.minTemp = 35;  # °C to start ramping
#         # autoFancontrol.maxTemp = 75;  # °C for max fan speed
#         # autoFancontrol.minPwm  = 70;  # 0–255, avoid stall while quiet
#         # autoFancontrol.maxPwm  = 255; # 0–255
#         # autoFancontrol.hysteresis = 3;  # °C
#         # autoFancontrol.interval  = 2;   # seconds
#         # autoFancontrol.allowStop = false;      # allow fans to fully stop below minTemp
#         # autoFancontrol.gpuPwmChannels = [ ];   # PWM channels (e.g., [2 3]) to follow GPU temp
#       };
#     }
#
# - Notes:
# - The generator uses CPU temperature (`k10temp`) to drive all motherboard PWM channels (nct6775).
# - If `gpuFancontrol.enable = true`, GPU fan (amdgpu pwm1) is driven by GPU temp (prefer junction
#   sensor when available).
# - If `/etc/fancontrol` already exists, it is backed up once to `/etc/fancontrol.backup` and replaced
#   with a symlink to `/etc/fancontrol.auto`.
# - GPU fans remain managed by the GPU driver; only motherboard PWM headers are targeted.
#   - Exception: when `gpuFancontrol.enable = true`, we switch `pwm1_enable` to manual and fancontrol
#     takes over.
#
# ## Fan stop capability test
#
# - Utility: `hwctl fan test-stop` checks which motherboard PWM channels can fully stop at 0%.
# - Safe by default: skips CPU/PUMP/AIO headers; restores original settings after probing.
# - Usage examples:
#   - List channels only: `sudo hwctl fan test-stop --list`
#   - Test chassis fans: `sudo hwctl fan test-stop`
#   - Include CPU/PUMP (at your own risk): `sudo hwctl fan test-stop --include-cpu`
# - Options: `--device <hwmonN|nct6798>`, `--wait <sec>` (default 6), `--threshold <rpm>` (default
#   50).
# - Note: stop `fancontrol` during the test for accurate results: `sudo systemctl stop fancontrol`.

{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.hardware.cooling or { };
  systemdUser = config.lib.neg.systemdUser;
in
{
  options.hardware.cooling = {
    enable = lib.mkEnableOption "Enable cooling stack (sensors + optional fancontrol).";

    loadNct6775 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Load the Nuvoton/ASUS Super I/O PWM driver (nct6775) for motherboard fan control.";
    };

    autoFancontrol = {
      enable = lib.mkEnableOption "Autogenerate /etc/fancontrol at boot with a conservative quiet profile.";

      minTemp = lib.mkOption {
        type = lib.types.int;
        default = 35;
        description = "Temperature (°C) where fans start ramping (quiet).";
      };
      maxTemp = lib.mkOption {
        type = lib.types.int;
        default = 75;
        description = "Temperature (°C) for max fan speed.";
      };
      minPwm = lib.mkOption {
        type = lib.types.int;
        default = 70;
        description = "Minimum PWM value (0–255) to avoid fan stall (quiet).";
      };
      maxPwm = lib.mkOption {
        type = lib.types.int;
        default = 255;
        description = "Maximum PWM value (0–255).";
      };
      hysteresis = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = "Hysteresis (°C) for fancontrol transitions.";
      };
      interval = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Polling interval (seconds).";
      };

      allowStop = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Allow PWM-controlled fans to fully stop below the minimum temperature.
          Uses a higher spin-up threshold to avoid stall when ramping from 0.
        '';
      };

      minStartOverride = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = ''
          Optional absolute MINSTART value (0–255) used when allowStop = true
          to guarantee spin-up from a stopped fan. If null, defaults to 100.
        '';
      };

      gpuPwmChannels = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [ ];
        description = ''
          Motherboard PWM channel numbers (e.g., [ 2 3 ]) that should follow GPU
          temperature instead of CPU temperature for case airflow near the GPU.
          Other channels will follow CPU temperature as before.
        '';
      };
    };

    gpuFancontrol = {
      enable = lib.mkEnableOption "Include AMDGPU fan (pwm1) in the generated fancontrol profile (manual control).";
      # Safer, quiet defaults for GPU
      minTemp = lib.mkOption {
        type = lib.types.int;
        default = 50;
        description = "GPU temperature (°C) to start ramping.";
      };
      maxTemp = lib.mkOption {
        type = lib.types.int;
        default = 85;
        description = "GPU temperature (°C) for max fan speed.";
      };
      minPwm = lib.mkOption {
        type = lib.types.int;
        default = 70;
        description = "GPU minimum PWM (0–255) to avoid stall while staying quiet.";
      };
      maxPwm = lib.mkOption {
        type = lib.types.int;
        default = 255;
        description = "GPU maximum PWM (0–255).";
      };
      hysteresis = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = "GPU fancontrol hysteresis (°C).";
      };
    };
  };

  config = lib.mkIf (cfg.enable or false) {
    # Load the typical motherboard PWM driver (Nuvoton/ASUS)
    boot.kernelModules = lib.mkIf cfg.loadNct6775 [ "nct6775" ];

    # Autogenerate a quiet fan profile if requested
    systemd.services.fancontrol-setup = lib.mkIf (cfg.autoFancontrol.enable or false) {
      description = "Generate quiet /etc/fancontrol from detected hwmon devices";
      # Avoid boot ordering cycle: do not depend on multi-user.target.
      before = [ "fancontrol.service" ];
      wantedBy = [ "fancontrol.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart =
          let
            gpuChannelArgs = map (c: "--gpu-pwm-channels ${builtins.toString c}") (
              cfg.autoFancontrol.gpuPwmChannels or [ ]
            );
            args = [
              "${pkgs.neg.hwctl}/bin/hwctl"
              "fan"
              "setup"
              "--min-temp ${builtins.toString cfg.autoFancontrol.minTemp}"
              "--max-temp ${builtins.toString cfg.autoFancontrol.maxTemp}"
              "--min-pwm ${builtins.toString cfg.autoFancontrol.minPwm}"
              "--max-pwm ${builtins.toString cfg.autoFancontrol.maxPwm}"
            ]
            ++ lib.optional cfg.autoFancontrol.allowStop "--allow-stop"
            ++ lib.optional cfg.gpuFancontrol.enable "--gpu-enable"
            ++ gpuChannelArgs;
          in
          lib.concatStringsSep " " args;
        RemainAfterExit = true;
      };
    };

    # Fancontrol service (runs the binary from lm_sensors)
    systemd.services.fancontrol = lib.mkIf (cfg.autoFancontrol.enable or false) (
      systemdUser.mkSystemService {
        description = "Software fan speed control (fancontrol)";
        presets = [ "restartOnFailure" ];
        requires = [ "fancontrol-setup.service" ];
        after = [ "fancontrol-setup.service" ];
        unitConfig = {
          # Only start if config exists
          ConditionPathExists = "/etc/fancontrol";
        };
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.lm_sensors}/bin/fancontrol"; # Tools for reading hardware sensors - maintained fork
          RestartSec = 5;
        };
        wantedBy = [ "multi-user.target" ];
      }
    );

    # Re-apply manual PWM ownership after suspend/hibernate resume
    # (amdgpu and some motherboard controllers reset pwm*_enable to automatic)
    environment.etc."systemd/system-sleep/99-fancontrol-reapply" =
      lib.mkIf (cfg.autoFancontrol.enable or false)
        {
          source = pkgs.writeShellScript "fancontrol-reapply" ''
            exec ${pkgs.neg.hwctl}/bin/hwctl fan reapply \
              ${lib.optionalString cfg.gpuFancontrol.enable "--gpu"}
          '';
          mode = "0755";
        };

    # Ensure tools are present for manual inspection/tweaks
    environment.systemPackages = [ pkgs.lm_sensors ]; # tools to read temperature/voltage/fan sensors
  };
}
