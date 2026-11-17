##
# Module: media/audio/headphones-web
# Purpose: the headphone catalogue's loopback web page — the model list, the
# picker and the equalizer panel at `/eq` (camillaEQ's tokens and behaviour in
# aurora's own page, docs/plan-eq-panel.md in ~/src/aurora). The page is a
# server (`headphones-web`, shipped by aurora-tools), so until this unit existed
# it was only a binary on PATH and nothing on the desktop could open it.
#
# The unit owns the port; `aurora-eq` is what the key and the menu entry run:
# it starts the unit (normally already up — the page is wanted by default),
# waits for the port to answer and hands the URL to the default browser.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.media.audio.headphonesWeb;
  systemdUser = config.lib.neg.systemdUser;
  port = cfg.port;

  # `headphones-web` takes `--bind ADDR:PORT` and refuses anything that is not a
  # loopback address; the unit passes the one this module owns.
  headphonesWeb = lib.getExe' pkgs.neg.aurora-tools "headphones-web";

  # The panel is a URL, not a window: the launcher is the one entry point both
  # the Hyprland key and the .desktop file use, so neither has to know the port.
  aurora-eq = pkgs.writeShellApplication {
    name = "aurora-eq";
    runtimeInputs = [
      pkgs.curl # wait for the page to answer before opening it
      pkgs.systemd # systemctl --user start, so a stopped unit comes back
      pkgs.xdg-utils # xdg-open: the URL goes to the default browser
    ];
    text = ''
      set -eu
      url="http://127.0.0.1:${toString port}/eq"
      # Idempotent: the unit is wanted by default.target, this only covers the
      # case where it was stopped or the machine is still settling.
      systemctl --user start headphones-web.service
      i=0
      while [ "$i" -lt 50 ] && ! curl -fsS -o /dev/null "$url"; do
        sleep 0.1
        i=$((i + 1))
      done
      exec xdg-open "$url"
    '';
  };

  desktop = pkgs.runCommand "aurora-eq-desktop" { } ''
    install -d $out/share/applications
    cat > $out/share/applications/aurora-eq.desktop <<'EOF'
    [Desktop Entry]
    Type=Application
    Name=Aurora EQ (headphones)
    GenericName=Equalizer
    Comment=The live headphone chain's bands, the model catalogue and the /eq panel
    Exec=${lib.getExe aurora-eq}
    Icon=multimedia-volume-control
    Terminal=false
    Categories=AudioVideo;Audio;
    Keywords=eq;equalizer;camilla;camilladsp;headphones;
    EOF
  '';
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      aurora-eq # the /eq page's launcher: start the unit, open the address
      desktop # the same launcher as a menu entry
    ];

    systemd.user.services.headphones-web = systemdUser.mkUserService {
      description = "Headphone catalogue web page (models, picker and the /eq equalizer panel)";
      presets = [
        "defaultWanted"
        "restartOnFailure"
      ];
      serviceConfig = {
        ExecStart = "${headphonesWeb} --bind 127.0.0.1:${toString port}";
        RestartSec = "2";
      };
    };
  };
}
