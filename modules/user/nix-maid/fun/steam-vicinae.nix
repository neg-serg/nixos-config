{ pkgs, lib, config, ... }:
let
  cfgGames = config.profiles.games or { };
  cfgVicinae = config.features.gui.vicinae or { };
  enabled = cfgGames.enable && cfgVicinae.enable;

  steamGameDesktopGen = pkgs.writeShellScript "steam-vicinae-desktop-gen" ''
    set -euo pipefail

    STEAM_HOME="$HOME/.local/share/Steam"
    OUTPUT_DIR="$HOME/.local/share/applications"
    MARKER_DIR="$HOME/.local/share/steam-vicinae"

    mkdir -p "$OUTPUT_DIR" "$MARKER_DIR"

    # Collect all steamapps directories (primary + libraryfolders.vdf)
    STEAMAPPS_DIRS=()
    if [ -d "$STEAM_HOME/steamapps" ]; then
      STEAMAPPS_DIRS+=("$STEAM_HOME/steamapps")
    fi

    # Parse libraryfolders.vdf for additional Steam library paths
    LFF="$STEAM_HOME/steamapps/libraryfolders.vdf"
    if [ -f "$LFF" ]; then
      while IFS= read -r line; do
        path="$(echo "$line" | sed -n 's/.*"path"[[:space:]]*"\(.*\)"/\1/p')"
        if [ -n "$path" ] && [ -d "$path/steamapps" ]; then
          STEAMAPPS_DIRS+=("$path/steamapps")
        fi
      done < "$LFF"
    fi

    # Track which appids exist this run
    FOUND_APPIDS=""

    for apps_dir in "''${STEAMAPPS_DIRS[@]}"; do
      [ -d "$apps_dir" ] || continue
      for manifest in "$apps_dir"/appmanifest_*.acf; do
        [ -f "$manifest" ] || continue

        appid="$(sed -n 's/^[[:space:]]*"appid"[[:space:]]*"\([0-9]*\)"/\1/p' "$manifest" | head -1)"
        name="$(sed -n 's/^[[:space:]]*"name"[[:space:]]*"\(.*\)"/\1/p' "$manifest" | head -1)"

        [ -n "$appid" ] || continue
        [ -n "$name" ] || continue

        FOUND_APPIDS="$FOUND_APPIDS $appid"

        desktop="$OUTPUT_DIR/steam_app_$appid.desktop"
        # Escape double quotes and strip control chars for .desktop format
        name_escaped="$(echo "$name" | sed 's/"/\\"/g; s/[[:cntrl:]]//g')"

        cat > "$desktop" << DESKTOPEOF
[Desktop Entry]
Version=1.0
Type=Application
Name=${name_escaped}
Exec=steam steam://rungameid/${appid}
Icon=steam_icon_${appid}
Categories=Game;
StartupWMClass=steam_app_${appid}
DESKTOPEOF

        chmod 644 "$desktop"
        touch "$MARKER_DIR/$appid"
      done
    done

    # Clean up .desktop files for games no longer installed
    for marker in "$MARKER_DIR"/*; do
      [ -f "$marker" ] || continue
      mid="$(basename "$marker")"
      found=0
      for apps_dir in "''${STEAMAPPS_DIRS[@]}"; do
        if [ -f "$apps_dir/appmanifest_$mid.acf" ]; then
          found=1
          break
        fi
      done
      if [ "$found" = "0" ]; then
        rm -f "$OUTPUT_DIR/steam_app_$mid.desktop"
        rm -f "$marker"
      fi
    done

    # Notify desktop environment about new .desktop files
    if command -v update-desktop-database >/dev/null 2>&1; then
      update-desktop-database "$OUTPUT_DIR" 2>/dev/null || true
    fi

    # Restart vicinae so it picks up the new entries
    if systemctl --user is-active vicinae.service >/dev/null 2>&1; then
      systemctl --user try-restart vicinae.service 2>/dev/null || true
    fi
  '';
in
{
  config = lib.mkIf enabled {
    systemd.user.services.steam-vicinae-desktop = {
      Unit = {
        Description = "Generate .desktop entries for Steam games in vicinae";
        After = [ "network.target" "vicinae.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = steamGameDesktopGen;
        RemainAfterExit = false;
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    systemd.user.timers.steam-vicinae-desktop = {
      Unit = {
        Description = "Daily refresh Steam game .desktop entries for vicinae";
      };
      Timer = {
        OnCalendar = "daily";
        Persistent = true;
      };
      Install = {
        WantedBy = [ "timers.target" ];
      };
    };
  };
}
