##
# Module: system/wine-apps
# Purpose: Declarative Wine app management. features.wine.apps.<id> declares
#   Windows apps installed into per-app Wine prefixes under
#   ~/.local/share/wineprefixes (bind-mounted to /gamez/main/wineprefixes on
#   odin). The wineapps CLI (list/install/uninstall/run) consumes the generated
#   registry at /etc/wineapps/apps.json.
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
        Exec=${pkgs.neg.wineapps}/bin/wineapps run ${name}
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
    environment.systemPackages = [
      pkgs.wineWow64Packages.stable # Open-source implementation of the Windows API
      pkgs.winetricks # Wine prefix setup helper (verbs: corefonts, vcrun2022, ...)
      pkgs.neg.wineapps # declarative Wine app manager (list/install/uninstall/run)
    ]
    ++ lib.optional (desktopApps != { }) desktopFiles;

    environment.etc."wineapps/apps.json".text = registry + "\n";
  };
}
