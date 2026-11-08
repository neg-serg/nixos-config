# PortProton mirror patch
#
# PortProton (Flatpak `ru.linux_gaming.PortProton`, declared in
# modules/flatpak) does not ship its launcher: on first run it downloads the
# PortWINE scripts from its own mirrors and rewrites them on update. Two of
# those hosts are unreachable from this network:
#
#   - git.linux-gaming.ru — no answer at all (direct and through the SOCKS
#     proxy). The wrapper calls curl without a timeout, so the first launch
#     waits the full 300 s before it falls through to the GitHub tarball, and
#     start.sh later aborts the game launch with "failed to fetch metadata"
#     because the wine-metadata JSON lives on the same dead host.
#   - ppdb.linux-gaming.ru — the per-game settings lookup, equally dead. There
#     is no mirror for that API, so games must be set up by hand in the GUI
#     (Prefix / WINE dropdowns); the unit below does not try to fix it.
#
# The wine-metadata JSON is mirrored by the same author on GitHub, so the patch
# repoints that one URL and nothing else. It is idempotent on purpose: a write
# would re-trigger the path unit, so the script exits without touching the file
# when the URL is already correct (or when upstream changed the string).
#
# Coverage:
#   - the path unit fires when PortProton rewrites functions_helper mid-session
#     (self-update, --repair), i.e. right after the bootstrap tarball is
#     unpacked;
#   - the login oneshot covers a scripts directory that was rewritten while
#     the session was down.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.games or { };

  helperRel = ".var/app/ru.linux_gaming.PortProton/data/scripts/functions_helper";

  deadUrl = "https://git.linux-gaming.ru/Boria138/PortProton-Wine-Metadata/raw/branch/main/wine_metadata.json";
  liveUrl = "https://raw.githubusercontent.com/Boria138/PortProton-Wine-Metadata/main/wine_metadata.json";

  mirrorPatch = pkgs.writeShellApplication {
    name = "portproton-mirror-patch";
    runtimeInputs = [
      pkgs.coreutils # cp
      pkgs.gnugrep # grep -qF
      pkgs.gnused # sed -i
    ];
    text = ''
      helper="''${PORT_PROTON_HELPER:-$HOME/${helperRel}}"
      dead="${deadUrl}"
      live="${liveUrl}"

      if [ ! -f "$helper" ]; then
        echo "no PortProton scripts yet ($helper) — nothing to patch"
        exit 0
      fi
      if ! grep -qF "$dead" "$helper"; then
        echo "metadata URL already repointed (or upstream changed) — nothing to do"
        exit 0
      fi
      cp -n "$helper" "$helper.bak-urlfix" 2>/dev/null || true
      sed -i "s|$dead|$live|g" "$helper"
      echo "repointed the wine-metadata URL at the GitHub mirror"
    '';
  };
in
lib.mkIf cfg.enable {
  systemd.user.services.portproton-mirror-patch = config.lib.neg.systemdUser.mkUserService {
    presets = [
      "oneshot"
    ];
    description = "Repoint PortProton's dead wine-metadata mirror at GitHub";
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = lib.getExe mirrorPatch;
    };
  };

  # PortProton writes the scripts itself (first run, update, --repair); the
  # path unit re-applies the patch each time the file is (re)written.
  systemd.user.paths.portproton-mirror-patch = {
    description = "Watch PortProton's functions_helper for rewrites";
    wantedBy = [ "graphical-session.target" ];
    pathConfig = {
      PathChanged = "%h/${helperRel}";
      Unit = "portproton-mirror-patch.service";
    };
  };
}
