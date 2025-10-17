{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.profiles.games or {};
  # Helper to strip common leading indentation from a multi-line string
  dedentPy = s: let
    lines = lib.splitString "\n" s;
    nonEmpty = lib.filter (l: l != "") lines;
    leading = l: let
      m = builtins.match "^( +)" l;
    in
      if m == null
      then 0
      else builtins.stringLength (builtins.elemAt m 0);
    minIndent =
      if nonEmpty == []
      then 0
      else
        lib.foldl' (a: b:
          if b < a
          then b
          else a)
        9999 (map leading nonEmpty);
    spaces = lib.concatStrings (builtins.genList (_: " ") minIndent);
    stripN = l:
      if lib.hasPrefix spaces l
      then lib.removePrefix spaces l
      else l;
  in
    lib.concatStringsSep "\n" (map stripN lines);
  # Python wrappers to avoid shell/Nix escaping pitfalls
  gamescopePinned =
    pkgs.writers.writePython3Bin "gamescope-pinned" {}
    (dedentPy ''
      import os
      import shlex
      import subprocess
      import sys

      GAMESCOPE = "gamescope"
      GAME_RUN = "game-run"

      flags = os.environ.get("GAMESCOPE_FLAGS", "-f --adaptive-sync")

      cmd = (
          [GAME_RUN, GAMESCOPE]
          + shlex.split(flags)
          + ["--"]
          + sys.argv[1:]
      )
      raise SystemExit(subprocess.call(cmd))
    '');

  gamePinned =
    pkgs.writers.writePython3Bin "game-pinned" {}
    (dedentPy ''
      import subprocess
      import sys

      GAME_RUN = "game-run"

      cmd = [GAME_RUN] + sys.argv[1:]
      raise SystemExit(subprocess.call(cmd))
    '');

  # (no-op placeholder removed)

  gamescopePerf =
    pkgs.writers.writePython3Bin "gamescope-perf" {}
    (dedentPy ''
      import json
      import os
      import shlex
      import subprocess
      import sys

      H = {
          "HYPRCTL": "hyprctl",
          "ZENITY": "zenity",
          "GAME_RUN": "game-run",
          "GAMESCOPE": "gamescope",
      }


      def get_monitors():
          try:
              out = subprocess.check_output(
                  [H["HYPRCTL"], "monitors", "-j"], text=True
              )
              return json.loads(out)
          except Exception:
              return []


      def pick_monitor(mon_name, mons):
          if mons:
              if mon_name:
                  for m in mons:
                      if m.get("name") == mon_name:
                          return m
              focused = [m for m in mons if m.get("focused")]
              if focused:
                  return focused[0]
              # best by refresh then resolution
              return sorted(
                  mons,
                  key=lambda m: (
                      m.get("refreshRate", 0),
                      (m.get("width", 0) * m.get("height", 0)),
                  ),
                  reverse=True,
              )[0]
          return None


      mon_env = os.environ.get("GAMESCOPE_MON")
      out_w = os.environ.get("GAMESCOPE_OUT_W")
      out_h = os.environ.get("GAMESCOPE_OUT_H")
      mons = get_monitors()
      mon = pick_monitor(mon_env, mons)
      if not out_w or not out_h:
          if mon:
              out_w = out_w or str(mon.get("width", 3840))
              out_h = out_h or str(mon.get("height", 2160))
          else:
              out_w = out_w or "3840"
              out_h = out_h or "2160"

      # focus chosen monitor
      if mon_env:
          try:
              subprocess.run(
                  [H["HYPRCTL"], "dispatch", "focusmonitor", mon_env],
                  check=False,
                  stdout=subprocess.DEVNULL,
                  stderr=subprocess.DEVNULL,
              )
          except Exception:
              pass

      rate = os.environ.get("GAMESCOPE_RATE")
      if not rate and mon:
          rr = mon.get("refreshRate")
          if rr:
              rate = str(int(round(rr)))

      game_w = os.environ.get("GAMESCOPE_GAME_W")
      game_h = os.environ.get("GAMESCOPE_GAME_H")
      if not game_w or not game_h:
          game_w = game_w or str(int(int(out_w) * 2 / 3))
          game_h = game_h or str(int(int(out_h) * 2 / 3))

      flags = ["-f", "--adaptive-sync"]
      if rate:
          flags += ["-r", rate]
      flags += [
          "-w",
          game_w,
          "-h",
          game_h,
          "-W",
          out_w,
          "-H",
          out_h,
          "--fsr-sharpness",
          "3",
      ]

      if len(sys.argv) == 1:
          try:
              cmd_str = subprocess.check_output(
                  [
                      H["ZENITY"],
                      "--entry",
                      "--title=Gamescope Performance",
                      "--text=Command to run:",
                  ],
                  text=True,
              ).strip()
          except Exception:
              cmd_str = ""
          if not cmd_str:
              sys.exit(0)
          args = shlex.split(cmd_str)
      else:
          args = sys.argv[1:]

      cmd = (
          [H["GAME_RUN"], H["GAMESCOPE"]]
          + flags
          + ["--"]
          + args
      )
      raise SystemExit(subprocess.call(cmd))
    '');

  gamescopeQuality =
    pkgs.writers.writePython3Bin "gamescope-quality" {}
    (dedentPy ''
      import json
      import os
      import shlex
      import subprocess
      import sys

      H = {
          "HYPRCTL": "hyprctl",
          "ZENITY": "zenity",
          "GAME_RUN": "game-run",
          "GAMESCOPE": "gamescope",
      }


      def get_monitors():
          try:
              out = subprocess.check_output(
                  [H["HYPRCTL"], "monitors", "-j"], text=True
              )
              return json.loads(out)
          except Exception:
              return []


      def pick_monitor(mon_name, mons):
          if mons:
              if mon_name:
                  for m in mons:
                      if m.get("name") == mon_name:
                          return m
              focused = [m for m in mons if m.get("focused")]
              if focused:
                  return focused[0]
              return sorted(
                  mons,
                  key=lambda m: (
                      m.get("refreshRate", 0),
                      (m.get("width", 0) * m.get("height", 0)),
                  ),
                  reverse=True,
              )[0]
          return None


      mon_env = os.environ.get("GAMESCOPE_MON")
      out_w = os.environ.get("GAMESCOPE_OUT_W") or ""
      out_h = os.environ.get("GAMESCOPE_OUT_H") or ""
      mons = get_monitors()
      mon = pick_monitor(mon_env, mons)
      if not out_w or not out_h:
          if mon:
              out_w = out_w or str(mon.get("width", 3840))
              out_h = out_h or str(mon.get("height", 2160))
          else:
              out_w = out_w or "3840"
              out_h = out_h or "2160"

      if mon_env:
          try:
              subprocess.run(
                  [H["HYPRCTL"], "dispatch", "focusmonitor", mon_env],
                  check=False,
                  stdout=subprocess.DEVNULL,
                  stderr=subprocess.DEVNULL,
              )
          except Exception:
              pass

      rate = os.environ.get("GAMESCOPE_RATE")
      if not rate and mon:
          rr = mon.get("refreshRate")
          if rr:
              rate = str(int(round(rr)))

      flags = ["-f", "--adaptive-sync"]
      if rate:
          flags += ["-r", rate]
      flags += [
          "-W",
          out_w,
          "-H",
          out_h,
      ]

      if len(sys.argv) == 1:
          try:
              cmd_str = subprocess.check_output(
                  [
                      H["ZENITY"],
                      "--entry",
                      "--title=Gamescope Quality",
                      "--text=Command to run:",
                  ],
                  text=True,
              ).strip()
          except Exception:
              cmd_str = ""
          if not cmd_str:
              sys.exit(0)
          args = shlex.split(cmd_str)
      else:
          args = sys.argv[1:]

      cmd = (
          [H["GAME_RUN"], H["GAMESCOPE"]]
          + flags
          + ["--"]
          + args
      )
      raise SystemExit(subprocess.call(cmd))
    '');

  gamescopeHDR =
    pkgs.writers.writePython3Bin "gamescope-hdr" {}
    (dedentPy ''
      import json
      import os
      import shlex
      import subprocess
      import sys

      H = {
          "HYPRCTL": "hyprctl",
          "ZENITY": "zenity",
          "GAME_RUN": "game-run",
          "GAMESCOPE": "gamescope",
      }


      def get_monitors():
          try:
              out = subprocess.check_output(
                  [H["HYPRCTL"], "monitors", "-j"], text=True
              )
              return json.loads(out)
          except Exception:
              return []


      def pick_monitor(mon_name, mons):
          if mons:
              if mon_name:
                  for m in mons:
                      if m.get("name") == mon_name:
                          return m
              focused = [m for m in mons if m.get("focused")]
              if focused:
                  return focused[0]
              return sorted(
                  mons,
                  key=lambda m: (
                      m.get("refreshRate", 0),
                      (m.get("width", 0) * m.get("height", 0)),
                  ),
                  reverse=True,
              )[0]
          return None


      mon_env = os.environ.get("GAMESCOPE_MON")
      out_w = os.environ.get("GAMESCOPE_OUT_W") or ""
      out_h = os.environ.get("GAMESCOPE_OUT_H") or ""
      mons = get_monitors()
      mon = pick_monitor(mon_env, mons)
      if not out_w or not out_h:
          if mon:
              out_w = out_w or str(mon.get("width", 3840))
              out_h = out_h or str(mon.get("height", 2160))
          else:
              out_w = out_w or "3840"
              out_h = out_h or "2160"

      if mon_env:
          try:
              subprocess.run(
                  [H["HYPRCTL"], "dispatch", "focusmonitor", mon_env],
                  check=False,
                  stdout=subprocess.DEVNULL,
                  stderr=subprocess.DEVNULL,
              )
          except Exception:
              pass

      rate = os.environ.get("GAMESCOPE_RATE")
      if not rate and mon:
          rr = mon.get("refreshRate")
          if rr:
              rate = str(int(round(rr)))

      flags = ["-f", "--adaptive-sync", "--hdr-enabled"]
      if rate:
          flags += ["-r", rate]
      flags += [
          "-W",
          out_w,
          "-H",
          out_h,
      ]

      if len(sys.argv) == 1:
          try:
              cmd_str = subprocess.check_output(
                  [
                      H["ZENITY"],
                      "--entry",
                      "--title=Gamescope HDR",
                      "--text=Command to run:",
                  ],
                  text=True,
              ).strip()
          except Exception:
              cmd_str = ""
          if not cmd_str:
              sys.exit(0)
          args = shlex.split(cmd_str)
      else:
          args = sys.argv[1:]

      cmd = (
          [H["GAME_RUN"], H["GAMESCOPE"]]
          + flags
          + ["--"]
          + args
      )
      raise SystemExit(subprocess.call(cmd))
    '');

  gamescopeTargetFPS =
    pkgs.writers.writePython3Bin "gamescope-targetfps" {}
    (dedentPy ''
      import json
      import math
      import os
      import shlex
      import subprocess
      import sys

      H = {
          "HYPRCTL": "hyprctl",
          "ZENITY": "zenity",
          "GAME_RUN": "game-run",
          "GAMESCOPE": "gamescope",
      }


      def get_monitors():
          try:
              out = subprocess.check_output(
                  [H["HYPRCTL"], "monitors", "-j"], text=True
              )
              return json.loads(out)
          except Exception:
              return []


      def pick_monitor(mon_name, mons):
          if mons:
              if mon_name:
                  for m in mons:
                      if m.get("name") == mon_name:
                          return m
              focused = [m for m in mons if m.get("focused")]
              if focused:
                  return focused[0]
              return sorted(
                  mons,
                  key=lambda m: (
                      m.get("refreshRate", 0),
                      (m.get("width", 0) * m.get("height", 0)),
                  ),
                  reverse=True,
              )[0]
          return None


      mon_env = os.environ.get("GAMESCOPE_MON")
      target = os.environ.get("TARGET_FPS")
      base = float(os.environ.get("NATIVE_BASE_FPS", "60"))
      autoscale = os.environ.get("GAMESCOPE_AUTOSCALE") == "1"

      out_w = os.environ.get("GAMESCOPE_OUT_W") or ""
      out_h = os.environ.get("GAMESCOPE_OUT_H") or ""
      mons = get_monitors()
      mon = pick_monitor(mon_env, mons)
      if not out_w or not out_h:
          if mon:
              out_w = out_w or str(mon.get("width", 3840))
              out_h = out_h or str(mon.get("height", 2160))
          else:
              out_w = out_w or "3840"
              out_h = out_h or "2160"

      if mon_env:
          try:
              subprocess.run(
                  [H["HYPRCTL"], "dispatch", "focusmonitor", mon_env],
                  check=False,
                  stdout=subprocess.DEVNULL,
                  stderr=subprocess.DEVNULL,
              )
          except Exception:
              pass

      rate = os.environ.get("GAMESCOPE_RATE")
      if not rate and mon:
          rr = mon.get("refreshRate")
          if rr:
              rate = str(int(round(rr)))

      # Heuristic autoscale
      scale = 1.0
      if target or autoscale:
          t = float(target or 120)
          if base > 0 and t > 0:
              scale = max(0.5, min(1.0, math.sqrt(base / t)))
      game_w = str(int(round(int(out_w) * scale)))
      game_h = str(int(round(int(out_h) * scale)))

      flags = ["-f", "--adaptive-sync"]
      if rate:
          flags += ["-r", rate]
      flags += [
          "-w",
          game_w,
          "-h",
          game_h,
          "-W",
          out_w,
          "-H",
          out_h,
          "--fsr-sharpness",
          "3",
      ]

      if len(sys.argv) == 1:
          prompt = f"Command to run (scale {scale:.3f}"
          if target:
              prompt += f", target {target} FPS"
          prompt += "):"
          try:
              cmd_str = subprocess.check_output(
                  [
                      H["ZENITY"],
                      "--entry",
                      "--title=Gamescope Target FPS",
                      f"--text={prompt}",
                  ],
                  text=True,
              ).strip()
          except Exception:
              cmd_str = ""
          if not cmd_str:
              sys.exit(0)
          args = shlex.split(cmd_str)
      else:
          args = sys.argv[1:]

      cmd = (
          [H["GAME_RUN"], H["GAMESCOPE"]]
          + flags
          + ["--"]
          + args
      )
      raise SystemExit(subprocess.call(cmd))
    '');

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
    text = ''
      set -euo pipefail
      # Hint: SteamVR AppID is 250820
      steam -applaunch 250820 &
      STEAM_PID=$!

      # Wait for VRCompositor to come up (up to 60s), then for it to exit
      tries=60
      while ! pgrep -f -u "$USER" -x vrcompositor >/dev/null 2>&1; do
        sleep 1
        tries=$((tries-1))
        if [ "$tries" -le 0 ]; then
          break
        fi
      done

      # Poll until VR compositor fully exits
      while pgrep -f -u "$USER" -x vrcompositor >/dev/null 2>&1; do
        sleep 2
      done

      # Give Steam a moment to settle
      sleep 1
      wait "$STEAM_PID" || true
    '';
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
  pinDefault =
    let v = config.profiles.performance.gamingCpuSet or ""; in
    if v != "" then v else "14,15,30,31";

  # Helper: set affinity inside the scope to avoid shell escaping issues
  gameAffinityExec =
    pkgs.writers.writePython3Bin "game-affinity-exec" {}
    (dedentPy ''
      import argparse
      import os
      import sys


      def parse_cpuset(s: str):
          cpus = set()
          for part in s.split(','):
              part = part.strip()
              if not part:
                  continue
              if '-' in part:
                  a, b = part.split('-', 1)
                  cpus.update(range(int(a), int(b) + 1))
              else:
                  cpus.add(int(part))
          return sorted(cpus)


      ap = argparse.ArgumentParser()
      ap.add_argument(
          '--cpus',
          default=os.environ.get('GAME_PIN_CPUSET', '${pinDefault}'),
      )
      ap.add_argument('cmd', nargs=argparse.REMAINDER)
      args = ap.parse_args()

      if not args.cmd or args.cmd[0] != '--':
          print(
              'Usage: game-affinity-exec --cpus 14,15,30,31 -- <command> [args...]',
              file=sys.stderr,
          )
          sys.exit(2)
      cmd = args.cmd[1:]

      cpus = parse_cpuset(args.cpus)
      try:
          os.sched_setaffinity(0, cpus)
      except Exception as e:
          print(f'Warning: failed to set CPU affinity: {e}', file=sys.stderr)

      use_gamemode = os.environ.get('GAME_RUN_USE_GAMEMODE', '1') not in (
          '0', 'false', 'no'
      )
      if use_gamemode:
          cmd = ['gamemoderun'] + cmd

      os.execvp(cmd[0], cmd)
    '');

  # Helper: run any command in a user cgroup scope with CPU affinity to gaming cores
  gameRun =
    pkgs.writers.writePython3Bin "game-run" {}
    (dedentPy ''
      import os
      import subprocess
      import sys

      CPUSET = os.environ.get('GAME_PIN_CPUSET', '${pinDefault}')
      if len(sys.argv) <= 1:
          print('Usage: game-run <command> [args...]', file=sys.stderr)
          sys.exit(1)

      cmd = [
          'systemd-run', '--user', '--scope', '--same-dir', '--collect',
          '-p', 'Slice=games.slice',
          '-p', 'CPUWeight=10000', '-p', 'IOWeight=10000', '-p', 'TasksMax=infinity',
          'game-affinity-exec', '--cpus', CPUSET, '--'
      ] + sys.argv[1:]

      raise SystemExit(subprocess.call(cmd))
    '');
in {
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
          extraPkgs = pkgs':
            let
              mkDeps =
                pkgsSet:
                with pkgsSet;
                [
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
        extraCompatPackages = [pkgs.proton-ge-custom];
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
        pkgs.protontricks
        pkgs.mangohud
        gamescopePinned
        gamePinned
        gamescopePerf
        gamescopeQuality
        gamescopeHDR
        gamescopeTargetFPS
        gamescopePerfDesktop
        gamescopeQualityDesktop
        gamescopeHDRDesktop
        gameRun
        gameAffinityExec
        steamvrCli
        steamvrDesktop
        deovrSteamCli
        deovrSteamDesktop
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
