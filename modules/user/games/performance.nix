# Gaming Performance Module
#
# Gamescope presets, Gamemode, MangoHud, CPU pinning, and environment variables.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.profiles.games or { };

  # gpu-oc: write AMD GPU overclock settings to pp_od_clk_voltage (root)
  # Usage: gpu-oc <sclk-offset> <vddgfx-offset>  (e.g. gpu-oc 300 -100)
  #        gpu-oc reset                          (reset to stock)
  gpuOc = pkgs.writeShellScriptBin "gpu-oc" ''
    set -e
    DEV=/sys/class/drm/card1/device/pp_od_clk_voltage
    # Wait for the GPU sysfs interface to appear (amdgpu probe may lag boot)
    for i in $(seq 1 30); do
      [ -w "$DEV" ] && break
      sleep 1
    done
    [ -w "$DEV" ] || { echo "gpu-oc: $DEV not writable after 30s" >&2; exit 1; }
    case "$1" in
      reset)
        echo "r" > "$DEV"
        echo "c" > "$DEV"
        ;;
      *)
        SCLK="''${1:?usage: gpu-oc <sclk-offset> <vddgfx-offset>|reset}"
        VDDG="''${2:?usage: gpu-oc <sclk-offset> <vddgfx-offset>|reset}"
        echo "s $SCLK" > "$DEV"
        echo "vo $VDDG" > "$DEV"
        echo "c" > "$DEV"
        ;;
    esac
  '';
in
{
  config = lib.mkIf cfg.enable {
    programs = {
      gamescope = {
        enable = true;
        package = pkgs.gamescope; # SteamOS session compositing window manager
      };

      gamemode = {
        enable = true;
        enableRenice = true;
        settings = {
          general = {
            softrealtime = "on";
            renice = -10;
            reaper_freq = 5;
            desiredgov = "performance";
            inhibit_screensaver = 1;
            ioprio = 0; # realtime I/O
          };
          gpu = {
            apply_gpu_optimisations = 1;
            gpu_device = 0;
            amd_performance_level = "high";
          };
          custom = {
            start = "${pkgs.writeShellScript "gamemode-start" ''
              # GameMode start: GPU performance high, CPU governor performance
              echo high | tee /sys/class/drm/card*/device/power_dpm_force_performance_level >/dev/null 2>&1 || true
              # Disable NUMA balancing (page migration jitter not wanted during gaming)
              echo 0 | tee /proc/sys/kernel/numa_balancing 2>/dev/null || true
              # Set energy performance preference to performance
              echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference 2>/dev/null || true
              # Set energy performance bias to 0 (max performance)
              echo 0 | tee /sys/devices/system/cpu/cpu*/power/energy_perf_bias 2>/dev/null || true
            ''}";
            end = "${pkgs.writeShellScript "gamemode-end" ''
              # GameMode end: restore GPU power profile
              echo auto | tee /sys/class/drm/card*/device/power_dpm_force_performance_level >/dev/null 2>&1 || true
              # Restore NUMA balancing
              echo 1 | tee /proc/sys/kernel/numa_balancing 2>/dev/null || true
              # Restore energy performance preference to default
              echo default | tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference 2>/dev/null || true
              # Restore energy performance bias to 6 (normal — balanced)
              echo 6 | tee /sys/devices/system/cpu/cpu*/power/energy_perf_bias 2>/dev/null || true
            ''}";
          };
        };
      };
    };

    # Systemd slice for game processes — CPU set scoped to gaming cores
    systemd.slices.games = {
      sliceConfig = {
        CPUAccounting = true;
        MemoryAccounting = true;
        TasksAccounting = true;
        AllowedCPUs = config.profiles.performance.gamingCpuSet;
        # NO AllowedMemoryNodes — let kernel auto-select (V-Cache CCD can be node 0 or 1 on dual-CCD X3D)
      };
    };
    # auto-oc: apply persistent CPU + GPU overclock at boot
    # CPU: PBO 230W, TDC 190A, Tctl 95C, Curve Optimizer -20 (9950X3D)
    # GPU: sclk +300MHz, vddgfx -100mV (RX 9070 XT optimum from OC sweep)
    systemd.services.auto-oc = {
      description = "Apply persistent CPU/GPU overclock";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-modules-load.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe pkgs.bash} -c '${lib.getExe pkgs.ryzenadj} -a 230000 -b 230000 -c 230000 -g 190000 -f 95 --set-coall=-20 && ${gpuOc}/bin/gpu-oc 300 -100'";
      };
    };

    environment = {

      systemPackages = [
        pkgs.mangohud # Vulkan/OpenGL overlay for FPS/frametime telemetry
        pkgs.neg.game # Unified game launcher — CPU pinning, Gamescope, sessions
        pkgs.corectrl # GUI for AMD GPU overclocking and fan control
        pkgs.ryzenadj # AMD CPU overclocking (PBO, curve optimizer) via SMU
        pkgs.stress-ng # CPU/RAM stress testing for stability verification
        pkgs.glmark2 # OpenGL benchmark for GPU stability/performance
        pkgs.vkmark # Vulkan benchmark for GPU stability/performance
        # gpu-oc: write AMD GPU overclock settings to pp_od_clk_voltage (root)
        # Usage: gpu-oc <sclk-offset> <vddgfx-offset>  (e.g. gpu-oc 150 -50)
        #        gpu-oc reset                          (reset to stock)
        gpuOc # GPU overclock/undervolt helper (root via NOPASSWD)
      ];

      # Global defaults for wrappers
      variables = lib.mkMerge [
        (lib.mkIf (cfg.autoscaleDefault or false) {
          GAMESCOPE_AUTOSCALE = "1";
          TARGET_FPS = builtins.toString (cfg.targetFps or 120);
          NATIVE_BASE_FPS = builtins.toString (cfg.nativeBaseFps or 60);
        })
        (lib.mkIf ((config.profiles.performance.gamingCpuSet or "") != "") {
          GAME_PIN_CPUSET = config.profiles.performance.gamingCpuSet;
        })
      ];

      # System-wide MangoHud defaults
      etc."xdg/MangoHud/MangoHud.conf".text = ''
        legacy_layout=0
        position=top-left
        font_size=20
        background_alpha=0.35
        toggle_hud=Shift_R+F12
        toggle_logging=Shift_L+F2
        toggle_fps_limit=Shift_L+F1

        fps=1
        frametime=1
        frame_timing=1
        gpu_stats=1
        cpu_stats=1
        gpu_temp=1
        cpu_temp=1
        vram=1
        ram=1
        io_read=1
        io_write=1
        gamemode=1
      '';
    };

    security.wrappers.gamemode = {
      owner = "root";
      group = "root";
      source = "${pkgs.gamemode}/bin/gamemoderun"; # Optimise Linux system performance on demand
      capabilities = "cap_sys_ptrace,cap_sys_nice+pie";
    };
  };
}
