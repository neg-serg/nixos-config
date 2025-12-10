{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  cfg = config.profiles.games or {};
  # Python wrappers to avoid shell/Nix escaping pitfalls
  gamescopePinned =
    pkgs.writers.writePython3Bin "gamescope-pinned" {}
    (builtins.readFile ./scripts/gamescope-pinned.py);

  gamePinned =
    pkgs.writers.writePython3Bin "game-pinned" {}
    (builtins.readFile ./scripts/game-pinned.py);

  # (no-op placeholder removed)

  gamescopePerf =
    pkgs.writers.writePython3Bin "gamescope-perf" {}
    (builtins.readFile ./scripts/gamescope-perf.py);

  gamescopeQuality =
    pkgs.writers.writePython3Bin "gamescope-quality" {}
    (builtins.readFile ./scripts/gamescope-quality.py);

  gamescopeHDR =
    pkgs.writers.writePython3Bin "gamescope-hdr" {}
    (builtins.readFile ./scripts/gamescope-hdr.py);

  gamescopeTargetFPS =
    pkgs.writers.writePython3Bin "gamescope-targetfps" {}
    (builtins.readFile ./scripts/gamescope-targetfps.py);

  # Desktop entries for convenient launchers
  gamescopePerfDesktop = pkgs.makeDesktopItem {
    name = "gamescope-perf";
    desktopName = "Gamescope (Performance)";
    comment = "Run a command via Gamescope with FSR downscale (2560x1440→3840x2160) and CPU pinning";
    exec = "gamescope-perf";
    terminal = false;
    categories = ["Game" "Utility"];
  };
  gamescopeQualityDesktop = pkgs.makeDesktopItem {
    name = "gamescope-quality";
    desktopName = "Gamescope (Quality)";
    comment = "Run a command via Gamescope at native resolution with CPU pinning";
    exec = "gamescope-quality";
    terminal = false;
    categories = ["Game" "Utility"];
  };
  gamescopeHDRDesktop = pkgs.makeDesktopItem {
    name = "gamescope-hdr";
    desktopName = "Gamescope (HDR)";
    comment = "Run a command via Gamescope with HDR enabled and CPU pinning";
    exec = "gamescope-hdr";
    terminal = false;
    categories = ["Game" "Utility"];
  };

  deovrSteamCli = pkgs.writeShellApplication {
    name = "deovr";
    text = ''
      exec steam steam://rungameid/837380 "$@"
    '';
  };

  deovrSteamDesktop = pkgs.makeDesktopItem {
    name = "deovr";
    desktopName = "DeoVR Video Player (Steam)";
    comment = "Launch DeoVR via Steam (AppID 837380)";
    exec = "steam steam://rungameid/837380";
    terminal = false;
    categories = ["Game" "AudioVideo"];
  };

  # SteamVR launcher for Wayland/Hyprland
  steamvrCli = pkgs.writeShellApplication {
    name = "steamvr";
    text = builtins.readFile ./scripts/steamvr.sh;
  };

  steamvrDesktop = pkgs.makeDesktopItem {
    name = "steamvr-hypr";
    desktopName = "SteamVR (Hyprland)";
    comment = "Launch SteamVR under Hyprland";
    exec = "steamvr";
    terminal = false;
    categories = ["Game" "Utility"];
  };

  # Default CPU pin set for affinity wrappers (comes from profiles.performance.gamingCpuSet)
  # Fallback is 'auto' to detect the V-Cache CCD via L3 size at runtime.
  pinDefault = let
    v = config.profiles.performance.gamingCpuSet or "";
  in
    if v != ""
    then v
    else "auto";

  # Helper: set affinity inside the scope to avoid shell escaping issues
  gameAffinityExec =
    pkgs.writers.writePython3Bin "game-affinity-exec" {}
    (lib.replaceStrings ["\${pinDefault}"] [pinDefault] (builtins.readFile ./scripts/game_affinity_exec.py));

  # Helper: run any command in a user cgroup scope with CPU affinity to gaming cores
  gameRun =
    pkgs.writers.writePython3Bin "game-run" {} # master wrapper orchestrating env vars, MangoHud, gamemode
    
    (lib.replaceStrings ["@pinDefault@"] [pinDefault] (builtins.readFile ./scripts/game_run.py));
in {
  imports = [inputs.aagl.nixosModules.default];
  nix.settings = inputs.aagl.nixConfig; # Set up Cachix

  options.profiles.games = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true; # preserve current behavior (enabled by default)
      description = "Enable the gaming stack (Steam, Gamescope wrappers, MangoHud, hardware rules).";
    };
    autoscaleDefault = lib.mkEnableOption "Enable autoscale heuristics by default for gamescope-targetfps.";
    targetFps = lib.mkOption {
      type = lib.types.int;
      default = 240;
      description = "Default target FPS used when autoscale is enabled globally or TARGET_FPS is unset.";
      example = 240;
    };
    nativeBaseFps = lib.mkOption {
      type = lib.types.int;
      default = 240;
      description = "Estimated FPS at native resolution used as baseline for autoscale heuristic.";
      example = 240;
    };
  };

  config = lib.mkIf cfg.enable {
    programs = {
      steam = {
        enable = true;
        package = pkgs.steam.override {
          extraBwrapArgs = ["--bind" "/zero" "/zero"];
          extraPkgs = pkgs': let
            mkDeps = pkgsSet:
              with pkgsSet; [
                # Core X11 libs required by many titles
                xorg.libX11
                xorg.libXext
                xorg.libXrender
                xorg.libXi
                xorg.libXinerama
                xorg.libXcursor
                xorg.libXScrnSaver
                xorg.libSM
                xorg.libICE
                xorg.libxcb
                xorg.libXrandr

                # Common multimedia/system libs
                libxkbcommon
                freetype
                fontconfig
                glib
                libpng
                libpulseaudio
                libvorbis
                libkrb5
                keyutils

                # GL/Vulkan plumbing for AMD on X11 (host RADV)
                libglvnd
                libdrm
                vulkan-loader

                # libstdc++ for the runtime
                (lib.getLib stdenv.cc.cc)
              ];
          in
            mkDeps pkgs';
        };
        dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
        gamescopeSession.enable = true;
        remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
        localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
        # Add Proton-GE for better compatibility/perf in some titles
        extraCompatPackages = [pkgs.proton-ge-bin];
      };

      gamescope = {
        enable = true;
        package = pkgs.gamescope; # the default, here in case I want to override it
      };

      gamemode = {
        enable = true;
        enableRenice = true;
        settings = {
          general = {
            softrealtime = "on";
            # Negative values increase priority; -10 is a safe bump
            renice = -10;
          };
        };
      };

      # MangoHud is installed via systemPackages; toggle via MANGOHUD=1

      anime-game-launcher.enable = true;
      honkers-railway-launcher.enable = true;
    };

    environment = {
      systemPackages = [
        pkgs.protontricks # winetricks-like helper tailored for Steam Proton
        pkgs.mangohud # Vulkan/OpenGL overlay for FPS/frametime telemetry
        gamescopePinned # CLI wrapper forcing pinned gamescope build
        gamePinned # wrapper to launch a Steam title w/ pinned Proton version
        gamescopePerf # helper to start gamescope with perf-friendly flags
        gamescopeQuality # helper to start gamescope with max fidelity settings
        gamescopeHDR # gamescope launcher enabling HDR pipeline tweaks
        gamescopeTargetFPS # wrapper that enforces FPS cap logic per title
        gamescopePerfDesktop # desktop entry for the perf preset
        gamescopeQualityDesktop # desktop entry for the quality preset
        gamescopeHDRDesktop # desktop entry for the HDR preset
        gameRun # wrapper orchestrating MangoHud, Gamescope, Gamemode
        gameAffinityExec # CLI forcing CPU affinity for stubborn games
        steamvrCli # script launching SteamVR under Wayland/Hypr tweaks
        steamvrDesktop # desktop entry for that SteamVR script
        deovrSteamCli # CLI wrapper to start DeoVR via Steam with env fixes
        deovrSteamDesktop # desktop entry for DeoVR launcher
        pkgs.prismlauncher # Minecraft launcher
      ];

      # Global defaults for wrappers
      variables = lib.mkMerge [
        # target-fps wrapper (opt-in switch)
        (lib.mkIf (cfg.autoscaleDefault or false) {
          GAMESCOPE_AUTOSCALE = "1";
          TARGET_FPS = builtins.toString (cfg.targetFps or 120);
          NATIVE_BASE_FPS = builtins.toString (cfg.nativeBaseFps or 60);
        })
        # default CPU pin set for game-run / game-affinity-exec if configured
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

      # No static games.slice unit file: we rely on transient scope created
      # by systemd-run with -p Slice=games.slice and per-scope properties.
    };

    # environment.variables merged above

    security.wrappers.gamemode = {
      owner = "root";
      group = "root";
      source = "${pkgs.gamemode}/bin/gamemoderun";
      capabilities = "cap_sys_ptrace,cap_sys_nice+pie";
    };

    # Expose udev rules/devices used by various game controllers/VR etc
    hardware.steam-hardware.enable = true;
  };
}
