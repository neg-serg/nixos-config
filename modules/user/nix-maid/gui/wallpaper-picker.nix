#
# qs-wallpaperpicker — swatch-deck wallpaper picker (features.gui.wallpaperPicker)
#
# The picker is a standalone Quickshell config: its own `qs -p` instance with the
# IPC target `wallpaper` (`toggle`, `wallhaven`, `set`, `current`). It is deployed
# to ~/.config/qs-wallpaperpicker — outside ~/.config/quickshell, so it runs next
# to the bar without touching it. Source: files/qs-wallpaperpicker (vendored from
# dhrruvsharma/qs-wallpaperpicker 3cfae35, see .package-export there).
#
# ## Who draws the wallpaper
#
# The picker does (features.gui.wallpaperPicker.drawsWallpaper, default on): its
# WallpaperLayer paints one WlrLayer.Background window per screen and handles what
# wl cannot — animated GIF/WebP and videos (muted, looping, paused while a window
# covers them) — so an image, an animated picture and a clip all work the same way.
#
# Exactly one program may own that layer, so while the picker draws:
#
#   - `environment.etc."wallpaper-owner/picker"` exists, and the
#     wallpaper-sync.nix units (`wl-daemon`, `wl-monitor-watch`, `wl-state-sync`)
#     carry `ConditionPathExists=!/etc/wallpaper-owner/picker` and skip. They stay
#     *defined* on purpose: hyprland.lua starts `wl-daemon.service` by name in the
#     login phase and in the session branch, the greeter's lock restarts it, and
#     wl-restore starts it — with the condition those calls are no-ops instead of
#     failures, and nothing paints a second background under the picker's.
#   - the login screen, the bar accent and wl's last-good fallback follow the
#     *still*: scripts/wallpaper-apply (the one local patch on the vendored tree)
#     writes ~/.cache/quickshell-wallpaper-path and ~/.local/state/wl/last-good
#     next to the two ~/.cache/current_wallpaper* links, which is what
#     wl-greeter-sync copies into the greeter's cache. A video's still is the frame
#     scripts/wallpaper-still grabs with ffmpeg, so the k-means on the login screen
#     and the bar's colour extraction keep working.
#   - `wl-wallpaper-resolve.sh` asks that notify file before wl's state.json: in
#     this mode wl's state is a leftover from before the switch.
#
# To hand the layer back to wl-daemon: set `drawsWallpaper = false`, switch, and
# put the painter back in the picker's gear — `wl img {}` (see features.gui
# .wallpaperVideo for the same one-owner rule).
#
# ## Deployment
#
# Read-only files are live links into /etc/nixos (edit = deployed): the QML tree,
# the shell scripts it runs, the compiled shaders and the matugen template.
# settings.json and colors/Colors.json are user state written by the picker and by
# matugen, so they live in a real ~/.config/qs-wallpaperpicker; ExecStartPre seeds
# settings.json once and never again — the gear always wins afterwards.
{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  # Module-shaped systemd user units (lib/systemd-user.nix)
  systemdUser = config.lib.neg.systemdUser;

  # Feature gate (single source: config.lib.neg.wallpaperPickerEnabled)
  pickerEnabled = config.lib.neg.wallpaperPickerEnabled;

  # The picker paints the background itself (see the header)
  pickerDraws = config.lib.neg.wallpaperPickerDraws;

  pickerSrcLive = config.lib.neg.live "files/qs-wallpaperpicker";

  # Read-only half of the config. `colors/Colors.qml` is linked on its own
  # because matugen writes Colors.json beside it; `bin/`, `install.sh`, the README
  # and the licence never reach the runtime directory.
  pickerEntries = [
    "shell.qml"
    "colors/Colors.qml"
    "components"
    "extras"
    "modules"
    "scripts"
    "services"
    "settings"
    "shaders"
  ];

  pickerHomeFiles = neg.mkDirEntries ".config/qs-wallpaperpicker" pickerEntries (name: {
    source = "${pickerSrcLive}/${name}";
  });

  # First-run settings: the host's wallpaper collection, and an empty wallpaper
  # command so Quickshell draws (images, animated pictures and videos — see the
  # header). JsonAdapter keeps the picker's own defaults for every key left out
  # here, so only these two are written.
  pickerInit = pkgs.writeShellScript "qs-wallpaperpicker-init" ''
    set -eu
    cfg="''${XDG_CONFIG_HOME:-$HOME/.config}/qs-wallpaperpicker"
    mkdir -p "$cfg/colors"
    [ -e "$cfg/settings.json" ] && exit 0
    cat > "$cfg/settings.json" <<'JSON'
    {
      "wallpaperDir": "~/pic/wl",
      "wallpaperCommand": ""
    }
    JSON
  '';
in
lib.mkIf pickerEnabled (
  lib.mkMerge [
    {
      environment.systemPackages = [
        pkgs.qs-wallpaperpicker # the deck's CLI: `qs-wallpaperpicker toggle|set|current`
      ];
    }

    {
      # The picker has to be resident to answer `qs-wallpaperpicker toggle`: the
      # keybind is an IPC call into this unit, not a new shell.
      systemd.user.services.qs-wallpaperpicker = systemdUser.mkUserService {
        description = "Quickshell wallpaper picker (swatch deck; `qs-wallpaperpicker toggle`)";
        documentation = [ "https://github.com/dhrruvsharma/qs-wallpaperpicker" ];
        presets = [ "restartOnFailure" ];
        partOf = [ "hyprland-session.target" ];
        after = [
          "graphical-session-pre.target"
          "maid-activation.service"
        ];
        wants = [ "maid-activation.service" ];
        wantedBy = [ "hyprland-session.target" ];
        unitConfig = {
          # A startup crash would otherwise restart forever: give up after 5 quick
          # failures, the same shape the bar's unit uses.
          StartLimitIntervalSec = 30;
          StartLimitBurst = 5;
          # The greeter owns the screen until the password is accepted — the same
          # login-phase contract quickshell.service follows.
          ConditionPathExists = [ "!%t/quickshell-login/login-phase" ];
        };
        serviceConfig = {
          ExecStartPre = pickerInit;
          ExecStart = "${lib.getExe' pkgs.qs-wallpaperpicker "qs-wallpaperpicker"} start";
          RestartSec = 5;
          # Same ceilings as the bar: the shell is flat when idle (the deck is
          # unloaded while closed), and the pictures are what can grow.
          MemoryHigh = "384M";
          MemoryMax = "768M";
          CPUQuota = "200%";
        };
      };
    }

    (neg.mkHomeFiles pickerHomeFiles)

    # Ownership marker: the wallpaper-sync.nix conditions key off it, so wl-daemon and
    # its helpers stand down while the picker paints (see the header). Declarative on
    # purpose — a marker a user toggles by hand would let two painters come back.
    (lib.mkIf pickerDraws {
      environment.etc."wallpaper-owner/picker".text = ''
        qs-wallpaperpicker draws the desktop wallpaper
        (features.gui.wallpaperPicker.drawsWallpaper = true).
        wl-daemon, wl-monitor-watch and wl-state-sync skip while this file exists;
        see modules/user/nix-maid/gui/wallpaper-picker.nix.
      '';
    })
  ]
)
