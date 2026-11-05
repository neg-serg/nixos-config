##
# Module: system/wine-apps
# Purpose: Declarative Wine app management. features.wine.apps.<id> declares
#   Windows apps installed into per-app Wine prefixes under
#   ~/.local/share/wineprefixes (bind-mounted to /gamez/main/wineprefixes on
#   trantor). The wineapps CLI (list/install/uninstall/run) consumes the generated
#   registry at /etc/wineapps/apps.json.
#
# Wine stays out of the system closure: `wineapps`, `wine` and `winetricks` are
# on-demand launchers (lib/on-demand-app.nix) that build the matching flake attr
# into ~/.local/state/nix-apps on first call. The desktop entries point at the
# launcher, never at the package store path — otherwise a single declared app
# would drag the whole 1.7 GiB closure back into /run/current-system.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.features.wine or { };
  enabled = cfg.enable or false;
  apps = cfg.apps or { };
  mainUser = config.lib.neg.mainUser;

  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") { inherit pkgs; };

  # The three commands the module provides, each built on first use and
  # GC-rooted under ~/.local/state/nix-apps. `wineapps` embeds wine in its own
  # wrapper, so it only needs the one root; the other two cover manual use.
  wineapps = onDemand {
    name = "wineapps";
    attr = "wineapps";
  };
  wine = onDemand {
    name = "wine";
    attr = "wine";
  };
  winetricks = onDemand {
    name = "winetricks";
    attr = "winetricks";
  };

  registry = builtins.toJSON (
    lib.mapAttrs (name: app: {
      inherit name;
      installer = app.installer;
      installArgs = app.installArgs;
      executable = app.executable;
      prefix = if app.prefix == "" then name else app.prefix;
      arch = app.arch;
      winetricks = app.winetricks;
      comment = app.comment;
    }) apps
  );

  # Apps that get a .desktop launcher (need a main executable)
  desktopApps = lib.filterAttrs (_: app: app.desktop && app.executable != null) apps;

  desktopFiles = pkgs.runCommand "wineapps-desktop" { } (
    ''
      mkdir -p $out/share/applications
    ''
    + lib.concatMapStrings (
      name:
      let
        app = desktopApps.${name};
      in
      ''
        cat > "$out/share/applications/wineapps-${name}.desktop" << 'DESKTOP'
        [Desktop Entry]
        Type=Application
        Name=${if app.comment == "" then name else builtins.replaceStrings [ "\n" ] [ " " ] app.comment}
        Comment=${name} (Windows via Wine)
        Exec=${wineapps}/bin/wineapps run ${name}
        Categories=Utility;
        Terminal=false
        NoDisplay=false
        DESKTOP
      ''
    ) (lib.attrNames desktopApps)
  );
in
{
  config = lib.mkIf enabled {
    # The prefix root is bind-mounted from /gamez/main/wineprefixes, which is
    # created by the pool import as root — hand it to the main user so the
    # wineapps CLI can create per-app prefixes without sudo.
    systemd.tmpfiles.rules = [
      "d /gamez/main/wineprefixes 0755 ${mainUser} ${mainUser} -"
      "z /gamez/main/wineprefixes - ${mainUser} ${mainUser} -"
    ];

    environment.systemPackages = [
      wine # Wine runtime, built on first use (wineapps' wrapper embeds it)
      winetricks # prefix setup helper (verbs: corefonts, vcrun2022, ...), built on first use
      wineapps # declarative app manager (list/install/uninstall/run), built on first use
    ]
    ++ lib.optional (desktopApps != { }) desktopFiles;

    environment.etc."wineapps/apps.json".text = registry + "\n";
  };
}
