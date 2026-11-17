##
# Module: media/audio/camillaeq
# Purpose: upstream CamillaEQ — the browser equalizer for CamillaDSP (a Svelte
# client behind a small Fastify server, one loopback origin for both). It is the
# reference app aurora's own `/eq` page was measured against; here it runs as a
# user unit so the full UI is one address and one key away.
#
# The server only serves the UI and its config library — the browser opens the
# CamillaDSP websocket itself from the Connect page — so which daemon the UI
# edits (1234 speakers, 1235 headphones) is a choice in the page, not here.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.media.audio.camillaEq;
  systemdUser = config.lib.neg.systemdUser;
  port = cfg.port;

  camillaeq = lib.getExe pkgs.camillaeq;

  # The UI is a URL: the same entry point serves the Hyprland key and the menu
  # entry, so the port lives in exactly one place.
  camillaeq-ui = pkgs.writeShellApplication {
    name = "camillaeq-ui";
    runtimeInputs = [
      pkgs.curl # wait for the page to answer before opening it
      pkgs.systemd # systemctl --user start, so a stopped unit comes back
      pkgs.xdg-utils # xdg-open: the URL goes to the default browser
    ];
    text = ''
      set -eu
      url="http://127.0.0.1:${toString port}/"
      systemctl --user start camillaeq.service
      i=0
      while [ "$i" -lt 50 ] && ! curl -fsS -o /dev/null "$url"; do
        sleep 0.1
        i=$((i + 1))
      done
      exec xdg-open "$url"
    '';
  };

  desktop = pkgs.runCommand "camillaeq-desktop" { } ''
    install -d $out/share/applications
    cat > $out/share/applications/camillaeq.desktop <<'EOF'
    [Desktop Entry]
    Type=Application
    Name=CamillaEQ
    GenericName=Equalizer
    Comment=Graphical equalizer and spectrum analyzer for CamillaDSP
    Exec=${lib.getExe camillaeq-ui}
    Icon=multimedia-volume-control
    Terminal=false
    Categories=AudioVideo;Audio;
    Keywords=eq;equalizer;camilla;camilladsp;spectrum;
    EOF
  '';
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.camillaeq # the CamillaEQ server: the Svelte UI plus its config library
      camillaeq-ui # start the unit, then open the address in the default browser
      desktop # the same launcher as a menu entry
    ];

    systemd.user.services.camillaeq = systemdUser.mkUserService {
      description = "CamillaEQ — browser equalizer for CamillaDSP";
      presets = [
        "defaultWanted"
        "restartOnFailure"
      ];
      serviceConfig = {
        ExecStart = camillaeq;
        # Loopback only: the server has no authentication, and the browser is on
        # this machine. The websocket default points at the speaker chain; the
        # Connect page can name the headphone one (1235) instead.
        Environment = [
          "NODE_ENV=production"
          "SERVER_HOST=127.0.0.1"
          "SERVER_PORT=${toString port}"
          "CAMILLA_CONTROL_WS_URL=ws://127.0.0.1:1234"
          "LOG_LEVEL=info"
        ];
        RestartSec = "2";
      };
    };
  };
}
