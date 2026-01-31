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

  # Import consolidated game scripts from packages/game-scripts
  gameScripts = import ../../../packages/game-scripts {
    inherit pkgs lib config;
  };

  # Desktop entries for gamescope presets
  gamescopePerfDesktop = pkgs.makeDesktopItem {
    name = "gamescope-perf";
    desktopName = "Gamescope (Performance)";
    comment = "Run a command via Gamescope with FSR downscale (2560x1440→3840x2160) and CPU pinning";
    exec = "gamescope-perf";
    terminal = false;
    categories = [
      "Game"
      "Utility"
    ];
  };
  gamescopeQualityDesktop = pkgs.makeDesktopItem {
    name = "gamescope-quality";
    desktopName = "Gamescope (Quality)";
    comment = "Run a command via Gamescope at native resolution with CPU pinning";
    exec = "gamescope-quality";
    terminal = false;
    categories = [
      "Game"
      "Utility"
    ];
  };
  gamescopeHDRDesktop = pkgs.makeDesktopItem {
    name = "gamescope-hdr";
    desktopName = "Gamescope (HDR)";
    comment = "Run a command via Gamescope with HDR enabled and CPU pinning";
    exec = "gamescope-hdr";
    terminal = false;
    categories = [
      "Game"
      "Utility"
    ];
  };
in
{
  config = lib.mkIf cfg.enable {
    programs = {
      gamescope = {
        enable = true;
        package =
          if (config.features.optimization.zen5.enable or false) then
            pkgs.gamescope-zen5
          else
            pkgs.gamescope; # SteamOS session compositing window manager
      };

      gamemode = {
        enable = true;
        enableRenice = true;
        settings = {
          general = {
            softrealtime = "on";
            renice = -10;
          };
        };
      };
    };

    environment = {
      systemPackages = [
        (if (config.features.optimization.zen5.enable or false) then pkgs.mangohud-zen5 else pkgs.mangohud) # Vulkan/OpenGL overlay for FPS/frametime telemetry
        # Game scripts from consolidated package
        gameScripts.gamescope-pinned
        gameScripts.game-pinned
        gameScripts.gamescope-perf
        gameScripts.gamescope-quality
        gameScripts.gamescope-hdr
        gameScripts.gamescope-targetfps
        gameScripts.game-run
        gameScripts.game-affinity-exec
        # Desktop entries
        gamescopePerfDesktop
        gamescopeQualityDesktop
        gamescopeHDRDesktop
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
