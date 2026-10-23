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
# The picker can draw the wallpaper itself (that is its default), but on trantor
# wl-daemon owns the background layer: it also paints behind the login screen,
# and modules/user/nix-maid/sys/wallpaper-sync.nix turns every wl change into
# ~/.cache/quickshell-wallpaper-path, which feeds the bar accent and the greeter
# copy. Two painters would fight over the same layer and leave the login screen on
# the previous picture, so the settings seed below hands each chosen wallpaper to
# `wl img {}`: the deck becomes a front end of the same daemon, and the login
# screen, the bar accent and `wl restore` all follow it. The one cost: video
# wallpapers stay the deck's preview only (wl takes images); the colour-sorted
# cards, the favourites and Wallhaven are unaffected.
#
# To let Quickshell paint instead, clear the wallpaper command in the picker's gear
# (the field applies on Enter) and stop wl-daemon first — the same one-owner rule
# features.gui.wallpaperVideo documents for its pinned window.
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

  # First-run settings: the host's wallpaper collection and wl as the painter (see
  # the header). JsonAdapter keeps the picker's own defaults for every key left
  # out here, so only the two host-specific ones are written.
  pickerInit = pkgs.writeShellScript "qs-wallpaperpicker-init" ''
    set -eu
    cfg="''${XDG_CONFIG_HOME:-$HOME/.config}/qs-wallpaperpicker"
    mkdir -p "$cfg/colors"
    [ -e "$cfg/settings.json" ] && exit 0
    cat > "$cfg/settings.json" <<'JSON'
    {
      "wallpaperDir": "~/pic/wl",
      "wallpaperCommand": "wl img {}"
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
          # login-phase contract quickshell.service and wayle follow.
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
  ]
)
