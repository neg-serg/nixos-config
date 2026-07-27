{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
let
  winappsCfg = config.features.apps.winapps or { };
  enabled = winappsCfg.enable or false;
  vmProfile = (config.profiles.vm or { enable = false; }).enable;

  # App configs from local files
  appDir = ../../files/winapps/apps;

  parseAppInfo = name:
    let
      raw = builtins.readFile "${appDir}/${name}/info";
      getVar = var: let
        matches = builtins.match ".*${var}=\"([^\"]*)\".*" raw;
      in if matches == null then "" else builtins.elemAt matches 0;
    in {
      name = getVar "NAME";
      fullName = getVar "FULL_NAME";
      executable = getVar "WIN_EXECUTABLE";
      categories = getVar "CATEGORIES";
      mimeTypes = getVar "MIME_TYPES";
    };

  # Desktop entries for selected apps
  desktopApps = winappsCfg.desktopApps or [];
  desktopFiles = pkgs.runCommand "winapps-desktop" {} (
    ''
      mkdir -p $out/share/applications
    ''
    + lib.concatMapStrings (appName:
      let app = parseAppInfo appName; in ''
        cat > "$out/share/applications/winapps-${appName}.desktop" << 'DESKTOP'
        [Desktop Entry]
        Type=Application
        Name=${app.name}
        GenericName=${app.fullName}
        Comment=${app.fullName} (Windows via RDP)
        Icon=${appDir}/${appName}/icon.svg
        Exec=${pkgs.writeShellScriptBin "winapps-${appName}" ''
          exec winapps ${appName} "''${1:-}"
        ''}/bin/winapps-${appName} %F
        Categories=${builtins.replaceStrings ["WinApps;"] [""] (if app.categories == "" then "Office" else app.categories)}
        MimeType=${app.mimeTypes}
        Terminal=false
        NoDisplay=false
        DESKTOP
      ''
    ) desktopApps
  );

in
{
  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = !vmProfile;
        message = "features.apps.winapps.enable is intended for bare-metal hosts; disable profiles.vm.enable when using WinApps.";
      }
      {
        assertion = config.virtualisation.libvirtd.enable or false;
        message = "features.apps.winapps.enable requires KVM/libvirt (virtualisation.libvirtd.enable = true).";
      }
    ];

    environment.systemPackages = lib.mkAfter (
      [
        (pkgs.writeShellScriptBin "winapps" ''
          set -euo pipefail

          if [ -f "$HOME/.config/winapps/winapps.conf" ]; then
            . "$HOME/.config/winapps/winapps.conf"
          elif [ -f /etc/winapps/winapps.conf ]; then
            . /etc/winapps/winapps.conf
          fi

          APPS_DIR="${appDir}"
          RDP_IP="''${RDP_IP:-127.0.0.1}"
          RDP_USER="''${RDP_USER:-neg}"
          RDP_DOMAIN="''${RDP_DOMAIN:-}"
          RDP_SCALE="''${RDP_SCALE:-100}"
          RDP_FLAGS="''${RDP_FLAGS:-/network:auto /sound:auto /microphone:auto /gfx:avc444 /bpp:32}"
          RDP_PASS="''${RDP_PASS:-}"

          if [ $# -eq 0 ]; then
            echo "Usage: winapps <app> [file]"
            echo "Available: $(${pkgs.coreutils}/bin/ls "$APPS_DIR" | ${pkgs.coreutils}/bin/sort)"
            exit 1
          fi

          APP="$1"; shift; FILE="''${1:-}"
          if [ ! -f "$APPS_DIR/$APP/info" ]; then
            echo "Unknown app: $APP" >&2; exit 1
          fi

          . "$APPS_DIR/$APP/info"
          ICON="$APPS_DIR/$APP/icon.svg"

          if [ -n "$FILE" ]; then
            WIN_FILE=$(echo "$FILE" | ${pkgs.gnused}/bin/sed 's|'"$HOME"'|\\\\tsclient\\home|;s|/|\\|g;s|\\|\\\\|g')
            exec ${pkgs.freerdp}/bin/xfreerdp \
              $RDP_FLAGS /d:"$RDP_DOMAIN" /u:"$RDP_USER" /p:"$RDP_PASS" \
              /v:"$RDP_IP" +auto-reconnect +clipboard +home-drive -wallpaper \
              /scale:"$RDP_SCALE" /dynamic-resolution \
              /wm-class:"$FULL_NAME" /app:"$WIN_EXECUTABLE" \
              /app-icon:"$ICON" /app-cmd:"\"$WIN_FILE\""
          else
            exec ${pkgs.freerdp}/bin/xfreerdp \
              $RDP_FLAGS /d:"$RDP_DOMAIN" /u:"$RDP_USER" /p:"$RDP_PASS" \
              /v:"$RDP_IP" +auto-reconnect +clipboard +home-drive -wallpaper \
              /scale:"$RDP_SCALE" /dynamic-resolution \
              /wm-class:"$FULL_NAME" /app:"$WIN_EXECUTABLE" \
              /app-icon:"$ICON"
          fi
        '')
        pkgs.freerdp
        pkgs.qemu_kvm
        pkgs.virt-manager
      ] ++ lib.optional (desktopApps != []) desktopFiles
    );
    environment.etc."winapps/winapps.conf".text = ''
      # WinApps configuration (default)
      # Override in ~/.config/winapps/winapps.conf
      RDP_USER="neg"
      RDP_PASS="neg"
      RDP_DOMAIN=""
      RDP_IP="127.0.0.1"
      RDP_SCALE=100
      MULTIMON="false"
      DEBUG="false"
      RDP_FLAGS="/network:auto /sound:auto /microphone:auto /gfx:avc444 /bpp:32"
    '';
  };
}
