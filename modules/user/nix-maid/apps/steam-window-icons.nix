##
# Module: user/nix-maid/apps/steam-window-icons
# Purpose: Give Steam games an icon and a window class a launcher can match.
#
# Steam writes one entry per library game into
# `~/.local/share/applications/<Game>.desktop` with `Icon=steam_icon_<appid>` and
# no `StartupWMClass`. Neither works out of the box: no icon theme carries a
# `steam_icon_*` name — Steam keeps its art in `appcache/librarycache` — and a
# game window reports the class `steam_app_<appid>`, which no entry matches. So
# the launcher paints all ~84 games blank and the Switch Windows view gives each
# running game the generic icon.
#
# `steam-window-icons` fixes both from data that is already on disk: it renders
# the art Steam downloaded (the 2:3 cover, else the logo, else the store header)
# into `~/.local/share/steam-game-icons/steam_icon_<appid>.png`, then patches
# Steam's own entry to point `Icon=` at that file and to carry
# `StartupWMClass=steam_app_<appid>`. The entry stays Steam's — the game list is
# read from it (`Exec=steam steam://rungameid/<appid>`), so there is no second
# library copy to keep in sync, and Vicinae rescans on the directory change.
#
# The icon cannot live in the theme: `~/.local/share/icons/hicolor` is a
# read-only nix-maid link to the store, and a user theme by the current theme's
# name would shadow the system one instead of extending it — hence the absolute
# `Icon=` path, which the desktop-entry spec allows and Vicinae reads as a file.
#
# A timer re-runs the pass because Steam rewrites its entries when the library
# changes (dropping both keys) and fills the art in lazily.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  guiEnabled = config.lib.neg.enabled "gui";
  systemdUser = config.lib.neg.systemdUser;

  steamWindowIcons = pkgs.writeShellApplication {
    name = "steam-window-icons";
    runtimeInputs = [
      pkgs.coreutils # mktemp/cut/chmod/mv of each generated file
      pkgs.diffutils # cmp: rewrite an entry only when its content changed
      pkgs.gnugrep # the appid and the keys already in Steam's entry
      pkgs.gnused # replace Icon= and add StartupWMClass=
      pkgs.imagemagick # magick: the downloaded cover into a 256x256 PNG
    ];
    text = ''
      set -uo pipefail

      apps="$HOME/.local/share/applications"
      cache="$HOME/.local/share/Steam/appcache/librarycache"
      icons="$HOME/.local/share/steam-game-icons"

      # No Steam or no library yet: nothing to render, and an empty icon
      # directory would only be left behind.
      [ -d "$apps" ] && [ -d "$cache" ] || exit 0
      mkdir -p "$icons"

      for entry in "$apps"/*.desktop; do
        [ -f "$entry" ] || continue
        appid=$(grep -m1 -o 'rungameid/[0-9][0-9]*' "$entry" 2>/dev/null | cut -d/ -f2) || true
        [ -n "''${appid:-}" ] || continue

        # Best art first: the cover is what the game is recognised by, the logo
        # and the store header are the fallbacks for entries Steam has not
        # downloaded a cover for.
        art=""
        for candidate in \
          "$cache/$appid/library_600x900.jpg" \
          "$cache/$appid/logo.png" \
          "$cache/$appid/header.jpg"; do
          if [ -f "$candidate" ]; then
            art=$candidate
            break
          fi
        done

        icon=steam
        png="$icons/steam_icon_$appid.png"
        if [ -n "$art" ] && { [ ! -f "$png" ] || [ "$art" -nt "$png" ]; }; then
          tmp=$(mktemp "$png.XXXXXX")
          # Fit, never crop: the cover is 2:3 and its middle is the artwork, so
          # transparent padding keeps the whole picture recognisable.
          if magick "$art" -resize 256x256 -background none -gravity center \
              -extent 256x256 -strip "PNG:$tmp" 2>/dev/null; then
            # mktemp hands back 0600; an icon is read by every process that
            # paints the entry, so it keeps the usual 0644.
            chmod 0644 "$tmp"
            mv -f "$tmp" "$png"
          else
            rm -f "$tmp"
          fi
        fi
        [ -f "$png" ] && icon=$png

        tmp=$(mktemp "$entry.XXXXXX")
        if grep -q '^StartupWMClass=' "$entry"; then
          sed -E \
            -e "s|^Icon=.*|Icon=$icon|" \
            -e "s|^StartupWMClass=.*|StartupWMClass=steam_app_$appid|" \
            "$entry" > "$tmp"
        elif grep -q '^Icon=' "$entry"; then
          sed -E \
            -e "s|^Icon=.*|Icon=$icon|" \
            -e "/^Icon=/a StartupWMClass=steam_app_$appid" \
            "$entry" > "$tmp"
        else
          { cat "$entry"; printf 'Icon=%s\nStartupWMClass=steam_app_%s\n' "$icon" "$appid"; } > "$tmp"
        fi

        # Steam rewrites these files on every library change; an unchanged file
        # must not be touched, or the launcher's directory watcher would rescan
        # the whole app list every five minutes for nothing.
        if cmp -s "$tmp" "$entry"; then
          rm -f "$tmp"
        else
          chmod --reference="$entry" "$tmp" 2>/dev/null || true
          mv -f "$tmp" "$entry"
        fi
      done
    '';
  };
in
{
  config = lib.mkIf guiEnabled {
    systemd.user.services.steam-window-icons = systemdUser.mkUserService {
      presets = [ "oneshot" ];
      description = "Render Steam game icons and tie game windows to them";
      serviceConfig.ExecStart = lib.getExe steamWindowIcons;
    };

    systemd.user.timers.steam-window-icons = {
      description = "Timer: refresh Steam game icons after library or art changes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnStartupSec = "30s";
        OnUnitActiveSec = "5min";
        Unit = "steam-window-icons.service";
      };
    };
  };
}
