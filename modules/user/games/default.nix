{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.profiles.games or {};

  # Import consolidated game scripts from packages/game-scripts
  gameScripts = import ../../../packages/game-scripts {
    inherit pkgs lib config;
  };

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

  steamvrDesktop = pkgs.makeDesktopItem {
    name = "steamvr-hypr";
    desktopName = "SteamVR (Hyprland)";
    comment = "Launch SteamVR under Hyprland";
    exec = "steamvr";
    terminal = false;
    categories = ["Game" "Utility"];
  };
in {
  imports = [];

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

                # Network/Auth libs often needed by Steam Runtime tools
                openssl
                libpsl
                nghttp2
                libidn2
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
    };

    environment = {
      systemPackages = [
        pkgs.protontricks # winetricks-like helper tailored for Steam Proton
        pkgs.mangohud # Vulkan/OpenGL overlay for FPS/frametime telemetry
        # Game scripts from consolidated package
        gameScripts.gamescope-pinned
        gameScripts.game-pinned
        gameScripts.gamescope-perf
        gameScripts.gamescope-quality
        gameScripts.gamescope-hdr
        gameScripts.gamescope-targetfps
        gameScripts.game-run
        gameScripts.game-affinity-exec
        gameScripts.steamvr
        # Desktop entries
        gamescopePerfDesktop
        gamescopeQualityDesktop
        gamescopeHDRDesktop
        steamvrDesktop
        deovrSteamCli
        deovrSteamDesktop
        pkgs.prismlauncher # Minecraft launcher
        pkgs.heroic # Epic, GOG, Amazon launcher
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
