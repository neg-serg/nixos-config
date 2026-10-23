#
# qs-wallpaperpicker — swatch-deck wallpaper picker (features.gui.wallpaperPicker)
#
# The picker is a standalone Quickshell config: its own `qs -p` instance with the
# IPC target `wallpaper` (`toggle`, `wallhaven`, `set`, `current`). It is deployed
# to ~/.config/qs-wallpaperpicker — outside ~/.config/quickshell, so it runs next
# to the bar without touching it. Source: files/qs-wallpaperpicker (vendored from
# dhrruvsharma/qs-wallpaperpicker 3cfae35, see .package-export there).
#
# ## Who draws the wallpaper — both, split by what each can paint
#
# wl-daemon stays the owner of the desktop background and of the login screen's
# backdrop (modules/user/nix-maid/sys/wallpaper-sync.nix), and the deck is its front
# end: an image chosen here is handed over as `wl img {}` and Quickshell opens no
# background window for it, so `wl query`, `wl restore`, the vicinae wl-switcher and
# the login screen keep agreeing with what is on screen.
#
# What wl cannot paint — an animated GIF/WebP or a video — the picker draws itself:
# WallpaperLayer puts one window per screen on WlrLayer.Bottom, i.e. above wl's
# background surface and below every normal window, so the clip really is the
# wallpaper and the daemon underneath is simply covered. services/WallpaperEngine
# picks the side per file kind (`external` is false only for those two kinds), so
# the gear's `wl img {}` command never sees a file wl would choke on.
#
# Two details of that pairing are deliberate, both learned the hard way:
#   - the layer's window exists for every screen from startup and is *unmapped*
#     (`visible: !external`) for images, not created on demand: Quickshell does not
#     instantiate a delegate when a model goes from empty back to a list, which
#     silently left the clip with no window at all;
#   - the layer is Bottom, not the vendored Background: wl paints Background, and a
#     Background window of ours created later was composited above it *by accident*
#     — Bottom is above it by the protocol's layer order.
#
# The asymmetry is by construction: while a clip is on screen, a wallpaper set from
# wl's side (`wl random`, the vicinae wl-switcher) lands underneath it — pick
# anything in the deck, or any image, and wl's picture is back on top.
#
# The login screen, the bar accent and wl's last-good fallback follow either kind:
# scripts/wallpaper-apply (the one local patch on the vendored tree) writes
# ~/.cache/quickshell-wallpaper-path and ~/.local/state/wl/last-good, and puts the
# *still* there — for a clip the frame scripts/wallpaper-still grabs with ffmpeg —
# because the k-means on the login screen and the bar's colour extraction cannot
# read a video. wl-wallpaper-resolve.sh asks that file before wl's state.json.
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

  # Backwards half of the pairing: wl is the other writer of the background
  # (`wl random`, the vicinae wl-switcher, `wl restore` when a monitor comes back),
  # so the deck follows it instead of keeping a clip on screen over a wallpaper the
  # user just picked somewhere else. Three rules keep that honest:
  #
  #   - only a readable file wl actually names is adopted;
  #   - wl's own restore at login re-applies exactly the file the deck last handed it
  #     (~/.cache/qs-picker-wl-last, written by scripts/wallpaper-apply) — adopting
  #     that would swap the user's clip back to the last still image on every login;
  #   - a live deck is switched through its IPC, and a deck that is down gets its
  #     stored state (scripts/wallpaper-apply) pointed at wl's picture instead: on its
  #     next start the deck re-applies what it has stored, so without this a pick made
  #     through wl while the deck was gone would be overwritten at startup.
  #
  # `qs-wallpaperpicker set` then writes the same state back (it is idempotent: the
  # second state.json write it causes finds `new == current` and stops), so the
  # loop terminates in one round.
  pickerAdopt = pkgs.writeShellScript "qs-wallpaper-adopt" ''
    set -eu
    export PATH="${
      lib.makeBinPath [
        pkgs.bash # scripts/wallpaper-apply and -still run under a bash shebang
        pkgs.coreutils # seq, sleep, cat, readlink, nice
        pkgs.jq # wl's state.json
        pkgs.matugen # the palette behind the adopted wallpaper, as on any set
        pkgs.ffmpeg # a video's still frame (wallpaper-still), should wl ever name one
        pkgs.qs-wallpaperpicker # the deck's own CLI (qs ipc)
      ]
    }"

    state="$HOME/.local/state/wl/state.json"
    [ -r "$state" ] || exit 0

    # Bounded wait for the deck's IPC: this unit is ordered after the picker's, but
    # QML still needs a moment before it answers at session start.
    ready=0
    cur=""
    for _ in $(seq 1 30); do
      if cur="$(qs-wallpaperpicker current 2> /dev/null)"; then
        ready=1
        break
      fi
      sleep 0.2
    done

    new="$(${lib.getExe' pkgs.jq "jq"} -r '.outputs | to_entries | .[0].value.wallpaper_path // empty' "$state" 2> /dev/null || true)"
    [ -n "$new" ] && [ -f "$new" ] || exit 0
    [ "$new" = "$cur" ] && exit 0

    last="$(cat "$HOME/.cache/qs-picker-wl-last" 2> /dev/null || true)"
    [ -n "$last" ] && [ "$new" = "$last" ] && exit 0

    if [ "$ready" = 1 ]; then
      # Live deck: switch it, so a clip's window gives way to the picture wl shows.
      qs-wallpaperpicker set "$new"
    else
      # Deck down: on its next start it re-applies the wallpaper it has stored
      # (WallpaperEngine runs the command once at startup), which would overwrite the
      # pick made through wl while it was gone. Point that stored state at wl's
      # picture instead — the deck then starts on the right wallpaper, and wl is
      # already showing it, so no second command is needed here.
      apply="''${XDG_CONFIG_HOME:-$HOME/.config}/qs-wallpaperpicker/scripts/wallpaper-apply"
      [ -x "$apply" ] && "$apply" "$new"
    fi
  '';

  # First-run settings: the host's wallpaper collection, and wl-daemon as the
  # painter — the deck hands every image over through it, while it draws the
  # animated pictures and clips itself (see the header). JsonAdapter keeps the
  # picker's own defaults for every key left out here, so only these two are written.
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
          # login-phase contract quickshell.service follows.
          ConditionPathExists = [ "!%t/quickshell-login/login-phase" ];
        };
        serviceConfig = {
          ExecStartPre = pickerInit;
          ExecStart = "${lib.getExe' pkgs.qs-wallpaperpicker "qs-wallpaperpicker"} start";
          # Re-run the adoption after a (re)start of the deck: a wallpaper picked on
          # wl's side while the deck was down stays invisible behind its clip until
          # something asks. Fire-and-forget — the adopt unit waits for IPC itself, so
          # the deck's start is not held up by it.
          ExecStartPost = "${lib.getExe' pkgs.systemd "systemctl"} --user start --no-block qs-wallpaper-adopt.service";
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

    {
      # Fires on every wl state write: the picker's own sets (a no-op second round) and
      # the wallpapers picked on wl's side, which are the point of this unit.
      systemd.user.services.qs-wallpaper-adopt = systemdUser.mkUserService {
        description = "Adopt a wallpaper set through wl into the Quickshell picker";
        presets = [ "oneshot" ];
        after = [
          "qs-wallpaperpicker.service"
          "graphical-session-pre.target"
        ];
        wants = [ "qs-wallpaperpicker.service" ];
        # Also runs once per session: a wallpaper picked while the deck was down must
        # not stay invisible behind it once it is back.
        wantedBy = [ "hyprland-session.target" ];
        unitConfig = {
          # wl writes its state in bursts while outputs settle; the default start rate
          # limit would fail the oneshot and kill the path unit with it.
          StartLimitIntervalSec = 0;
        };
        serviceConfig.ExecStart = pickerAdopt;
      };

      systemd.user.paths.qs-wallpaper-adopt = {
        description = "Watch wl state.json for wallpapers set outside the picker";
        wantedBy = [ "hyprland-session.target" ];
        partOf = [ "hyprland-session.target" ];
        pathConfig = {
          PathChanged = "%h/.local/state/wl/state.json";
          Unit = "qs-wallpaper-adopt.service";
        };
      };
    }
  ]
)
